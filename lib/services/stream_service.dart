import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shikai_app/services/local_proxy/local_proxy.dart';
import 'package:shikai_app/services/anivexa_service.dart';
import 'package:shikai_app/services/subtitle_service.dart';

class StreamSource {
  final String id;
  final String serverName;
  final String streamUrl;
  final String type; // 'hls' or 'mp4'
  final String quality; // '1080p', 'Multi', etc.
  final String audioType; // 'Sub', 'Dub', 'Hindi'
  final Map<String, String> headers;
  final List<SubtitleTrack> subtitles;
  final int introStart;
  final int introEnd;
  final int outroStart;
  final int outroEnd;
  final bool isZeroBandwidth;
  final String? playlistKey;
  final String? referer;

  StreamSource({
    required this.id,
    required this.serverName,
    required this.streamUrl,
    this.type = 'hls',
    this.quality = '1080p',
    this.audioType = 'Sub',
    this.headers = const {},
    this.subtitles = const [],
    this.introStart = 0,
    this.introEnd = 0,
    this.outroStart = 0,
    this.outroEnd = 0,
    this.isZeroBandwidth = true,
    this.playlistKey,
    this.referer,
  });

  StreamSource copyWith({
    String? id,
    String? serverName,
    String? streamUrl,
    String? type,
    String? quality,
    String? audioType,
    Map<String, String>? headers,
    List<SubtitleTrack>? subtitles,
    int? introStart,
    int? introEnd,
    int? outroStart,
    int? outroEnd,
    bool? isZeroBandwidth,
    String? playlistKey,
    String? referer,
  }) {
    return StreamSource(
      id: id ?? this.id,
      serverName: serverName ?? this.serverName,
      streamUrl: streamUrl ?? this.streamUrl,
      type: type ?? this.type,
      quality: quality ?? this.quality,
      audioType: audioType ?? this.audioType,
      headers: headers ?? this.headers,
      subtitles: subtitles ?? this.subtitles,
      introStart: introStart ?? this.introStart,
      introEnd: introEnd ?? this.introEnd,
      outroStart: outroStart ?? this.outroStart,
      outroEnd: outroEnd ?? this.outroEnd,
      isZeroBandwidth: isZeroBandwidth ?? this.isZeroBandwidth,
      playlistKey: playlistKey ?? this.playlistKey,
      referer: referer ?? this.referer,
    );
  }
}

class SubtitleTrack {
  final String url;
  final String label;
  final String language;
  final String flag;
  final String kind;
  final bool isDefault;

  SubtitleTrack({
    required this.url,
    required this.label,
    this.language = 'en',
    this.flag = '',
    this.kind = 'subtitles',
    this.isDefault = false,
  });
}

class StreamService {
  /// The official Shikai production backend & proxy gateway
  static const String shikaiBaseUrl = 'https://shikai.biz';

  /// In-App Client-Side Proxy Engine (0% Oracle VM Bandwidth)
  static final LocalStreamingProxyInterface localProxy = getLocalStreamingProxy();

  static Future<void> initLocalProxy() async {
    await localProxy.start();
  }

  /// Transforms stream URL to route directly to ExoPlayer or via local proxy if needed
  static String getClientSideStreamUrl(String upstreamUrl, {String? referer, String? key, String? audio}) {
    if (upstreamUrl.isEmpty) return upstreamUrl;

    String resolved = upstreamUrl;
    if (!resolved.startsWith('http')) {
      resolved = '$shikaiBaseUrl${resolved.startsWith('/') ? '' : '/'}$resolved';
    }

    // Direct MP4 videos bypass HLS proxy
    if (resolved.endsWith('.mp4')) {
      return resolved;
    }

    // Client-side HLS proxy: serves master.m3u8 locally, intercepts encrypted Flix/VidMoly segments,
    // unwraps WebP/PNG in RAM, decrypts XOR cipher, and streams clean MPEG-TS to ExoPlayer with 0% server bandwidth!
    if (localProxy.isRunning) {
      return localProxy.getPlaybackUrl(resolved, referer: referer, key: key, audio: audio);
    }

    // Fallback if local proxy server not running
    if ((resolved.contains('/api/anivexa/stream/') ||
         resolved.contains('/api/miruro/stream/')) &&
        !resolved.contains('.m3u8')) {
      resolved = resolved.replaceFirstMapped(
        RegExp(r'(/api/[a-z0-9_-]+/stream/\d+/\d+)'),
        (match) => '${match.group(1)}.m3u8',
      );
    }

    return resolved;
  }

  /// Check Hindi dub availability for an anime on DesiDub
  static Future<bool> checkHindiAvailability(int anilistId) async {
    try {
      final res = await http.get(Uri.parse('$shikaiBaseUrl/api/desidub/availability/$anilistId')).timeout(const Duration(milliseconds: 900));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['available'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Fetch subtitles from Shikai production API
  static Future<List<SubtitleTrack>> fetchSubtitles(int anilistId, int episode) async {
    try {
      final res = await http.get(Uri.parse('$shikaiBaseUrl/api/subtitles/$anilistId/$episode')).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['subtitles'] != null && data['subtitles'] is List) {
          return (data['subtitles'] as List).map((s) {
            String url = s['url'] ?? s['file'] ?? '';
            if (url.isNotEmpty && !url.startsWith('http')) {
              url = '$shikaiBaseUrl${url.startsWith('/') ? '' : '/'}$url';
            }
            return SubtitleTrack(
              url: url,
              label: s['label'] ?? s['lang'] ?? s['language'] ?? 'English',
              language: s['language'] ?? s['lang'] ?? 'en',
              flag: s['flag'] ?? '',
              isDefault: s['default'] == true,
            );
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Resolve all unlocked providers for an anime episode using Anivexa-API and direct CDNs
  static Future<List<StreamSource>> resolveStreamsForEpisode({
    required int anilistId,
    required int episode,
    String title = '',
    String audio = 'sub', // 'sub' or 'dub'
  }) async {
    final List<StreamSource> sources = [];

    // Parallel fetch: Anivexa ReAnime Watch, AniZone, AniKoto, Hindi availability, and subtitles
    final reanimeFuture = AnivexaService.getReAnimeWatch(anilistId: anilistId, episode: episode, audio: audio);
    final anizoneFuture = AnivexaService.getAniZoneWatch(anilistId: anilistId, episode: episode, audio: audio);
    final anikotoFuture = AnivexaService.getAniKotoWatch(anilistId: anilistId, episode: episode, audio: audio);
    final hindiFuture = checkHindiAvailability(anilistId);
    final subsFuture = fetchSubtitles(anilistId, episode);

    final results = await Future.wait([
      reanimeFuture,
      anizoneFuture,
      anikotoFuture,
      hindiFuture,
      subsFuture,
    ]);

    final reanimeWatch = results[0] as AnivexaWatchResult?;
    final anizoneWatch = results[1] as AnivexaWatchResult?;
    final anikotoWatch = results[2] as AnivexaWatchResult?;
    final isHindiAvailable = results[3] as bool;
    final subs = results[4] as List<SubtitleTrack>;

    // Filter out dummy/empty subtitles and deduplicate identical language tracks across all providers
    final effectiveSubs = SubtitleService.cleanSubtitleTracks([
      ...(anikotoWatch?.subtitles ?? []),
      ...(anizoneWatch?.subtitles ?? []),
      ...(reanimeWatch?.subtitles ?? []),
      ...subs,
    ]);

    final encodedTitle = Uri.encodeComponent(title);

    String server1Url = '$shikaiBaseUrl/api/anivexa/stream/$anilistId/$episode.m3u8?audio=$audio&title=$encodedTitle';
    int introStart = 30;
    int introEnd = 115;
    int outroStart = 1370;
    int outroEnd = 1445;
    String? playlistKey = reanimeWatch?.playlistKey;

    if (reanimeWatch != null && reanimeWatch.streamUrl.isNotEmpty) {
      String resolved = reanimeWatch.streamUrl;
      if (!resolved.startsWith('http')) {
        resolved = '$shikaiBaseUrl${resolved.startsWith('/') ? '' : '/'}$resolved';
      }
      if (resolved.contains('/api/anivexa/stream/') && !resolved.contains('.m3u8')) {
        resolved = resolved.replaceFirstMapped(
          RegExp(r'(/api/[a-z0-9_-]+/stream/\d+/\d+)'),
          (m) => '${m.group(1)}.m3u8',
        );
      }
      server1Url = resolved;
      if (reanimeWatch.introStart > 0) introStart = reanimeWatch.introStart;
      if (reanimeWatch.introEnd > 0) introEnd = reanimeWatch.introEnd;
      if (reanimeWatch.outroStart > 0) outroStart = reanimeWatch.outroStart;
      if (reanimeWatch.outroEnd > 0) outroEnd = reanimeWatch.outroEnd;
    }

    // ==============================================================
    // 1. PRIMARY: AniKoto (Bankai • Koto Ultra 1080p)
    // ==============================================================
    sources.add(StreamSource(
      id: 'anikoto',
      serverName: 'Bankai • Koto (Ultra 1080p)',
      streamUrl: anikotoWatch?.streamUrl.isNotEmpty == true
          ? anikotoWatch!.streamUrl
          : '$shikaiBaseUrl/api/anivexa/stream/$anilistId/$episode.m3u8?server=anikoto&audio=$audio&title=$encodedTitle',
      referer: 'https://megaplay.buzz/',
      quality: '1080p Ultra HD',
      audioType: audio == 'dub' ? 'English Dub' : 'Japanese Sub',
      subtitles: effectiveSubs,
      introStart: introStart,
      introEnd: introEnd,
      outroStart: outroStart,
      outroEnd: outroEnd,
      isZeroBandwidth: true,
    ));

    // ==============================================================
    // 2. SECONDARY: AniZone (Shikai • Zone Adaptive HQ)
    // ==============================================================
    sources.add(StreamSource(
      id: 'anizone',
      serverName: 'Shikai • Zone (Adaptive HQ)',
      streamUrl: anizoneWatch?.streamUrl.isNotEmpty == true
          ? anizoneWatch!.streamUrl
          : '$shikaiBaseUrl/api/anivexa/stream/$anilistId/$episode.m3u8?server=anizone&audio=$audio&title=$encodedTitle',
      referer: 'https://anizone.to/',
      quality: '1080p / 720p Adaptive',
      audioType: audio == 'dub' ? 'English Dub' : 'Japanese Sub',
      subtitles: effectiveSubs,
      introStart: introStart,
      introEnd: introEnd,
      outroStart: outroStart,
      outroEnd: outroEnd,
      isZeroBandwidth: true,
    ));

    // ==============================================================
    // 3. FALLBACK: Anivexa HD-2 (Tsukuyomi Direct Master)
    // ==============================================================
    sources.add(StreamSource(
      id: 'anivexa',
      serverName: 'Tsukuyomi (HD-2 Direct)',
      streamUrl: server1Url,
      playlistKey: playlistKey,
      referer: 'https://flixcloud.cc/',
      quality: '1080p Direct Master',
      audioType: audio == 'dub' ? 'English Dub' : 'Japanese Sub',
      subtitles: effectiveSubs,
      introStart: introStart,
      introEnd: introEnd,
      outroStart: outroStart,
      outroEnd: outroEnd,
      isZeroBandwidth: true,
    ));

    // ==============================================================
    // 4. FALLBACK: ReAnime Mirror HD-1 (Kamui Fast Mirror)
    // ==============================================================
    sources.add(StreamSource(
      id: 'reanime',
      serverName: 'Kamui (HD-1 Fast)',
      streamUrl: '$shikaiBaseUrl/api/anivexa/stream/$anilistId/$episode.m3u8?server=hd1&audio=$audio&title=$encodedTitle',
      playlistKey: playlistKey,
      referer: 'https://flixcloud.cc/',
      quality: '1080p Fast Mirror',
      audioType: audio == 'dub' ? 'English Dub' : 'Japanese Sub',
      subtitles: effectiveSubs,
      introStart: introStart,
      introEnd: introEnd,
      outroStart: outroStart,
      outroEnd: outroEnd,
      isZeroBandwidth: true,
    ));

    // ==============================================================
    // 5. FALLBACK: Miruro Global (Rinnegan Global HD)
    // ==============================================================
    sources.add(StreamSource(
      id: 'miruro',
      serverName: 'Rinnegan (Global HD)',
      streamUrl: '$shikaiBaseUrl/api/miruro/stream/$anilistId/$episode.m3u8?audio=$audio&title=$encodedTitle',
      referer: 'https://www.miruro.tv/',
      quality: '1080p Global Direct',
      audioType: audio == 'dub' ? 'English Dub' : 'Japanese Sub',
      subtitles: effectiveSubs,
      isZeroBandwidth: true,
    ));

    // ==============================================================
    // 6. SPECIAL: DesiDub Hindi Dub (Chidori Hindi Dub 🇮🇳)
    // ==============================================================
    if (isHindiAvailable || audio == 'hindi') {
      sources.add(StreamSource(
        id: 'desidub',
        serverName: 'Chidori (Hindi Dub 🇮🇳)',
        streamUrl: '$shikaiBaseUrl/api/desidub/stream/$anilistId/$episode',
        referer: 'https://vidmoly.net/',
        quality: '720p HD Hindi',
        audioType: 'Hindi Dub',
        subtitles: [],
        isZeroBandwidth: true,
      ));
    }

    // ==============================================================
    // 7. BACKUP: Zangetsu Backup Mirror
    // ==============================================================
    sources.add(StreamSource(
      id: 'backup',
      serverName: 'Zangetsu (Backup Mirror)',
      streamUrl: 'https://cdn.4animo.xyz/embed/hd-1/$anilistId/$audio?k=1',
      referer: 'https://zangetsu.cc/',
      quality: '1080p Clean',
      audioType: audio == 'dub' ? 'Dub' : 'Sub',
      subtitles: effectiveSubs,
      isZeroBandwidth: true,
    ));

    return sources;
  }
}
