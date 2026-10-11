import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/airing_schedule_item.dart';

class AnilistService {
  static const String endpoint = 'https://graphql.anilist.co';

  static const String _mediaFragment = '''
    id
    title {
      romaji
      english
    }
    coverImage {
      extraLarge
      large
      medium
    }
    bannerImage
    description
    episodes
    genres
    averageScore
    status
    format
  ''';

  static Future<List<AnilistMedia>> getTrendingAnime({int page = 1, int perPage = 12}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: TRENDING_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getPopularAnime({int page = 1, int perPage = 12}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getTopAiring({int page = 1, int perPage = 12}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: SCORE_DESC, status: RELEASING, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getAnimeByGenre(String genre, {int page = 1, int perPage = 20}) async {
    const query = '''
      query (\$genre: String, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(genre: \$genre, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, {'genre': genre, 'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> searchAnime(String search, {int page = 1, int perPage = 20}) async {
    const query = '''
      query (\$search: String, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(search: \$search, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, {'search': search, 'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getMovies({int page = 1, int perPage = 20}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(format: MOVIE, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';
    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getRecentlyUpdated({int page = 1, int perPage = 25}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: UPDATED_AT_DESC, status: RELEASING, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';
    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getTopRated({int page = 1, int perPage = 25}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: SCORE_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';
    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<List<AnilistMedia>> getUpcomingAnime({int page = 1, int perPage = 25}) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(status: NOT_YET_RELEASED, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';
    return _fetchMediaList(query, {'page': page, 'perPage': perPage});
  }

  static Future<AnilistMedia?> getRandomAnime() async {
    final randomPage = (DateTime.now().millisecondsSinceEpoch % 20) + 1;
    const query = '''
      query (\$page: Int) {
        Page(page: \$page, perPage: 15) {
          media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';
    final list = await _fetchMediaList(query, {'page': randomPage});
    if (list.isNotEmpty) {
      list.shuffle();
      return list.first;
    }
    return null;
  }

  static Future<List<AiringScheduleItem>> getAiringSchedule() async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final start = nowSec - (86400 * 2); // 2 days ago
    final end = nowSec + (86400 * 7);   // 7 days ahead

    const query = '''
      query (\$start: Int, \$end: Int) {
        Page(page: 1, perPage: 50) {
          airingSchedules(airingAt_greater: \$start, airingAt_lesser: \$end, sort: TIME) {
            id
            airingAt
            episode
            timeUntilAiring
            media {
              $_mediaFragment
            }
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          'variables': {'start': start, 'end': end},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic>? schedules = data['data']?['Page']?['airingSchedules'];
        if (schedules != null) {
          return schedules.map((s) => AiringScheduleItem.fromJson(s)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<List<AnilistMedia>> advancedFilter({
    String? query,
    String? format,
    String? genre,
    String? status,
    String sort = 'POPULARITY_DESC',
    int page = 1,
    int perPage = 21,
  }) async {
    final Map<String, dynamic> variables = {
      'page': page,
      'perPage': perPage,
      'sort': [sort],
    };

    final List<String> varDefs = ['\$page: Int', '\$perPage: Int', '\$sort: [MediaSort]'];
    final List<String> mediaArgs = ['sort: \$sort', 'type: ANIME', 'isAdult: false'];

    if (query != null && query.trim().isNotEmpty) {
      varDefs.add('\$search: String');
      mediaArgs.add('search: \$search');
      variables['search'] = query.trim();
    }

    if (format != null && format != 'All') {
      varDefs.add('\$format: MediaFormat');
      mediaArgs.add('format: \$format');
      variables['format'] = format;
    }

    if (genre != null && genre != 'All') {
      varDefs.add('\$genre: String');
      mediaArgs.add('genre: \$genre');
      variables['genre'] = genre;
    }

    if (status != null && status != 'All') {
      varDefs.add('\$status: MediaStatus');
      mediaArgs.add('status: \$status');
      variables['status'] = status;
    }

    final gql = '''
      query (${varDefs.join(', ')}) {
        Page(page: \$page, perPage: \$perPage) {
          media(${mediaArgs.join(', ')}) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(gql, variables);
  }

  static Future<AnilistMedia?> getAnimeDetails(int id) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_mediaFragment
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': {'id': id}}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mediaData = data['data']?['Media'];
        if (mediaData != null) {
          return AnilistMedia.fromJson(mediaData);
        }
      }
    } catch (e) {
      print('AnilistService getAnimeDetails error: \$e');
    }
    return null;
  }

  static Future<List<AnilistMedia>> _fetchMediaList(String query, Map<String, dynamic> variables) async {
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic>? mediaList = data['data']?['Page']?['media'];
        if (mediaList != null) {
          return mediaList.map((m) => AnilistMedia.fromJson(m)).toList();
        }
      } else {
        print('Anilist error: HTTP ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('AnilistService error: \$e');
    }
    return [];
  }
}
