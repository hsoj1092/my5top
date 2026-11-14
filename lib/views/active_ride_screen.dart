import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/animated_train_timeline.dart';
import '../widgets/anime_mascot_banner.dart';

class ActiveRideScreen extends StatelessWidget {
  const ActiveRideScreen({super.key});

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
                    onPressed: () => Navigator.of(context).pop(),
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
        final currStop = appState.currentOrLastPassedStop;
        final distDestMeters = appState.distanceToDestinationMeters;
        final isUrgent = rem <= rules.startNotifyingStopsAway;

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
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
                                      Text(
                                        'ETA ${trip.arrivalTime} at ${appState.destinationStation.shortName}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: pal.textPrimary,
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
                        // Current vs Destination Bar
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: pal.scaffoldBg.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Last/At: ${currStop?.stationName ?? appState.originStation.shortName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: pal.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                'Alerting ≤ ${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"} away',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: pal.trackBadgeBg,
                                ),
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

                  // Interactive Commute Simulator Controls (Test GPS/Stop progression anytime!)
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
                            Text(
                              'Ride & Alert Simulator (Test Mode)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: pal.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Step through stops to test notifications',
                              style: TextStyle(
                                fontSize: 11,
                                color: pal.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: rem > 0
                                    ? () => appState.simulateNextStop()
                                    : null,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 18,
                                ),
                                label: const Text('+1 Stop (Test Alert)'),
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
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Animated Train & Stop Progression Map
                  AnimatedTrainTimeline(
                    palette: pal,
                    stops: appState.activeCommuteStops,
                    currentStopIndex: appState.currentStopIndex,
                    segmentProgress: appState.segmentProgress,
                    alertStopsAwayThreshold: rules.startNotifyingStopsAway,
                    trainId: trip.trainId,
                    track: trip.track,
                  ),
                  const SizedBox(height: 14),

                  // Live Notification Customizer Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: pal.cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: pal.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.notifications_active_rounded,
                              size: 19,
                              color: pal.primaryAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Customize Stop Notifications',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: pal.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Start alerting me when X stops away from ${appState.destinationStation.shortName}:',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [1, 2, 3, 4, 5].map((count) {
                            final selected =
                                rules.startNotifyingStopsAway == count;
                            return ChoiceChip(
                              label: Text(
                                '$count ${count == 1 ? "stop" : "stops"} away',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? const Color(0xFF0F172A)
                                      : pal.textPrimary,
                                ),
                              ),
                              selected: selected,
                              selectedColor: pal.primaryAccent,
                              onSelected: (_) {
                                appState.updateNotificationRules(
                                  rules.copyWith(
                                    startNotifyingStopsAway: count,
                                  ),
                                );
                              },
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
                          Navigator.of(context).pop();
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
