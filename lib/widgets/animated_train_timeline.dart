import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _worldScroll = 0.0;
  double _timeSec = 0.0;
  double _currentSpeedMultiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  double _computeTargetSpeedMultiplier() {
    final stops = widget.stops;
    if (stops.isEmpty) return 0.0;
    final isAtDestination = widget.currentStopIndex >= stops.length - 1;
    if (isAtDestination) return 0.0;

    final seg = widget.segmentProgress.clamp(0.0, 1.0);
    final stopsLeft = (stops.length - 1) - widget.currentStopIndex;

    // Speed profile within each station-to-station segment:
    // - Just departed station (seg 0.00..0.15): smooth acceleration (0.42 -> 1.0)
    // - Mid-segment cruise (seg 0.15..0.75): fast cruise (1.15, or 1.35 on express)
    // - Approaching next station (seg 0.75..1.00): smooth braking/deceleration (1.0 -> 0.25)
    double baseSpeed;
    if (seg < 0.15) {
      final t = (seg / 0.15).clamp(0.0, 1.0);
      baseSpeed = 0.42 + (0.68 * t);
    } else if (seg > 0.75) {
      final t = ((seg - 0.75) / 0.25).clamp(0.0, 1.0);
      baseSpeed = 1.10 - (0.82 * t);
    } else {
      baseSpeed = stops.length <= 5 ? 1.32 : 1.12;
    }

    // Slightly gentler approach when 1 stop away from final destination
    if (stopsLeft == 1 && seg > 0.65) {
      baseSpeed *= 0.75;
    }
    return baseSpeed.clamp(0.0, 1.5);
  }

  void _onTick(Duration elapsed) {
    final dt = (_lastElapsed == Duration.zero)
        ? 0.016
        : ((elapsed - _lastElapsed).inMicroseconds / 1000000.0).clamp(0.0, 0.05);
    _lastElapsed = elapsed;

    final targetSpeed = _computeTargetSpeedMultiplier();
    // Smoothly interpolate speed so acceleration & braking feel natural
    _currentSpeedMultiplier += (targetSpeed - _currentSpeedMultiplier) * (dt * 4.5).clamp(0.0, 1.0);
    _timeSec += dt;
    _worldScroll = (_worldScroll + dt * 115.0 * _currentSpeedMultiplier) % 100000.0;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _sceneLabel(double overallProgress) {
    if (overallProgress < 0.36) {
      return '🗾 Countryside';
    } else if (overallProgress < 0.64) {
      return '🚇 Mountain Tunnel';
    } else {
      return '🗼 Tokyo Skyline';
    }
  }

  String _motionLabel() {
    final stops = widget.stops;
    if (stops.isEmpty || widget.currentStopIndex >= stops.length - 1) {
      return '★ Arrived at Platform';
    }
    final seg = widget.segmentProgress;
    if (seg > 0.75) {
      return '🛑 Slowing for Next Stop';
    }
    if (seg < 0.12) {
      return '🚉 Accelerating from Stop';
    }
    return stops.length <= 5 ? '⚡ Express Cruise' : '🚆 Cruising';
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

    final sceneText = _sceneLabel(overallProgress);
    final motionText = _motionLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Charming Side-View Scenic Train Diorama (Countryside -> Tunnel -> Tokyo)
        Container(
          height: 138,
          decoration: BoxDecoration(
            color: pal.cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: pal.cardBorder, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: pal.primaryAccent.withOpacity(pal.isDark ? 0.12 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScenicTrainDioramaPainter(
                      palette: pal,
                      overallProgress: overallProgress,
                      segmentProgress: widget.segmentProgress,
                      worldScroll: _worldScroll,
                      timeSec: _timeSec,
                      speedMultiplier: _currentSpeedMultiplier,
                      trainId: widget.trainId,
                    ),
                  ),
                ),
                // Top overlay pills: Scene Zone + Live Speed/Braking status + Route endpoints
                Positioned(
                  left: 10,
                  right: 10,
                  top: 8,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(pal.isDark ? 0.52 : 0.42),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        child: Text(
                          '$sceneText • $motionText',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(pal.isDark ? 0.52 : 0.42),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: pal.primaryAccent.withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          '${stops.first.stationCode} → ${stops.last.stationCode} (${(overallProgress * 100).round()}%)',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

class _ScenicTrainDioramaPainter extends CustomPainter {
  final AnimeThemePalette palette;
  final double overallProgress;
  final double segmentProgress;
  final double worldScroll;
  final double timeSec;
  final double speedMultiplier;
  final String trainId;

  _ScenicTrainDioramaPainter({
    required this.palette,
    required this.overallProgress,
    required this.segmentProgress,
    required this.worldScroll,
    required this.timeSec,
    required this.speedMultiplier,
    required this.trainId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isSakura = palette.id == 'sakura';
    final isDark = palette.isDark;
    final groundY = size.height - 22.0;

    // Determine blend weights for the 3 scenic zones:
    // Zone 1 (0.00 - 0.36): Japanese Countryside (Mt. Fuji, Torii gate, hills, cedar trees)
    // Zone 2 (0.36 - 0.64): Mountain Tunnel (dark tunnel arch, glowing amber wall lights)
    // Zone 3 (0.64 - 1.00): Tokyo Metropolis (Tokyo Tower, skyscrapers, glowing city windows)
    double tunnelWeight = 0.0;
    if (overallProgress >= 0.32 && overallProgress <= 0.68) {
      if (overallProgress < 0.40) {
        tunnelWeight = ((overallProgress - 0.32) / 0.08).clamp(0.0, 1.0);
      } else if (overallProgress > 0.60) {
        tunnelWeight = ((0.68 - overallProgress) / 0.08).clamp(0.0, 1.0);
      } else {
        tunnelWeight = 1.0;
      }
    }
    final isTokyoZone = overallProgress >= 0.50;

    // 1. Sky Gradient (adapts to MyGO vs Sakura and Dark vs Light mode)
    final List<Color> skyColors;
    if (isSakura) {
      skyColors = isDark
          ? [const Color(0xFF1A1025), const Color(0xFF351B42), const Color(0xFF582757)]
          : [const Color(0xFFFFDFE9), const Color(0xFFFFEEF4), const Color(0xFFFFF8FB)];
    } else {
      skyColors = isDark
          ? [const Color(0xFF070C18), const Color(0xFF0F1E36), const Color(0xFF1A3152)]
          : [const Color(0xFF7DD3FC), const Color(0xFFBAE6FD), const Color(0xFFE0F2FE)];
    }

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: skyColors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, groundY));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, groundY), skyPaint);

    // 2. Celestial body (Moon / Sun) & twinkling stars in dark mode
    if (isDark) {
      final starPaint = Paint()..color = Colors.white.withOpacity(0.55);
      for (int i = 0; i < 16; i++) {
        final sx = ((i * 53.0) + 19.0) % size.width;
        final sy = ((i * 19.0) + 10.0) % (groundY * 0.55);
        final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(timeSec * 3.0 + i));
        starPaint.color = Colors.white.withOpacity(twinkle * (1.0 - tunnelWeight));
        canvas.drawCircle(Offset(sx, sy), (i % 3 == 0) ? 1.5 : 1.0, starPaint);
      }
      // Soft glowing moon
      if (tunnelWeight < 0.95) {
        final moonCenter = Offset(size.width * 0.82, 34);
        canvas.drawCircle(
          moonCenter,
          14,
          Paint()
            ..color = (isSakura ? const Color(0xFFFDE68A) : const Color(0xFFE0F2FE))
                .withOpacity(0.22 * (1.0 - tunnelWeight)),
        );
        canvas.drawCircle(
          moonCenter,
          9,
          Paint()
            ..color = (isSakura ? const Color(0xFFFEF08A) : const Color(0xFFF8FAFC))
                .withOpacity(0.88 * (1.0 - tunnelWeight)),
        );
      }
    } else {
      // Soft daytime sun & drifting clouds
      final sunCenter = Offset(size.width * 0.82, 34);
      canvas.drawCircle(
        sunCenter,
        12,
        Paint()
          ..color = (isSakura ? const Color(0xFFF472B6) : const Color(0xFFFBBF24))
              .withOpacity(0.35 * (1.0 - tunnelWeight)),
      );
    }

    // 3. Far & Mid Scenery: Japanese Countryside vs Tokyo Metropolis
    if (!isTokyoZone) {
      _paintJapaneseCountryside(canvas, size, groundY, isDark, isSakura);
    } else {
      _paintTokyoMetropolis(canvas, size, groundY, isDark, isSakura);
    }

    // 4. Tunnel Overlay & Interior when passing through Zone 2 (0.32..0.68)
    if (tunnelWeight > 0.01) {
      _paintTunnelZone(canvas, size, groundY, tunnelWeight, isSakura);
    }

    // 5. Overhead Catenary Poles & Wires (scrolling faster in foreground)
    _paintCatenaryWires(canvas, size, groundY, isDark, tunnelWeight);

    // 6. Track Ballast, Sleepers & Steel Rails
    _paintTrackBed(canvas, size, groundY, isDark);

    // 7. Cute Multi-Car Side-View Commuter Train (with speed/braking physics & headlights)
    _paintSideViewTrain(
      canvas,
      size,
      groundY,
      isDark: isDark,
      isSakura: isSakura,
      inTunnel: tunnelWeight > 0.45,
    );

    // 8. Theme Weather Particles (Sakura blossoms or MyGO starry rain outside tunnel)
    if (tunnelWeight < 0.7) {
      _paintThemeWeather(
        canvas,
        size,
        groundY,
        isSakura: isSakura,
        isDark: isDark,
        opacityScale: 1.0 - tunnelWeight,
      );
    }
  }

  void _paintJapaneseCountryside(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    bool isSakura,
  ) {
    // Slow parallax Mt. Fuji in background
    final fujiShift = (worldScroll * 0.06) % (size.width + 220);
    final fujiCenterX = size.width * 0.62 - (fujiShift * 0.18);
    final fujiBaseY = groundY;
    final fujiPeakY = 30.0;

    final fujiBodyColor = isDark
        ? (isSakura ? const Color(0xFF4A2545) : const Color(0xFF1E3A5F))
        : (isSakura ? const Color(0xFF9D759B) : const Color(0xFF3B82F6));

    final fujiPath = Path()
      ..moveTo(fujiCenterX - 95, fujiBaseY)
      ..quadraticBezierTo(fujiCenterX - 28, fujiPeakY + 26, fujiCenterX - 10, fujiPeakY)
      ..lineTo(fujiCenterX + 10, fujiPeakY)
      ..quadraticBezierTo(fujiCenterX + 28, fujiPeakY + 26, fujiCenterX + 95, fujiBaseY)
      ..close();
    canvas.drawPath(fujiPath, Paint()..color = fujiBodyColor.withOpacity(0.85));

    // Mt. Fuji snow cap
    final snowPath = Path()
      ..moveTo(fujiCenterX - 10, fujiPeakY)
      ..lineTo(fujiCenterX + 10, fujiPeakY)
      ..quadraticBezierTo(fujiCenterX + 16, fujiPeakY + 12, fujiCenterX + 24, fujiPeakY + 22)
      ..lineTo(fujiCenterX + 10, fujiPeakY + 17)
      ..lineTo(fujiCenterX, fujiPeakY + 23)
      ..lineTo(fujiCenterX - 10, fujiPeakY + 17)
      ..lineTo(fujiCenterX - 24, fujiPeakY + 22)
      ..quadraticBezierTo(fujiCenterX - 16, fujiPeakY + 12, fujiCenterX - 10, fujiPeakY)
      ..close();
    canvas.drawPath(
      snowPath,
      Paint()..color = Colors.white.withOpacity(isDark ? 0.85 : 0.95),
    );

    // Rolling countryside hills (midground parallax)
    final hillColor1 = isDark
        ? (isSakura ? const Color(0xFF2D1936) : const Color(0xFF132A3E))
        : (isSakura ? const Color(0xFFFBCFE8) : const Color(0xFF86EFAC));
    final hillColor2 = isDark
        ? (isSakura ? const Color(0xFF23132B) : const Color(0xFF0F2233))
        : (isSakura ? const Color(0xFFF9A8D4) : const Color(0xFF4ADE80));

    final hillPath = Path()..moveTo(0, groundY);
    const hillSpan = 140.0;
    final hillOffset = (worldScroll * 0.25) % hillSpan;
    for (double x = -hillSpan; x <= size.width + hillSpan; x += hillSpan) {
      final hx = x - hillOffset;
      hillPath.quadraticBezierTo(
        hx + hillSpan * 0.5,
        groundY - 28,
        hx + hillSpan,
        groundY,
      );
    }
    hillPath.lineTo(size.width, groundY);
    hillPath.close();
    canvas.drawPath(hillPath, Paint()..color = hillColor1);

    // Foreground bushes, trees, and iconic red Torii gate scrolling past
    const propSpacing = 190.0;
    final propOffset = (worldScroll * 0.55) % propSpacing;
    for (double base = -propSpacing; base <= size.width + propSpacing; base += propSpacing) {
      final px = base - propOffset;
      // Draw a traditional Red Torii Gate
      final toriiX = px + 40;
      final toriiPaint = Paint()
        ..color = isDark ? const Color(0xFFDC2626) : const Color(0xFFEF4444)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      // Two vertical pillars
      canvas.drawLine(Offset(toriiX - 7, groundY), Offset(toriiX - 6, groundY - 22), toriiPaint);
      canvas.drawLine(Offset(toriiX + 7, groundY), Offset(toriiX + 6, groundY - 22), toriiPaint);
      // Top kasagi lintel bar
      canvas.drawLine(Offset(toriiX - 12, groundY - 22), Offset(toriiX + 12, groundY - 22), toriiPaint);
      // Lower nuki tie beam
      canvas.drawLine(Offset(toriiX - 9, groundY - 16), Offset(toriiX + 9, groundY - 16), toriiPaint);

      // Draw cedar / sakura trees nearby
      for (int t = 0; t < 3; t++) {
        final tx = px + 100 + t * 26.0;
        final treeCrownColor = isSakura
            ? (isDark ? const Color(0xFFEC4899) : const Color(0xFFF472B6))
            : hillColor2;
        canvas.drawRect(
          Rect.fromLTWH(tx - 1.5, groundY - 10, 3, 10),
          Paint()..color = const Color(0xFF78350F),
        );
        canvas.drawCircle(
          Offset(tx, groundY - 14 - (t % 2) * 3),
          8.5,
          Paint()..color = treeCrownColor.withOpacity(0.9),
        );
      }
    }
  }

  void _paintTokyoMetropolis(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    bool isSakura,
  ) {
    // Tokyo Tower in mid-background
    final towerShift = (worldScroll * 0.14) % (size.width + 240);
    final towerX = size.width * 0.72 - (towerShift * 0.25);
    final towerBaseY = groundY;
    final towerTopY = 20.0;

    final towerRed = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    final towerWhite = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2.2;

    // Tokyo Tower Eiffel-like curved legs & spire
    final towerPath = Path()
      ..moveTo(towerX - 18, towerBaseY)
      ..quadraticBezierTo(towerX - 5, towerBaseY - 40, towerX - 2, towerTopY + 14)
      ..lineTo(towerX + 2, towerTopY + 14)
      ..quadraticBezierTo(towerX + 5, towerBaseY - 40, towerX + 18, towerBaseY);
    canvas.drawPath(towerPath, towerRed);
    // Spire antenna
    canvas.drawLine(Offset(towerX, towerTopY), Offset(towerX, towerTopY + 14), towerRed);
    // White bands & observation decks
    canvas.drawLine(Offset(towerX - 11, towerBaseY - 26), Offset(towerX + 11, towerBaseY - 26), towerWhite);
    canvas.drawLine(Offset(towerX - 6, towerBaseY - 52), Offset(towerX + 6, towerBaseY - 52), towerWhite);
    if (isDark) {
      canvas.drawCircle(
        Offset(towerX, towerTopY),
        2.5,
        Paint()..color = const Color(0xFFFBBF24),
      );
    }

    // Scrolling Tokyo skyscrapers with glowing windows
    const cityRepeat = 240.0;
    final cityOffset = (worldScroll * 0.38) % cityRepeat;
    final bldgWidths = [28.0, 36.0, 24.0, 42.0, 30.0, 34.0];
    final bldgHeights = [58.0, 76.0, 46.0, 84.0, 62.0, 52.0];

    for (double base = -cityRepeat; base <= size.width + cityRepeat; base += cityRepeat) {
      double cursorX = base - cityOffset;
      for (int i = 0; i < bldgWidths.length; i++) {
        final bw = bldgWidths[i];
        final bh = bldgHeights[i];
        final bx = cursorX;
        final by = groundY - bh;
        cursorX += bw + 10.0;

        if (bx + bw < -10 || bx > size.width + 10) continue;

        final bldgColor = isDark
            ? (isSakura ? const Color(0xFF231530) : const Color(0xFF111C2D))
            : (isSakura ? const Color(0xFFE2C6DC) : const Color(0xFF94A3B8));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, by, bw, bh),
            const Radius.circular(3),
          ),
          Paint()..color = bldgColor,
        );

        // Glowing office / apartment window grid
        final winColor = isDark
            ? ((i.isEven)
                ? const Color(0xFFFDE047).withOpacity(0.75)
                : palette.primaryAccent.withOpacity(0.65))
            : Colors.white.withOpacity(0.65);
        final winPaint = Paint()..color = winColor;

        for (double wy = by + 7; wy < groundY - 8; wy += 9) {
          for (double wx = bx + 5; wx < bx + bw - 6; wx += 7) {
            if (((wx.toInt() + wy.toInt() + i) % 3) != 0) {
              canvas.drawRect(Rect.fromLTWH(wx, wy, 3.5, 4.5), winPaint);
            }
          }
        }
      }
    }
  }

  void _paintTunnelZone(
    Canvas canvas,
    Size size,
    double groundY,
    double tunnelWeight,
    bool isSakura,
  ) {
    // Dark arched tunnel interior
    final tunnelBg = Paint()
      ..color = const Color(0xFF06080F).withOpacity(0.92 * tunnelWeight);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, groundY), tunnelBg);

    // Concrete tunnel ceiling arch rib lines scrolling past quickly
    const ribSpacing = 70.0;
    final ribOffset = (worldScroll * 1.15) % ribSpacing;
    final ribPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.55 * tunnelWeight)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    for (double x = -ribSpacing; x <= size.width + ribSpacing; x += ribSpacing) {
      final rx = x - ribOffset;
      canvas.drawLine(Offset(rx, 16), Offset(rx, groundY), ribPaint);
      // Glowing warm amber tunnel wall lights!
      final lampCenter = Offset(rx + 25, groundY - 46);
      canvas.drawCircle(
        lampCenter,
        11,
        Paint()
          ..color = const Color(0xFFF59E0B).withOpacity(0.28 * tunnelWeight),
      );
      canvas.drawCircle(
        lampCenter,
        3.2,
        Paint()
          ..color = const Color(0xFFFDE047).withOpacity(0.95 * tunnelWeight),
      );
    }
  }

  void _paintCatenaryWires(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    double tunnelWeight,
  ) {
    final wireY = groundY - 54.0;
    final wirePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black)
          .withOpacity(0.24 * (1.0 - tunnelWeight * 0.5))
      ..strokeWidth = 1.1;

    // Contact wire
    canvas.drawLine(Offset(0, wireY), Offset(size.width, wireY), wirePaint);

    // Overhead catenary masts scrolling in foreground
    const mastSpacing = 135.0;
    final mastOffset = (worldScroll * 0.85) % mastSpacing;
    final mastPaint = Paint()
      ..color = (isDark ? const Color(0xFF64748B) : const Color(0xFF475569))
          .withOpacity(0.55)
      ..strokeWidth = 2.2;

    for (double x = -mastSpacing; x <= size.width + mastSpacing; x += mastSpacing) {
      final mx = x - mastOffset;
      canvas.drawLine(Offset(mx, wireY - 8), Offset(mx, groundY), mastPaint);
      canvas.drawLine(Offset(mx - 8, wireY), Offset(mx + 8, wireY), mastPaint);
    }
  }

  void _paintTrackBed(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
  ) {
    // Ballast gravel bed
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      Paint()
        ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
    );

    // Steel rail line
    canvas.drawLine(
      Offset(0, groundY + 2),
      Offset(size.width, groundY + 2),
      Paint()
        ..color = palette.primaryAccent.withOpacity(0.85)
        ..strokeWidth = 2.6,
    );

    // Scrolling wooden/concrete ties (sleepers)
    const tieSpacing = 16.0;
    final tieOffset = (worldScroll * 1.25) % tieSpacing;
    final tiePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.32)
      ..strokeWidth = 3.0;

    for (double x = -tieSpacing; x <= size.width + tieSpacing; x += tieSpacing) {
      final tx = x - tieOffset;
      canvas.drawLine(Offset(tx, groundY + 3), Offset(tx - 3, groundY + 9), tiePaint);
    }
  }

  void _paintSideViewTrain(
    Canvas canvas,
    Size size,
    double groundY, {
    required bool isDark,
    required bool isSakura,
    required bool inTunnel,
  }) {
    // Subtle suspension bounce when moving
    final bounce = speedMultiplier > 0.05
        ? math.sin(timeSec * 14.0 * speedMultiplier.clamp(0.4, 1.3)) * 1.1
        : 0.0;

    // Position the 2-car cute anime commuter train near center-left facing right
    final leadCarWidth = 104.0;
    final rearCarWidth = 86.0;
    final carHeight = 32.0;
    final gap = 6.0;
    final totalTrainWidth = leadCarWidth + gap + rearCarWidth;
    final startX = (size.width - totalTrainWidth) * 0.46;
    final carTopY = groundY - carHeight - 5.0 + bounce;

    // Headlight beam (stronger in dark mode or inside the tunnel!)
    if (isDark || inTunnel) {
      final noseX = startX + totalTrainWidth;
      final beamPath = Path()
        ..moveTo(noseX - 2, carTopY + 18)
        ..lineTo(noseX + 95, carTopY + 2)
        ..lineTo(noseX + 95, groundY + 2)
        ..lineTo(noseX - 2, carTopY + 28)
        ..close();
      canvas.drawPath(
        beamPath,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFFFEF08A).withOpacity(inTunnel ? 0.48 : 0.30),
              const Color(0xFFFEF08A).withOpacity(0.0),
            ],
          ).createShader(Rect.fromLTWH(noseX, carTopY, 95, 40)),
      );
    }

    // Draw Rear Car + Lead Streamlined Car
    _drawSingleTrainCar(
      canvas,
      left: startX,
      top: carTopY,
      width: rearCarWidth,
      height: carHeight,
      isLeadCar: false,
      isDark: isDark,
      isSakura: isSakura,
      inTunnel: inTunnel,
    );

    // Coupler accordion between cars
    canvas.drawRect(
      Rect.fromLTWH(startX + rearCarWidth, carTopY + 8, gap, carHeight - 12),
      Paint()..color = const Color(0xFF334155),
    );

    _drawSingleTrainCar(
      canvas,
      left: startX + rearCarWidth + gap,
      top: carTopY,
      width: leadCarWidth,
      height: carHeight,
      isLeadCar: true,
      isDark: isDark,
      isSakura: isSakura,
      inTunnel: inTunnel,
    );
  }

  void _drawSingleTrainCar(
    Canvas canvas, {
    required double left,
    required double top,
    required double width,
    required double height,
    required bool isLeadCar,
    required bool isDark,
    required bool isSakura,
    required bool inTunnel,
  }) {
    // Pantograph on roof touching overhead catenary wire
    final pantoX = left + width * 0.35;
    final pantoPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final pantoPath = Path()
      ..moveTo(pantoX - 6, top)
      ..lineTo(pantoX, top - 8)
      ..lineTo(pantoX + 6, top - 15)
      ..moveTo(pantoX - 4, top - 15)
      ..lineTo(pantoX + 10, top - 15);
    canvas.drawPath(pantoPath, pantoPaint);

    // Car body shape (streamlined aerodynamic nose on lead car)
    final bodyColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFFF8FAFC);
    final stripeColor = palette.primaryAccent;
    final subStripeColor = palette.secondaryAccent;

    final bodyPath = Path();
    if (isLeadCar) {
      bodyPath
        ..moveTo(left + 4, top)
        ..lineTo(left + width - 18, top)
        ..quadraticBezierTo(left + width - 3, top + 4, left + width, top + height - 6)
        ..quadraticBezierTo(left + width, top + height, left + width - 6, top + height)
        ..lineTo(left + 4, top + height)
        ..quadraticBezierTo(left, top + height, left, top + height - 4)
        ..lineTo(left, top + 4)
        ..quadraticBezierTo(left, top, left + 4, top)
        ..close();
    } else {
      bodyPath.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, width, height),
          const Radius.circular(5),
        ),
      );
    }

    canvas.save();
    canvas.clipPath(bodyPath);

    // Base body paint
    canvas.drawPath(bodyPath, Paint()..color = bodyColor);

    // Roof dark metallic trim
    canvas.drawRect(
      Rect.fromLTWH(left, top, width, 4.5),
      Paint()..color = const Color(0xFF334155),
    );

    // Signature Anime Livery Stripe across waist
    canvas.drawRect(
      Rect.fromLTWH(left, top + height - 11.5, width, 5.0),
      Paint()..color = stripeColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, top + height - 6.5, width, 2.5),
      Paint()..color = subStripeColor,
    );

    // Glowing passenger windows
    final windowGlow = (isDark || inTunnel)
        ? (isSakura ? const Color(0xFFFEF08A) : const Color(0xFFBAE6FD))
        : const Color(0xFF0284C7).withOpacity(0.75);
    final winCount = isLeadCar ? 4 : 4;
    for (int w = 0; w < winCount; w++) {
      final wx = left + 8.0 + w * 19.5;
      final wy = top + 7.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(wx, wy, 13.5, 9.5),
          const Radius.circular(2.5),
        ),
        Paint()..color = windowGlow,
      );
    }

    // Driver cockpit windshield on lead car
    if (isLeadCar) {
      final cabPath = Path()
        ..moveTo(left + width - 19, top + 6.5)
        ..lineTo(left + width - 7, top + 8.5)
        ..lineTo(left + width - 3, top + 16.5)
        ..lineTo(left + width - 19, top + 16.5)
        ..close();
      canvas.drawPath(
        cabPath,
        Paint()..color = const Color(0xFF0F172A),
      );
      // Warm headlight lens
      canvas.drawCircle(
        Offset(left + width - 3.0, top + height - 8.5),
        2.6,
        Paint()..color = const Color(0xFFFDE047),
      );

      // Train ID mini plate on lead car side
      final tp = TextPainter(
        text: TextSpan(
          text: '#$trainId',
          style: const TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left + 8, top + height - 11));
    }

    canvas.restore();

    // Car outline
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = const Color(0xFF475569).withOpacity(0.55)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    // Bogies & Wheels underneath
    final wheelY = top + height + 2.5;
    final wheelPositions = [
      left + 14,
      left + 25,
      left + width - 28,
      left + width - 17,
    ];
    for (final wx in wheelPositions) {
      canvas.drawCircle(
        Offset(wx, wheelY),
        3.6,
        Paint()..color = const Color(0xFF1E293B),
      );
      canvas.drawCircle(
        Offset(wx, wheelY),
        1.5,
        Paint()..color = const Color(0xFF94A3B8),
      );
    }
  }

  void _paintThemeWeather(
    Canvas canvas,
    Size size,
    double groundY, {
    required bool isSakura,
    required bool isDark,
    required double opacityScale,
  }) {
    final paint = Paint()
      ..color = palette.primaryAccent.withOpacity(0.32 * opacityScale);
    const count = 12;
    for (int i = 0; i < count; i++) {
      final px = ((i * 47.0) - (worldScroll * 0.45) + 10000.0) % size.width;
      final py = ((i * 23.0) + (timeSec * 28.0)) % (groundY - 8);
      if (isSakura) {
        canvas.save();
        canvas.translate(px, py);
        canvas.rotate(timeSec * 2.0 + i);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 6.0, height: 3.5),
          paint,
        );
        canvas.restore();
      } else {
        // MyGO Starry Rain diagonal streaks
        canvas.drawLine(
          Offset(px, py),
          Offset(px - 6, py + 9),
          paint..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScenicTrainDioramaPainter oldDelegate) => true;
}
