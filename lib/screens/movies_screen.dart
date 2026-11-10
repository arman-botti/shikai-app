import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_detail_screen.dart';
import 'package:shikai_app/screens/movie_search_screen.dart';
import 'package:shikai_app/screens/movie_section_screen.dart';
import 'package:shikai_app/services/moviebox_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

typedef MovieboxHomeLoader = Future<MovieboxHome> Function({bool forceRefresh});

/// ---------------------------------------------------------------------------
/// SHIKAI MOVIES & TV — MovieBox catalog powered entirely on-device.
/// Every request is signed and sent from the user's own IP.
/// ---------------------------------------------------------------------------
class MoviesScreen extends StatefulWidget {
  final MovieboxHomeLoader? homeLoader;

  const MoviesScreen({Key? key, this.homeLoader}) : super(key: key);

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  MovieboxHome? _home;
  bool _isLoading = true;
  String? _error;
  String _filter = 'all'; // all | movie | series

  final PageController _bannerController = PageController();
  final ValueNotifier<int> _bannerIndex = ValueNotifier<int>(0);
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _bannerIndex.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final loader = widget.homeLoader ?? MovieboxService.getHome;
      final home = await loader(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _home = home;
        _isLoading = false;
      });
      _startBannerTimer(home.banners.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _startBannerTimer(int count) {
    _bannerTimer?.cancel();
    if (count <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex.value + 1) % count;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
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

  void _openSection(MovieboxHomeSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieSectionScreen(
          title: section.title,
          initialItems: section.items,
          isTrending: section.title.toLowerCase().contains('trend') ||
              section.type.toLowerCase().contains('rank'),
        ),
      ),
    );
  }

  List<MovieboxHomeSection> get _filteredSections {
    final sections = _home?.sections ?? [];
    if (_filter == 'all') return sections;

    final wantSeries = _filter == 'series';
    final filtered = <MovieboxHomeSection>[];
    for (final section in sections) {
      final items = section.items.where((e) => e.isSeries == wantSeries).toList();
      if (items.isNotEmpty) {
        filtered.add(MovieboxHomeSection(title: section.title, type: section.type, items: items));
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeService.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: ThemeService.crimson, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text(
              'MOVIES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: ThemeService.crimson.withOpacity(0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'TV',
                style: TextStyle(
                  color: ThemeService.crimson,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ThemeService.crimson));
    }

    if (_error != null && _home == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: ThemeService.textMuted, size: 46),
              const SizedBox(height: 14),
              const Text(
                'Movies load nahi ho payi',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ThemeService.crimson),
                onPressed: () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final home = _home!;
    final sections = _filteredSections;

    return RefreshIndicator(
      color: ThemeService.crimson,
      backgroundColor: ThemeService.surface,
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          if (home.banners.isNotEmpty) _buildHero(home.banners),
          const SizedBox(height: 14),
          _buildFilterBar(),
          const SizedBox(height: 8),
          if (sections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'Kuch nahi mila',
                  style: TextStyle(color: ThemeService.textMuted),
                ),
              ),
            ),
          ...sections.map(_buildSection),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hero carousel
  // ---------------------------------------------------------------------------
  Widget _buildHero(List<MovieboxItem> banners) {
    final items = banners.take(7).toList();
    return SizedBox(
      height: 342,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            itemCount: items.length,
            onPageChanged: (index) => _bannerIndex.value = index,
            itemBuilder: (context, index) => _buildHeroCard(items[index]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: ValueListenableBuilder<int>(
              valueListenable: _bannerIndex,
              builder: (context, active, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(items.length, (i) {
                    final selected = i == active;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 20 : 6,
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected ? ThemeService.crimson : Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(MovieboxItem item) {
    final image = item.backdrop ?? item.cover ?? '';
    return GestureDetector(
      onTap: () => _openDetail(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ShikaiNetworkImage(
            imageUrl: image,
            fit: BoxFit.cover,
            placeholderTitle: item.title,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.25),
                  ThemeService.background.withOpacity(0.96),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ThemeService.crimson,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.isSeries ? 'SERIES' : 'MOVIE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (item.rating != null && item.rating! > 0) ...[
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (item.year != null)
                      Text(
                        item.year!,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    if (item.genre != null && item.genre!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.genre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeService.crimson,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openDetail(item),
                      icon: const Icon(Icons.play_arrow_rounded, size: 19),
                      label: const Text(
                        'Watch Now',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openDetail(item),
                      child: const Text('Details', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter bar
  // ---------------------------------------------------------------------------
  Widget _buildFilterBar() {
    const filters = [
      ['all', 'All'],
      ['movie', 'Movies'],
      ['series', 'TV Series'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: filters.map((f) {
          final selected = _filter == f[0];
          return GestureDetector(
            onTap: () => setState(() => _filter = f[0]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? ThemeService.crimson : ThemeService.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? ThemeService.crimson : ThemeService.border,
                ),
              ),
              child: Text(
                f[1],
                style: TextStyle(
                  color: selected ? Colors.white : ThemeService.textMuted,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Horizontal shelf
  // ---------------------------------------------------------------------------
  Widget _buildSection(MovieboxHomeSection section) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openSection(section),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View More',
                          style: TextStyle(
                            color: ThemeService.crimson,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: ThemeService.crimson,
                          size: 11,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 218,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: section.items.length,
              itemBuilder: (context, index) => _buildCard(section.items[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(MovieboxItem item) {
    return GestureDetector(
      onTap: () => _openDetail(item),
      child: Container(
        width: 118,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ShikaiNetworkImage(
                  imageUrl: item.cover ?? '',
                  width: 118,
                  height: 164,
                  borderRadius: BorderRadius.circular(11),
                  placeholderTitle: item.title,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.white10),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.22)],
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
            const SizedBox(height: 7),
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
      ),
    );
  }
}
