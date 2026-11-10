import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/services/moviebox_service.dart';
import 'package:shikai_app/services/subtitle_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:video_player/video_player.dart';

/// ---------------------------------------------------------------------------
/// ON-DEVICE MOVIE PLAYER
/// Direct MP4 playback from MovieBox CDN with quality switching and subtitles.
/// ---------------------------------------------------------------------------
class MoviePlayerScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<MovieboxStream> streams;
  final String subjectId;
  final int season;
  final int episode;

  const MoviePlayerScreen({
    Key? key,
    required this.title,
    required this.streams,
    required this.subjectId,
    this.subtitle,
    this.season = 0,
    this.episode = 0,
  }) : super(key: key);

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  VideoPlayerController? _controller;
  int _streamIndex = 0;
  int _generation = 0;

  bool _isInitializing = true;
  String? _error;
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _hideTimer;

  List<MovieboxCaption> _captions = [];
  MovieboxCaption? _selectedCaption;
  List<SubtitleCue> _cues = [];
  bool _isLoadingSubtitles = false;
  double _subtitleSize = 16;
  Color _subtitleColor = Colors.white;
  bool _subtitlesEnabled = true;
  String _preferredLang = 'en';

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _sortStreams();
    _bootstrapSubtitles();
    _initController(_streams.first);
  }

  Future<void> _bootstrapSubtitles() async {
    await _loadSubtitleSettings();
    await _loadCaptions();
  }

  List<MovieboxStream> get _streams => widget.streams;

  void _sortStreams() {
    widget.streams.sort((a, b) {
      final q = b.qualityValue.compareTo(a.qualityValue);
      if (q != 0) return q;
      final d = (b.durationSec ?? 0).compareTo(a.durationSec ?? 0);
      if (d != 0) return d;
      final ah = (a.codec ?? '').toLowerCase().contains('h264');
      final bh = (b.codec ?? '').toLowerCase().contains('h264');
      if (ah == bh) return 0;
      return ah ? -1 : 1;
    });
  }

  Future<void> _loadSubtitleSettings() async {
    try {
      final settings = await SubtitleService.getSubtitleSettings();
      if (!mounted) return;
      setState(() {
        _subtitleSize = (settings['size'] as double?) ?? 16;
        _subtitleColor = (settings['color'] as Color?) ?? Colors.white;
        _subtitlesEnabled = (settings['enabled'] as bool?) ?? true;
        _preferredLang = (settings['lang'] as String?) ?? 'en';
      });
    } catch (_) {}
  }

  Future<void> _loadCaptions() async {
    try {
      final caps = await MovieboxService.getCaptions(
        widget.subjectId,
        season: widget.season,
        episode: widget.episode,
      );
      if (!mounted) return;
      setState(() => _captions = caps);

      if (caps.isNotEmpty && _subtitlesEnabled) {
        final preferred = caps.where((c) => c.code == _preferredLang).toList();
        final english = caps.where((c) => c.code == 'en').toList();
        final chosen = preferred.isNotEmpty
            ? preferred.first
            : (english.isNotEmpty ? english.first : caps.first);
        _selectCaption(chosen);
      }
    } catch (_) {}
  }

  Future<void> _selectCaption(MovieboxCaption? caption) async {
    if (caption == null) {
      if (mounted) {
        setState(() {
          _selectedCaption = null;
          _cues = [];
        });
      }
      return;
    }

    setState(() {
      _selectedCaption = caption;
      _isLoadingSubtitles = true;
    });

    final cues = await SubtitleService.loadSubtitles(caption.url, lang: caption.code);
    if (!mounted) return;
    setState(() {
      _cues = cues;
      _isLoadingSubtitles = false;
    });

    if (cues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${caption.language} subtitle load nahi hui')),
      );
    }
  }

  Future<void> _initController(MovieboxStream stream) async {
    final generation = ++_generation;
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onTick);
      await previous.dispose();
      _controller = null;
    }

    if (mounted) {
      setState(() {
        _isInitializing = true;
        _error = null;
      });
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(stream.url),
        httpHeaders: stream.headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        rethrow;
      }

      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }

      controller.addListener(_onTick);
      await controller.play();

      setState(() {
        _controller = controller;
        _isInitializing = false;
        _duration = controller.value.duration;
        _isPlaying = controller.value.isPlaying;
      });
      _scheduleHide();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isInitializing = false;
        _error = 'Video load nahi hui. Doosri quality try karo.\n$e';
      });
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final value = controller.value;
    final pos = value.position;
    final shouldRebuild = (pos - _position).inMilliseconds.abs() >= 300 ||
        value.isPlaying != _isPlaying ||
        value.isBuffering != _isBuffering ||
        value.duration != _duration;

    if (shouldRebuild) {
      setState(() {
        _position = pos;
        _duration = value.duration;
        _isPlaying = value.isPlaying;
        _isBuffering = value.isBuffering;
      });
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    } else {
      await controller.play();
      _scheduleHide();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final controller = _controller;
    if (controller == null) return;
    final target = controller.value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await controller.seekTo(clamped);
    _scheduleHide();
  }

  Future<void> _seekTo(double milliseconds) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.seekTo(Duration(milliseconds: milliseconds.round()));
  }

  Future<void> _switchQuality(int index) async {
    if (index == _streamIndex) return;
    final previousPosition = _position;
    final wasPlaying = _isPlaying;
    _streamIndex = index;
    await _initController(_streams[index]);
    final controller = _controller;
    if (controller != null && previousPosition > Duration.zero) {
      await controller.seekTo(previousPosition);
      if (wasPlaying) await controller.play();
    }
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  SubtitleCue? get _activeCue {
    if (_cues.isEmpty || _selectedCaption == null) return null;
    final seconds = _position.inMilliseconds / 1000.0;
    for (final cue in _cues) {
      if (seconds >= cue.start && seconds <= cue.end + 0.2) return cue;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoLayer(),
            if (_showControls) _buildTopBar(),
            if (_showControls) _buildCenterControls(),
            if (_showControls) _buildBottomBar(),
            if (_isInitializing) _buildLoadingOverlay(),
            if (_error != null) _buildErrorOverlay(),
            _buildSubtitleOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoLayer() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ThemeService.crimson),
            SizedBox(height: 16),
            Text(
              'Streaming from MovieBox...',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white38, size: 46),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ThemeService.crimson),
                onPressed: () => _initController(_streams[_streamIndex]),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 6,
          right: 6,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.75), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: _toggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _circleButton(
            icon: Icons.replay_10,
            size: 22,
            onTap: () => _seekRelative(-10),
          ),
          const SizedBox(width: 26),
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 26),
          _circleButton(
            icon: Icons.forward_10,
            size: 22,
            onTap: () => _seekRelative(10),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({required IconData icon, required double size, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _buildBottomBar() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final valueMs = (_dragValue ?? _position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 20,
          bottom: MediaQuery.of(context).padding.bottom + 10,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.85), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: ThemeService.crimson,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: ThemeService.crimson.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: valueMs,
                      max: maxMs > 0 ? maxMs : 1,
                      onChangeStart: (_) {
                        _hideTimer?.cancel();
                        if (mounted) setState(() => _showControls = true);
                      },
                      onChanged: (value) => setState(() => _dragValue = value),
                      onChangeEnd: (value) {
                        _dragValue = null;
                        _seekTo(value);
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusPill(
                      icon: _isBuffering ? Icons.hourglass_bottom : Icons.hd_outlined,
                      label: _isBuffering
                          ? 'Buffering'
                          : (_controller?.value.isInitialized == true
                              ? _streams[_streamIndex].quality
                              : 'Loading'),
                      color: _isBuffering ? Colors.amberAccent : const Color(0xFF10B981),
                    ),
                  ),
                ),
                _actionChip(
                  icon: Icons.high_quality_outlined,
                  label: 'Quality',
                  onTap: _showQualitySheet,
                ),
                const SizedBox(width: 8),
                _actionChip(
                  icon: Icons.subtitles_outlined,
                  label: _selectedCaption == null ? 'Subs' : _selectedCaption!.code.toUpperCase(),
                  onTap: _showSubtitleSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitleOverlay() {
    final cue = _activeCue;
    if (cue == null) return const SizedBox.shrink();

    return Positioned(
      left: 20,
      right: 20,
      bottom: _showControls ? 132 : 34,
      child: IgnorePointer(
        child: Text(
          cue.text.replaceAll(RegExp(r'<[^>]*>'), ''),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _subtitleColor,
            fontSize: _subtitleSize,
            height: 1.35,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1.5, 1.5)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(-1.5, 1.5)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1.5, -1.5)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(-1.5, -1.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeService.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Video Quality',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            ...List.generate(_streams.length, (index) {
              final stream = _streams[index];
              final selected = index == _streamIndex;
              return ListTile(
                dense: true,
                leading: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? ThemeService.crimson : ThemeService.textDarkMuted,
                  size: 20,
                ),
                title: Text(
                  stream.quality,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  [
                    if (stream.sizeMb > 0) '${stream.sizeMb.toStringAsFixed(0)} MB',
                    if (stream.codec != null) stream.codec!.toUpperCase(),
                    if (stream.durationSec != null) _formatDuration(Duration(seconds: stream.durationSec!)),
                  ].join(' • '),
                  style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 10.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _switchQuality(index);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSubtitleSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeService.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Subtitles',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            if (_isLoadingSubtitles)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: ThemeService.crimson, strokeWidth: 2),
              )
            else ...[
              ListTile(
                dense: true,
                leading: Icon(
                  _selectedCaption == null ? Icons.check_circle : Icons.circle_outlined,
                  color: _selectedCaption == null ? ThemeService.crimson : ThemeService.textDarkMuted,
                  size: 20,
                ),
                title: const Text('Off', style: TextStyle(color: Colors.white70, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _selectCaption(null);
                },
              ),
              if (_captions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No subtitles available',
                    style: TextStyle(color: ThemeService.textMuted, fontSize: 12),
                  ),
                )
              else
                ..._captions.map(
                  (cap) => ListTile(
                    dense: true,
                    leading: Icon(
                      _selectedCaption?.url == cap.url ? Icons.check_circle : Icons.circle_outlined,
                      color: _selectedCaption?.url == cap.url
                          ? ThemeService.crimson
                          : ThemeService.textDarkMuted,
                      size: 20,
                    ),
                    title: Text(
                      cap.language,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    trailing: Text(
                      cap.code.toUpperCase(),
                      style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 10),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _selectCaption(cap);
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
