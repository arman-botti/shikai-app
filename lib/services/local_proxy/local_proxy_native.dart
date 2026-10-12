import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shikai_app/services/client_stream_proxy.dart';
import 'package:shikai_app/services/local_proxy/local_proxy_interface.dart';
import 'package:shikai_app/services/security_vault.dart';

class LocalStreamingProxyNative implements LocalStreamingProxyInterface {
  HttpServer? _server;
  int _port = 0;

  static final HttpClient _httpClient = HttpClient()
    ..idleTimeout = const Duration(seconds: 45)
    ..maxConnectionsPerHost = 15
    ..autoUncompress = true;

  static final Map<String, Uint8List> _keyCache = {};
  static final Map<String, String> _manifestCache = {};
  static final List<String> _recentSegmentOrder = [];

  @override
  bool get isRunning => _server != null;

  @override
  Future<int> start() async {
    if (_server != null) return _port;

    // Bind to local loopback address on an ephemeral port
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _listen();
    print('⚡ [Shikai In-App Proxy] Running on http://127.0.0.1:$_port (0% Server Bandwidth Mode)');
    return _port;
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  @override
  String getPlaybackUrl(String upstreamMasterUrl, {String? referer, String? key, String? audio}) {
    if (_port == 0) return upstreamMasterUrl;
    String effectiveMasterUrl = upstreamMasterUrl;
    if (!effectiveMasterUrl.startsWith('http')) {
      effectiveMasterUrl = '${SecurityVault.shikaiBase}${effectiveMasterUrl.startsWith('/') ? '' : '/'}$effectiveMasterUrl';
    }
    final ref = referer ?? ClientStreamProxy.getRefererForUrl(effectiveMasterUrl);
    final keyParam = (key != null && key.isNotEmpty) ? '&key=${Uri.encodeComponent(key)}' : '';
    final audioParam = (audio != null && audio.isNotEmpty) ? '&audio=${Uri.encodeComponent(audio)}' : '';
    return 'http://127.0.0.1:$_port/master.m3u8?url=${Uri.encodeComponent(effectiveMasterUrl)}&ref=${Uri.encodeComponent(ref)}$keyParam$audioParam';
  }

  void _listen() {
    _server?.listen((HttpRequest request) async {
      try {
        final path = request.uri.path;
        String? targetUrl = request.uri.queryParameters['url'];
        final referer = request.uri.queryParameters['ref'] ?? SecurityVault.flixReferer;
        final keyParam = request.uri.queryParameters['key'];
        String? audioParam = request.uri.queryParameters['audio']?.toLowerCase();
        if (audioParam == null && targetUrl != null) {
          final targetUri = Uri.tryParse(targetUrl);
          audioParam = targetUri?.queryParameters['audio']?.toLowerCase();
          if (audioParam == null) {
            if (targetUrl.contains('audio=dub')) {
              audioParam = 'dub';
            } else if (targetUrl.contains('audio=hindi')) {
              audioParam = 'hindi';
            } else if (targetUrl.contains('audio=sub')) {
              audioParam = 'sub';
            }
          }
        }

        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.headers.set('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        if (targetUrl == null || targetUrl.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Missing target url');
          await request.response.close();
          return;
        }

        if (!targetUrl.startsWith('http')) {
          targetUrl = '${SecurityVault.shikaiBase}${targetUrl.startsWith('/') ? '' : '/'}$targetUrl';
        }

        // ==========================================================
        // 1. MASTER PLAYLIST PROXY (Client-Side Rewrite & Decrypt)
        // ==========================================================
        if (path == '/master.m3u8') {
          final cacheKey = '$targetUrl|$keyParam|$audioParam';
          if (_manifestCache.containsKey(cacheKey)) {
            request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
            request.response.write(_manifestCache[cacheKey]!);
            await request.response.close();
            return;
          }

          final req = await _httpClient.getUrl(Uri.parse(targetUrl));
          req.headers.set(HttpHeaders.userAgentHeader, ClientStreamProxy.userAgent);
          req.headers.set(HttpHeaders.refererHeader, referer);
          req.headers.set('Origin', ClientStreamProxy.getOriginForUrl(targetUrl, referer));

          final res = await req.close().timeout(const Duration(seconds: 8));

          if (res.statusCode != HttpStatus.ok) {
            request.response.statusCode = res.statusCode;
            await request.response.close();
            return;
          }

          final rawTextStream = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
          String rawText = rawTextStream;
          // Decrypt FlixCloud Base64/XOR manifest if encrypted
          rawText = ClientStreamProxy.decryptFlixManifest(rawText, keyParam);

          final baseUrl = targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);

          final rewritten = rawText.split('\n').map((line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return line;

            // Handle #EXT-X-MEDIA:TYPE=AUDIO
            if (trimmed.startsWith('#EXT-X-MEDIA:') && trimmed.contains('TYPE=AUDIO')) {
              String lineModified = trimmed;

              // Dynamically enforce default/autoselect tags matching user's active audio mode!
              if (audioParam != null && audioParam.isNotEmpty) {
                final lineLower = trimmed.toLowerCase();
                bool isTargetAudio = false;

                if (audioParam == 'dub') {
                  // English Dub
                  isTargetAudio = lineLower.contains('language="eng"') ||
                                  lineLower.contains('language="en"') ||
                                  lineLower.contains('name="english"') ||
                                  lineLower.contains('name="eng"');
                } else if (audioParam == 'hindi') {
                  // Hindi Dub
                  isTargetAudio = lineLower.contains('language="hi"') ||
                                  lineLower.contains('language="hin"') ||
                                  lineLower.contains('name="हिन्दी"') ||
                                  lineLower.contains('name="hindi"');
                } else if (audioParam == 'sub') {
                  // Japanese Sub / Native
                  isTargetAudio = lineLower.contains('language="jpn"') ||
                                  lineLower.contains('language="ja"') ||
                                  lineLower.contains('name="native"') ||
                                  lineLower.contains('name="日本語"') ||
                                  lineLower.contains('name="japanese"');
                }

                if (isTargetAudio) {
                  lineModified = lineModified.replaceAll('DEFAULT=NO', 'DEFAULT=YES')
                                             .replaceAll('AUTOSELECT=NO', 'AUTOSELECT=YES');
                  if (!lineModified.contains('DEFAULT=')) {
                    lineModified += ',DEFAULT=YES,AUTOSELECT=YES';
                  }
                } else {
                  lineModified = lineModified.replaceAll('DEFAULT=YES', 'DEFAULT=NO')
                                             .replaceAll('AUTOSELECT=YES', 'AUTOSELECT=NO');
                }
              }

              if (lineModified.contains('URI="')) {
                return lineModified.replaceFirstMapped(RegExp(r'URI="([^"]+)"'), (m) {
                  final rawUri = m[1]!;
                  String childTarget = rawUri;
                  String childKey = keyParam ?? '';
                  String childRef = referer;

                  if (rawUri.contains('playlist-child')) {
                    final childParsed = Uri.tryParse(rawUri.startsWith('http') ? rawUri : '${SecurityVault.shikaiBase}$rawUri');
                    if (childParsed != null) {
                      childTarget = childParsed.queryParameters['url'] ?? childTarget;
                      childKey = childParsed.queryParameters['key'] ?? childKey;
                      childRef = childParsed.queryParameters['ref'] ?? childRef;
                    }
                  } else {
                    childTarget = Uri.parse(baseUrl).resolve(rawUri).toString();
                  }

                  final keyQ = childKey.isNotEmpty ? '&key=${Uri.encodeComponent(childKey)}' : '';
                  return 'URI="http://127.0.0.1:$_port/child.m3u8?url=${Uri.encodeComponent(childTarget)}&ref=${Uri.encodeComponent(childRef)}$keyQ"';
                });
              }
              return lineModified;
            }

            if (trimmed.startsWith('#EXT-X-STREAM-INF:')) {
              return line;
            }

            if (!trimmed.startsWith('#')) {
              String childTarget = trimmed;
              String childKey = keyParam ?? '';
              String childRef = referer;

              if (trimmed.contains('playlist-child')) {
                final childParsed = Uri.tryParse(trimmed.startsWith('http') ? trimmed : '${SecurityVault.shikaiBase}$trimmed');
                if (childParsed != null) {
                  childTarget = childParsed.queryParameters['url'] ?? childTarget;
                  childKey = childParsed.queryParameters['key'] ?? childKey;
                  childRef = childParsed.queryParameters['ref'] ?? childRef;
                }
              } else {
                childTarget = Uri.parse(baseUrl).resolve(trimmed).toString();
              }

              final keyQ = childKey.isNotEmpty ? '&key=${Uri.encodeComponent(childKey)}' : '';
              return 'http://127.0.0.1:$_port/child.m3u8?url=${Uri.encodeComponent(childTarget)}&ref=${Uri.encodeComponent(childRef)}$keyQ';
            }

            return line;
          }).join('\n');

          _manifestCache[cacheKey] = rewritten;
          request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          request.response.write(rewritten);
          await request.response.close();
          return;
        }

        // ==========================================================
        // 2. CHILD PLAYLIST PROXY (Extracts direct CDN chunks & prefetches)
        // ==========================================================
        if (path == '/child.m3u8') {
          final req = await _httpClient.getUrl(Uri.parse(targetUrl));
          req.headers.set(HttpHeaders.userAgentHeader, ClientStreamProxy.userAgent);
          req.headers.set(HttpHeaders.refererHeader, referer);
          req.headers.set('Origin', ClientStreamProxy.getOriginForUrl(targetUrl, referer));

          final res = await req.close().timeout(const Duration(seconds: 8));

          String rawText;
          if (res.statusCode == HttpStatus.ok) {
            rawText = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
          } else {
            // Fallback to backend playlist-child if direct request got non-200 (e.g. VidMoly IP ASN lock)
            final fallbackUrl = '${SecurityVault.shikaiBase}/api/anivexa/playlist-child?url=${Uri.encodeComponent(targetUrl)}&ref=${Uri.encodeComponent(referer)}';
            final fbReq = await _httpClient.getUrl(Uri.parse(fallbackUrl));
            final fbRes = await fbReq.close().timeout(const Duration(seconds: 10));
            if (fbRes.statusCode != HttpStatus.ok) {
              request.response.statusCode = fbRes.statusCode;
              await request.response.close();
              return;
            }
            rawText = await fbRes.transform(const Utf8Decoder(allowMalformed: true)).join();
          }

          // Decrypt FlixCloud Base64/XOR manifest if encrypted
          rawText = ClientStreamProxy.decryptFlixManifest(rawText, keyParam);

          final baseUrl = targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);
          final List<String> extractedSegUrls = [];

          final rewritten = rawText.split('\n').map((line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return line;

            // Handle Key URI
            if (trimmed.startsWith('#EXT-X-KEY:') && trimmed.contains('URI="')) {
              return trimmed.replaceFirstMapped(RegExp(r'URI="([^"]+)"'), (m) {
                final rawUri = m[1]!;
                String keyTarget = rawUri;
                String keyRef = referer;

                if (rawUri.contains('/api/anivexa/key') || rawUri.contains('key?url=')) {
                  final parsedUri = Uri.tryParse(rawUri.startsWith('http') ? rawUri : '${SecurityVault.shikaiBase}$rawUri');
                  if (parsedUri != null) {
                    keyTarget = parsedUri.queryParameters['url'] ?? keyTarget;
                    keyRef = parsedUri.queryParameters['ref'] ?? keyRef;
                  }
                } else {
                  keyTarget = Uri.parse(baseUrl).resolve(rawUri).toString();
                }

                return 'URI="http://127.0.0.1:$_port/key?url=${Uri.encodeComponent(keyTarget)}&ref=${Uri.encodeComponent(keyRef)}"';
              });
            }

            // Handle MAP URI
            if (trimmed.startsWith('#EXT-X-MAP:') && trimmed.contains('URI="')) {
              return trimmed.replaceFirstMapped(RegExp(r'URI="([^"]+)"'), (m) {
                final rawUri = m[1]!;
                String segTarget = rawUri;
                String segRef = referer;

                if (rawUri.contains('segment')) {
                  final parsedUri = Uri.tryParse(rawUri.startsWith('http') ? rawUri : '${SecurityVault.shikaiBase}$rawUri');
                  if (parsedUri != null) {
                    segTarget = parsedUri.queryParameters['url'] ?? segTarget;
                    segRef = parsedUri.queryParameters['ref'] ?? segRef;
                  }
                } else {
                  segTarget = Uri.parse(baseUrl).resolve(rawUri).toString();
                }

                return 'URI="http://127.0.0.1:$_port/seg.ts?url=${Uri.encodeComponent(segTarget)}&ref=${Uri.encodeComponent(segRef)}"';
              });
            }

            // Handle Segment TS/WebP/PNG lines
            if (!trimmed.startsWith('#')) {
              if (trimmed.contains('/api/anivexa/segment') || trimmed.contains('segment?url=')) {
                final fullSegmentUrl = trimmed.startsWith('http') ? trimmed : '${SecurityVault.shikaiBase}${trimmed.startsWith('/') ? '' : '/'}$trimmed';
                extractedSegUrls.add(fullSegmentUrl);
                return fullSegmentUrl;
              }

              String segTarget = Uri.parse(baseUrl).resolve(trimmed).toString();
              String segRef = referer;
              extractedSegUrls.add(segTarget);

              return 'http://127.0.0.1:$_port/seg.ts?url=${Uri.encodeComponent(segTarget)}&ref=${Uri.encodeComponent(segRef)}';
            }

            return line;
          }).join('\n');

          // Cache full segment sequence for continuous sliding-window prebuffering during playback
          _recentSegmentOrder
            ..clear()
            ..addAll(extractedSegUrls);

          // Eagerly prefetch the first chunk so playback starts instantly with 0ms delay
          if (extractedSegUrls.isNotEmpty) {
            final firstSeg = extractedSegUrls.first;
            ClientStreamProxy.prefetchChunk(
              chunkUrl: firstSeg,
              referer: referer,
              origin: ClientStreamProxy.getOriginForUrl(firstSeg, referer),
            );
          }

          request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          request.response.write(rewritten);
          await request.response.close();
          return;
        }

        // ==========================================================
        // 3. ENCRYPTION KEY PROXY (With RAM caching)
        // ==========================================================
        if (path == '/key') {
          if (_keyCache.containsKey(targetUrl)) {
            request.response.headers.set('Content-Type', 'application/octet-stream');
            request.response.add(_keyCache[targetUrl]!);
            await request.response.close();
            return;
          }

          final req = await _httpClient.getUrl(Uri.parse(targetUrl));
          req.headers.set(HttpHeaders.userAgentHeader, ClientStreamProxy.userAgent);
          req.headers.set(HttpHeaders.refererHeader, referer);
          req.headers.set('Origin', ClientStreamProxy.getOriginForUrl(targetUrl, referer));

          final res = await req.close().timeout(const Duration(seconds: 8));
          final builder = BytesBuilder(copy: false);
          await for (final b in res) {
            builder.add(b);
          }
          final keyBytes = builder.takeBytes();
          _keyCache[targetUrl] = keyBytes;

          request.response.headers.set('Content-Type', 'application/octet-stream');
          request.response.add(keyBytes);
          await request.response.close();
          return;
        }

        // ==========================================================
        // 4. VIDEO CHUNK SEGMENT (.ts) PROXY
        // Direct download from CDN -> Unpack WebP/PNG & XOR decrypt in RAM
        // 0% Oracle Server Bandwidth!
        // ==========================================================
        if (path == '/seg.ts') {
          // Demanded chunk takes top priority for instant delivery to ExoPlayer
          final chunkBytes = await ClientStreamProxy.fetchChunkDirectly(
            chunkUrl: targetUrl,
            referer: referer,
            origin: ClientStreamProxy.getOriginForUrl(targetUrl, referer),
          );

          if (chunkBytes == null || chunkBytes.isEmpty) {
            request.response.statusCode = HttpStatus.badGateway;
            await request.response.close();
            return;
          }

          // Smart sequential lookahead (1 chunk ahead):
          // Now that demanded chunk is retrieved, smoothly prefetch chunk i+1 in the background!
          // Zero bandwidth competition with the active chunk while keeping RAM buffer continuously warm.
          final currentIndex = _recentSegmentOrder.indexOf(targetUrl);
          if (currentIndex != -1 && currentIndex + 1 < _recentSegmentOrder.length) {
            final nextSegUrl = _recentSegmentOrder[currentIndex + 1];
            ClientStreamProxy.prefetchChunk(
              chunkUrl: nextSegUrl,
              referer: referer,
              origin: ClientStreamProxy.getOriginForUrl(nextSegUrl, referer),
            );
          }

          request.response.headers.set('Content-Type', 'video/mp2t');
          request.response.headers.set('Cache-Control', 'public, max-age=86400');
          request.response.add(chunkBytes);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (e, st) {
        print('❌ [LocalStreamingProxy] Error handling request ${request.uri}: $e\n$st');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
  }
}

LocalStreamingProxyInterface getLocalStreamingProxy() => LocalStreamingProxyNative();
