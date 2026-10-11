import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shikai_app/services/stream_service.dart';

class SubtitleCue {
  final double start;
  final double end;
  final String text;

  SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

class SubtitleRaceWinner {
  final int index;
  final SubtitleTrack track;
  final List<SubtitleCue> cues;
  final int cueCount;
  final int latencyMs;

  SubtitleRaceWinner({
    required this.index,
    required this.track,
    required this.cues,
    required this.cueCount,
    required this.latencyMs,
  });
}

/// ---------------------------------------------------------------------------
/// SHIKAI UNIVERSAL BULLETPROOF SUBTITLE ENGINE
/// Supports Native .ASS, .SSA, .SRT, .VTT parsing with 3-Layer Network Failover,
/// Full Multi-Language Cataloging & Dedicated English (Dubtitle AI) Support.
/// ---------------------------------------------------------------------------
class SubtitleService {
  // 0ms in-memory cue cache
  static final Map<String, List<SubtitleCue>> _cache = {};

  static const String _prefLangKey = 'shikai_preferred_sub_lang';
  static const String _prefFontSizeKey = 'shikai_sub_font_size';
  static const String _prefColorKey = 'shikai_sub_color_val';
  static const String _prefEnabledKey = 'shikai_sub_enabled';

  /// Save user's chosen subtitle language (e.g. 'en', 'en-ai', 'es', 'ja', 'off') to persist across all anime
  static Future<void> savePreferredLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLangKey, lang);
  }

  /// Get user's globally chosen subtitle language
  static Future<String?> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLangKey);
  }

  /// Save whether subtitles are globally enabled/disabled
  static Future<void> saveSubtitlesEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
  }

  /// Get whether subtitles are globally enabled
  static Future<bool> getSubtitlesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? true;
  }

  /// Save user's appearance preferences (size, color)
  static Future<void> saveSubtitleAppearance({required double size, required int colorVal}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefFontSizeKey, size);
    await prefs.setInt(_prefColorKey, colorVal);
  }

  /// Retrieve persistent appearance settings
  static Future<Map<String, dynamic>> getSubtitleSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble(_prefFontSizeKey) ?? 16.0;
    final colorVal = prefs.getInt(_prefColorKey) ?? 0xFFFFFFFF;
    final enabled = prefs.getBool(_prefEnabledKey) ?? true;
    final lang = prefs.getString(_prefLangKey) ?? 'en';
    return {
      'size': size,
      'color': Color(colorVal),
      'enabled': enabled,
      'lang': lang,
    };
  }

  /// Universal Timestamp Parser: Handles H:MM:SS.cs (ASS), HH:MM:SS.mmm (VTT/SRT), MM:SS.mmm
  static double parseTimestamp(String timeStr) {
    if (timeStr.isEmpty) return 0.0;
    final clean = timeStr.trim().replaceAll(',', '.');
    final parts = clean.split(':');
    try {
      if (parts.length == 3) {
        final h = double.tryParse(parts[0]) ?? 0.0;
        final m = double.tryParse(parts[1]) ?? 0.0;
        final s = double.tryParse(parts[2]) ?? 0.0;
        return h * 3600.0 + m * 60.0 + s;
      } else if (parts.length == 2) {
        final m = double.tryParse(parts[0]) ?? 0.0;
        final s = double.tryParse(parts[1]) ?? 0.0;
        return m * 60.0 + s;
      }
      return double.tryParse(clean) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// -------------------------------------------------------------------------
  /// 1. ADVANCED SUBSTATION ALPHA (.ASS / .SSA) PARSER
  /// Extracts dialogue events, handles styling tags, line breaks, and timestamp parsing
  /// -------------------------------------------------------------------------
  static List<SubtitleCue> parseAssToCues(String assText) {
    if (assText.isEmpty) return [];
    final List<SubtitleCue> cues = [];
    final lines = assText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (!trimmed.toLowerCase().startsWith('dialogue:')) continue;
      // Skip vector drawing modes in ASS (e.g. \p1, \p2)
      if (trimmed.contains(r'\p1') || trimmed.contains(r'\p2') || trimmed.contains(r'\p4')) continue;

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx == -1) continue;
      final payload = trimmed.substring(colonIdx + 1);
      final parts = payload.split(',');
      if (parts.length < 10) continue;

      final start = parseTimestamp(parts[1]);
      final end = parseTimestamp(parts[2]);
      if (end <= start) continue;

      final style = (parts[3]).toLowerCase().trim();
      if (style.contains('credit') || style.contains('logo') || style.contains('staff')) {
        continue;
      }

      // Everything from index 9 onwards is the dialogue text (may contain commas)
      String text = parts.sublist(9).join(',').trim();
      text = text
          .replaceAll(RegExp(r'\{[^}]+\}'), '') // Strips ASS styling tags {\an8}, {\c&H...&}, {\pos(...)}
          .replaceAll(RegExp(r'\\N', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'\\n', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'\\h', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();

      // Discard drawing commands like "m 0 0 l 10 10..."
      if (text.isEmpty || RegExp(r'^m\s+[-0-9]+', caseSensitive: false).hasMatch(text)) {
        continue;
      }

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// -------------------------------------------------------------------------
  /// 2. WEBVTT & SUBRIP (.VTT / .SRT) PARSER
  /// Handles timestamp arrows ("-->"), HTML formatting, line breaks, and cue settings
  /// -------------------------------------------------------------------------
  static List<SubtitleCue> parseSrtOrVttToCues(String content) {
    if (content.isEmpty) return [];
    final List<SubtitleCue> cues = [];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n+'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      final arrowLineIndex = lines.indexWhere((l) => l.contains('-->'));
      if (arrowLineIndex == -1) continue;

      final times = lines[arrowLineIndex].split('-->');
      if (times.length < 2) continue;

      final startRaw = times[0].trim().split(RegExp(r'\s+'))[0];
      final endRaw = times[1].trim().split(RegExp(r'\s+'))[0];

      final start = parseTimestamp(startRaw);
      final end = parseTimestamp(endRaw);

      if (end <= start) continue;

      final textLines = lines.sublist(arrowLineIndex + 1);
      String text = textLines
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\{[^}]+\}'), '')
          .replaceAll(RegExp(r'\\N', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'\\n', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'\\h', caseSensitive: false), ' ')
          .trim();

      if (text.isEmpty || RegExp(r'^m\s+[-0-9]+', caseSensitive: false).hasMatch(text)) {
        continue;
      }

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// -------------------------------------------------------------------------
  /// 3. UNIVERSAL FORMAT DETECTOR & PARSER
  /// Auto-detects .ASS, .SSA, .SRT, .VTT from raw payload and returns cleaned cues
  /// -------------------------------------------------------------------------
  static List<SubtitleCue> parseAnySubtitleFormat(String rawContent) {
    if (rawContent.isEmpty) return [];
    final clean = rawContent.replaceAll('\uFEFF', '').trim();

    // Check for ASS/SSA signatures
    if (clean.toLowerCase().contains('[script info]') || clean.toLowerCase().contains('dialogue:')) {
      final assCues = parseAssToCues(clean);
      if (assCues.isNotEmpty) return assCues;
    }

    // Try VTT / SRT format
    final vttCues = parseSrtOrVttToCues(clean);
    if (vttCues.isNotEmpty) return vttCues;

    // Fallback: If VTT failed, maybe ASS without [script info] header
    if (clean.contains('Dialogue:')) {
      return parseAssToCues(clean);
    }

    return [];
  }

  /// Clean & Deduplicate Subtitle Lines (matches cleanAndDeduplicateSubtitleLines from HlsPlayer.tsx)
  /// Maximum 2 lines to strictly adhere to professional anime subtitling standards
  static String cleanAndDeduplicateSubtitleLines(List<SubtitleCue> matchingCues) {
    if (matchingCues.isEmpty) return '';
    final List<String> lines = [];

    for (final m in matchingCues) {
      final split = m.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      for (final line in split) {
        final isDuplicate = lines.any((existing) {
          final eLow = existing.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          final lLow = line.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          return eLow == lLow || (eLow.length > 5 && lLow.length > 5 && (eLow.contains(lLow) || lLow.contains(eLow)));
        });
        if (!isDuplicate) {
          lines.add(line);
        }
      }
    }

    return lines.take(2).join('\n');
  }

  /// Helper: Check if track is AI Dubtitle
  static bool isAiDubtitle(SubtitleTrack s) {
    final lbl = s.label.toLowerCase();
    final url = s.url.toLowerCase();
    return lbl.contains('dubtitle') ||
        lbl.contains('(ai)') ||
        lbl.contains('ai dub') ||
        lbl.contains('dub title') ||
        url.contains('dubtitle') ||
        url.contains('(ai)');
  }

  /// Helper: Check if track is Signs & Songs (non-dialogue)
  static bool isSignOrSongTrack(SubtitleTrack s) {
    final lbl = s.label.toLowerCase();
    final url = s.url.toLowerCase();
    return lbl.contains('sign') ||
        lbl.contains('song') ||
        lbl.contains('s&s') ||
        lbl.contains('forced') ||
        url.contains('forced') ||
        lbl.contains('episode name') ||
        lbl.contains('title only');
  }

  /// Country flag mapping helper
  static String getFlagForLanguage(String code, String label) {
    final c = code.toLowerCase().trim();
    final l = label.toLowerCase().trim();
    if (c == 'en' || l.contains('english')) return '🇺🇸';
    if (c == 'es' || l.contains('spanish') || l.contains('español')) return l.contains('latin') ? '🇲🇽' : '🇪🇸';
    if (c == 'pt' || l.contains('portuguese') || l.contains('português')) return l.contains('portugal') ? '🇵🇹' : '🇧🇷';
    if (c == 'fr' || l.contains('french') || l.contains('français')) return '🇫🇷';
    if (c == 'de' || l.contains('german') || l.contains('deutsch')) return '🇩🇪';
    if (c == 'it' || l.contains('italian') || l.contains('italiano')) return '🇮🇹';
    if (c == 'ru' || l.contains('russian') || l.contains('русский')) return '🇷🇺';
    if (c == 'ar' || l.contains('arabic') || l.contains('عربي')) return '🇸🇦';
    if (c == 'hi' || l.contains('hindi') || l.contains('हिन्दी')) return '🇮🇳';
    if (c == 'ja' || l.contains('japanese') || l.contains('日本語')) return '🇯🇵';
    if (c == 'id' || l.contains('indonesian') || l.contains('bahasa')) return '🇮🇩';
    if (c == 'tr' || l.contains('turkish') || l.contains('türkçe')) return '🇹🇷';
    if (c == 'vi' || l.contains('vietnamese') || l.contains('tiếng việt')) return '🇻🇳';
    if (c == 'th' || l.contains('thai') || l.contains('ไทย')) return '🇹🇭';
    if (c == 'zh' || l.contains('chinese') || l.contains('中文')) return '🇨🇳';
    if (c == 'ko' || l.contains('korean') || l.contains('한국어')) return '🇰🇷';
    if (c == 'pl' || l.contains('polish') || l.contains('polski')) return '🇵🇱';
    if (c == 'nl' || l.contains('dutch') || l.contains('nederlands')) return '🇳🇱';
    return '🌐';
  }

  static String getLocalizedLanguageName(String code, String label) {
    final c = code.toLowerCase().trim();
    final l = label.toLowerCase().trim();
    if (c == 'en' || l.contains('english')) return 'English';
    if (c == 'es' || l.contains('spanish') || l.contains('español')) return l.contains('latin') ? 'Español (Latino)' : 'Español';
    if (c == 'pt' || l.contains('portuguese') || l.contains('português')) return l.contains('portugal') ? 'Português (Portugal)' : 'Português (Brasil)';
    if (c == 'fr' || l.contains('french') || l.contains('français')) return 'Français';
    if (c == 'de' || l.contains('german') || l.contains('deutsch')) return 'Deutsch';
    if (c == 'it' || l.contains('italian') || l.contains('italiano')) return 'Italiano';
    if (c == 'ru' || l.contains('russian') || l.contains('русский')) return 'Русский';
    if (c == 'ar' || l.contains('arabic') || l.contains('عربي')) return 'العربية';
    if (c == 'hi' || l.contains('hindi') || l.contains('हिन्दी')) return 'हिन्दी';
    if (c == 'ja' || l.contains('japanese') || l.contains('日本語')) return '日本語';
    if (c == 'id' || l.contains('indonesian') || l.contains('bahasa')) return 'Bahasa Indonesia';
    if (c == 'tr' || l.contains('turkish') || l.contains('türkçe')) return 'Türkçe';
    if (c == 'vi' || l.contains('vietnamese') || l.contains('tiếng việt')) return 'Tiếng Việt';
    if (c == 'th' || l.contains('thai') || l.contains('ไทย')) return 'ไทย';
    if (c == 'zh' || l.contains('chinese') || l.contains('中文')) return '中文';
    if (c == 'ko' || l.contains('korean') || l.contains('한국어')) return '한국어';
    if (c == 'pl' || l.contains('polish') || l.contains('polski')) return 'Polski';
    if (c == 'nl' || l.contains('dutch') || l.contains('nederlands')) return 'Nederlands';
    return label.isNotEmpty ? label : code.toUpperCase();
  }

  /// -------------------------------------------------------------------------
  /// 4. SMART SUBTITLE CATALOG & MULTI-COUNTRY DEDUPLICATION
  /// Preserves:
  /// - 1. English (Official Full Dialogue) 🇺🇸
  /// - 2. English (Dubtitle AI) 🤖
  /// - 3. All distinct international country languages (Spanish, Portuguese, French, German, Italian, Hindi, Russian, Arabic, etc.)
  /// - 4. English (Signs & Songs) 🇺🇸
  /// -------------------------------------------------------------------------
  static List<SubtitleTrack> cleanSubtitleTracks(List<SubtitleTrack> tracks) {
    if (tracks.isEmpty) return [];

    final List<SubtitleTrack> cleaned = [];
    final Set<String> seenKeys = {};

    SubtitleTrack? bestEnglishDialogue;
    SubtitleTrack? bestEnglishAi;
    SubtitleTrack? bestEnglishSigns;

    final List<SubtitleTrack> otherLanguages = [];

    for (final track in tracks) {
      if (track.url.trim().isEmpty) continue;
      final lbl = track.label.trim().toLowerCase();

      // Filter out garbage/placeholders
      if (lbl.contains('dummy') ||
          lbl.contains('empty') ||
          lbl == 'null' ||
          lbl == 'test' ||
          lbl == 'undefined') {
        continue;
      }

      final isAi = isAiDubtitle(track);
      final isSigns = isSignOrSongTrack(track);
      String langCode = (track.language.isNotEmpty ? track.language : 'en').toLowerCase().trim();

      if (langCode == 'en' || lbl.contains('english')) {
        if (isAi) {
          bestEnglishAi ??= SubtitleTrack(
            url: track.url,
            label: "English (Dubtitle AI) 🤖",
            language: 'en-ai',
            flag: '🤖',
            isDefault: false,
          );
        } else if (isSigns) {
          bestEnglishSigns ??= SubtitleTrack(
            url: track.url,
            label: "English (Signs & Songs) 🇺🇸",
            language: 'en-signs',
            flag: '🇺🇸',
            isDefault: false,
          );
        } else {
          // Regular dialogue track: prioritize full dialogue over title-only
          if (bestEnglishDialogue == null || lbl.contains('full') || lbl.contains('dialogue') || lbl.contains('restyled')) {
            bestEnglishDialogue = SubtitleTrack(
              url: track.url,
              label: "English (Full Dialogue) 🇺🇸",
              language: 'en',
              flag: '🇺🇸',
              isDefault: true,
            );
          }
        }
      } else {
        // International Country Languages (Spanish, French, German, Portuguese, Hindi, Arabic, Russian, etc.)
        final flag = track.flag.isNotEmpty ? track.flag : getFlagForLanguage(langCode, track.label);
        final locName = getLocalizedLanguageName(langCode, track.label);
        final uniqueKey = '${langCode}_${isSigns ? "signs" : "dialogue"}';

        if (!seenKeys.contains(uniqueKey)) {
          seenKeys.add(uniqueKey);
          otherLanguages.add(SubtitleTrack(
            url: track.url,
            label: "$locName $flag",
            language: langCode,
            flag: flag,
            isDefault: false,
          ));
        }
      }
    }

    // Assemble final priority list
    if (bestEnglishDialogue != null) cleaned.add(bestEnglishDialogue);
    if (bestEnglishAi != null) cleaned.add(bestEnglishAi);
    cleaned.addAll(otherLanguages);
    if (bestEnglishSigns != null) cleaned.add(bestEnglishSigns);

    // Fallback if empty: return any unique by url
    if (cleaned.isEmpty) {
      final seen = <String>{};
      for (final t in tracks) {
        if (t.url.isNotEmpty && seen.add(t.url)) {
          cleaned.add(t);
        }
      }
    }

    return cleaned;
  }

  /// Subtitle Race: Concurrently evaluates candidate subtitle tracks,
  /// testing speed, completeness (cue count), and cleanliness to declare the #1 winner.
  static Future<SubtitleRaceWinner?> raceForBestTrack(
    List<SubtitleTrack> tracks, {
    List<SubtitleTrack> rawCandidates = const [],
    String preferredLang = 'en',
  }) async {
    if (tracks.isEmpty && rawCandidates.isEmpty) return null;

    final allCandidates = <SubtitleTrack>[
      ...tracks,
      ...rawCandidates,
    ];

    // Filter to candidate tracks matching preferred language, prioritizing dialogue over signs
    final targetCandidates = allCandidates.where((t) {
      final lang = t.language.toLowerCase();
      final lbl = t.label.toLowerCase();
      if (preferredLang == 'en') {
        return (lang == 'en' || lang == 'en-ai' || lbl.contains('english')) && !isSignOrSongTrack(t);
      }
      return lang.startsWith(preferredLang) || lbl.contains(preferredLang);
    }).toList();

    final pool = targetCandidates.isNotEmpty
        ? targetCandidates
        : allCandidates.where((t) => t.language.startsWith(preferredLang)).toList();

    if (pool.isEmpty) {
      if (tracks.isNotEmpty) {
        final cues = await loadSubtitles(tracks.first.url, lang: tracks.first.language);
        return SubtitleRaceWinner(
          index: 0,
          track: tracks.first,
          cues: cues,
          cueCount: cues.length,
          latencyMs: 0,
        );
      }
      return null;
    }

    // Limit concurrent race to top 5 candidates to conserve bandwidth
    final racers = pool.take(5).toList();

    // Run parallel race with individual stopwatches
    final List<Future<SubtitleRaceWinner?>> futures = racers.map((track) async {
      final sw = Stopwatch()..start();
      try {
        final cues = await loadSubtitles(track.url, lang: track.language).timeout(
          const Duration(milliseconds: 3200),
          onTimeout: () => [],
        );
        sw.stop();
        if (cues.isEmpty) return null;

        return SubtitleRaceWinner(
          index: tracks.indexOf(track),
          track: track,
          cues: cues,
          cueCount: cues.length,
          latencyMs: sw.elapsedMilliseconds,
        );
      } catch (_) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);
    final validWinners = results.whereType<SubtitleRaceWinner>().toList();

    if (validWinners.isEmpty) {
      if (tracks.isNotEmpty) {
        final cues = await loadSubtitles(tracks.first.url, lang: tracks.first.language);
        return SubtitleRaceWinner(
          index: 0,
          track: tracks.first,
          cues: cues,
          cueCount: cues.length,
          latencyMs: 0,
        );
      }
      return null;
    }

    // Scoring function:
    // 1. Fullness: High cue count (>100 cues = full episode)
    // 2. Penalty if cue count is tiny (< 15 cues, title only)
    // 3. Speed: Lower latencyMs
    validWinners.sort((a, b) {
      double scoreA = (a.cueCount * 3.0) - (a.latencyMs * 0.1);
      double scoreB = (b.cueCount * 3.0) - (b.latencyMs * 0.1);

      if (a.cueCount < 15) scoreA -= 5000;
      if (b.cueCount < 15) scoreB -= 5000;

      final lblA = a.track.label.toLowerCase();
      final lblB = b.track.label.toLowerCase();
      if (lblA.contains('full') || lblA.contains('dialogue')) scoreA += 500;
      if (lblB.contains('full') || lblB.contains('dialogue')) scoreB += 500;
      if (lblA.contains('episode name') || lblA.contains('forced') || lblA.contains('s&s')) scoreA -= 2000;
      if (lblB.contains('episode name') || lblB.contains('forced') || lblB.contains('s&s')) scoreB -= 2000;

      return scoreB.compareTo(scoreA); // Highest score wins
    });

    final ultimateWinner = validWinners.first;
    int targetIndex = tracks.indexOf(ultimateWinner.track);
    if (targetIndex == -1) {
      targetIndex = tracks.indexWhere((t) => t.language == ultimateWinner.track.language);
      if (targetIndex == -1) targetIndex = 0;
    }

    return SubtitleRaceWinner(
      index: targetIndex,
      track: ultimateWinner.track,
      cues: ultimateWinner.cues,
      cueCount: ultimateWinner.cueCount,
      latencyMs: ultimateWinner.latencyMs,
    );
  }

  /// Find the optimal dialogue subtitle track
  static int findOptimalTrackIndex(List<SubtitleTrack> tracks, {String? userPreferredLang}) {
    if (tracks.isEmpty) return -1;

    // 1. If user previously chose a specific language, try to honor that language
    if (userPreferredLang != null && userPreferredLang != 'off') {
      final userMatch = tracks.indexWhere((s) => s.language == userPreferredLang);
      if (userMatch != -1) return userMatch;
    }

    // 2. Official English Dialogue
    final engDialogueIdx = tracks.indexWhere((s) => s.language == 'en' && !isSignOrSongTrack(s));
    if (engDialogueIdx != -1) return engDialogueIdx;

    // 3. AI Dubtitle
    final aiIdx = tracks.indexWhere((s) => isAiDubtitle(s));
    if (aiIdx != -1) return aiIdx;

    // 4. Default track
    final defaultIdx = tracks.indexWhere((s) => s.isDefault);
    if (defaultIdx != -1) return defaultIdx;

    return 0;
  }

  /// -------------------------------------------------------------------------
  /// 5. 3-LAYER NETWORK FAILOVER SUBTITLE LOADER
  /// Layer 1: Direct fetch with native ASS/SRT/VTT parsing
  /// Layer 2: Shikai Server VTT Converter Proxy (/api/subtitles/vtt?url=...)
  /// Layer 3: Shikai Host prefix resolution
  /// -------------------------------------------------------------------------
  static Future<List<SubtitleCue>> loadSubtitles(String url, {String lang = 'en'}) async {
    if (url.isEmpty) return [];

    if (_cache.containsKey(url) && _cache[url]!.isNotEmpty) {
      return _cache[url]!;
    }

    String effectiveUrl = url;
    if (effectiveUrl.startsWith('//')) {
      effectiveUrl = 'https:$effectiveUrl';
    } else if (effectiveUrl.startsWith('/api/')) {
      effectiveUrl = 'https://shikai.biz$effectiveUrl';
    }

    // -----------------------------------------------------------------------
    // LAYER 1: Direct Fetch & Native Multi-Format Parsing
    // -----------------------------------------------------------------------
    try {
      final res = await http.get(
        Uri.parse(effectiveUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/plain, text/vtt, application/x-subrip, */*',
        },
      ).timeout(const Duration(milliseconds: 4000));

      if (res.statusCode == 200 && res.body.isNotEmpty && !res.body.startsWith('<!DOCTYPE')) {
        final cues = parseAnySubtitleFormat(res.body);
        if (cues.isNotEmpty) {
          _cache[url] = cues;
          return cues;
        }
      }
    } catch (_) {}

    // -----------------------------------------------------------------------
    // LAYER 2: Server VTT Converter Proxy Failover
    // Converts remote .ass or protected streams to clean WebVTT via shikai.biz
    // -----------------------------------------------------------------------
    try {
      final cleanLang = lang.replaceAll('-ai', '').replaceAll('-signs', '');
      final converterUrl = 'https://shikai.biz/api/subtitles/vtt?url=${Uri.encodeComponent(effectiveUrl)}&lang=$cleanLang';

      final res = await http.get(
        Uri.parse(converterUrl),
        headers: {
          'Accept': 'text/vtt, text/plain, */*',
        },
      ).timeout(const Duration(milliseconds: 5000));

      if (res.statusCode == 200 && res.body.isNotEmpty && !res.body.startsWith('<!DOCTYPE')) {
        final cues = parseAnySubtitleFormat(res.body);
        if (cues.isNotEmpty) {
          _cache[url] = cues;
          return cues;
        }
      }
    } catch (_) {}

    return [];
  }
}
