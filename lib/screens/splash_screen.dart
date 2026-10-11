import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shikai_app/main.dart';
import 'package:shikai_app/services/app_preload_service.dart';

/// ---------------------------------------------------------------------------
/// SHIKAI CINEMATIC MINIMALIST OPENING SCREEN
/// Inspired by high-end Japanese anime streaming aesthetic (Muse / Sony).
/// Pure OLED black void, soft atmospheric spiritual glow, iconic katana emblem,
/// razor-sharp typography, and live background preloading into GPU memory.
/// ---------------------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _revealController;
  late AnimationController _pulseController;
  late AnimationController _progressController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _progressAnimation;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Edge-to-edge transparent system bars for seamless immersion
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // 1. Reveal Animation (Gentle micro-scale 0.94 -> 1.0 + fade in)
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _textFadeAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    );

    // 2. Soft Breathing Backlight Glow (Subtle 0.10 -> 0.18 pulse)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // 3. Ultra-thin progress indicator
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );

    _revealController.forward();
    _progressController.forward();

    // 4. Start background data preloading as soon as the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundPreloadAndNavigate();
    });
  }

  Future<void> _startBackgroundPreloadAndNavigate() async {
    try {
      // Warm up metadata and precache hero banners & posters into GPU memory
      await Future.any([
        Future.wait([
          AppPreloadService.preloadAll(context),
          Future.delayed(const Duration(milliseconds: 1350)), // Minimum aesthetic dwell time
        ]),
        Future.delayed(const Duration(milliseconds: 2200)), // Safety timeout
      ]);
    } catch (_) {}

    // Complete the progress animation smoothly if not yet done
    if (mounted && _progressController.status != AnimationStatus.completed) {
      _progressController.animateTo(1.0, duration: const Duration(milliseconds: 200));
      await Future.delayed(const Duration(milliseconds: 120));
    }

    _navigateToHome();
  }

  void _navigateToHome() {
    if (!mounted || _navigated) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) => const ShikaiHomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
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
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const crimsonAccent = Color(0xFFE50914);

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Pure OLED dark canvas
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Atmospheric Optical Center Glow (Soft Gaussian Backlight)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _pulseController.value;
              return Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        crimsonAccent.withOpacity(0.12 + (pulse * 0.06)),
                        crimsonAccent.withOpacity(0.03),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),

          // Central Minimalist Composition
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Clean Floating Shikai Katana Emblem (No tacky outer rings)
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.9),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: crimsonAccent.withOpacity(0.25),
                            blurRadius: 20,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.flash_on_rounded, color: crimsonAccent, size: 48),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Refined Brand Typography
                    FadeTransition(
                      opacity: _textFadeAnimation,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // S H I K A I
                          Text(
                            "SHIKAI",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 9.0,
                            ),
                          ),

                          SizedBox(height: 6),

                          // Minimal Kanji Subtitle
                          Text(
                            "始 解",
                            style: TextStyle(
                              color: crimsonAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 6.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Razor-Thin Progress Line (Ultra-minimalist)
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: SizedBox(
                  width: 100,
                  height: 1.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: Stack(
                      children: [
                        Container(
                          color: Colors.white.withOpacity(0.06),
                        ),
                        AnimatedBuilder(
                          animation: _progressAnimation,
                          builder: (context, child) {
                            return FractionallySizedBox(
                              widthFactor: _progressAnimation.value.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF8B0000),
                                      crimsonAccent,
                                      Colors.white,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: crimsonAccent.withOpacity(0.8),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
