import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/manga_chapter.dart';
import 'package:shikai_app/services/manga_service.dart';
import 'package:shikai_app/services/manga_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/manga_reader_screen.dart';
import 'package:shikai_app/widgets/sharingan_loader.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class MangaDetailScreen extends StatefulWidget {
  final AnilistMedia manga;

  const MangaDetailScreen({
    Key? key,
    required this.manga,
  }) : super(key: key);

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  bool _isLoadingChapters = true;
  List<MangaChapter> _chapters = [];
  String? _errorMessage;

  bool _isBookmarked = false;
  MangaHistoryItem? _savedProgress;

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  String _searchFilter = '';
  bool _isAscending = true;
  bool _isExpandedDesc = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    // 1. Check bookmarks & progress
    final bookmarked = await MangaHistoryService.isBookmarked(widget.manga.id);
    final progress = await MangaHistoryService.getProgressForManga(widget.manga.id);

    if (mounted) {
      setState(() {
        _isBookmarked = bookmarked;
        _savedProgress = progress;
      });
    }

    // 2. Fetch Chapters
    try {
      final chapters = await MangaService.getMangaChapters(
        widget.manga.title,
        englishTitle: widget.manga.englishTitle,
        sourceUrl: widget.manga.sourceUrl,
        sourceId: widget.manga.sourceId,
      );

      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _isLoadingChapters = false;
        if (chapters.isEmpty) {
          _errorMessage = "No chapters found for this title.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingChapters = false;
        _errorMessage = "Failed to load chapters.";
      });
    }
  }

  void _openReader({int chapterIndex = 0, int initialPage = 0}) async {
    if (_chapters.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaReaderScreen(
          manga: widget.manga,
          chapters: _chapters,
          initialChapterIndex: chapterIndex,
          initialPage: initialPage,
        ),
      ),
    );

    // Refresh progress on return
    final progress = await MangaHistoryService.getProgressForManga(widget.manga.id);
    if (mounted) {
      setState(() => _savedProgress = progress);
    }
  }

  void _resumeReading() {
    if (_savedProgress == null || _chapters.isEmpty) {
      _openReader(chapterIndex: 0);
      return;
    }

    final index = _chapters.indexWhere((c) => c.chapterNumber == _savedProgress!.chapterNumber);
    if (index != -1) {
      _openReader(chapterIndex: index, initialPage: _savedProgress!.pageIndex);
    } else {
      _openReader(chapterIndex: 0);
    }
  }

  List<MangaChapter> get _filteredChapters {
    var list = _chapters.where((c) {
      if (_searchFilter.isEmpty) return true;
      return c.chapterNumber.contains(_searchFilter) ||
          c.title.toLowerCase().contains(_searchFilter.toLowerCase());
    }).toList();

    if (!_isAscending) {
      list = list.reversed.toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.currentAccent;
    final bannerUrl = widget.manga.bannerImage ?? widget.manga.coverImage;

    return Scaffold(
      backgroundColor: ThemeService.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Hero Backdrop Header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: ThemeService.background,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: _isBookmarked ? accent : Colors.white,
                    size: 19,
                  ),
                ),
                onPressed: () async {
                  final now = await MangaHistoryService.toggleBookmark(widget.manga.id);
                  setState(() => _isBookmarked = now);
                },
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  ShikaiNetworkImage(
                    imageUrl: bannerUrl,
                    placeholderTitle: widget.manga.displayTitle,
                    isManga: true,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.2),
                          ThemeService.background.withOpacity(0.7),
                          ThemeService.background,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Poster, Title, Meta Details & Quick Actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Manga Cover Poster
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 105,
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: ShikaiNetworkImage(
                            imageUrl: widget.manga.coverImage,
                            placeholderTitle: widget.manga.displayTitle,
                            isManga: true,
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.manga.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                              ),
                            ),
                            if (widget.manga.title.isNotEmpty && widget.manga.title != widget.manga.displayTitle) ...[
                              const SizedBox(height: 3),
                              Text(
                                widget.manga.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
                              ),
                            ],
                            const SizedBox(height: 10),
                            // Meta Chips
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: widget.manga.isManhwa
                                        ? const Color(0xFF059669).withOpacity(0.2)
                                        : (widget.manga.isManhua
                                            ? const Color(0xFFDC2626).withOpacity(0.2)
                                            : const Color(0xFF4F46E5).withOpacity(0.2)),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: widget.manga.isManhwa
                                          ? const Color(0xFF059669).withOpacity(0.5)
                                          : (widget.manga.isManhua
                                              ? const Color(0xFFDC2626).withOpacity(0.5)
                                              : const Color(0xFF4F46E5).withOpacity(0.5)),
                                    ),
                                  ),
                                  child: Text(
                                    "${widget.manga.originFlag} ${widget.manga.categoryLabel.toUpperCase()}",
                                    style: TextStyle(
                                      color: widget.manga.isManhwa
                                          ? const Color(0xFF34D399)
                                          : (widget.manga.isManhua
                                              ? const Color(0xFFF87171)
                                              : const Color(0xFF818CF8)),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (widget.manga.averageScore != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 14),
                                        const SizedBox(width: 3),
                                        Text(
                                          (widget.manga.averageScore! / 10).toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (widget.manga.status != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                                    ),
                                    child: Text(
                                      widget.manga.status!,
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (widget.manga.chapters != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${widget.manga.chapters} Chs",
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Action Buttons (Read / Resume)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _chapters.isNotEmpty ? _resumeReading : null,
                          icon: const Icon(Icons.auto_stories, color: Colors.white, size: 19),
                          label: Text(
                            _savedProgress != null
                                ? "Resume Ch. ${_savedProgress!.chapterNumber}"
                                : "Start Reading",
                            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: ThemeService.surface,
                          padding: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: ThemeService.border),
                          ),
                        ),
                        icon: Icon(
                          _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                          color: _isBookmarked ? accent : Colors.white70,
                        ),
                        onPressed: () async {
                          final now = await MangaHistoryService.toggleBookmark(widget.manga.id);
                          setState(() => _isBookmarked = now);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Genres
                  if (widget.manga.genres.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.manga.genres.map((g) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: ThemeService.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: Text(
                            g,
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Description
                  if (widget.manga.description != null && widget.manga.description!.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => setState(() => _isExpandedDesc = !_isExpandedDesc),
                      child: Text(
                        widget.manga.description!,
                        maxLines: _isExpandedDesc ? null : 3,
                        overflow: _isExpandedDesc ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Chapters Section Header & Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Chapters (${_chapters.length})",
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(
                          _isAscending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _isAscending = !_isAscending),
                        tooltip: _isAscending ? "Newest First" : "Oldest First",
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Search Filter in Chapters
                  if (_chapters.length > 10) ...[
                    TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Search chapter...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                        filled: true,
                        fillColor: ThemeService.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: ThemeService.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: ThemeService.border),
                        ),
                      ),
                      onChanged: (val) => setState(() => _searchFilter = val.trim()),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),

          // 3. Chapters List
          if (_isLoadingChapters)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: Center(child: SharinganLoader(size: 48, showLabel: false)),
              ),
            )
          else if (_errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
                child: Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: ThemeService.textMuted, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chapter = _filteredChapters[index];
                    final originalIndex = _chapters.indexOf(chapter);
                    final isCurrent = _savedProgress?.chapterNumber == chapter.chapterNumber;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isCurrent ? accent.withOpacity(0.12) : ThemeService.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent ? accent.withOpacity(0.4) : ThemeService.border,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isCurrent ? accent : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isCurrent ? Icons.menu_book : Icons.auto_stories_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          chapter.displayTitle,
                          style: TextStyle(
                            color: isCurrent ? Colors.white : Colors.white.withOpacity(0.9),
                            fontSize: 13.5,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: chapter.releaseDate != null
                            ? Text(
                                chapter.releaseDate!.split('T').first,
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              )
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 13),
                        onTap: () => _openReader(chapterIndex: originalIndex),
                      ),
                    );
                  },
                  childCount: _filteredChapters.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 36)),
        ],
      ),
    );
  }
}
