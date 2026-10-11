import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ---------------------------------------------------------------------------
/// SEANIME TENJI COLOR SYSTEM & THEME SERVICE
/// Authentic Seanime Tenji dark palette (#0C0C0C, #171717, #262626) with
/// signature Seanime Brand Purple (#6152DF) and customizable Shikai palettes.
/// ---------------------------------------------------------------------------
class ThemeService {
  static const String _themeKey = 'shikai_active_theme_v2';

  // Seanime Tenji Official Color Constants
  static const Color background = Color(0xFF0C0C0C);       // Pure dark matte background
  static const Color surface = Color(0xFF171717);          // Surface / Card background
  static const Color card = Color(0xFF171717);             // Card background
  static const Color border = Color(0xFF262626);           // Subtle 1px zinc border
  static const Color borderSubtle = Color(0xFF1E1E1E);     // Sub-border
  static const Color textMuted = Color(0xFFA1A1AA);        // Zinc 400
  static const Color textDarkMuted = Color(0xFF71717A);    // Zinc 500

  // Brand Accents
  static const Color crimson = Color(0xFFE50914);          // Shikai Signature Crimson Red
  static const Color seanimePurple = Color(0xFF6152DF);
  static const Color cyan = Color(0xFF00D2FF);

  static final ValueNotifier<Color> accentColor = ValueNotifier<Color>(crimson);
  static final ValueNotifier<String> themeName = ValueNotifier<String>('crimson');

  static Color get currentAccent => crimson;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Permanently lock Crimson Red as the app theme
      await prefs.setString(_themeKey, 'crimson');
      setTheme('crimson');
    } catch (_) {}
  }

  static void setTheme(String name) async {
    themeName.value = 'crimson';
    accentColor.value = crimson;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, 'crimson');
    } catch (_) {}
  }

  static void cycleTheme() {
    setTheme('crimson');
  }

  static String get themeLabel => 'SHIKAI (CRIMSON RED)';
}
