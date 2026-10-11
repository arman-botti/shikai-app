import 'package:shikai_app/models/anilist_media.dart';

class AiringScheduleItem {
  final int id;
  final int airingAt; // Epoch timestamp in seconds
  final int episode;
  final int timeUntilAiring;
  final AnilistMedia media;

  AiringScheduleItem({
    required this.id,
    required this.airingAt,
    required this.episode,
    required this.timeUntilAiring,
    required this.media,
  });

  factory AiringScheduleItem.fromJson(Map<String, dynamic> json) {
    return AiringScheduleItem(
      id: json['id'] ?? 0,
      airingAt: json['airingAt'] ?? 0,
      episode: json['episode'] ?? 1,
      timeUntilAiring: json['timeUntilAiring'] ?? 0,
      media: AnilistMedia.fromJson(json['media'] ?? {}),
    );
  }

  String get countdownText {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = airingAt - nowSec;

    if (diff <= 0) {
      final pastMin = (-diff) ~/ 60;
      if (pastMin < 60) return "Aired ${pastMin}m ago";
      final pastHours = pastMin ~/ 60;
      if (pastHours < 24) return "Aired ${pastHours}h ago";
      return "Recently Aired";
    }

    final min = diff ~/ 60;
    final hours = min ~/ 60;
    final days = hours ~/ 24;

    if (days > 0) return "In ${days}d ${hours % 24}h";
    if (hours > 0) return "In ${hours}h ${min % 60}m";
    return "In ${min}m";
  }

  String get airingTimeFormatted {
    final dt = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }
}
