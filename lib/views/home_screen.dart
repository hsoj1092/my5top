import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/station.dart';
import '../models/train_trip.dart';
import '../providers/app_state.dart';
import '../providers/backup_provider.dart';
import '../services/njt_api_service.dart';
import '../services/notification_service.dart';
import '../widgets/anime_mascot_banner.dart';
import 'active_ride_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const int _initialUpcomingLimit = 3;
  static const int _loadMoreStep = 4;

  InAppAlertEvent? _latestBannerAlert;
  int _visibleUpcomingCount = _initialUpcomingLimit;
  bool _enRouteExpanded = false;
  String _lastRouteKey = '';
  DateTime? _lastPausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.addAlertListener(_onInAppAlert);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NotificationService.requestPermission();
      final appState = context.read<AppState>();
      context.read<BackupProvider>().checkAndRunAutoBackup(appState);
      appState.checkAndRunDailyUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.removeAlertListener(_onInAppAlert);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
      appState.setAppFocused(false);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final wasBackgrounded = _lastPausedAt != null &&
          DateTime.now().difference(_lastPausedAt!) >
              const Duration(seconds: 2);
      _lastPausedAt = null;
      appState.setAppFocused(true);
      _handleAppReopened(appState, wasBackgrounded: wasBackgrounded);
    } else {
      appState.setAppFocused(false);
    }
  }

  Future<void> _handleAppReopened(
    AppState appState, {
    required bool wasBackgrounded,
  }) async {
    final expired = await appState.checkAndExpireStaleActiveRide();
    if (!mounted) return;
    if (expired) {
      // Tracked train arrival time is >= 20 min stale -> return to main train table
      if (activeRideRouteObserver.isActiveRideInStack) {
        appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
      return;
    }
    // If reopened from background while actively tracking a non-stale train, bring back ActiveRideScreen
    if (wasBackgrounded &&
        appState.isRiding &&
        !activeRideRouteObserver.isActiveRideInStack) {
      appNavigatorKey.currentState?.push(ActiveRideScreen.route());
    }
  }

  void _onInAppAlert(InAppAlertEvent evt) {
    if (!mounted) return;
    setState(() {
      _latestBannerAlert = evt;
    });
  }

  bool _shouldShowSecondaryStatus(TrainTrip trip, bool hasCountdownChip) {
    if (trip.isRecentPastDeparture) {
      return trip.status.trim().isNotEmpty;
    }
    final raw = trip.status.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (lower == 'on time' || lower == 'ontime' || lower == 'scheduled') {
      return false;
    }
    if (lower == 'boarding') {
      return false;
    }
    if (hasCountdownChip &&
        RegExp(r'^in\s+\d+\s*min', caseSensitive: false).hasMatch(raw)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pal = appState.palette;
        final orig = appState.originStation;
        final dest = appState.destinationStation;
        final rules = appState.notificationRules;

        final routeKey = '${orig.code}->${dest.code}';
        if (_lastRouteKey != routeKey) {
          _lastRouteKey = routeKey;
          _visibleUpcomingCount = _initialUpcomingLimit;
          _enRouteExpanded = false;
        }

        final watchedTrain = appState.upcomingTrains
            .where((t) => t.trainId == appState.watchedTrainId)
            .firstOrNull;

        final mascotMsg = pal.mascotLineForState(
          isRiding: appState.isRiding,
          watchedTrainId: appState.watchedTrainId,
          activeTrainId: appState.activeRideTrain?.trainId,
          originShort: orig.shortName,
          destShort: dest.shortName,
          stopsRemaining: appState.stopsRemaining,
          track: watchedTrain?.track ?? appState.activeRideTrain?.track,
        );

        final isHeadingHome = dest.code == appState.homeStationCode &&
            orig.code == appState.workStationCode;
        final isHeadingToWork = dest.code == appState.workStationCode &&
            orig.code == appState.homeStationCode;

        final easternNow = NjtApiService.easternNow();
        final upcomingList = appState.upcomingScheduleTrains;
        final displayedUpcoming =
            upcomingList.take(_visibleUpcomingCount).toList();
        final remainingUpcomingCount =
            (upcomingList.length - displayedUpcoming.length).clamp(0, 999);
        final recentDepartedList = appState.recentDepartedTrains;
        final showEnRouteCards = _enRouteExpanded || upcomingList.isEmpty;

        final lastCheckedShort = appState.lastScheduleRefresh != null
            ? NjtApiService.formatTime12h(appState.lastScheduleRefresh!)
            : null;

        return PopScope(
          canPop: !appState.isBackgroundGuardActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && appState.isBackgroundGuardActive) {
              NotificationService.moveToBackground();
            }
          },
          child: Scaffold(
          backgroundColor: pal.scaffoldBg,
          appBar: AppBar(
            toolbarHeight: 52,
            titleSpacing: 16,
            title: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4.5,
              ),
              decoration: BoxDecoration(
                color: pal.primaryAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.train_rounded,
                    size: 16,
                    color: pal.isDark ? const Color(0xFF0F172A) : Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'my5top',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color:
                          pal.isDark ? const Color(0xFF0F172A) : Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh Live Departures',
                onPressed: () =>
                    appState.refreshSchedules(forceNetwork: true),
                icon: appState.isLoadingTrains
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: pal.primaryAccent,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 21),
              ),
              IconButton(
                tooltip: 'Settings, Backups & Updates',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 21),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              color: pal.primaryAccent,
              onRefresh: () =>
                  appState.refreshSchedules(forceNetwork: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  // 1. Live In-App Notification Toast Banner (when an alert fires)
                  if (_latestBannerAlert != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: _latestBannerAlert!.type == 'arrival'
                            ? pal.urgentColor.withOpacity(0.18)
                            : _latestBannerAlert!.type == 'track'
                                ? pal.trackBadgeBg.withOpacity(0.20)
                                : pal.primaryAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _latestBannerAlert!.type == 'arrival'
                              ? pal.urgentColor
                              : _latestBannerAlert!.type == 'track'
                                  ? pal.trackBadgeBg
                                  : pal.primaryAccent,
                          width: 1.3,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _latestBannerAlert!.type == 'track'
                                ? Icons.campaign_rounded
                                : Icons.notifications_active_rounded,
                            color: _latestBannerAlert!.type == 'arrival'
                                ? pal.urgentColor
                                : pal.primaryAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _latestBannerAlert!.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: pal.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _latestBannerAlert!.body,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: pal.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => _latestBannerAlert = null);
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 2. Active Ride Banner (if currently on a train)
                  if (appState.isRiding && appState.activeRideTrain != null) ...[
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(ActiveRideScreen.route());
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              pal.primaryAccent.withOpacity(0.26),
                              pal.secondaryAccent.withOpacity(0.20),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: pal.primaryAccent,
                            width: 1.6,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: pal.primaryAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.train_rounded,
                                color: Color(0xFF0F172A),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ON TRAIN #${appState.activeRideTrain!.trainId} → ${dest.shortName}',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 1.5),
                                  Text(
                                    '${appState.stopsRemaining} ${appState.stopsRemaining == 1 ? "stop" : "stops"} left • ETA ${appState.activeRideTrain!.arrivalTime} • Live Map',
                                    style: TextStyle(
                                      fontSize: 11.8,
                                      fontWeight: FontWeight.w600,
                                      color: pal.primaryAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 15,
                              color: pal.primaryAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 3. Compact Single-Row Mascot Companion Strip
                  AnimeMascotBanner(
                    palette: pal,
                    message: mascotMsg,
                    isExcited: appState.watchedTrainId != null ||
                        (appState.isRiding && appState.stopsRemaining <= 2),
                    isRiding: appState.isRiding,
                    compact: true,
                  ),
                  const SizedBox(height: 10),

                  // 4. Slim Unified Commute Route & Quick Alert Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: pal.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: pal.cardBorder, width: 1.1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top micro-row: To Home / To Work quick switcher + single Quick Alert Rules pill
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: pal.scaffoldBg.withOpacity(
                                    pal.isDark ? 0.65 : 0.75,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: pal.cardBorder.withOpacity(0.7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildPresetButton(
                                        selected: isHeadingHome,
                                        icon: Icons.home_rounded,
                                        label: 'To Home',
                                        accent: pal.primaryAccent,
                                        textColor: pal.textPrimary,
                                        secondaryColor: pal.textSecondary,
                                        onTap: () => appState.setToHomePreset(),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: _buildPresetButton(
                                        selected: isHeadingToWork,
                                        icon: Icons.work_rounded,
                                        label: 'To Work',
                                        accent: pal.secondaryAccent,
                                        textColor: pal.textPrimary,
                                        secondaryColor: pal.textSecondary,
                                        onTap: () => appState.setToWorkPreset(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildAlertRulesButton(
                              context: context,
                              stopsAway: rules.startNotifyingStopsAway,
                              everyStopOn: rules.notifyEveryStop,
                              accent: pal.primaryAccent,
                              successColor: pal.successColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Compact Origin <-> Destination Selector Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildStationBox(
                                context: context,
                                roleLabel: orig.code == appState.workStationCode
                                    ? 'FROM • WORK'
                                    : orig.code == appState.homeStationCode
                                        ? 'FROM • HOME'
                                        : 'FROM',
                                station: orig,
                                onTap: () => _showStationPickerModal(
                                  context: context,
                                  isOrigin: true,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: InkWell(
                                onTap: () => appState.swapStations(),
                                borderRadius: BorderRadius.circular(99),
                                child: Tooltip(
                                  message: 'Swap Stations',
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color:
                                          pal.primaryAccent.withOpacity(0.14),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            pal.primaryAccent.withOpacity(0.45),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.swap_horiz_rounded,
                                      color: pal.primaryAccent,
                                      size: 19,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: _buildStationBox(
                                context: context,
                                roleLabel: dest.code == appState.homeStationCode
                                    ? 'TO • HOME'
                                    : dest.code == appState.workStationCode
                                        ? 'TO • WORK'
                                        : 'TO',
                                station: dest,
                                onTap: () => _showStationPickerModal(
                                  context: context,
                                  isOrigin: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. Calm Section Header: Upcoming + Live Status Pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.departure_board_rounded,
                              size: 17,
                              color: pal.primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Upcoming',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: pal.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () =>
                            appState.refreshSchedules(forceNetwork: true),
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: appState.isFastTrackPolling
                                ? pal.trackBadgeBg.withOpacity(0.16)
                                : pal.cardBg,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: appState.isFastTrackPolling
                                  ? pal.trackBadgeBg
                                  : pal.cardBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (appState.isFastTrackPolling)
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 13,
                                  color: pal.trackBadgeBg,
                                )
                              else if (appState.isLoadingTrains)
                                Icon(
                                  Icons.sync_rounded,
                                  size: 12,
                                  color: pal.primaryAccent,
                                )
                              else
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: appState.isPollingActive
                                        ? pal.successColor
                                        : pal.textSecondary,
                                  ),
                                ),
                              const SizedBox(width: 5),
                              Text(
                                appState.isFastTrackPolling
                                    ? '1s Track Watch'
                                    : appState.isLoadingTrains
                                        ? 'Syncing...'
                                        : appState.isPollingActive
                                            ? (lastCheckedShort != null
                                                ? 'Live • $lastCheckedShort'
                                                : 'Live')
                                            : (lastCheckedShort != null
                                                ? 'Updated $lastCheckedShort'
                                                : 'Tap to refresh'),
                                style: TextStyle(
                                  fontSize: 10.8,
                                  fontWeight: FontWeight.w700,
                                  color: appState.isFastTrackPolling
                                      ? pal.trackBadgeBg
                                      : appState.isLoadingTrains
                                          ? pal.primaryAccent
                                          : pal.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (appState.isLoadingTrains && upcomingList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (upcomingList.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: pal.cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: pal.cardBorder),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.nights_stay_rounded,
                            size: 26,
                            color: pal.secondaryAccent,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No upcoming direct trains posted right now (${orig.shortName} → ${dest.shortName})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: pal.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: () =>
                                appState.refreshSchedules(forceNetwork: true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Refresh Departures'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    for (int i = 0; i < displayedUpcoming.length; i++)
                      _buildTrainCard(
                        context,
                        appState,
                        displayedUpcoming[i],
                        easternNow: easternNow,
                        isPrimaryNext: i == 0 && !appState.isRiding,
                      ),
                    if (remainingUpcomingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleUpcomingCount += _loadMoreStep;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: pal.primaryAccent,
                              backgroundColor:
                                  pal.primaryAccent.withOpacity(0.06),
                              side: BorderSide(
                                color: pal.primaryAccent.withOpacity(0.38),
                                width: 1.1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.expand_more_rounded,
                              size: 19,
                            ),
                            label: Text(
                              remainingUpcomingCount <= _loadMoreStep
                                  ? 'Load More Trains ($remainingUpcomingCount more)'
                                  : 'Load More Trains (+$_loadMoreStep of $remainingUpcomingCount more)',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (upcomingList.length > _initialUpcomingLimit &&
                        _visibleUpcomingCount > _initialUpcomingLimit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _visibleUpcomingCount = _initialUpcomingLimit;
                              });
                            },
                            icon: Icon(
                              Icons.expand_less_rounded,
                              size: 18,
                              color: pal.textSecondary,
                            ),
                            label: Text(
                              'Show Fewer Trains',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: pal.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],

                  // 6. Collapsible "Already on board?" En-Route Accordion
                  if (recentDepartedList.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          pal.cardBg,
                          pal.secondaryAccent,
                          pal.isDark ? 0.12 : 0.07,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: pal.secondaryAccent.withOpacity(
                            pal.isDark ? 0.40 : 0.32,
                          ),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              setState(() {
                                _enRouteExpanded = !showEnRouteCards;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.history_toggle_off_rounded,
                                    size: 18,
                                    color: pal.secondaryAccent,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Already on board?',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: pal.textPrimary,
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                '  •  ${recentDepartedList.length} ${recentDepartedList.length == 1 ? "train" : "trains"}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: pal.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          pal.secondaryAccent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      'EN ROUTE',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: pal.secondaryAccent,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    showEnRouteCards
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 20,
                                    color: pal.secondaryAccent,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (showEnRouteCards)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 2, 10, 3),
                              child: Column(
                                children: recentDepartedList
                                    .map(
                                      (trip) => _buildTrainCard(
                                        context,
                                        appState,
                                        trip,
                                        easternNow: easternNow,
                                        isPrimaryNext: false,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildPresetButton({
    required bool selected,
    required IconData icon,
    required String label,
    required Color accent,
    required Color textColor,
    required Color secondaryColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6.5),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected
              ? Border.all(color: accent.withOpacity(0.65), width: 1.1)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? accent : secondaryColor,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? textColor : secondaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertRulesButton({
    required BuildContext context,
    required int stopsAway,
    required bool everyStopOn,
    required Color accent,
    required Color successColor,
  }) {
    return InkWell(
      onTap: () => _showQuickRulesSheet(context),
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: 'Quick Commute Alert Settings',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withOpacity(0.38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 4),
              Text(
                '≤$stopsAway ${stopsAway == 1 ? "stop" : "stops"}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              if (everyStopOn) ...[
                const SizedBox(width: 5),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: successColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationBox({
    required BuildContext context,
    required String roleLabel,
    required Station station,
    required VoidCallback onTap,
  }) {
    final pal = context.read<AppState>().palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: pal.scaffoldBg.withOpacity(0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: pal.primaryAccent,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    station.shortName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: pal.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: pal.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainCard(
    BuildContext context,
    AppState appState,
    TrainTrip trip, {
    required DateTime easternNow,
    bool isPrimaryNext = false,
  }) {
    final pal = appState.palette;
    final isWatched = appState.watchedTrainId == trip.trainId;
    final isActiveRide = appState.activeRideTrain?.trainId == trip.trainId;
    final stopCount = trip.totalStopCount;
    final isExpressCount = trip.isFourOrLessStops;

    final Color expressColor =
        pal.isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    final statusLower = trip.status.toLowerCase();
    final isUrgentStatus =
        statusLower.contains('delay') || statusLower.contains('cancel');
    final isBoardingStatus = statusLower == 'boarding';

    final Color statusColor = isUrgentStatus
        ? pal.urgentColor
        : trip.isRecentPastDeparture
            ? pal.secondaryAccent
            : pal.successColor;

    final int? minsUntil = trip.minutesUntilDeparture(
      easternNow,
      parsedDeparture:
          NjtApiService.parseNjtTime(trip.departureTime, easternNow),
    );
    final String? topChipLabel = isBoardingStatus
        ? 'Boarding'
        : (minsUntil != null ? TrainTrip.formatCountdownLabel(minsUntil) : null);
    final bool isSoonChip =
        isBoardingStatus || (minsUntil != null && minsUntil <= 10);
    final bool showSecondaryStatus =
        _shouldShowSecondaryStatus(trip, topChipLabel != null);

    final bool emphasizeBoardCta = isActiveRide || isPrimaryNext;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: trip.isRecentPastDeparture
            ? pal.scaffoldBg.withOpacity(pal.isDark ? 0.78 : 0.94)
            : pal.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActiveRide
              ? pal.primaryAccent
              : isWatched
                  ? pal.trackBadgeBg
                  : isPrimaryNext
                      ? pal.primaryAccent.withOpacity(pal.isDark ? 0.48 : 0.40)
                      : trip.isRecentPastDeparture
                          ? pal.secondaryAccent.withOpacity(0.30)
                          : pal.cardBorder,
          width: isActiveRide || isWatched
              ? 1.7
              : isPrimaryNext
                  ? 1.3
                  : 1.1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showTrainDetailSheet(context, appState, trip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Departure -> Arrival + Countdown chip (left) | Track / Watch focal badge (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              trip.departureTime,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: pal.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: pal.primaryAccent,
                              ),
                            ),
                            Text(
                              trip.arrivalTime,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: pal.textSecondary,
                              ),
                            ),
                            if (topChipLabel != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: (isSoonChip
                                          ? pal.successColor
                                          : pal.primaryAccent)
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  topChipLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isSoonChip
                                        ? pal.successColor
                                        : pal.primaryAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (trip.hasTrack) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 92),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.5,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: pal.trackBadgeBg,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            'TRACK ${trip.track}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: pal.trackBadgeText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else if (!trip.isRecentPastDeparture) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 102),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => appState.toggleWatchTrainTrack(trip),
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isWatched
                                  ? pal.trackBadgeBg.withOpacity(0.20)
                                  : pal.scaffoldBg.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isWatched
                                    ? pal.trackBadgeBg
                                    : pal.cardBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isWatched
                                      ? (appState.isFastTrackPolling
                                          ? Icons.bolt_rounded
                                          : Icons.visibility_rounded)
                                      : Icons.notifications_none_rounded,
                                  size: 12,
                                  color: isWatched
                                      ? pal.trackBadgeBg
                                      : pal.textSecondary,
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  isWatched
                                      ? (appState.isFastTrackPolling
                                          ? '1s Watch'
                                          : 'Watching')
                                      : 'Watch Track',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isWatched
                                        ? pal.trackBadgeBg
                                        : pal.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Plain-text metadata (no badge borders) + Contextual Board button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${trip.trainId}',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: pal.textPrimary,
                              ),
                            ),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (isExpressCount) ...[
                                      const TextSpan(text: ' • '),
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Icon(
                                          Icons.bolt_rounded,
                                          size: 13.5,
                                          color: expressColor,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Express',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: expressColor,
                                        ),
                                      ),
                                    ],
                                    TextSpan(
                                      text:
                                          ' • ${trip.durationMinutes}m • $stopCount ${stopCount == 1 ? "stop" : "stops"}',
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: pal.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showSecondaryStatus) ...[
                          const SizedBox(height: 2),
                          Text(
                            trip.status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (appState.devTestMode && !trip.hasTrack) ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                      ),
                      onPressed: () =>
                          appState.simulateTrackAnnouncement(trip.trainId),
                      icon: Icon(
                        Icons.flash_on_rounded,
                        size: 13,
                        color: pal.trackBadgeBg,
                      ),
                      label: Text(
                        'Sim',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: pal.trackBadgeBg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActiveRide
                          ? pal.successColor
                          : emphasizeBoardCta
                              ? pal.primaryAccent
                              : pal.primaryAccent.withOpacity(
                                  pal.isDark ? 0.13 : 0.10,
                                ),
                      foregroundColor: emphasizeBoardCta
                          ? (pal.isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white)
                          : pal.primaryAccent,
                      elevation: 0,
                      side: emphasizeBoardCta
                          ? BorderSide.none
                          : BorderSide(
                              color: pal.primaryAccent.withOpacity(0.38),
                              width: 1.0,
                            ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      if (!isActiveRide) {
                        await appState.startRide(trip);
                      }
                      if (context.mounted) {
                        Navigator.of(context).push(ActiveRideScreen.route());
                      }
                    },
                    icon: Icon(
                      isActiveRide
                          ? Icons.sensors_rounded
                          : Icons.directions_railway_rounded,
                      size: 14,
                    ),
                    label: Text(
                      isActiveRide ? 'Riding' : 'Board',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight:
                            emphasizeBoardCta ? FontWeight.w900 : FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTrainDetailSheet(
    BuildContext context,
    AppState appState,
    TrainTrip trip,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pal = appState.palette;
        final stops = trip.commuteStops;
        final alertThreshold = appState.notificationRules.startNotifyingStopsAway;

        return Material(
          color: pal.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            side: BorderSide(color: pal.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: pal.textSecondary.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: pal.primaryAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'TRAIN #${trip.trainId}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${appState.originStation.shortName} → ${appState.destinationStation.shortName}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: pal.textPrimary,
                          ),
                        ),
                      ),
                      if (trip.hasTrack)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: pal.trackBadgeBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'TRACK ${trip.track}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: pal.trackBadgeText,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Departs ${trip.departureTime} • Arrives ${trip.arrivalTime} (${trip.totalStopCount} stops) • Alerting at $alertThreshold ${alertThreshold == 1 ? "stop" : "stops"} away',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: pal.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.42,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: stops.length,
                      itemBuilder: (_, idx) {
                        final s = stops[idx];
                        final rem = (stops.length - 1) - idx;
                        final isOrig = idx == 0;
                        final isDest = idx == stops.length - 1;
                        final triggersAlert = !isDest && rem == alertThreshold;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                isOrig
                                    ? Icons.trip_origin_rounded
                                    : isDest
                                        ? Icons.flag_circle_rounded
                                        : triggersAlert
                                            ? Icons.notifications_active_rounded
                                            : Icons.circle,
                                size: isOrig || isDest || triggersAlert ? 18 : 10,
                                color: isDest
                                    ? pal.urgentColor
                                    : triggersAlert
                                        ? pal.trackBadgeBg
                                        : pal.primaryAccent,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.stationName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isOrig || isDest || triggersAlert
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: pal.textPrimary,
                                  ),
                                ),
                              ),
                              if (triggersAlert)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: pal.trackBadgeBg.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'ALERT STARTS HERE ($rem left)',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: pal.trackBadgeBg,
                                    ),
                                  ),
                                ),
                              Text(
                                s.estimatedTime,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: pal.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!trip.hasTrack && !trip.isRecentPastDeparture) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              appState.toggleWatchTrainTrack(trip);
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: const Text('Watch Track'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: pal.primaryAccent,
                              foregroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await appState.startRide(trip);
                              if (context.mounted) {
                                Navigator.of(context)
                                    .push(ActiveRideScreen.route());
                              }
                            },
                            icon: const Icon(Icons.train_rounded),
                            label: Text(
                              'I\'m on Train #${trip.trainId}! (Start Ride)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
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
  }

  void _showStationPickerModal({
    required BuildContext context,
    required bool isOrigin,
  }) {
    final appState = context.read<AppState>();
    final pal = appState.palette;

    showModalBottomSheet(
      context: context,
      backgroundColor: pal.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOrigin
                      ? 'Select Boarding Station'
                      : 'Select Destination Station',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: kNjtStations.length,
                    itemBuilder: (_, idx) {
                      final st = kNjtStations[idx];
                      final isWork = st.code == appState.workStationCode;
                      final isHome = st.code == appState.homeStationCode;
                      final isStarred =
                          appState.starredStationCodes.contains(st.code);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: pal.primaryAccent.withOpacity(0.18),
                          child: Text(
                            st.code,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: pal.primaryAccent,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                st.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: pal.textPrimary,
                                ),
                              ),
                            ),
                            if (isWork) ...[
                              const SizedBox(width: 6),
                              _buildBadge('WORK 🏢', pal.secondaryAccent),
                            ],
                            if (isHome) ...[
                              const SizedBox(width: 6),
                              _buildBadge('HOME 🏠', pal.primaryAccent),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          st.line,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: pal.textSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isStarred
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: isStarred
                                ? pal.trackBadgeBg
                                : pal.textSecondary,
                          ),
                          onPressed: () {
                            appState.toggleStarredStation(st.code);
                          },
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (isOrigin) {
                            appState.setOriginAndDestination(
                              st.code,
                              appState.destinationStationCode,
                            );
                          } else {
                            appState.setOriginAndDestination(
                              appState.originStationCode,
                              st.code,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  void _showQuickRulesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<AppState>(
          builder: (context, appState, _) {
            final pal = appState.palette;
            final rules = appState.notificationRules;
            return Material(
              color: pal.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                side: BorderSide(color: pal.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Commute Alert Settings',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Start notifying me when X stops away:',
                        style: TextStyle(
                          fontSize: 13,
                          color: pal.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [1, 2, 3, 4, 5, 6].map((n) {
                          final sel = rules.startNotifyingStopsAway == n;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              appState.updateNotificationRules(
                                rules.copyWith(startNotifyingStopsAway: n),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: sel
                                          ? pal.primaryAccent
                                          : pal.scaffoldBg,
                                      border: Border.all(
                                        color: sel
                                            ? pal.primaryAccent
                                            : pal.cardBorder,
                                        width: 1.8,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      sel
                                          ? Icons.notifications_active
                                          : Icons.circle,
                                      size: sel ? 15 : 8,
                                      color: sel
                                          ? const Color(0xFF0F172A)
                                          : pal.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$n',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: sel
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      color: sel
                                          ? pal.primaryAccent
                                          : pal.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Notify me on every stop'),
                        value: rules.notifyEveryStop,
                        activeColor: pal.primaryAccent,
                        onChanged: (v) => appState.updateNotificationRules(
                          rules.copyWith(notifyEveryStop: v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Alert when Track Assignment drops'),
                        value: rules.notifyOnTrackAssigned,
                        activeColor: pal.trackBadgeBg,
                        onChanged: (v) => appState.updateNotificationRules(
                          rules.copyWith(notifyOnTrackAssigned: v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Headphone sound on Silent/Vibrate'),
                        subtitle: Text(
                          'Plays strictly in connected headphones (never speakers)',
                          style: TextStyle(
                            fontSize: 12,
                            color: pal.textSecondary,
                          ),
                        ),
                        value: rules.headphoneAudioBypass,
                        activeColor: pal.primaryAccent,
                        onChanged: (v) => appState.updateNotificationRules(
                          rules.copyWith(headphoneAudioBypass: v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
