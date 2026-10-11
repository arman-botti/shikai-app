import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/manga_service.dart';
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = true;
  List<AnilistMedia> _spotlight = [];
  List<AnilistMedia> _trending = [];
  List<AnilistMedia> _popularCategory = [];
  List<AnilistMedia> _popularManhwa = [];
  List<AnilistMedia> _popularManhua = [];
  List<AnilistMedia> _popularManga = [];
  List<AnilistMedia> _topRated = [];
  List<AnilistMedia> _actionHits = [];
  List<AnilistMedia> _fantasyHits = [];

  // Search & Filter state
  String _selectedCategory = 'All'; // All, Manga, Manhwa, Manhua
  String _selectedGenre = 'All';
  String _searchQuery = '';
  List<AnilistMedia> _searchResults = [];
  bool _isSearching = false;

  final List<String> _categories = ['All', 'Manga', 'Manhwa', 'Manhua'];
  final Map<String, String> _categoryLabels = {
    'All': '🌐 All',
    'Manga': '🇯🇵 Manga',
    'Manhwa': '🇰🇷 Manhwa',
    'Manhua': '🇨🇳 Manhua',
  };

  final List<String> _genres = [
    'All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror',
    'Isekai', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life',
    'Supernatural', 'Thriller'
  ];

  @override
  void initState() {
    super.initState();
    _loadMangaFeeds();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMangaFeeds() async {
    setState(() => _isLoading = true);
    try {
      if (_selectedCategory == 'Manhwa') {
        // STRICTLY South Korean Manhwa / Webtoons (countryOfOrigin: "KR")
        final results = await Future.wait([
          MangaService.getTrendingManga(category: 'Manhwa', perPage: 25),
          MangaService.getPopularManga(category: 'Manhwa', perPage: 25),
          MangaService.getMangaByGenre('Action', category: 'Manhwa', perPage: 25),
          MangaService.getMangaByGenre('Fantasy', category: 'Manhwa', perPage: 25),
          MangaService.getTopRatedManga(category: 'Manhwa', perPage: 25),
        ]);

        if (!mounted) return;
        setState(() {
          _trending = results[0];
          _spotlight = _trending.take(5).toList();
          _popularCategory = results[1];
          _actionHits = results[2];
          _fantasyHits = results[3];
          _topRated = results[4];
          _isLoading = false;
        });
      } else if (_selectedCategory == 'Manhua') {
        // STRICTLY Chinese Manhua (countryOfOrigin: "CN")
        final results = await Future.wait([
          MangaService.getTrendingManga(category: 'Manhua', perPage: 25),
          MangaService.getPopularManga(category: 'Manhua', perPage: 25),
          MangaService.getMangaByGenre('Action', category: 'Manhua', perPage: 25),
          MangaService.getMangaByGenre('Fantasy', category: 'Manhua', perPage: 25),
          MangaService.getTopRatedManga(category: 'Manhua', perPage: 25),
        ]);

        if (!mounted) return;
        setState(() {
          _trending = results[0];
          _spotlight = _trending.take(5).toList();
          _popularCategory = results[1];
          _actionHits = results[2];
          _fantasyHits = results[3];
          _topRated = results[4];
          _isLoading = false;
        });
      } else if (_selectedCategory == 'Manga') {
        // STRICTLY Japanese Manga (countryOfOrigin_not_in: ["KR", "CN"])
        final results = await Future.wait([
          MangaService.getTrendingManga(category: 'Manga', perPage: 25),
          MangaService.getPopularManga(category: 'Manga', perPage: 25),
          MangaService.getMangaByGenre('Action', category: 'Manga', perPage: 25),
          MangaService.getMangaByGenre('Supernatural', category: 'Manga', perPage: 25),
          MangaService.getTopRatedManga(category: 'Manga', perPage: 25),
        ]);

        if (!mounted) return;
        setState(() {
          _trending = results[0];
          _spotlight = _trending.take(5).toList();
          _popularCategory = results[1];
          _actionHits = results[2];
          _fantasyHits = results[3];
          _topRated = results[4];
          _isLoading = false;
        });
      } else {
        // 'All' - Comprehensive catalog across all origins
        final results = await Future.wait([
          MangaService.getTrendingManga(category: 'All', perPage: 25),
          MangaService.getPopularManhwa(perPage: 20),
          MangaService.getPopularManhua(perPage: 20),
          MangaService.getPopularJapaneseManga(perPage: 20),
          MangaService.getTopRatedManga(category: 'All', perPage: 25),
        ]);

        if (!mounted) return;
        setState(() {
          _trending = results[0];
          _spotlight = _trending.take(5).toList();
          _popularManhwa = results[1];
          _popularManhua = results[2];
          _popularManga = results[3];
          _topRated = results[4];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onCategorySelected(String cat) {
    if (_selectedCategory == cat) return;
    setState(() {
      _selectedCategory = cat;
    });

    if (_searchQuery.isNotEmpty) {
      _executeSearch(_searchQuery);
    } else if (_selectedGenre != 'All') {
      _executeGenreFilter(_selectedGenre);
    } else {
      _loadMangaFeeds();
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      final trimmed = query.trim();
      setState(() {
        _searchQuery = trimmed;
        _isSearching = trimmed.isNotEmpty;
      });

      if (trimmed.isNotEmpty) {
        _executeSearch(trimmed);
      }
    });
  }

  void _executeSearch(String query) async {
    setState(() => _isLoading = true);
    final results = await MangaService.searchManga(query, category: _selectedCategory);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _onGenreSelected(String genre) {
    setState(() {
      _selectedGenre = genre;
      _isSearching = genre != 'All';
    });

    if (genre != 'All') {
      _executeGenreFilter(genre);
    } else if (_searchQuery.isNotEmpty) {
      _executeSearch(_searchQuery);
    } else {
      _loadMangaFeeds();
    }
  }

  void _executeGenreFilter(String genre) async {
    setState(() => _isLoading = true);
    final results = await MangaService.getMangaByGenre(genre, category: _selectedCategory);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

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
                                setState(() {
                                  _searchQuery = '';
                                  _isSearching = false;
                                });
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

            // 3. Body: Search/Filter Grid or Home Feeds
            Expanded(
              child: _isLoading
                  ? const Center(child: SharinganLoader(size: 52, showLabel: false))
                  : _isSearching
                      ? _buildSearchResultsGrid()
                      : _buildFeedsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsGrid() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              "No ${_selectedCategory != 'All' ? _selectedCategory : 'manga'} found matching your query.",
              style: const TextStyle(color: ThemeService.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.60,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildMangaCard(_searchResults[index]);
      },
    );
  }

  Widget _buildFeedsList() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        // Spotlight Carousel
        if (_spotlight.isNotEmpty) _buildSpotlight(),

        if (_selectedCategory == 'Manhwa') ...[
          // STRICTLY KOREAN MANHWA
          _buildSectionHeader("🔥 Trending Manhwa", onSeeAll: () {}),
          _buildHorizontalRow(_trending),

          _buildSectionHeader("🇰🇷 Popular Korean Webtoons", onSeeAll: () {}),
          _buildHorizontalRow(_popularCategory),

          if (_actionHits.isNotEmpty) ...[
            _buildSectionHeader("⚔️ Action & Leveling Manhwa", onSeeAll: () {}),
            _buildHorizontalRow(_actionHits),
          ],

          _buildSectionHeader("Explore Genres", onSeeAll: () {}),
          _buildGenresRow(),
          const SizedBox(height: 14),

          if (_fantasyHits.isNotEmpty) ...[
            _buildSectionHeader("✨ Fantasy & Reincarnation Manhwa", onSeeAll: () {}),
            _buildHorizontalRow(_fantasyHits),
          ],

          _buildSectionHeader("⭐ Top Rated Manhwa", onSeeAll: () {}),
          _buildHorizontalRow(_topRated),
        ] else if (_selectedCategory == 'Manhua') ...[
          // STRICTLY CHINESE MANHUA
          _buildSectionHeader("🔥 Trending Manhua", onSeeAll: () {}),
          _buildHorizontalRow(_trending),

          _buildSectionHeader("🇨🇳 Popular Chinese Cultivation & Action", onSeeAll: () {}),
          _buildHorizontalRow(_popularCategory),

          if (_actionHits.isNotEmpty) ...[
            _buildSectionHeader("🥋 Martial Arts & Cultivation Manhua", onSeeAll: () {}),
            _buildHorizontalRow(_actionHits),
          ],

          _buildSectionHeader("Explore Genres", onSeeAll: () {}),
          _buildGenresRow(),
          const SizedBox(height: 14),

          if (_fantasyHits.isNotEmpty) ...[
            _buildSectionHeader("🐉 Fantasy & Adventure Manhua", onSeeAll: () {}),
            _buildHorizontalRow(_fantasyHits),
          ],

          _buildSectionHeader("⭐ Top Rated Manhua", onSeeAll: () {}),
          _buildHorizontalRow(_topRated),
        ] else if (_selectedCategory == 'Manga') ...[
          // STRICTLY JAPANESE MANGA
          _buildSectionHeader("🔥 Trending Japanese Manga", onSeeAll: () {}),
          _buildHorizontalRow(_trending),

          _buildSectionHeader("🇯🇵 Popular Japanese Manga", onSeeAll: () {}),
          _buildHorizontalRow(_popularCategory),

          if (_actionHits.isNotEmpty) ...[
            _buildSectionHeader("🗡️ Shonen & Action Hits", onSeeAll: () {}),
            _buildHorizontalRow(_actionHits),
          ],

          _buildSectionHeader("Explore Genres", onSeeAll: () {}),
          _buildGenresRow(),
          const SizedBox(height: 14),

          if (_fantasyHits.isNotEmpty) ...[
            _buildSectionHeader("🔮 Supernatural & Dark Fantasy", onSeeAll: () {}),
            _buildHorizontalRow(_fantasyHits),
          ],

          _buildSectionHeader("⭐ Top Rated Japanese Manga", onSeeAll: () {}),
          _buildHorizontalRow(_topRated),
        ] else ...[
          // ALL CATEGORIES
          _buildSectionHeader("🔥 Trending Manga & Webtoons", onSeeAll: () {}),
          _buildHorizontalRow(_trending),

          _buildSectionHeader("🇰🇷 Popular Korean Manhwa", onSeeAll: () {}),
          _buildHorizontalRow(_popularManhwa),

          _buildSectionHeader("🇨🇳 Popular Chinese Manhua", onSeeAll: () {}),
          _buildHorizontalRow(_popularManhua),

          _buildSectionHeader("🇯🇵 Popular Japanese Manga", onSeeAll: () {}),
          _buildHorizontalRow(_popularManga),

          _buildSectionHeader("Explore Genres", onSeeAll: () {}),
          _buildGenresRow(),
          const SizedBox(height: 14),

          _buildSectionHeader("⭐ Top Rated Overall", onSeeAll: () {}),
          _buildHorizontalRow(_topRated),
        ],
      ],
    );
  }

  Widget _buildGenresRow() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _genres.length,
        itemBuilder: (context, index) {
          final g = _genres[index];
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

  Widget _buildSpotlight() {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        itemCount: _spotlight.length,
        itemBuilder: (context, index) {
          final m = _spotlight[index];
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

  Widget _buildSectionHeader(String title, {required VoidCallback onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 13),
        ],
      ),
    );
  }

  Widget _buildHorizontalRow(List<AnilistMedia> list) {
    return SizedBox(
      height: 200,
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
