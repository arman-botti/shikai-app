import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/manga_chapter.dart';
import 'package:shikai_app/services/manga_service.dart';
import 'package:shikai_app/services/manga_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/widgets/sharingan_loader.dart';
import 'package:shikai_app/widgets/smart_manga_image.dart';

enum MangaReaderMode { webtoon, horizontal }

class MangaReaderScreen extends StatefulWidget {
  final AnilistMedia manga;
  final List<MangaChapter> chapters;
  final int initialChapterIndex;
  final int initialPage;

  const MangaReaderScreen({
    Key? key,
    required this.manga,
    required this.chapters,
    required this.initialChapterIndex,
    this.initialPage = 0,
  }) : super(key: key);

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  late int _currentChapterIndex;
  List<String> _pageUrls = [];
  bool _isLoadingPages = true;
  String? _errorMessage;

  // Reader Settings
  MangaReaderMode _readerMode = MangaReaderMode.webtoon;
  int _currentPage = 0;
  bool _showControls = true;

  // Controllers
  late PageController _pageController;
  final ScrollController _webtoonScrollController = ScrollController();

  // Webtoon precise page tracking & restoration
  final Map<int, GlobalKey> _pageKeys = {};
  Timer? _saveDebounceTimer;
  bool _isInitialScrollDone = false;

  MangaChapter get currentChapter => widget.chapters[_currentChapterIndex];

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);
    _webtoonScrollController.addListener(_onWebtoonScroll);

    // Enter fullscreen for immersive reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadChapterPages();
  }

  @override
  void dispose() {
    _webtoonScrollController.removeListener(_onWebtoonScroll);
    _saveDebounceTimer?.cancel();
    _saveProgress(); // Ensure latest reading position is persisted
    _pageController.dispose();
    _webtoonScrollController.dispose();
    // Restore normal system overlays
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SmartMangaImage.clearCache();
    super.dispose();
  }

  void _onWebtoonScroll() {
    if (!_webtoonScrollController.hasClients || _pageUrls.isEmpty) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final viewThreshold = screenHeight * 0.45;
    int? detectedPage;

    // Scan through mounted page keys to find which page spans the viewing area
    for (int i = 0; i < _pageUrls.length; i++) {
      final key = _pageKeys[i];
      final ctx = key?.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          final top = pos.dy;
          final bottom = top + box.size.height;
          if (top <= viewThreshold && bottom > 80) {
            detectedPage = i;
            break;
          }
        }
      }
    }

    if (detectedPage != null && detectedPage != _currentPage) {
      setState(() {
        _currentPage = detectedPage!;
      });
      _prefetchUpcomingPages(_currentPage);
      _saveProgressThrottled();
    }
  }

  void _saveProgressThrottled() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _saveProgress();
      }
    });
  }

  void _scrollToInitialPageWebtoon(int targetPage) {
    if (targetPage <= 0 || targetPage >= _pageUrls.length) return;

    void attemptScroll(int attemptsLeft) {
      if (!mounted || !_webtoonScrollController.hasClients || attemptsLeft <= 0) return;

      final key = _pageKeys[targetPage];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0);
        return;
      }

      final maxScroll = _webtoonScrollController.position.maxScrollExtent;
      final current = _webtoonScrollController.offset;
      final screenH = MediaQuery.of(context).size.height;
      final step = (screenH * 1.2) * (targetPage - _currentPage).clamp(1, 8);
      final nextOffset = (current + step).clamp(0.0, maxScroll);

      if (nextOffset > current) {
        _webtoonScrollController.jumpTo(nextOffset);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final foundCtx = _pageKeys[targetPage]?.currentContext;
        if (foundCtx != null) {
          Scrollable.ensureVisible(foundCtx, alignment: 0.0);
        } else if (attemptsLeft > 1) {
          attemptScroll(attemptsLeft - 1);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attemptScroll(10));
  }

  void _jumpToWebtoonPage(int targetPage) {
    if (!_webtoonScrollController.hasClients || targetPage < 0 || targetPage >= _pageUrls.length) return;
    final ctx = _pageKeys[targetPage]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollToInitialPageWebtoon(targetPage);
    }
  }

  Future<void> _loadChapterPages() async {
    setState(() {
      _isLoadingPages = true;
      _errorMessage = null;
      _pageUrls = [];
    });

    try {
      final pages = await MangaService.getChapterPages(
        currentChapter.id,
        chapterUrl: currentChapter.url,
        source: currentChapter.source ?? widget.manga.sourceId,
      );
      if (!mounted) return;

      if (pages.isEmpty) {
        setState(() {
          _isLoadingPages = false;
          _errorMessage = "No pages found for this chapter.";
        });
      } else {
        setState(() {
          _pageUrls = pages;
          _isLoadingPages = false;
        });

        // Prefetch first few pages
        _prefetchUpcomingPages(_currentPage);

        // Save progress
        _saveProgress();

        // Restore initial page in webtoon mode if initialPage > 0
        if (_currentPage > 0 && _readerMode == MangaReaderMode.webtoon && !_isInitialScrollDone) {
          _isInitialScrollDone = true;
          _scrollToInitialPageWebtoon(_currentPage);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPages = false;
        _errorMessage = "Failed to load chapter pages.";
      });
    }
  }

  void _prefetchUpcomingPages(int currentIndex) {
    for (int i = 1; i <= 4; i++) {
      final nextIdx = currentIndex + i;
      if (nextIdx < _pageUrls.length) {
        final nextUrl = _pageUrls[nextIdx];
        SmartMangaImage.prefetch(nextUrl, _getImageHeaders(nextUrl));
      }
    }
  }

  void _saveProgress() {
    MangaHistoryService.saveReadingProgress(
      anilistId: widget.manga.id,
      title: widget.manga.displayTitle,
      coverImage: widget.manga.coverImage,
      chapterId: currentChapter.id,
      chapterNumber: currentChapter.chapterNumber,
      pageIndex: _currentPage,
      totalPages: _pageUrls.isNotEmpty ? _pageUrls.length : 1,
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _switchChapter(int newIndex) {
    if (newIndex >= 0 && newIndex < widget.chapters.length) {
      if (_webtoonScrollController.hasClients) {
        _webtoonScrollController.jumpTo(0);
      }
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      SmartMangaImage.clearCache();
      _pageKeys.clear();
      _isInitialScrollDone = false;
      setState(() {
        _currentChapterIndex = newIndex;
        _currentPage = 0;
      });
      _loadChapterPages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveProgress();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // 1. Reading Canvas
              if (_isLoadingPages)
                const Center(
                  child: SharinganLoader(size: 60, showLabel: true),
                )
              else if (_errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: ThemeService.currentAccent),
                          onPressed: _loadChapterPages,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text("Retry"),
                        ),
                      ],
                    ),
                  ),
                )
              else
                _buildReaderView(),

              // 2. Subtle Floating Page Indicator (bottom-right when controls hidden)
              if (!_showControls && _pageUrls.isNotEmpty)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      "${_currentPage + 1} / ${_pageUrls.length}",
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // 3. Floating Top Header (when controls visible)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildTopBar(),
              ),

              // 4. Floating Bottom Controls (when controls visible)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                bottom: _showControls ? 0 : -140,
                left: 0,
                right: 0,
                child: _buildBottomBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, String> _getImageHeaders(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    String referer = 'https://www.mangaread.org/';
    if (uri != null) {
      final host = uri.host.toLowerCase();
      if (host.contains('mangadex') || host.contains('mangadex.network') || host.contains('uploads.mangadex.org')) {
        // MangaDex@Home nodes require root mangadex.org referer
        referer = 'https://mangadex.org/';
      } else if (host.contains('mangapicgallery') || host.contains('mangago')) {
        referer = 'https://www.mangago.zone/';
      } else if (host.contains('asurascans') || host.contains('asura') || host.contains('asuracomic') || host.contains('ggcdn')) {
        referer = 'https://asuracomic.net/';
      } else if (host.contains('weebcentral') || host.contains('planeptune') || host.contains('compsci88')) {
        referer = 'https://weebcentral.com/';
      } else if (host.contains('flame') || host.contains('flamecomics')) {
        referer = 'https://flamecomics.xyz/';
      } else if (host.contains('mkklcdn') || host.contains('manganato') || host.contains('chapmanganelo') || host.contains('mangakakalot')) {
        referer = 'https://chapmanganelo.com/';
      } else if (host.contains('manhuaplus')) {
        referer = 'https://manhuaplus.top/';
      } else if (host.contains('mangakatana')) {
        referer = 'https://mangakatana.com/';
      } else if (host.isNotEmpty) {
        referer = '${uri.scheme}://${uri.host}/';
      }
    }
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Referer': referer,
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
    };
  }

  Widget _buildReaderView() {
    if (_readerMode == MangaReaderMode.webtoon) {
      return ListView.builder(
        controller: _webtoonScrollController,
        physics: const BouncingScrollPhysics(),
        cacheExtent: 4000.0, // Pre-renders 3-4 screens ahead and behind
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        itemCount: _pageUrls.length + 1,
        itemBuilder: (context, index) {
          if (index == _pageUrls.length) {
            return _buildEndOfChapterWidget();
          }
          final pageUrl = _pageUrls[index];
          final pageKey = _pageKeys.putIfAbsent(index, () => GlobalKey());
          return Container(
            key: pageKey,
            child: SmartMangaImage(
              key: ValueKey(pageUrl),
              imageUrl: pageUrl,
              headers: _getImageHeaders(pageUrl),
              fit: BoxFit.fitWidth,
              pageIndex: index + 1,
            ),
          );
        },
      );
    } else {
      // Horizontal Page-by-Page Manga mode
      return PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        itemCount: _pageUrls.length + 1,
        onPageChanged: (page) {
          setState(() => _currentPage = page);
          if (page < _pageUrls.length) {
            _saveProgress();
            _prefetchUpcomingPages(page);
          }
        },
        itemBuilder: (context, index) {
          if (index == _pageUrls.length) {
            return Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildEndOfChapterWidget(),
              ),
            );
          }
          final pageUrl = _pageUrls[index];
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 3.5,
            child: Center(
              child: SmartMangaImage(
                key: ValueKey(pageUrl),
                imageUrl: pageUrl,
                headers: _getImageHeaders(pageUrl),
                fit: BoxFit.contain,
                pageIndex: index + 1,
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.9),
            Colors.black.withOpacity(0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () {
              _saveProgress();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.manga.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  _pageUrls.isNotEmpty
                      ? "${currentChapter.displayTitle} • Page ${_currentPage + 1} of ${_pageUrls.length}"
                      : currentChapter.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Reader Mode Toggle Button
          GestureDetector(
            onTap: () {
              setState(() {
                if (_readerMode == MangaReaderMode.webtoon) {
                  _readerMode = MangaReaderMode.horizontal;
                  _pageController = PageController(initialPage: _currentPage);
                } else {
                  _readerMode = MangaReaderMode.webtoon;
                  _scrollToInitialPageWebtoon(_currentPage);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ThemeService.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ThemeService.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _readerMode == MangaReaderMode.webtoon ? Icons.view_day_outlined : Icons.auto_stories_outlined,
                    color: ThemeService.currentAccent,
                    size: 15,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _readerMode == MangaReaderMode.webtoon ? "Webtoon" : "Manga",
                    style: TextStyle(
                      color: ThemeService.currentAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _pageUrls.length;
    return Container(
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.92),
            Colors.black.withOpacity(0.0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page Indicator & Scrubber (works for both Webtoon and Horizontal modes)
          if (total > 1) ...[
            Row(
              children: [
                Text(
                  "${_currentPage + 1}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: ThemeService.currentAccent,
                      activeTrackColor: ThemeService.currentAccent,
                      inactiveTrackColor: Colors.white24,
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _currentPage.clamp(0, total - 1).toDouble(),
                      min: 0,
                      max: (total - 1).toDouble(),
                      onChanged: (val) {
                        final target = val.round();
                        setState(() => _currentPage = target);
                        if (_readerMode == MangaReaderMode.horizontal) {
                          _pageController.jumpToPage(target);
                        } else {
                          _jumpToWebtoonPage(target);
                        }
                        _saveProgressThrottled();
                      },
                    ),
                  ),
                ),
                Text(
                  "$total",
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          // Chapter Navigation Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  foregroundColor: _currentChapterIndex > 0 ? Colors.white : Colors.white24,
                ),
                onPressed: _currentChapterIndex > 0 ? () => _switchChapter(_currentChapterIndex - 1) : null,
                icon: const Icon(Icons.skip_previous, size: 18),
                label: const Text("Prev", style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "Ch. ${currentChapter.chapterNumber} (${_currentChapterIndex + 1}/${widget.chapters.length})",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
              if (_currentChapterIndex < widget.chapters.length - 1)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE50914).withOpacity(0.6)),
                  ),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      foregroundColor: const Color(0xFFFF4D4D),
                    ),
                    onPressed: () => _switchChapter(_currentChapterIndex + 1),
                    label: const Text(
                      "NEXT",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFFFF4D4D),
                      ),
                    ),
                    icon: const Icon(Icons.skip_next, size: 18, color: Color(0xFFFF4D4D)),
                  ),
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    foregroundColor: Colors.white24,
                  ),
                  onPressed: null,
                  label: const Text("Next", style: TextStyle(fontSize: 12)),
                  icon: const Icon(Icons.skip_next, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEndOfChapterWidget() {
    final hasNext = _currentChapterIndex < widget.chapters.length - 1;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 48),
          const SizedBox(height: 12),
          Text(
            "Completed ${currentChapter.displayTitle}",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Ready for the next chapter?",
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 22),
          if (hasNext) ...[
            // Red "NEXT" label badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE50914).withOpacity(0.55)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, color: Color(0xFFFF4D4D), size: 14),
                  SizedBox(width: 4),
                  Text(
                    "NEXT CHAPTER READY",
                    style: TextStyle(
                      color: Color(0xFFFF4D4D),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // Prominent Glowing Crimson Red Next Button
            GestureDetector(
              onTap: () => _switchChapter(_currentChapterIndex + 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFB91C1C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "NEXT",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "• Ch. ${widget.chapters[_currentChapterIndex + 1].chapterNumber}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ] else
            const Text(
              "You are all caught up!",
              style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}
