import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/manga_service.dart';
import 'package:shikai_app/services/manga_curated_data.dart';
import 'package:shikai_app/services/app_preload_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/manga_detail_screen.dart';
import 'package:shikai_app/widgets/sharingan_loader.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class MangaScreen extends StatefulWidget {
  const MangaScreen({Key? key}) : super(key: key);

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  // Active filter state
  String _selectedCategory = 'All'; // All, Manga, Manhwa, Manhua
  String _selectedGenre = 'All';
  String _searchQuery = '';
  int _requestId = 0;

  // Status flags
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // Category in-memory caches (Preserves data across tab switching so manga never disappears)
  final Map<String, List<AnilistMedia>> _categorySpotlight = {};
  final Map<String, List<AnilistMedia>> _categoryTrending = {};
  final Map<String, List<AnilistMedia>> _categoryTopRated = {};
  final Map<String, List<AnilistMedia>> _categoryInfinite = {};
  final Map<String, int> _categoryPage = {};
  final Map<String, bool> _categoryHasMore = {};

  // Genre filtered list state
  List<AnilistMedia> _genreItems = [];
  int _genrePage = 1;
  bool _genreHasMore = true;

  // Search filtered list state
  List<AnilistMedia> _searchItems = [];
  int _searchPage = 1;
  bool _searchHasMore = true;

  final List<String> _categories = ['All', 'Manga', 'Manhwa', 'Manhua'];
  final Map<String, String> _categoryLabels = {
    'All': '🌐 All',
    'Manga': '🇯🇵 Manga',
    'Manhwa': '🇰🇷 Manhwa',
    'Manhua': '🇨🇳 Manhua',
  };

  final List<String> _allGenres = [
    'All', 'Leveling', 'Murim', 'Cultivation', 'Isekai', 'Shonen', 'Seinen',
    'Action', 'Fantasy', 'Reincarnation', 'Romance', 'Supernatural', 'Psychological', 'Comedy'
  ];

  final List<String> _manhwaGenres = [
    'All', 'Leveling', 'Murim', 'Dungeon', 'Regression', 'Reincarnation',
    'Villainess', 'Revenge', 'Action', 'Fantasy', 'Romance', 'Supernatural'
  ];

  final List<String> _manhuaGenres = [
    'All', 'Cultivation', 'Xianxia', 'Wuxia', 'Rebirth', 'Urban',
    'Action', 'Fantasy', 'Adventure', 'Supernatural', 'Comedy'
  ];

  final List<String> _mangaGenres = [
    'All', 'Shonen', 'Seinen', 'Isekai', 'Dark Fantasy', 'Psychological',
    'Action', 'Romance', 'Supernatural', 'Comedy', 'Mystery', 'Sci-Fi'
  ];

  List<String> get _currentGenres {
    switch (_selectedCategory) {
      case 'Manhwa':
        return _manhwaGenres;
      case 'Manhua':
        return _manhuaGenres;
      case 'Manga':
        return _mangaGenres;
      default:
        return _allGenres;
    }
  }

  @override
  void initState() {
    super.initState();
    // 0. Instantly hydrate from AppPreloadService or curated fallback for 0ms startup!
    final initialFallback = AppPreloadService.trendingManga.isNotEmpty
        ? AppPreloadService.trendingManga
        : MangaCuratedData.getForCategory(_selectedCategory);
    if (initialFallback.isNotEmpty) {
      _categoryTrending[_selectedCategory] = List.from(initialFallback);
      _categorySpotlight[_selectedCategory] = initialFallback.take(5).toList();
      _categoryTopRated[_selectedCategory] = initialFallback.reversed.take(18).toList();
      _categoryInfinite[_selectedCategory] = List.from(initialFallback);
      _categoryPage[_selectedCategory] = 1;
      _categoryHasMore[_selectedCategory] = true;
      _isLoading = false;
    }
    _loadCategoryData(_selectedCategory);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 450) {
      if (_isLoading || _isLoadingMore) return;

      if (_searchQuery.isNotEmpty) {
        _loadMoreSearch();
      } else if (_selectedGenre != 'All') {
        _loadMoreGenre();
      } else {
        _loadMoreCategoryInfinite();
      }
    }
  }

  // --------------------------------------------------------------------------
  // DATA FETCHING & PAGINATION (INFINITE SCROLL)
  // --------------------------------------------------------------------------

  Future<void> _loadCategoryData(String category, {bool forceRefresh = false}) async {
    final int currentRequestId = ++_requestId;

    // 1. If already cached and not forcing refresh, display instantly!
    if (!forceRefresh && _categoryInfinite[category] != null && _categoryInfinite[category]!.isNotEmpty) {
      if (_isLoading) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
      return;
    }

    if (_categoryInfinite[category] == null || _categoryInfinite[category]!.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final tFuture = MangaService.getTrendingManga(category: category, perPage: 18)
          .catchError((_) => <AnilistMedia>[]);
      final trFuture = MangaService.getTopRatedManga(category: category, perPage: 18)
          .catchError((_) => <AnilistMedia>[]);
      final popFuture = MangaService.getPopularManga(category: category, page: 1, perPage: 24)
          .catchError((_) => <AnilistMedia>[]);

      final results = await Future.wait([tFuture, trFuture, popFuture]);

      if (!mounted || currentRequestId != _requestId) return;

      var trending = results[0];
      var topRated = results[1];
      var infinite = results[2];

      // Cross-fallback if any individual shelf is empty
      if (trending.isEmpty && infinite.isNotEmpty) {
        trending = infinite.take(18).toList();
      }
      if (topRated.isEmpty && infinite.isNotEmpty) {
        topRated = infinite.reversed.take(18).toList();
      }
      if (infinite.isEmpty && trending.isNotEmpty) {
        infinite = List.from(trending);
      }
      if (infinite.isEmpty && topRated.isNotEmpty) {
        infinite = List.from(topRated);
      }

      // If still empty (e.g. offline or server rate limit), use curated fallback
      if (infinite.isEmpty && trending.isEmpty) {
        final fallback = MangaCuratedData.getForCategory(category);
        trending = fallback.take(12).toList();
        topRated = fallback.reversed.take(12).toList();
        infinite = List.from(fallback);
      }

      setState(() {
        _categoryTrending[category] = trending;
        _categorySpotlight[category] = trending.take(5).toList();
        _categoryTopRated[category] = topRated;
        _categoryInfinite[category] = infinite;
        _categoryPage[category] = 1;
        _categoryHasMore[category] = infinite.length >= 10;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || currentRequestId != _requestId) return;
      if (_categoryInfinite[category] == null || _categoryInfinite[category]!.isEmpty) {
        final fallback = MangaCuratedData.getForCategory(category);
        setState(() {
          _categoryTrending[category] = fallback.take(12).toList();
          _categorySpotlight[category] = fallback.take(5).toList();
          _categoryTopRated[category] = fallback.reversed.take(12).toList();
          _categoryInfinite[category] = List.from(fallback);
          _categoryPage[category] = 1;
          _categoryHasMore[category] = true;
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreCategoryInfinite() async {
    final cat = _selectedCategory;
    if (_isLoadingMore || (_categoryHasMore[cat] == false)) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = (_categoryPage[cat] ?? 1) + 1;
      final more = await MangaService.getPopularManga(
        category: cat,
        page: nextPage,
        perPage: 24,
      );

      if (!mounted || _selectedCategory != cat) return;

      setState(() {
        if (more.isNotEmpty) {
          final current = _categoryInfinite[cat] ?? [];
          final existingIds = current.map((m) => m.id).toSet();
          final uniqueNew = more.where((m) => !existingIds.contains(m.id)).toList();
          current.addAll(uniqueNew);
          _categoryInfinite[cat] = current;
          _categoryPage[cat] = nextPage;
          if (more.length < 15) {
            _categoryHasMore[cat] = false;
          }
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onCategorySelected(String cat) {
    if (_selectedCategory == cat && _selectedGenre == 'All' && _searchQuery.isEmpty) return;

    setState(() {
      _selectedCategory = cat;
      _selectedGenre = 'All';
      _genreItems.clear();
      _genrePage = 1;
      _genreHasMore = true;
    });

    if (_searchQuery.isNotEmpty) {
      _executeSearch(_searchQuery);
    } else {
      _loadCategoryData(cat);
    }
  }

  void _onGenreSelected(String genre) {
    if (_selectedGenre == genre) return;

    setState(() {
      _selectedGenre = genre;
      _genreItems.clear();
      _genrePage = 1;
      _genreHasMore = true;
    });

    if (genre == 'All') {
      if (_searchQuery.isNotEmpty) {
        _executeSearch(_searchQuery);
      } else {
        _loadCategoryData(_selectedCategory);
      }
    } else {
      _loadGenreData(genre);
    }
  }

  Future<void> _loadGenreData(String genre) async {
    final int currentRequestId = ++_requestId;
    setState(() => _isLoading = true);

    try {
      final items = await MangaService.getMangaByGenre(
        genre,
        category: _selectedCategory,
        page: 1,
        perPage: 24,
      );

      if (!mounted || currentRequestId != _requestId) return;

      setState(() {
        _genreItems = items;
        _genrePage = 1;
        _genreHasMore = items.length >= 24;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || currentRequestId != _requestId) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreGenre() async {
    if (_isLoadingMore || !_genreHasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _genrePage + 1;
      final more = await MangaService.getMangaByGenre(
        _selectedGenre,
        category: _selectedCategory,
        page: nextPage,
        perPage: 24,
      );

      if (!mounted || _selectedGenre == 'All') return;

      setState(() {
        if (more.isNotEmpty) {
          final existingIds = _genreItems.map((m) => m.id).toSet();
          final uniqueNew = more.where((m) => !existingIds.contains(m.id)).toList();
          _genreItems.addAll(uniqueNew);
          _genrePage = nextPage;
        }
        if (more.length < 24) {
          _genreHasMore = false;
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 380), () {
      final trimmed = query.trim();
      setState(() {
        _searchQuery = trimmed;
      });

      if (trimmed.isNotEmpty) {
        _executeSearch(trimmed);
      } else {
        if (_selectedGenre != 'All') {
          _loadGenreData(_selectedGenre);
        } else {
          _loadCategoryData(_selectedCategory);
        }
      }
    });
  }

  Future<void> _executeSearch(String query) async {
    final int currentRequestId = ++_requestId;
    setState(() => _isLoading = true);

    try {
      final items = await MangaService.searchManga(
        query,
        category: _selectedCategory,
        page: 1,
        perPage: 24,
      );

      if (!mounted || currentRequestId != _requestId) return;

      setState(() {
        _searchItems = items;
        _searchPage = 1;
        _searchHasMore = items.length >= 24;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || currentRequestId != _requestId) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreSearch() async {
    if (_isLoadingMore || !_searchHasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _searchPage + 1;
      final more = await MangaService.searchManga(
        _searchQuery,
        category: _selectedCategory,
        page: nextPage,
        perPage: 24,
      );

      if (!mounted || _searchQuery.isEmpty) return;

      setState(() {
        if (more.isNotEmpty) {
          final existingIds = _searchItems.map((m) => m.id).toSet();
          final uniqueNew = more.where((m) => !existingIds.contains(m.id)).toList();
          _searchItems.addAll(uniqueNew);
          _searchPage = nextPage;
        }
        if (more.length < 24) {
          _searchHasMore = false;
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  // --------------------------------------------------------------------------
  // UI BUILDERS
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.currentAccent;

    return Scaffold(
      backgroundColor: ThemeService.background,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Search Bar & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.auto_stories, color: accent, size: 24),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                "Manga & Webtoons",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accent.withOpacity(0.4)),
                        ),
                        child: Text(
                          "HQ Reader",
                          style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search TextField
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Search manga, manhwa, webtoons...",
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13.5),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                if (_selectedGenre != 'All') {
                                  _loadGenreData(_selectedGenre);
                                } else {
                                  _loadCategoryData(_selectedCategory);
                                }
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: ThemeService.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ThemeService.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: ThemeService.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Category Filter Chips (All, Manga, Manhwa, Manhua)
            SizedBox(
              height: 42,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat;
                  final label = _categoryLabels[cat] ?? cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(label),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: ThemeService.surface,
                      selectedColor: accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? accent : ThemeService.border,
                        ),
                      ),
                      onSelected: (_) => _onCategorySelected(cat),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // 2.5 Dynamic Sub-Genre Filter Chips
            _buildGenresRow(),
            const SizedBox(height: 6),

            // 3. Body: Search / Genre Infinite Grid or Home Category Infinite Feed
            Expanded(
              child: RefreshIndicator(
                color: accent,
                backgroundColor: ThemeService.surface,
                onRefresh: () async {
                  if (_searchQuery.isNotEmpty) {
                    await _executeSearch(_searchQuery);
                  } else if (_selectedGenre != 'All') {
                    await _loadGenreData(_selectedGenre);
                  } else {
                    await _loadCategoryData(_selectedCategory, forceRefresh: true);
                  }
                },
                child: _isLoading
                    ? const Center(child: SharinganLoader(size: 52, showLabel: false))
                    : _searchQuery.isNotEmpty
                        ? _buildSearchGrid(accent)
                        : _selectedGenre != 'All'
                            ? _buildGenreGrid(accent)
                            : _buildCategoryInfiniteView(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SUB-VIEWS
  // --------------------------------------------------------------------------

  /// View when searching text: Infinite Grid with endless scroll
  Widget _buildSearchGrid(Color accent) {
    if (_searchItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 54),
            const SizedBox(height: 12),
            Text(
              "No ${_selectedCategory != 'All' ? _selectedCategory : 'manga'} found for '$_searchQuery'.",
              style: const TextStyle(color: ThemeService.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withOpacity(0.3)),
                  ),
                  child: Text(
                    "Search: '$_searchQuery'",
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text(
                  "${_searchItems.length} titles loaded",
                  style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.54,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildMangaCard(_searchItems[index]),
              childCount: _searchItems.length,
            ),
          ),
        ),
        if (_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: accent)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  /// View when a Genre Chip is selected: Infinite Grid of that specific genre
  Widget _buildGenreGrid(Color accent) {
    if (_genreItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 54),
            const SizedBox(height: 12),
            Text(
              "No ${_selectedCategory != 'All' ? _selectedCategory : 'manga'} found in $_selectedGenre.",
              style: const TextStyle(color: ThemeService.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
              onPressed: () => _onGenreSelected('All'),
              child: const Text("Clear Filter"),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${_selectedCategory != 'All' ? _selectedCategory : 'All'} • $_selectedGenre",
                        style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _onGenreSelected('All'),
                        child: Icon(Icons.close, size: 14, color: accent),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  "${_genreItems.length} titles loaded",
                  style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.54,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildMangaCard(_genreItems[index]),
              childCount: _genreItems.length,
            ),
          ),
        ),
        if (_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: accent)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  /// Default View for Category (All, Manga, Manhwa, Manhua): Spotlight + Trending + Top Rated + Endless Infinite Grid!
  Widget _buildCategoryInfiniteView(Color accent) {
    final cat = _selectedCategory;
    final spotlight = _categorySpotlight[cat] ?? [];
    final trending = _categoryTrending[cat] ?? [];
    final topRated = _categoryTopRated[cat] ?? [];
    final infinite = _categoryInfinite[cat] ?? [];

    String infiniteFeedTitle;
    if (cat == 'Manhwa') {
      infiniteFeedTitle = "⚡ Endless Korean Webtoons (Infinite)";
    } else if (cat == 'Manhua') {
      infiniteFeedTitle = "⚡ Endless Chinese Manhua (Infinite)";
    } else if (cat == 'Manga') {
      infiniteFeedTitle = "⚡ Endless Japanese Manga (Infinite)";
    } else {
      infiniteFeedTitle = "⚡ Endless Manga & Webtoons Feed (Infinite)";
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 1. Spotlight Banner Carousel
        if (spotlight.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildSpotlight(spotlight),
          ),

        // 2. Trending Shelf
        if (trending.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              cat == 'Manhwa'
                  ? "🔥 Trending Korean Manhwa"
                  : (cat == 'Manhua'
                      ? "🔥 Trending Chinese Manhua"
                      : (cat == 'Manga' ? "🔥 Trending Japanese Manga" : "🔥 Trending Manga & Webtoons")),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildHorizontalRow(trending),
          ),
        ],

        // 3. Top Rated Shelf
        if (topRated.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              cat == 'Manhwa'
                  ? "⭐ Top Rated Korean Webtoons"
                  : (cat == 'Manhua'
                      ? "⭐ Top Rated Chinese Cultivation"
                      : (cat == 'Manga' ? "⭐ Top Rated Japanese Masterpieces" : "⭐ Top Rated Classics Overall")),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildHorizontalRow(topRated),
          ),
        ],

        // 4. Endless Infinite Feed Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        infiniteFeedTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Continuous endless scrolling catalog",
                        style: TextStyle(color: ThemeService.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${infinite.length} titles",
                    style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 5. 3-Column Infinite Feed Grid
        if (infinite.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.54,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildMangaCard(infinite[index]),
                childCount: infinite.length,
              ),
            ),
          )
        else if (!_isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Icon(Icons.auto_stories_rounded, color: accent, size: 36),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "No ${cat != 'All' ? cat : 'manga'} titles loaded",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Network request delayed or rate-limited. Tap below to reload the catalog.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ThemeService.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _loadCategoryData(cat, forceRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text("Reload Catalog", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 6. Loader while fetching next infinite page
        if (_isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2, color: accent)),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }

  Widget _buildGenresRow() {
    final genres = _currentGenres;
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: genres.length,
        itemBuilder: (context, index) {
          final g = genres[index];
          final isSelected = _selectedGenre == g;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(g),
              selected: isSelected,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: ThemeService.surface,
              selectedColor: ThemeService.currentAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSelected ? ThemeService.currentAccent : ThemeService.border),
              ),
              onSelected: (_) => _onGenreSelected(g),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpotlight(List<AnilistMedia> spotlight) {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        itemCount: spotlight.length,
        itemBuilder: (context, index) {
          final m = spotlight[index];
          final bannerUrl = m.bannerImage ?? m.coverImage;

          return GestureDetector(
            onTap: () => _openMangaDetail(m),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ThemeService.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShikaiNetworkImage(
                      imageUrl: bannerUrl,
                      placeholderTitle: m.displayTitle,
                      isManga: true,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.85),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: m.isManhwa
                                  ? const Color(0xFF059669).withOpacity(0.9)
                                  : (m.isManhua
                                      ? const Color(0xFFDC2626).withOpacity(0.9)
                                      : const Color(0xFF4F46E5).withOpacity(0.9)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${m.originFlag} ${m.categoryLabel.toUpperCase()}',
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.genres.take(3).join(" • "),
                            style: TextStyle(color: ThemeService.currentAccent, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHorizontalRow(List<AnilistMedia> list) {
    return SizedBox(
      height: 215,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return Container(
            width: 120,
            margin: const EdgeInsets.only(right: 12),
            child: _buildMangaCard(list[index]),
          );
        },
      ),
    );
  }

  Widget _buildMangaCard(AnilistMedia m) {
    return GestureDetector(
      onTap: () => _openMangaDetail(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ShikaiNetworkImage(
                  imageUrl: m.coverImage,
                  placeholderTitle: m.displayTitle,
                  isManga: true,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Origin Category Badge (🇰🇷 Manhwa / 🇨🇳 Manhua / 🇯🇵 Manga)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: m.isManhwa
                          ? const Color(0xFF059669).withOpacity(0.92)
                          : (m.isManhua
                              ? const Color(0xFFDC2626).withOpacity(0.92)
                              : const Color(0xFF4F46E5).withOpacity(0.92)),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '${m.originFlag} ${m.categoryLabel}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                if (m.averageScore != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 11),
                          const SizedBox(width: 2),
                          Text(
                            (m.averageScore! / 10).toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            m.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void _openMangaDetail(AnilistMedia m) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MangaDetailScreen(manga: m)),
    );
  }
}
