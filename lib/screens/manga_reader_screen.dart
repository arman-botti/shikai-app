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

  MangaChapter get currentChapter => widget.chapters[_currentChapterIndex];

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: _currentPage);

    // Enter fullscreen for immersive reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadChapterPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _webtoonScrollController.dispose();
    // Restore normal system overlays
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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

        // Save progress
        _saveProgress();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPages = false;
        _errorMessage = "Failed to load chapter pages.";
      });
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
      setState(() {
        _currentChapterIndex = newIndex;
        _currentPage = 0;
      });
      _loadChapterPages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

            // 2. Floating Top Header (when controls visible)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // 3. Floating Bottom Controls (when controls visible)
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
    );
  }

  Map<String, String> _getImageHeaders(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    String referer = 'https://www.mangaread.org/';
    if (uri != null) {
      if (uri.host.contains('mangapicgallery') || uri.host.contains('mangago')) {
        referer = 'https://www.mangago.zone/';
      } else if (uri.host.contains('asurascans') || uri.host.contains('asura')) {
        referer = 'https://asurascans.com/';
      } else if (uri.host.contains('weebcentral') || uri.host.contains('planeptune') || uri.host.contains('compsci88')) {
        referer = 'https://weebcentral.com/';
      } else if (uri.host.contains('manhuaplus')) {
        referer = 'https://manhuaplus.top/';
      } else if (uri.host.contains('mangakatana')) {
        referer = 'https://mangakatana.com/';
      } else if (uri.host.isNotEmpty) {
        referer = '${uri.scheme}://${uri.host}/';
      }
    }
    return {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Referer': referer,
    };
  }

  Widget _buildReaderView() {
    if (_readerMode == MangaReaderMode.webtoon) {
      return ListView.builder(
        controller: _webtoonScrollController,
        physics: const BouncingScrollPhysics(),
        itemCount: _pageUrls.length + 1,
        itemBuilder: (context, index) {
          if (index == _pageUrls.length) {
            return _buildEndOfChapterWidget();
          }
          final pageUrl = _pageUrls[index];
          return SmartMangaImage(
            imageUrl: pageUrl,
            headers: _getImageHeaders(pageUrl),
            fit: BoxFit.fitWidth,
          );
        },
      );
    } else {
      // Horizontal Page-by-Page Manga mode
      return PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        itemCount: _pageUrls.length,
        onPageChanged: (page) {
          setState(() => _currentPage = page);
          _saveProgress();
        },
        itemBuilder: (context, index) {
          final pageUrl = _pageUrls[index];
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 3.5,
            child: Center(
              child: SmartMangaImage(
                imageUrl: pageUrl,
                headers: _getImageHeaders(pageUrl),
                fit: BoxFit.contain,
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
            onPressed: () => Navigator.pop(context),
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
                  currentChapter.displayTitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          // Reader Mode Toggle Button
          GestureDetector(
            onTap: () {
              setState(() {
                _readerMode = _readerMode == MangaReaderMode.webtoon
                    ? MangaReaderMode.horizontal
                    : MangaReaderMode.webtoon;
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
          // Page Indicator & Scrubber (for horizontal mode)
          if (_readerMode == MangaReaderMode.horizontal && total > 1) ...[
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
                      value: _currentPage.toDouble(),
                      min: 0,
                      max: (total - 1).toDouble(),
                      onChanged: (val) {
                        final target = val.round();
                        _pageController.jumpToPage(target);
                        setState(() => _currentPage = target);
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
                  foregroundColor: _currentChapterIndex > 0 ? Colors.white : Colors.white24,
                ),
                onPressed: _currentChapterIndex > 0 ? () => _switchChapter(_currentChapterIndex - 1) : null,
                icon: const Icon(Icons.skip_previous, size: 20),
                label: const Text("Prev Chapter"),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Ch. ${currentChapter.chapterNumber} (${_currentChapterIndex + 1}/${widget.chapters.length})",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: _currentChapterIndex < widget.chapters.length - 1 ? Colors.white : Colors.white24,
                ),
                onPressed: _currentChapterIndex < widget.chapters.length - 1
                    ? () => _switchChapter(_currentChapterIndex + 1)
                    : null,
                label: const Text("Next Chapter"),
                icon: const Icon(Icons.skip_next, size: 20),
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
          const SizedBox(height: 20),
          if (hasNext)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeService.currentAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _switchChapter(_currentChapterIndex + 1),
              icon: const Icon(Icons.skip_next, size: 20),
              label: Text("Next: Ch. ${widget.chapters[_currentChapterIndex + 1].chapterNumber}"),
            )
          else
            const Text(
              "You are all caught up!",
              style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}
