import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shikai_app/main.dart';
import 'package:shikai_app/services/theme_service.dart';

/// ---------------------------------------------------------------------------
/// SHIKAI MUSE-STYLE CINEMATIC OPENING SCREEN
/// Inspired by the minimalist Japanese anime aesthetic of Muse.
/// Features a breathing reiatsu pulse, glowing katana emblem reveal,
/// kinetic kanji typography, and a seamless dissolve transition to Home.
/// ---------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _revealController;
  late AnimationController _pulseController;
  late AnimationController _laserController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<Offset> _textSlideAnimation;
  late Animation<double> _laserProgress;

  @override
  void initState() {
    super.initState();

    // Lock to edge-to-edge immersive mode on start
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 1. Reveal Animation (Scale + Fade in over 1200ms)
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );

    _textFadeAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.35, 1.0, curve: Curves.easeIn),
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
    ));

    // 2. Breathing Pulse Aura Animation (repeats continuously)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // 3. Laser Beam Progress Animation
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _laserProgress = CurvedAnimation(
      parent: _laserController,
      curve: Curves.easeInOutCubic,
    );

    // Kick off animations
    _revealController.forward();
    _laserController.forward();

    // 4. Seamless Transition into Shikai Home Screen after 2.4s
    Timer(const Duration(milliseconds: 2400), _navigateToHome);
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => const ShikaiHomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    _pulseController.dispose();
    _laserController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.currentAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF090A0F), // Deep obsidian void canvas
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Atmospheric Radial Ambient Glow
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _pulseController.value;
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85 + (pulse * 0.15),
                    colors: [
                      accent.withOpacity(0.12 + (pulse * 0.08)),
                      accent.withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              );
            },
          ),

          // Central Hero Composition
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glowing Breathing Aura + Shikai Katana Emblem
                AnimatedBuilder(
                  animation: Listenable.merge([_scaleAnimation, _pulseController]),
                  builder: (context, child) {
                    final pulse = _pulseController.value;
                    final scale = _scaleAnimation.value;

                    return Transform.scale(
                      scale: scale,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer Spiritual Ring Ripple 1
                          Container(
                            width: 140 + (pulse * 24),
                            height: 140 + (pulse * 24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent.withOpacity((0.25 - (pulse * 0.15)).clamp(0.0, 1.0)),
                                width: 1.5,
                              ),
                            ),
                          ),

                          // Inner Breathing Aura Ring 2
                          Container(
                            width: 120 + (pulse * 12),
                            height: 120 + (pulse * 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.25 + (pulse * 0.2)),
                                  blurRadius: 32 + (pulse * 16),
                                  spreadRadius: 2 + (pulse * 4),
                                ),
                              ],
                            ),
                          ),

                          // Emblem Icon Container
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: const Color(0xFF11131C),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent.withOpacity(0.55),
                                width: 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.85),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/app_icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Icon(Icons.flash_on_rounded, color: accent, size: 52),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // Kinetic Typography (Slide + Fade)
                SlideTransition(
                  position: _textSlideAnimation,
                  child: FadeTransition(
                    opacity: _textFadeAnimation,
                    child: Column(
                      children: [
                        // Main Brand Name with wide Japanese spacing
                        Text(
                          "SHIKAI",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 10.0,
                            shadows: [
                              Shadow(
                                color: accent.withOpacity(0.7),
                                blurRadius: 20,
                              ),
                              const Shadow(
                                color: Colors.black87,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Kanji Subtitle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 20, height: 1, color: accent.withOpacity(0.4)),
                            const SizedBox(width: 8),
                            Text(
                              "始 解 • RELEASE",
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(width: 20, height: 1, color: accent.withOpacity(0.4)),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Elegant Tagline
                        const Text(
                          "Release Your Anime",
                          style: TextStyle(
                            color: Color(0xFF8E92A4),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Laser Loading Indicator & Footnote
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Sleek Laser Loading Beam
                  SizedBox(
                    width: 140,
                    height: 2.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Stack(
                        children: [
                          Container(
                            color: Colors.white10,
                          ),
                          AnimatedBuilder(
                            animation: _laserProgress,
                            builder: (context, child) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _laserProgress.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          accent.withOpacity(0.4),
                                          accent,
                                          Colors.white,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withOpacity(0.8),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Minimal Version Footnote
                  Text(
                    "v1.0.0 • Seanime Tenji Edition",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
