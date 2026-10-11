class AnivexaEpisode {
  final int number;
  final String title;
  final String? image;
  final String? description;
  final String? airDate;
  final int? duration;
  final String audio;
  final String watchId;

  AnivexaEpisode({
    required this.number,
    required this.title,
    this.image,
    this.description,
    this.airDate,
    this.duration,
    required this.audio,
    required this.watchId,
  });

  factory AnivexaEpisode.fromJson(Map<String, dynamic> json) {
    int parsedNumber = 1;
    final rawNumber = json['number'] ?? json['episode'] ?? json['ep'];
    if (rawNumber is num) {
      parsedNumber = rawNumber.toInt();
    } else if (rawNumber is String) {
      parsedNumber = int.tryParse(rawNumber) ?? (double.tryParse(rawNumber)?.toInt() ?? 1);
    }

    String parsedTitle = (json['title'] ?? '').toString().trim();
    if (parsedTitle.isEmpty || parsedTitle.contains(r'$') || parsedTitle.contains('{')) {
      parsedTitle = 'Episode $parsedNumber';
    }

    String? desc = json['description']?.toString().trim();
    if (desc != null && (desc.contains(r'$') || desc.contains('{'))) {
      desc = null;
    }

    return AnivexaEpisode(
      number: parsedNumber,
      title: parsedTitle,
      image: json['image']?.toString(),
      description: desc,
      airDate: json['airDate']?.toString(),
      duration: json['duration'] is num ? (json['duration'] as num).toInt() : null,
      audio: json['audio']?.toString() ?? 'sub',
      watchId: json['id']?.toString() ?? '',
    );
  }
}
