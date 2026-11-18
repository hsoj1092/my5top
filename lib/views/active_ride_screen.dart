import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/njt_api_service.dart';
import '../widgets/animated_train_timeline.dart';
import '../widgets/anime_mascot_banner.dart';

class ActiveRideScreen extends StatefulWidget {
  static const String routeName = '/active-ride';

  static Route<void> route() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const ActiveRideScreen(),
    );
  }

  const ActiveRideScreen({super.key});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  bool _notifZippyExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pal = appState.palette;
        final trip = appState.activeRideTrain;

        if (trip == null) {
          return Scaffold(
            backgroundColor: pal.scaffoldBg,
            appBar: AppBar(title: const Text('Active Commute')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.train_outlined,
                    size: 56,
                    color: pal.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No active train ride right now.',
                    style: TextStyle(color: pal.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back to Departures'),
                  ),
                ],
              ),
            ),
          );
        }

        final rem = appState.stopsRemaining;
        final rules = appState.notificationRules;
        final nextStop = appState.nextUpcomingStop;
        final distDestMeters = appState.distanceToDestinationMeters;
        final isUrgent = rem <= rules.startNotifyingStopsAway;
        final lastUpdatedStamp = NjtApiService.formatDateAndTimeHms(
          appState.lastRideUpdateDateTime,
        );

        final mascotMsg = pal.mascotLineForState(
          isRiding: true,
          watchedTrainId: appState.watchedTrainId,
          activeTrainId: trip.trainId,
          originShort: appState.originStation.shortName,
          destShort: appState.destinationStation.shortName,
          stopsRemaining: rem,
          track: trip.track,
        );

        return Scaffold(
          backgroundColor: pal.scaffoldBg,
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: pal.primaryAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'LIVE RIDE #${trip.trainId}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: pal.primaryAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '→ ${appState.destinationStation.shortName}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: pal.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (trip.hasTrack)
                Container(
                  margin: const EdgeInsets.only(right: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: pal.trackBadgeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'TRK ${trip.track}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: pal.trackBadgeText,
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Stops Remaining & Live ETA Counter Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isUrgent
                            ? [
                                pal.urgentColor.withOpacity(0.22),
                                pal.cardBg,
                              ]
                            : [
                                pal.primaryAccent.withOpacity(0.20),
                                pal.cardBg,
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isUrgent ? pal.urgentColor : pal.primaryAccent,
                        width: 1.6,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Big Stops Away Circle
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (isUrgent
                                        ? pal.urgentColor
                                        : pal.primaryAccent)
                                    .withOpacity(0.18),
                                border: Border.all(
                                  color: isUrgent
                                      ? pal.urgentColor
                                      : pal.primaryAccent,
                                  width: 2.5,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$rem',
                                    style: TextStyle(
                                      fontSize: 34,
                                      height: 1.0,
                                      fontWeight: FontWeight.w900,
                                      color: isUrgent
                                          ? pal.urgentColor
                                          : pal.primaryAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rem == 1 ? 'STOP LEFT' : 'STOPS LEFT',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rem == 0
                                        ? 'Arrived at ${appState.destinationStation.shortName}!'
                                        : 'Next: ${nextStop?.stationName ?? appState.destinationStation.shortName}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 15,
                                        color: pal.primaryAccent,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          'ETA ${trip.arrivalTime} at ${appState.destinationStation.shortName}',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: pal.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.gps_fixed_rounded,
                                        size: 14,
                                        color: pal.successColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          distDestMeters != null
                                              ? '${(distDestMeters / 1609.34).toStringAsFixed(1)} mi to ${appState.destinationStation.code} • ${appState.lastTrackingSignalSource}'
                                              : appState.lastTrackingSignalSource,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: pal.textSecondary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Accuracy Timestamp + Next Poll Countdown + Alert Threshold Bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: pal.scaffoldBg.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sync_rounded,
                                          size: 13,
                                          color: pal.successColor,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            'Updated: $lastUpdatedStamp (${appState.pollCountdownSeconds}s)',
                                            style: TextStyle(
                                              fontSize: 11.2,
                                              fontWeight: FontWeight.w700,
                                              color: pal.textSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Alert ≤ ${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"}',
                                    style: TextStyle(
                                      fontSize: 11.2,
                                      fontWeight: FontWeight.w800,
                                      color: pal.trackBadgeBg,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield_rounded,
                                    size: 13,
                                    color: pal.primaryAccent,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      rem == 0
                                          ? 'Silent Guard: Arrived • Auto-stopping in 2m to save battery'
                                          : 'Silent Guard ON • Runs safely in background until ${appState.destinationStation.shortName}',
                                      style: TextStyle(
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.w700,
                                        color: pal.primaryAccent,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mascot Status Banner
                  AnimeMascotBanner(
                    palette: pal,
                    message: mascotMsg,
                    isExcited: isUrgent,
                    isRiding: true,
                    onToggleThemeStyle: () {
                      appState.setAnimeThemeStyle(
                        pal.id == 'mygo' ? 'sakura' : 'mygo',
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Interactive Commute Simulator Controls (ONLY visible when Dev Test Mode is ON)
                  if (appState.devTestMode) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pal.cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: pal.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sports_esports_rounded,
                                size: 18,
                                color: pal.secondaryAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ride & Alert Simulator (Dev Test Mode)',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: pal.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Step through stops to test live notifications & diorama speed changes',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: pal.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: rem > 0
                                      ? () => appState.simulateNextStop()
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.skip_next_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    '+1 Stop',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: rem > 0
                                      ? () => appState.toggleAutoSimulateRide()
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: appState.isAutoSimulating
                                        ? pal.urgentColor
                                        : pal.secondaryAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                  ),
                                  icon: Icon(
                                    appState.isAutoSimulating
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    appState.isAutoSimulating
                                        ? 'Pause Sim'
                                        : 'Auto-Play Ride',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Animated Side-View Scenic Train Diorama & Stop Progression Map
                  AnimatedTrainTimeline(
                    palette: pal,
                    stops: appState.activeCommuteStops,
                    currentStopIndex: appState.currentStopIndex,
                    segmentProgress: appState.segmentProgress,
                    alertStopsAwayThreshold: rules.startNotifyingStopsAway,
                    trainId: trip.trainId,
                    track: trip.track,
                    sceneSeed: appState.rideSceneSeed,
                    variationIndex: appState.rideVariationIndex,
                  ),
                  const SizedBox(height: 14),

                  // Clean Collapsible Zippy for Customize Stop Notifications
                  Container(
                    decoration: BoxDecoration(
                      color: pal.cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: pal.cardBorder),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            setState(() {
                              _notifZippyExpanded = !_notifZippyExpanded;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded,
                                  size: 19,
                                  color: pal.primaryAccent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Customize Stop Notifications',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: pal.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Alert ≤ ${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"} away • Every stop: ${rules.notifyEveryStop ? "ON" : "OFF"} • Wake-up: ${rules.finalWakeUpAlarm ? "ON" : "OFF"}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: pal.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _notifZippyExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: pal.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Material(
                            type: MaterialType.transparency,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(height: 16),
                                  Text(
                                    'Start alerting me when X stops away from ${appState.destinationStation.shortName}:',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: pal.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [1, 2, 3, 4, 5, 6].map((count) {
                                      final selected =
                                          rules.startNotifyingStopsAway ==
                                              count;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          appState.updateNotificationRules(
                                            rules.copyWith(
                                              startNotifyingStopsAway: count,
                                            ),
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
                                                  color: selected
                                                      ? pal.primaryAccent
                                                      : pal.scaffoldBg,
                                                  border: Border.all(
                                                    color: selected
                                                        ? pal.primaryAccent
                                                        : pal.cardBorder,
                                                    width: 1.8,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  selected
                                                      ? Icons
                                                          .notifications_active
                                                      : Icons.circle,
                                                  size: selected ? 15 : 8,
                                                  color: selected
                                                      ? const Color(0xFF0F172A)
                                                      : pal.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$count',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: selected
                                                      ? FontWeight.w900
                                                      : FontWeight.w600,
                                                  color: selected
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
                                  const Divider(height: 20),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Notify on every single stop',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: pal.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Ping me each time a station is cleared along the line',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: pal.textSecondary,
                                      ),
                                    ),
                                    value: rules.notifyEveryStop,
                                    activeColor: pal.primaryAccent,
                                    onChanged: (val) {
                                      appState.updateNotificationRules(
                                        rules.copyWith(notifyEveryStop: val),
                                      );
                                    },
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Final Wake-Up Arrival Alarm',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: pal.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'High-priority alarm + vibration when approaching ${appState.destinationStation.shortName}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: pal.textSecondary,
                                      ),
                                    ),
                                    value: rules.finalWakeUpAlarm,
                                    activeColor: pal.urgentColor,
                                    onChanged: (val) {
                                      appState.updateNotificationRules(
                                        rules.copyWith(finalWakeUpAlarm: val),
                                      );
                                    },
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Headphone sound on Silent/Vibrate',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: pal.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Play sound strictly in wired/Bluetooth headphones even on Silent/Vibrate (never speakers)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: pal.textSecondary,
                                      ),
                                    ),
                                    value: rules.headphoneAudioBypass,
                                    activeColor: pal.primaryAccent,
                                    onChanged: (val) {
                                      appState.updateNotificationRules(
                                        rules.copyWith(
                                          headphoneAudioBypass: val,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          crossFadeState: _notifZippyExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 220),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Complete / Exit Ride Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await appState.completeOrCancelRide(saveToHistory: true);
                        if (context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rem == 0
                            ? pal.successColor
                            : pal.urgentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: Icon(
                        rem == 0
                            ? Icons.check_circle_rounded
                            : Icons.exit_to_app_rounded,
                      ),
                      label: Text(
                        rem == 0
                            ? 'Complete Commute (Arrived at ${appState.destinationStation.shortName}!)'
                            : 'End Ride / Exit Train',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
