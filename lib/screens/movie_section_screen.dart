import 'package:flutter/material.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_detail_screen.dart';
import 'package:shikai_app/screens/movie_search_screen.dart';
import 'package:shikai_app/services/moviebox_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

/// ---------------------------------------------------------------------------
/// MOVIE SECTION VIEW MORE SCREEN
/// Displays full grid catalog of a MovieBox section (e.g. Trending, Popular)
/// with category filters (All / Movies / Series) and infinite scroll for ranking.
/// ---------------------------------------------------------------------------
class MovieSectionScreen extends StatefulWidget {
  final String title;
  final List<MovieboxItem> initialItems;
  final bool isTrending;

  const MovieSectionScreen({
    Key? key,
    required this.title,
    required this.initialItems,
    this.isTrending = false,
  }) : super(key: key);

  @override
  State<MovieSectionScreen> createState() => _MovieSectionScreenState();
}

class _MovieSectionScreenState extends State<MovieSectionScreen> {
  final ScrollController _scrollController = ScrollController();
  late List<MovieboxItem> _items;
  String _filter = 'all'; // all | movie | series
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _items = List<MovieboxItem>.from(widget.initialItems);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (widget.isTrending && !_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final newItems = await MovieboxService.getRankingList(page: nextPage);
      if (!mounted) return;

      if (newItems.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
      } else {
        final existingIds = _items.map((e) => e.id).toSet();
        final filtered = newItems.where((e) => !existingIds.contains(e.id)).toList();
        setState(() {
          _page = nextPage;
          _items.addAll(filtered);
          _isLoadingMore = false;
          if (filtered.isEmpty) _hasMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    if (widget.isTrending) {
      try {
        final refreshed = await MovieboxService.getRankingList(page: 1);
        if (!mounted) return;
        if (refreshed.isNotEmpty) {
          setState(() {
            _items = refreshed;
            _page = 1;
            _hasMore = true;
          });
        }
      } catch (_) {}
    }
  }

  List<MovieboxItem> get _filteredItems {
    if (_filter == 'all') return _items;
    final wantSeries = _filter == 'series';
    return _items.where((e) => e.isSeries == wantSeries).toList();
  }

  void _openDetail(MovieboxItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          subjectId: item.id,
          title: item.title,
          cover: item.cover,
          detailPath: item.detailPath,
          isSeries: item.isSeries,
        ),
      ),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MovieSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _filteredItems;

    return Scaffold(
      backgroundColor: ThemeService.background,
      appBar: AppBar(
        backgroundColor: ThemeService.surface,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.search, color: Colors.white, size: 20),
                  onPressed: _openSearch,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: RefreshIndicator(
              color: ThemeService.crimson,
              backgroundColor: ThemeService.surface,
              onRefresh: _refresh,
              child: displayed.isEmpty
                  ? const Center(
                      child: Text(
                        'No titles found',
                        style: TextStyle(color: ThemeService.textMuted),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.58,
                        crossAxisSpacing: 9,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: displayed.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= displayed.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: ThemeService.crimson,
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        }
                        return _buildCard(displayed[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    const filters = [
      ['all', 'All'],
      ['movie', 'Movies'],
      ['series', 'TV Series'],
    ];

    return Container(
      color: ThemeService.surface.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f[0];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f[0]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? ThemeService.crimson : ThemeService.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? ThemeService.crimson : ThemeService.border,
                  ),
                ),
                child: Text(
                  f[1],
                  style: TextStyle(
                    color: selected ? Colors.white : ThemeService.textMuted,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCard(MovieboxItem item) {
    return GestureDetector(
      onTap: () => _openDetail(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ShikaiNetworkImage(
                    imageUrl: item.cover ?? '',
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.circular(10),
                    placeholderTitle: item.title,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (item.rating != null && item.rating! > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.74),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: ThemeService.crimson.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.isSeries ? 'SERIES' : 'MOVIE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [if (item.year != null) item.year!, if (item.corner != null) item.corner!]
                .where((e) => e.isNotEmpty)
                .join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
