import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';

enum FranchiseCategory {
  seasons,
  movies,
  related,
  manga,
}

class FranchiseItem {
  final int id;
  final String title;
  final String englishTitle;
  final String shortTitle;
  final String seasonTag;      // "S1", "S2", "Final P1", "Movie 1", "OVA"
  final String seasonLabel;    // "Season 1", "Mugen Train Arc", "The Final Season"
  final String? format;        // 'TV', 'MOVIE', 'OVA', etc.
  final String? status;
  final int? episodes;
  final int? seasonYear;
  final int? releaseYear;
  final String coverImage;
  final String? bannerImage;
  final int? averageScore;
  final String relationType;
  final bool isCurrent;
  final bool isManga;
  final AnilistMedia rawMedia;

  const FranchiseItem({
    required this.id,
    required this.title,
    required this.englishTitle,
    required this.shortTitle,
    required this.seasonTag,
    required this.seasonLabel,
    this.format,
    this.status,
    this.episodes,
    this.seasonYear,
    this.releaseYear,
    required this.coverImage,
    this.bannerImage,
    this.averageScore,
    required this.relationType,
    required this.isCurrent,
    required this.isManga,
    required this.rawMedia,
  });

  String get displayTitle {
    if (englishTitle.isNotEmpty) return englishTitle;
    return title;
  }

  Color get tagColor {
    if (isCurrent) return const Color(0xFFE50914); // Shikai Crimson
    if (seasonTag.startsWith('S') || seasonTag.startsWith('Final') || seasonTag.startsWith('Part')) {
      return const Color(0xFF10B981); // Emerald Green
    }
    if (seasonTag.contains('Movie') || format == 'MOVIE') {
      return const Color(0xFFF59E0B); // Amber / Gold
    }
    if (seasonTag.contains('TYBW') || seasonTag.contains('Arc')) {
      return const Color(0xFF8B5CF6); // Purple
    }
    if (isManga) {
      return const Color(0xFFEC4899); // Rose Pink
    }
    return const Color(0xFF0EA5E9);   // Sky Blue
  }

  IconData get tagIcon {
    if (isCurrent) return Icons.play_circle_fill_rounded;
    if (seasonTag.contains('Movie') || format == 'MOVIE') return Icons.movie_rounded;
    if (isManga) return Icons.menu_book_rounded;
    if (seasonTag.startsWith('S') || seasonTag.startsWith('Final')) return Icons.tv_rounded;
    return Icons.auto_awesome_rounded;
  }
}

class FranchiseData {
  final List<FranchiseItem> seasons;
  final List<FranchiseItem> movies;
  final List<FranchiseItem> related;
  final List<FranchiseItem> sourceManga;

  const FranchiseData({
    required this.seasons,
    required this.movies,
    required this.related,
    required this.sourceManga,
  });

  bool get isEmpty => seasons.isEmpty && movies.isEmpty && related.isEmpty && sourceManga.isEmpty;
  int get totalCount => seasons.length + movies.length + related.length + sourceManga.length;

  List<FranchiseItem> itemsForCategory(FranchiseCategory category) {
    switch (category) {
      case FranchiseCategory.seasons:
        return seasons;
      case FranchiseCategory.movies:
        return movies;
      case FranchiseCategory.related:
        return related;
      case FranchiseCategory.manga:
        return sourceManga;
    }
  }

  List<FranchiseCategory> get availableCategories {
    final list = <FranchiseCategory>[];
    if (seasons.isNotEmpty) list.add(FranchiseCategory.seasons);
    if (movies.isNotEmpty) list.add(FranchiseCategory.movies);
    if (related.isNotEmpty) list.add(FranchiseCategory.related);
    if (sourceManga.isNotEmpty) list.add(FranchiseCategory.manga);
    return list;
  }

  String categoryLabel(FranchiseCategory cat) {
    switch (cat) {
      case FranchiseCategory.seasons:
        return 'Seasons';
      case FranchiseCategory.movies:
        return 'Movies';
      case FranchiseCategory.related:
        return 'OVAs & Specials';
      case FranchiseCategory.manga:
        return 'Manga';
    }
  }
}
