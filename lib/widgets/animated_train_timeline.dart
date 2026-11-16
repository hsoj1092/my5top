import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/train_trip.dart';
import '../theme/anime_theme.dart';

enum _JpProp {
  toriiShrine,
  lawson,
  sevenEleven,
  ramenShop,
  machiyaHouse,
  modernJpHouse,
  jpTownBuilding,
  pagodaTeaHouse,
}

class AnimatedTrainTimeline extends StatefulWidget {
  final AnimeThemePalette palette;
  final List<TrainStop> stops;
  final int currentStopIndex;
  final double segmentProgress;
  final int alertStopsAwayThreshold;
  final String trainId;
  final String? track;
  final int sceneSeed;
  final int variationIndex;

  const AnimatedTrainTimeline({
    super.key,
    required this.palette,
    required this.stops,
    required this.currentStopIndex,
    required this.segmentProgress,
    required this.alertStopsAwayThreshold,
    required this.trainId,
    this.track,
    this.sceneSeed = 0,
    this.variationIndex = 0,
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
  double _displayedOverallProgress = 0.0;

  static const List<String> _variationTitles = [
    '⛩️ Torii & Konbini Town',
    '🍜 Ramen & Yokocho Run',
    '🏘️ Machiya & Shrine Line',
    '🏪 Konbini & Neon Street',
    '🌸 Sakura Shrine & Shops',
  ];

  @override
  void initState() {
    super.initState();
    _displayedOverallProgress = _computeRawOverallProgress();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant AnimatedTrainTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trainId != widget.trainId ||
        oldWidget.sceneSeed != widget.sceneSeed) {
      _displayedOverallProgress = _computeRawOverallProgress();
    }
  }

  double _computeRawOverallProgress() {
    final stops = widget.stops;
    if (stops.isEmpty) return 0.0;
    final totalIndex = stops.length - 1;
    if (totalIndex <= 0) return 1.0;
    return ((widget.currentStopIndex + widget.segmentProgress) / totalIndex)
        .clamp(0.0, 1.0);
  }

  double _computeTargetSpeedMultiplier() {
    final stops = widget.stops;
    if (stops.isEmpty) return 0.0;
    final isAtDestination = widget.currentStopIndex >= stops.length - 1;
    if (isAtDestination) return 0.0;

    final seg = widget.segmentProgress.clamp(0.0, 1.0);
    final stopsLeft = (stops.length - 1) - widget.currentStopIndex;

    // Speed profile within each station-to-station segment:
    // - Just departed station (seg 0.00..0.15): smooth acceleration (0.42 -> 1.10)
    // - Mid-segment cruise (seg 0.15..0.75): fast cruise (1.12, or 1.32 on express)
    // - Approaching next station (seg 0.75..1.00): smooth braking/deceleration (1.10 -> 0.28)
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
        : ((elapsed - _lastElapsed).inMicroseconds / 1000000.0)
            .clamp(0.0, 0.05);
    _lastElapsed = elapsed;

    final targetSpeed = _computeTargetSpeedMultiplier();
    // Smoothly interpolate speed & overall trip progress so Mt. Fuji glides naturally
    _currentSpeedMultiplier +=
        (targetSpeed - _currentSpeedMultiplier) * (dt * 4.5).clamp(0.0, 1.0);

    final targetProgress = _computeRawOverallProgress();
    _displayedOverallProgress +=
        (targetProgress - _displayedOverallProgress) *
            (dt * 3.6).clamp(0.0, 1.0);

    _timeSec += dt;
    _worldScroll += dt * 112.0 * _currentSpeedMultiplier;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _sceneLabel() {
    final idx = widget.variationIndex.abs() % _variationTitles.length;
    return _variationTitles[idx];
  }

  String _motionLabel() {
    final stops = widget.stops;
    if (stops.isEmpty || widget.currentStopIndex >= stops.length - 1) {
      return '★ Arrived';
    }
    final seg = widget.segmentProgress;
    if (seg > 0.75) {
      return '🛑 Braking';
    }
    if (seg < 0.12) {
      return '🚉 Departing';
    }
    return stops.length <= 5 ? '⚡ Express' : '🚆 Cruising';
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.palette;
    final stops = widget.stops;
    if (stops.isEmpty) return const SizedBox.shrink();

    final overallProgress = _computeRawOverallProgress();
    final sceneText = _sceneLabel();
    final motionText = _motionLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Charming Side-View Japanese Scenic Train Diorama
        Container(
          height: 148,
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
                      overallProgress: _displayedOverallProgress,
                      segmentProgress: widget.segmentProgress,
                      worldScroll: _worldScroll,
                      timeSec: _timeSec,
                      speedMultiplier: _currentSpeedMultiplier,
                      trainId: widget.trainId,
                      sceneSeed: widget.sceneSeed,
                      variationIndex: widget.variationIndex,
                    ),
                  ),
                ),
                // Top overlay pills: Variation + Motion status + Route %
                Positioned(
                  left: 10,
                  right: 10,
                  top: 8,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black
                                .withOpacity(pal.isDark ? 0.54 : 0.44),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            '$sceneText • $motionText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black
                              .withOpacity(pal.isDark ? 0.54 : 0.44),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: pal.primaryAccent.withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          '${stops.first.stationCode} → ${stops.last.stationCode} (${(overallProgress * 100).round()}%)',
                          style: const TextStyle(
                            fontSize: 9.8,
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
                                        color: pal.primaryAccent
                                            .withOpacity(0.55),
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
                                margin:
                                    const EdgeInsets.symmetric(vertical: 2),
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
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Text(
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
                            const SizedBox(width: 8),
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
  final int sceneSeed;
  final int variationIndex;

  static final Map<String, TextPainter> _labelCache = {};

  // 5 Distinct Route Variations (selected randomly at check-in, then further shuffled per slot by sceneSeed)
  static const List<List<_JpProp>> _variationDeck = [
    // Variation 0: Balanced Shrine & Konbini Town
    [
      _JpProp.toriiShrine,
      _JpProp.lawson,
      _JpProp.machiyaHouse,
      _JpProp.ramenShop,
      _JpProp.modernJpHouse,
      _JpProp.sevenEleven,
      _JpProp.jpTownBuilding,
      _JpProp.pagodaTeaHouse,
    ],
    // Variation 1: Ramen & Yokocho Konbini Run
    [
      _JpProp.ramenShop,
      _JpProp.sevenEleven,
      _JpProp.jpTownBuilding,
      _JpProp.toriiShrine,
      _JpProp.lawson,
      _JpProp.modernJpHouse,
      _JpProp.ramenShop,
      _JpProp.machiyaHouse,
    ],
    // Variation 2: Machiya & Red Torii Shrine Line
    [
      _JpProp.machiyaHouse,
      _JpProp.toriiShrine,
      _JpProp.pagodaTeaHouse,
      _JpProp.lawson,
      _JpProp.modernJpHouse,
      _JpProp.toriiShrine,
      _JpProp.ramenShop,
      _JpProp.sevenEleven,
    ],
    // Variation 3: Late-Night Konbini & Town Buildings
    [
      _JpProp.sevenEleven,
      _JpProp.jpTownBuilding,
      _JpProp.modernJpHouse,
      _JpProp.lawson,
      _JpProp.toriiShrine,
      _JpProp.ramenShop,
      _JpProp.jpTownBuilding,
      _JpProp.machiyaHouse,
    ],
    // Variation 4: Sakura Shrine & Neighborhood Shops
    [
      _JpProp.toriiShrine,
      _JpProp.ramenShop,
      _JpProp.modernJpHouse,
      _JpProp.lawson,
      _JpProp.pagodaTeaHouse,
      _JpProp.sevenEleven,
      _JpProp.toriiShrine,
      _JpProp.jpTownBuilding,
    ],
  ];

  _ScenicTrainDioramaPainter({
    required this.palette,
    required this.overallProgress,
    required this.segmentProgress,
    required this.worldScroll,
    required this.timeSec,
    required this.speedMultiplier,
    required this.trainId,
    required this.sceneSeed,
    required this.variationIndex,
  });

  static TextPainter _cachedLabel(
    String text, {
    required double fontSize,
    required Color color,
    FontWeight weight = FontWeight.w900,
    double letterSpacing = 0.0,
  }) {
    final key = '$text|$fontSize|${color.value}|${weight.index}|$letterSpacing';
    final existing = _labelCache[key];
    if (existing != null) return existing;
    if (_labelCache.length > 64) {
      _labelCache.clear();
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _labelCache[key] = tp;
    return tp;
  }

  static int _mixHash(int x, int seed) {
    int h = (x * 0x9E3779B1) ^ (seed * 0x85EBCA6B) ^ 0xC2B2AE35;
    h ^= (h >>> 16);
    h = (h * 0x7FEB352D) & 0x7FFFFFFF;
    h ^= (h >>> 15);
    return h & 0x7FFFFFFF;
  }

  _JpProp _propForSlot(int slotIndex) {
    final deck = _variationDeck[variationIndex.abs() % _variationDeck.length];
    final baseSeed = sceneSeed ^ (variationIndex * 7919);

    // Walk a short window so adjacent slots never show duplicate buildings
    _JpProp prev1 = deck[_mixHash(slotIndex - 2, baseSeed) % deck.length];
    _JpProp prev0 = deck[_mixHash(slotIndex - 1, baseSeed) % deck.length];
    if (prev0 == prev1) {
      prev0 = deck[(_mixHash(slotIndex - 1, baseSeed) + 1) % deck.length];
    }

    int idx = _mixHash(slotIndex, baseSeed) % deck.length;
    _JpProp chosen = deck[idx];
    int guard = 0;
    while ((chosen == prev0 || chosen == prev1) && guard < deck.length) {
      idx = (idx + 1) % deck.length;
      chosen = deck[idx];
      guard++;
    }
    return chosen;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final isSakura = palette.id == 'sakura';
    final isDark = palette.isDark;
    final groundY = size.height - 22.0;

    // 1. Sky Gradient (adapts to MyGO vs Sakura and Dark vs Light mode)
    final List<Color> skyColors;
    if (isSakura) {
      skyColors = isDark
          ? [
              const Color(0xFF1A1025),
              const Color(0xFF351B42),
              const Color(0xFF582757),
            ]
          : [
              const Color(0xFFFFDFE9),
              const Color(0xFFFFEEF4),
              const Color(0xFFFFF8FB),
            ];
    } else {
      skyColors = isDark
          ? [
              const Color(0xFF070C18),
              const Color(0xFF0F1E36),
              const Color(0xFF1A3152),
            ]
          : [
              const Color(0xFF7DD3FC),
              const Color(0xFFBAE6FD),
              const Color(0xFFE0F2FE),
            ];
    }

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: skyColors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, groundY));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, groundY), skyPaint);

    // 2. Celestial body (Moon / Sun) & twinkling stars
    if (isDark) {
      final starPaint = Paint();
      for (int i = 0; i < 16; i++) {
        final sx = ((i * 53.0) + 19.0) % size.width;
        final sy = ((i * 19.0) + 12.0) % (groundY * 0.52);
        final twinkle =
            0.35 + 0.65 * (0.5 + 0.5 * math.sin(timeSec * 3.0 + i));
        starPaint.color = Colors.white.withOpacity(twinkle * 0.85);
        canvas.drawCircle(Offset(sx, sy), (i % 3 == 0) ? 1.5 : 1.0, starPaint);
      }
      final moonCenter = Offset(size.width * 0.85, 36);
      canvas.drawCircle(
        moonCenter,
        14,
        Paint()
          ..color =
              (isSakura ? const Color(0xFFFDE68A) : const Color(0xFFE0F2FE))
                  .withOpacity(0.20),
      );
      canvas.drawCircle(
        moonCenter,
        8.5,
        Paint()
          ..color =
              (isSakura ? const Color(0xFFFEF08A) : const Color(0xFFF8FAFC))
                  .withOpacity(0.88),
      );
    } else {
      final sunCenter = Offset(size.width * 0.85, 36);
      canvas.drawCircle(
        sunCenter,
        13,
        Paint()
          ..color =
              (isSakura ? const Color(0xFFF472B6) : const Color(0xFFFBBF24))
                  .withOpacity(0.35),
      );
      canvas.drawCircle(
        sunCenter,
        8,
        Paint()
          ..color =
              (isSakura ? const Color(0xFFF9A8D4) : const Color(0xFFFDE047))
                  .withOpacity(0.85),
      );
    }

    // 3. Trip-Progress Mountain (Mt. Fuji) — glides across the sky at the exact
    //    pace of overallProgress and exits off the left toward the end of the trip!
    _paintTripProgressMountain(canvas, size, groundY, isDark, isSakura);

    // 4. Rolling Distant Hills (soft horizon layer behind the townscape)
    _paintRollingHills(canvas, size, groundY, isDark, isSakura);

    // 5. Randomized Japanese Townscape: Red Torii Arches, Lawson, 7-Eleven,
    //    Ramen Shop, Machiya & Modern Japanese Houses, and Narrow Town Buildings!
    _paintJapaneseStreetscape(canvas, size, groundY, isDark, isSakura);

    // 6. Overhead Catenary Poles & Wires
    _paintCatenaryWires(canvas, size, groundY, isDark);

    // 7. Track Ballast, Sleepers & Steel Rails
    _paintTrackBed(canvas, size, groundY, isDark);

    // 8. Multi-Car Side-View Commuter Train (with speed/braking physics & headlights)
    _paintSideViewTrain(
      canvas,
      size,
      groundY,
      isDark: isDark,
      isSakura: isSakura,
    );

    // 9. Theme Weather Particles (Sakura blossoms or MyGO starry rain)
    _paintThemeWeather(
      canvas,
      size,
      groundY,
      isSakura: isSakura,
      isDark: isDark,
    );
  }

  void _paintTripProgressMountain(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    bool isSakura,
  ) {
    // At overallProgress == 0.0: mountain sits on the right horizon (size.width - 66).
    // Across the trip (0.0 -> 1.0): glides steadily left in lockstep with trip progress,
    // exiting off the left edge of the screen (-102) right toward the end of the trip!
    final double startX = size.width - 66.0;
    const double endX = -102.0;
    final double fujiCenterX =
        ui.lerpDouble(startX, endX, overallProgress.clamp(0.0, 1.0))!;

    // Skip drawing only once completely past the left edge
    if (fujiCenterX + 100 < -4 || fujiCenterX - 100 > size.width + 4) {
      return;
    }

    final double fujiBaseY = groundY;
    const double fujiPeakY = 26.0;

    final Color fujiBodyColor = isDark
        ? (isSakura ? const Color(0xFF4C2648) : const Color(0xFF1E3A5F))
        : (isSakura ? const Color(0xFFA779A6) : const Color(0xFF3B82F6));
    final Color fujiShadowSlope = isDark
        ? (isSakura ? const Color(0xFF381B36) : const Color(0xFF152C4A))
        : (isSakura ? const Color(0xFF936592) : const Color(0xFF2563EB));

    final fujiPath = Path()
      ..moveTo(fujiCenterX - 96, fujiBaseY)
      ..quadraticBezierTo(
        fujiCenterX - 30,
        fujiPeakY + 28,
        fujiCenterX - 10,
        fujiPeakY,
      )
      ..lineTo(fujiCenterX + 10, fujiPeakY)
      ..quadraticBezierTo(
        fujiCenterX + 30,
        fujiPeakY + 28,
        fujiCenterX + 96,
        fujiBaseY,
      )
      ..close();

    canvas.drawPath(
      fujiPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fujiBodyColor.withOpacity(0.90),
            fujiShadowSlope.withOpacity(0.88),
          ],
        ).createShader(
          Rect.fromLTWH(
            fujiCenterX - 96,
            fujiPeakY,
            192,
            fujiBaseY - fujiPeakY,
          ),
        ),
    );

    // Iconic jagged snow cap on Mt. Fuji
    final snowPath = Path()
      ..moveTo(fujiCenterX - 10, fujiPeakY)
      ..lineTo(fujiCenterX + 10, fujiPeakY)
      ..quadraticBezierTo(
        fujiCenterX + 17,
        fujiPeakY + 13,
        fujiCenterX + 26,
        fujiPeakY + 24,
      )
      ..lineTo(fujiCenterX + 11, fujiPeakY + 18)
      ..lineTo(fujiCenterX + 1, fujiPeakY + 25)
      ..lineTo(fujiCenterX - 10, fujiPeakY + 18)
      ..lineTo(fujiCenterX - 26, fujiPeakY + 24)
      ..quadraticBezierTo(
        fujiCenterX - 17,
        fujiPeakY + 13,
        fujiCenterX - 10,
        fujiPeakY,
      )
      ..close();
    canvas.drawPath(
      snowPath,
      Paint()..color = Colors.white.withOpacity(isDark ? 0.88 : 0.96),
    );
  }

  void _paintRollingHills(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    bool isSakura,
  ) {
    final hillColor = isDark
        ? (isSakura ? const Color(0xFF2B1734) : const Color(0xFF11263A))
        : (isSakura ? const Color(0xFFFBCFE8) : const Color(0xFF86EFAC));

    final hillPath = Path()..moveTo(0, groundY);
    const hillSpan = 145.0;
    final hillOffset = (worldScroll * 0.22) % hillSpan;
    for (double x = -hillSpan; x <= size.width + hillSpan; x += hillSpan) {
      final hx = x - hillOffset;
      hillPath.quadraticBezierTo(
        hx + hillSpan * 0.5,
        groundY - 22,
        hx + hillSpan,
        groundY,
      );
    }
    hillPath.lineTo(size.width, groundY);
    hillPath.close();
    canvas.drawPath(hillPath, Paint()..color = hillColor.withOpacity(0.88));
  }

  void _paintJapaneseStreetscape(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
    bool isSakura,
  ) {
    const double slotSpan = 96.0;
    final double scrollPx = worldScroll * 0.56;
    final int firstSlot = ((scrollPx - slotSpan) / slotSpan).floor();
    final int lastSlot = ((scrollPx + size.width + slotSpan) / slotSpan).ceil();

    for (int slot = firstSlot; slot <= lastSlot; slot++) {
      final double slotLeft = slot * slotSpan - scrollPx;
      if (slotLeft + slotSpan < -24 || slotLeft > size.width + 24) continue;

      final prop = _propForSlot(slot);
      final subHash = _mixHash(slot + 101, sceneSeed ^ 0x5A5A);

      // Draw a cozy tree or bush separator on alternating slots for natural depth
      if (subHash % 2 == 0) {
        _drawSmallTree(
          canvas,
          x: slotLeft + slotSpan - 10,
          groundY: groundY,
          isDark: isDark,
          isSakura: isSakura,
          tall: (subHash % 4 == 0),
        );
      }

      switch (prop) {
        case _JpProp.toriiShrine:
          _drawRedToriiShrine(
            canvas,
            x: slotLeft + 14,
            groundY: groundY,
            isDark: isDark,
            isSakura: isSakura,
          );
          break;
        case _JpProp.lawson:
          _drawLawsonStore(
            canvas,
            left: slotLeft + 10,
            groundY: groundY,
            isDark: isDark,
          );
          break;
        case _JpProp.sevenEleven:
          _drawSevenElevenStore(
            canvas,
            left: slotLeft + 10,
            groundY: groundY,
            isDark: isDark,
          );
          break;
        case _JpProp.ramenShop:
          _drawRamenShop(
            canvas,
            left: slotLeft + 12,
            groundY: groundY,
            isDark: isDark,
            slot: slot,
            indigoNoren: (subHash % 3 == 0),
          );
          break;
        case _JpProp.machiyaHouse:
          _drawMachiyaHouse(
            canvas,
            left: slotLeft + 12,
            groundY: groundY,
            isDark: isDark,
          );
          break;
        case _JpProp.modernJpHouse:
          _drawModernJapaneseHouse(
            canvas,
            left: slotLeft + 14,
            groundY: groundY,
            isDark: isDark,
            colorVariant: subHash % 4,
          );
          break;
        case _JpProp.jpTownBuilding:
          _drawJapaneseTownBuilding(
            canvas,
            left: slotLeft + 16,
            groundY: groundY,
            isDark: isDark,
            isSakura: isSakura,
            variant: subHash % 3,
          );
          break;
        case _JpProp.pagodaTeaHouse:
          _drawPagodaTeaHouseAndJihanki(
            canvas,
            left: slotLeft + 10,
            groundY: groundY,
            isDark: isDark,
            isSakura: isSakura,
          );
          break;
      }
    }
  }

  void _drawSmallTree(
    Canvas canvas, {
    required double x,
    required double groundY,
    required bool isDark,
    required bool isSakura,
    required bool tall,
  }) {
    final trunkH = tall ? 13.0 : 9.5;
    canvas.drawRect(
      Rect.fromLTWH(x - 1.5, groundY - trunkH, 3.0, trunkH),
      Paint()..color = const Color(0xFF78350F),
    );
    final crownColor = isSakura
        ? (isDark ? const Color(0xFFEC4899) : const Color(0xFFF472B6))
        : (isDark ? const Color(0xFF15803D) : const Color(0xFF4ADE80));
    canvas.drawCircle(
      Offset(x, groundY - trunkH - 4.5),
      tall ? 8.5 : 7.0,
      Paint()..color = crownColor.withOpacity(0.92),
    );
  }

  /// 1. Beloved Red Torii Gate + Stone Lantern (`Toro`) + Shrine Trees
  void _drawRedToriiShrine(
    Canvas canvas, {
    required double x,
    required double groundY,
    required bool isDark,
    required bool isSakura,
  }) {
    // Background shrine trees flanking the arch
    _drawSmallTree(
      canvas,
      x: x + 4,
      groundY: groundY,
      isDark: isDark,
      isSakura: isSakura,
      tall: true,
    );
    _drawSmallTree(
      canvas,
      x: x + 52,
      groundY: groundY,
      isDark: isDark,
      isSakura: isSakura,
      tall: false,
    );

    final toriiX = x + 27;
    final vermilion = Paint()
      ..color = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final darkCap = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Two vertical pillars + nemaki black base boots
    canvas.drawLine(
      Offset(toriiX - 10, groundY),
      Offset(toriiX - 8.5, groundY - 30),
      vermilion,
    );
    canvas.drawLine(
      Offset(toriiX + 10, groundY),
      Offset(toriiX + 8.5, groundY - 30),
      vermilion,
    );
    canvas.drawRect(
      Rect.fromLTWH(toriiX - 11.8, groundY - 5, 3.6, 5),
      Paint()..color = const Color(0xFF1E293B),
    );
    canvas.drawRect(
      Rect.fromLTWH(toriiX + 8.2, groundY - 5, 3.6, 5),
      Paint()..color = const Color(0xFF1E293B),
    );

    // Curved top kasagi lintel + dark cap bar
    final kasagiPath = Path()
      ..moveTo(toriiX - 16, groundY - 31.5)
      ..quadraticBezierTo(
        toriiX,
        groundY - 28.5,
        toriiX + 16,
        groundY - 31.5,
      );
    canvas.drawPath(
      kasagiPath,
      vermilion..style = PaintingStyle.stroke,
    );
    final capPath = Path()
      ..moveTo(toriiX - 16.5, groundY - 33.2)
      ..quadraticBezierTo(
        toriiX,
        groundY - 30.2,
        toriiX + 16.5,
        groundY - 33.2,
      );
    canvas.drawPath(capPath, darkCap..style = PaintingStyle.stroke);

    // Lower nuki tie beam & center gakuzuka tablet
    canvas.drawLine(
      Offset(toriiX - 12.5, groundY - 22.5),
      Offset(toriiX + 12.5, groundY - 22.5),
      vermilion,
    );
    canvas.drawRect(
      Rect.fromLTWH(toriiX - 2, groundY - 29.5, 4, 7),
      Paint()..color = const Color(0xFF1E293B),
    );

    // Cute stone shrine lantern (Toro) with warm candle glow
    final lanternX = x + 44;
    final stonePaint = Paint()
      ..color = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    canvas.drawRect(
      Rect.fromLTWH(lanternX - 3, groundY - 3, 6, 3),
      stonePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(lanternX - 1.5, groundY - 9, 3, 6),
      stonePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(lanternX - 3, groundY - 14, 6, 5),
      stonePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(lanternX - 1.5, groundY - 13, 3, 3),
      Paint()..color = const Color(0xFFFDE047),
    );
    final lanternRoof = Path()
      ..moveTo(lanternX - 5, groundY - 14)
      ..lineTo(lanternX, groundY - 17.5)
      ..lineTo(lanternX + 5, groundY - 14)
      ..close();
    canvas.drawPath(lanternRoof, stonePaint);
  }

  /// 2. Lawson Konbini (Cream storefront, signature Lawson Blue fascia + milk-can badge + pole sign)
  void _drawLawsonStore(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
  }) {
    const double w = 56.0;
    const double h = 32.0;
    final double top = groundY - h;

    // Storefront body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(2.5),
      ),
      Paint()
        ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFFF8FAFC),
    );

    // Signature Lawson Blue signboard fascia
    const lawsonBlue = Color(0xFF0068B7);
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 1, w + 2, 9.0),
      Paint()..color = lawsonBlue,
    );
    // White & pink accent trim stripe beneath blue fascia
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 10.0, w + 2, 1.5),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 11.5, w + 2, 1.4),
      Paint()..color = const Color(0xFFEC4899),
    );

    // Mini milk-can icon + "LAWSON" micro-sign
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 4, top + 2.5, 5.5, 6.0),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white,
    );
    final tp = _cachedLabel(
      'LAWSON',
      fontSize: 5.8,
      color: Colors.white,
      letterSpacing: 0.4,
    );
    tp.paint(canvas, Offset(left + 12.5, top + 2.6));

    // Bright convenience store glass windows & sliding doors
    final glassGlow = Paint()
      ..color = isDark ? const Color(0xFFFEF9C3) : const Color(0xFFBAE6FD);
    canvas.drawRect(Rect.fromLTWH(left + 4, top + 15, 16, 13), glassGlow);
    canvas.drawRect(Rect.fromLTWH(left + 22, top + 15, 12, 17), glassGlow);
    canvas.drawRect(Rect.fromLTWH(left + 36, top + 15, 16, 13), glassGlow);

    // Door frame lines
    final framePaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(left + 28, top + 15),
      Offset(left + 28, groundY),
      framePaint,
    );

    // Roadside freestanding Lawson pole sign
    final poleX = left + w + 5.5;
    canvas.drawLine(
      Offset(poleX, groundY),
      Offset(poleX, top - 5),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 1.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(poleX - 4.5, top - 11, 9, 8),
        const Radius.circular(1.8),
      ),
      Paint()..color = lawsonBlue,
    );
    canvas.drawCircle(
      Offset(poleX, top - 7),
      2.0,
      Paint()..color = Colors.white,
    );
  }

  /// 3. 7-Eleven Konbini (Brick/ivory storefront, iconic Orange/Green/Red fascia + vending machine)
  void _drawSevenElevenStore(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
  }) {
    const double w = 56.0;
    const double h = 32.0;
    final double top = groundY - h;

    // Warm brick/tan konbini lower body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(2.5),
      ),
      Paint()
        ..color = isDark ? const Color(0xFFD6D3D1) : const Color(0xFFF5F5F4),
    );

    // White upper fascia board + signature 3-stripe ribbon (Orange, Green, Red)
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top, w + 2, 10.5),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 2.0, w + 2, 2.2),
      Paint()..color = const Color(0xFFF97316), // Orange
    );
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 4.5, w + 2, 2.2),
      Paint()..color = const Color(0xFF16A34A), // Green
    );
    canvas.drawRect(
      Rect.fromLTWH(left - 1, top + 7.0, w + 2, 2.2),
      Paint()..color = const Color(0xFFDC2626), // Red
    );

    // Center "7-11" badge box on fascia
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 18, top + 1.0, 20, 8.8),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white,
    );
    final tp = _cachedLabel(
      '7-11',
      fontSize: 6.2,
      color: const Color(0xFF15803D),
      letterSpacing: 0.3,
    );
    tp.paint(canvas, Offset(left + 20.5, top + 2.2));

    // Bright store windows & entrance
    final glassGlow = Paint()
      ..color = isDark ? const Color(0xFFFEF08A) : const Color(0xFFE0F2FE);
    canvas.drawRect(Rect.fromLTWH(left + 4, top + 14, 15, 13), glassGlow);
    canvas.drawRect(Rect.fromLTWH(left + 21, top + 14, 13, 18), glassGlow);
    canvas.drawRect(Rect.fromLTWH(left + 36, top + 14, 15, 13), glassGlow);

    // Cute glowing red Japanese vending machine (jihanki) right outside
    final vmLeft = left + w + 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(vmLeft, groundY - 16, 9, 16),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFFDC2626),
    );
    canvas.drawRect(
      Rect.fromLTWH(vmLeft + 1.5, groundY - 14, 6, 7),
      Paint()..color = const Color(0xFFFEF9C3),
    );
  }

  /// 4. Cozy Japanese Ramen Shop (Timber facade, kawara eaves, split noren curtains, swaying red chochin lanterns & RAMEN sign)
  void _drawRamenShop(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
    required int slot,
    required bool indigoNoren,
  }) {
    const double w = 50.0;
    const double h = 36.0;
    final double top = groundY - h;

    // Warm dark timber body
    canvas.drawRect(
      Rect.fromLTWH(left, top + 6, w, h - 6),
      Paint()
        ..color = isDark ? const Color(0xFF3E2723) : const Color(0xFF5D4037),
    );

    // Traditional sloped tiled eaves roof
    final roofPath = Path()
      ..moveTo(left - 4, top + 9)
      ..lineTo(left + 3, top + 2)
      ..lineTo(left + w - 3, top + 2)
      ..lineTo(left + w + 4, top + 9)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()..color = const Color(0xFF1E293B),
    );

    // Rooftop Ramen signboard ("ラーメン")
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 7, top - 8, 36, 9.5),
        const Radius.circular(2.0),
      ),
      Paint()..color = const Color(0xFFB91C1C),
    );
    final signTp = _cachedLabel(
      'ラーメン',
      fontSize: 6.0,
      color: const Color(0xFFFEF08A),
    );
    signTp.paint(canvas, Offset(left + 12, top - 6.2));

    // Warm golden counter window on right side
    canvas.drawRect(
      Rect.fromLTWH(left + 29, top + 15, 16, 12),
      Paint()..color = const Color(0xFFFDE047).withOpacity(0.9),
    );
    // Wooden counter bar inside window
    canvas.drawRect(
      Rect.fromLTWH(left + 29, top + 23, 16, 4),
      Paint()..color = const Color(0xFF92400E),
    );

    // Doorway glow + 3-panel split Noren curtain!
    canvas.drawRect(
      Rect.fromLTWH(left + 6, top + 14, 19, 22),
      Paint()..color = const Color(0xFFFEF3C7).withOpacity(0.85),
    );
    final norenColor =
        indigoNoren ? const Color(0xFF1E3A8A) : const Color(0xFF991B1B);
    for (int panel = 0; panel < 3; panel++) {
      canvas.drawRect(
        Rect.fromLTWH(left + 6.5 + panel * 6.2, top + 13.5, 5.2, 9.0),
        Paint()..color = norenColor,
      );
      canvas.drawLine(
        Offset(left + 7.5 + panel * 6.2, top + 20.5),
        Offset(left + 10.7 + panel * 6.2, top + 20.5),
        Paint()
          ..color = Colors.white.withOpacity(0.75)
          ..strokeWidth = 0.9,
      );
    }

    // Swaying glowing Red Chochin paper lanterns under eaves
    final sway = math.sin(timeSec * 3.0 + slot) * 1.2;
    for (final lx in [left + 2.5, left + w - 2.5]) {
      final lanternCenter = Offset(lx + sway, top + 14.5);
      if (isDark) {
        canvas.drawCircle(
          lanternCenter,
          6.5,
          Paint()..color = const Color(0xFFF97316).withOpacity(0.28),
        );
      }
      canvas.drawOval(
        Rect.fromCenter(center: lanternCenter, width: 5.5, height: 7.5),
        Paint()..color = const Color(0xFFEF4444),
      );
      canvas.drawCircle(
        lanternCenter,
        1.4,
        Paint()..color = const Color(0xFFFEF08A),
      );
    }
  }

  /// 5. Traditional Japanese Machiya / Kominka Wooden House
  void _drawMachiyaHouse(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
  }) {
    const double w = 48.0;
    const double h = 38.0;
    final double top = groundY - h;

    // Lower timber wall & upper white shikkui plaster wall
    canvas.drawRect(
      Rect.fromLTWH(left, top + 10, w, 12),
      Paint()
        ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFFFAF5FF),
    );
    canvas.drawRect(
      Rect.fromLTWH(left, top + 22, w, 16),
      Paint()
        ..color = isDark ? const Color(0xFF451A03) : const Color(0xFF78350F),
    );

    // Upper pitched kawara tiled roof with curved eaves
    final roof = Path()
      ..moveTo(left - 5, top + 12)
      ..quadraticBezierTo(left + w * 0.5, top - 2, left + w + 5, top + 12)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF1E293B));

    // Lower entrance canopy eave
    canvas.drawLine(
      Offset(left - 3, top + 22),
      Offset(left + w + 3, top + 22),
      Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 2.6,
    );

    // Warm glowing shoji sliding paper doors downstairs
    final shojiPaint = Paint()
      ..color = isDark ? const Color(0xFFFDE68A) : const Color(0xFFFEF9C3);
    canvas.drawRect(Rect.fromLTWH(left + 6, top + 25, 15, 13), shojiPaint);
    canvas.drawRect(Rect.fromLTWH(left + 27, top + 25, 14, 10), shojiPaint);

    // Upper lattice window
    canvas.drawRect(
      Rect.fromLTWH(left + 16, top + 13, 16, 6),
      Paint()..color = const Color(0xFF475569),
    );
  }

  /// 6. Modern Japanese 2-Story Suburban House (Ikkodate with balcony & postbox)
  void _drawModernJapaneseHouse(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
    required int colorVariant,
  }) {
    const double w = 44.0;
    const double h = 45.0;
    final double top = groundY - h;

    final wallPalettesDark = [
      const Color(0xFFCBD5E1),
      const Color(0xFFD6D3D1),
      const Color(0xFFBFDBFE),
      const Color(0xFFFBCFE8),
    ];
    final wallPalettesLight = [
      const Color(0xFFF8FAFC),
      const Color(0xFFFEF3C7),
      const Color(0xFFE0F2FE),
      const Color(0xFFFCE7F3),
    ];
    final wallColor = isDark
        ? wallPalettesDark[colorVariant % 4]
        : wallPalettesLight[colorVariant % 4];

    // Main 2-story house block
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top + 8, w, h - 8),
        const Radius.circular(2),
      ),
      Paint()..color = wallColor,
    );

    // Asymmetric modern Japanese gable/shed roof
    final roofPath = Path()
      ..moveTo(left - 3, top + 9)
      ..lineTo(left + w * 0.38, top)
      ..lineTo(left + w + 3, top + 9)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = const Color(0xFF334155));

    // 2nd floor window + cantilevered balcony box
    final winGlow = Paint()
      ..color = isDark ? const Color(0xFFFEF08A) : const Color(0xFF38BDF8);
    canvas.drawRect(Rect.fromLTWH(left + 6, top + 13, 13, 9), winGlow);
    canvas.drawRect(Rect.fromLTWH(left + 24, top + 13, 14, 9), winGlow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 21, top + 20, 21, 5.5),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF64748B),
    );

    // Ground floor wood genkan front door + living window + red post-box
    canvas.drawRect(
      Rect.fromLTWH(left + 6, groundY - 15, 9, 15),
      Paint()..color = const Color(0xFF92400E),
    );
    canvas.drawRect(Rect.fromLTWH(left + 21, groundY - 14, 16, 9), winGlow);
    // Tiny Japanese red post-box beside entrance
    canvas.drawRect(
      Rect.fromLTWH(left - 4, groundY - 9, 3, 4),
      Paint()..color = const Color(0xFFEF4444),
    );
    canvas.drawLine(
      Offset(left - 2.5, groundY - 5),
      Offset(left - 2.5, groundY),
      Paint()
        ..color = const Color(0xFF64748B)
        ..strokeWidth = 1.2,
    );
  }

  /// 7. Narrow 3-Story Japanese Town Building (`Zakkyo Biru` with projecting neon side-sign)
  void _drawJapaneseTownBuilding(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
    required bool isSakura,
    required int variant,
  }) {
    const double w = 38.0;
    const double h = 56.0;
    final double top = groundY - h;

    final bldgColor = isDark
        ? (variant == 0
            ? const Color(0xFF1E293B)
            : variant == 1
                ? const Color(0xFF27272A)
                : const Color(0xFF312E81))
        : (variant == 0
            ? const Color(0xFFCBD5E1)
            : variant == 1
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFDDD6FE));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(2.5),
      ),
      Paint()..color = bldgColor,
    );

    // Rooftop fence & tiny AC unit
    canvas.drawRect(
      Rect.fromLTWH(left + 5, top - 4, 9, 4),
      Paint()..color = const Color(0xFF64748B),
    );
    canvas.drawLine(
      Offset(left + 2, top - 2.5),
      Offset(left + w - 2, top - 2.5),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 1.0,
    );

    // Glowing apartment/office windows on 2F & 3F
    final winPaint = Paint()
      ..color = isDark
          ? const Color(0xFFFDE047).withOpacity(0.85)
          : Colors.white.withOpacity(0.85);
    for (int row = 0; row < 3; row++) {
      final wy = top + 6.0 + row * 11.0;
      for (int col = 0; col < 3; col++) {
        final wx = left + 5.0 + col * 10.5;
        canvas.drawRect(Rect.fromLTWH(wx, wy, 6.5, 6.5), winPaint);
      }
    }

    // Ground-floor cozy shopfront & striped cafe/bookstore awning
    final awningColor = isSakura
        ? const Color(0xFFEC4899)
        : (variant == 1 ? const Color(0xFF10B981) : const Color(0xFF0284C7));
    canvas.drawRect(
      Rect.fromLTWH(left + 3, groundY - 14, w - 6, 14),
      Paint()..color = const Color(0xFFFEF3C7).withOpacity(0.9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left - 1.5, groundY - 16.5, w + 3, 4.5),
        const Radius.circular(1.5),
      ),
      Paint()..color = awningColor,
    );

    // Projecting vertical Japanese street sign (`Sode-kanban`) on side of building
    final signColor = variant == 0
        ? palette.primaryAccent
        : variant == 1
            ? const Color(0xFFF43F5E)
            : const Color(0xFFFBBF24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + w + 1.5, top + 9, 5.5, 22),
        const Radius.circular(1.5),
      ),
      Paint()..color = signColor,
    );
  }

  /// 8. 2-Tiered Japanese Eaves Tea-House Pavilion + Dual Glowing Vending Machines
  void _drawPagodaTeaHouseAndJihanki(
    Canvas canvas, {
    required double left,
    required double groundY,
    required bool isDark,
    required bool isSakura,
  }) {
    // 2-tier traditional pavilion on left
    const double pw = 36.0;
    final double pTop = groundY - 40.0;

    canvas.drawRect(
      Rect.fromLTWH(left + 4, pTop + 8, pw - 8, 13),
      Paint()..color = const Color(0xFF78350F),
    );
    canvas.drawRect(
      Rect.fromLTWH(left + 2, pTop + 21, pw - 4, 19),
      Paint()..color = const Color(0xFF451A03),
    );

    final eavePaint = Paint()..color = const Color(0xFF1E293B);
    final upperRoof = Path()
      ..moveTo(left, pTop + 10)
      ..quadraticBezierTo(left + pw * 0.5, pTop - 2, left + pw, pTop + 10)
      ..close();
    final lowerRoof = Path()
      ..moveTo(left - 3, pTop + 23)
      ..quadraticBezierTo(
        left + pw * 0.5,
        pTop + 14,
        left + pw + 3,
        pTop + 23,
      )
      ..close();
    canvas.drawPath(upperRoof, eavePaint);
    canvas.drawPath(lowerRoof, eavePaint);

    // Warm round maromado window
    canvas.drawCircle(
      Offset(left + pw * 0.5, groundY - 9.5),
      4.8,
      Paint()..color = const Color(0xFFFDE047),
    );

    // Pair of glowing Japanese street vending machines (blue & sakura/red)
    final vmBaseX = left + pw + 5;
    final vmColors = [
      const Color(0xFF0284C7),
      isSakura ? const Color(0xFFEC4899) : const Color(0xFFEF4444),
    ];
    for (int i = 0; i < 2; i++) {
      final vx = vmBaseX + i * 10.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(vx, groundY - 16, 9.0, 16.0),
          const Radius.circular(1.5),
        ),
        Paint()..color = vmColors[i],
      );
      canvas.drawRect(
        Rect.fromLTWH(vx + 1.5, groundY - 14, 6.0, 7.5),
        Paint()..color = const Color(0xFFFEF9C3),
      );
    }
  }

  void _paintCatenaryWires(
    Canvas canvas,
    Size size,
    double groundY,
    bool isDark,
  ) {
    final wireY = groundY - 54.0;
    final wirePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.22)
      ..strokeWidth = 1.1;

    // Contact wire
    canvas.drawLine(Offset(0, wireY), Offset(size.width, wireY), wirePaint);

    // Overhead catenary masts scrolling in foreground
    const mastSpacing = 138.0;
    final mastOffset = (worldScroll * 0.85) % mastSpacing;
    final mastPaint = Paint()
      ..color = (isDark ? const Color(0xFF64748B) : const Color(0xFF475569))
          .withOpacity(0.52)
      ..strokeWidth = 2.1;

    for (double x = -mastSpacing;
        x <= size.width + mastSpacing;
        x += mastSpacing) {
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
      canvas.drawLine(
        Offset(tx, groundY + 3),
        Offset(tx - 3, groundY + 9),
        tiePaint,
      );
    }
  }

  void _paintSideViewTrain(
    Canvas canvas,
    Size size,
    double groundY, {
    required bool isDark,
    required bool isSakura,
  }) {
    // Subtle suspension bounce when moving
    final bounce = speedMultiplier > 0.05
        ? math.sin(timeSec * 14.0 * speedMultiplier.clamp(0.4, 1.3)) * 1.1
        : 0.0;

    // Position the 2-car cute anime commuter train near center-left facing right
    const leadCarWidth = 104.0;
    const rearCarWidth = 86.0;
    const carHeight = 32.0;
    const gap = 6.0;
    const totalTrainWidth = leadCarWidth + gap + rearCarWidth;
    final startX = (size.width - totalTrainWidth) * 0.44;
    final carTopY = groundY - carHeight - 5.0 + bounce;

    // Headlight beam in dark mode
    if (isDark) {
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
              const Color(0xFFFEF08A).withOpacity(0.30),
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
    final bodyColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFFF8FAFC);
    final stripeColor = palette.primaryAccent;
    final subStripeColor = palette.secondaryAccent;

    final bodyPath = Path();
    if (isLeadCar) {
      bodyPath
        ..moveTo(left + 4, top)
        ..lineTo(left + width - 18, top)
        ..quadraticBezierTo(
          left + width - 3,
          top + 4,
          left + width,
          top + height - 6,
        )
        ..quadraticBezierTo(
          left + width,
          top + height,
          left + width - 6,
          top + height,
        )
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
    final windowGlow = isDark
        ? (isSakura ? const Color(0xFFFEF08A) : const Color(0xFFBAE6FD))
        : const Color(0xFF0284C7).withOpacity(0.75);
    for (int w = 0; w < 4; w++) {
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

      // Cached Train ID mini plate on lead car side
      final tp = _cachedLabel(
        '#$trainId',
        fontSize: 7.5,
        color: const Color(0xFF0F172A),
      );
      tp.paint(canvas, Offset(left + 8, top + height - 10.5));
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
  }) {
    final paint = Paint()..color = palette.primaryAccent.withOpacity(0.30);
    const count = 12;
    for (int i = 0; i < count; i++) {
      final px = ((i * 47.0) - (worldScroll * 0.45) % size.width + size.width) %
          size.width;
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
