import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shikai_app/models/anivexa_episode.dart';
import 'package:shikai_app/services/anivexa_service.dart';
import 'package:shikai_app/services/stream_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/widgets/sharingan_loader.dart';

/// ---------------------------------------------------------------------------
/// SHIKAI ANIVEXA EMBEDDED PLAYER SCREEN
/// 
/// High-Performance Zero-Proxy Embedded Video Player Architecture:
/// - Official Anivexa / FlixCloud / MegaCloud Embed integration
/// - Strict Navigation Sandboxing & Built-in Ad/Popup Redirect Neutralizer
/// - Dynamic Auto-Skip Opening (?ski=1) & Audio Switching (?a=0 Sub / ?a=1 Dub)
/// - Multi-Server Failover: Server 1 (HD-2 Ultra) & Server 2 (HD-1 Mirror)
/// - Seamless Landscape Fullscreen Cinema Mode & Portrait Responsive Layout
/// - Instant Episode Switcher, Watch History Synchronization, and Seanime Tenji Design
/// ---------------------------------------------------------------------------
class PlayerScreen extends StatefulWidget {
  final int anilistId;
  final String title;
  final String coverImage;
  final int episodeNumber;
  final int totalEpisodes;
  final StreamSource? streamSource;
  final List<StreamSource>? availableSources;
  final String initialAudio;
  final List<AnivexaEpisode>? episodes;
  final String? preferredServerId;

  const PlayerScreen({
    Key? key,
    this.anilistId = 0,
    required this.title,
    this.coverImage = '',
    required this.episodeNumber,
    this.totalEpisodes = 1,
    this.streamSource,
    this.availableSources,
    this.initialAudio = 'sub',
    this.episodes,
    this.preferredServerId,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _currentEpisode;
  late String _currentAudioMode; // 'sub' | 'dub' | 'hindi'
  String _selectedServer = 'hd2'; // 'hd2' (Server 1 Ultra) | 'hd1' (Server 2 Fast)
  bool _autoSkipOpening = true;

  bool _isFullscreen = false;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  String? _currentEmbedUrl;
  String? _embedUrlHd2;
  String? _embedUrlHd1;

  List<AnivexaEpisode> _episodes = [];
  bool _hasHindiDub = false;
  bool _isLocked = false;
  bool _showOverlayControls = true;
  Timer? _overlayHideTimer;

  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episodeNumber;
    _currentAudioMode = widget.initialAudio;

    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      _episodes = List.from(widget.episodes!);
    }

    _initWebViewController();
    _loadEpisodeCatalogAndCheckHindi();
    _loadStreamForEpisode(_currentEpisode);
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _webViewController?.loadRequest(Uri.parse('about:blank'));
    // Restore normal system orientation and edge-to-edge system chrome
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _initWebViewController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted && !url.startsWith('about:blank')) {
              setState(() => _isLoading = true);
            }
          },
          onPageFinished: (String url) {
            if (mounted && !url.startsWith('about:blank')) {
              setState(() {
                _isLoading = false;
                _hasError = false;
              });
            }
            _injectPlayerStyles();
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            final host = uri.host.toLowerCase();

            // Strict Whitelist for legitimate video players, CDNs and stream gateways
            if (host.contains('flixcloud') ||
                host.contains('megacloud') ||
                host.contains('rabbitstream') ||
                host.contains('shikai.biz') ||
                host.contains('fallencdn') ||
                host.contains('rapid-cloud') ||
                host.contains('vizcloud') ||
                host.contains('vidplay') ||
                host.contains('mycloud') ||
                host.contains('vidmoly') ||
                host.contains('streamruby') ||
                request.url.startsWith('about:blank') ||
                request.url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }

            // Silently block popups, external ads, and untrusted schemes
            debugPrint('[WebView AdBlocker] Blocked intrusive redirect: ${request.url}');
            return NavigationDecision.prevent;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[WebView Resource Warning]: ${error.description}');
          },
        ),
      );

    _webViewController = controller;
  }

  void _injectPlayerStyles() {
    _webViewController?.runJavaScript('''
      (function() {
        try {
          window.open = function() { return null; };
          window.alert = function() { return null; };
          const style = document.createElement('style');
          style.innerHTML = 'html, body { background: #000000 !important; margin: 0; padding: 0; width: 100vw; height: 100vh; overflow: hidden; } iframe { border: none !important; width: 100% !important; height: 100% !important; }';
          document.head.appendChild(style);
        } catch(e) {}
      })();
    ''');
  }

  Future<void> _loadEpisodeCatalogAndCheckHindi() async {
    if (widget.anilistId <= 0) return;

    // Check Hindi dub availability
    StreamService.checkHindiAvailability(widget.anilistId).then((hasHindi) {
      if (mounted) setState(() => _hasHindiDub = hasHindi);
    }).catchError((_) {});

    // If episodes list not provided upfront, load from catalog
    if (_episodes.isEmpty) {
      try {
        final epMap = await AnivexaService.getEpisodes(widget.anilistId);
        if (mounted) {
          final list = _currentAudioMode == 'dub' ? (epMap['dub'] ?? []) : (epMap['sub'] ?? []);
          setState(() {
            _episodes = list.isNotEmpty ? list : (epMap['sub'] ?? []);
          });
        }
      } catch (_) {}
    }
  }

  String _buildEmbedUrl(String rawUrl, String audio, bool autoSkip) {
    try {
      final uri = Uri.parse(rawUrl);
      final query = Map<String, String>.from(uri.queryParameters);
      query['a'] = (audio == 'dub') ? '1' : '0';
      query['autoPlay'] = 'true';
      query['autoplay'] = 'true';
      if (autoSkip) {
        query['ski'] = '1';
      }
      return uri.replace(queryParameters: query).toString();
    } catch (_) {
      final sep = rawUrl.contains('?') ? '&' : '?';
      final skiParam = autoSkip ? '&ski=1' : '';
      return '$rawUrl${sep}a=${audio == 'dub' ? '1' : '0'}&autoPlay=true&autoplay=true$skiParam';
    }
  }

  Future<void> _loadStreamForEpisode(int episode, {String? audio, String? server}) async {
    setState(() {
      _currentEpisode = episode;
      if (audio != null) _currentAudioMode = audio;
      if (server != null) _selectedServer = server;
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    // Record progress into Watch History immediately so "Continue Watching" updates
    WatchHistoryService.saveProgress(
      anilistId: widget.anilistId,
      title: widget.title,
      coverImage: widget.coverImage,
      episodeNumber: _currentEpisode,
      positionSeconds: 120, // default active watched marker
      durationSeconds: 1440, // standard 24m anime length
      audio: _currentAudioMode,
    );

    try {
      final watchData = await AnivexaService.getWatchData(
        anilistId: widget.anilistId,
        episode: _currentEpisode,
        audio: _currentAudioMode == 'dub' ? 'dub' : 'sub',
      );

      if (!mounted) return;

      if (watchData != null && (watchData.embedUrl != null || watchData.embedUrlHd1 != null)) {
        _embedUrlHd2 = watchData.embedUrl;
        _embedUrlHd1 = watchData.embedUrlHd1;

        String? rawUrl = (_selectedServer == 'hd1' && _embedUrlHd1 != null)
            ? _embedUrlHd1
            : (_embedUrlHd2 ?? _embedUrlHd1);

        if (rawUrl != null && rawUrl.isNotEmpty) {
          _currentEmbedUrl = _buildEmbedUrl(rawUrl, _currentAudioMode, _autoSkipOpening);
          _webViewController?.loadRequest(Uri.parse(_currentEmbedUrl!));
          return;
        }
      }

      setState(() {
        _hasError = true;
        _errorMessage = "Episode $_currentEpisode stream is not available or temporarily offline. Try switching servers or choosing another episode.";
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = "Unable to connect to streaming server: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      _showOverlayControls = true;
    });

    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _scheduleOverlayHide();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer?.cancel();
    if (_isFullscreen && !_isLocked) {
      _overlayHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isFullscreen) {
          setState(() => _showOverlayControls = false);
        }
      });
    }
  }

  void _toggleOverlayControls() {
    if (_isLocked) return;
    setState(() {
      _showOverlayControls = !_showOverlayControls;
    });
    if (_showOverlayControls && _isFullscreen) {
      _scheduleOverlayHide();
    }
  }

  int get _resolvedTotalEpisodes {
    if (_episodes.isNotEmpty) return _episodes.length;
    return widget.totalEpisodes > 0 ? widget.totalEpisodes : 1;
  }

  void _playPreviousEpisode() {
    if (_currentEpisode > 1) {
      _loadStreamForEpisode(_currentEpisode - 1);
    }
  }

  void _playNextEpisode() {
    if (_currentEpisode < _resolvedTotalEpisodes) {
      _loadStreamForEpisode(_currentEpisode + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullscreen) {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: ThemeService.background,
        body: SafeArea(
          top: !_isFullscreen,
          bottom: !_isFullscreen,
          child: _isFullscreen ? _buildLandscapePlayer() : _buildPortraitLayout(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. PORTRAIT LAYOUT (Seanime Tenji Matte Carbon Visual System)
  // ---------------------------------------------------------------------------
  Widget _buildPortraitLayout() {
    return Column(
      children: [
        // Top 16:9 Video Player Container
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_webViewController != null)
                WebViewWidget(controller: _webViewController!),

              // Loading Spinner Animation
              if (_isLoading)
                Container(
                  color: Colors.black,
                  child: const Center(
                    child: SharinganLoader(
                      label: "CONNECTING ANIVEXA STREAM",
                      size: 52,
                    ),
                  ),
                ),

              // Error State Overlay
              if (_hasError)
                Container(
                  color: Colors.black.withOpacity(0.92),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: ThemeService.crimson, size: 42),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage ?? "Stream connection failed.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeService.currentAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _loadStreamForEpisode(_currentEpisode),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text("Retry Stream", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: ThemeService.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              final nextServer = _selectedServer == 'hd2' ? 'hd1' : 'hd2';
                              _loadStreamForEpisode(_currentEpisode, server: nextServer);
                            },
                            child: Text(
                              _selectedServer == 'hd2' ? "Switch to Server 2" : "Switch to Server 1",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Top Translucent Header Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        tooltip: "Back",
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "Episode $_currentEpisode",
                              style: const TextStyle(color: ThemeService.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                        tooltip: "Reload Stream",
                        onPressed: () => _loadStreamForEpisode(_currentEpisode),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                        tooltip: "Fullscreen",
                        onPressed: _toggleFullscreen,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Scrollable Below-Player Controls & Episodes Selector
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Anime Title & Episode Bar
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "Streaming via Anivexa • Episode $_currentEpisode of $_resolvedTotalEpisodes",
                            style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _buildCinemaButton(),
                  ],
                ),

                const SizedBox(height: 14),

                // Episode Quick Jump Row (Prev / Next)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: ThemeService.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: _currentEpisode > 1 ? _playPreviousEpisode : null,
                          icon: const Icon(Icons.chevron_left, size: 18),
                          label: const Text("Previous", style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: ThemeService.currentAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ThemeService.currentAccent.withOpacity(0.4)),
                        ),
                        child: Text(
                          "EP $_currentEpisode",
                          style: TextStyle(
                            color: ThemeService.currentAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeService.currentAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: _currentEpisode < _resolvedTotalEpisodes ? _playNextEpisode : null,
                          icon: const Text("Next", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          label: const Icon(Icons.chevron_right, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Audio Language Switcher (Sub / Dub / Hindi)
                const Text(
                  "AUDIO TRACK",
                  style: TextStyle(
                    color: ThemeService.textDarkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPill(
                      label: "🇯🇵 Japanese Sub",
                      isSelected: _currentAudioMode == 'sub',
                      onTap: () {
                        if (_currentAudioMode != 'sub') {
                          _loadStreamForEpisode(_currentEpisode, audio: 'sub');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildPill(
                      label: "🇺🇸 English Dub",
                      isSelected: _currentAudioMode == 'dub',
                      onTap: () {
                        if (_currentAudioMode != 'dub') {
                          _loadStreamForEpisode(_currentEpisode, audio: 'dub');
                        }
                      },
                    ),
                    if (_hasHindiDub) ...[
                      const SizedBox(width: 8),
                      _buildPill(
                        label: "🇮🇳 Hindi Dub",
                        isSelected: _currentAudioMode == 'hindi',
                        onTap: () {
                          if (_currentAudioMode != 'hindi') {
                            _loadStreamForEpisode(_currentEpisode, audio: 'hindi');
                          }
                        },
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // Server Switcher Row (HD-2 vs HD-1)
                const Text(
                  "STREAMING SERVER",
                  style: TextStyle(
                    color: ThemeService.textDarkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildPill(
                      label: "⚡ Server 1 (HD-2 Ultra)",
                      isSelected: _selectedServer == 'hd2',
                      onTap: () {
                        if (_selectedServer != 'hd2') {
                          _loadStreamForEpisode(_currentEpisode, server: 'hd2');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildPill(
                      label: "🚀 Server 2 (HD-1 Fast)",
                      isSelected: _selectedServer == 'hd1',
                      onTap: () {
                        if (_selectedServer != 'hd1') {
                          _loadStreamForEpisode(_currentEpisode, server: 'hd1');
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Auto-Skip Opening Intro Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.fast_forward_rounded, color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Auto-Skip Opening Intro",
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Switch(
                        value: _autoSkipOpening,
                        activeColor: ThemeService.currentAccent,
                        onChanged: (val) {
                          setState(() => _autoSkipOpening = val);
                          _loadStreamForEpisode(_currentEpisode);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Episodes Grid Browser
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "EPISODES ($_resolvedTotalEpisodes)",
                      style: const TextStyle(
                        color: ThemeService.textDarkMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      "Active: Ep $_currentEpisode",
                      style: TextStyle(color: ThemeService.currentAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                _buildEpisodesGrid(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. LANDSCAPE FULLSCREEN CINEMA LAYOUT
  // ---------------------------------------------------------------------------
  Widget _buildLandscapePlayer() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleOverlayControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Underlying Hardware Accelerated WebView Player
          if (_webViewController != null)
            WebViewWidget(controller: _webViewController!),

          // Loading Animation
          if (_isLoading)
            Container(
              color: Colors.black,
              child: const Center(
                child: SharinganLoader(
                  label: "CONNECTING ANIVEXA STREAM",
                  size: 64,
                ),
              ),
            ),

          // Error Overlay
          if (_hasError)
            Container(
              color: Colors.black.withOpacity(0.92),
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: ThemeService.crimson, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage ?? "Playback error",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: ThemeService.currentAccent),
                          onPressed: () => _loadStreamForEpisode(_currentEpisode),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text("Retry"),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: _toggleFullscreen,
                          child: const Text("Exit Fullscreen"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Floating Controls Overlay (Visible when tapped, auto-hides after 4s)
          if (_showOverlayControls)
            IgnorePointer(
              ignoring: _isLocked,
              child: AnimatedOpacity(
                opacity: _showOverlayControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black.withOpacity(0.40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                              onPressed: _toggleFullscreen,
                              tooltip: "Exit Fullscreen",
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    "Episode $_currentEpisode • ${_selectedServer.toUpperCase()}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),

                            // Sub/Dub Quick Toggle
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                final nextAudio = _currentAudioMode == 'dub' ? 'sub' : 'dub';
                                _loadStreamForEpisode(_currentEpisode, audio: nextAudio);
                              },
                              icon: const Icon(Icons.audiotrack, size: 14),
                              label: Text(_currentAudioMode.toUpperCase(), style: const TextStyle(fontSize: 12)),
                            ),

                            const SizedBox(width: 8),

                            // Server Quick Toggle
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                final nextServer = _selectedServer == 'hd2' ? 'hd1' : 'hd2';
                                _loadStreamForEpisode(_currentEpisode, server: nextServer);
                              },
                              icon: const Icon(Icons.dns, size: 14),
                              label: Text(_selectedServer.toUpperCase(), style: const TextStyle(fontSize: 12)),
                            ),

                            const SizedBox(width: 8),

                            // Fullscreen Exit
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 28),
                              onPressed: _toggleFullscreen,
                              tooltip: "Exit Fullscreen",
                            ),
                          ],
                        ),
                      ),

                      // Bottom Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _currentEpisode > 1 ? _playPreviousEpisode : null,
                              icon: const Icon(Icons.skip_previous, size: 18),
                              label: const Text("Previous Ep"),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: ThemeService.currentAccent.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: ThemeService.currentAccent),
                              ),
                              child: Text(
                                "EPISODE $_currentEpisode / $_resolvedTotalEpisodes",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ThemeService.currentAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _currentEpisode < _resolvedTotalEpisodes ? _playNextEpisode : null,
                              icon: const Text("Next Ep"),
                              label: const Icon(Icons.skip_next, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating Screen Lock Button (Bottom Left)
          if (_showOverlayControls || _isLocked)
            Positioned(
              left: 20,
              bottom: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isLocked = !_isLocked;
                    _showOverlayControls = !_isLocked;
                  });
                  if (!_isLocked) _scheduleOverlayHide();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isLocked ? ThemeService.crimson : Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Icon(
                    _isLocked ? Icons.lock : Icons.lock_open,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. UI HELPER WIDGETS
  // ---------------------------------------------------------------------------
  Widget _buildCinemaButton() {
    return GestureDetector(
      onTap: _toggleFullscreen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ThemeService.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ThemeService.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.crop_free, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              "Cinema",
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({required String label, required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? ThemeService.currentAccent.withOpacity(0.18) : ThemeService.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? ThemeService.currentAccent : ThemeService.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : ThemeService.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodesGrid() {
    final count = _resolvedTotalEpisodes;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (context, index) {
        final epNum = index + 1;
        final isCurrent = epNum == _currentEpisode;

        return GestureDetector(
          onTap: () {
            if (!isCurrent) {
              _loadStreamForEpisode(epNum);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isCurrent ? ThemeService.currentAccent : ThemeService.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrent ? ThemeService.currentAccent : ThemeService.border,
                width: isCurrent ? 1.5 : 1.0,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: ThemeService.currentAccent.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                "$epNum",
                style: TextStyle(
                  color: isCurrent ? Colors.white : ThemeService.textMuted,
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
