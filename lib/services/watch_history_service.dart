import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryItem {
  final int anilistId;
  final String title;
  final String coverImage;
  final int episodeNumber;
  final int positionSeconds;
  final int durationSeconds;
  final String audio;
  final int updatedAt; // timestamp in millis

  WatchHistoryItem({
    required this.anilistId,
    required this.title,
    required this.coverImage,
    required this.episodeNumber,
    required this.positionSeconds,
    required this.durationSeconds,
    this.audio = 'sub',
    required this.updatedAt,
  });

  double get progressPercentage {
    if (durationSeconds <= 0) return 0.0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'anilistId': anilistId,
    'title': title,
    'coverImage': coverImage,
    'episodeNumber': episodeNumber,
    'positionSeconds': positionSeconds,
    'durationSeconds': durationSeconds,
    'audio': audio,
    'updatedAt': updatedAt,
  };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) => WatchHistoryItem(
    anilistId: json['anilistId'] ?? 0,
    title: json['title'] ?? '',
    coverImage: json['coverImage'] ?? '',
    episodeNumber: json['episodeNumber'] ?? 1,
    positionSeconds: json['positionSeconds'] ?? 0,
    durationSeconds: json['durationSeconds'] ?? 0,
    audio: json['audio'] ?? 'sub',
    updatedAt: json['updatedAt'] ?? 0,
  );
}

class WatchHistoryService {
  static const String _historyKey = 'shikai_watch_history_v1';
  static const String _watchedEpisodesKey = 'shikai_watched_episodes_v1';
  static const String _watchlistKey = 'shikai_watchlist_v1';

  /// Save or update user playback position for an episode
  static Future<void> saveProgress({
    required int anilistId,
    required String title,
    required String coverImage,
    required int episodeNumber,
    required int positionSeconds,
    required int durationSeconds,
    String audio = 'sub',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyList = await getContinueWatching();

      // Remove existing item for this anime if present
      historyList.removeWhere((item) => item.anilistId == anilistId);

      // Insert fresh item at top
      final newItem = WatchHistoryItem(
        anilistId: anilistId,
        title: title,
        coverImage: coverImage,
        episodeNumber: episodeNumber,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        audio: audio,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      historyList.insert(0, newItem);

      // Keep up to 30 items
      if (historyList.length > 30) {
        historyList.removeRange(30, historyList.length);
      }

      final encoded = jsonEncode(historyList.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);

      // Mark episode as watched if past 60s or 50%
      if (positionSeconds > 60) {
        await markEpisodeWatched(anilistId, episodeNumber);
      }
    } catch (_) {}
  }

  /// Get list of continue watching items sorted by most recently watched
  static Future<List<WatchHistoryItem>> getContinueWatching() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return [];

      final List decoded = jsonDecode(raw);
      return decoded.map((e) => WatchHistoryItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Mark an episode as watched
  static Future<void> markEpisodeWatched(int anilistId, int episodeNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_watchedEpisodesKey}_$anilistId';
      final list = prefs.getStringList(key) ?? [];
      final epStr = episodeNumber.toString();
      if (!list.contains(epStr)) {
        list.add(epStr);
        await prefs.setStringList(key, list);
      }
    } catch (_) {}
  }

  /// Unmark an episode as watched
  static Future<void> unmarkEpisodeWatched(int anilistId, int episodeNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_watchedEpisodesKey}_$anilistId';
      final list = prefs.getStringList(key) ?? [];
      final epStr = episodeNumber.toString();
      if (list.contains(epStr)) {
        list.remove(epStr);
        await prefs.setStringList(key, list);
      }
    } catch (_) {}
  }

  /// Toggle episode watched status
  static Future<bool> toggleEpisodeWatched(int anilistId, int episodeNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_watchedEpisodesKey}_$anilistId';
      final list = prefs.getStringList(key) ?? [];
      final epStr = episodeNumber.toString();
      final isNowWatched = !list.contains(epStr);
      if (isNowWatched) {
        list.add(epStr);
      } else {
        list.remove(epStr);
      }
      await prefs.setStringList(key, list);
      return isNowWatched;
    } catch (_) {
      return false;
    }
  }

  /// Check if a specific episode is already watched
  static Future<bool> isEpisodeWatched(int anilistId, int episodeNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_watchedEpisodesKey}_$anilistId';
      final list = prefs.getStringList(key) ?? [];
      return list.contains(episodeNumber.toString());
    } catch (_) {
      return false;
    }
  }

  /// Get set of all watched episode numbers for an anime
  static Future<Set<int>> getWatchedEpisodeNumbers(int anilistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_watchedEpisodesKey}_$anilistId';
      final list = prefs.getStringList(key) ?? [];
      return list.map((e) => int.tryParse(e) ?? 0).where((e) => e > 0).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Watchlist / Favorites Management
  static Future<void> toggleWatchlist(Map<String, dynamic> animeJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_watchlistKey);
      List list = raw != null ? jsonDecode(raw) : [];

      final id = animeJson['id'];
      final exists = list.any((item) => item['id'] == id);

      if (exists) {
        list.removeWhere((item) => item['id'] == id);
      } else {
        list.insert(0, animeJson);
      }

      await prefs.setString(_watchlistKey, jsonEncode(list));
    } catch (_) {}
  }

  static Future<bool> isInWatchlist(int anilistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_watchlistKey);
      if (raw == null) return false;
      List list = jsonDecode(raw);
      return list.any((item) => item['id'] == anilistId);
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getWatchlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_watchlistKey);
      if (raw == null) return [];
      final List list = jsonDecode(raw);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Remove a specific anime from history
  static Future<void> remove(int anilistId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyList = await getContinueWatching();
      historyList.removeWhere((item) => item.anilistId == anilistId);
      final encoded = jsonEncode(historyList.map((e) => e.toJson()).toList());
      await prefs.setString(_historyKey, encoded);
    } catch (_) {}
  }

  /// Clear all history
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      await prefs.remove(_watchlistKey);
    } catch (_) {}
  }
}
