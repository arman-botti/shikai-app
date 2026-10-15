import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:shikai_app/services/vast_ad_service.dart';

class MidRollAdOverlay extends StatefulWidget {
  final VastAdModel ad;
  final VoidCallback onAdFinished;

  const MidRollAdOverlay({
    Key? key,
    required this.ad,
    required this.onAdFinished,
  }) : super(key: key);

  @override
  State<MidRollAdOverlay> createState() => _MidRollAdOverlayState();
}

class _MidRollAdOverlayState extends State<MidRollAdOverlay> {
  VideoPlayerController? _adController;
  bool _isAdReady = false;
  bool _canSkip = false;
  int _secondsRemaining = 5;
  Timer? _countdownTimer;
  Timer? _watchdogTimer;

  bool _firedFirstQuartile = false;
  bool _firedMidpoint = false;
  bool _firedThirdQuartile = false;
  bool _firedComplete = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.ad.skipOffsetSeconds > 0 ? widget.ad.skipOffsetSeconds : 5;

    // Safety watchdog: allow up to 15s for mobile network buffering before failing open
    _watchdogTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (!_isAdReady) {
        debugPrint('[MidRollAd] Ad video failed to load in 15s -> failing open');
        widget.onAdFinished();
      }
    });

    _initAdVideo();
  }

  void _initAdVideo() {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.ad.videoUrl),
      httpHeaders: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://shikai.biz/',
      },
    );

    _adController = controller;

    controller.initialize().then((_) {
      _watchdogTimer?.cancel();
      if (!mounted || _adController != controller) return;

      setState(() {
        _isAdReady = true;
      });

      controller.play().catchError((_) {});
      widget.ad.fireImpressions();
      widget.ad.fireTracking('start');

      _startSkipCountdown();
    }).catchError((err) {
      _watchdogTimer?.cancel();
      debugPrint('[MidRollAd] Error playing ad video: $err');
      if (mounted) widget.onAdFinished();
    });

    controller.addListener(_onAdPlaybackTick);
  }

  void _onAdPlaybackTick() {
    if (!mounted || _adController == null || !_adController!.value.isInitialized) return;

    final pos = _adController!.value.position;
    final dur = _adController!.value.duration;

    if (dur.inMilliseconds > 0) {
      final ratio = pos.inMilliseconds / dur.inMilliseconds;

      if (!_firedFirstQuartile && ratio >= 0.25) {
        _firedFirstQuartile = true;
        widget.ad.fireTracking('firstQuartile');
      }
      if (!_firedMidpoint && ratio >= 0.50) {
        _firedMidpoint = true;
        widget.ad.fireTracking('midpoint');
      }
      if (!_firedThirdQuartile && ratio >= 0.75) {
        _firedThirdQuartile = true;
        widget.ad.fireTracking('thirdQuartile');
      }
      if (!_firedComplete && (ratio >= 0.98 || pos >= dur)) {
        _firedComplete = true;
        widget.ad.fireTracking('complete');
        _completeAd();
      }
    }
  }

  void _startSkipCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        setState(() {
          _canSkip = true;
          _secondsRemaining = 0;
        });
        timer.cancel();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _handleSkip() {
    widget.ad.fireTracking('skip');
    _completeAd();
  }

  void _completeAd() {
    _countdownTimer?.cancel();
    _watchdogTimer?.cancel();
    _adController?.removeListener(_onAdPlaybackTick);
    _adController?.dispose();
    _adController = null;
    widget.onAdFinished();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _watchdogTimer?.cancel();
    _adController?.removeListener(_onAdPlaybackTick);
    _adController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Ad Video Player Layer
          if (_isAdReady && _adController != null && _adController!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _adController!.value.aspectRatio > 0
                    ? _adController!.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(_adController!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                strokeWidth: 2.5,
              ),
            ),

          // 2. Top Header Overlay (Non-intrusive metadata)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    "AD",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    "Mid-Roll Break • Shikai Partner",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Bar: Sponsor Link & Skip Button
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Sponsor Destination / Learn More Button
                if (widget.ad.clickThroughUrl != null && widget.ad.clickThroughUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () => widget.ad.handleClick(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161E).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, color: Colors.white70, size: 14),
                          SizedBox(width: 6),
                          Text(
                            "Visit Sponsor",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Glowing Crimson Skip Button
                GestureDetector(
                  onTap: _canSkip ? _handleSkip : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: _canSkip
                          ? const Color(0xFFE50914)
                          : Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _canSkip ? const Color(0xFFFF334B) : Colors.white24,
                        width: 1.2,
                      ),
                      boxShadow: _canSkip
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.55),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _canSkip ? "Skip Ad  ›" : "Skip in ${_secondsRemaining}s",
                          style: TextStyle(
                            color: _canSkip ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
