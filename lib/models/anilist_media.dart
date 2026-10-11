class AnilistMedia {
  final int id;
  final String title;
  final String englishTitle;
  final String? bannerImage;
  final String coverImage;
  final String? description;
  final int? episodes;
  final int? chapters;
  final List<String> genres;
  final int? averageScore;
  final String? status;
  final String? format;
  final String? countryOfOrigin; // 'JP', 'KR', 'CN'
  final String type; // 'ANIME' or 'MANGA'
  final String? sourceUrl;
  final String? sourceId;
  final String? sourceName;

  AnilistMedia({
    required this.id,
    required this.title,
    required this.englishTitle,
    this.bannerImage,
    required this.coverImage,
    this.description,
    this.episodes,
    this.chapters,
    required this.genres,
    this.averageScore,
    this.status,
    this.format,
    this.countryOfOrigin,
    this.type = 'ANIME',
    this.sourceUrl,
    this.sourceId,
    this.sourceName,
  });

  String get displayTitle {
    if (englishTitle.isNotEmpty) return englishTitle;
    return title;
  }

  bool get isManga => type == 'MANGA' || format == 'MANGA' || format == 'ONE_SHOT' || format == 'NOVEL' || format == 'MANHWA' || format == 'MANHUA';
  bool get isManhwa => countryOfOrigin == 'KR' || format == 'MANHWA';
  bool get isManhua => countryOfOrigin == 'CN' || format == 'MANHUA';
  bool get isJapaneseManga => countryOfOrigin == 'JP' || (isManga && !isManhwa && !isManhua);

  String get categoryLabel {
    if (isManhwa) return 'Manhwa';
    if (isManhua) return 'Manhua';
    return 'Manga';
  }

  String get originFlag {
    if (isManhwa) return '🇰🇷';
    if (isManhua) return '🇨🇳';
    return '🇯🇵';
  }

  factory AnilistMedia.fromComickSearchResult(
    Map<String, dynamic> json, {
    String? source,
    String? category,
  }) {
    final title = (json['title'] ?? '').toString();
    final url = (json['url'] ?? '').toString();
    var cover = (json['coverImage'] ?? '').toString();
    if (cover.contains('iweb_') && cover.startsWith('https://')) {
      cover = cover.replaceFirst('https://', 'http://');
    }

    final latestChapter = json['latestChapter'];
    int? chapters;
    if (latestChapter is num) {
      chapters = latestChapter.toInt();
    } else if (latestChapter is String) {
      chapters = int.tryParse(latestChapter);
    }

    String country = 'JP';
    final catLower = (category ?? '').toLowerCase();
    if (catLower == 'manhwa') {
      country = 'KR';
    } else if (catLower == 'manhua') {
      country = 'CN';
    } else if (source != null) {
      final s = source.toLowerCase();
      if (s.contains('asura') || s.contains('flame') || s.contains('webtoon') || s.contains('raven') || s.contains('lagoon')) {
        country = 'KR';
      } else if (s.contains('manhua') || s.contains('spider') || s.contains('yaksha')) {
        country = 'CN';
      }
    }

    final id = (url.isNotEmpty ? url.hashCode : title.hashCode).abs();

    return AnilistMedia(
      id: id,
      title: title,
      englishTitle: title,
      coverImage: cover,
      bannerImage: cover.isNotEmpty ? cover : null,
      description: json['lastUpdated'] != null && json['lastUpdated'].toString().isNotEmpty
          ? 'Source: ${source ?? "Comick"} • Last updated: ${json['lastUpdated']}'
          : 'Source: ${source ?? "Comick"}',
      chapters: chapters,
      genres: [if (source != null) source, if (category != null) category],
      averageScore: json['rating'] is num ? ((json['rating'] as num) * 10).toInt() : null,
      status: 'RELEASING',
      format: country == 'KR' ? 'MANHWA' : (country == 'CN' ? 'MANHUA' : 'MANGA'),
      countryOfOrigin: country,
      type: 'MANGA',
      sourceUrl: url,
      sourceId: source,
      sourceName: json['source']?.toString() ?? source,
    );
  }

  factory AnilistMedia.fromJson(Map<String, dynamic> json) {
    String romaji = '';
    String english = '';

    final rawTitle = json['title'] ?? json['name'];
    if (rawTitle is Map) {
      romaji = (rawTitle['romaji'] ?? rawTitle['userPreferred'] ?? rawTitle['native'] ?? '').toString();
      english = (rawTitle['english'] ?? '').toString();
    } else if (rawTitle is String) {
      romaji = rawTitle;
      english = rawTitle;
    }

    if (romaji.isEmpty && english.isNotEmpty) romaji = english;
    if (english.isEmpty && romaji.isNotEmpty) english = romaji;

    String cover = '';
    final rawCover = json['coverImage'] ?? json['image'] ?? json['poster'] ?? json['cover'] ?? json['thumbnail'];
    if (rawCover is Map) {
      cover = (rawCover['extraLarge'] ?? rawCover['large'] ?? rawCover['medium'] ?? rawCover['default'] ?? '').toString();
    } else if (rawCover is String) {
      cover = rawCover;
    }

    if (cover.startsWith('//')) {
      cover = 'https:$cover';
    } else if (cover.startsWith('http://') && !cover.contains('iweb_')) {
      cover = cover.replaceFirst('http://', 'https://');
    }

    String? banner;
    final rawBanner = json['bannerImage'] ?? json['banner'];
    if (rawBanner is String && rawBanner.isNotEmpty) {
      banner = rawBanner.startsWith('//') ? 'https:$rawBanner' : rawBanner;
      if (banner.startsWith('http://') && !banner.contains('iweb_')) {
        banner = banner.replaceFirst('http://', 'https://');
      }
    }
    banner ??= cover.isNotEmpty ? cover : null;

    // Strip HTML tags from description if present
    String? desc = json['description']?.toString();
    if (desc != null) {
      desc = desc.replaceAll(RegExp(r'<[^>]*>'), '');
    }

    int? parsedEpisodes;
    final rawEps = json['episodes'] ?? json['totalEpisodes'];
    if (rawEps is num) {
      parsedEpisodes = rawEps.toInt();
    } else if (rawEps is String) {
      parsedEpisodes = int.tryParse(rawEps);
    }

    return AnilistMedia(
      id: json['id'] is num ? (json['id'] as num).toInt() : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      title: romaji,
      englishTitle: english,
      bannerImage: banner,
      coverImage: cover,
      description: desc,
      episodes: parsedEpisodes,
      chapters: json['chapters'] is num ? (json['chapters'] as num).toInt() : null,
      genres: (json['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      averageScore: json['averageScore'] is num ? (json['averageScore'] as num).toInt() : null,
      status: json['status']?.toString(),
      format: json['format']?.toString(),
      countryOfOrigin: json['countryOfOrigin']?.toString(),
      type: json['type']?.toString() ?? 'ANIME',
      sourceUrl: json['sourceUrl']?.toString(),
      sourceId: json['sourceId']?.toString(),
      sourceName: json['sourceName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': {
      'romaji': title,
      'english': englishTitle,
    },
    'bannerImage': bannerImage,
    'coverImage': {
      'extraLarge': coverImage,
    },
    'description': description,
    'episodes': episodes,
    'chapters': chapters,
    'genres': genres,
    'averageScore': averageScore,
    'status': status,
    'format': format,
    'countryOfOrigin': countryOfOrigin,
    'type': type,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (sourceId != null) 'sourceId': sourceId,
    if (sourceName != null) 'sourceName': sourceName,
  };
}
