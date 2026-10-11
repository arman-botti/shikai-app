import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shikai_app/services/stream_service.dart';
import 'package:shikai_app/services/subtitle_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/services/anivexa_service.dart';
import 'package:shikai_app/services/security_vault.dart';
import 'package:shikai_app/models/anivexa_episode.dart';
import 'package:shikai_app/widgets/sharingan_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  StreamSource? _currentSource;
  late int _currentEpisode;
  late String _currentAudioMode;
  List<StreamSource> _availableSources = [];

  bool _isLoadingStream = false;
  bool _hasStartedPlayback = false;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _bufferingWatchdog;
  Timer? _initTimeoutTimer;

  // Controls Visibility & Auto-hide
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _isLocked = false;
  bool _isFullscreen = false;

  // Episodes List
  List<AnivexaEpisode> _episodes = [];
  bool _showEpisodesDrawer = false;
  bool _hasHindiDub = false;

  // Double-tap Seek Animation
  String? _seekRippleText;
  Alignment _seekRippleAlign = Alignment.center;
  Timer? _seekRippleTimer;

  // Gestures (Brightness / Volume HUD)
  double _volume = 1.0;
  double _brightness = 0.5;
  String? _hudType; // 'volume' or 'brightness'
  double _hudValue = 0.5;
  Timer? _hudTimer;

  // Subtitle Engine
  List<SubtitleTrack> _subtitles = [];
  int _selectedSubtitleIndex = -1;
  bool _subtitlesEnabled = true;
  double _subtitleSize = 16.0;
  double _subtitleOffset = 0.0;
  Color _subtitleColor = Colors.white;
  bool _subtitleBackground = true;
  List<SubtitleCue> _currentCues = [];
  String _currentCueText = '';

  // Playback Settings
  double _playbackSpeed = 1.0;

  bool get _isControllerReady => _controller != null && _controller!.value.isInitialized;

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episodeNumber;
    _currentAudioMode = widget.initialAudio;
    _currentSource = widget.streamSource;
    _availableSources = widget.availableSources != null ? List.from(widget.availableSources!) : (_currentSource != null ? [_currentSource!] : []);

    if (widget.streamSource != null) {
      _subtitles = SubtitleService.cleanSubtitleTracks(widget.streamSource!.subtitles);
    }

    // Dynamic orientations: default to portrait mode with 16:9 box + episodes below
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _isFullscreen = false;

    // Check Hindi dub availability
    if (widget.anilistId > 0) {
      StreamService.checkHindiAvailability(widget.anilistId).then((hasHindi) {
        if (mounted && hasHindi) setState(() => _hasHindiDub = true);
      });
    }

    // Load persisted subtitle offset and styling preferences
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      final savedOffset = prefs.getDouble('shikai_sub_offset_${widget.anilistId}') ??
          prefs.getDouble('shikai_global_sub_offset') ??
          0.0;
      final savedSize = prefs.getDouble('shikai_sub_font_size');
      final savedColor = prefs.getInt('shikai_sub_color_val');
      final savedBg = prefs.getBool('shikai_sub_bg');
      setState(() {
        _subtitleOffset = savedOffset;
        if (savedSize != null) _subtitleSize = savedSize;
        if (savedColor != null) _subtitleColor = Color(savedColor);
        if (savedBg != null) _subtitleBackground = savedBg;
      });
    }).catchError((_) {});

    // Load Episodes for drawer and portrait selector
    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      _episodes = List.from(widget.episodes!);
    } else if (widget.anilistId > 0) {
      AnivexaService.getEpisodes(widget.anilistId).then((epMap) {
        if (mounted) {
          final list = _currentAudioMode == 'dub' ? (epMap['dub'] ?? []) : (epMap['sub'] ?? []);
          setState(() => _episodes = list.isNotEmpty ? list : (epMap['sub'] ?? []));
        }
      });
    }

    if (widget.streamSource != null) {
      _initPlayer();
    } else {
      _resolveAndStartPlayback();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _seekRippleTimer?.cancel();
    _hudTimer?.cancel();
    _bufferingWatchdog?.cancel();
    _initTimeoutTimer?.cancel();
    _controller?.removeListener(_videoPlayerListener);
    _controller?.dispose();

    // Reset system UI and orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _resolveAndStartPlayback() async {
    setState(() {
      _isLoadingStream = true;
      _hasError = false;
      _errorMessage = null;
    });

    final encodedTitle = Uri.encodeComponent(widget.title);

    // ==============================================================
    // PRE-POPULATE SERVER SOURCES UPFRONT (AniKoto Primary -> AniZone -> Fallbacks)
    // ==============================================================
    final instantKoto = StreamSource(
      id: 'anikoto',
      serverName: 'Bankai • Koto (Ultra 1080p)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/anivexa/stream/${widget.anilistId}/$_currentEpisode.m3u8?server=anikoto&audio=$_currentAudioMode&title=$encodedTitle',
      referer: 'https://megaplay.buzz/',
      quality: '1080p Ultra HD',
      audioType: _currentAudioMode == 'dub' ? 'English Dub' : 'Japanese Sub',
      introStart: 30,
      introEnd: 115,
      isZeroBandwidth: true,
    );

    final instantZone = StreamSource(
      id: 'anizone',
      serverName: 'Shikai • Zone (Adaptive HQ)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/anivexa/stream/${widget.anilistId}/$_currentEpisode.m3u8?server=anizone&audio=$_currentAudioMode&title=$encodedTitle',
      referer: SecurityVault.anizoneReferer,
      quality: '1080p / 720p Adaptive',
      audioType: _currentAudioMode == 'dub' ? 'English Dub' : 'Japanese Sub',
      introStart: 30,
      introEnd: 115,
      isZeroBandwidth: true,
    );

    final instantTsukuyomi = StreamSource(
      id: 'anivexa',
      serverName: 'Tsukuyomi (HD-2 Direct)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/anivexa/stream/${widget.anilistId}/$_currentEpisode.m3u8?server=hd2&audio=$_currentAudioMode&title=$encodedTitle',
      referer: SecurityVault.flixReferer,
      quality: '1080p Direct Master',
      audioType: _currentAudioMode == 'dub' ? 'English Dub' : 'Japanese Sub',
      introStart: 30,
      introEnd: 115,
      isZeroBandwidth: true,
    );

    final instantKamui = StreamSource(
      id: 'reanime',
      serverName: 'Kamui (HD-1 Fast)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/anivexa/stream/${widget.anilistId}/$_currentEpisode.m3u8?server=hd1&audio=$_currentAudioMode&title=$encodedTitle',
      referer: SecurityVault.flixReferer,
      quality: '1080p Fast Mirror',
      audioType: _currentAudioMode == 'dub' ? 'English Dub' : 'Japanese Sub',
      introStart: 30,
      introEnd: 115,
      isZeroBandwidth: true,
    );

    final instantMiruro = StreamSource(
      id: 'miruro',
      serverName: 'Rinnegan (Global HD)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/miruro/stream/${widget.anilistId}/$_currentEpisode.m3u8?audio=$_currentAudioMode&title=$encodedTitle',
      referer: SecurityVault.flixReferer,
      quality: '1080p Global Direct',
      audioType: _currentAudioMode == 'dub' ? 'English Dub' : 'Japanese Sub',
      isZeroBandwidth: true,
    );

    final instantHindi = StreamSource(
      id: 'desidub',
      serverName: 'Chidori (Hindi Dub 🇮🇳)',
      streamUrl: '${StreamService.shikaiBaseUrl}/api/desidub/stream/${widget.anilistId}/$_currentEpisode',
      referer: SecurityVault.vidmolyReferer,
      quality: '720p HD Hindi',
      audioType: 'Hindi Dub',
      isZeroBandwidth: true,
    );

    final initialList = <StreamSource>[
      instantKoto,       // 1. AniKoto (Primary)
      instantZone,       // 2. AniZone (Secondary)
      instantTsukuyomi,  // 3. HD-2 Direct
      instantKamui,      // 4. HD-1 Mirror
      instantMiruro,     // 5. Miruro Global
    ];
    if (_currentAudioMode == 'hindi') {
      initialList.insert(0, instantHindi);
    } else {
      initialList.add(instantHindi);
    }

    _availableSources = initialList;

    final preferred = widget.preferredServerId?.toLowerCase();
    if (_currentAudioMode == 'hindi' || preferred == 'desidub') {
      _currentSource = instantHindi;
    } else if (preferred != null) {
      _currentSource = initialList.firstWhere(
        (s) => s.id.toLowerCase() == preferred,
        orElse: () => instantKoto,
      );
    } else {
      _currentSource = instantKoto; // Primary server is Bankai • Koto!
    }

    // Immediately start video player with Primary AniKoto stream (<200ms)!
    _initPlayer();

    // Early Subtitle Fetch: fetch official subtitles immediately in parallel
    if (widget.anilistId > 0) {
      StreamService.fetchSubtitles(widget.anilistId, _currentEpisode).then((subs) {
        if (!mounted || subs.isEmpty) return;
        setState(() {
          _subtitles = SubtitleService.cleanSubtitleTracks([
            ..._subtitles,
            ...subs,
          ]);
          if (_currentSource != null) {
            _currentSource = _currentSource!.copyWith(subtitles: _subtitles);
          }
        });
        if (_subtitles.isNotEmpty && (_selectedSubtitleIndex == -1 || _currentCues.isEmpty)) {
          _initSubtitles();
        }
      }).catchError((_) {});
    }

    // Resolve full server mirrors and subtitle tracks in background
    try {
      final sources = await StreamService.resolveStreamsForEpisode(
        anilistId: widget.anilistId,
        episode: _currentEpisode,
        title: widget.title,
        audio: _currentAudioMode,
      );

      if (!mounted) return;

      if (sources.isNotEmpty) {
        _availableSources = sources;

        if (_controller == null) {
          _currentSource = sources.firstWhere(
            (s) => _currentAudioMode == 'hindi'
                ? s.id == 'desidub'
                : (_currentAudioMode == 'dub'
                    ? s.audioType.toLowerCase().contains('dub')
                    : !s.audioType.toLowerCase().contains('dub')),
            orElse: () => sources.first,
          );
          _subtitles = SubtitleService.cleanSubtitleTracks([
            ..._currentSource!.subtitles,
            ..._subtitles,
          ]);
          _currentSource = _currentSource!.copyWith(subtitles: _subtitles);
          _initPlayer();
        } else {
          // Seamlessly attach extracted subtitles and server playlist keys
          final matched = sources.firstWhere(
            (s) => s.id == _currentSource?.id,
            orElse: () => sources.first,
          );
          if (mounted) {
            setState(() {
              _subtitles = SubtitleService.cleanSubtitleTracks([
                ...matched.subtitles,
                ..._subtitles,
              ]);
              _currentSource = matched.copyWith(subtitles: _subtitles);
            });
            if (_subtitles.isNotEmpty && (_selectedSubtitleIndex == -1 || _currentCues.isEmpty)) {
              _initSubtitles();
            }
          }
        }
      } else if (_controller == null) {
        setState(() {
          _isLoadingStream = false;
          _hasError = true;
          _errorMessage = "No active stream found for Episode $_currentEpisode.";
        });
      }
    } catch (e) {
      debugPrint('[Player] Metadata resolution background error: $e');
      if (_controller == null && mounted) {
        setState(() {
          _isLoadingStream = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _initPlayer({Duration? seekToPosition}) {
    if (_currentSource == null) return;

    _initTimeoutTimer?.cancel();
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _hasStartedPlayback = false;

    setState(() {
      _isLoadingStream = true;
      _hasError = false;
      _errorMessage = null;
      _currentCueText = '';
    });

    _controller?.removeListener(_videoPlayerListener);
    _controller?.dispose();

    final clientPlaybackUrl = StreamService.getClientSideStreamUrl(
      _currentSource!.streamUrl,
      referer: _currentSource!.referer ?? _currentSource!.headers['Referer'],
      key: _currentSource!.playlistKey,
      audio: _currentAudioMode,
    );

    final isHls = _currentSource!.type.toLowerCase() == 'hls' ||
        clientPlaybackUrl.contains('.m3u8') ||
        clientPlaybackUrl.contains('/stream/');

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(clientPlaybackUrl),
      formatHint: isHls ? VideoFormat.hls : null,
      httpHeaders: {
        ..._currentSource!.headers,
        if (_currentSource!.referer != null) 'Referer': _currentSource!.referer!,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
    );

    _controller = controller;

    // 15-Second Connection Timeout Watchdog: relaxed so slow CDNs/mobile networks have ample time to establish stream
    _initTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _controller != controller) return;
      if (_isLoadingStream && !_hasStartedPlayback) {
        debugPrint('[Player] Connection timed out on ${_currentSource?.serverName} (15s) -> triggering smart failover');
        _failoverToNextSource('Connection timed out (15s)');
      }
    });

    controller.initialize().then((_) async {
      _initTimeoutTimer?.cancel();
      if (!mounted || _controller != controller) return;

      setState(() {
        _isLoadingStream = false;
        _hasError = false;
      });

      controller.play().catchError((_) {});
      _hasStartedPlayback = true;
      controller.setPlaybackSpeed(_playbackSpeed);
      _scheduleControlsHide();

      // Resume from previous position if provided (seamless swap) or from watch history
      if (seekToPosition != null && seekToPosition > Duration.zero) {
        controller.seekTo(seekToPosition);
      } else if (widget.anilistId > 0) {
        WatchHistoryService.getContinueWatching().then((history) {
          if (!mounted || _controller != controller) return;
          final match = history.where((h) => h.anilistId == widget.anilistId && h.episodeNumber == _currentEpisode).toList();
          if (match.isNotEmpty && match.first.positionSeconds > 10 && match.first.progressPercentage < 0.90) {
            controller.seekTo(Duration(seconds: match.first.positionSeconds));
          }
        });
      }

      _initSubtitles();
    }).catchError((error) {
      _initTimeoutTimer?.cancel();
      if (!mounted || _controller != controller) return;
      debugPrint('[Player] Error initializing ${_currentSource?.serverName}: $error');
      if (!_hasStartedPlayback) {
        _failoverToNextSource(error.toString());
      }
    });

    controller.addListener(_videoPlayerListener);
  }

  void _failoverToNextSource([String? reason]) {
    _initTimeoutTimer?.cancel();
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;

    // RELAXED FALLBACK: Fallback is strictly restricted to INITIAL video startup/loading.
    // If the episode has already started playing, NEVER switch servers automatically mid-playback
    // or during skipping/seeking!
    if (_hasStartedPlayback) {
      debugPrint('[Player] Playback already active. Suppressing automatic server swap on event: $reason');
      return;
    }

    final currentIndex = _availableSources.indexWhere((s) => s.id == _currentSource?.id);
    if (currentIndex >= 0 && currentIndex + 1 < _availableSources.length) {
      final nextSource = _availableSources[currentIndex + 1];
      debugPrint('[Player] Smart Failover: ${_currentSource?.serverName} failed ($reason) -> switching to ${nextSource.serverName}');

      // Preserve current playback progress for seamless swap
      Duration lastPosition = Duration.zero;
      if (_controller != null && _controller!.value.isInitialized) {
        lastPosition = _controller!.value.position;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚡ Fallback: Swapped to ${nextSource.serverName}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E202E),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _currentSource = nextSource;
        });
        _initPlayer(seekToPosition: lastPosition);
      }
    } else {
      setState(() {
        _isLoadingStream = false;
        _hasError = true;
        _errorMessage = reason ?? "All streaming servers failed for Episode $_currentEpisode.";
      });
    }
  }

  void _videoPlayerListener() {
    if (!mounted || !_isControllerReady) return;

    // Detect when video has actually started playing
    if (!_hasStartedPlayback && (_controller!.value.isPlaying || _controller!.value.position > Duration.zero)) {
      _hasStartedPlayback = true;
      _initTimeoutTimer?.cancel();
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
    }

    // Runtime error detection for automatic smart failover - ONLY during initial startup!
    if (_controller!.value.hasError) {
      debugPrint('[Player] Runtime playback error in ${_currentSource?.serverName}: ${_controller!.value.errorDescription}');
      if (!_hasStartedPlayback) {
        _failoverToNextSource(_controller!.value.errorDescription);
      }
      return;
    }

    // Mid-playback buffering: Buffering during seeking/skipping or network variation is normal video behavior.
    // We cancel any watchdog once playback has started so it never kills the working stream!
    if (_hasStartedPlayback) {
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
    } else if (_controller!.value.isBuffering) {
      // Relaxed 15-second watchdog ONLY during initial startup if stream is completely frozen before first play
      _bufferingWatchdog ??= Timer(const Duration(seconds: 15), () {
        if (mounted && _controller != null && !_hasStartedPlayback && _controller!.value.isBuffering && !_controller!.value.isPlaying) {
          debugPrint('[Player] Initial startup buffering stalled > 15s on ${_currentSource?.serverName} -> failover');
          _failoverToNextSource('Initial stream stalled while buffering');
        }
      });
    } else {
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
    }

    // Subtitle cue matching
    if (_subtitlesEnabled && _currentCues.isNotEmpty) {
      final currentSec = (_controller!.value.position.inMilliseconds / 1000.0) - _subtitleOffset;
      final matching = _currentCues.where((c) => currentSec >= c.start && currentSec <= c.end).toList();
      final newText = SubtitleService.cleanAndDeduplicateSubtitleLines(matching);
      if (newText != _currentCueText) {
        setState(() => _currentCueText = newText);
      }
    } else if (_currentCueText.isNotEmpty && (!_subtitlesEnabled || _currentCues.isEmpty)) {
      setState(() => _currentCueText = '');
    }

    // Save watch progress periodically
    if (_controller!.value.isPlaying) {
      final posSec = _controller!.value.position.inSeconds;
      final durSec = _controller!.value.duration.inSeconds;
      if (posSec > 0 && durSec > 0 && posSec % 5 == 0) {
        WatchHistoryService.saveProgress(
          anilistId: widget.anilistId,
          title: widget.title,
          coverImage: widget.coverImage,
          episodeNumber: _currentEpisode,
          positionSeconds: posSec,
          durationSeconds: durSec,
          audio: _currentAudioMode,
        );
      }
    }

    setState(() {});
  }

  void _initSubtitles() async {
    if (_currentSource == null) return;
    final sourceSubs = SubtitleService.cleanSubtitleTracks(_currentSource!.subtitles);
    if (sourceSubs.isNotEmpty) {
      _subtitles = sourceSubs;
    }

    // If still empty, fetch directly from Shikai subtitle endpoint
    if (_subtitles.isEmpty && widget.anilistId > 0) {
      final fetched = await StreamService.fetchSubtitles(widget.anilistId, _currentEpisode);
      if (fetched.isNotEmpty && mounted) {
        _subtitles = SubtitleService.cleanSubtitleTracks(fetched);
        _currentSource = _currentSource?.copyWith(subtitles: _subtitles);
      }
    }

    if (_subtitles.isEmpty) {
      setState(() {
        _selectedSubtitleIndex = -1;
        _currentCues = [];
        _currentCueText = '';
      });
      return;
    }

    // Subtitle Race: Concurrently evaluates candidate tracks to pick the fastest full dialogue track!
    final raceWinner = await SubtitleService.raceForBestTrack(
      _subtitles,
      rawCandidates: _currentSource?.subtitles ?? _subtitles,
      preferredLang: 'en',
    );

    if (!mounted) return;

    if (raceWinner != null) {
      setState(() {
        _selectedSubtitleIndex = raceWinner.index;
        _currentCues = raceWinner.cues;
      });
    } else {
      _selectSubtitleTrack(0);
    }
  }

  void _selectSubtitleTrack(int index) async {
    if (index < 0 || index >= _subtitles.length) {
      setState(() {
        _selectedSubtitleIndex = -1;
        _currentCues = [];
        _currentCueText = '';
      });
      return;
    }

    setState(() => _selectedSubtitleIndex = index);
    final track = _subtitles[index];

    // If candidate has siblings for the same language, race them to get the cleanest & fullest version!
    final raceWinner = await SubtitleService.raceForBestTrack(
      [track],
      rawCandidates: _currentSource?.subtitles ?? [],
      preferredLang: track.language,
    );

    if (mounted) {
      if (raceWinner != null && raceWinner.cues.isNotEmpty) {
        setState(() => _currentCues = raceWinner.cues);
      } else {
        final cues = await SubtitleService.loadSubtitles(track.url, lang: track.language);
        if (mounted) setState(() => _currentCues = cues);
      }
    }
  }

  void _togglePlayPause() {
    if (!_isControllerReady) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _showControls = true;
        _controlsTimer?.cancel();
      } else {
        _controller!.play();
        _scheduleControlsHide();
      }
    });
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _isControllerReady && _controller!.value.isPlaying && !_isLocked && !_showEpisodesDrawer) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      return;
    }
    setState(() {
      _showControls = !_showControls;
      if (_showControls && _isControllerReady && _controller!.value.isPlaying) {
        _scheduleControlsHide();
      }
    });
  }

  void _seekRelative(int seconds) {
    if (!_isControllerReady) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    final clamped = Duration(
      seconds: target.inSeconds.clamp(0, _controller!.value.duration.inSeconds),
    );
    _controller!.seekTo(clamped);

    _showSeekRipple(seconds > 0 ? "+${seconds}s" : "${seconds}s", seconds > 0 ? Alignment.centerRight : Alignment.centerLeft);
  }

  void _showSeekRipple(String text, Alignment alignment) {
    _seekRippleTimer?.cancel();
    setState(() {
      _seekRippleText = text;
      _seekRippleAlign = alignment;
    });
    _seekRippleTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekRippleText = null);
    });
  }

  void _handleVerticalDrag(DragUpdateDetails details, bool isLeftHalf) {
    final delta = -details.primaryDelta! / 200.0;
    if (isLeftHalf) {
      setState(() {
        _brightness = (_brightness + delta).clamp(0.0, 1.0);
        _hudType = 'brightness';
        _hudValue = _brightness;
      });
    } else {
      setState(() {
        _volume = (_volume + delta).clamp(0.0, 1.0);
        _controller?.setVolume(_volume);
        _hudType = 'volume';
        _hudValue = _volume;
      });
    }

    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _hudType = null);
    });
  }

  void _switchEpisode(int epNum) {
    if (epNum == _currentEpisode) return;

    setState(() {
      _currentEpisode = epNum;
      _showEpisodesDrawer = false;
    });

    _controller?.pause();
    _controller?.removeListener(_videoPlayerListener);
    _controller?.dispose();
    _controller = null;

    _resolveAndStartPlayback();
  }

  void _switchAudio(String mode) {
    if (mode == _currentAudioMode) return;
    setState(() {
      _currentAudioMode = mode;
    });

    _controller?.pause();
    _controller?.removeListener(_videoPlayerListener);
    _controller?.dispose();
    _controller = null;

    _resolveAndStartPlayback();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return "${duration.inHours}:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait || !_isFullscreen;

    return PopScope(
      canPop: !_showEpisodesDrawer,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showEpisodesDrawer) {
          setState(() => _showEpisodesDrawer = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: isPortrait ? _buildPortraitLayout() : _buildLandscapeLayout(),
      ),
    );
  }

  // ==============================================================
  // PORTRAIT LAYOUT: Clean 16:9 Video Box on Top + Episode List Below
  // Zero spillage, zero overflow, perfectly contained!
  // ==============================================================
  Widget _buildPortraitLayout() {
    return SafeArea(
      top: true,
      bottom: true,
      child: Column(
        children: [
          // 1. Contained 16:9 Video Surface & Controls
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoSurface(),
                  _buildGesturesLayer(),
                  if (_seekRippleText != null) _buildSeekRipple(),
                  if (_hudType != null) _buildHudOverlay(),
                  if (_subtitlesEnabled && _currentCueText.isNotEmpty) _buildSubtitlesOverlay(isPortrait: true),
                  // In-Player Sharingan Preloader
                  if (_isLoadingStream || (_isControllerReady && _controller!.value.isBuffering))
                    const Center(child: SharinganLoader(size: 42, showLabel: false)),
                  if (_hasError) _buildErrorCard(),
                  // Animated Controls Overlay
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.transparent,
                              Colors.black.withOpacity(0.9),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(isPortrait: true)),
                            if (!_isLocked && !_isLoadingStream && !(_isControllerReady && _controller!.value.isBuffering))
                              Center(child: _buildCenterControls(isPortrait: true)),
                            if (!_isLocked)
                              Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar(isPortrait: true)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Below Video in Portrait: Info Header & Scrollable Episodes List
          Expanded(
            child: _buildPortraitDetailsAndEpisodes(),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // LANDSCAPE LAYOUT: Fullscreen Immersive Netflix / AnymeX Experience
  // ==============================================================
  Widget _buildLandscapeLayout() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoSurface(),
        _buildGesturesLayer(),
        if (_seekRippleText != null) _buildSeekRipple(),
        if (_hudType != null) _buildHudOverlay(),
        if (_subtitlesEnabled && _currentCueText.isNotEmpty) _buildSubtitlesOverlay(isPortrait: false),
        // In-Player Sharingan Preloader
        if (_isLoadingStream || (_isControllerReady && _controller!.value.isBuffering))
          const Center(child: SharinganLoader(size: 54, showLabel: false)),
        if (_hasError) _buildErrorCard(),
        // Animated Controls Overlay
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                    Colors.black.withOpacity(0.9),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(isPortrait: false)),
                  if (!_isLocked && !_isLoadingStream && !(_isControllerReady && _controller!.value.isBuffering))
                    Center(child: _buildCenterControls(isPortrait: false)),
                  Positioned(left: 16, top: 0, bottom: 0, child: _buildLockButton()),
                  if (!_isLocked)
                    Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar(isPortrait: false)),
                ],
              ),
            ),
          ),
        ),
        // Episodes Slide-in Drawer (from right)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          right: _showEpisodesDrawer ? 0 : -320,
          width: 300,
          child: _buildEpisodesDrawer(),
        ),
      ],
    );
  }

  // Video Surface
  Widget _buildVideoSurface() {
    return Center(
      child: _isControllerReady
          ? AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            )
          : Container(color: Colors.black),
    );
  }

  // Gestures Layer
  Widget _buildGesturesLayer() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          if (_isLocked) return;
          final width = MediaQuery.of(context).size.width;
          final x = details.localPosition.dx;
          if (x < width * 0.4) {
            _seekRelative(-10);
          } else if (x > width * 0.6) {
            _seekRelative(10);
          } else {
            _togglePlayPause();
          }
        },
        onVerticalDragUpdate: (details) {
          if (_isLocked) return;
          final width = MediaQuery.of(context).size.width;
          final isLeft = details.localPosition.dx < width * 0.5;
          _handleVerticalDrag(details, isLeft);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(color: Colors.transparent),
      ),
    );
  }

  // Double-tap Seek Ripple Feedback
  Widget _buildSeekRipple() {
    return Align(
      alignment: _seekRippleAlign,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _seekRippleAlign == Alignment.centerRight ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 2),
            Text(
              _seekRippleText!,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Volume / Brightness / Subtitle Sync HUD Overlay
  Widget _buildHudOverlay() {
    if (_hudType == 'sub_sync') {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ThemeService.currentAccent.withOpacity(0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_rounded, color: ThemeService.currentAccent, size: 22),
              const SizedBox(width: 10),
              Text(
                "Subtitle Sync: ${_subtitleOffset > 0 ? '+' : ''}${_subtitleOffset.toStringAsFixed(1)}s${_subtitleOffset < 0 ? ' (Earlier)' : (_subtitleOffset > 0 ? ' (Later)' : ' (Synced)')}",
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hudType == 'volume'
                  ? (_hudValue == 0 ? Icons.volume_off : Icons.volume_up)
                  : Icons.brightness_6,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _hudValue,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(ThemeService.currentAccent),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${(_hudValue * 100).round()}%",
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
  }

  // Subtitle Rendering Overlay
  Widget _buildSubtitlesOverlay({required bool isPortrait}) {
    final effectiveSize = isPortrait ? (_subtitleSize * 0.85).clamp(11.5, 20.0) : _subtitleSize;
    return Positioned(
      left: 16,
      right: 16,
      bottom: isPortrait ? 42 : (_showControls ? 88 : 28),
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: _subtitleBackground
                ? BoxDecoration(
                    color: Colors.black.withOpacity(0.70),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              _currentCueText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _subtitleColor,
                fontSize: effectiveSize,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
                  Shadow(offset: Offset(-1, -1), blurRadius: 3, color: Colors.black),
                  Shadow(offset: Offset(1, -1), blurRadius: 3, color: Colors.black),
                  Shadow(offset: Offset(-1, 1), blurRadius: 3, color: Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Playback Error Card
  Widget _buildErrorCard() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeService.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 38),
            const SizedBox(height: 10),
            const Text(
              "Playback Error",
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? "Stream connection failed.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: ThemeService.currentAccent),
                  onPressed: _resolveAndStartPlayback,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text("Retry"),
                ),
                if (_availableSources.length > 1) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: ThemeService.border),
                    ),
                    onPressed: () {
                      final currIdx = _availableSources.indexWhere((s) => s.id == _currentSource?.id);
                      final nextIdx = (currIdx + 1) % _availableSources.length;
                      setState(() => _currentSource = _availableSources[nextIdx]);
                      _initPlayer();
                    },
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text("Next Mirror"),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Top Bar
  Widget _buildTopBar({required bool isPortrait}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isPortrait ? 4 : 8),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 15),
            ),
            onPressed: () {
              if (!isPortrait) {
                _toggleFullscreen();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: isPortrait ? 13 : 14.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Episode $_currentEpisode • ${_currentAudioMode.toUpperCase()} • ${_currentSource?.serverName ?? 'Auto'}",
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_isLocked) ...[
            if (!isPortrait) ...[
              // Landscape Episodes Drawer Button
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.video_library_outlined, size: 14),
                label: const Text("Episodes", style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() => _showEpisodesDrawer = true),
              ),
              const SizedBox(width: 6),
            ],
            // Quick Subtitle Button
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _subtitlesEnabled ? ThemeService.currentAccent.withOpacity(0.3) : Colors.black45,
                  shape: BoxShape.circle,
                  border: _subtitlesEnabled ? Border.all(color: ThemeService.currentAccent, width: 1.2) : null,
                ),
                child: Icon(
                  _subtitlesEnabled ? Icons.subtitles : Icons.subtitles_off_outlined,
                  color: _subtitlesEnabled ? ThemeService.currentAccent : Colors.white70,
                  size: 17,
                ),
              ),
              tooltip: "Subtitles",
              onPressed: _showSubtitleSettingsModal,
            ),
            // Settings Gear Button
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.settings_outlined, color: Colors.white, size: 17),
              ),
              onPressed: _showSettingsSheet,
            ),
          ],
        ],
      ),
    );
  }

  // Center Playback Controls
  Widget _buildCenterControls({required bool isPortrait}) {
    final isPlaying = _isControllerReady && _controller!.value.isPlaying;
    final iconScale = isPortrait ? 28.0 : 38.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: iconScale,
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white70),
          onPressed: () => _seekRelative(-10),
        ),
        SizedBox(width: isPortrait ? 18 : 28),
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            padding: EdgeInsets.all(isPortrait ? 12 : 16),
            decoration: BoxDecoration(
              color: ThemeService.currentAccent.withOpacity(0.92),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ThemeService.currentAccent.withOpacity(0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: isPortrait ? 30 : 40,
            ),
          ),
        ),
        SizedBox(width: isPortrait ? 18 : 28),
        IconButton(
          iconSize: iconScale,
          icon: const Icon(Icons.forward_10_rounded, color: Colors.white70),
          onPressed: () => _seekRelative(10),
        ),
      ],
    );
  }

  // Lock Button (Landscape)
  Widget _buildLockButton() {
    return Center(
      child: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isLocked ? ThemeService.currentAccent : Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: Colors.white,
            size: 17,
          ),
        ),
        onPressed: () {
          setState(() {
            _isLocked = !_isLocked;
            if (!_isLocked) _scheduleControlsHide();
          });
        },
      ),
    );
  }

  // Bottom Bar Scrubber & Time
  Widget _buildBottomBar({required bool isPortrait}) {
    final position = _isControllerReady ? _controller!.value.position : Duration.zero;
    final duration = _isControllerReady ? _controller!.value.duration : Duration.zero;

    // Calculate maximum pre-buffered position for the white buffer line
    double maxBufferedSeconds = 0.0;
    if (_isControllerReady) {
      for (final range in _controller!.value.buffered) {
        final endSec = range.end.inMilliseconds / 1000.0;
        if (endSec > maxBufferedSeconds) {
          maxBufferedSeconds = endSec;
        }
      }
    }
    final totalSec = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final posSec = position.inSeconds.toDouble().clamp(0.0, totalSec);
    final secondarySec = maxBufferedSeconds.clamp(posSec, totalSec);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isPortrait ? 2 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrubber with YouTube-style White Pre-Buffer Track
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: ThemeService.currentAccent,
              activeTrackColor: ThemeService.currentAccent,
              secondaryActiveTrackColor: Colors.white.withOpacity(0.65), // Pre-buffer white line
              inactiveTrackColor: Colors.white24,
              trackHeight: isPortrait ? 2.8 : 3.2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: isPortrait ? 4.5 : 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: isPortrait ? 9 : 12),
            ),
            child: Slider(
              value: posSec,
              secondaryTrackValue: secondarySec,
              min: 0.0,
              max: totalSec,
              onChanged: (val) {
                _controller?.seekTo(Duration(seconds: val.round()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(color: Colors.white, fontSize: isPortrait ? 10.5 : 11.5, fontWeight: FontWeight.bold),
                ),
                Text(" / ", style: TextStyle(color: Colors.white38, fontSize: isPortrait ? 10 : 11)),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: Colors.white60, fontSize: isPortrait ? 10.5 : 11.5),
                ),
                const Spacer(),
                // Audio Switch Pill
                GestureDetector(
                  onTap: _showAudioSelectorModal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.audiotrack, color: ThemeService.currentAccent, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          _currentAudioMode.toUpperCase(),
                          style: TextStyle(
                            color: ThemeService.currentAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Fullscreen Button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isPortrait ? Icons.fullscreen : Icons.fullscreen_exit,
                    color: Colors.white,
                    size: isPortrait ? 22 : 24,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Portrait Episode List & Details underneath the 16:9 video box
  Widget _buildPortraitDetailsAndEpisodes() {
    final total = _episodes.isNotEmpty ? _episodes.length : widget.totalEpisodes;

    return Container(
      color: const Color(0xFF0C0E14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Anime Title & Episode Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                      onPressed: _showSettingsSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ThemeService.currentAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ThemeService.currentAccent.withOpacity(0.4)),
                      ),
                      child: Text(
                        "EP $_currentEpisode",
                        style: TextStyle(color: ThemeService.currentAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Audio Mode Pill
                    GestureDetector(
                      onTap: _showAudioSelectorModal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.audiotrack, color: ThemeService.currentAccent, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              _currentAudioMode.toUpperCase(),
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Subtitles Pill
                    GestureDetector(
                      onTap: _showSubtitleSettingsModal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _subtitlesEnabled ? ThemeService.currentAccent.withOpacity(0.18) : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _subtitlesEnabled ? ThemeService.currentAccent.withOpacity(0.4) : Colors.white12,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _subtitlesEnabled ? Icons.subtitles : Icons.subtitles_off_outlined,
                              color: _subtitlesEnabled ? ThemeService.currentAccent : Colors.white54,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _subtitlesEnabled
                                  ? (_selectedSubtitleIndex >= 0 && _selectedSubtitleIndex < _subtitles.length
                                      ? _subtitles[_selectedSubtitleIndex].label
                                      : "SUBTITLES")
                                  : "OFF",
                              style: TextStyle(
                                color: _subtitlesEnabled ? ThemeService.currentAccent : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          // Episodes header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Episodes ($total)",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Tap to switch",
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          // Scrollable Episodes List
          Expanded(
            child: _episodes.isEmpty
                ? Center(
                    child: Text(
                      "Episode list loading...",
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _episodes.length,
                    itemBuilder: (context, index) {
                      final ep = _episodes[index];
                      final isSelected = ep.number == _currentEpisode;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? ThemeService.currentAccent.withOpacity(0.15) : const Color(0xFF141722),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? ThemeService.currentAccent : Colors.white.withOpacity(0.06),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: Container(
                            width: 36,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? ThemeService.currentAccent : Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${ep.number}",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            ep.title.isNotEmpty ? ep.title : "Episode ${ep.number}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.play_arrow, color: ThemeService.currentAccent, size: 20)
                              : const Icon(Icons.play_circle_outline, color: Colors.white30, size: 18),
                          onTap: () => _switchEpisode(ep.number),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Landscape Slide-in Drawer
  Widget _buildEpisodesDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E14).withOpacity(0.95),
        border: const Border(left: BorderSide(color: Colors.white12)),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 20)],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Episodes",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => setState(() => _showEpisodesDrawer = false),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _episodes.isEmpty
                  ? Center(
                      child: Text(
                        "Episode list unavailable",
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final ep = _episodes[index];
                        final isSelected = ep.number == _currentEpisode;
                        return Container(
                          color: isSelected ? ThemeService.currentAccent.withOpacity(0.15) : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? ThemeService.currentAccent : Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${ep.number}",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              ep.title.isNotEmpty ? ep.title : "Episode ${ep.number}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected ? Icon(Icons.play_arrow, color: ThemeService.currentAccent, size: 18) : null,
                            onTap: () => _switchEpisode(ep.number),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Playback Settings Sheet
  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Playback Settings", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Speed
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed, color: Colors.white70),
                  title: const Text("Speed", style: TextStyle(color: Colors.white)),
                  trailing: Text("${_playbackSpeed}x", style: TextStyle(color: ThemeService.currentAccent, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _cycleSpeed();
                  },
                ),
                // Subtitles
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.subtitles_outlined, color: Colors.white70),
                  title: const Text("Subtitles", style: TextStyle(color: Colors.white)),
                  trailing: Text(
                    !_subtitlesEnabled
                        ? "Off"
                        : (_selectedSubtitleIndex >= 0 && _selectedSubtitleIndex < _subtitles.length
                            ? _subtitles[_selectedSubtitleIndex].label
                            : "Auto"),
                    style: TextStyle(color: ThemeService.currentAccent, fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSubtitleSettingsModal();
                  },
                ),
                // Audio Language
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language, color: Colors.white70),
                  title: const Text("Audio Language", style: TextStyle(color: Colors.white)),
                  trailing: Text(_currentAudioMode.toUpperCase(), style: TextStyle(color: ThemeService.currentAccent, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAudioSelectorModal();
                  },
                ),
                // Streaming Server
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dns_outlined, color: Colors.white70),
                  title: const Text("Streaming Server", style: TextStyle(color: Colors.white)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ThemeService.currentAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ThemeService.currentAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      _currentSource?.serverName ?? "Auto",
                      style: TextStyle(color: ThemeService.currentAccent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showServerSwitchModal();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showServerSwitchModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.dns_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 8),
                      Text("SELECT STREAMING SERVER", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ..._availableSources.map((source) {
                    final isSelected = source.id == _currentSource?.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? ThemeService.currentAccent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? ThemeService.currentAccent : Colors.white10,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          source.id == 'anikoto'
                              ? Icons.bolt_rounded
                              : (source.id == 'anizone'
                                  ? Icons.waves_rounded
                                  : (source.id == 'anivexa'
                                      ? Icons.remove_red_eye_rounded
                                      : (source.id == 'reanime'
                                          ? Icons.speed_rounded
                                          : (source.id == 'miruro'
                                              ? Icons.public_rounded
                                              : (source.id == 'desidub'
                                                  ? Icons.translate_rounded
                                                  : Icons.stream_rounded))))),
                          color: isSelected ? ThemeService.currentAccent : Colors.white70,
                        ),
                        title: Text(
                          source.serverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.85),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          source.quality,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isSelected ? ThemeService.currentAccent.withOpacity(0.8) : Colors.white38, fontSize: 11),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle_rounded, color: ThemeService.currentAccent, size: 20)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          if (!isSelected) {
                            setState(() {
                              _currentSource = source;
                            });
                            _initPlayer();
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _cycleSpeed() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    final nextSpeed = speeds[nextIndex];
    setState(() => _playbackSpeed = nextSpeed);
    _controller?.setPlaybackSpeed(nextSpeed);
  }

  void _showSubtitleSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.subtitles, color: ThemeService.currentAccent, size: 22),
                            const SizedBox(width: 10),
                            const Text(
                              "Subtitle Settings",
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Section 1: Track Selection (All Countries Supported + Auto-Race)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "TRACK SELECTION (ALL COUNTRIES)",
                          style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, color: Color(0xFF10B981), size: 12),
                              SizedBox(width: 3),
                              Text(
                                "Fast Clean Cues",
                                style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Off chip
                        ChoiceChip(
                          label: const Text("Off"),
                          selected: !_subtitlesEnabled,
                          selectedColor: ThemeService.currentAccent.withOpacity(0.2),
                          backgroundColor: ThemeService.surface,
                          side: BorderSide(
                            color: !_subtitlesEnabled ? ThemeService.currentAccent : ThemeService.border,
                          ),
                          labelStyle: TextStyle(
                            color: !_subtitlesEnabled ? ThemeService.currentAccent : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setState(() => _subtitlesEnabled = false);
                            setModalState(() {});
                          },
                        ),
                        // Track chips
                        ...List.generate(_subtitles.length, (i) {
                          final track = _subtitles[i];
                          final isSelected = _subtitlesEnabled && _selectedSubtitleIndex == i;
                          return ChoiceChip(
                            label: Text(track.label),
                            selected: isSelected,
                            selectedColor: ThemeService.currentAccent.withOpacity(0.2),
                            backgroundColor: ThemeService.surface,
                            side: BorderSide(
                              color: isSelected ? ThemeService.currentAccent : ThemeService.border,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected ? ThemeService.currentAccent : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            onSelected: (val) {
                              setState(() => _subtitlesEnabled = true);
                              _selectSubtitleTrack(i);
                              setModalState(() {});
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section 2: Font Size
                    const Text(
                      "FONT SIZE",
                      style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final entry in [
                          {'label': 'Small', 'size': 13.0},
                          {'label': 'Medium', 'size': 16.0},
                          {'label': 'Large', 'size': 19.0},
                          {'label': 'Extra', 'size': 22.0},
                        ]) ...[
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final s = entry['size'] as double;
                                setState(() => _subtitleSize = s);
                                setModalState(() {});
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _subtitleSize == entry['size']
                                      ? ThemeService.currentAccent.withOpacity(0.2)
                                      : ThemeService.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _subtitleSize == entry['size']
                                        ? ThemeService.currentAccent
                                        : ThemeService.border,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    entry['label'] as String,
                                    style: TextStyle(
                                      color: _subtitleSize == entry['size']
                                          ? ThemeService.currentAccent
                                          : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section 3: Text Color
                    const Text(
                      "TEXT COLOR",
                      style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final c in [
                          {'color': Colors.white, 'name': 'White'},
                          {'color': const Color(0xFFFFEB3B), 'name': 'Yellow'},
                          {'color': const Color(0xFF00E5FF), 'name': 'Cyan'},
                          {'color': const Color(0xFF69F0AE), 'name': 'Green'},
                        ]) ...[
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final col = c['color'] as Color;
                                setState(() => _subtitleColor = col);
                                setModalState(() {});
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: ThemeService.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _subtitleColor == c['color']
                                        ? ThemeService.currentAccent
                                        : ThemeService.border,
                                    width: _subtitleColor == c['color'] ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: c['color'] as Color,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black26),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      c['name'] as String,
                                      style: TextStyle(
                                        color: _subtitleColor == c['color'] ? Colors.white : Colors.white60,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section 4: Sync Timing Offset Calibration
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "TIMING CALIBRATION",
                              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "- = Earlier, + = Later",
                              style: TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ThemeService.currentAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ThemeService.currentAccent.withOpacity(0.35)),
                          ),
                          child: Text(
                            "${_subtitleOffset >= 0 ? '+' : ''}${_subtitleOffset.toStringAsFixed(1)}s${_subtitleOffset < 0 ? ' (Earlier)' : (_subtitleOffset > 0 ? ' (Later)' : '')}",
                            style: TextStyle(
                              color: ThemeService.currentAccent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildOffsetBtn(
                          label: "-0.5s",
                          sublabel: "Earlier",
                          onTap: () {
                            _updateSubtitleOffset(_subtitleOffset - 0.5);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildOffsetBtn(
                          label: "-0.1s",
                          onTap: () {
                            _updateSubtitleOffset(_subtitleOffset - 0.1);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeService.surface,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: ThemeService.border),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              _updateSubtitleOffset(0.0);
                              setModalState(() {});
                            },
                            child: const Text("Reset", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildOffsetBtn(
                          label: "+0.1s",
                          onTap: () {
                            _updateSubtitleOffset(_subtitleOffset + 0.1);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildOffsetBtn(
                          label: "+0.5s",
                          sublabel: "Later",
                          onTap: () {
                            _updateSubtitleOffset(_subtitleOffset + 0.5);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Section 5: Background Box Switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: ThemeService.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ThemeService.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Dark Text Backing",
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Semi-transparent box for contrast",
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                          Switch(
                            value: _subtitleBackground,
                            activeColor: ThemeService.currentAccent,
                            onChanged: (val) {
                              setState(() => _subtitleBackground = val);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateSubtitleOffset(double newOffset) {
    final clamped = double.parse(newOffset.clamp(-15.0, 15.0).toStringAsFixed(1));
    setState(() {
      _subtitleOffset = clamped;
      _hudType = 'sub_sync';
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _hudType == 'sub_sync') {
        setState(() => _hudType = null);
      }
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('shikai_sub_offset_${widget.anilistId}', clamped);
      prefs.setDouble('shikai_global_sub_offset', clamped);
    }).catchError((_) {});
  }

  Widget _buildOffsetBtn({required String label, String? sublabel, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: ThemeService.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ThemeService.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: TextStyle(color: ThemeService.currentAccent, fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11131A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Select Audio Track", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text("Japanese (Original Sub)", style: TextStyle(color: Colors.white)),
                  trailing: _currentAudioMode == 'sub' ? Icon(Icons.check, color: ThemeService.currentAccent) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _switchAudio('sub');
                  },
                ),
                ListTile(
                  title: const Text("English (Dub)", style: TextStyle(color: Colors.white)),
                  trailing: _currentAudioMode == 'dub' ? Icon(Icons.check, color: ThemeService.currentAccent) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _switchAudio('dub');
                  },
                ),
                if (_hasHindiDub)
                  ListTile(
                    title: const Text("Hindi (Desi Dub 🇮🇳)", style: TextStyle(color: Colors.white)),
                    trailing: _currentAudioMode == 'hindi' ? Icon(Icons.check, color: ThemeService.currentAccent) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchAudio('hindi');
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
