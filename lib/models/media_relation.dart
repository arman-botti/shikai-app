import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';

enum RelationType {
  prequel,
  sequel,
  parent,
  sideStory,
  spinOff,
  alternative,
  summary,
  adaptation,
  other,
}

class MediaRelation {
  final int id;
  final String rawRelationType;
  final RelationType relationType;
  final AnilistMedia media;

  MediaRelation({
    required this.id,
    required this.rawRelationType,
    required this.relationType,
    required this.media,
  });

  factory MediaRelation.fromJson(Map<String, dynamic> json) {
    final rawType = (json['relationType'] ?? 'OTHER').toString();
    final node = json['node'] as Map<String, dynamic>? ?? {};

    return MediaRelation(
      id: json['id'] is num
          ? (json['id'] as num).toInt()
          : (node['id'] is num ? (node['id'] as num).toInt() : 0),
      rawRelationType: rawType,
      relationType: _parseRelationType(rawType),
      media: AnilistMedia.fromJson(node),
    );
  }

  static RelationType _parseRelationType(String raw) {
    switch (raw.toUpperCase()) {
      case 'PREQUEL':
        return RelationType.prequel;
      case 'SEQUEL':
        return RelationType.sequel;
      case 'PARENT':
        return RelationType.parent;
      case 'SIDE_STORY':
        return RelationType.sideStory;
      case 'SPIN_OFF':
        return RelationType.spinOff;
      case 'ALTERNATIVE':
        return RelationType.alternative;
      case 'SUMMARY':
        return RelationType.summary;
      case 'ADAPTATION':
      case 'SOURCE':
        return RelationType.adaptation;
      default:
        return RelationType.other;
    }
  }

  bool get isAnime => media.type == 'ANIME' && media.format != 'MANGA' && media.format != 'NOVEL' && media.format != 'ONE_SHOT';
  bool get isManga => media.type == 'MANGA' || media.format == 'MANGA' || media.format == 'NOVEL' || media.format == 'ONE_SHOT';

  String get smartDisplayTag {
    final title = (media.englishTitle.isNotEmpty ? media.englishTitle : media.title).toLowerCase();

    // Check title for explicit season numbers
    if (title.contains('final season')) {
      return 'FINAL SEASON';
    } else if (title.contains('season 4') || title.contains('4th season')) {
      return 'SEASON 4';
    } else if (title.contains('season 3') || title.contains('3rd season')) {
      return 'SEASON 3';
    } else if (title.contains('season 2') || title.contains('2nd season')) {
      return 'SEASON 2';
    } else if (title.contains('part 2') || title.contains('part ii') || title.contains('cour 2')) {
      return 'PART 2';
    } else if (title.contains('part 3') || title.contains('part iii') || title.contains('cour 3')) {
      return 'PART 3';
    }

    // Fall back to relation type with clear watch order wording
    switch (relationType) {
      case RelationType.prequel:
        return '◀ PREV SEASON';
      case RelationType.sequel:
        return 'NEXT SEASON ▶';
      case RelationType.parent:
        return 'MAIN STORY';
      case RelationType.sideStory:
        return media.format == 'MOVIE' ? '🎬 MOVIE' : 'SIDE STORY';
      case RelationType.spinOff:
        return '⚡ SPIN-OFF';
      case RelationType.alternative:
        return 'ALT VERSION';
      case RelationType.adaptation:
        return 'ORIGINAL MANGA';
      case RelationType.summary:
        return 'RECAP';
      default:
        return media.format == 'MOVIE' ? '🎬 MOVIE' : rawRelationType.replaceAll('_', ' ');
    }
  }

  String get displayTag => smartDisplayTag;

  Color get smartTagColor {
    final tag = smartDisplayTag;
    if (tag.contains('NEXT') || tag.contains('SEASON 2') || tag.contains('SEASON 3') || tag.contains('SEASON 4') || tag.contains('FINAL')) {
      return const Color(0xFF10B981); // Emerald Green
    }
    if (tag.contains('PREV')) {
      return const Color(0xFF0EA5E9); // Sky Blue
    }
    if (tag.contains('MOVIE')) {
      return const Color(0xFFF59E0B); // Amber
    }
    if (tag.contains('SPIN-OFF')) {
      return const Color(0xFFEC4899); // Rose Pink
    }
    return tagColor;
  }

  Color get tagColor {
    switch (relationType) {
      case RelationType.sequel:
        return const Color(0xFF10B981); // Emerald Green
      case RelationType.prequel:
        return const Color(0xFF0EA5E9); // Sky Blue
      case RelationType.parent:
        return const Color(0xFF6366F1); // Indigo
      case RelationType.sideStory:
        return const Color(0xFFF59E0B); // Amber / Gold
      case RelationType.spinOff:
        return const Color(0xFFEC4899); // Rose Pink
      case RelationType.alternative:
        return const Color(0xFFA855F7); // Violet
      case RelationType.adaptation:
        return const Color(0xFFE50914); // Shikai Crimson Red
      case RelationType.summary:
        return const Color(0xFF71717A); // Gray / Zinc
      default:
        return const Color(0xFF71717A);
    }
  }

  IconData get tagIcon {
    final tag = smartDisplayTag;
    if (tag.contains('PREV')) return Icons.fast_rewind_rounded;
    if (tag.contains('NEXT') || tag.contains('SEASON') || tag.contains('FINAL')) return Icons.fast_forward_rounded;
    if (tag.contains('MOVIE')) return Icons.movie_rounded;
    if (tag.contains('SPIN-OFF')) return Icons.alt_route_rounded;

    switch (relationType) {
      case RelationType.sequel:
        return Icons.fast_forward_rounded;
      case RelationType.prequel:
        return Icons.fast_rewind_rounded;
      case RelationType.parent:
        return Icons.auto_stories_rounded;
      case RelationType.sideStory:
        return Icons.movie_rounded;
      case RelationType.spinOff:
        return Icons.alt_route_rounded;
      case RelationType.alternative:
        return Icons.shuffle_rounded;
      case RelationType.adaptation:
        return Icons.menu_book_rounded;
      case RelationType.summary:
        return Icons.summarize_rounded;
      default:
        return Icons.hub_rounded;
    }
  }

  int get watchOrderPriority {
    // 1. Prequels (earlier seasons) come first: 0
    if (relationType == RelationType.prequel) return 0;
    // 2. Sequels (next seasons) come second: 1
    if (relationType == RelationType.sequel) return 1;
    // 3. Main/Parent story: 2
    if (relationType == RelationType.parent) return 2;
    // 4. Movies: 3
    if (media.format == 'MOVIE') return 3;
    // 5. OVAs / Specials: 4
    if (media.format == 'OVA' || media.format == 'SPECIAL') return 4;
    // 6. Side story: 5
    if (relationType == RelationType.sideStory) return 5;
    // 7. Spin-off: 6
    if (relationType == RelationType.spinOff) return 6;
    // 8. Manga adaptation: 10 (at the end)
    if (isManga) return 10;
    return 7;
  }

  int get priority => watchOrderPriority;
}
