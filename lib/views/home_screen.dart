import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  InAppAlertEvent? _latestBannerAlert;

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
    appState.setAppFocused(state == AppLifecycleState.resumed);
  }

  void _onInAppAlert(InAppAlertEvent evt) {
    if (!mounted) return;
    setState(() {
      _latestBannerAlert = evt;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pal = appState.palette;
        final orig = appState.originStation;
        final dest = appState.destinationStation;
        final rules = appState.notificationRules;

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

        final upcomingList = appState.upcomingScheduleTrains;
        final recentDepartedList = appState.recentDepartedTrains;
        final lastCheckedStr = appState.lastScheduleRefresh != null
            ? NjtApiService.formatTimeHms(appState.lastScheduleRefresh!)
            : '--:--:--';

        return Scaffold(
          backgroundColor: pal.scaffoldBg,
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: pal.primaryAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.train_rounded,
                        size: 16,
                        color: Color(0xFF0F172A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'my5top',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'NJ Transit Commute',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: pal.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh Live NEC Departures',
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
                    : const Icon(Icons.refresh_rounded),
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
                icon: const Icon(Icons.tune_rounded),
              ),
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
                  8,
                  16,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  // 1. Live In-App Notification Toast Banner (when an alert fires)
                  if (_latestBannerAlert != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: _latestBannerAlert!.type == 'arrival'
                            ? pal.urgentColor.withOpacity(0.18)
                            : _latestBannerAlert!.type == 'track'
                                ? pal.trackBadgeBg.withOpacity(0.20)
                                : pal.primaryAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _latestBannerAlert!.type == 'arrival'
                              ? pal.urgentColor
                              : _latestBannerAlert!.type == 'track'
                                  ? pal.trackBadgeBg
                                  : pal.primaryAccent,
                          width: 1.4,
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActiveRideScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              pal.primaryAccent.withOpacity(0.28),
                              pal.secondaryAccent.withOpacity(0.22),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: pal.primaryAccent,
                            width: 1.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: pal.primaryAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.train_rounded,
                                color: Color(0xFF0F172A),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ON TRAIN #${appState.activeRideTrain!.trainId} → ${dest.shortName}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${appState.stopsRemaining} ${appState.stopsRemaining == 1 ? "stop" : "stops"} left • ETA ${appState.activeRideTrain!.arrivalTime} • Tap for Live Map',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: pal.primaryAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: pal.primaryAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 3. Cute Anime Mascot Header
                  AnimeMascotBanner(
                    palette: pal,
                    message: mascotMsg,
                    isExcited: appState.watchedTrainId != null ||
                        (appState.isRiding && appState.stopsRemaining <= 2),
                    isRiding: appState.isRiding,
                    onToggleThemeStyle: () {
                      appState.setAnimeThemeStyle(
                        pal.id == 'mygo' ? 'sakura' : 'mygo',
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // 4. 1-Tap Commute Route Selector (Work NY Penn <-> Home Metropark)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: pal.cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: pal.cardBorder, width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick Preset Pills (To Home / To Work) - balanced padding so labels never clip
                        Row(
                          children: [
                            Expanded(
                              child: _buildPresetButton(
                                selected: isHeadingHome,
                                icon: Icons.home_rounded,
                                label:
                                    'To Home (${appState.workStation.code} → ${appState.homeStation.code})',
                                accent: pal.primaryAccent,
                                textColor: pal.textPrimary,
                                onTap: () => appState.setToHomePreset(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildPresetButton(
                                selected: isHeadingToWork,
                                icon: Icons.work_rounded,
                                label:
                                    'To Work (${appState.homeStation.code} → ${appState.workStation.code})',
                                accent: pal.secondaryAccent,
                                textColor: pal.textPrimary,
                                onTap: () => appState.setToWorkPreset(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Interactive Origin <-> Destination Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildStationBox(
                                context: context,
                                roleLabel: orig.code == appState.workStationCode
                                    ? 'FROM • WORK 🏢'
                                    : orig.code == appState.homeStationCode
                                        ? 'FROM • HOME 🏠'
                                        : 'FROM STATION',
                                station: orig,
                                onTap: () => _showStationPickerModal(
                                  context: context,
                                  isOrigin: true,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: InkWell(
                                onTap: () => appState.swapStations(),
                                borderRadius: BorderRadius.circular(99),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: pal.primaryAccent.withOpacity(0.16),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: pal.primaryAccent.withOpacity(0.5),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.swap_horiz_rounded,
                                    color: pal.primaryAccent,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: _buildStationBox(
                                context: context,
                                roleLabel: dest.code == appState.homeStationCode
                                    ? 'TO • HOME 🏠'
                                    : dest.code == appState.workStationCode
                                        ? 'TO • WORK 🏢'
                                        : 'TO DESTINATION',
                                station: dest,
                                onTap: () => _showStationPickerModal(
                                  context: context,
                                  isOrigin: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Active Notification Summary Chip Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildRuleChip(
                                icon: Icons.notifications_active_outlined,
                                text:
                                    'Alert at ≤ ${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"} away',
                                color: pal.primaryAccent,
                                onTap: () => _showQuickRulesSheet(context),
                              ),
                              const SizedBox(width: 8),
                              _buildRuleChip(
                                icon: rules.notifyEveryStop
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked,
                                text: rules.notifyEveryStop
                                    ? 'Every Stop: ON'
                                    : 'Every Stop: OFF',
                                color: rules.notifyEveryStop
                                    ? pal.successColor
                                    : pal.textSecondary,
                                onTap: () {
                                  appState.updateNotificationRules(
                                    rules.copyWith(
                                      notifyEveryStop: !rules.notifyEveryStop,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildRuleChip(
                                icon: Icons.track_changes_rounded,
                                text: rules.notifyOnTrackAssigned
                                    ? 'Track Drop Alert: ON'
                                    : 'Track Drop Alert: OFF',
                                color: pal.trackBadgeBg,
                                onTap: () => _showQuickRulesSheet(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Section Header: Upcoming Trains + Live 5s Poll Accuracy Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.departure_board_rounded,
                              size: 19,
                              color: pal.primaryAccent,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Upcoming (${orig.code} → ${dest.code})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: pal.textPrimary,
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
                            color: pal.cardBg,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: pal.cardBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sync_rounded,
                                size: 12,
                                color: appState.isLoadingTrains
                                    ? pal.primaryAccent
                                    : appState.isPollingActive
                                        ? pal.successColor
                                        : pal.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                appState.isLoadingTrains
                                    ? 'Polling NEC Live...'
                                    : '$lastCheckedStr • ${appState.isPollingActive ? "${appState.pollCountdownSeconds}s" : "Idle"}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: appState.isLoadingTrains
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
                  const SizedBox(height: 10),

                  if (appState.isLoadingTrains && upcomingList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (upcomingList.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: pal.cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: pal.cardBorder),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.nights_stay_rounded,
                            size: 28,
                            color: pal.secondaryAccent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No upcoming direct trains posted right now (${orig.shortName} → ${dest.shortName})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: pal.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () =>
                                appState.refreshSchedules(forceNetwork: true),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Poll Live NEC Board'),
                          ),
                        ],
                      ),
                    )
                  else
                    ...upcomingList.map(
                      (trip) => _buildTrainCard(context, appState, trip),
                    ),

                  // 6. Just Departed (2-3 Prior Departures) at the bottom so user can still select & check in!
                  if (recentDepartedList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 18,
                              color: pal.secondaryAccent,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Just Departed (${orig.code} → ${dest.code})',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: pal.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Already on board? Tap to track',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: pal.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...recentDepartedList.map(
                      (trip) => _buildTrainCard(context, appState, trip),
                    ),
                  ],
                ],
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
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : accent.withOpacity(0.28),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: pal.scaffoldBg.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roleLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: pal.primaryAccent,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    station.shortName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: pal.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: pal.textSecondary,
                ),
              ],
            ),
            Text(
              '${station.code} • ${station.line}',
              style: TextStyle(
                fontSize: 10.5,
                color: pal.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleChip({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainCard(
    BuildContext context,
    AppState appState,
    TrainTrip trip,
  ) {
    final pal = appState.palette;
    final isWatched = appState.watchedTrainId == trip.trainId;
    final isActiveRide = appState.activeRideTrain?.trainId == trip.trainId;
    final stopCount = trip.totalStopCount;
    final isExpressCount = trip.isFourOrLessStops;

    // Color-code <= 4 stops to mark Express train clearly
    final Color stopCountColor = isExpressCount
        ? (pal.isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
        : pal.secondaryAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: trip.isRecentPastDeparture
            ? pal.cardBg.withOpacity(0.88)
            : pal.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActiveRide
              ? pal.primaryAccent
              : isWatched
                  ? pal.trackBadgeBg
                  : pal.cardBorder,
          width: isActiveRide || isWatched ? 1.8 : 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showTrainDetailSheet(context, appState, trip),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Train # + Express/Local badge + Track Assignment Pill
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pal.primaryAccent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '#${trip.trainId}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: pal.primaryAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isExpressCount
                          ? pal.urgentColor.withOpacity(0.16)
                          : pal.secondaryAccent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isExpressCount ? '⚡ EXPRESS' : 'LOCAL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isExpressCount
                            ? pal.urgentColor
                            : pal.secondaryAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '→ ${trip.finalDestinationName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pal.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Track Assignment Badge or Watch Track Pill
                  if (trip.hasTrack)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: pal.trackBadgeBg,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: pal.trackBadgeBg.withOpacity(0.30),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.confirmation_number_rounded,
                            size: 13,
                            color: pal.trackBadgeText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'TRACK ${trip.track}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: pal.trackBadgeText,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!trip.isRecentPastDeparture)
                    InkWell(
                      onTap: () => appState.toggleWatchTrainTrack(trip),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isWatched
                              ? pal.trackBadgeBg.withOpacity(0.22)
                              : pal.scaffoldBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isWatched
                                ? pal.trackBadgeBg
                                : pal.textSecondary.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isWatched
                                  ? Icons.visibility_rounded
                                  : Icons.notifications_none_rounded,
                              size: 13,
                              color: isWatched
                                  ? pal.trackBadgeBg
                                  : pal.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isWatched ? 'WATCHING TRK ★' : 'TRACK TBA • WATCH',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isWatched
                                    ? pal.trackBadgeBg
                                    : pal.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Middle row: DepartureTime -> ArrivalTime & Duration + Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trip.departureTime,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: pal.textPrimary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: pal.primaryAccent,
                    ),
                  ),
                  Text(
                    trip.arrivalTime,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${trip.durationMinutes} min',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: pal.textPrimary,
                        ),
                      ),
                      Text(
                        trip.status,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: (trip.status.toLowerCase().contains('delay') ||
                                  trip.status.toLowerCase().contains('cancel'))
                              ? pal.urgentColor
                              : trip.isRecentPastDeparture
                                  ? pal.secondaryAccent
                                  : pal.successColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bottom row: Stop count till destination (color-coded + ⚡ emoji for <= 4 stops) + Boarding button
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5.5,
                      ),
                      decoration: BoxDecoration(
                        color: stopCountColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: stopCountColor.withOpacity(0.42),
                        ),
                      ),
                      child: Text(
                        isExpressCount
                            ? '⚡ $stopCount ${stopCount == 1 ? "stop" : "stops"} to ${trip.destinationCode} • Express'
                            : '🚉 $stopCount stops to ${trip.destinationCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: stopCountColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Hide Sim Track unless Dev Test Mode is enabled in Settings
                  if (appState.devTestMode && !trip.hasTrack) ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () =>
                          appState.simulateTrackAnnouncement(trip.trainId),
                      icon: Icon(
                        Icons.flash_on_rounded,
                        size: 14,
                        color: pal.trackBadgeBg,
                      ),
                      label: Text(
                        'Sim Track',
                        style: TextStyle(
                          fontSize: 11.5,
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
                          : pal.primaryAccent,
                      foregroundColor: const Color(0xFF0F172A),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      if (!isActiveRide) {
                        await appState.startRide(trip);
                      }
                      if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActiveRideScreen(),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      isActiveRide
                          ? Icons.sensors_rounded
                          : Icons.directions_railway_rounded,
                      size: 15,
                    ),
                    label: Text(
                      isActiveRide ? 'Active Ride' : 'I\'m on this!',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
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

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: pal.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: pal.cardBorder),
          ),
          child: SafeArea(
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
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ActiveRideScreen(),
                                ),
                              );
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<AppState>(
          builder: (context, appState, _) {
            final pal = appState.palette;
            final rules = appState.notificationRules;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: pal.cardBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
