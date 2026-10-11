import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/stream_service.dart';

/// Intelligent Multi-Source Anime Aggregator & Deduplication Engine
/// Integrates AniList, Anivexa (HD-2/HD-1), and Miruro (Smart Fallback).
/// Strictly ensures single unified entries without duplicate cards (e.g. 1 unified JJK, Pokemon through Miruro).
class AnimeAggregatorService {
  static String get shikaiBaseUrl => StreamService.shikaiBaseUrl;

  /// Normalize anime title string for robust duplicate matching across sources
  static String normalizeTitle(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  /// Unified search across AniList, Anivexa, and Miruro with strict deduplication
  static Future<List<AnilistMedia>> searchUnified(String query, {int page = 1, int perPage = 25}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Parallel search across AniList (rich metadata) and Shikai Anivexa / Miruro backend
    final anilistFuture = AnilistService.searchAnime(cleanQuery, page: page, perPage: perPage);
    final backendFuture = _searchBackendSources(cleanQuery);

    final results = await Future.wait([anilistFuture, backendFuture]);
    final anilistResults = results[0];
    final backendResults = results[1];

    final Map<String, AnilistMedia> unifiedMap = {};
    final Set<int> seenIds = {};

    // 1. Ingest primary AniList results
    for (final media in anilistResults) {
      if (media.id > 0) seenIds.add(media.id);
      final normKey = normalizeTitle(media.title.isNotEmpty ? media.title : media.englishTitle);
      if (normKey.isNotEmpty) {
        unifiedMap[normKey] = media;
      }
    }

    // 2. Merge backend results (Anivexa / Miruro), deduplicating existing entries
    for (final bMedia in backendResults) {
      if (bMedia.id > 0 && seenIds.contains(bMedia.id)) {
        continue; // Already included via AniList ID
      }

      final normKey = normalizeTitle(bMedia.title.isNotEmpty ? bMedia.title : bMedia.englishTitle);
      if (normKey.isNotEmpty && unifiedMap.containsKey(normKey)) {
        // Already exists -> Merge higher quality cover or metadata if available
        final existing = unifiedMap[normKey]!;
        if (existing.coverImage.isEmpty && bMedia.coverImage.isNotEmpty) {
          unifiedMap[normKey] = AnilistMedia(
            id: existing.id > 0 ? existing.id : bMedia.id,
            title: existing.title.isNotEmpty ? existing.title : bMedia.title,
            englishTitle: existing.englishTitle.isNotEmpty ? existing.englishTitle : bMedia.englishTitle,
            coverImage: bMedia.coverImage,
            bannerImage: existing.bannerImage ?? bMedia.bannerImage,
            description: existing.description ?? bMedia.description,
            episodes: existing.episodes ?? bMedia.episodes,
            genres: existing.genres.isNotEmpty ? existing.genres : bMedia.genres,
            averageScore: existing.averageScore ?? bMedia.averageScore,
            status: existing.status ?? bMedia.status,
            format: existing.format ?? bMedia.format,
            countryOfOrigin: existing.countryOfOrigin ?? bMedia.countryOfOrigin,
            type: 'ANIME',
          );
        }
        continue;
      }

      // Unique title only found in Miruro / backend (e.g. Pokémon variations) -> add as unified card!
      if (normKey.isNotEmpty) {
        unifiedMap[normKey] = bMedia;
        if (bMedia.id > 0) seenIds.add(bMedia.id);
      }
    }

    return unifiedMap.values.toList();
  }

  /// Internal search against Shikai / Anivexa / Miruro catalog
  static Future<List<AnilistMedia>> _searchBackendSources(String query) async {
    final List<AnilistMedia> items = [];
    try {
      final res = await http.get(
        Uri.parse('$shikaiBaseUrl/api/anivexa/search?query=${Uri.encodeComponent(query)}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(milliseconds: 2500));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data is List) ? data : (data['results'] ?? data['data'] ?? []);
        if (list is List) {
          for (final raw in list) {
            if (raw is Map<String, dynamic>) {
              items.add(AnilistMedia.fromJson(raw));
            }
          }
        }
      }
    } catch (_) {}
    return items;
  }
}
