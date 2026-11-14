import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/anime_theme.dart';

class AnimeMascotBanner extends StatefulWidget {
  final AnimeThemePalette palette;
  final String message;
  final bool isExcited;
  final bool isRiding;
  final VoidCallback onToggleThemeStyle;

  const AnimeMascotBanner({
    super.key,
    required this.palette,
    required this.message,
    this.isExcited = false,
    this.isRiding = false,
    required this.onToggleThemeStyle,
  });

  @override
  State<AnimeMascotBanner> createState() => _AnimeMascotBannerState();
}

class _AnimeMascotBannerState extends State<AnimeMascotBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.palette;
    final isSakura = pal.id == 'sakura';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final bounce = math.sin(t * 2 * math.pi) * (widget.isExcited ? 4.5 : 2.5);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isSakura
                  ? [
                      pal.cardBg,
                      pal.primaryAccent.withOpacity(pal.isDark ? 0.18 : 0.10),
                    ]
                  : [
                      pal.cardBg,
                      pal.primaryAccent.withOpacity(pal.isDark ? 0.16 : 0.08),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: pal.cardBorder, width: 1.4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Subtle animated starry rain / sakura petals background
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AnimeParticlesPainter(
                      progress: t,
                      isSakura: isSakura,
                      color: pal.primaryAccent,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Chibi Conductor / Navigator Avatar
                      Transform.translate(
                        offset: Offset(0, bounce),
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pal.primaryAccent.withOpacity(0.15),
                            border: Border.all(
                              color: widget.isExcited
                                  ? pal.urgentColor
                                  : pal.primaryAccent,
                              width: 2.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (widget.isExcited
                                        ? pal.urgentColor
                                        : pal.primaryAccent)
                                    .withOpacity(0.28),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: _ChibiConductorPainter(
                              isSakura: isSakura,
                              isExcited: widget.isExcited,
                              isRiding: widget.isRiding,
                              blinkPhase: t,
                              primaryColor: pal.primaryAccent,
                              urgentColor: pal.urgentColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: pal.primaryAccent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '${pal.mascotName} • ${pal.jpTitle}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: pal.primaryAccent,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: widget.onToggleThemeStyle,
                                  borderRadius: BorderRadius.circular(99),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: pal.secondaryAccent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: pal.secondaryAccent.withOpacity(0.45),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isSakura
                                              ? Icons.local_florist_rounded
                                              : Icons.nightlight_round,
                                          size: 12,
                                          color: pal.secondaryAccent,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isSakura ? 'Sakura' : 'MyGO',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: pal.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.message,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: pal.textPrimary,
                              ),
                            ),
                          ],
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

class _AnimeParticlesPainter extends CustomPainter {
  final double progress;
  final bool isSakura;
  final Color color;

  _AnimeParticlesPainter({
    required this.progress,
    required this.isSakura,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.16);
    const count = 8;
    for (int i = 0; i < count; i++) {
      final seed = (i * 0.137) % 1.0;
      final x = ((seed * size.width) + (progress * 30 * (i.isEven ? 1 : -1))) %
          size.width;
      final y = ((i / count + progress) % 1.0) * size.height;

      if (isSakura) {
        // Cute sakura petal oval
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(progress * math.pi * 2 + i);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 7, height: 4.2),
          paint,
        );
        canvas.restore();
      } else {
        // MyGO starry rain streak + twinkle
        canvas.drawLine(
          Offset(x, y),
          Offset(x - 3, y + 9),
          paint..strokeWidth = 1.4,
        );
        if (i % 2 == 0) {
          canvas.drawCircle(Offset(x, y), 1.8, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isSakura != isSakura;
}

class _ChibiConductorPainter extends CustomPainter {
  final bool isSakura;
  final bool isExcited;
  final bool isRiding;
  final double blinkPhase;
  final Color primaryColor;
  final Color urgentColor;

  _ChibiConductorPainter({
    required this.isSakura,
    required this.isExcited,
    required this.isRiding,
    required this.blinkPhase,
    required this.primaryColor,
    required this.urgentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;

    // Hair back
    final hairColor = isSakura
        ? const Color(0xFFF472B6) // Pastel strawberry pink hair
        : const Color(0xFF64748B); // Tomori slate-ash hair
    final hairPaint = Paint()..color = hairColor;
    canvas.drawCircle(Offset(cx, cy), 20, hairPaint);

    // Chibi face
    final skinPaint = Paint()..color = const Color(0xFFFFEFE5);
    canvas.drawCircle(Offset(cx, cy + 2), 16, skinPaint);

    // Cute rosy cheeks
    final blushPaint = Paint()
      ..color = const Color(0xFFFB7185).withOpacity(isExcited ? 0.55 : 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 9, cy + 5), width: 6, height: 3.5),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 9, cy + 5), width: 6, height: 3.5),
      blushPaint,
    );

    // Anime eyes (blink briefly when blinkPhase > 0.92)
    final isBlinking = blinkPhase > 0.93;
    final eyePaint = Paint()
      ..color = isSakura ? const Color(0xFFBE185D) : const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;

    if (isBlinking) {
      final linePaint = Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(cx - 8, cy + 1), Offset(cx - 4, cy + 1), linePaint);
      canvas.drawLine(Offset(cx + 4, cy + 1), Offset(cx + 8, cy + 1), linePaint);
    } else if (isExcited) {
      // Starry / Sparkle eyes (`> <` or big shiny eyes)
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 6, cy + 1), width: 5.5, height: 6.5),
        eyePaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 6, cy + 1), width: 5.5, height: 6.5),
        eyePaint,
      );
      final shine = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(cx - 7, cy - 0.5), 1.6, shine);
      canvas.drawCircle(Offset(cx + 5, cy - 0.5), 1.6, shine);
    } else {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 6, cy + 1), width: 4.8, height: 5.8),
        eyePaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 6, cy + 1), width: 4.8, height: 5.8),
        eyePaint,
      );
      final shine = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(cx - 6.8, cy - 0.5), 1.4, shine);
      canvas.drawCircle(Offset(cx + 5.2, cy - 0.5), 1.4, shine);
    }

    // Smile / mouth
    final mouthPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = isExcited ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.6;
    if (isExcited) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy + 6.5), width: 6, height: 5),
        0,
        math.pi,
        true,
        Paint()..color = const Color(0xFFFB7185),
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy + 6), width: 5, height: 3.5),
        0,
        math.pi,
        false,
        mouthPaint,
      );
    }

    // Bangs
    final bangPath = Path()
      ..moveTo(cx - 16, cy - 4)
      ..quadraticBezierTo(cx - 6, cy - 15, cx, cy - 6)
      ..quadraticBezierTo(cx + 6, cy - 15, cx + 16, cy - 4)
      ..quadraticBezierTo(cx, cy - 18, cx - 16, cy - 4);
    canvas.drawPath(bangPath, hairPaint);

    // Cute NJT / Anime Conductor Cap!
    final capPaint = Paint()
      ..color = isSakura ? const Color(0xFF1E293B) : const Color(0xFF0F172A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 15), width: 28, height: 9),
        const Radius.circular(5),
      ),
      capPaint,
    );
    // Gold cap visor stripe & star badge
    final goldPaint = Paint()..color = const Color(0xFFFBBF24);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - 11.5), width: 24, height: 2),
      goldPaint,
    );
    canvas.drawCircle(Offset(cx, cy - 15.5), 2.3, goldPaint);
  }

  @override
  bool shouldRepaint(covariant _ChibiConductorPainter oldDelegate) =>
      oldDelegate.blinkPhase != blinkPhase ||
      oldDelegate.isExcited != isExcited ||
      oldDelegate.isSakura != isSakura;
}
