import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/airing_schedule_item.dart';
import 'package:shikai_app/models/franchise_data.dart';
import 'package:shikai_app/models/media_relation.dart';

class AnilistService {
  static const String endpoint = 'https://graphql.anilist.co';

  static const Map<String, String> _graphqlHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };

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
    final bool isTag = (genre == 'Isekai');
    final String varDef = isTag ? '\$tag: String' : '\$genre: String';
    final String filterClause = isTag ? 'tag: \$tag' : 'genre: \$genre';
    final Map<String, dynamic> variables = {'page': page, 'perPage': perPage};
    if (isTag) {
      variables['tag'] = 'Isekai';
    } else {
      variables['genre'] = genre;
    }

    final query = '''
      query ($varDef, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media($filterClause, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
            $_mediaFragment
          }
        }
      }
    ''';

    return _fetchMediaList(query, variables);
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
        headers: _graphqlHeaders,
        body: jsonEncode({
          'query': query,
          'variables': {'start': start, 'end': end},
        }),
      ).timeout(const Duration(seconds: 14));

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
      if (genre == 'Isekai') {
        varDefs.add('\$tag: String');
        mediaArgs.add('tag: \$tag');
        variables['tag'] = 'Isekai';
      } else {
        varDefs.add('\$genre: String');
        mediaArgs.add('genre: \$genre');
        variables['genre'] = genre;
      }
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
        headers: _graphqlHeaders,
        body: jsonEncode({'query': query, 'variables': {'id': id}}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mediaData = data['data']?['Media'];
        if (mediaData != null) {
          return AnilistMedia.fromJson(mediaData);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<List<MediaRelation>> getAnimeRelations(int id) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id) {
          relations {
            edges {
              id
              relationType
              node {
                id
                type
                format
                status
                episodes
                averageScore
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
                genres
                countryOfOrigin
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _graphqlHeaders,
        body: jsonEncode({'query': query, 'variables': {'id': id}}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic>? edges = data['data']?['Media']?['relations']?['edges'];
        if (edges != null) {
          final List<MediaRelation> list = [];
          for (final edge in edges) {
            try {
              final rel = MediaRelation.fromJson(edge);
              // Include valid anime and manga adaptations with cover images
              if (rel.media.format != 'MUSIC' &&
                  rel.media.id != 0 &&
                  rel.media.coverImage.isNotEmpty) {
                list.add(rel);
              }
            } catch (_) {}
          }
          list.sort((a, b) => a.priority.compareTo(b.priority));
          return list;
        }
      }
    } catch (e) {
      // AnilistService getAnimeRelations error
    }
    return [];
  }

  // Universal 0ms Memory Cache for Franchise Data (keyed by Anime ID)
  static final Map<int, FranchiseData> _franchiseCache = {};

  /// Deep 2-Hop Franchise Traversal, Source Manga Adaptation Clustering,
  /// Chronological Release Sorting, Clean Title Stripping, and Smart Badge Generation
  static Future<FranchiseData> getAnimeFranchise(int animeId) async {
    if (_franchiseCache.containsKey(animeId)) {
      return _franchiseCache[animeId]!;
    }

    const franchiseQuery = '''
      query GetAnimeFranchise(\$id: Int) {
        Media(id: \$id) {
          id
          type
          format
          status
          episodes
          seasonYear
          startDate { year month day }
          title { english romaji native }
          coverImage { large medium extraLarge }
          bannerImage
          averageScore
          relations {
            edges {
              relationType
              node {
                id
                type
                format
                status
                episodes
                seasonYear
                startDate { year month day }
                title { english romaji native }
                coverImage { large medium extraLarge }
                bannerImage
                averageScore
                relations {
                  edges {
                    relationType
                    node {
                      id
                      type
                      format
                      status
                      episodes
                      seasonYear
                      startDate { year month day }
                      title { english romaji native }
                      coverImage { large medium extraLarge }
                      bannerImage
                      averageScore
                    }
                  }
                }
              }
            }
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _graphqlHeaders,
        body: jsonEncode({
          'query': franchiseQuery,
          'variables': {'id': animeId},
        }),
      ).timeout(const Duration(seconds: 14));

      if (response.statusCode != 200) {
        return const FranchiseData(seasons: [], movies: [], related: [], sourceManga: []);
      }

      final data = jsonDecode(response.body);
      final current = data['data']?['Media'] as Map<String, dynamic>?;
      if (current == null) {
        return const FranchiseData(seasons: [], movies: [], related: [], sourceManga: []);
      }

      final allowedDirect = {'PREQUEL', 'SEQUEL', 'PARENT', 'SIDE_STORY', 'ALTERNATIVE', 'SPIN_OFF'};
      final promoOrAdRegex = RegExp(
        r'\b(pv|cm|commercial|teaser|preview|music video|mv|recap|summary|digest|bonus|creditless|clean op|clean ed|picture drama|audio drama|nissan|cup noodle|lakers|cry heart|relight|tokubetsu hen)\b',
        caseSensitive: false,
      );
      final validFormats = {'TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'};

      final stopWords = {
        'the', 'a', 'an', 'no', 'to', 'in', 'of', 'and', 'season', 'part', 'arc',
        'cour', 'movie', 'tv', 'special', 'ova', 'ona', 'act', 'hen', 'edition',
        'version', 'chapter', 'shou', 'first', 'second', 'third', 'fourth', 'final',
        'episode', 'episodes', 'goro', 'zoku', 'film', 'series', 'world', 'journey',
        'blood', 'war', 'gate', 'hero', 'battle', 'story', 'time', 'chronicle'
      };

      List<String> cleanKeywords(String? title) {
        if (title == null || title.isEmpty) return [];
        return title
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 2 && !stopWords.contains(w))
            .toList();
      }

      final rootKeywords = {
        ...cleanKeywords(current['title']?['english']?.toString()),
        ...cleanKeywords(current['title']?['romaji']?.toString()),
      };

      bool isTitleMatch(Map<String, dynamic>? node) {
        if (rootKeywords.isEmpty || node == null) return true;
        final candWords = [
          ...cleanKeywords(node['title']?['english']?.toString()),
          ...cleanKeywords(node['title']?['romaji']?.toString()),
        ];
        return candWords.any((w) => rootKeywords.contains(w));
      }

      bool isClean(Map<String, dynamic>? n) {
        if (n == null || n['title'] == null) return false;
        final format = n['format']?.toString() ?? '';
        if (!validFormats.contains(format)) return false;
        final fullTitle = '${n['title']?['english'] ?? ''} ${n['title']?['romaji'] ?? ''}'.toLowerCase();
        if (promoOrAdRegex.hasMatch(fullTitle)) return false;
        if (format == 'SPECIAL' && (n['episodes'] == 1 || n['episodes'] == null) &&
            (fullTitle.contains('pv') || fullTitle.contains('trailer') || fullTitle.contains('preview'))) {
          return false;
        }
        return true;
      }

      final Map<int, Map<String, dynamic>> allMap = {};
      final Map<int, Map<String, dynamic>> mangaMap = {};

      allMap[(current['id'] as num).toInt()] = {...current, 'relationType': 'CURRENT'};

      final edges1 = (current['relations']?['edges'] as List<dynamic>?) ?? [];
      for (final e1 in edges1) {
        final relType1 = e1['relationType']?.toString() ?? '';
        final node1 = e1['node'] as Map<String, dynamic>?;
        if (node1 == null) continue;
        final n1Id = (node1['id'] as num?)?.toInt();
        if (n1Id == null) continue;

        if (relType1 == 'ADAPTATION' && (node1['type'] == 'MANGA' || node1['type'] == 'NOVEL')) {
          if (!mangaMap.containsKey(n1Id)) {
            mangaMap[n1Id] = {...node1, 'relationType': 'ORIGINAL'};
          }
          final sourceEdges = (node1['relations']?['edges'] as List<dynamic>?) ?? [];
          for (final se in sourceEdges) {
            final seNode = se['node'] as Map<String, dynamic>?;
            if (seNode == null) continue;
            final seId = (seNode['id'] as num?)?.toInt();
            if (seId == null) continue;

            if (se['relationType'] == 'ADAPTATION' && seNode['type'] == 'ANIME' && isClean(seNode)) {
              if (isTitleMatch(seNode) && !allMap.containsKey(seId)) {
                allMap[seId] = {...seNode, 'relationType': 'ADAPTATION'};
              }
            }
          }
        } else if (allowedDirect.contains(relType1) && isClean(node1)) {
          if (isTitleMatch(node1) && !allMap.containsKey(n1Id)) {
            allMap[n1Id] = {...node1, 'relationType': relType1};
          }

          final edges2 = (node1['relations']?['edges'] as List<dynamic>?) ?? [];
          for (final e2 in edges2) {
            final relType2 = e2['relationType']?.toString() ?? '';
            final node2 = e2['node'] as Map<String, dynamic>?;
            if (node2 == null) continue;
            final n2Id = (node2['id'] as num?)?.toInt();
            if (n2Id == null) continue;

            if ((relType2 == 'PREQUEL' || relType2 == 'SEQUEL') && isClean(node2)) {
              if (isTitleMatch(node2) && !allMap.containsKey(n2Id)) {
                allMap[n2Id] = {...node2, 'relationType': relType2};
              }
            }
          }
        }
      }

      final list = allMap.values.toList();

      bool isSpinOff(Map<String, dynamic> item) {
        if (item['relationType'] == 'SPIN_OFF') return true;
        final full = '${item['title']?['english'] ?? ''} ${item['title']?['romaji'] ?? ''}'.toLowerCase();
        return RegExp(r'\b(junior high|vigilantes|gakuen|chibi|academy story|rock lee|diaries)\b', caseSensitive: false).hasMatch(full);
      }

      bool isCoreTv(Map<String, dynamic> item) {
        if (isSpinOff(item)) return false;
        final full = '${item['title']?['english'] ?? ''} ${item['title']?['romaji'] ?? ''}'.toLowerCase();
        final isFinalChapter = full.contains('final chapter') || full.contains('kanketsu-hen');
        final format = item['format']?.toString() ?? '';
        final eps = (item['episodes'] as num?)?.toInt() ?? 0;
        if (format == 'TV') return true;
        if (isFinalChapter) return true;
        if ((format == 'TV_SHORT' || format == 'ONA') && eps >= 3) return true;
        return false;
      }

      final coreTvNodes = list.where(isCoreTv).toList();
      final movieNodes = list.where((item) => !isSpinOff(item) && item['format'] == 'MOVIE').toList();
      final relatedNodes = list.where((item) => isSpinOff(item) || (!isCoreTv(item) && item['format'] != 'MOVIE')).toList();

      int sortByDate(Map<String, dynamic> a, Map<String, dynamic> b) {
        final sA = a['startDate'] as Map<String, dynamic>?;
        final sB = b['startDate'] as Map<String, dynamic>?;
        final yA = (sA?['year'] as num?)?.toInt() ?? (a['seasonYear'] as num?)?.toInt() ?? 9999;
        final mA = (sA?['month'] as num?)?.toInt() ?? 1;
        final dA = (sA?['day'] as num?)?.toInt() ?? 1;
        final scoreA = yA * 10000 + mA * 100 + dA;

        final yB = (sB?['year'] as num?)?.toInt() ?? (b['seasonYear'] as num?)?.toInt() ?? 9999;
        final mB = (sB?['month'] as num?)?.toInt() ?? 1;
        final dB = (sB?['day'] as num?)?.toInt() ?? 1;
        final scoreB = yB * 10000 + mB * 100 + dB;

        if (scoreA != scoreB) return scoreA.compareTo(scoreB);
        return ((a['id'] as num?)?.toInt() ?? 0).compareTo((b['id'] as num?)?.toInt() ?? 0);
      }

      coreTvNodes.sort(sortByDate);
      movieNodes.sort(sortByDate);
      relatedNodes.sort(sortByDate);

      final rootEn = (current['title']?['english'] ?? '').toString().trim();
      final rootRo = (current['title']?['romaji'] ?? '').toString().trim();

      String getShortTitle(Map<String, dynamic> item) {
        final full = (item['title']?['english'] ?? item['title']?['romaji'] ?? 'Season').toString();
        if (rootEn.isNotEmpty && full.toLowerCase() == rootEn.toLowerCase()) return full;
        if (rootRo.isNotEmpty && full.toLowerCase() == rootRo.toLowerCase()) return full;

        final prefixes = [rootEn, rootRo].where((p) => p.length >= 3);
        for (final p in prefixes) {
          final reg = RegExp('^${RegExp.escape(p)}[:\\s\\-–]+', caseSensitive: false);
          if (reg.hasMatch(full)) {
            final stripped = full.replaceFirst(reg, '').trim();
            if (stripped.length >= 2) return stripped;
          }
        }
        return full;
      }

      Map<String, String> parseSeasonBadge(Map<String, dynamic> item, int index) {
        final titleStr = '${item['title']?['english'] ?? ''} ${item['title']?['romaji'] ?? ''}'.toLowerCase();

        if (titleStr.contains('kimetsu no yaiba') || titleStr.contains('demon slayer')) {
          if (titleStr.contains('mugen train arc') || titleStr.contains('mugen ressha-hen')) {
            return {'tag': 'Mugen Arc', 'label': 'Mugen Train Arc'};
          }
          if (titleStr.contains('entertainment district') || titleStr.contains('yuukaku-hen')) {
            return {'tag': 'S2', 'label': 'Season 2 (Entertainment District)'};
          }
          if (titleStr.contains('swordsmith village') || titleStr.contains('katanakaji no sato-hen')) {
            return {'tag': 'S3', 'label': 'Season 3 (Swordsmith Village)'};
          }
          if (titleStr.contains('hashira training') || titleStr.contains('hashira geiko-hen')) {
            return {'tag': 'S4', 'label': 'Season 4 (Hashira Training)'};
          }
          if (index == 0) return {'tag': 'S1', 'label': 'Season 1'};
        }

        if (titleStr.contains('thousand-year blood war') || titleStr.contains('sennen kessen-hen')) {
          final partMatch = RegExp(r'(?:part|cour)\s*([0-9]+)', caseSensitive: false).firstMatch(titleStr);
          if (partMatch != null) {
            return {'tag': 'TYBW P${partMatch.group(1)}', 'label': 'TYBW Part ${partMatch.group(1)}'};
          }
          if (titleStr.contains('separation') || titleStr.contains('ketsubetsu-tan')) {
            return {'tag': 'TYBW P2', 'label': 'TYBW Part 2 (The Separation)'};
          }
          if (titleStr.contains('conflict') || titleStr.contains('soukoku-tan')) {
            return {'tag': 'TYBW P3', 'label': 'TYBW Part 3 (The Conflict)'};
          }
          if (titleStr.contains('calamity') || titleStr.contains('kashin-tan')) {
            return {'tag': 'TYBW P4', 'label': 'TYBW Part 4 (The Calamity)'};
          }
          return {'tag': 'TYBW P1', 'label': 'Thousand-Year Blood War'};
        }

        final sMatch = RegExp(r'(?:season|s)\s*([0-9]+)|([0-9]+)(?:st|nd|rd|th)\s*season', caseSensitive: false).firstMatch(titleStr);
        final partMatch = RegExp(r'(?:part|cour)\s*([0-9]+)', caseSensitive: false).firstMatch(titleStr);
        final isFinal = titleStr.contains('final season') || titleStr.contains('the final chapters');

        String tag = 'S${index + 1}';
        String label = 'Season ${index + 1}';

        if (isFinal) {
          if (partMatch != null) {
            tag = 'Final P${partMatch.group(1)}';
            label = 'Final Season Part ${partMatch.group(1)}';
          } else if (titleStr.contains('the final chapters')) {
            final specMatch = RegExp(r'special\s*([0-9]+)', caseSensitive: false).firstMatch(titleStr);
            tag = specMatch != null ? 'Final Ch ${specMatch.group(1)}' : 'Final Chapters';
            label = specMatch != null ? 'The Final Chapters (${specMatch.group(1)})' : 'The Final Chapters';
          } else {
            tag = 'Final S';
            label = 'The Final Season';
          }
        } else if (sMatch != null) {
          final sNum = sMatch.group(1) ?? sMatch.group(2);
          if (partMatch != null) {
            tag = 'S$sNum P${partMatch.group(1)}';
            label = 'Season $sNum Part ${partMatch.group(1)}';
          } else {
            tag = 'S$sNum';
            label = 'Season $sNum';
          }
        } else if (partMatch != null) {
          tag = 'Part ${partMatch.group(1)}';
          label = 'Part ${partMatch.group(1)}';
        } else if (index == 0) {
          tag = 'S1';
          label = 'Season 1';
        }

        return {'tag': tag, 'label': label};
      }

      FranchiseItem toItem(Map<String, dynamic> n, {required String tag, required String label, bool isManga = false}) {
        final id = (n['id'] as num).toInt();
        final sYear = (n['startDate']?['year'] as num?)?.toInt() ?? (n['seasonYear'] as num?)?.toInt();
        return FranchiseItem(
          id: id,
          title: n['title']?['romaji']?.toString() ?? '',
          englishTitle: n['title']?['english']?.toString() ?? '',
          shortTitle: isManga ? (n['title']?['english'] ?? n['title']?['romaji'] ?? '') : getShortTitle(n),
          seasonTag: tag,
          seasonLabel: label,
          format: n['format']?.toString(),
          status: n['status']?.toString(),
          episodes: (n['episodes'] as num?)?.toInt(),
          seasonYear: sYear,
          releaseYear: sYear,
          coverImage: (n['coverImage']?['extraLarge'] ?? n['coverImage']?['large'] ?? n['coverImage']?['medium'] ?? '').toString(),
          bannerImage: n['bannerImage']?.toString(),
          averageScore: (n['averageScore'] as num?)?.toInt(),
          relationType: n['relationType']?.toString() ?? '',
          isCurrent: id == animeId,
          isManga: isManga,
          rawMedia: AnilistMedia.fromJson(n),
        );
      }

      final formattedTv = coreTvNodes.asMap().entries.map((e) {
        final b = parseSeasonBadge(e.value, e.key);
        return toItem(e.value, tag: b['tag']!, label: b['label']!);
      }).toList();

      int movieIdx = 1;
      final formattedMovies = movieNodes.map((n) {
        const tag = 'Movie';
        final label = movieNodes.length > 1 ? 'Movie ${movieIdx++}' : 'Movie';
        return toItem(n, tag: tag, label: label);
      }).toList();

      final formattedRelated = relatedNodes.map((n) {
        final fmt = n['format']?.toString() ?? '';
        final tag = isSpinOff(n) ? 'Spin-off' : (fmt == 'OVA' ? 'OVA' : 'Special');
        return toItem(n, tag: tag, label: tag);
      }).toList();

      final formattedManga = mangaMap.values.map((n) {
        final isNovel = n['format'] == 'NOVEL';
        return toItem(n, tag: isNovel ? 'Light Novel' : 'Manga', label: isNovel ? 'Original Light Novel' : 'Original Manga', isManga: true);
      }).toList();

      final franchise = FranchiseData(
        seasons: formattedTv,
        movies: formattedMovies,
        related: formattedRelated,
        sourceManga: formattedManga,
      );

      // Warm memory cache for ALL participating IDs
      for (final s in formattedTv) { _franchiseCache[s.id] = franchise; }
      for (final m in formattedMovies) { _franchiseCache[m.id] = franchise; }
      for (final r in formattedRelated) { _franchiseCache[r.id] = franchise; }

      return franchise;
    } catch (_) {
      return const FranchiseData(seasons: [], movies: [], related: [], sourceManga: []);
    }
  }

  /// In-memory cache for anime queries to prevent empty screen on rate-limits or tab switches
  static final Map<String, List<AnilistMedia>> _animeQueryCache = {};

  static Future<List<AnilistMedia>> _fetchMediaList(String query, Map<String, dynamic> variables) async {
    final cacheKey = '$query#${jsonEncode(variables)}';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: _graphqlHeaders,
        body: jsonEncode({'query': query, 'variables': variables}),
      ).timeout(const Duration(seconds: 14));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic>? mediaList = data['data']?['Page']?['media'];
        if (mediaList != null) {
          final results = mediaList.map((m) => AnilistMedia.fromJson(m)).toList();
          if (results.isNotEmpty) {
            _animeQueryCache[cacheKey] = results;
          }
          return results;
        }
      } else if (response.statusCode == 429) {
        // Rate limited: wait 1.8s and retry with browser headers
        await Future.delayed(const Duration(milliseconds: 1800));
        final retry = await http.post(
          Uri.parse(endpoint),
          headers: _graphqlHeaders,
          body: jsonEncode({'query': query, 'variables': variables}),
        ).timeout(const Duration(seconds: 12));

        if (retry.statusCode == 200) {
          final data = jsonDecode(retry.body);
          final List<dynamic>? mediaList = data['data']?['Page']?['media'];
          if (mediaList != null) {
            final results = mediaList.map((m) => AnilistMedia.fromJson(m)).toList();
            if (results.isNotEmpty) {
              _animeQueryCache[cacheKey] = results;
            }
            return results;
          }
        }
      }
    } catch (_) {}

    // Fallback to cache if available
    if (_animeQueryCache.containsKey(cacheKey)) {
      return _animeQueryCache[cacheKey]!;
    }

    return [];
  }
}
