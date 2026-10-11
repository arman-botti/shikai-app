import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// SHARINGAN LOADER (Anime Summoning Loader)
/// Pixel-perfect replica of shikai.biz AnimeSummoningLoader
/// Features:
/// - 360-degree Continuous Spinning Sharingan Wheel (2.2s linear)
/// - Pure Chakra Pulse animation (drop-shadow and scaling)
/// - Ambient Floating Chakra Aura Glow
/// - Crimson Blood Iris Gradient with 3 classic Tomoes (Magatama paths)
/// - Center Pupil Core with Specular Glint
/// - Glowing "SUMMONING STREAM" typography with pulsing red dot
/// ---------------------------------------------------------------------------
class SharinganLoader extends StatefulWidget {
  final String label;
  final double size;
  final bool showLabel;

  const SharinganLoader({
    Key? key,
    this.label = "SUMMONING STREAM",
    this.size = 64.0,
    this.showLabel = true,
  }) : super(key: key);

  @override
  State<SharinganLoader> createState() => _SharinganLoaderState();
}

class _SharinganLoaderState extends State<SharinganLoader> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Continuous 360-degree rotation (2.2s linear)
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // 2. Chakra pulse animation (2.4s easeInOut)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ambient Aura Glow & Pulsing Sharingan Eye
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Ambient Floating Chakra Aura Glow
                  Container(
                    width: widget.size * 1.5,
                    height: widget.size * 1.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF1F5A).withOpacity(_glowAnimation.value * 0.5),
                          const Color(0xFFE0164C).withOpacity(_glowAnimation.value * 0.2),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 0.85],
                      ),
                    ),
                  ),

                  // 360-degree continuous spinning Sharingan Eye Wheel
                  RotationTransition(
                    turns: _spinController,
                    child: SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: CustomPaint(
                        painter: _SharinganEyePainter(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (widget.showLabel) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing Crimson Dot
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1F5A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF1F5A).withOpacity(0.9),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                      shadows: [
                        const Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                        Shadow(color: const Color(0xFFFF1F5A).withOpacity(0.8), blurRadius: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------------
/// CUSTOM PAINTER FOR SHARINGAN EYE
/// Draws the exact 3-Tomoe Sharingan based on the website's SVG geometry
/// ---------------------------------------------------------------------------
class _SharinganEyePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 100.0;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // 1. Iris Gradient (Rich Anime Blood Crimson Iris)
    final Rect irisRect = Rect.fromCircle(center: center, radius: 47 * scale);
    final Paint irisPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFFF3366),
          Color(0xFFE0164C),
          Color(0xFF940426),
          Color(0xFF240008),
        ],
        stops: [0.0, 0.60, 0.88, 1.0],
      ).createShader(irisRect);

    canvas.drawCircle(center, 47 * scale, irisPaint);

    // 2. Outer Black Rim
    final Paint outerBorderPaint = Paint()
      ..color = const Color(0xFF150005)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8 * scale;
    canvas.drawCircle(center, 47 * scale, outerBorderPaint);

    // 3. Tomoe Connecting Orbit Ring
    final Paint orbitPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale;
    canvas.drawCircle(center, 26 * scale, orbitPaint);

    // 4. Draw 3 Magatama Tomoes (Rotated 0°, 120°, 240° around center)
    final Paint tomoePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final Paint tomoeStrokePaint = Paint()
      ..color = const Color(0xFF1A0006)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 * scale;

    final Paint tomoeInnerDotPaint = Paint()
      ..color = const Color(0xFFFF1F5A).withOpacity(0.85)
      ..style = PaintingStyle.fill;

    // SVG coordinates normalized around (50, 50)
    for (int i = 0; i < 3; i++) {
      final double angle = i * (2 * math.pi / 3);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.scale(scale);

      // Magatama path matching:
      // M 50 20 C 53.5 20 56.2 22.8 56.2 26.2 C 56.2 29.8 53.2 32.5 49.6 32.5 C 46 32.5 43.5 29.6 43.5 26.2 C 43.5 23.2 45.6 20.8 48.2 20.2 C 47 16.5 43.5 14.5 39 15 C 44 12.5 49.5 15 50 20 Z
      // Shifted by (-50, -50) to center at (0, 0)
      final Path tomoePath = Path();
      tomoePath.moveTo(0, -30);
      tomoePath.cubicTo(3.5, -30, 6.2, -27.2, 6.2, -23.8);
      tomoePath.cubicTo(6.2, -20.2, 3.2, -17.5, -0.4, -17.5);
      tomoePath.cubicTo(-4.0, -17.5, -6.5, -20.4, -6.5, -23.8);
      tomoePath.cubicTo(-6.5, -26.8, -4.4, -29.2, -1.8, -29.8);
      tomoePath.cubicTo(-3.0, -33.5, -6.5, -35.5, -11.0, -35.0);
      tomoePath.cubicTo(-6.0, -37.5, -0.5, -35.0, 0.0, -30.0);
      tomoePath.close();

      canvas.drawPath(tomoePath, tomoePaint);
      canvas.drawPath(tomoePath, tomoeStrokePaint);

      // Inner crimson dot inside tomoe head at (49.5 - 50 = -0.5, 26 - 50 = -24)
      canvas.drawCircle(const Offset(-0.5, -24.0), 1.8, tomoeInnerDotPaint);

      canvas.restore();
    }

    // 5. Center Black Pupil Core
    final Paint pupilPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8.5 * scale, pupilPaint);

    final Paint pupilBorder = Paint()
      ..color = const Color(0xFFFF1F5A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale;
    canvas.drawCircle(center, 8.5 * scale, pupilBorder);

    // 6. Specular Glint Highlight (White reflection at (-2, -2) from center)
    final Paint glintPaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - 2 * scale, center.dy - 2 * scale), 2.0 * scale, glintPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
