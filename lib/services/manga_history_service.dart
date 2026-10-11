import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MangaHistoryItem {
  final int anilistId;
  final String title;
  final String coverImage;
  final String chapterId;
  final String chapterNumber;
  final int pageIndex;
  final int totalPages;
  final DateTime updatedAt;

  MangaHistoryItem({
    required this.anilistId,
    required this.title,
    required this.coverImage,
    required this.chapterId,
    required this.chapterNumber,
    required this.pageIndex,
    required this.totalPages,
    required this.updatedAt,
  });

  double get progressPercentage {
    if (totalPages <= 0) return 0.0;
    return ((pageIndex + 1) / totalPages).clamp(0.0, 1.0);
  }

  factory MangaHistoryItem.fromJson(Map<String, dynamic> json) {
    return MangaHistoryItem(
      anilistId: json['anilistId'] ?? 0,
      title: json['title'] ?? '',
      coverImage: json['coverImage'] ?? '',
      chapterId: json['chapterId'] ?? '',
      chapterNumber: json['chapterNumber'] ?? '1',
      pageIndex: json['pageIndex'] ?? 0,
      totalPages: json['totalPages'] ?? 1,
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'anilistId': anilistId,
    'title': title,
    'coverImage': coverImage,
    'chapterId': chapterId,
    'chapterNumber': chapterNumber,
    'pageIndex': pageIndex,
    'totalPages': totalPages,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class MangaHistoryService {
  static const String _keyHistory = 'shikai_manga_reading_history';
  static const String _keyBookmarks = 'shikai_manga_bookmarks';

  static Future<void> saveReadingProgress({
    required int anilistId,
    required String title,
    required String coverImage,
    required String chapterId,
    required String chapterNumber,
    required int pageIndex,
    required int totalPages,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getContinueReading();

    // Remove existing entry for same manga
    items.removeWhere((item) => item.anilistId == anilistId);

    // Insert updated at top
    items.insert(
      0,
      MangaHistoryItem(
        anilistId: anilistId,
        title: title,
        coverImage: coverImage,
        chapterId: chapterId,
        chapterNumber: chapterNumber,
        pageIndex: pageIndex,
        totalPages: totalPages,
        updatedAt: DateTime.now(),
      ),
    );

    // Limit to 30 items
    final trimmed = items.take(30).toList();
    final jsonList = trimmed.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyHistory, jsonList);
  }

  static Future<List<MangaHistoryItem>> getContinueReading() async {
    final prefs = await SharedPreferences.getInstance();
    final stringList = prefs.getStringList(_keyHistory) ?? [];
    final List<MangaHistoryItem> items = [];

    for (var s in stringList) {
      try {
        items.add(MangaHistoryItem.fromJson(jsonDecode(s)));
      } catch (_) {}
    }
    return items;
  }

  static Future<MangaHistoryItem?> getProgressForManga(int anilistId) async {
    final items = await getContinueReading();
    final match = items.where((i) => i.anilistId == anilistId);
    return match.isNotEmpty ? match.first : null;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }

  // Bookmarks
  static Future<bool> isBookmarked(int anilistId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBookmarks) ?? [];
    return list.contains(anilistId.toString());
  }

  static Future<bool> toggleBookmark(int anilistId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBookmarks) ?? [];
    final idStr = anilistId.toString();
    bool nowBookmarked = false;
    if (list.contains(idStr)) {
      list.remove(idStr);
      nowBookmarked = false;
    } else {
      list.add(idStr);
      nowBookmarked = true;
    }
    await prefs.setStringList(_keyBookmarks, list);
    return nowBookmarked;
  }
}
