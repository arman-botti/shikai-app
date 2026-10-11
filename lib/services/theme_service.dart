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
  static const Color seanimePurple = Color(0xFF6152DF);    // Seanime Tenji Official Brand Purple
  static const Color crimson = Color(0xFFFF1F5A);          // Shikai Signature Crimson
  static const Color cyan = Color(0xFF00D2FF);             // Getsuga Cyan

  static final ValueNotifier<Color> accentColor = ValueNotifier<Color>(seanimePurple);
  static final ValueNotifier<String> themeName = ValueNotifier<String>('seanime');

  static Color get currentAccent => accentColor.value;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeKey) ?? 'seanime';
      setTheme(saved);
    } catch (_) {}
  }

  static void setTheme(String name) async {
    themeName.value = name;
    if (name == 'crimson') {
      accentColor.value = crimson;
    } else if (name == 'cyan') {
      accentColor.value = cyan;
    } else {
      accentColor.value = seanimePurple;
      themeName.value = 'seanime';
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, themeName.value);
    } catch (_) {}
  }

  static void cycleTheme() {
    if (themeName.value == 'seanime') {
      setTheme('crimson');
    } else if (themeName.value == 'crimson') {
      setTheme('cyan');
    } else {
      setTheme('seanime');
    }
  }

  static String get themeLabel {
    switch (themeName.value) {
      case 'crimson':
        return 'SHIKAI (CRIMSON)';
      case 'cyan':
        return 'GETSUGA (CYAN)';
      default:
        return 'SEANIME (PURPLE)';
    }
  }
}
