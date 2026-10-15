import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/anivexa_episode.dart';
import 'package:shikai_app/services/stream_service.dart';
import 'package:shikai_app/services/security_vault.dart';

/// -----------------------------------------------------------------------
/// ANIVEXA WATCH RESULT MODEL
/// -----------------------------------------------------------------------
class AnivexaWatchResult {
  final String streamUrl;
  final String? playlistKey;
  final String? server;
  final List<SubtitleTrack> subtitles;
  final int introStart;
  final int introEnd;
  final int outroStart;
  final int outroEnd;

  AnivexaWatchResult({
    required this.streamUrl,
    this.playlistKey,
    this.server,
    this.subtitles = const [],
    this.introStart = 0,
    this.introEnd = 0,
    this.outroStart = 0,
    this.outroEnd = 0,
  });
}

/// -----------------------------------------------------------------------
/// ANIVEXA EMBED & WATCH DATA MODEL
/// -----------------------------------------------------------------------
class AnivexaWatchData {
  final bool success;
  final String? embedUrl;
  final String? embedUrlHd1;
  final int? introStart;
  final int? introEnd;
  final int? outroStart;
  final int? outroEnd;
  final List<SubtitleTrack> subtitles;

  AnivexaWatchData({
    required this.success,
    this.embedUrl,
    this.embedUrlHd1,
    this.introStart,
    this.introEnd,
    this.outroStart,
    this.outroEnd,
    this.subtitles = const [],
  });
}

/// -----------------------------------------------------------------------
/// ANIVEXA API CLIENT (walterwhite-69/Anivexa-API)
/// Official Multi-Provider Aggregator Engine for Shikai
/// -----------------------------------------------------------------------
class AnivexaService {
  static String get baseUrl => SecurityVault.shikaiBase;

  /// Fetch full episode catalog from Anivexa Aggregator
  static Future<Map<String, List<AnivexaEpisode>>> getEpisodes(int anilistId) async {
    final Map<String, List<AnivexaEpisode>> result = {
      'sub': [],
      'dub': [],
    };

    try {
      final res = await http.get(
        Uri.parse('${SecurityVault.shikaiBase}${SecurityVault.anivexaEpisodesPath}$anilistId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 3500));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        Map<String, dynamic>? episodesMap;

        if (data['reanime']?['episodes'] != null) {
          episodesMap = data['reanime']['episodes'];
        } else if (data['episodes'] != null) {
          episodesMap = data['episodes'];
        } else {
          for (final key in data.keys) {
            if (data[key] is Map && data[key]['episodes'] != null) {
              episodesMap = data[key]['episodes'];
              break;
            }
          }
        }

        if (episodesMap != null) {
          if (episodesMap['sub'] is List) {
            final seen = <int>{};
            result['sub'] = (episodesMap['sub'] as List)
                .map((e) => AnivexaEpisode.fromJson(e))
                .where((ep) => seen.add(ep.number))
                .toList();
            result['sub']!.sort((a, b) => a.number.compareTo(b.number));
          }
          if (episodesMap['dub'] is List) {
            final seen = <int>{};
            result['dub'] = (episodesMap['dub'] as List)
                .map((e) => AnivexaEpisode.fromJson(e))
                .where((ep) => seen.add(ep.number))
                .toList();
            result['dub']!.sort((a, b) => a.number.compareTo(b.number));
          }
        }
      }
    } catch (_) {}

    return result;
  }

  /// Get ReAnime watch stream, key, subtitles, and intro/outro timestamps
  static Future<AnivexaWatchResult?> getReAnimeWatch({
    required int anilistId,
    required int episode,
    String audio = 'sub',
  }) async {
    try {
      final res = await http.get(
        Uri.parse('${SecurityVault.shikaiBase}${SecurityVault.anivexaWatchPath}$anilistId/$episode?audio=$audio'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 3500));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        final List<SubtitleTrack> subs = [];
        final rawSubs = data['subtitles'] ?? data['streams']?[0]?['subtitles'];
        if (rawSubs is List) {
          for (final s in rawSubs) {
            String subUrl = s['url'] ?? s['file'] ?? '';
            if (subUrl.isNotEmpty) {
              if (!subUrl.startsWith('http')) {
                subUrl = '${SecurityVault.shikaiBase}${subUrl.startsWith('/') ? '' : '/'}$subUrl';
              }
              subs.add(SubtitleTrack(
                url: subUrl,
                label: s['language'] ?? s['label'] ?? s['lang'] ?? 'English',
                language: s['lang'] ?? s['language'] ?? 'en',
                flag: s['flag'] ?? '',
                isDefault: s['default'] == true,
              ));
            }
          }
        }

        final introStart = data['intro']?['start'] ?? data['intro_start'] ?? 0;
        final introEnd = data['intro']?['end'] ?? data['intro_end'] ?? 0;
        final outroStart = data['outro']?['start'] ?? data['outro_start'] ?? 0;
        final outroEnd = data['outro']?['end'] ?? data['outro_end'] ?? 0;

        String streamUrl = data['stream_url'] ?? data['streamUrl'] ?? '';
        String? playlistKey = data['playlist_key'] ?? data['key'];

        if (streamUrl.isEmpty && data['streams'] is List && (data['streams'] as List).isNotEmpty) {
          streamUrl = data['streams'][0]['url'] ?? '';
          playlistKey ??= data['streams'][0]['key'] ?? data['streams'][0]['playlist_key'];
        }

        if (streamUrl.isNotEmpty) {
          if (!streamUrl.startsWith('http')) {
            streamUrl = '${SecurityVault.shikaiBase}${streamUrl.startsWith('/') ? '' : '/'}$streamUrl';
          }
          return AnivexaWatchResult(
            streamUrl: streamUrl,
            playlistKey: playlistKey,
            server: data['server'] ?? 'HD-2',
            subtitles: subs,
            introStart: introStart is num ? introStart.toInt() : 0,
            introEnd: introEnd is num ? introEnd.toInt() : 0,
            outroStart: outroStart is num ? outroStart.toInt() : 0,
            outroEnd: outroEnd is num ? outroEnd.toInt() : 0,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get AniZone watch stream (fallback stub)
  static Future<AnivexaWatchResult?> getAniZoneWatch({
    required int anilistId,
    required int episode,
    String audio = 'sub',
  }) async {
    return null;
  }

  /// Get AniKoto watch stream (fallback stub)
  static Future<AnivexaWatchResult?> getAniKotoWatch({
    required int anilistId,
    required int episode,
    String audio = 'sub',
  }) async {
    return null;
  }

  /// Fetch official Anivexa Watch & Embed Data
  static Future<AnivexaWatchData?> getWatchData({
    required int anilistId,
    required int episode,
    String audio = 'sub',
  }) async {
    try {
      final res = await http.get(
        Uri.parse('${SecurityVault.shikaiBase}${SecurityVault.anivexaWatchPath}$anilistId/$episode?audio=$audio'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic>) {
          String? embedUrl = data['embedUrl'] ?? data['embed'];
          String? embedUrlHd1 = data['embedUrlHd1'];

          final introStart = data['intro']?['start'] ?? data['intro_start'] ?? 0;
          final introEnd = data['intro']?['end'] ?? data['intro_end'] ?? 0;
          final outroStart = data['outro']?['start'] ?? data['outro_start'] ?? 0;
          final outroEnd = data['outro']?['end'] ?? data['outro_end'] ?? 0;

          final List<SubtitleTrack> subs = [];
          final rawSubs = data['subtitles'] ?? data['streams']?[0]?['subtitles'];
          if (rawSubs is List) {
            for (final s in rawSubs) {
              String subUrl = s['url'] ?? s['file'] ?? '';
              if (subUrl.isNotEmpty) {
                if (!subUrl.startsWith('http')) {
                  subUrl = '${SecurityVault.shikaiBase}${subUrl.startsWith('/') ? '' : '/'}$subUrl';
                }
                subs.add(SubtitleTrack(
                  url: subUrl,
                  label: s['language'] ?? s['label'] ?? s['lang'] ?? 'English',
                  language: s['lang'] ?? s['language'] ?? 'en',
                  flag: s['flag'] ?? '',
                  isDefault: s['default'] == true,
                ));
              }
            }
          }

          return AnivexaWatchData(
            success: data['success'] == true || embedUrl != null,
            embedUrl: embedUrl,
            embedUrlHd1: embedUrlHd1,
            introStart: introStart is num ? introStart.toInt() : 0,
            introEnd: introEnd is num ? introEnd.toInt() : 0,
            outroStart: outroStart is num ? outroStart.toInt() : 0,
            outroEnd: outroEnd is num ? outroEnd.toInt() : 0,
            subtitles: subs,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
