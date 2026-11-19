import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/station.dart';
import '../models/train_trip.dart';

class _BoardTrainEntry {
  final String stationDvCode;
  final String trainId;
  final String departureDate;
  final String destination;
  final String line;
  final String lineAbbreviation;
  final String status;
  final String track;
  final String inlineMessage;
  final DateTime seenAtEastern;

  const _BoardTrainEntry({
    required this.stationDvCode,
    required this.trainId,
    required this.departureDate,
    required this.destination,
    required this.line,
    required this.lineAbbreviation,
    required this.status,
    required this.track,
    required this.inlineMessage,
    required this.seenAtEastern,
  });

  bool get isNec =>
      lineAbbreviation.toUpperCase() == 'NEC' ||
      line.toLowerCase().contains('northeast') ||
      line.toLowerCase().contains('corrdr');
}

class _CachedStopList {
  final List<TrainStop> stops;
  final DateTime fetchedAtUtc;

  const _CachedStopList({
    required this.stops,
    required this.fetchedAtUtc,
  });
}

class _LiveCorridorSnapshot {
  final DateTime fetchedAtUtc;
  final DateTime fetchedAtEastern;
  final Map<String, Map<String, _BoardTrainEntry>> boardsByDvCode;
  final Map<String, _BoardTrainEntry> metaByTrainId;
  final Map<String, List<TrainStop>> stopsByTrainId;

  const _LiveCorridorSnapshot({
    required this.fetchedAtUtc,
    required this.fetchedAtEastern,
    required this.boardsByDvCode,
    required this.metaByTrainId,
    required this.stopsByTrainId,
  });
}

class TrackWatchPollResult {
  final String trainId;
  final String? track;
  final String status;
  final String inlineMessage;
  final bool foundOnBoard;
  final bool rateLimited;
  final DateTime fetchedAtEastern;

  const TrackWatchPollResult({
    required this.trainId,
    required this.track,
    required this.status,
    required this.inlineMessage,
    required this.foundOnBoard,
    this.rateLimited = false,
    required this.fetchedAtEastern,
  });

  bool get hasTrack => track != null && track!.trim().isNotEmpty;
}

class NjtApiService {
  static const String _graphQlUrl =
      'https://www.njtransit.com/api/graphql/graphql';
  static const List<String> _railDataBaseUrls = [
    'https://raildata.njtransit.com/api/TrainData',
    'https://testraildata.njtransit.com/api/TrainData',
  ];

  /// Core NEC corridor stations spanning NY Penn <-> Trenton so every poll
  /// captures both Northbound (to NYC) and Southbound (to Trenton) trains,
  /// including en-route trains that already departed their origin terminal.
  static const List<String> _necCorridorDvBackbone = [
    'NY',
    'SE',
    'NP',
    'MP',
    'NB',
    'PJ',
    'TR',
  ];

  static final RegExp _numericTrainIdRegex = RegExp(r'^\d+$');

  static _LiveCorridorSnapshot? _latestLiveSnapshot;
  static final Map<String, _BoardTrainEntry> _recentTrainMetaCache = {};
  static final Map<String, _CachedStopList> _stopListCache = {};
  static String? _activeOfficialBaseUrl;

  static String formatTime12h(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minStr = dt.minute.toString().padLeft(2, '0');
    final amPm = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minStr $amPm';
  }

  static String formatTimeHms(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  static String formatDateAndTimeHms(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  /// Computes current US Eastern wall-clock time (`America/New_York`, EST/EDT)
  /// from [instant] (defaults to `DateTime.now()`) so NJ Transit timestamps
  /// are always compared in NJ/NY local time regardless of device timezone.
  static DateTime easternNow([DateTime? instant]) {
    final utc = (instant ?? DateTime.now()).toUtc();
    final year = utc.year;

    // 2nd Sunday in March at 07:00 UTC (2:00 AM EST)
    final march1Weekday = DateTime.utc(year, 3, 1).weekday; // 1=Mon..7=Sun
    final secondSundayMarch = 8 + ((7 - march1Weekday) % 7);
    final dstStartUtc = DateTime.utc(year, 3, secondSundayMarch, 7, 0);

    // 1st Sunday in November at 06:00 UTC (2:00 AM EDT)
    final nov1Weekday = DateTime.utc(year, 11, 1).weekday;
    final firstSundayNov = 1 + ((7 - nov1Weekday) % 7);
    final dstEndUtc = DateTime.utc(year, 11, firstSundayNov, 6, 0);

    final isEdt = !utc.isBefore(dstStartUtc) && utc.isBefore(dstEndUtc);
    final shifted = utc.subtract(Duration(hours: isEdt ? 4 : 5));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Converts an Eastern wall-clock [DateTime] (as returned by [easternNow] or
  /// [parseNjtTime]) into an exact UTC Unix timestamp in milliseconds.
  static int easternWallClockToEpochMs(DateTime easternWallClock) {
    final year = easternWallClock.year;
    final march1Weekday = DateTime.utc(year, 3, 1).weekday;
    final secondSundayMarch = 8 + ((7 - march1Weekday) % 7);
    final dstStartUtc = DateTime.utc(year, 3, secondSundayMarch, 7, 0);

    final nov1Weekday = DateTime.utc(year, 11, 1).weekday;
    final firstSundayNov = 1 + ((7 - nov1Weekday) % 7);
    final dstEndUtc = DateTime.utc(year, 11, firstSundayNov, 6, 0);

    final candidateEdtUtc = DateTime.utc(
      easternWallClock.year,
      easternWallClock.month,
      easternWallClock.day,
      easternWallClock.hour + 4,
      easternWallClock.minute,
      easternWallClock.second,
    );
    if (!candidateEdtUtc.isBefore(dstStartUtc) &&
        candidateEdtUtc.isBefore(dstEndUtc)) {
      return candidateEdtUtc.millisecondsSinceEpoch;
    }
    return DateTime.utc(
      easternWallClock.year,
      easternWallClock.month,
      easternWallClock.day,
      easternWallClock.hour + 5,
      easternWallClock.minute,
      easternWallClock.second,
    ).millisecondsSinceEpoch;
  }

  /// Parses NJ Transit 12-hour (`"11:37 AM"`) or ISO/timestamp strings into
  /// an Eastern wall-clock [DateTime] anchored near [referenceEasternNow].
  static DateTime? parseNjtTime(String raw, DateTime referenceEasternNow) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final amPmMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])',
    ).firstMatch(text);
    if (amPmMatch != null) {
      int hour = int.tryParse(amPmMatch.group(1)!) ?? 0;
      final int minute = int.tryParse(amPmMatch.group(2)!) ?? 0;
      final String meridiem = amPmMatch.group(3)!.toUpperCase();
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;

      DateTime candidate = DateTime(
        referenceEasternNow.year,
        referenceEasternNow.month,
        referenceEasternNow.day,
        hour,
        minute,
      );
      // Handle midnight wraparound (e.g., 11:50 PM polling 12:18 AM train,
      // or 12:10 AM viewing a 11:48 PM en-route train).
      final diffMinutes = candidate.difference(referenceEasternNow).inMinutes;
      if (diffMinutes < -720) {
        candidate = candidate.add(const Duration(days: 1));
      } else if (diffMinutes > 720) {
        candidate = candidate.subtract(const Duration(days: 1));
      }
      return candidate;
    }

    final parsed = DateTime.tryParse(text);
    return parsed;
  }

  /// Cleans HTML entities and NJT terminal suffixes (e.g., `"Trenton -SEC &#9992"` -> `"Trenton"`).
  static String cleanDestinationName(String raw) {
    String cleaned = raw
        .replaceAll(RegExp(r'&#\d+;?'), '')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s*-SEC\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'-BH\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'NJ Transit';
    final matched = findStationByNameOrCode(cleaned);
    if (matched != null) {
      if (matched.code == 'NY') return 'NY Penn Station';
      if (matched.code == 'TR') return 'Trenton';
      return matched.shortName;
    }
    if (cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  /// Formats NJ Transit status strings (`"BOARDING"`, `"OnTime"`, `"in 18 Min"`) cleanly.
  static String normalizeStatusText(
    String rawStatus, {
    String inlineMessage = '',
  }) {
    final s = rawStatus.trim();
    if (s.isEmpty) {
      if (inlineMessage.toLowerCase().contains('delay')) return 'Delayed';
      return 'On Time';
    }
    final upper = s.toUpperCase();
    if (upper == 'ONTIME' || upper == 'ON TIME') return 'On Time';
    if (upper == 'BOARDING') return 'Boarding';
    if (upper == 'ALL ABOARD') return 'All Aboard';
    if (upper == 'STAND BY') return 'Stand By';
    if (upper == 'CANCELLED' || upper == 'CANCELED') return 'Cancelled';
    if (upper == 'DELAYED') return 'Delayed';
    if (upper == 'DEPARTED') return 'Departed';

    final inMinMatch = RegExp(
      r'^in\s+(\d+)\s*min',
      caseSensitive: false,
    ).firstMatch(s);
    if (inMinMatch != null) {
      return 'In ${inMinMatch.group(1)} min';
    }
    return s;
  }

  /// Returns immediately projected live trips from the most recent bidirectional
  /// NEC corridor poll (if fresh within [maxAge]) without inverting directions.
  static List<TrainTrip>? getCachedLiveTrips({
    required String originCode,
    required String destinationCode,
    String? activeRideTrainId,
    Duration maxAge = const Duration(minutes: 15),
  }) {
    final snap = _latestLiveSnapshot;
    if (snap == null) return null;
    if (DateTime.now().toUtc().difference(snap.fetchedAtUtc) > maxAge) {
      return null;
    }
    final projected = _projectTripsFromSnapshot(
      snapshot: snap,
      originCode: originCode,
      destinationCode: destinationCode,
      nowEast: easternNow(),
      activeRideTrainId: activeRideTrainId,
    );
    return projected.isNotEmpty ? projected : null;
  }

  /// Clears in-memory corridor caches (useful in tests).
  static void clearLiveCaches() {
    _latestLiveSnapshot = null;
    _recentTrainMetaCache.clear();
    _stopListCache.clear();
  }

  /// Authenticates with the official free NJ Transit RailData API (`/getToken`).
  /// Tries production first and falls back to NJT's test RailData host if needed.
  static Future<String?> fetchOfficialToken({
    required String username,
    required String password,
    http.Client? httpClient,
  }) async {
    if (username.trim().isEmpty || password.trim().isEmpty) return null;
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    try {
      for (final baseUrl in _railDataBaseUrls) {
        try {
          final uri = Uri.parse('$baseUrl/getToken');
          final req = http.MultipartRequest('POST', uri)
            ..fields['username'] = username.trim()
            ..fields['password'] = password.trim();
          final streamed =
              await client.send(req).timeout(const Duration(seconds: 8));
          final resp = await http.Response.fromStream(streamed)
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final decoded = json.decode(resp.body);
            if (decoded is Map && decoded['UserToken'] != null) {
              final token = decoded['UserToken'].toString().trim();
              if (token.isNotEmpty && decoded['Authenticated'] != 'False') {
                _activeOfficialBaseUrl = baseUrl;
                return token;
              }
            }
          }
        } catch (_) {}
      }
    } finally {
      if (shouldClose) client.close();
    }
    return null;
  }

  /// Polls live NJ Transit trains in both NEC directions (to NYC and to Trenton)
  /// and returns the accurate schedule for [originCode] -> [destinationCode].
  ///
  /// Priority order:
  /// 1. Live NJ Transit DepartureVision GraphQL corridor poll (batches NY Penn,
  ///    Secaucus, Newark Penn, Metropark, New Brunswick, Princeton Jct, Trenton,
  ///    plus [originCode] & [destinationCode] in one poll so Northbound-to-NYC
  ///    and Southbound-to-Trenton trains are always up to date).
  /// 2. Official NJ Transit RailData API (`getTrainSchedule`) if configured.
  /// 3. Recent cached live corridor snapshot (<20 min old) during brief tunnel dropouts.
  /// 4. Offline schedule fallback only when completely unreachable.
  static Future<List<TrainTrip>> fetchUpcomingTrains({
    required String originCode,
    required String destinationCode,
    String? cachedToken,
    bool forceRefresh = false,
    String? watchedTrainId,
    String? activeRideTrainId,
    http.Client? httpClient,
    DateTime? referenceNow,
  }) async {
    // 1. Primary: Poll live bidirectional NEC DepartureVision GraphQL boards & stop lists
    final liveGraphQl = await pollBidirectionalCorridorGraphQl(
      originCode: originCode,
      destinationCode: destinationCode,
      forceRefresh: forceRefresh,
      watchedTrainId: watchedTrainId,
      activeRideTrainId: activeRideTrainId,
      httpClient: httpClient,
      referenceNow: referenceNow,
    );
    if (liveGraphQl.isNotEmpty) {
      return liveGraphQl;
    }

    // 2. Optional Official NJT RailData API (`getTrainSchedule` with STOPS) if token configured
    if (cachedToken != null && cachedToken.trim().isNotEmpty) {
      final official = await _fetchFromOfficialApi(
        token: cachedToken.trim(),
        originCode: originCode,
        destinationCode: destinationCode,
        httpClient: httpClient,
        referenceNow: referenceNow,
      );
      if (official.isNotEmpty) {
        return official;
      }
    }

    // 3. Recent live bidirectional corridor snapshot (e.g., momentary tunnel dropout)
    final cachedLive = getCachedLiveTrips(
      originCode: originCode,
      destinationCode: destinationCode,
      activeRideTrainId: activeRideTrainId,
      maxAge: const Duration(minutes: 20),
    );
    if (cachedLive != null && cachedLive.isNotEmpty) {
      return cachedLive
          .map((t) => t.copyWith(dataSource: 'NJT Live (Cached)'))
          .toList();
    }

    // 4. Last-resort offline fallback
    return generateSmartSchedule(
      originCode: originCode,
      destinationCode: destinationCode,
      now: referenceNow ?? DateTime.now(),
    );
  }

  /// Polls NJ Transit's public DepartureVision GraphQL API across the Northeast
  /// Corridor in BOTH directions (Northbound to NYC & Southbound to Trenton),
  /// caches the full bidirectional snapshot, and projects accurate trips for
  /// [originCode] -> [destinationCode].
  static Future<List<TrainTrip>> pollBidirectionalCorridorGraphQl({
    required String originCode,
    required String destinationCode,
    bool forceRefresh = false,
    String? watchedTrainId,
    String? activeRideTrainId,
    http.Client? httpClient,
    DateTime? referenceNow,
  }) async {
    final orig = getStationByCode(originCode);
    final dest = getStationByCode(destinationCode);
    if (orig.code == dest.code) return const [];

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    final nowUtc = (referenceNow ?? DateTime.now()).toUtc();
    final nowEast = easternNow(nowUtc);

    try {
      // Step A: Build deduplicated station set covering the entire NEC corridor
      // (NY <-> TR) plus the active origin and destination stations.
      final Set<String> stationDvCodes = {
        ..._necCorridorDvBackbone,
        orig.dvCode.toUpperCase(),
        dest.dvCode.toUpperCase(),
      };

      final StringBuffer boardQueryBuf = StringBuffer('query { ');
      for (final dv in stationDvCodes) {
        final safeAlias = 'b_${dv.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';
        boardQueryBuf.write(
          '$safeAlias: getTrainDepartureScreens(station: "$dv") { '
          'items { trainID departureDate destination line lineAbbreviation status track inlineMessage } '
          '} ',
        );
      }
      boardQueryBuf.write('}');

      final boardResp = await client
          .post(
            Uri.parse(_graphQlUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'query': boardQueryBuf.toString()}),
          )
          .timeout(const Duration(seconds: 7));

      if (boardResp.statusCode != 200) return const [];
      final boardDecoded = json.decode(boardResp.body);
      if (boardDecoded is! Map || boardDecoded['data'] is! Map) {
        return const [];
      }
      final Map<String, dynamic> boardData =
          Map<String, dynamic>.from(boardDecoded['data'] as Map);

      final Map<String, Map<String, _BoardTrainEntry>> boardsByDvCode = {};
      final Map<String, _BoardTrainEntry> currentMetaByTrainId = {};

      for (final dv in stationDvCodes) {
        final safeAlias = 'b_${dv.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';
        final stationNode = boardData[safeAlias];
        final Map<String, _BoardTrainEntry> stationMap = {};
        if (stationNode is Map && stationNode['items'] is List) {
          for (final rawItem in (stationNode['items'] as List)) {
            if (rawItem is! Map) continue;
            final m = Map<String, dynamic>.from(rawItem);
            final trainId = (m['trainID'] ?? '').toString().trim();
            // Keep NJ Transit numbered trains (exclude Amtrak 'A...' & SEPTA 'S...')
            if (trainId.isEmpty || !_numericTrainIdRegex.hasMatch(trainId)) {
              continue;
            }
            final entry = _BoardTrainEntry(
              stationDvCode: dv,
              trainId: trainId,
              departureDate: (m['departureDate'] ?? '').toString().trim(),
              destination: (m['destination'] ?? '').toString().trim(),
              line: (m['line'] ?? '').toString().trim(),
              lineAbbreviation: (m['lineAbbreviation'] ?? '').toString().trim(),
              status: (m['status'] ?? '').toString().trim(),
              track: (m['track'] ?? '').toString().trim(),
              inlineMessage: (m['inlineMessage'] ?? '').toString().trim(),
              seenAtEastern: nowEast,
            );
            stationMap[trainId] = entry;

            // Prefer metadata from origin board if available, else keep first non-empty
            final existing = currentMetaByTrainId[trainId];
            if (existing == null || dv == orig.dvCode.toUpperCase()) {
              currentMetaByTrainId[trainId] = entry;
            }
          }
        }
        boardsByDvCode[dv] = stationMap;
      }

      if (currentMetaByTrainId.isEmpty && _recentTrainMetaCache.isEmpty) {
        return const [];
      }

      // Prune rolling cache entries older than 60 minutes and merge fresh sightings
      _recentTrainMetaCache.removeWhere(
        (_, meta) => nowEast.difference(meta.seenAtEastern).inMinutes.abs() > 60,
      );
      for (final e in currentMetaByTrainId.entries) {
        if (e.value.isNec ||
            boardsByDvCode[orig.dvCode]?.containsKey(e.key) == true ||
            boardsByDvCode[dest.dvCode]?.containsKey(e.key) == true) {
          _recentTrainMetaCache[e.key] = e.value;
        }
      }

      // Step B: Select candidate trains covering BOTH NEC directions (to NYC & to Trenton)
      // plus any direct trains between non-NEC/shared stations.
      final origBoard = boardsByDvCode[orig.dvCode.toUpperCase()] ?? const {};
      final destBoard = boardsByDvCode[dest.dvCode.toUpperCase()] ?? const {};
      final bool nonNecSelected = orig.necOrder >= 100 || dest.necOrder >= 100;

      final Set<String> candidateIds = {};
      for (final entry in currentMetaByTrainId.values) {
        final id = entry.trainId;
        final onBothSelected =
            origBoard.containsKey(id) && destBoard.containsKey(id);
        final onEitherSelected =
            origBoard.containsKey(id) || destBoard.containsKey(id);
        if (entry.isNec ||
            onBothSelected ||
            (nonNecSelected && onEitherSelected)) {
          candidateIds.add(id);
        }
      }

      // Also include recently seen NEC trains (e.g., Northbound train between
      // Secaucus and NY Penn tunnel) so "Just Departed" stays accurate.
      for (final entry in _recentTrainMetaCache.entries) {
        candidateIds.add(entry.key);
      }
      if (watchedTrainId != null && _numericTrainIdRegex.hasMatch(watchedTrainId)) {
        candidateIds.add(watchedTrainId);
      }
      if (activeRideTrainId != null &&
          _numericTrainIdRegex.hasMatch(activeRideTrainId)) {
        candidateIds.add(activeRideTrainId);
      }

      // Prioritize trains on origin/destination boards & chronologically closest trains
      final List<String> orderedCandidates = candidateIds.toList()
        ..sort((a, b) {
          final aPriority = (a == activeRideTrainId || a == watchedTrainId)
              ? 0
              : (origBoard.containsKey(a) || destBoard.containsKey(a) ? 1 : 2);
          final bPriority = (b == activeRideTrainId || b == watchedTrainId)
              ? 0
              : (origBoard.containsKey(b) || destBoard.containsKey(b) ? 1 : 2);
          if (aPriority != bPriority) return aPriority.compareTo(bPriority);

          final aMeta = currentMetaByTrainId[a] ?? _recentTrainMetaCache[a];
          final bMeta = currentMetaByTrainId[b] ?? _recentTrainMetaCache[b];
          final aDt = aMeta != null
              ? parseNjtTime(aMeta.departureDate, nowEast)
              : null;
          final bDt = bMeta != null
              ? parseNjtTime(bMeta.departureDate, nowEast)
              : null;
          final aDiff =
              aDt != null ? aDt.difference(nowEast).inMinutes.abs() : 999;
          final bDiff =
              bDt != null ? bDt.difference(nowEast).inMinutes.abs() : 999;
          return aDiff.compareTo(bDiff);
        });

      final List<String> cappedCandidates =
          orderedCandidates.take(32).toList();

      // Determine which trains need fresh stop lists vs recent (<25s) stop-list cache
      final List<String> idsToQueryStops = [];
      for (final id in cappedCandidates) {
        if (forceRefresh ||
            id == watchedTrainId ||
            id == activeRideTrainId) {
          idsToQueryStops.add(id);
          continue;
        }
        final cached = _stopListCache[id];
        if (cached == null ||
            nowUtc.difference(cached.fetchedAtUtc).inSeconds >= 25) {
          idsToQueryStops.add(id);
          continue;
        }
        // Always refresh stop lists for imminent or en-route trains (<25 min window)
        final meta = currentMetaByTrainId[id] ?? _recentTrainMetaCache[id];
        final dt =
            meta != null ? parseNjtTime(meta.departureDate, nowEast) : null;
        if (dt == null || dt.difference(nowEast).inMinutes.abs() <= 25) {
          idsToQueryStops.add(id);
        }
      }

      if (idsToQueryStops.isNotEmpty) {
        final StringBuffer stopsQueryBuf = StringBuffer('query { ');
        for (final id in idsToQueryStops) {
          stopsQueryBuf.write(
            't_$id: getTrainStopList(train: "$id") { name time departed status } ',
          );
        }
        stopsQueryBuf.write('}');

        final stopsResp = await client
            .post(
              Uri.parse(_graphQlUrl),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: json.encode({'query': stopsQueryBuf.toString()}),
            )
            .timeout(const Duration(seconds: 7));

        if (stopsResp.statusCode == 200) {
          final stopsDecoded = json.decode(stopsResp.body);
          if (stopsDecoded is Map && stopsDecoded['data'] is Map) {
            final Map<String, dynamic> stopsData =
                Map<String, dynamic>.from(stopsDecoded['data'] as Map);
            for (final id in idsToQueryStops) {
              final rawList = stopsData['t_$id'];
              if (rawList is List && rawList.isNotEmpty) {
                final parsed = _parseGraphQlStopList(rawList);
                if (parsed.isNotEmpty) {
                  _stopListCache[id] = _CachedStopList(
                    stops: parsed,
                    fetchedAtUtc: nowUtc,
                  );
                }
              }
            }
          }
        }
      }

      // Prune stale stop-list cache entries older than 90 minutes
      _stopListCache.removeWhere(
        (_, v) => nowUtc.difference(v.fetchedAtUtc).inMinutes > 90,
      );

      final Map<String, List<TrainStop>> snapshotStops = {};
      final Map<String, _BoardTrainEntry> snapshotMeta = {
        ..._recentTrainMetaCache,
        ...currentMetaByTrainId,
      };
      for (final id in cappedCandidates) {
        final cached = _stopListCache[id];
        if (cached != null && cached.stops.isNotEmpty) {
          snapshotStops[id] = cached.stops;
        }
      }

      final snapshot = _LiveCorridorSnapshot(
        fetchedAtUtc: nowUtc,
        fetchedAtEastern: nowEast,
        boardsByDvCode: boardsByDvCode,
        metaByTrainId: snapshotMeta,
        stopsByTrainId: snapshotStops,
      );
      _latestLiveSnapshot = snapshot;

      return _projectTripsFromSnapshot(
        snapshot: snapshot,
        originCode: orig.code,
        destinationCode: dest.code,
        nowEast: nowEast,
        activeRideTrainId: activeRideTrainId,
      );
    } catch (_) {
      return const [];
    } finally {
      if (shouldClose) client.close();
    }
  }

  /// Ultra-lightweight single-station DepartureVision GraphQL query used during
  /// the 1-second Track Watch burst window (11m–9m before departure, or extended
  /// during delays/non-routine statuses). Queries only [originCode]'s board
  /// without fetching stop lists, keeping payload & latency minimal.
  static Future<TrackWatchPollResult?> pollSingleTrainTrackFast({
    required String originCode,
    required String trainId,
    http.Client? httpClient,
    DateTime? referenceNow,
  }) async {
    final orig = getStationByCode(originCode);
    final dv = orig.dvCode.toUpperCase();
    final targetId = trainId.trim();
    if (targetId.isEmpty) return null;

    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    final nowEast = easternNow(referenceNow);

    try {
      final query =
          'query { board: getTrainDepartureScreens(station: "$dv") { '
          'items { trainID status track inlineMessage } '
          '} }';

      final resp = await client
          .post(
            Uri.parse(_graphQlUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'query': query}),
          )
          .timeout(const Duration(seconds: 4));

      if (resp.statusCode == 429 || resp.statusCode == 503) {
        return TrackWatchPollResult(
          trainId: targetId,
          track: null,
          status: '',
          inlineMessage: '',
          foundOnBoard: false,
          rateLimited: true,
          fetchedAtEastern: nowEast,
        );
      }
      if (resp.statusCode != 200) return null;

      final decoded = json.decode(resp.body);
      if (decoded is! Map || decoded['data'] is! Map) return null;
      final board = (decoded['data'] as Map)['board'];
      if (board is! Map || board['items'] is! List) return null;

      for (final rawItem in (board['items'] as List)) {
        if (rawItem is! Map) continue;
        final id = (rawItem['trainID'] ?? '').toString().trim();
        if (id != targetId) continue;

        final rawTrack = (rawItem['track'] ?? '').toString().trim();
        final rawStatus = (rawItem['status'] ?? '').toString().trim();
        final inlineMsg = (rawItem['inlineMessage'] ?? '').toString().trim();
        return TrackWatchPollResult(
          trainId: targetId,
          track: rawTrack.isEmpty ? null : rawTrack,
          status: normalizeStatusText(rawStatus, inlineMessage: inlineMsg),
          inlineMessage: inlineMsg,
          foundOnBoard: true,
          fetchedAtEastern: nowEast,
        );
      }

      return TrackWatchPollResult(
        trainId: targetId,
        track: null,
        status: '',
        inlineMessage: '',
        foundOnBoard: false,
        fetchedAtEastern: nowEast,
      );
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }

  static List<TrainStop> _parseGraphQlStopList(List rawStops) {
    final List<TrainStop> result = [];
    for (final rs in rawStops) {
      if (rs is! Map) continue;
      final m = Map<String, dynamic>.from(rs);
      final rawName = (m['name'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;

      final matched = findStationByNameOrCode(rawName);
      final code = matched?.code ?? _fallbackStationCode(rawName);
      final stopTime = (m['time'] ?? '').toString().trim();
      final departed = m['departed'] == true;
      final rawStopStatus = (m['status'] ?? '').toString().trim();

      result.add(
        TrainStop(
          stationCode: code,
          stationName: matched?.name ?? rawName,
          scheduledTime: stopTime,
          estimatedTime: stopTime,
          departed: departed,
          stopStatus: normalizeStatusText(rawStopStatus),
          latitude: matched?.latitude ?? 40.65,
          longitude: matched?.longitude ?? -74.25,
        ),
      );
    }
    return result;
  }

  static String _fallbackStationCode(String rawName) {
    final letters =
        rawName.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    if (letters.length >= 2) return letters.substring(0, 2);
    return 'ST';
  }

  static List<TrainTrip> _projectTripsFromSnapshot({
    required _LiveCorridorSnapshot snapshot,
    required String originCode,
    required String destinationCode,
    required DateTime nowEast,
    String? activeRideTrainId,
  }) {
    final orig = getStationByCode(originCode);
    final dest = getStationByCode(destinationCode);
    final origBoard =
        snapshot.boardsByDvCode[orig.dvCode.toUpperCase()] ?? const {};
    final destBoard =
        snapshot.boardsByDvCode[dest.dvCode.toUpperCase()] ?? const {};

    final List<TrainTrip> upcoming = [];
    final List<TrainTrip> recentPast = [];

    for (final entry in snapshot.stopsByTrainId.entries) {
      final trainId = entry.key;
      final rawStops = entry.value;
      if (rawStops.length < 2) continue;

      final origIdx = rawStops.indexWhere(
        (s) => s.stationCode.toUpperCase() == orig.code.toUpperCase(),
      );
      final destIdx = rawStops.indexWhere(
        (s) => s.stationCode.toUpperCase() == dest.code.toUpperCase(),
      );

      // Strict directionality check: train MUST stop at origin first and destination after!
      // Northbound trains (TR -> MP -> NY) have MP < NY; Southbound trains (NY -> MP -> TR) have NY < MP.
      if (origIdx == -1 || destIdx == -1 || origIdx >= destIdx) {
        continue;
      }

      // Skip trains that have already completed/departed the destination station
      // (unless this is the user's actively tracked ride).
      if (rawStops[destIdx].departed && trainId != activeRideTrainId) {
        continue;
      }

      final origBoardItem = origBoard[trainId];
      final destBoardItem = destBoard[trainId];
      final fallbackMeta = snapshot.metaByTrainId[trainId];

      final String origBoardStatusUpper =
          (origBoardItem?.status ?? '').trim().toUpperCase();
      final bool onOrigBoardAndNotDeparted =
          origBoardItem != null && !origBoardStatusUpper.contains('DEPART');

      final String depTimeStr = (origBoardItem != null &&
              origBoardItem.departureDate.isNotEmpty)
          ? origBoardItem.departureDate
          : rawStops[origIdx].scheduledTime;
      final String arrTimeStr = rawStops[destIdx].estimatedTime.isNotEmpty
          ? rawStops[destIdx].estimatedTime
          : (destBoardItem?.departureDate ?? depTimeStr);

      final DateTime? depDt = parseNjtTime(depTimeStr, nowEast);
      DateTime? arrDt = parseNjtTime(arrTimeStr, depDt ?? nowEast);
      if (depDt != null && arrDt != null && arrDt.isBefore(depDt)) {
        arrDt = arrDt.add(const Duration(days: 1));
      }

      bool isPastDeparture = false;
      if (onOrigBoardAndNotDeparted) {
        isPastDeparture = false;
      } else if (rawStops[origIdx].departed) {
        isPastDeparture = true;
      } else if (depDt != null &&
          depDt.isBefore(nowEast.subtract(const Duration(minutes: 3)))) {
        isPastDeparture = true;
      }

      // Filter out stale en-route records if departure was >110m ago and no live board shows it
      if (isPastDeparture &&
          depDt != null &&
          nowEast.difference(depDt).inMinutes > 110 &&
          destBoardItem == null &&
          trainId != activeRideTrainId) {
        continue;
      }

      // Normalize origin stop departed flag when train is still actively BOARDING at origin
      final List<TrainStop> normalizedStops = List<TrainStop>.from(rawStops);
      if (!isPastDeparture && normalizedStops[origIdx].departed) {
        normalizedStops[origIdx] =
            normalizedStops[origIdx].copyWith(departed: false);
      }

      // Track number MUST come strictly from the origin station's departure board
      final String? originTrack =
          (origBoardItem != null && origBoardItem.track.isNotEmpty)
              ? origBoardItem.track
              : null;

      // Build clear live status for both Upcoming and Just Departed (En Route) trains
      String displayStatus;
      if (!isPastDeparture) {
        displayStatus = normalizeStatusText(
          origBoardItem?.status ?? normalizedStops[origIdx].stopStatus,
          inlineMessage: origBoardItem?.inlineMessage ?? '',
        );
      } else {
        TrainStop? nextUnpassed;
        for (int i = origIdx + 1; i <= destIdx; i++) {
          if (!normalizedStops[i].departed) {
            nextUnpassed = normalizedStops[i];
            break;
          }
        }
        final destStatusRaw = destBoardItem?.status ?? '';
        final isDelayed = destStatusRaw.toUpperCase().contains('DELAY') ||
            normalizedStops[destIdx].stopStatus.toLowerCase().contains('delay');
        if (nextUnpassed != null) {
          final nextStation = getStationByCode(nextUnpassed.stationCode);
          final nextLabel = nextUnpassed.stationCode.toUpperCase() ==
                  dest.code.toUpperCase()
              ? 'Approaching ${dest.shortName}'
              : 'En Route → ${nextStation.shortName}';
          displayStatus = isDelayed ? 'Delayed • $nextLabel' : nextLabel;
        } else {
          displayStatus = isDelayed ? 'Delayed • En Route' : 'En Route';
        }
      }

      final int stopCount = destIdx - origIdx;
      final int corridorSpan =
          (orig.necOrder < 100 && dest.necOrder < 100)
              ? (orig.necOrder - dest.necOrder).abs()
              : stopCount;
      final bool isExpress =
          stopCount <= 4 || (corridorSpan > 4 && stopCount < corridorSpan);

      final int durationMins = (depDt != null && arrDt != null)
          ? arrDt.difference(depDt).inMinutes.clamp(1, 240)
          : (stopCount * (isExpress ? 7 : 5)).clamp(5, 180);

      final String rawLine =
          origBoardItem?.line ?? fallbackMeta?.line ?? 'Northeast Corridor';
      final String rawLineAbbr = origBoardItem?.lineAbbreviation ??
          fallbackMeta?.lineAbbreviation ??
          'NEC';
      final String rawFinalDest = origBoardItem?.destination ??
          destBoardItem?.destination ??
          fallbackMeta?.destination ??
          normalizedStops.last.stationName;

      final trip = TrainTrip(
        trainId: trainId,
        line: rawLine.isEmpty ? 'Northeast Corridor' : rawLine,
        lineBadge: rawLineAbbr.isEmpty
            ? (isExpress ? 'NEC EXPRESS' : 'NEC LOCAL')
            : rawLineAbbr.toUpperCase(),
        originCode: orig.code,
        destinationCode: dest.code,
        finalDestinationName: cleanDestinationName(rawFinalDest),
        departureTime: depTimeStr,
        arrivalTime: arrTimeStr,
        departureDateTime: depDt,
        durationMinutes: durationMins,
        status: displayStatus,
        track: originTrack,
        isExpress: isExpress,
        isRecentPastDeparture: isPastDeparture,
        dataSource: 'NJT DepartureVision Live',
        stops: normalizedStops,
      );

      if (isPastDeparture) {
        recentPast.add(trip);
      } else {
        upcoming.add(trip);
      }
    }

    upcoming.sort((a, b) {
      final aDt = a.departureDateTime;
      final bDt = b.departureDateTime;
      if (aDt == null && bDt == null) return a.trainId.compareTo(b.trainId);
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return aDt.compareTo(bDt);
    });

    recentPast.sort((a, b) {
      final aDt = a.departureDateTime;
      final bDt = b.departureDateTime;
      if (aDt == null && bDt == null) return b.trainId.compareTo(a.trainId);
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return bDt.compareTo(aDt); // Most recently departed first
    });

    return [
      ...upcoming,
      ...recentPast.take(4),
    ];
  }

  /// Queries Official NJ Transit RailData `getTrainSchedule` (which includes full `STOPS`)
  /// and strictly enforces `origIdx < destIdx` so opposite-direction trains never leak.
  static Future<List<TrainTrip>> _fetchFromOfficialApi({
    required String token,
    required String originCode,
    required String destinationCode,
    http.Client? httpClient,
    DateTime? referenceNow,
  }) async {
    final origStation = getStationByCode(originCode);
    final destStation = getStationByCode(destinationCode);
    final nowEast = easternNow(referenceNow);
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;

    final List<String> candidateBases = [
      if (_activeOfficialBaseUrl != null) _activeOfficialBaseUrl!,
      ..._railDataBaseUrls.where((u) => u != _activeOfficialBaseUrl),
    ];

    try {
      for (final baseUrl in candidateBases) {
        try {
          final uri = Uri.parse('$baseUrl/getTrainSchedule');
          final req = http.MultipartRequest('POST', uri)
            ..fields['token'] = token
            ..fields['station'] = origStation.dvCode.toUpperCase()
            ..fields['NJTOnly'] = 'true';

          final streamed =
              await client.send(req).timeout(const Duration(seconds: 8));
          final resp = await http.Response.fromStream(streamed)
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) continue;

          final decoded = json.decode(resp.body);
          List rawItems = const [];
          if (decoded is Map && decoded['ITEMS'] is List) {
            rawItems = decoded['ITEMS'] as List;
          } else if (decoded is List) {
            rawItems = decoded;
          }
          if (rawItems.isEmpty) continue;

          final List<TrainTrip> results = [];

          for (final raw in rawItems) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final trainId =
                (item['TRAIN_ID'] ?? item['train_id'] ?? '').toString().trim();
            if (trainId.isEmpty || !_numericTrainIdRegex.hasMatch(trainId)) {
              continue;
            }

            final rawTrack =
                (item['TRACK'] ?? item['track'] ?? '').toString().trim();
            final rawStatus =
                (item['STATUS'] ?? item['status'] ?? '').toString().trim();
            final depTimeRaw =
                (item['SCHED_DEP_DATE'] ?? item['DEP_TIME'] ?? '')
                    .toString()
                    .trim();
            final lineName =
                (item['LINE'] ?? 'Northeast Corridor').toString().trim();
            final finalDest =
                (item['DESTINATION'] ?? '').toString().trim();

            final List<TrainStop> parsedStops = [];
            final rawStops = item['STOPS'] ?? item['stops'];
            if (rawStops is List) {
              for (final rs in rawStops) {
                if (rs is! Map) continue;
                final sm = Map<String, dynamic>.from(rs);
                final stopNameOrCode = (sm['STATION_2CHAR'] ??
                        sm['STATION'] ??
                        sm['station'] ??
                        '')
                    .toString()
                    .trim();
                final matchedStation = findStationByNameOrCode(stopNameOrCode);
                final code =
                    matchedStation?.code ?? _fallbackStationCode(stopNameOrCode);
                final stopTime =
                    (sm['TIME'] ?? sm['DEP_TIME'] ?? '').toString().trim();
                final departedStr = (sm['DEPARTED'] ?? sm['departed'] ?? 'NO')
                    .toString()
                    .toUpperCase();
                final isDeparted =
                    departedStr == 'YES' || departedStr == 'TRUE';
                final sStatus =
                    (sm['STOP_STATUS'] ?? '').toString().trim();

                final dtStop = parseNjtTime(stopTime, nowEast);
                final formattedStopTime =
                    dtStop != null ? formatTime12h(dtStop) : stopTime;

                parsedStops.add(
                  TrainStop(
                    stationCode: code,
                    stationName: matchedStation?.name ?? stopNameOrCode,
                    scheduledTime: formattedStopTime,
                    estimatedTime: formattedStopTime,
                    departed: isDeparted,
                    stopStatus: normalizeStatusText(sStatus),
                    latitude:
                        matchedStation?.latitude ?? origStation.latitude,
                    longitude:
                        matchedStation?.longitude ?? origStation.longitude,
                  ),
                );
              }
            }

            final origIdx = parsedStops.indexWhere(
              (s) =>
                  s.stationCode.toUpperCase() ==
                  origStation.code.toUpperCase(),
            );
            final destIdx = parsedStops.indexWhere(
              (s) =>
                  s.stationCode.toUpperCase() ==
                  destStation.code.toUpperCase(),
            );

            if (origIdx == -1 || destIdx == -1 || origIdx >= destIdx) {
              continue;
            }
            if (parsedStops[destIdx].departed) continue;

            final depDt = parseNjtTime(depTimeRaw, nowEast) ??
                parseNjtTime(parsedStops[origIdx].scheduledTime, nowEast);
            final arrDt =
                parseNjtTime(parsedStops[destIdx].estimatedTime, depDt ?? nowEast);
            final formattedDep = depDt != null
                ? formatTime12h(depDt)
                : parsedStops[origIdx].scheduledTime;
            final formattedArr = arrDt != null
                ? formatTime12h(arrDt)
                : parsedStops[destIdx].estimatedTime;

            final stopCount = destIdx - origIdx;
            final isExpress = stopCount <= 4;
            final durationMins = (depDt != null && arrDt != null)
                ? arrDt.difference(depDt).inMinutes.clamp(1, 240)
                : (isExpress ? 34 : 44);

            results.add(
              TrainTrip(
                trainId: trainId,
                line: lineName,
                lineBadge:
                    lineName.toLowerCase().contains('coast') ? 'NJCL' : 'NEC',
                originCode: origStation.code,
                destinationCode: destStation.code,
                finalDestinationName: cleanDestinationName(finalDest),
                departureTime: formattedDep,
                arrivalTime: formattedArr,
                departureDateTime: depDt,
                durationMinutes: durationMins,
                status: normalizeStatusText(rawStatus),
                track: rawTrack.isEmpty ? null : rawTrack,
                isExpress: isExpress,
                isRecentPastDeparture: parsedStops[origIdx].departed,
                dataSource: 'NJT RailData API',
                stops: parsedStops,
              ),
            );
          }

          if (results.isNotEmpty) {
            _activeOfficialBaseUrl = baseUrl;
            return results;
          }
        } catch (_) {}
      }
    } finally {
      if (shouldClose) client.close();
    }
    return const [];
  }

  /// Generates realistic, direction-specific offline fallback Northeast Corridor / NJT
  /// trains between [originCode] and [destinationCode] when no network connection is available.
  static List<TrainTrip> generateSmartSchedule({
    required String originCode,
    required String destinationCode,
    required DateTime now,
  }) {
    final orig = getStationByCode(originCode);
    final dest = getStationByCode(destinationCode);

    // Build ordered station chain between origin and destination along NEC
    List<Station> fullChain = [];
    final necStations = kNjtStations.where((s) => s.necOrder < 100).toList()
      ..sort((a, b) => a.necOrder.compareTo(b.necOrder));

    if (orig.necOrder < 100 && dest.necOrder < 100 && orig.code != dest.code) {
      if (orig.necOrder < dest.necOrder) {
        // Southbound (toward Trenton)
        fullChain = necStations
            .where(
              (s) =>
                  s.necOrder >= orig.necOrder && s.necOrder <= dest.necOrder,
            )
            .toList();
      } else {
        // Northbound (toward NY Penn)
        fullChain = necStations
            .where(
              (s) =>
                  s.necOrder <= orig.necOrder && s.necOrder >= dest.necOrder,
            )
            .toList()
            .reversed
            .toList();
      }
    } else {
      fullChain = [orig, getStationByCode('SE'), getStationByCode('NP'), dest]
          .fold<List<Station>>([], (acc, s) {
        if (acc.every((x) => x.code != s.code)) acc.add(s);
        return acc;
      });
    }

    final bool southbound = orig.necOrder <= dest.necOrder;
    final String finalTerm = southbound ? 'Trenton' : 'NY Penn Station';

    // Distinct directional headways so offline Southbound & Northbound schedules
    // are never simple inversions of each other.
    final offsets = southbound
        ? [6, 16, 28, 42, 58, 75, -5, -14, -24]
        : [4, 13, 25, 39, 54, 71, -3, -11, -21];
    final trainIds = southbound
        ? ['3941', '3843', '3725', '3945', '3847', '3849', '3939', '3837', '3721']
        : ['3840', '3914', '3842', '3712', '3844', '3846', '3838', '3836', '3710'];
    final expressFlags = [
      true,
      false,
      true,
      true,
      false,
      false,
      true,
      false,
      true,
    ];
    final tracks = southbound
        ? ['9', '7', null, null, null, null, '11', '8', '10']
        : ['1', '1', '1', null, null, null, '1', '1', '2'];
    final statuses = southbound
        ? [
            'Boarding',
            'On Time',
            'Track TBA',
            'On Time',
            'Delayed 3m',
            'On Time',
            'Departed 5m ago',
            'Departed 14m ago',
            'Departed 24m ago',
          ]
        : [
            'On Time',
            'On Time',
            'On Time',
            'Track TBA',
            'On Time',
            'On Time',
            'En Route',
            'En Route',
            'En Route',
          ];

    final List<TrainTrip> trips = [];

    for (int i = 0; i < offsets.length; i++) {
      final isExp = expressFlags[i];
      final offsetMins = offsets[i];
      final isPast = offsetMins < 0;
      final depDt = now.add(Duration(minutes: offsetMins));

      List<Station> stopStations;
      if (isExp && fullChain.length > 4) {
        const expressCoreCodes = {
          'NY',
          'SE',
          'NP',
          'NA',
          'RA',
          'MP',
          'NB',
          'PJ',
          'TR',
        };
        stopStations = fullChain.where((s) {
          if (s.code == orig.code || s.code == dest.code) return true;
          if ((i == 0 || i == 6) && (s.code == 'NA' || s.code == 'RA')) {
            return false;
          }
          return expressCoreCodes.contains(s.code);
        }).toList();
      } else {
        stopStations = List<Station>.from(fullChain);
      }

      final int minsPerStop = isExp ? 8 : 5;
      final List<TrainStop> trainStops = [];
      for (int sIdx = 0; sIdx < stopStations.length; sIdx++) {
        final st = stopStations[sIdx];
        final stopDt = depDt.add(Duration(minutes: sIdx * minsPerStop));
        final formattedTime = formatTime12h(stopDt);
        final hasStopDeparted = stopDt.isBefore(now);
        trainStops.add(
          TrainStop(
            stationCode: st.code,
            stationName: st.name,
            scheduledTime: formattedTime,
            estimatedTime: formattedTime,
            departed: hasStopDeparted,
            stopStatus: hasStopDeparted
                ? 'Departed'
                : (statuses[i] == 'Delayed 3m' ? 'Late 3m' : 'On Time'),
            latitude: st.latitude,
            longitude: st.longitude,
          ),
        );
      }

      final arrDt = depDt.add(
        Duration(minutes: (stopStations.length - 1) * minsPerStop),
      );
      final totalDuration = (stopStations.length - 1) * minsPerStop;

      trips.add(
        TrainTrip(
          trainId: trainIds[i],
          line: 'Northeast Corridor',
          lineBadge: isExp ? 'NEC EXPRESS' : 'NEC LOCAL',
          originCode: orig.code,
          destinationCode: dest.code,
          finalDestinationName: finalTerm,
          departureTime: formatTime12h(depDt),
          arrivalTime: formatTime12h(arrDt),
          durationMinutes: totalDuration,
          status: statuses[i],
          track: tracks[i],
          isExpress: isExp,
          dataSource: 'Offline Schedule Estimate',
          stops: trainStops,
          departureDateTime: depDt,
          isRecentPastDeparture: isPast,
        ),
      );
    }

    return trips;
  }
}
