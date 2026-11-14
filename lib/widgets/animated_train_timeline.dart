import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/train_trip.dart';
import '../theme/anime_theme.dart';

class AnimatedTrainTimeline extends StatefulWidget {
  final AnimeThemePalette palette;
  final List<TrainStop> stops;
  final int currentStopIndex;
  final double segmentProgress;
  final int alertStopsAwayThreshold;
  final String trainId;
  final String? track;

  const AnimatedTrainTimeline({
    super.key,
    required this.palette,
    required this.stops,
    required this.currentStopIndex,
    required this.segmentProgress,
    required this.alertStopsAwayThreshold,
    required this.trainId,
    this.track,
  });

  @override
  State<AnimatedTrainTimeline> createState() => _AnimatedTrainTimelineState();
}

class _AnimatedTrainTimelineState extends State<AnimatedTrainTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chugController;

  @override
  void initState() {
    super.initState();
    _chugController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _chugController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.palette;
    final stops = widget.stops;
    if (stops.isEmpty) return const SizedBox.shrink();

    final totalIndex = stops.length - 1;
    final overallProgress = totalIndex > 0
        ? ((widget.currentStopIndex + widget.segmentProgress) / totalIndex)
            .clamp(0.0, 1.0)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Animated Cute Chibi Train Track Banner
        AnimatedBuilder(
          animation: _chugController,
          builder: (context, _) {
            final bounce = math.sin(_chugController.value * math.pi) * 2.5;
            return Container(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: pal.cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: pal.cardBorder, width: 1.2),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth =
                      (constraints.maxWidth - 68).clamp(40.0, 2000.0);
                  final trainLeft = trackWidth * overallProgress;

                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Rail sleepers & track line
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 10,
                        child: CustomPaint(
                          size: Size(constraints.maxWidth - 32, 10),
                          painter: _RailTrackPainter(
                            progress: overallProgress,
                            activeColor: pal.primaryAccent,
                            mutedColor: pal.textSecondary.withOpacity(0.28),
                          ),
                        ),
                      ),
                      // Origin & Destination mini flags
                      Positioned(
                        left: 4,
                        top: 2,
                        child: Text(
                          stops.first.stationCode,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: pal.textSecondary,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.flag_rounded,
                              size: 13,
                              color: pal.urgentColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              stops.last.stationCode,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: pal.urgentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Animated Chibi Train Car
                      Positioned(
                        left: trainLeft,
                        bottom: 14 + bounce,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: pal.primaryAccent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: pal.primaryAccent.withOpacity(0.45),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.train_rounded,
                                size: 15,
                                color: Color(0xFF0F172A),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '#${widget.trainId}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 14),

        // Vertical Stop-by-Stop Commute Progression List
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pal.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: pal.cardBorder, width: 1.2),
          ),
          child: Column(
            children: List.generate(stops.length, (index) {
              final stop = stops[index];
              final isOrigin = index == 0;
              final isDestination = index == stops.length - 1;
              final isPassed = index < widget.currentStopIndex;
              final isCurrent = index == widget.currentStopIndex;
              final stopsAwayFromDest = (stops.length - 1) - index;
              final isInAlertZone = !isDestination &&
                  stopsAwayFromDest > 0 &&
                  stopsAwayFromDest <= widget.alertStopsAwayThreshold;

              Color dotColor;
              if (isCurrent) {
                dotColor = pal.primaryAccent;
              } else if (isPassed) {
                dotColor = pal.successColor;
              } else if (isDestination) {
                dotColor = pal.urgentColor;
              } else if (isInAlertZone) {
                dotColor = pal.trackBadgeBg;
              } else {
                dotColor = pal.textSecondary.withOpacity(0.4);
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left timeline rail & station node
                    SizedBox(
                      width: 32,
                      child: Column(
                        children: [
                          Container(
                            width: isCurrent ? 22 : 16,
                            height: isCurrent ? 22 : 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                              border: Border.all(
                                color: pal.scaffoldBg,
                                width: 2.5,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: pal.primaryAccent.withOpacity(0.55),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isPassed
                                ? const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.black,
                                  )
                                : isCurrent
                                    ? const Icon(
                                        Icons.train,
                                        size: 11,
                                        color: Colors.black,
                                      )
                                    : null,
                          ),
                          if (!isDestination)
                            Expanded(
                              child: Container(
                                width: 3,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPassed
                                      ? pal.successColor
                                      : pal.textSecondary.withOpacity(0.22),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Right station info row
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: isDestination ? 2 : 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          stop.stationName,
                                          style: TextStyle(
                                            fontSize: isCurrent || isDestination
                                                ? 15
                                                : 14,
                                            fontWeight: isCurrent || isDestination
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: isPassed
                                                ? pal.textSecondary
                                                : pal.textPrimary,
                                            decoration: isPassed
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isOrigin)
                                        _buildMiniPill(
                                          'BOARDED',
                                          pal.primaryAccent.withOpacity(0.18),
                                          pal.primaryAccent,
                                        )
                                      else if (isDestination)
                                        _buildMiniPill(
                                          'MY STOP ★',
                                          pal.urgentColor.withOpacity(0.2),
                                          pal.urgentColor,
                                        )
                                      else if (isInAlertZone)
                                        _buildMiniPill(
                                          '🔔 $stopsAwayFromDest ${stopsAwayFromDest == 1 ? "STOP" : "STOPS"} LEFT',
                                          pal.trackBadgeBg.withOpacity(0.22),
                                          pal.isDark
                                              ? pal.trackBadgeBg
                                              : const Color(0xFF92400E),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isCurrent
                                        ? (isDestination
                                            ? 'Arrived at destination platform!'
                                            : 'Train is currently here / departing → Next stop ahead')
                                        : isPassed
                                            ? 'Cleared station'
                                            : isDestination
                                                ? 'Get ready to exit here'
                                                : '$stopsAwayFromDest ${stopsAwayFromDest == 1 ? "stop" : "stops"} before ${stops.last.stationCode}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isCurrent
                                          ? pal.primaryAccent
                                          : pal.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              stop.estimatedTime,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isPassed
                                    ? pal.textSecondary
                                    : pal.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniPill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _RailTrackPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color mutedColor;

  _RailTrackPainter({
    required this.progress,
    required this.activeColor,
    required this.mutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = mutedColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), basePaint);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * progress, y),
      activePaint,
    );

    // Draw railroad ties (sleepers)
    const tieCount = 18;
    for (int i = 0; i <= tieCount; i++) {
      final x = (i / tieCount) * size.width;
      final isDone = (i / tieCount) <= progress;
      canvas.drawLine(
        Offset(x, y - 3.5),
        Offset(x, y + 3.5),
        Paint()
          ..color = isDone ? activeColor : mutedColor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RailTrackPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
