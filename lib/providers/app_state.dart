import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/notification_rules.dart';
import '../models/ride_log.dart';
import '../models/station.dart';
import '../models/train_trip.dart';
import '../services/njt_api_service.dart';
import '../services/notification_service.dart';
import '../theme/anime_theme.dart';

class AppState extends ChangeNotifier {
  static String appVersion = '1.0.5';
  static int appBuildNumber = 6;
  static bool _hasCheckedUpdateThisSession = false;
  static const Duration activeRideStalenessThreshold = Duration(minutes: 20);

  /// Computes the scheduled/estimated Eastern arrival [DateTime] for [trip].
  static DateTime computeTripArrivalEastern(
    TrainTrip trip, {
    DateTime? referenceEasternNow,
  }) {
    final refEast = referenceEasternNow ?? NjtApiService.easternNow();
    final depEast = trip.departureDateTime ??
        NjtApiService.parseNjtTime(trip.departureTime, refEast) ??
        refEast;

    final stops = trip.commuteStops;
    final arrRaw = trip.arrivalTime.trim().isNotEmpty
        ? trip.arrivalTime
        : (stops.isNotEmpty ? stops.last.estimatedTime : '');
    DateTime? arrEast = NjtApiService.parseNjtTime(arrRaw, depEast);
    if (arrEast != null) {
      if (arrEast.isBefore(depEast)) {
        arrEast = arrEast.add(const Duration(days: 1));
      }
      return arrEast;
    }
    return depEast.add(Duration(minutes: trip.durationMinutes));
  }

  /// Returns `true` when [nowEastern] is 20 minutes or more past [arrivalEastern].
  static bool isTripArrivalStale({
    required DateTime arrivalEastern,
    required DateTime nowEastern,
    Duration maxStaleness = activeRideStalenessThreshold,
  }) {
    return nowEastern.difference(arrivalEastern) >= maxStaleness;
  }

  // Fast 1-second Track Watch polling burst window (11m down to 9m before departure)
  static const int fastTrackWatchStartSeconds = 11 * 60; // 660s before departure
  static const int fastTrackWatchEndSeconds = 9 * 60; // 540s guardrail for On Time trains
  static const Duration fastTrackWatchMaxBurstDuration = Duration(minutes: 8);
  static const Duration postArrivalGuardGracePeriod = Duration(minutes: 2);

  /// Returns `true` when a train's DepartureVision status indicates a delay,
  /// hold, standby, or other non-routine condition outside normal "On Time".
  static bool isTrainNonRoutineCondition(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty ||
        s == 'on time' ||
        s == 'ontime' ||
        s == 'scheduled' ||
        s == 'track tba') {
      return false;
    }
    if (RegExp(r'^in\s+\d+\s*min').hasMatch(s)) {
      return false;
    }
    if (s.contains('cancel')) {
      return false;
    }
    return true;
  }

  /// Evaluates whether 1-second lightweight Track Watch polling should be active.
  ///
  /// - Activates at the **11-minute mark** before departure (`<= 660s`).
  /// - Stops immediately once a track is posted, the train departs, or is cancelled.
  /// - For normal ("On Time") trains, stops at the **9-minute guardrail** (`< 540s`).
  /// - For delayed or non-routine conditions, extends past the 9-minute mark
  ///   (up to [fastTrackWatchMaxBurstDuration] continuous burst or 15m past scheduled
  ///   departure) so late track postings are still caught accurately.
  static bool shouldUseFastTrackWatchPolling({
    required TrainTrip? watchedTrip,
    required DateTime nowEastern,
    DateTime? fastBurstStartedAt,
    DateTime? rateLimitBackoffUntil,
  }) {
    if (watchedTrip == null) return false;
    if (watchedTrip.hasTrack) return false;
    if (watchedTrip.hasDepartedOrigin(nowEastern)) return false;
    if (watchedTrip.status.toLowerCase().contains('cancel')) return false;
    if (rateLimitBackoffUntil != null &&
        nowEastern.isBefore(rateLimitBackoffUntil)) {
      return false;
    }

    final depEast = watchedTrip.departureDateTime ??
        NjtApiService.parseNjtTime(watchedTrip.departureTime, nowEastern);
    if (depEast == null) return false;

    final secondsUntilDep = depEast.difference(nowEastern).inSeconds;
    if (secondsUntilDep > fastTrackWatchStartSeconds) {
      return false;
    }

    // Standard 11-minute to 9-minute window for On Time trains
    if (secondsUntilDep >= fastTrackWatchEndSeconds) {
      return true;
    }

    // Exception: Delayed or other non-"On Time" conditions extend past 9-minute guardrail
    // with a hard 8-minute continuous burst cap for battery & API safety.
    if (isTrainNonRoutineCondition(watchedTrip.status) &&
        secondsUntilDep >= -900) {
      if (fastBurstStartedAt == null) return true;
      return nowEastern.difference(fastBurstStartedAt) <=
          fastTrackWatchMaxBurstDuration;
    }

    return false;
  }

  static const MethodChannel _safBackupChannel =
      MethodChannel('com.my5top.commute/saf_backup');

  bool _initialized = false;
  bool get initialized => _initialized;

  late Box _settingsBox;

  // Theme & Anime Aesthetic State
  String _animeThemeStyle = 'mygo'; // 'mygo' or 'sakura'
  bool _isDarkMode = true;
  bool _isPureBlackDarkMode = false;
  double _textScaleFactor = 1.0;
  bool _devTestMode = false;

  // Commute Stations State (Defaults: NY Penn = Work, Metropark = Home)
  String _workStationCode = 'NY';
  String _homeStationCode = 'MP';
  List<String> _starredStationCodes = ['NY', 'MP', 'NP', 'SE', 'RA'];
  String _originStationCode = 'NY';
  String _destinationStationCode = 'MP';

  // NJ Transit API Optional Credentials
  String _njtUsername = '';
  String _njtPassword = '';
  String _cachedNjtToken = '';
  DateTime? _cachedNjtTokenTime;

  // Upcoming Trains & Track Watcher + Smart 5s / 1s Burst Polling
  List<TrainTrip> _upcomingTrains = [];
  bool _isLoadingTrains = false;
  DateTime? _lastScheduleRefresh;
  String? _watchedTrainId;
  DateTime? _watchStartedAt;
  Timer? _schedulePollTimer;
  bool _isAppFocused = true;
  int _pollCountdownSeconds = 5;
  bool _isPollInFlight = false;
  bool _isFastTrackPolling = false;
  bool _isFastTrackPollInFlight = false;
  DateTime? _fastTrackBurstStartedAt;
  DateTime? _trackWatchRateLimitUntil;
  int _fastTrackFullSyncCounter = 0;
  int _refreshGeneration = 0;
  final Set<String> _simulatedTrackTrainIds = {};

  // Active Ride & Hybrid GPS + API State
  TrainTrip? _activeRideTrain;
  DateTime? _activeRideArrivalEastern;
  DateTime? _activeRideBoardedAt;
  int _rideSceneSeed = 0;
  int _rideVariationIndex = 0;
  int _currentStopIndex = 0; // Index within activeRideTrain.commuteStops
  Position? _currentGpsPosition;
  double? _distanceToNextStopMeters;
  double? _distanceToDestinationMeters;
  double _segmentProgress = 0.0; // 0.0..1.0 between currentStop and nextStop
  String _lastTrackingSignalSource = 'Schedule + GPS Ready';
  DateTime _lastRideUpdateDateTime = DateTime.now();
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _simulationTimer;
  Timer? _postArrivalGuardStopTimer;
  bool _isAutoSimulating = false;
  final Set<int> _notifiedStopIndices = {};
  bool _hasFiredWakeUpAlarm = false;

  // Customizable Notification Rules
  NotificationRules _notificationRules = const NotificationRules();

  // Commute Ride History Logs
  List<RideLog> _rideLogs = [];

  AppState() {
    _init();
  }

  AppState._uninitialized();

  @visibleForTesting
  static Future<AppState> createForTesting({
    required Box settingsBox,
    List<TrainTrip>? initialTrains,
  }) async {
    final state = AppState._uninitialized();
    _hasCheckedUpdateThisSession = true;
    state._settingsBox = settingsBox;
    await state._loadFromBox();
    if (initialTrains != null) {
      state._upcomingTrains = initialTrains;
      state._lastScheduleRefresh = DateTime.now();
    }
    state._initialized = true;
    return state;
  }

  // Getters
  String get animeThemeStyle => _animeThemeStyle;
  bool get isDarkMode => _isDarkMode;
  bool get isPureBlackDarkMode => _isPureBlackDarkMode;
  double get textScaleFactor => _textScaleFactor;
  bool get devTestMode => _devTestMode;

  AnimeThemePalette get palette => AnimeThemePalette.resolve(
        themeStyle: _animeThemeStyle,
        isDark: _isDarkMode,
        isAmoled: _isPureBlackDarkMode,
      );

  String get workStationCode => _workStationCode;
  String get homeStationCode => _homeStationCode;
  Station get workStation => getStationByCode(_workStationCode);
  Station get homeStation => getStationByCode(_homeStationCode);
  List<String> get starredStationCodes => _starredStationCodes;

  String get originStationCode => _originStationCode;
  String get destinationStationCode => _destinationStationCode;
  Station get originStation => getStationByCode(_originStationCode);
  Station get destinationStation => getStationByCode(_destinationStationCode);

  String get njtUsername => _njtUsername;
  String get njtPassword => _njtPassword;
  bool get hasNjtCredentials =>
      _njtUsername.trim().isNotEmpty && _njtPassword.trim().isNotEmpty;
  bool get hasActiveNjtToken => _cachedNjtToken.trim().isNotEmpty;

  List<TrainTrip> get upcomingTrains => _upcomingTrains;
  List<TrainTrip> get upcomingScheduleTrains =>
      _upcomingTrains.where((t) => !t.isRecentPastDeparture).toList();
  List<TrainTrip> get recentDepartedTrains =>
      _upcomingTrains.where((t) => t.isRecentPastDeparture).toList();
  String get scheduleDataSource => _upcomingTrains.isNotEmpty
      ? _upcomingTrains.first.dataSource
      : 'Polling NJT Live...';

  bool get isLoadingTrains => _isLoadingTrains;
  DateTime? get lastScheduleRefresh => _lastScheduleRefresh;
  String? get watchedTrainId => _watchedTrainId;
  TrainTrip? get watchedTrain => _watchedTrainId == null
      ? null
      : _upcomingTrains.where((t) => t.trainId == _watchedTrainId).firstOrNull;
  bool get isAppFocused => _isAppFocused;
  int get pollCountdownSeconds => _pollCountdownSeconds;
  bool get isFastTrackPolling => _isFastTrackPolling;
  bool get isPollingActive =>
      _isAppFocused || _watchedTrainId != null || _activeRideTrain != null;
  bool get isBackgroundGuardActive =>
      _activeRideTrain != null || _watchedTrainId != null;

  TrainTrip? get activeRideTrain => _activeRideTrain;
  DateTime? get activeRideArrivalEastern => _activeRideArrivalEastern;
  int get rideSceneSeed => _rideSceneSeed;
  int get rideVariationIndex => _rideVariationIndex;
  bool get isRiding => _activeRideTrain != null;
  int get currentStopIndex => _currentStopIndex;
  Position? get currentGpsPosition => _currentGpsPosition;
  double? get distanceToNextStopMeters => _distanceToNextStopMeters;
  double? get distanceToDestinationMeters => _distanceToDestinationMeters;
  double get segmentProgress => _segmentProgress;
  String get lastTrackingSignalSource => _lastTrackingSignalSource;
  DateTime get lastRideUpdateDateTime => _lastRideUpdateDateTime;
  bool get isAutoSimulating => _isAutoSimulating;

  NotificationRules get notificationRules => _notificationRules;
  List<RideLog> get rideLogs => _rideLogs;

  List<TrainStop> get activeCommuteStops =>
      _activeRideTrain?.commuteStops ?? const [];

  int get stopsRemaining {
    final stops = activeCommuteStops;
    if (stops.isEmpty) return 0;
    final rem = (stops.length - 1) - _currentStopIndex;
    return rem < 0 ? 0 : rem;
  }

  TrainStop? get currentOrLastPassedStop {
    final stops = activeCommuteStops;
    if (stops.isEmpty) return null;
    final idx = _currentStopIndex.clamp(0, stops.length - 1);
    return stops[idx];
  }

  TrainStop? get nextUpcomingStop {
    final stops = activeCommuteStops;
    if (stops.isEmpty) return null;
    final nextIdx = _currentStopIndex + 1;
    if (nextIdx >= stops.length) return stops.last;
    return stops[nextIdx];
  }

  Future<void> _init() async {
    await Hive.initFlutter();
    _settingsBox = await Hive.openBox('my5top_settings');
    await _loadFromBox();
    await syncFromBackgroundGuard();
    _initialized = true;
    notifyListeners();

    await NotificationService.requestPermission();
    if (_activeRideTrain != null) {
      await _startGpsStream();
      await _updateOngoingNotification();
      await _syncBackgroundGuard();
    } else {
      await NotificationService.cancelRideProgress();
      await NotificationService.stopBackgroundGuard();
    }
    await refreshSchedules();
    _startPeriodicSchedulePoll();
    _initLastKnownGps();
  }

  Future<void> _loadFromBox() async {
    _animeThemeStyle =
        _settingsBox.get('anime_theme_style', defaultValue: 'mygo') as String;
    _isDarkMode = _settingsBox.get('is_dark_mode', defaultValue: true) as bool;
    _isPureBlackDarkMode =
        _settingsBox.get('pure_black_dark_mode', defaultValue: false) as bool;
    _textScaleFactor =
        (_settingsBox.get('text_scale_factor', defaultValue: 1.0) as num)
            .toDouble();
    _devTestMode =
        _settingsBox.get('dev_test_mode', defaultValue: false) as bool;

    _workStationCode =
        _settingsBox.get('work_station_code', defaultValue: 'NY') as String;
    _homeStationCode =
        _settingsBox.get('home_station_code', defaultValue: 'MP') as String;

    final rawStarred = _settingsBox.get('starred_station_codes');
    if (rawStarred is List) {
      _starredStationCodes = rawStarred.map((e) => e.toString()).toList();
    } else {
      _starredStationCodes = ['NY', 'MP', 'NP', 'SE', 'RA'];
    }

    // Smart default commute direction based on time of day:
    // Morning (before 12 PM): Home (Metropark) -> Work (NY Penn)
    // Afternoon/Evening: Work (NY Penn) -> Home (Metropark)
    final savedOrig = _settingsBox.get('origin_station_code') as String?;
    final savedDest = _settingsBox.get('destination_station_code') as String?;
    if (savedOrig != null && savedDest != null && savedOrig != savedDest) {
      _originStationCode = savedOrig;
      _destinationStationCode = savedDest;
    } else {
      final hour = DateTime.now().hour;
      if (hour >= 4 && hour < 12) {
        _originStationCode = _homeStationCode;
        _destinationStationCode = _workStationCode;
      } else {
        _originStationCode = _workStationCode;
        _destinationStationCode = _homeStationCode;
      }
    }

    _njtUsername =
        _settingsBox.get('njt_username', defaultValue: '') as String;
    _njtPassword =
        _settingsBox.get('njt_password', defaultValue: '') as String;
    _cachedNjtToken =
        _settingsBox.get('cached_njt_token', defaultValue: '') as String;
    final tokenTimeStr = _settingsBox.get('cached_njt_token_time') as String?;
    if (tokenTimeStr != null) {
      _cachedNjtTokenTime = DateTime.tryParse(tokenTimeStr);
    }

    final rawRules = _settingsBox.get('notification_rules');
    if (rawRules is Map) {
      _notificationRules =
          NotificationRules.fromJson(Map<String, dynamic>.from(rawRules));
    }

    final rawLogs = _settingsBox.get('ride_logs');
    if (rawLogs is List) {
      _rideLogs = rawLogs
          .whereType<Map>()
          .map((m) => RideLog.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    final rawRide = _settingsBox.get('active_ride_state');
    if (rawRide is Map) {
      try {
        final rideMap = Map<String, dynamic>.from(rawRide);
        final rawTrip = rideMap['trip'];
        if (rawTrip is Map) {
          final trip = TrainTrip.fromJson(Map<String, dynamic>.from(rawTrip));
          final nowEast = NjtApiService.easternNow();
          final arrEast = DateTime.tryParse(
                rideMap['arrivalEasternIso']?.toString() ?? '',
              ) ??
              computeTripArrivalEastern(trip, referenceEasternNow: nowEast);
          final boardedAt = DateTime.tryParse(
                rideMap['boardedAtIso']?.toString() ?? '',
              ) ??
              DateTime.now().subtract(const Duration(minutes: 30));

          if (isTripArrivalStale(
            arrivalEastern: arrEast,
            nowEastern: nowEast,
          )) {
            // Tracked train arrival time is >= 20 min stale: archive log & open to main train table
            final origSt = getStationByCode(trip.originCode);
            final destSt = getStationByCode(trip.destinationCode);
            final log = RideLog(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              trainId: trip.trainId,
              originCode: trip.originCode,
              originName: origSt.shortName,
              destinationCode: trip.destinationCode,
              destinationName: destSt.shortName,
              track: trip.track,
              boardedAt: boardedAt,
              arrivedAt: DateTime.now(),
              totalStops: trip.totalStopCount,
              statusSummary: 'Arrived (${trip.arrivalTime})',
            );
            _rideLogs.insert(0, log);
            if (_rideLogs.length > 50) {
              _rideLogs = _rideLogs.sublist(0, 50);
            }
            await _settingsBox.put(
              'ride_logs',
              _rideLogs.map((e) => e.toJson()).toList(),
            );
            await _settingsBox.delete('active_ride_state');
            _activeRideTrain = null;
          } else {
            // Active ride is still fresh (< 20 min past arrival): restore full tracking state!
            _activeRideTrain = trip;
            _activeRideArrivalEastern = arrEast;
            _activeRideBoardedAt = boardedAt;
            _originStationCode = trip.originCode;
            _destinationStationCode = trip.destinationCode;

            final stops = trip.commuteStops;
            final savedIdx =
                (rideMap['currentStopIndex'] as num?)?.toInt() ?? 0;
            _currentStopIndex = stops.isEmpty
                ? 0
                : savedIdx.clamp(0, stops.length - 1);
            _segmentProgress =
                ((rideMap['segmentProgress'] as num?)?.toDouble() ?? 0.0)
                    .clamp(0.0, 1.0);

            _notifiedStopIndices.clear();
            final rawNotified = rideMap['notifiedStopIndices'];
            if (rawNotified is List) {
              for (final item in rawNotified) {
                if (item is num) _notifiedStopIndices.add(item.toInt());
              }
            }
            _hasFiredWakeUpAlarm = rideMap['hasFiredWakeUpAlarm'] == true;
            _lastTrackingSignalSource =
                (rideMap['lastTrackingSignalSource'] ?? 'Restored Active Ride')
                    .toString();
            _rideSceneSeed = (rideMap['rideSceneSeed'] as num?)?.toInt() ??
                math.Random().nextInt(1 << 20);
            _rideVariationIndex =
                ((rideMap['rideVariationIndex'] as num?)?.toInt() ?? 0) % 5;
            _lastRideUpdateDateTime = DateTime.now();

            if (stops.length > 1) {
              final curr = stops[_currentStopIndex];
              final next =
                  stops[(_currentStopIndex + 1).clamp(0, stops.length - 1)];
              final dest = stops.last;
              _distanceToNextStopMeters = getStationByCode(curr.stationCode)
                  .distanceMetersTo(next.latitude, next.longitude);
              _distanceToDestinationMeters = getStationByCode(curr.stationCode)
                  .distanceMetersTo(dest.latitude, dest.longitude);
            }
          }
        }
      } catch (_) {
        await _settingsBox.delete('active_ride_state');
      }
    }
  }

  Future<void> _initLastKnownGps() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          _currentGpsPosition = pos;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void _startPeriodicSchedulePoll() {
    _schedulePollTimer?.cancel();
    _pollCountdownSeconds = 5;
    _schedulePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Guardrail: Only poll when app is open & focused, OR user has an active Track Watch, OR user confirmed they're on a train.
      if (!isPollingActive) {
        if (_isFastTrackPolling) {
          _isFastTrackPolling = false;
          notifyListeners();
        }
        return;
      }

      final nowEast = NjtApiService.easternNow();
      final watched = watchedTrain;
      final shouldFastPoll = shouldUseFastTrackWatchPolling(
        watchedTrip: watched,
        nowEastern: nowEast,
        fastBurstStartedAt: _fastTrackBurstStartedAt,
        rateLimitBackoffUntil: _trackWatchRateLimitUntil,
      );

      if (shouldFastPoll) {
        final wasFast = _isFastTrackPolling;
        _isFastTrackPolling = true;
        _fastTrackBurstStartedAt ??= nowEast;
        _pollCountdownSeconds = 1;
        _fastTrackFullSyncCounter++;

        if (!_isFastTrackPollInFlight && !_isPollInFlight) {
          _pollWatchedTrackFast();
        }
        if (_activeRideTrain != null &&
            _fastTrackFullSyncCounter >= 10 &&
            !_isPollInFlight) {
          _fastTrackFullSyncCounter = 0;
          refreshSchedules(silent: true);
        }
        if (!wasFast) {
          _syncBackgroundGuard();
        }
        notifyListeners();
        return;
      }

      if (_isFastTrackPolling) {
        _isFastTrackPolling = false;
        _fastTrackFullSyncCounter = 0;
        if (watched == null || watched.hasTrack) {
          _fastTrackBurstStartedAt = null;
        }
        _syncBackgroundGuard();
      }

      if (_isPollInFlight) return;

      if (_pollCountdownSeconds > 1) {
        _pollCountdownSeconds--;
        notifyListeners();
      } else {
        _pollCountdownSeconds = 5;
        refreshSchedules(silent: true);
      }
    });
  }

  Future<void> _pollWatchedTrackFast() async {
    final targetId = _watchedTrainId;
    if (targetId == null || _isFastTrackPollInFlight) return;

    final reqOrigin = _originStationCode;
    final reqDest = _destinationStationCode;
    _isFastTrackPollInFlight = true;

    try {
      final res = await NjtApiService.pollSingleTrainTrackFast(
        originCode: reqOrigin,
        trainId: targetId,
      );
      if (res == null ||
          _watchedTrainId != targetId ||
          _originStationCode != reqOrigin ||
          _destinationStationCode != reqDest) {
        return;
      }

      if (res.rateLimited) {
        _trackWatchRateLimitUntil =
            res.fetchedAtEastern.add(const Duration(seconds: 30));
        _isFastTrackPolling = false;
        notifyListeners();
        return;
      }

      if (!res.foundOnBoard) return;

      final idx = _upcomingTrains.indexWhere(
        (t) =>
            t.trainId == targetId &&
            t.originCode == reqOrigin &&
            t.destinationCode == reqDest,
      );
      if (idx == -1) return;

      final prev = _upcomingTrains[idx];
      final updated = prev.copyWith(
        track: res.hasTrack ? res.track : prev.track,
        status: res.status.isNotEmpty ? res.status : prev.status,
      );
      _upcomingTrains[idx] = updated;
      _lastScheduleRefresh = DateTime.now();

      final statusUpper = updated.status.toUpperCase();
      if (statusUpper.contains('CANCEL')) {
        _clearWatchedTrain(notify: false);
        await NotificationService.showCommuteAlert(
          type: 'track',
          title: '⚠️ Train #$targetId Cancelled',
          body:
              'DepartureVision marked Train #$targetId as Cancelled at ${originStation.shortName}.',
          vibrate: _notificationRules.vibrateOnAlerts,
          headphoneAudioBypass: _notificationRules.headphoneAudioBypass,
        );
        await _syncBackgroundGuard();
        notifyListeners();
        return;
      }

      if (_activeRideTrain == null && statusUpper.contains('DEPART')) {
        _clearWatchedTrain(notify: false);
        await NotificationService.showCommuteAlert(
          type: 'info',
          title: '🚉 Train #$targetId Departed ${originStation.shortName}',
          body:
              'Track watch paused automatically since Train #$targetId has departed.',
          vibrate: false,
          headphoneAudioBypass: false,
        );
        await _syncBackgroundGuard();
        notifyListeners();
        return;
      }

      if (updated.hasTrack && !prev.hasTrack) {
        _clearWatchedTrain(notify: false);
        await _fireTrackAnnouncedAlert(updated);
        await _syncBackgroundGuard();
      }
      notifyListeners();
    } finally {
      _isFastTrackPollInFlight = false;
    }
  }

  void _clearWatchedTrain({bool notify = true}) {
    _watchedTrainId = null;
    _watchStartedAt = null;
    _isFastTrackPolling = false;
    _fastTrackBurstStartedAt = null;
    _fastTrackFullSyncCounter = 0;
    if (notify) {
      notifyListeners();
    }
  }

  void setAppFocused(bool focused) {
    if (_isAppFocused == focused) return;
    _isAppFocused = focused;
    if (focused) {
      _pollCountdownSeconds = 5;
      syncFromBackgroundGuard();
      refreshSchedules(silent: true);
    } else {
      if (isBackgroundGuardActive) {
        _syncBackgroundGuard();
      }
      notifyListeners();
    }
  }

  Future<void> setDevTestMode(bool val) async {
    _devTestMode = val;
    await _settingsBox.put('dev_test_mode', val);
    if (!val && _isAutoSimulating) {
      stopAutoSimulate();
    }
    notifyListeners();
  }

  // --- Theme Controls ---
  Future<void> setAnimeThemeStyle(String style) async {
    _animeThemeStyle = style;
    await _settingsBox.put('anime_theme_style', style);
    _notificationRules = _notificationRules.copyWith(mascotPersonality: style);
    await _saveNotificationRules();
    notifyListeners();
    if (isBackgroundGuardActive) {
      await _syncBackgroundGuard();
    }
  }

  Future<void> setDarkMode(bool val) async {
    _isDarkMode = val;
    await _settingsBox.put('is_dark_mode', val);
    notifyListeners();
  }

  Future<void> setPureBlackDarkMode(bool val) async {
    _isPureBlackDarkMode = val;
    await _settingsBox.put('pure_black_dark_mode', val);
    notifyListeners();
  }

  Future<void> updateTextScale(double factor) async {
    _textScaleFactor = factor.clamp(0.85, 1.35);
    await _settingsBox.put('text_scale_factor', _textScaleFactor);
    notifyListeners();
  }

  // --- Station & Route Controls ---
  Future<void> setOriginAndDestination(String origCode, String destCode) async {
    if (origCode == destCode) return;
    final bool routeChanged =
        _originStationCode != origCode || _destinationStationCode != destCode;
    _originStationCode = origCode;
    _destinationStationCode = destCode;
    if (routeChanged) {
      _clearWatchedTrain(notify: false);
      _simulatedTrackTrainIds.clear();
      // Immediately replace old-direction trains with real cached bidirectional
      // NEC trains for the new direction (or empty while polling) — never invert!
      _upcomingTrains = NjtApiService.getCachedLiveTrips(
            originCode: origCode,
            destinationCode: destCode,
            activeRideTrainId: _activeRideTrain?.trainId,
          ) ??
          [];
      await _syncBackgroundGuard();
    }
    await _settingsBox.put('origin_station_code', origCode);
    await _settingsBox.put('destination_station_code', destCode);
    notifyListeners();
    await refreshSchedules(forceNetwork: true);
  }

  Future<void> swapStations() async {
    await setOriginAndDestination(_destinationStationCode, _originStationCode);
  }

  Future<void> setToWorkPreset() async {
    await setOriginAndDestination(_homeStationCode, _workStationCode);
  }

  Future<void> setToHomePreset() async {
    await setOriginAndDestination(_workStationCode, _homeStationCode);
  }

  Future<void> setWorkStation(String code) async {
    _workStationCode = code;
    if (!_starredStationCodes.contains(code)) {
      _starredStationCodes.add(code);
      await _settingsBox.put('starred_station_codes', _starredStationCodes);
    }
    await _settingsBox.put('work_station_code', code);
    notifyListeners();
  }

  Future<void> setHomeStation(String code) async {
    _homeStationCode = code;
    if (!_starredStationCodes.contains(code)) {
      _starredStationCodes.add(code);
      await _settingsBox.put('starred_station_codes', _starredStationCodes);
    }
    await _settingsBox.put('home_station_code', code);
    notifyListeners();
  }

  Future<void> toggleStarredStation(String code) async {
    if (_starredStationCodes.contains(code)) {
      if (code != _workStationCode && code != _homeStationCode) {
        _starredStationCodes.remove(code);
      }
    } else {
      _starredStationCodes.add(code);
    }
    await _settingsBox.put('starred_station_codes', _starredStationCodes);
    notifyListeners();
  }

  // --- Notification Rules Controls ---
  Future<void> updateNotificationRules(NotificationRules updated) async {
    _notificationRules = updated;
    await _saveNotificationRules();
    notifyListeners();
    if (isRiding) {
      await _updateOngoingNotification();
    }
    if (isBackgroundGuardActive) {
      await _syncBackgroundGuard();
    }
  }

  Future<void> _saveNotificationRules() async {
    await _settingsBox.put('notification_rules', _notificationRules.toJson());
  }

  // --- NJ Transit API & Schedule Fetching ---
  Future<bool> saveAndTestNjtCredentials(String username, String password) async {
    _njtUsername = username.trim();
    _njtPassword = password.trim();
    await _settingsBox.put('njt_username', _njtUsername);
    await _settingsBox.put('njt_password', _njtPassword);

    if (_njtUsername.isEmpty || _njtPassword.isEmpty) {
      _cachedNjtToken = '';
      await _settingsBox.put('cached_njt_token', '');
      notifyListeners();
      await refreshSchedules(forceNetwork: true);
      return false;
    }

    final token = await NjtApiService.fetchOfficialToken(
      username: _njtUsername,
      password: _njtPassword,
    );
    if (token != null && token.isNotEmpty) {
      _cachedNjtToken = token;
      _cachedNjtTokenTime = DateTime.now();
      await _settingsBox.put('cached_njt_token', token);
      await _settingsBox.put(
        'cached_njt_token_time',
        _cachedNjtTokenTime!.toIso8601String(),
      );
      notifyListeners();
      await refreshSchedules(forceNetwork: true);
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<String?> _getValidNjtToken() async {
    if (_cachedNjtToken.isNotEmpty && _cachedNjtTokenTime != null) {
      if (DateTime.now().difference(_cachedNjtTokenTime!).inHours < 22) {
        return _cachedNjtToken;
      }
    }
    if (hasNjtCredentials) {
      final fresh = await NjtApiService.fetchOfficialToken(
        username: _njtUsername,
        password: _njtPassword,
      );
      if (fresh != null) {
        _cachedNjtToken = fresh;
        _cachedNjtTokenTime = DateTime.now();
        await _settingsBox.put('cached_njt_token', fresh);
        await _settingsBox.put(
          'cached_njt_token_time',
          _cachedNjtTokenTime!.toIso8601String(),
        );
        return fresh;
      }
    }
    return null;
  }

  Future<void> refreshSchedules({
    bool silent = false,
    bool forceNetwork = false,
  }) async {
    if (_isPollInFlight && silent && !forceNetwork) return;

    final int requestGen = ++_refreshGeneration;
    final String reqOrigin = _originStationCode;
    final String reqDest = _destinationStationCode;

    _isPollInFlight = true;
    _pollCountdownSeconds = 5;
    if (!silent) {
      _isLoadingTrains = true;
      notifyListeners();
    }

    try {
      final token = await _getValidNjtToken();
      final previousTrains = List<TrainTrip>.from(_upcomingTrains);

      final fetched = await NjtApiService.fetchUpcomingTrains(
        originCode: reqOrigin,
        destinationCode: reqDest,
        cachedToken: token,
        forceRefresh: forceNetwork || !silent,
        watchedTrainId: _watchedTrainId,
        activeRideTrainId: _activeRideTrain?.trainId,
      );

      // Discard stale poll results if a newer direction switch or reload started
      if (requestGen != _refreshGeneration ||
          reqOrigin != _originStationCode ||
          reqDest != _destinationStationCode) {
        return;
      }

      // Only preserve explicit Dev Test Mode simulated track overrides in the same direction
      final merged = fetched.map((t) {
        if (!_devTestMode || !_simulatedTrackTrainIds.contains(t.trainId)) {
          return t;
        }
        final prev = previousTrains
            .where(
              (p) =>
                  p.trainId == t.trainId &&
                  p.originCode == t.originCode &&
                  p.destinationCode == t.destinationCode,
            )
            .firstOrNull;
        if (prev != null && prev.hasTrack && !t.hasTrack) {
          return t.copyWith(track: prev.track, status: prev.status);
        }
        return t;
      }).toList();

      // Check watched train track announcement & departure guardrail
      if (_watchedTrainId != null) {
        final watchedPrev = previousTrains
            .where(
              (p) =>
                  p.trainId == _watchedTrainId &&
                  p.originCode == reqOrigin &&
                  p.destinationCode == reqDest,
            )
            .firstOrNull;
        final watchedNow =
            merged.where((p) => p.trainId == _watchedTrainId).firstOrNull;

        if (watchedNow != null) {
          // Guardrail: If the watched train already departed origin and user hasn't confirmed boarding, stop watching/polling it
          if (_activeRideTrain == null &&
              watchedNow.hasDepartedOrigin(NjtApiService.easternNow())) {
            final departedId = watchedNow.trainId;
            _clearWatchedTrain(notify: false);
            NotificationService.showCommuteAlert(
              type: 'info',
              title: '🚉 Train #$departedId Departed ${originStation.shortName}',
              body:
                  'Track watch paused automatically since Train #$departedId has departed. If you boarded it, tap "I\'m on this!" under Just Departed.',
              vibrate: false,
              headphoneAudioBypass: false,
            );
            _syncBackgroundGuard();
          } else if (watchedNow.hasTrack &&
              (watchedPrev == null || !watchedPrev.hasTrack)) {
            _clearWatchedTrain(notify: false);
            _fireTrackAnnouncedAlert(watchedNow);
            _syncBackgroundGuard();
          } else if (watchedPrev == null ||
              watchedPrev.status != watchedNow.status) {
            _syncBackgroundGuard();
          }
        }
      }

      // If currently riding a train, sync live API stop departures (even if user flipped board view!)
      if (_activeRideTrain != null) {
        TrainTrip? liveMatch = merged
            .where(
              (t) =>
                  t.trainId == _activeRideTrain!.trainId &&
                  t.originCode == _activeRideTrain!.originCode &&
                  t.destinationCode == _activeRideTrain!.destinationCode,
            )
            .firstOrNull;
        if (liveMatch == null) {
          final activeRouteTrips = NjtApiService.getCachedLiveTrips(
            originCode: _activeRideTrain!.originCode,
            destinationCode: _activeRideTrain!.destinationCode,
            activeRideTrainId: _activeRideTrain!.trainId,
          );
          liveMatch = activeRouteTrips
              ?.where((t) => t.trainId == _activeRideTrain!.trainId)
              .firstOrNull;
        }
        if (liveMatch != null) {
          _syncActiveRideFromApi(liveMatch);
        }
        _lastRideUpdateDateTime = DateTime.now();
      }

      _upcomingTrains = merged;
      _isLoadingTrains = false;
      _lastScheduleRefresh = DateTime.now();
    } finally {
      if (requestGen == _refreshGeneration) {
        _isPollInFlight = false;
        _isLoadingTrains = false;
        notifyListeners();
      }
    }
  }

  // --- Track Watcher ---
  void toggleWatchTrainTrack(TrainTrip trip) {
    if (_watchedTrainId == trip.trainId) {
      _clearWatchedTrain();
      _syncBackgroundGuard();
      return;
    }
    _watchedTrainId = trip.trainId;
    _watchStartedAt = DateTime.now();
    _fastTrackBurstStartedAt = null;
    _isFastTrackPolling = false;
    _fastTrackFullSyncCounter = 0;
    notifyListeners();

    if (trip.hasTrack && _notificationRules.notifyOnTrackAssigned) {
      _fireTrackAnnouncedAlert(trip);
      _clearWatchedTrain();
      _syncBackgroundGuard();
    } else {
      NotificationService.showCommuteAlert(
        type: 'info',
        title: '👀 Watching Train #${trip.trainId} for Track',
        body:
            '1s fast polling engages at the 11-min mark so you\'re alerted the instant ${originStation.shortName} posts the track!',
        vibrate: false,
        headphoneAudioBypass: false,
      );
      _syncBackgroundGuard();
    }
  }

  /// Lets the user test/simulate a live NY Penn / Metropark track drop on a TBA train!
  Future<void> simulateTrackAnnouncement(String trainId, {String? customTrack}) async {
    final idx = _upcomingTrains.indexWhere((t) => t.trainId == trainId);
    if (idx == -1) return;
    _simulatedTrackTrainIds.add(trainId);
    final assignedTrack = customTrack ?? (originStationCode == 'NY' ? '11' : '4');
    final updated = _upcomingTrains[idx].copyWith(
      track: assignedTrack,
      status: 'Boarding',
    );
    _upcomingTrains[idx] = updated;
    if (_activeRideTrain?.trainId == trainId) {
      _activeRideTrain = _activeRideTrain!.copyWith(
        track: assignedTrack,
        status: 'Boarding',
      );
    }
    if (_watchedTrainId == trainId) {
      _clearWatchedTrain(notify: false);
    }
    notifyListeners();
    await _fireTrackAnnouncedAlert(updated);
    await _syncBackgroundGuard();
  }

  Future<void> _fireTrackAnnouncedAlert(TrainTrip trip) async {
    if (!_notificationRules.notifyOnTrackAssigned) return;
    final isSakura = _animeThemeStyle == 'sakura';
    final title = '⚡ TRACK ${trip.track} POSTED! • Train #${trip.trainId}';
    final body = isSakura
        ? '★ Hana-chan: Train #${trip.trainId} to ${destinationStation.shortName} is boarding on Track ${trip.track} (${trip.departureTime})! Hurry to the stairs~ ♪'
        : '✦ Tomori-navi: Track ${trip.track} announced at ${originStation.shortName} for Train #${trip.trainId} → ${destinationStation.shortName} (${trip.departureTime}). Move now!';
    await NotificationService.showCommuteAlert(
      type: 'track',
      title: title,
      body: body,
      vibrate: _notificationRules.vibrateOnAlerts,
      headphoneAudioBypass: _notificationRules.headphoneAudioBypass,
    );
  }

  // --- Active Ride & Hybrid GPS + API Engine ---
  Future<void> _saveActiveRideToBox() async {
    final trip = _activeRideTrain;
    if (trip == null) {
      await _settingsBox.delete('active_ride_state');
      return;
    }
    await _settingsBox.put('active_ride_state', {
      'trip': trip.toJson(),
      'arrivalEasternIso': _activeRideArrivalEastern?.toIso8601String(),
      'boardedAtIso': _activeRideBoardedAt?.toIso8601String(),
      'currentStopIndex': _currentStopIndex,
      'segmentProgress': _segmentProgress,
      'notifiedStopIndices': _notifiedStopIndices.toList(),
      'hasFiredWakeUpAlarm': _hasFiredWakeUpAlarm,
      'lastTrackingSignalSource': _lastTrackingSignalSource,
      'rideSceneSeed': _rideSceneSeed,
      'rideVariationIndex': _rideVariationIndex,
    });
  }

  /// Checks if the currently tracked train's arrival time is 20 minutes or more
  /// stale in Eastern time; if so, completes/clears the ride and returns `true`.
  Future<bool> checkAndExpireStaleActiveRide({DateTime? nowEastern}) async {
    final trip = _activeRideTrain;
    if (trip == null) return false;

    final nowEast = nowEastern ?? NjtApiService.easternNow();
    final arrEast = _activeRideArrivalEastern ??
        computeTripArrivalEastern(trip, referenceEasternNow: nowEast);

    if (isTripArrivalStale(arrivalEastern: arrEast, nowEastern: nowEast)) {
      await completeOrCancelRide(saveToHistory: true);
      return true;
    }
    return false;
  }

  Future<void> startRide(TrainTrip trip) async {
    stopAutoSimulate();
    _postArrivalGuardStopTimer?.cancel();
    _postArrivalGuardStopTimer = null;
    final rng = math.Random();
    _activeRideTrain = trip;
    _activeRideBoardedAt = DateTime.now();
    _activeRideArrivalEastern = computeTripArrivalEastern(trip);
    _rideSceneSeed = rng.nextInt(1 << 20);
    _rideVariationIndex = rng.nextInt(5);
    _clearWatchedTrain(notify: false);

    final stops = activeCommuteStops;
    int initialStopIdx = 0;
    if (trip.isRecentPastDeparture && stops.length > 2) {
      int passedCount = 0;
      for (int i = 0; i < stops.length - 1; i++) {
        if (stops[i].departed) passedCount = i;
      }
      initialStopIdx = passedCount.clamp(0, stops.length - 2);
    }

    _currentStopIndex = initialStopIdx;
    _segmentProgress = trip.isRecentPastDeparture ? 0.35 : 0.0;
    _notifiedStopIndices.clear();
    _hasFiredWakeUpAlarm = false;
    _lastRideUpdateDateTime = DateTime.now();
    _lastTrackingSignalSource = trip.isRecentPastDeparture
        ? 'Joined en-route (${trip.status})'
        : 'Boarded at ${originStation.shortName}';

    // Initialize distances from current station coordinates
    if (stops.length > 1) {
      final curr = stops[_currentStopIndex];
      final next = stops[(_currentStopIndex + 1).clamp(0, stops.length - 1)];
      final dest = stops.last;
      _distanceToNextStopMeters = getStationByCode(curr.stationCode)
          .distanceMetersTo(next.latitude, next.longitude);
      _distanceToDestinationMeters = getStationByCode(curr.stationCode)
          .distanceMetersTo(dest.latitude, dest.longitude);
    }

    await _saveActiveRideToBox();
    notifyListeners();
    await _startGpsStream();
    await _syncBackgroundGuard();

    final isSakura = _animeThemeStyle == 'sakura';
    final destShort = getStationByCode(trip.destinationCode).shortName;
    await NotificationService.showCommuteAlert(
      type: 'stop',
      title: '🚆 Boarded Train #${trip.trainId} → $destShort',
      body: isSakura
          ? '♪ All aboard! $stopsRemaining stops to $destShort (ETA ${trip.arrivalTime}). Silent Guard active & alerting at ${_notificationRules.startNotifyingStopsAway} stops away~'
          : '✦ Confirmed on Train #${trip.trainId} (${trip.track != null ? "Track ${trip.track}" : "NEC"}). $stopsRemaining stops to $destShort • ETA ${trip.arrivalTime}. Silent Guard ON.',
      vibrate: _notificationRules.vibrateOnAlerts,
      headphoneAudioBypass: false,
    );
  }

  Future<void> _startGpsStream() async {
    await _gpsSubscription?.cancel();
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _gpsSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 35,
          ),
        ).listen(_onGpsPositionUpdate);
      }
    } catch (_) {}
  }

  void _onGpsPositionUpdate(Position pos) {
    _currentGpsPosition = pos;
    _lastRideUpdateDateTime = DateTime.now();
    if (_activeRideTrain == null) {
      notifyListeners();
      return;
    }

    final stops = activeCommuteStops;
    if (stops.isEmpty) return;

    final destStop = stops.last;
    _distanceToDestinationMeters = getStationByCode(destStop.stationCode)
        .distanceMetersTo(pos.latitude, pos.longitude);

    // Check proximity to each stop ahead of _currentStopIndex
    for (int i = _currentStopIndex + 1; i < stops.length; i++) {
      final st = stops[i];
      final dist = getStationByCode(st.stationCode)
          .distanceMetersTo(pos.latitude, pos.longitude);
      if (dist <= _notificationRules.gpsStationRadiusMeters) {
        _advanceToStopIndex(i, source: 'Live GPS Geofence (${dist.toInt()}m)');
        break;
      }
    }

    // Update segment progress & distance to next stop
    final nextStop = nextUpcomingStop;
    final currStop = currentOrLastPassedStop;
    if (nextStop != null && currStop != null && _currentStopIndex < stops.length - 1) {
      final dNext = getStationByCode(nextStop.stationCode)
          .distanceMetersTo(pos.latitude, pos.longitude);
      final dTotal = getStationByCode(currStop.stationCode)
          .distanceMetersTo(nextStop.latitude, nextStop.longitude);
      _distanceToNextStopMeters = dNext;
      if (dTotal > 100) {
        _segmentProgress = (1.0 - (dNext / dTotal)).clamp(0.0, 0.98);
      }
    } else {
      _distanceToNextStopMeters = 0;
      _segmentProgress = 1.0;
    }

    // Check final wake-up distance alarm if approaching destination
    if (_notificationRules.finalWakeUpAlarm &&
        !_hasFiredWakeUpAlarm &&
        _distanceToDestinationMeters != null &&
        _distanceToDestinationMeters! <= 950 &&
        stopsRemaining <= 1) {
      _hasFiredWakeUpAlarm = true;
      final destShort =
          getStationByCode(_activeRideTrain!.destinationCode).shortName;
      _fireArrivalWakeUpAlert(
        reason: 'Within ${_distanceToDestinationMeters!.toInt()}m of $destShort',
      );
      _syncBackgroundGuard();
    }

    _saveActiveRideToBox();
    notifyListeners();
  }

  void _syncActiveRideFromApi(TrainTrip freshTrip) {
    final prevTrip = _activeRideTrain!;
    final freshStops = freshTrip.commuteStops;
    int highestDepartedIdx = _currentStopIndex;
    for (int i = 0; i < freshStops.length; i++) {
      if (freshStops[i].departed && i > highestDepartedIdx) {
        highestDepartedIdx = i;
      }
    }
    _activeRideTrain = prevTrip.copyWith(
      status: freshTrip.status,
      track: freshTrip.track ?? prevTrip.track,
      arrivalTime: freshTrip.arrivalTime,
      stops: freshTrip.stops.isNotEmpty ? freshTrip.stops : prevTrip.stops,
    );
    _activeRideArrivalEastern = computeTripArrivalEastern(
      _activeRideTrain!,
      referenceEasternNow:
          _activeRideArrivalEastern ?? NjtApiService.easternNow(),
    );
    if (highestDepartedIdx > _currentStopIndex) {
      _advanceToStopIndex(highestDepartedIdx, source: 'NJT Live API Feed');
    } else {
      _saveActiveRideToBox();
      if (_activeRideTrain!.track != prevTrip.track ||
          _activeRideTrain!.status != prevTrip.status ||
          _activeRideTrain!.arrivalTime != prevTrip.arrivalTime) {
        _syncBackgroundGuard();
      }
    }
  }

  Future<void> _advanceToStopIndex(int newIndex, {required String source}) async {
    final stops = activeCommuteStops;
    if (stops.isEmpty) return;
    final clamped = newIndex.clamp(0, stops.length - 1);
    if (clamped <= _currentStopIndex) return;

    _currentStopIndex = clamped;
    _segmentProgress = 0.0;
    _lastTrackingSignalSource = source;
    _lastRideUpdateDateTime = DateTime.now();

    // Update synthetic distances when advancing stops
    final currentSt = stops[_currentStopIndex];
    final destSt = stops.last;
    _distanceToDestinationMeters = getStationByCode(currentSt.stationCode)
        .distanceMetersTo(destSt.latitude, destSt.longitude);
    if (_currentStopIndex < stops.length - 1) {
      final nextSt = stops[_currentStopIndex + 1];
      _distanceToNextStopMeters = getStationByCode(currentSt.stationCode)
          .distanceMetersTo(nextSt.latitude, nextSt.longitude);
    } else {
      _distanceToNextStopMeters = 0;
      _segmentProgress = 1.0;
    }

    notifyListeners();
    await _evaluateStopNotifications(clamped, source: source);
    await _saveActiveRideToBox();
    await _syncBackgroundGuard();

    // Battery-safe auto-cutoff: 2 minutes after reaching the desired stop, shut down background guard
    if (stopsRemaining == 0) {
      _postArrivalGuardStopTimer?.cancel();
      _postArrivalGuardStopTimer = Timer(postArrivalGuardGracePeriod, () async {
        if (_activeRideTrain != null && stopsRemaining == 0) {
          await NotificationService.stopBackgroundGuard();
          await NotificationService.cancelRideProgress();
        }
      });
    }
  }

  Future<void> _evaluateStopNotifications(int stopIdx, {required String source}) async {
    if (_notifiedStopIndices.contains(stopIdx)) return;
    _notifiedStopIndices.add(stopIdx);

    final stops = activeCommuteStops;
    if (stops.isEmpty) return;
    final currentStop = stops[stopIdx];
    final rem = stopsRemaining;
    final isSakura = _animeThemeStyle == 'sakura';
    final destShort = _activeRideTrain != null
        ? getStationByCode(_activeRideTrain!.destinationCode).shortName
        : destinationStation.shortName;

    // Case 1: Arrived at destination (0 stops remaining)
    if (rem == 0) {
      if (!_hasFiredWakeUpAlarm) {
        _hasFiredWakeUpAlarm = true;
        await _fireArrivalWakeUpAlert(
          reason: 'Arrived at $destShort!',
        );
      }
      return;
    }

    // Case 2: Within user's "Start notifying X stops away" threshold!
    if (rem <= _notificationRules.startNotifyingStopsAway) {
      final isOneStopAway = rem == 1;
      final title = isOneStopAway
          ? '🚨 1 STOP AWAY! Next: $destShort'
          : '🔔 $rem Stops Away from $destShort!';
      final body = isOneStopAway
          ? (isSakura
              ? '★ Passing ${currentStop.stationName}! $destShort is NEXT (ETA ${_activeRideTrain?.arrivalTime})! Pack up & head to the doors~ ♪'
              : '⚡ Passed ${currentStop.stationName}. $destShort is the NEXT stop (ETA ${_activeRideTrain?.arrivalTime}). Time to stand up!')
          : (isSakura
              ? '✿ Now at ${currentStop.stationName} • Only $rem stops left until $destShort (ETA ${_activeRideTrain?.arrivalTime})~!'
              : '✦ Cleared ${currentStop.stationName} ($source). $rem stops left to $destShort • ETA ${_activeRideTrain?.arrivalTime}.');

      await NotificationService.showCommuteAlert(
        type: isOneStopAway ? 'arrival' : 'stop',
        title: title,
        body: body,
        vibrate: _notificationRules.vibrateOnAlerts,
        headphoneAudioBypass: _notificationRules.headphoneAudioBypass,
      );
      return;
    }

    // Case 3: User enabled "Notify me on every stop"
    if (_notificationRules.notifyEveryStop) {
      await NotificationService.showCommuteAlert(
        type: 'stop',
        title: '🚉 Passed ${currentStop.stationName} ($rem stops left)',
        body:
            'Next stop: ${nextUpcomingStop?.stationName ?? destShort} • Destination ETA: ${_activeRideTrain?.arrivalTime}',
        vibrate: _notificationRules.vibrateOnAlerts,
        headphoneAudioBypass: _notificationRules.headphoneAudioBypass,
      );
    }
  }

  Future<void> _fireArrivalWakeUpAlert({required String reason}) async {
    final isSakura = _animeThemeStyle == 'sakura';
    final destShort = _activeRideTrain != null
        ? getStationByCode(_activeRideTrain!.destinationCode).shortName
        : destinationStation.shortName;
    await NotificationService.showCommuteAlert(
      type: 'arrival',
      title: '🎉 ARRIVING AT ${destShort.toUpperCase()}!',
      body: isSakura
          ? '★ $reason! Check your seat for your phone, headphones & bag before stepping off~ ♪'
          : '⚡ $reason! Grab your bag and step onto the platform safely.',
      vibrate: true,
      headphoneAudioBypass: _notificationRules.headphoneAudioBypass,
    );
  }

  Future<void> _updateOngoingNotification() async {
    await _syncBackgroundGuard();
  }

  /// Synchronizes the native Android Foreground Service ("Silent Guard") with
  /// the active ride or active track watch so notifications survive accidental
  /// app closing and automatically cut off after arrival or safety caps.
  Future<void> _syncBackgroundGuard() async {
    final rideTrip = _activeRideTrain;
    if (rideTrip != null) {
      final origSt = getStationByCode(rideTrip.originCode);
      final destSt = getStationByCode(rideTrip.destinationCode);
      final stops = activeCommuteStops;
      final rem = stopsRemaining;
      final currName = currentOrLastPassedStop?.stationName ?? origSt.shortName;
      final nextName = nextUpcomingStop?.stationName ?? destSt.shortName;
      final arrivalEast = _activeRideArrivalEastern ??
          computeTripArrivalEastern(rideTrip);
      final depEast = rideTrip.departureDateTime;

      final notifTitle = rem == 0
          ? 'Arrived at ${destSt.shortName}! • Train #${rideTrip.trainId}'
          : 'Train #${rideTrip.trainId} → ${destSt.shortName} ($rem ${rem == 1 ? "stop" : "stops"} away)';
      final notifBody = rem == 0
          ? 'Commute complete! Auto-stopping soon to save battery.'
          : 'At/Passed: $currName • Next: $nextName • ETA ${rideTrip.arrivalTime}';
      final notifSubText = rideTrip.track != null
          ? 'Track ${rideTrip.track} • Guard ON'
          : 'my5top Guard';

      final payload = <String, dynamic>{
        'mode': 'ride',
        'trainId': rideTrip.trainId,
        'originCode': origSt.code,
        'originDvCode': origSt.dvCode,
        'originShortName': origSt.shortName,
        'destCode': destSt.code,
        'destShortName': destSt.shortName,
        'departureTime': rideTrip.departureTime,
        'arrivalTime': rideTrip.arrivalTime,
        'departureEpochMs': depEast != null
            ? NjtApiService.easternWallClockToEpochMs(depEast)
            : 0,
        'arrivalEpochMs': NjtApiService.easternWallClockToEpochMs(arrivalEast),
        'startedAtEpochMs':
            (_activeRideBoardedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'track': rideTrip.track ?? '',
        'status': rideTrip.status,
        'currentStopIndex': _currentStopIndex,
        'notifiedStopIndices': _notifiedStopIndices.toList(),
        'hasFiredWakeUpAlarm': _hasFiredWakeUpAlarm,
        'stops': stops
            .map((s) => {
                  'stationCode': s.stationCode,
                  'stationName': s.stationName,
                  'latitude': s.latitude,
                  'longitude': s.longitude,
                  'estimatedTime': s.estimatedTime,
                })
            .toList(),
        'rules': _notificationRules.toJson(),
        'notificationTitle': notifTitle,
        'notificationBody': notifBody,
        'notificationSubText': notifSubText,
      };
      await NotificationService.startBackgroundGuard(payload);
      return;
    }

    final watched = watchedTrain;
    if (watched != null && !watched.hasTrack) {
      final origSt = getStationByCode(watched.originCode);
      final destSt = getStationByCode(watched.destinationCode);
      final depEast = watched.departureDateTime;
      final notifTitle =
          '👀 Watching Track • Train #${watched.trainId} (${watched.departureTime})';
      final notifBody = _isFastTrackPolling
          ? '1s fast polling active for ${origSt.shortName} track drop • ${watched.status}'
          : 'Waiting for ${origSt.shortName} track assignment • ${watched.status}';
      final notifSubText =
          _isFastTrackPolling ? '⚡ 1s Watch' : 'Track Watch';

      final payload = <String, dynamic>{
        'mode': 'watch',
        'trainId': watched.trainId,
        'originCode': origSt.code,
        'originDvCode': origSt.dvCode,
        'originShortName': origSt.shortName,
        'destCode': destSt.code,
        'destShortName': destSt.shortName,
        'departureTime': watched.departureTime,
        'arrivalTime': watched.arrivalTime,
        'departureEpochMs': depEast != null
            ? NjtApiService.easternWallClockToEpochMs(depEast)
            : 0,
        'arrivalEpochMs': 0,
        'startedAtEpochMs':
            (_watchStartedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'track': watched.track ?? '',
        'status': watched.status,
        'currentStopIndex': 0,
        'notifiedStopIndices': <int>[],
        'hasFiredWakeUpAlarm': false,
        'stops': <Map<String, dynamic>>[],
        'rules': _notificationRules.toJson(),
        'notificationTitle': notifTitle,
        'notificationBody': notifBody,
        'notificationSubText': notifSubText,
      };
      await NotificationService.startBackgroundGuard(payload);
      return;
    }

    await NotificationService.stopBackgroundGuard();
    await NotificationService.cancelRideProgress();
  }

  /// Pulls any progress, track announcements, or 1-tap notification stop events
  /// recorded by the native Android Foreground Service while the UI was closed.
  Future<void> syncFromBackgroundGuard() async {
    final updates = await NotificationService.syncBackgroundState();
    if (updates == null || updates['hasUpdates'] != true) return;

    final bgMode = (updates['mode'] ?? '').toString();
    final bgTrainId = (updates['trainId'] ?? '').toString();
    final stoppedByUser = updates['stoppedByUser'] == true;

    if (stoppedByUser) {
      if (bgMode == 'ride' && _activeRideTrain != null) {
        await completeOrCancelRide(saveToHistory: true);
      } else if (bgMode == 'watch' && _watchedTrainId != null) {
        _clearWatchedTrain();
      }
      return;
    }

    if (bgMode == 'ride' &&
        _activeRideTrain != null &&
        _activeRideTrain!.trainId == bgTrainId) {
      bool changed = false;
      final bgStopIdx = (updates['currentStopIndex'] as num?)?.toInt() ?? -1;
      final stops = activeCommuteStops;
      if (stops.isNotEmpty && bgStopIdx > _currentStopIndex) {
        _currentStopIndex = bgStopIdx.clamp(0, stops.length - 1);
        final currSt = stops[_currentStopIndex];
        final destSt = stops.last;
        _distanceToDestinationMeters = getStationByCode(currSt.stationCode)
            .distanceMetersTo(destSt.latitude, destSt.longitude);
        if (_currentStopIndex < stops.length - 1) {
          final nextSt = stops[_currentStopIndex + 1];
          _distanceToNextStopMeters = getStationByCode(currSt.stationCode)
              .distanceMetersTo(nextSt.latitude, nextSt.longitude);
          _segmentProgress = 0.0;
        } else {
          _distanceToNextStopMeters = 0;
          _segmentProgress = 1.0;
        }
        changed = true;
      }

      final bgNotified = updates['notifiedStopIndices'];
      if (bgNotified is List) {
        for (final item in bgNotified) {
          if (item is num) {
            if (_notifiedStopIndices.add(item.toInt())) {
              changed = true;
            }
          }
        }
      }

      if (updates['hasFiredWakeUpAlarm'] == true && !_hasFiredWakeUpAlarm) {
        _hasFiredWakeUpAlarm = true;
        changed = true;
      }

      final bgSource = (updates['lastTrackingSignalSource'] ?? '').toString().trim();
      if (bgSource.isNotEmpty && bgSource != _lastTrackingSignalSource) {
        _lastTrackingSignalSource = bgSource;
        changed = true;
      }

      if (changed) {
        _lastRideUpdateDateTime = DateTime.now();
        await _saveActiveRideToBox();
        notifyListeners();
      }
    } else if (bgMode == 'watch' && bgTrainId.isNotEmpty) {
      final detectedTrack = (updates['detectedTrack'] ?? '').toString().trim();
      final detectedStatus = (updates['detectedStatus'] ?? '').toString().trim();
      if (detectedTrack.isNotEmpty) {
        final idx = _upcomingTrains.indexWhere((t) => t.trainId == bgTrainId);
        if (idx != -1) {
          _upcomingTrains[idx] = _upcomingTrains[idx].copyWith(
            track: detectedTrack,
            status: detectedStatus.isNotEmpty
                ? detectedStatus
                : _upcomingTrains[idx].status,
          );
        }
        if (_watchedTrainId == bgTrainId) {
          _clearWatchedTrain(notify: false);
        }
        notifyListeners();
      }
    }
  }

  // --- Interactive Commute Simulator (Step through stops or auto-run) ---
  Future<void> simulateNextStop() async {
    if (_activeRideTrain == null) return;
    final stops = activeCommuteStops;
    if (_currentStopIndex < stops.length - 1) {
      await _advanceToStopIndex(
        _currentStopIndex + 1,
        source: 'Simulated GPS + API Step',
      );
    }
  }

  void toggleAutoSimulateRide() {
    if (_isAutoSimulating) {
      stopAutoSimulate();
      return;
    }
    if (_activeRideTrain == null) return;
    _isAutoSimulating = true;
    notifyListeners();

    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_activeRideTrain == null || _currentStopIndex >= activeCommuteStops.length - 1) {
        stopAutoSimulate();
        return;
      }
      _segmentProgress += 0.34;
      if (_segmentProgress >= 1.0) {
        await simulateNextStop();
      } else {
        notifyListeners();
      }
    });
  }

  void stopAutoSimulate() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    if (_isAutoSimulating) {
      _isAutoSimulating = false;
      notifyListeners();
    }
  }

  Future<void> completeOrCancelRide({bool saveToHistory = true}) async {
    stopAutoSimulate();
    _postArrivalGuardStopTimer?.cancel();
    _postArrivalGuardStopTimer = null;
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;

    final trip = _activeRideTrain;
    if (trip != null && saveToHistory) {
      final origSt = getStationByCode(trip.originCode);
      final destSt = getStationByCode(trip.destinationCode);
      final log = RideLog(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        trainId: trip.trainId,
        originCode: trip.originCode,
        originName: origSt.shortName,
        destinationCode: trip.destinationCode,
        destinationName: destSt.shortName,
        track: trip.track,
        boardedAt: _activeRideBoardedAt ??
            DateTime.now().subtract(const Duration(minutes: 25)),
        arrivedAt: DateTime.now(),
        totalStops: trip.totalStopCount,
        statusSummary: trip.status,
      );
      _rideLogs.insert(0, log);
      if (_rideLogs.length > 50) {
        _rideLogs = _rideLogs.sublist(0, 50);
      }
      await _settingsBox.put(
        'ride_logs',
        _rideLogs.map((e) => e.toJson()).toList(),
      );
    }

    _activeRideTrain = null;
    _activeRideArrivalEastern = null;
    _activeRideBoardedAt = null;
    _currentStopIndex = 0;
    _segmentProgress = 0.0;
    await _settingsBox.delete('active_ride_state');
    await _syncBackgroundGuard();
    notifyListeners();
  }

  @override
  void dispose() {
    _schedulePollTimer?.cancel();
    _simulationTimer?.cancel();
    _postArrivalGuardStopTimer?.cancel();
    _gpsSubscription?.cancel();
    super.dispose();
  }

  // --- MIHON-STYLE SAF / GOOGLE DRIVE JSON BACKUP & RESTORE ---
  String get safBackupDirectoryUri =>
      _settingsBox.get('saf_backup_directory_uri', defaultValue: '') as String;

  String get safBackupDirectoryLabel =>
      _settingsBox.get('saf_backup_directory_label', defaultValue: '') as String;

  String get backupInterval =>
      _settingsBox.get('backup_interval', defaultValue: 'off') as String;

  Future<void> setBackupInterval(String val) async {
    await _settingsBox.put('backup_interval', val);
    notifyListeners();
  }

  DateTime? get lastBackupTime {
    final timeStr = _settingsBox.get('last_backup_time') as String?;
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  Future<void> setLastBackupTime(DateTime dt) async {
    await _settingsBox.put('last_backup_time', dt.toIso8601String());
    notifyListeners();
  }

  Map<String, dynamic> exportBackupMap({bool includeCredentials = true}) {
    return {
      'app': 'my5top',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': appVersion,
      'animeThemeStyle': _animeThemeStyle,
      'isDarkMode': _isDarkMode,
      'isPureBlackDarkMode': _isPureBlackDarkMode,
      'textScaleFactor': _textScaleFactor,
      'workStationCode': _workStationCode,
      'homeStationCode': _homeStationCode,
      'starredStationCodes': _starredStationCodes,
      'originStationCode': _originStationCode,
      'destinationStationCode': _destinationStationCode,
      'notificationRules': _notificationRules.toJson(),
      'rideLogs': _rideLogs.map((r) => r.toJson()).toList(),
      if (includeCredentials) 'njtUsername': _njtUsername,
      'githubRepoPath': githubRepoPath,
    };
  }

  Future<void> importFromJson(Map<String, dynamic> json) async {
    if (json['animeThemeStyle'] != null) {
      _animeThemeStyle = json['animeThemeStyle'].toString();
      await _settingsBox.put('anime_theme_style', _animeThemeStyle);
    }
    if (json['isDarkMode'] is bool) {
      _isDarkMode = json['isDarkMode'] as bool;
      await _settingsBox.put('is_dark_mode', _isDarkMode);
    }
    if (json['isPureBlackDarkMode'] is bool) {
      _isPureBlackDarkMode = json['isPureBlackDarkMode'] as bool;
      await _settingsBox.put('pure_black_dark_mode', _isPureBlackDarkMode);
    }
    if (json['workStationCode'] != null) {
      _workStationCode = json['workStationCode'].toString();
      await _settingsBox.put('work_station_code', _workStationCode);
    }
    if (json['homeStationCode'] != null) {
      _homeStationCode = json['homeStationCode'].toString();
      await _settingsBox.put('home_station_code', _homeStationCode);
    }
    if (json['starredStationCodes'] is List) {
      _starredStationCodes = (json['starredStationCodes'] as List)
          .map((e) => e.toString())
          .toList();
      await _settingsBox.put('starred_station_codes', _starredStationCodes);
    }
    if (json['originStationCode'] != null &&
        json['destinationStationCode'] != null) {
      _originStationCode = json['originStationCode'].toString();
      _destinationStationCode = json['destinationStationCode'].toString();
      await _settingsBox.put('origin_station_code', _originStationCode);
      await _settingsBox.put('destination_station_code', _destinationStationCode);
    }
    if (json['notificationRules'] is Map) {
      _notificationRules = NotificationRules.fromJson(
        Map<String, dynamic>.from(json['notificationRules'] as Map),
      );
      await _saveNotificationRules();
    }
    if (json['rideLogs'] is List) {
      _rideLogs = (json['rideLogs'] as List)
          .whereType<Map>()
          .map((m) => RideLog.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      await _settingsBox.put(
        'ride_logs',
        _rideLogs.map((e) => e.toJson()).toList(),
      );
    }
    if (json['njtUsername'] != null &&
        json['njtUsername'].toString().isNotEmpty) {
      _njtUsername = json['njtUsername'].toString();
      await _settingsBox.put('njt_username', _njtUsername);
    }
    if (json['githubRepoPath'] != null &&
        json['githubRepoPath'].toString().isNotEmpty) {
      await setGithubRepoPath(json['githubRepoPath'].toString());
    }
    notifyListeners();
    await refreshSchedules();
  }

  /// Opens the native Android Files / Google Drive folder chooser (Mihon style)
  Future<Map<String, dynamic>?> pickBackupDestinationFolder() async {
    if (!kIsWeb && Platform.isAndroid) {
      final res = await _safBackupChannel
          .invokeMethod<Map<dynamic, dynamic>>('pickBackupDirectory');
      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        if (map['success'] == true) {
          final uri = map['uri']?.toString() ?? '';
          final display = map['displayName']?.toString() ?? uri;
          await _settingsBox.put('saf_backup_directory_uri', uri);
          await _settingsBox.put('saf_backup_directory_label', display);
          notifyListeners();
        }
        return map;
      }
    }
    return null;
  }

  /// Opens the native Android Files / Google Drive "Save to..." chooser (`ACTION_CREATE_DOCUMENT`)
  Future<Map<String, dynamic>?> createBackupViaFilePicker() async {
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'my5top_backup_$stamp.json';
    final fullMap = exportBackupMap();
    final payload = const JsonEncoder.withIndent('  ').convert(fullMap);

    String? sourceFilePath;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final backupDir =
          Directory('${docDir.path}${Platform.pathSeparator}backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final localFile =
          File('${backupDir.path}${Platform.pathSeparator}$fileName');
      await localFile.writeAsString(payload);
      sourceFilePath = localFile.path;
    } catch (_) {}

    if (!kIsWeb && Platform.isAndroid) {
      final res = await _safBackupChannel.invokeMethod<Map<dynamic, dynamic>>(
        'createBackupDocument',
        {
          'fileName': fileName,
          if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
          if (sourceFilePath == null) 'content': payload,
        },
      );
      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        if (map['success'] == true) {
          await setLastBackupTime(DateTime.now());
        }
        return map;
      }
    } else {
      final savedPath = await exportLocalBackupFile();
      await setLastBackupTime(DateTime.now());
      return {
        'success': true,
        'displayName': savedPath,
        'uri': savedPath,
      };
    }
    return null;
  }

  /// Opens the native Android Files / Google Drive file chooser (`ACTION_OPEN_DOCUMENT`)
  Future<Map<String, dynamic>?> restoreBackupViaFilePicker() async {
    if (!kIsWeb && Platform.isAndroid) {
      final res = await _safBackupChannel
          .invokeMethod<Map<dynamic, dynamic>>('openBackupDocument');
      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        if (map['cancelled'] == true) return map;
        if (map['success'] == true) {
          String? content;
          final tempFilePath = map['tempFilePath']?.toString();
          if (tempFilePath != null && tempFilePath.isNotEmpty) {
            final tempFile = File(tempFilePath);
            if (await tempFile.exists()) {
              content = await tempFile.readAsString();
            }
          }
          content ??= map['content']?.toString();
          if (content != null && content.isNotEmpty) {
            final decoded = json.decode(content) as Map<String, dynamic>;
            await importFromJson(decoded);
            return {
              'success': true,
              'displayName': map['displayName']?.toString() ?? 'backup.json',
              'rideLogs': _rideLogs.length,
            };
          }
        }
      }
    }
    return null;
  }

  Future<String> exportLocalBackupFile() async {
    final docDir = await getApplicationDocumentsDirectory();
    final backupDir =
        Directory('${docDir.path}${Platform.pathSeparator}backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'my5top_backup_$stamp.json';
    final payload =
        const JsonEncoder.withIndent('  ').convert(exportBackupMap());

    final localFile =
        File('${backupDir.path}${Platform.pathSeparator}$fileName');
    await localFile.writeAsString(payload);
    await setLastBackupTime(now);

    if (!kIsWeb && Platform.isAndroid && safBackupDirectoryUri.isNotEmpty) {
      try {
        await _safBackupChannel.invokeMethod<Map<dynamic, dynamic>>(
          'saveToDirectoryUri',
          {
            'treeUri': safBackupDirectoryUri,
            'fileName': fileName,
            'sourceFilePath': localFile.path,
          },
        );
      } catch (_) {}
    }

    return localFile.path;
  }

  Future<List<File>> getLocalBackupFiles() async {
    final List<File> files = [];
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final backupDir =
          Directory('${docDir.path}${Platform.pathSeparator}backups');
      if (await backupDir.exists()) {
        await for (final entity in backupDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            files.add(entity);
          }
        }
      }
      files.sort((a, b) => b.path.compareTo(a.path));
    } catch (_) {}
    return files;
  }

  Future<void> restoreFromLocalBackupFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final decoded = json.decode(content) as Map<String, dynamic>;
    await importFromJson(decoded);
  }

  /// Calculates storage usage of local/SAF backups matching mygo2.
  Future<Map<String, int>> getStorageStats() async {
    int backupFiles = 0;
    int backupBytes = 0;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final backupDir =
          Directory('${docDir.path}${Platform.pathSeparator}backups');
      if (await backupDir.exists()) {
        await for (final entity in backupDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            backupFiles++;
            backupBytes += await entity.length();
          }
        }
      }

      if (!kIsWeb && Platform.isAndroid && safBackupDirectoryUri.isNotEmpty) {
        try {
          final res =
              await _safBackupChannel.invokeMethod<Map<dynamic, dynamic>>(
            'getBackupDirectoryStats',
            {'treeUri': safBackupDirectoryUri},
          );
          if (res != null && res['success'] == true) {
            final folderCount = (res['fileCount'] as num?)?.toInt() ?? 0;
            final folderBytes = (res['totalBytes'] as num?)?.toInt() ?? 0;
            if (folderCount > 0 || folderBytes > 0) {
              backupFiles = folderCount;
              backupBytes = folderBytes;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    return {
      'backupFiles': backupFiles,
      'backupBytes': backupBytes,
    };
  }

  /// Opens the "What's new" release notes bottom sheet matching mygo2.
  Future<void> showWhatsNew(BuildContext context) async {
    final repo = githubRepoPath.trim();
    if (repo.isEmpty) return;

    try {
      final headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'my5top-app',
      };
      if (githubToken.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${githubToken.trim()}';
      }
      final url = 'https://api.github.com/repos/$repo/releases';
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty && context.mounted) {
          final latestRelease = data[0];
          final rawTagName =
              (latestRelease['tag_name'] as String? ?? 'v$appVersion').trim();
          final releaseTitle =
              (latestRelease['name'] as String? ?? 'What\'s New').trim();
          final releaseNotes =
              (latestRelease['body'] as String? ?? 'No release notes provided.')
                  .trim();
          final releaseUrl = (latestRelease['html_url'] as String? ??
                  'https://github.com/$repo/releases')
              .trim();

          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) {
              final dark = isDarkMode;
              final bg = dark
                  ? (isPureBlackDarkMode
                      ? Colors.black
                      : const Color(0xFF0F172A))
                  : Colors.white;
              return Container(
                height: MediaQuery.of(ctx).size.height * 0.85,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border:
                      Border.all(color: dark ? Colors.white12 : Colors.black12),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: dark ? Colors.white24 : Colors.black26,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.new_releases_outlined,
                              color: palette.primaryAccent,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'What\'s new',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          dark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    '$rawTagName • $releaseTitle',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dark
                                          ? Colors.white60
                                          : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: Icon(
                                Icons.close,
                                color: dark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: dark ? Colors.white12 : Colors.black12),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            releaseNotes,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.55,
                              color: dark
                                  ? Colors.white.withOpacity(0.88)
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  if (await canLaunchUrl(
                                      Uri.parse(releaseUrl))) {
                                    await launchUrl(
                                      Uri.parse(releaseUrl),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('View on GitHub'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: palette.primaryAccent,
                                  foregroundColor: Colors.black,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Done',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      }
    } catch (_) {}
  }

  // --- GITHUB RELEASES APK SELF-UPDATER (Matching mygo2) ---
  String get githubRepoPath => 'hsoj1092/my5top';

  Future<void> setGithubRepoPath(String path) async {
    await _settingsBox.put('github_repo_path', 'hsoj1092/my5top');
    notifyListeners();
  }

  String get githubToken =>
      _settingsBox.get('github_token', defaultValue: '') as String;

  Future<void> setGithubToken(String token) async {
    await _settingsBox.put('github_token', token.trim());
    notifyListeners();
  }

  String get skippedUpdateVersion =>
      _settingsBox.get('skipped_update_version', defaultValue: '') as String;

  Future<void> setSkippedUpdateVersion(String version) async {
    await _settingsBox.put('skipped_update_version', version);
    notifyListeners();
  }

  DateTime? get lastUpdateCheckTime {
    final timeStr = _settingsBox.get('last_update_check_time') as String?;
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  Future<void> setLastUpdateCheckTime(DateTime dt) async {
    await _settingsBox.put('last_update_check_time', dt.toIso8601String());
    notifyListeners();
  }

  Future<void> checkAndRunDailyUpdate(BuildContext context) async {
    if (_hasCheckedUpdateThisSession) return;
    final repo = githubRepoPath.trim();
    if (repo.isEmpty) return;

    _hasCheckedUpdateThisSession = true;
    await setLastUpdateCheckTime(DateTime.now());
    if (context.mounted) {
      await checkForUpdates(context, showNoUpdateDialog: false);
    }
  }

  bool isVersionNewer(String currentVer, String latestVer) {
    final cleanCur = currentVer.replaceAll(RegExp(r'^[vV]'), '').trim();
    final cleanLat = latestVer.replaceAll(RegExp(r'^[vV]'), '').trim();

    final curSplit = cleanCur.split(RegExp(r'[+\-]'));
    final latSplit = cleanLat.split(RegExp(r'[+\-]'));

    final currentParts = curSplit[0]
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final latestParts = latSplit[0]
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final maxLen = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;
    for (int i = 0; i < maxLen; i++) {
      final cur = i < currentParts.length ? currentParts[i] : 0;
      final lat = i < latestParts.length ? latestParts[i] : 0;
      if (lat > cur) return true;
      if (lat < cur) return false;
    }

    final curIsPreRelease = cleanCur.split('+')[0].contains('-');
    final latIsPreRelease = cleanLat.split('+')[0].contains('-');
    if (curIsPreRelease && !latIsPreRelease) return true;

    final curPlusParts = cleanCur.split('+');
    final latPlusParts = cleanLat.split('+');

    final int curBuild = (curPlusParts.length > 1
            ? int.tryParse(curPlusParts.last.replaceAll(RegExp(r'[^0-9]'), ''))
            : null) ??
        appBuildNumber;
    final int latBuild = (latPlusParts.length > 1
            ? int.tryParse(latPlusParts.last.replaceAll(RegExp(r'[^0-9]'), ''))
            : null) ??
        0;

    if (latBuild > 0 && latBuild > curBuild) return true;
    return false;
  }

  Future<void> checkForUpdates(
    BuildContext context, {
    bool showNoUpdateDialog = true,
  }) async {
    final repo = githubRepoPath.trim();
    if (repo.isEmpty) return;

    try {
      final headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'my5top-app',
      };
      if (githubToken.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${githubToken.trim()}';
      }

      final url = 'https://api.github.com/repos/$repo/releases';
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isEmpty) {
          if (showNoUpdateDialog && context.mounted) {
            _showUpToDateDialog(context, 'https://github.com/$repo/releases');
          }
          return;
        }

        Map<String, dynamic> latestRelease =
            Map<String, dynamic>.from(data[0] as Map);
        for (final item in data) {
          if (item is Map) {
            final t = (item['tag_name'] as String? ?? '').trim();
            if (RegExp(r'\d+\.\d+\.\d+').hasMatch(t)) {
              latestRelease = Map<String, dynamic>.from(item);
              break;
            }
          }
        }

        final rawTagName = (latestRelease['tag_name'] as String? ?? '').trim();
        final latestVersion =
            rawTagName.replaceAll(RegExp(r'^[vV]'), '').trim();
        final releaseTitle = (latestRelease['name'] as String? ?? '').trim();
        final releaseNotes = (latestRelease['body'] as String? ?? '').trim();
        final releaseUrl = (latestRelease['html_url'] as String? ??
                'https://github.com/$repo/releases')
            .trim();

        final newer = isVersionNewer(appVersion, latestVersion);
        if (!showNoUpdateDialog && skippedUpdateVersion == latestVersion) {
          return;
        }

        if (newer && context.mounted) {
          String? apkUrl;
          int? apkAssetId;
          String? apkName;
          final assets = latestRelease['assets'] as List?;
          if (assets != null) {
            for (final asset in assets) {
              final name = asset['name'] as String;
              if (name.toLowerCase().endsWith('.apk')) {
                apkUrl = asset['browser_download_url'] as String?;
                apkAssetId = asset['id'] as int?;
                apkName = name;
                break;
              }
            }
          }

          await _showUpdateScreen(
            context: context,
            latestVersion: latestVersion,
            releaseTitle: releaseTitle,
            releaseNotes: releaseNotes,
            releaseUrl: releaseUrl,
            apkAssetId: apkAssetId,
            apkName: apkName,
            apkUrl: apkUrl,
          );
        } else if (showNoUpdateDialog && context.mounted) {
          _showUpToDateDialog(context, releaseUrl);
        }
      } else if (showNoUpdateDialog && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'GitHub release check returned HTTP ${response.statusCode} for $repo (publish your first v1.0.0 release to enable OTA!).',
            ),
          ),
        );
      }
    } catch (e) {
      if (showNoUpdateDialog && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reach GitHub Releases: $e')),
        );
      }
    }
  }

  void _showUpToDateDialog(BuildContext context, String releaseUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: palette.successColor),
            const SizedBox(width: 8),
            const Text('Up to Date'),
          ],
        ),
        content: Text(
          'You are running the latest version of my5top (v$appVersion+$appBuildNumber).',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (await canLaunchUrl(Uri.parse(releaseUrl))) {
                await launchUrl(
                  Uri.parse(releaseUrl),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: const Text('GitHub Releases'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateScreen({
    required BuildContext context,
    required String latestVersion,
    required String releaseTitle,
    required String releaseNotes,
    required String releaseUrl,
    required int? apkAssetId,
    required String? apkName,
    required String? apkUrl,
  }) async {
    bool isDownloading = false;
    double? downloadProgress;
    String statusMessage = '';

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (screenCtx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final pal = palette;

              Future<void> startSeamlessInstall() async {
                if (isDownloading) return;
                if (apkAssetId == null && (apkUrl == null || apkUrl.isEmpty)) {
                  if (await canLaunchUrl(Uri.parse(releaseUrl))) {
                    await launchUrl(
                      Uri.parse(releaseUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                  return;
                }

                setModalState(() {
                  isDownloading = true;
                  downloadProgress = null;
                  statusMessage = 'Starting APK download...';
                });

                final client = http.Client();
                try {
                  final repo = githubRepoPath.trim();
                  final targetUrl = apkAssetId != null
                      ? 'https://api.github.com/repos/$repo/releases/assets/$apkAssetId'
                      : apkUrl!;

                  final request = http.Request('GET', Uri.parse(targetUrl));
                  request.headers['User-Agent'] = 'my5top-app';
                  if (apkAssetId != null) {
                    request.headers['Accept'] = 'application/octet-stream';
                  }
                  if (githubToken.trim().isNotEmpty) {
                    request.headers['Authorization'] =
                        'Bearer ${githubToken.trim()}';
                  }

                  final streamedResponse = await client.send(request);
                  if (streamedResponse.statusCode != 200) {
                    throw Exception(
                      'GitHub returned HTTP ${streamedResponse.statusCode}',
                    );
                  }

                  final contentLength = streamedResponse.contentLength ?? 0;
                  final tempDir = await getTemporaryDirectory();
                  final safeFileName = (apkName != null && apkName.isNotEmpty)
                      ? apkName
                      : 'my5top-v$latestVersion.apk';
                  final file = File('${tempDir.path}/$safeFileName');
                  final sink = file.openWrite();

                  int receivedBytes = 0;
                  await for (final chunk in streamedResponse.stream) {
                    sink.add(chunk);
                    receivedBytes += chunk.length;
                    if (contentLength > 0 && ctx.mounted) {
                      setModalState(() {
                        downloadProgress = receivedBytes / contentLength;
                        final pct =
                            ((downloadProgress ?? 0) * 100).clamp(0, 100).toInt();
                        statusMessage = 'Downloading update... $pct%';
                      });
                    }
                  }

                  await sink.flush();
                  await sink.close();

                  if (ctx.mounted) {
                    setModalState(() {
                      isDownloading = false;
                      statusMessage = 'Opening Android package installer...';
                    });
                  }

                  await OpenFilex.open(
                    file.path,
                    type: 'application/vnd.android.package-archive',
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    setModalState(() {
                      isDownloading = false;
                      statusMessage = 'Download error: $e';
                    });
                  }
                } finally {
                  client.close();
                }
              }

              return Scaffold(
                backgroundColor: pal.scaffoldBg,
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 46,
                          color: pal.primaryAccent,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'New my5top Update Available!',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: pal.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'v$latestVersion • Current: v$appVersion',
                          style: TextStyle(
                            fontSize: 14,
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: pal.cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: pal.cardBorder),
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (releaseTitle.isNotEmpty) ...[
                                    Text(
                                      releaseTitle,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: pal.primaryAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  Text(
                                    releaseNotes.isNotEmpty
                                        ? releaseNotes
                                        : 'Commute tracking improvements and anime UI polish.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (isDownloading || statusMessage.isNotEmpty) ...[
                          if (isDownloading)
                            LinearProgressIndicator(
                              value: downloadProgress,
                              color: pal.primaryAccent,
                            ),
                          const SizedBox(height: 8),
                          Text(
                            statusMessage,
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.primaryAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: isDownloading ? null : startSeamlessInstall,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text(
                              'Download & Install APK',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: pal.primaryAccent,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(screenCtx).pop(),
                                child: const Text('Not now'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () async {
                                await setSkippedUpdateVersion(latestVersion);
                                if (screenCtx.mounted) {
                                  Navigator.of(screenCtx).pop();
                                }
                              },
                              child: const Text('Skip version'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
