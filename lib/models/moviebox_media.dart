/// ---------------------------------------------------------------------------
/// MOVIEBOX CONTENT MODELS
/// Metadata scraped directly from MovieBox by the on-device API engine.
/// ---------------------------------------------------------------------------

class MovieboxItem {
  final String id;
  final String title;
  final int subjectType; // 1 = Movie, 2 = Series
  final String? cover;
  final String? backdrop;
  final String? year;
  final double? rating;
  final String? genre;
  final String? description;
  final String? detailPath;
  final String? corner;

  const MovieboxItem({
    required this.id,
    required this.title,
    required this.subjectType,
    this.cover,
    this.backdrop,
    this.year,
    this.rating,
    this.genre,
    this.description,
    this.detailPath,
    this.corner,
  });

  bool get isSeries => subjectType != 1;

  factory MovieboxItem.fromJson(Map<String, dynamic> json) {
    final sub = (json['subject'] is Map)
        ? Map<String, dynamic>.from(json['subject'] as Map)
        : json;

    String? coverUrl;
    final coverRaw = sub['cover'];
    if (coverRaw is Map) {
      coverUrl = coverRaw['url']?.toString();
    } else if (coverRaw is String) {
      coverUrl = coverRaw;
    }

    String? backdropUrl;
    final imageRaw = json['image'];
    if (imageRaw is Map) {
      backdropUrl = imageRaw['url']?.toString();
    }

    final rawRating = sub['imdbRatingValue'];
    double? rating;
    if (rawRating is num) {
      rating = rawRating.toDouble();
    } else if (rawRating != null) {
      rating = double.tryParse(rawRating.toString());
    }

    final release = sub['releaseDate']?.toString();
    String? year;
    if (release != null && release.length >= 4) {
      year = release.substring(0, 4);
    }

    return MovieboxItem(
      id: (sub['subjectId'] ?? json['subjectId'] ?? '').toString(),
      title: (sub['title'] ?? json['title'] ?? 'Untitled').toString(),
      subjectType: int.tryParse((sub['subjectType'] ?? json['subjectType'] ?? 1).toString()) ?? 1,
      cover: coverUrl,
      backdrop: backdropUrl,
      year: year,
      rating: rating,
      genre: sub['genre']?.toString(),
      description: sub['description']?.toString(),
      detailPath: (sub['detailPath'] ?? json['detailPath'])?.toString(),
      corner: (sub['corner'] ?? json['corner'])?.toString(),
    );
  }
}

class MovieboxDub {
  final String id;
  final String name;

  const MovieboxDub({required this.id, required this.name});

  factory MovieboxDub.fromJson(Map<String, dynamic> json) {
    return MovieboxDub(
      id: (json['subjectId'] ?? json['subject_id'] ?? '').toString(),
      name: (json['lanName'] ?? json['lang_name'] ?? 'Audio').toString(),
    );
  }
}

class MovieboxDetail {
  final String id;
  final String title;
  final int subjectType;
  final String? description;
  final String? releaseDate;
  final String? duration;
  final double? rating;
  final String? genre;
  final String? country;
  final String? language;
  final String? cover;
  final String? detailPath;
  final List<MovieboxDub> dubs;

  const MovieboxDetail({
    required this.id,
    required this.title,
    required this.subjectType,
    this.description,
    this.releaseDate,
    this.duration,
    this.rating,
    this.genre,
    this.country,
    this.language,
    this.cover,
    this.detailPath,
    this.dubs = const [],
  });

  bool get isSeries => subjectType != 1;

  String? get year {
    final r = releaseDate;
    if (r == null || r.length < 4) return null;
    return r.substring(0, 4);
  }

  factory MovieboxDetail.fromJson(Map<String, dynamic> json) {
    final rawPath = json['detailPath']?.toString();
    final detailUrl = json['detailUrl']?.toString() ?? '';
    String detailPath = rawPath ?? '';
    if (detailPath.isEmpty && detailUrl.isNotEmpty) {
      final uri = Uri.tryParse(detailUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        detailPath = uri.pathSegments.last;
      } else {
        detailPath = detailUrl.split('/').last;
      }
    }

    String? coverUrl;
    final coverRaw = json['cover'];
    if (coverRaw is Map) {
      coverUrl = coverRaw['url']?.toString();
    } else if (coverRaw is String) {
      coverUrl = coverRaw;
    }

    final rawRating = json['imdbRatingValue'];
    double? rating;
    if (rawRating is num) {
      rating = rawRating.toDouble();
    } else if (rawRating != null) {
      rating = double.tryParse(rawRating.toString());
    }

    final rawDubs = json['dubs'];
    final dubs = <MovieboxDub>[];
    if (rawDubs is List) {
      for (final d in rawDubs) {
        if (d is Map) dubs.add(MovieboxDub.fromJson(Map<String, dynamic>.from(d)));
      }
    }

    return MovieboxDetail(
      id: (json['subjectId'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      subjectType: int.tryParse((json['subjectType'] ?? 1).toString()) ?? 1,
      description: json['description']?.toString(),
      releaseDate: json['releaseDate']?.toString(),
      duration: json['duration']?.toString(),
      rating: rating,
      genre: json['genre']?.toString(),
      country: json['countryName']?.toString(),
      language: json['language']?.toString(),
      cover: coverUrl,
      detailPath: detailPath.isEmpty ? null : detailPath,
      dubs: dubs,
    );
  }
}

class MovieboxSeason {
  final int season;
  final int episodeCount;

  const MovieboxSeason({required this.season, required this.episodeCount});

  factory MovieboxSeason.fromJson(Map<String, dynamic> json) {
    return MovieboxSeason(
      season: int.tryParse((json['se'] ?? json['season'] ?? 1).toString()) ?? 1,
      episodeCount: int.tryParse((json['maxEp'] ?? json['episode_count'] ?? 1).toString()) ?? 1,
    );
  }
}

class MovieboxStream {
  final String url;
  final String quality;
  final int qualityValue;
  final String format;
  final double sizeMb;
  final int? durationSec;
  final String? codec;
  final Map<String, String> headers;
  final String source;

  const MovieboxStream({
    required this.url,
    required this.quality,
    required this.qualityValue,
    required this.format,
    required this.sizeMb,
    this.durationSec,
    this.codec,
    this.headers = const {},
    this.source = '',
  });

  bool get isDash => format.toUpperCase() == 'DASH' || url.toLowerCase().contains('.mpd');
  bool get isMp4 => !isDash;

  factory MovieboxStream.fromJson(Map<String, dynamic> json, {String source = ''}) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
    }

    return MovieboxStream(
      url: (json['url'] ?? '').toString(),
      quality: (json['quality'] ?? 'Auto').toString(),
      qualityValue: int.tryParse((json['quality_value'] ?? 0).toString()) ?? 0,
      format: (json['format'] ?? 'MP4').toString(),
      sizeMb: (json['size_mb'] is num) ? (json['size_mb'] as num).toDouble() : 0,
      durationSec: int.tryParse((json['duration_sec'] ?? '').toString()),
      codec: json['codec']?.toString(),
      headers: headers,
      source: source.isNotEmpty ? source : (json['source'] ?? '').toString(),
    );
  }
}

class MovieboxCaption {
  final String language;
  final String code;
  final String url;

  const MovieboxCaption({required this.language, required this.code, required this.url});

  factory MovieboxCaption.fromJson(Map<String, dynamic> json) {
    return MovieboxCaption(
      language: (json['language'] ?? json['lanName'] ?? 'English').toString(),
      code: (json['code'] ?? json['lan'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
    );
  }
}

class MovieboxHome {
  final List<MovieboxItem> banners;
  final List<MovieboxHomeSection> sections;

  const MovieboxHome({required this.banners, required this.sections});
}

class MovieboxHomeSection {
  final String title;
  final String type;
  final List<MovieboxItem> items;

  const MovieboxHomeSection({required this.title, required this.type, required this.items});
}

class MovieboxException implements Exception {
  final String message;
  const MovieboxException(this.message);

  @override
  String toString() => message;
}
