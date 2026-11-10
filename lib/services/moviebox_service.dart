import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/moviebox_media.dart';

/// ---------------------------------------------------------------------------
/// MOVIEBOX ON-DEVICE API ENGINE
///
/// Ported from walterwhite-69/Moviebox-API (FastAPI) to pure Dart so every
/// request is signed and sent directly from the user's device IP. No backend
/// server, no datacenter IP, no bandwidth cost.
///
/// Flow:
///   1. Bootstrap a guest JWT from the MovieBox ranking endpoint.
///   2. Sign every native API request (HMAC-MD5 + x-tr-signature).
///   3. Resolve 1080p/720p/480p/360p MP4 streams from the web play gateway.
///   4. Parse season/episode lists and multi-language captions.
/// ---------------------------------------------------------------------------
class MovieboxService {
  static const String _apiBase = 'https://api3.aoneroom.com';
  static const String _h5Base = 'https://h5-api.aoneroom.com/wefeed-h5api-bff';
  static const String _bootstrapUrl =
      'https://apig.inmoviebox.com/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';

  static const String _modernUserAgent =
      'com.community.mbox.in/50020130 (Linux; U; Android 14; en_IN; Pixel 8; Build/UD1A.230803.041; Cronet/145.0.7582.0)';
  static const String _webUserAgent =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Mobile Safari/537.36';

  // MovieBox web mirrors used by the official play gateway.
  static const List<String> _webDomains = [
    'https://123moviesfree.club',
    'https://movie-box.co',
    'https://movieboxonline.net',
    'https://sflix.film',
    'https://h5-api.aoneroom.com',
    'https://netnaija.film',
    'https://movieboxhd.net',
  ];

  static const String _secretDefaultB64 =
      'NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==';

  static final http.Client _client = http.Client();
  static final List<int> _secret = _decodeBase64(
    utf8.decode(_decodeBase64(_secretDefaultB64)),
  );

  static final String _deviceId = _generateDeviceId();
  static String? _token;

  static MovieboxHome? _cachedHome;
  static DateTime? _homeCachedAt;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  static Future<MovieboxHome> getHome({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedHome != null &&
        _homeCachedAt != null &&
        DateTime.now().difference(_homeCachedAt!) < const Duration(minutes: 10)) {
      return _cachedHome!;
    }

    const url = '$_h5Base/home?host=moviebox.ph';
    final res = await _client
        .get(Uri.parse(url), headers: _webHeaders())
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw MovieboxException('MovieBox home returned HTTP ${res.statusCode}');
    }

    final root = _jsonDecode(res.body);
    final data = root['data'];
    if (data is! Map) throw const MovieboxException('Invalid MovieBox home payload');

    final banners = <MovieboxItem>[];
    final sections = <MovieboxHomeSection>[];
    final operating = data['operatingList'];

    if (operating is List) {
      for (final raw in operating) {
        if (raw is! Map) continue;
        final section = Map<String, dynamic>.from(raw);
        final type = (section['type'] ?? '').toString();
        final title = (section['title'] ?? '').toString();

        if (type == 'BANNER') {
          final banner = section['banner'];
          if (banner is Map && banner['items'] is List) {
            for (final b in banner['items'] as List) {
              if (b is Map) {
                final item = MovieboxItem.fromJson(Map<String, dynamic>.from(b));
                if (item.id.isNotEmpty && item.title.isNotEmpty) banners.add(item);
              }
            }
          }
          continue;
        }

        if (type == 'SPORT_LIVE' || type == 'FILTER' || type.isEmpty) continue;

        final rawItems = section['subjects'];
        if (rawItems is! List || rawItems.isEmpty) continue;

        final items = rawItems
            .whereType<Map>()
            .map((e) => MovieboxItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id.isNotEmpty && e.title.isNotEmpty)
            .toList();

        if (items.isNotEmpty) {
          sections.add(MovieboxHomeSection(title: title, type: type, items: items));
        }
      }
    }

    final home = MovieboxHome(banners: banners, sections: sections);
    _cachedHome = home;
    _homeCachedAt = DateTime.now();
    return home;
  }

  static Future<List<MovieboxItem>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];

    final body = {'keyword': query.trim(), 'page': page, 'perPage': 20};
    final root = await _apiRequest(
      'POST',
      '/wefeed-mobile-bff/subject-api/search',
      body: body,
    );

    final data = root['data'];
    if (data is! Map) return [];
    final rawItems = data['items'] ?? data['list'];
    if (rawItems is! List) return [];

    return rawItems
        .whereType<Map>()
        .map((e) => MovieboxItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty && e.title.isNotEmpty)
        .toList();
  }

  static Future<MovieboxDetail> getDetail(String subjectId) async {
    final root = await _apiRequest(
      'GET',
      '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId',
    );
    final data = root['data'];
    if (data is! Map) throw const MovieboxException('MovieBox detail not found');
    return MovieboxDetail.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<List<MovieboxSeason>> getSeasons(String subjectId) async {
    final root = await _apiRequest(
      'GET',
      '/wefeed-mobile-bff/subject-api/season-info?subjectId=$subjectId',
    );
    final data = root['data'];
    if (data is! Map || data['seasons'] is! List) return [];

    return (data['seasons'] as List)
        .whereType<Map>()
        .map((e) => MovieboxSeason.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.episodeCount > 0)
        .toList();
  }

  static Future<List<MovieboxStream>> getStreams(
    String subjectId, {
    int season = 0,
    int episode = 0,
    String? detailPath,
  }) async {
    var path = detailPath;
    if (path == null || path.isEmpty) {
      try {
        final detail = await getDetail(subjectId);
        path = detail.detailPath;
      } catch (_) {}
    }

    final token = await _ensureToken();
    final streams = <MovieboxStream>[];
    final seen = <String>{};

    // 1. Official web play gateway (fastest, gives full-length MP4 files).
    for (final domain in _webDomains) {
      final playUrl =
          '$domain/wefeed-h5api-bff/subject/play?subjectId=$subjectId&se=$season&ep=$episode'
          '&detailPath=${Uri.encodeComponent(path ?? '')}'
          '&streamSignType=1&supportCodecs%5Bhevc%5D=1&supportCodecs%5Bh264%5D=1';
      final referer =
          '$domain/movies/${path ?? ''}?id=$subjectId&type=/movie/detail&detailSe=&detailEp=&lang=en';

      try {
        final res = await _client.get(
          Uri.parse(playUrl),
          headers: {
            'User-Agent': _webUserAgent,
            'Referer': referer,
            'Accept': 'application/json',
            'x-client-info': '{"timezone":"Asia/Calcutta"}',
            'x-request-lang': 'en',
            'x-vip-restrict': '0',
            'x-no-high-risk-restrict': '0',
            'x-source': 'moviebox',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 12));

        if (res.statusCode != 200) continue;

        final root = _jsonDecode(res.body);
        final data = root['data'];
        if (data is! Map) continue;

        final webStreams = data['streams'];
        if (webStreams is List) {
          for (final raw in webStreams) {
            if (raw is! Map) continue;
            final st = Map<String, dynamic>.from(raw);
            final url = st['url']?.toString();
            if (url == null || url.isEmpty || seen.contains(url)) continue;
            seen.add(url);

            final resolution = (st['resolutions'] ?? 'unknown').toString();
            final quality = _qualityValue(resolution);
            final sizeBytes = int.tryParse((st['size'] ?? 0).toString()) ?? 0;

            streams.add(MovieboxStream(
              url: url,
              quality: quality > 0 ? '${quality}p' : resolution,
              qualityValue: quality,
              format: (st['format'] ?? 'MP4').toString(),
              sizeMb: sizeBytes > 0 ? sizeBytes / (1024 * 1024) : 0,
              durationSec: int.tryParse((st['duration'] ?? '').toString()),
              codec: st['codecName']?.toString(),
              headers: {
                'User-Agent': 'Mozilla/5.0',
                'Referer': '$domain/',
                'Origin': domain,
              },
              source: 'Web CDN',
            ));
          }
        }

        final dashItems = data['dash'];
        if (dashItems is List) {
          for (final raw in dashItems) {
            if (raw is! Map) continue;
            final dash = Map<String, dynamic>.from(raw);
            final cookie = dash['signCookie']?.toString();
            final extracted = cookie != null ? _extractPolicyResource(cookie) : null;
            final url = (extracted ?? dash['url'])?.toString();
            if (url == null || url.isEmpty || seen.contains(url)) continue;
            seen.add(url);

            final resolution = (dash['resolutions'] ?? 'adaptive').toString();
            streams.add(MovieboxStream(
              url: url,
              quality: resolution.contains('1080') ? '1080p (Adaptive)' : 'Adaptive',
              qualityValue: resolution.contains('1080') ? 1080 : 999,
              format: 'DASH',
              sizeMb: 0,
              headers: {
                'User-Agent': 'Mozilla/5.0',
                'Referer': '$domain/',
                'Origin': domain,
              },
              source: 'Web DASH',
            ));
          }
        }

        if (streams.isNotEmpty) break;
      } catch (_) {
        continue;
      }
    }

    // 2. Native mobile play-info fallback.
    try {
      final root = await _apiRequest(
        'GET',
        '/wefeed-mobile-bff/subject-api/play-info?subjectId=$subjectId&se=$season&ep=$episode',
      );
      final data = root['data'];
      if (data is Map && data['streams'] is List) {
        for (final raw in data['streams'] as List) {
          if (raw is! Map) continue;
          final st = Map<String, dynamic>.from(raw);
          final rawUrl = st['url']?.toString();
          if (rawUrl == null || rawUrl.isEmpty) continue;
          if (rawUrl.contains('b164fbfb4347792950bdfbfb563d39d9')) continue;

          final cookie = st['signCookie']?.toString();
          final policyUrl = cookie != null ? _extractPolicyResource(cookie) : null;
          final url = policyUrl ?? rawUrl;
          if (seen.contains(url)) continue;
          seen.add(url);

          final resolution = (st['resolutions'] ?? '').toString();
          final quality = _qualityValue(resolution);
          final sizeBytes = int.tryParse((st['size'] ?? 0).toString()) ?? 0;

          streams.add(MovieboxStream(
            url: url,
            quality: quality > 0 ? '${quality}p' : (resolution.isEmpty ? 'Default' : resolution),
            qualityValue: quality,
            format: (policyUrl != null || url.contains('.mpd'))
                ? 'DASH'
                : (st['format'] ?? 'MP4').toString(),
            sizeMb: sizeBytes > 0 ? sizeBytes / (1024 * 1024) : 0,
            durationSec: int.tryParse((st['duration'] ?? '').toString()),
            codec: st['codecName']?.toString(),
            headers: {
              'User-Agent': _modernUserAgent,
              'Referer': 'https://api3.aoneroom.com/',
            },
            source: 'Mobile CDN',
          ));
        }
      }
    } catch (_) {}

    streams.sort((a, b) {
      final q = b.qualityValue.compareTo(a.qualityValue);
      if (q != 0) return q;
      final d = (b.durationSec ?? 0).compareTo(a.durationSec ?? 0);
      if (d != 0) return d;
      return a.isDash ? 1 : -1;
    });

    return streams;
  }

  static Future<List<MovieboxCaption>> getCaptions(
    String subjectId, {
    int season = 0,
    int episode = 0,
    String? streamId,
  }) async {
    var resourceId = streamId;
    if (resourceId == null || resourceId.isEmpty) {
      try {
        final root = await _apiRequest(
          'GET',
          '/wefeed-mobile-bff/subject-api/play-info?subjectId=$subjectId&se=$season&ep=$episode',
        );
        final data = root['data'];
        if (data is Map && data['streams'] is List && (data['streams'] as List).isNotEmpty) {
          final first = (data['streams'] as List).first;
          if (first is Map) resourceId = first['id']?.toString();
        }
      } catch (_) {}
    }

    final captions = <MovieboxCaption>[];
    final seen = <String>{};

    void addAll(dynamic rawData) {
      final list = rawData is List
          ? rawData
          : (rawData is Map ? (rawData['extCaptions'] ?? rawData['captions']) : null);
      if (list is! List) return;
      for (final raw in list) {
        if (raw is! Map) continue;
        final cap = MovieboxCaption.fromJson(Map<String, dynamic>.from(raw));
        if (cap.url.isEmpty || seen.contains(cap.url)) continue;
        seen.add(cap.url);
        captions.add(cap);
      }
    }

    if (resourceId != null && resourceId.isNotEmpty) {
      try {
        final root = await _apiRequest(
          'GET',
          '/wefeed-mobile-bff/subject-api/get-stream-captions?subjectId=$subjectId&streamId=$resourceId',
        );
        addAll(root['data']);
      } catch (_) {}
    }

    try {
      final root = await _apiRequest(
        'GET',
        '/wefeed-mobile-bff/subject-api/get-ext-captions?subjectId=$subjectId&resourceId=${resourceId ?? '0'}&episode=$episode',
      );
      addAll(root['data']);
    } catch (_) {}

    captions.sort((a, b) {
      if (a.code == 'en') return -1;
      if (b.code == 'en') return 1;
      return a.language.compareTo(b.language);
    });
    return captions;
  }

  // -------------------------------------------------------------------------
  // Authentication & signed requests
  // -------------------------------------------------------------------------

  static Future<String> _ensureToken({bool force = false}) async {
    if (!force && _token != null && _token!.isNotEmpty) return _token!;

    final res = await _client
        .get(Uri.parse(_bootstrapUrl), headers: _signedHeaders('GET', _bootstrapUrl))
        .timeout(const Duration(seconds: 20));

    final rawUser = res.headers['x-user'];
    if (res.statusCode != 200 || rawUser == null || rawUser.isEmpty) {
      throw MovieboxException('MovieBox auth failed (HTTP ${res.statusCode})');
    }

    final decoded = _jsonDecode(rawUser);
    final token = decoded['token']?.toString();
    if (token == null || token.isEmpty) {
      throw const MovieboxException('MovieBox auth token missing');
    }
    _token = token;
    return token;
  }

  static Future<Map<String, dynamic>> _apiRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retryAuth = true,
  }) async {
    final token = await _ensureToken();
    final url = '$_apiBase$path';
    final bodyStr = body != null ? jsonEncode(body) : null;
    final headers = _signedHeaders(method, url, body: bodyStr, token: token);

    late http.Response res;
    if (method.toUpperCase() == 'POST') {
      res = await _client
          .post(Uri.parse(url), headers: headers, body: bodyStr)
          .timeout(const Duration(seconds: 25));
    } else {
      res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 25));
    }

    if ((res.statusCode == 401 || res.statusCode == 441) && retryAuth) {
      await _ensureToken(force: true);
      return _apiRequest(method, path, body: body, retryAuth: false);
    }

    if (res.statusCode != 200) {
      final snippet = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
      throw MovieboxException('MovieBox API returned HTTP ${res.statusCode}: $snippet');
    }

    return _jsonDecode(res.body);
  }

  static Map<String, String> _signedHeaders(
    String method,
    String url, {
    String? body,
    String? token,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final canonical = _canonicalString(method, 'application/json', 'application/json', url, body, ts);
    final signature = base64.encode(
      Hmac(md5, _secret).convert(utf8.encode(canonical)).bytes,
    );
    final reversed = ts.toString().split('').reversed.join();

    return {
      'user-agent': _modernUserAgent,
      'accept': 'application/json',
      'content-type': 'application/json',
      'connection': 'keep-alive',
      'x-client-token': '$ts,${md5.convert(utf8.encode(reversed))}',
      'x-tr-signature': '$ts|2|$signature',
      'x-client-info': _clientInfo(),
      'x-client-status': '0',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  static Map<String, String> _webHeaders() => {
        'User-Agent': _webUserAgent,
        'Referer': 'https://moviebox.ph/',
        'Accept': 'application/json',
      };

  static String _canonicalString(
    String method,
    String accept,
    String contentType,
    String url,
    String? body,
    int timestamp,
  ) {
    final uri = Uri.parse(url);
    final path = uri.path.isEmpty ? '/' : uri.path;
    String canonicalUrl = path;

    if (uri.query.isNotEmpty) {
      final pairs = uri.query
          .split('&')
          .where((e) => e.isNotEmpty)
          .map((segment) {
            final idx = segment.indexOf('=');
            return idx < 0
                ? [segment, '']
                : [segment.substring(0, idx), segment.substring(idx + 1)];
          })
          .toList()
        ..sort((a, b) => a[0].compareTo(b[0]));
      canonicalUrl = '$path?${pairs.map((p) => '${p[0]}=${p[1]}').join('&')}';
    }

    final bodyBytes = body == null ? null : utf8.encode(body);
    final bodyLength = bodyBytes == null ? '' : bodyBytes.length.toString();
    final bodyHash = bodyBytes == null
        ? ''
        : md5.convert(bodyBytes.sublist(0, min(bodyBytes.length, 102400))).toString();

    return [
      method.toUpperCase(),
      accept,
      contentType,
      bodyLength,
      timestamp.toString(),
      bodyHash,
      canonicalUrl,
    ].join('\n');
  }

  static String _clientInfo() {
    return jsonEncode({
      'package_name': 'com.community.mbox.in',
      'version_name': '4.0.03.0920.03',
      'version_code': 50020130,
      'os': 'android',
      'os_version': '14',
      'device_id': _deviceId,
      'install_store': 'official',
      'gaid': '1b2212c1-dadf-43c3-a0c8-bd6ce48ae22d',
      'brand': 'Google',
      'model': 'Pixel 8',
      'system_language': 'en',
      'net': 'NETWORK_WIFI',
      'region': 'IN',
      'timezone': 'Asia/Calcutta',
      'sp_code': '',
    });
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String? _extractPolicyResource(String cookie) {
    final edge = RegExp(r'Edge-Cache-Cookie=urlprefix=([^:;\s]+)').firstMatch(cookie);
    if (edge != null) {
      try {
        final decoded = utf8.decode(_decodeBase64(edge.group(1)!)).replaceAll(RegExp(r'/+$'), '');
        return '$decoded/index.mpd';
      } catch (_) {}
    }

    final cloudFront = RegExp(r'CloudFront-Policy=([^;]+)').firstMatch(cookie);
    if (cloudFront != null) {
      try {
        final decoded = jsonDecode(utf8.decode(_decodeBase64(cloudFront.group(1)!)));
        if (decoded is Map && decoded['Statement'] is List) {
          for (final statement in decoded['Statement'] as List) {
            if (statement is! Map) continue;
            final resource = statement['Resource']?.toString();
            if (resource != null && resource.isNotEmpty) {
              final clean = resource.replaceAll(RegExp(r'[*]+$'), '').replaceAll(RegExp(r'/+$'), '');
              return '$clean/index.mpd';
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  static int _qualityValue(String resolutions) {
    for (final q in [2160, 1440, 1080, 720, 480, 360, 240]) {
      if (resolutions.contains(q.toString())) return q;
    }
    return 0;
  }

  static Map<String, dynamic> _jsonDecode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const MovieboxException('Unexpected MovieBox response');
  }

  static List<int> _decodeBase64(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    normalized += '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(normalized);
  }

  static String _generateDeviceId() {
    const chars = '0123456789abcdef';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
