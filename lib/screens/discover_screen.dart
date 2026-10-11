import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/anime_detail_screen.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class DiscoverScreen extends StatefulWidget {
  final String? initialGenre;
  final String? initialFormat;

  const DiscoverScreen({
    Key? key,
    this.initialGenre,
    this.initialFormat,
  }) : super(key: key);

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  // Filter state
  late String _selectedFormat;
  late String _selectedGenre;
  String _selectedStatus = 'All';
  String _selectedSort = 'POPULARITY_DESC';
  String _searchQuery = '';

  // Results & Pagination
  final List<AnilistMedia> _animeList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;

  final List<Map<String, String>> _formats = [
    {'id': 'All', 'label': 'All Formats'},
    {'id': 'TV', 'label': 'TV Series'},
    {'id': 'MOVIE', 'label': 'Movie'},
    {'id': 'OVA', 'label': 'OVA'},
    {'id': 'ONA', 'label': 'ONA'},
    {'id': 'SPECIAL', 'label': 'Special'},
  ];

  final List<String> _genres = [
    'All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror',
    'Isekai', 'Mecha', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi',
    'Slice of Life', 'Sports', 'Supernatural', 'Thriller'
  ];

  final List<Map<String, String>> _statuses = [
    {'id': 'All', 'label': 'All Status'},
    {'id': 'RELEASING', 'label': 'Ongoing (Airing)'},
    {'id': 'FINISHED', 'label': 'Completed'},
  ];

  final List<Map<String, String>> _sortOptions = [
    {'id': 'POPULARITY_DESC', 'label': 'Most Popular'},
    {'id': 'SCORE_DESC', 'label': 'Highest Rated'},
    {'id': 'TRENDING_DESC', 'label': 'Trending Now'},
    {'id': 'START_DATE_DESC', 'label': 'Newest Releases'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.initialFormat ?? 'All';
    _selectedGenre = widget.initialGenre ?? 'All';

    _loadResults(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadResults();
      }
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      setState(() {
        _searchQuery = val.trim();
      });
      _loadResults(refresh: true);
    });
  }

  int _requestId = 0;

  Future<void> _loadResults({bool refresh = false}) async {
    final int thisRequestId = ++_requestId;

    if (refresh) {
      setState(() {
        _isLoading = true;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    List<AnilistMedia> newItems = await AnilistService.advancedFilter(
      query: _searchQuery.isNotEmpty ? _searchQuery : null,
      format: _selectedFormat,
      genre: _selectedGenre,
      status: _selectedStatus,
      sort: _selectedSort,
      page: _page,
      perPage: 21,
    );

    // If initial query returned empty and not searching, fallback to trending so screen is never blank
    if (newItems.isEmpty && refresh && _searchQuery.isEmpty && _selectedFormat == 'All' && _selectedGenre == 'All') {
      newItems = await AnilistService.getTrendingAnime(page: 1, perPage: 21);
    }

    if (!mounted || thisRequestId != _requestId) return;

    setState(() {
      if (refresh) {
        if (newItems.isNotEmpty || _animeList.isEmpty) {
          _animeList.clear();
          _animeList.addAll(newItems);
        }
      } else {
        _animeList.addAll(newItems);
      }
      _isLoading = false;
      _isLoadingMore = false;
      if (newItems.length < 21) {
        _hasMore = false;
      } else {
        _page++;
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _selectedFormat = 'All';
      _selectedGenre = 'All';
      _selectedStatus = 'All';
      _selectedSort = 'POPULARITY_DESC';
      _searchQuery = '';
      _searchController.clear();
    });
    _loadResults(refresh: true);
  }

  void _showFilterBottomSheet(Color accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeService.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.9,
              minChildSize: 0.5,
              builder: (context, scroll) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: ListView(
                    controller: scroll,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.tune, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "Advanced Filters",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              _resetFilters();
                              Navigator.pop(context);
                            },
                            child: const Text("Reset All", style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Format Section
                      const Text(
                        "FORMAT",
                        style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _formats.map((f) {
                          final isSel = _selectedFormat == f['id'];
                          return ChoiceChip(
                            label: Text(f['label']!),
                            selected: isSel,
                            selectedColor: accent,
                            side: BorderSide(color: isSel ? accent : ThemeService.border),
                            labelStyle: TextStyle(
                              color: isSel ? Colors.black : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.background,
                            onSelected: (val) {
                              setModalState(() => _selectedFormat = f['id']!);
                              setState(() => _selectedFormat = f['id']!);
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Status Section
                      const Text(
                        "STATUS",
                        style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statuses.map((s) {
                          final isSel = _selectedStatus == s['id'];
                          return ChoiceChip(
                            label: Text(s['label']!),
                            selected: isSel,
                            selectedColor: accent,
                            side: BorderSide(color: isSel ? accent : ThemeService.border),
                            labelStyle: TextStyle(
                              color: isSel ? Colors.black : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.background,
                            onSelected: (val) {
                              setModalState(() => _selectedStatus = s['id']!);
                              setState(() => _selectedStatus = s['id']!);
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Sort Section
                      const Text(
                        "SORT BY",
                        style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _sortOptions.map((s) {
                          final isSel = _selectedSort == s['id'];
                          return ChoiceChip(
                            label: Text(s['label']!),
                            selected: isSel,
                            side: BorderSide(color: isSel ? accent : ThemeService.border),
                            selectedColor: accent,
                            labelStyle: TextStyle(
                              color: isSel ? Colors.black : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.background,
                            onSelected: (val) {
                              setModalState(() => _selectedSort = s['id']!);
                              setState(() => _selectedSort = s['id']!);
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Genre Section
                      const Text(
                        "GENRE",
                        style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _genres.map((g) {
                          final isSel = _selectedGenre == g;
                          return ChoiceChip(
                            label: Text(g),
                            selected: isSel,
                            side: BorderSide(color: isSel ? accent : ThemeService.border),
                            selectedColor: accent,
                            labelStyle: TextStyle(
                              color: isSel ? Colors.black : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.background,
                            onSelected: (val) {
                              setModalState(() => _selectedGenre = g);
                              setState(() => _selectedGenre = g);
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Apply Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _loadResults(refresh: true);
                        },
                        child: const Text("Apply Filters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        final activeFilterCount = (_selectedFormat != 'All' ? 1 : 0) +
            (_selectedGenre != 'All' ? 1 : 0) +
            (_selectedStatus != 'All' ? 1 : 0) +
            (_selectedSort != 'POPULARITY_DESC' ? 1 : 0);

        return Scaffold(
          backgroundColor: ThemeService.background,
          appBar: AppBar(
            backgroundColor: ThemeService.background,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ThemeService.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ThemeService.border),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.maybePop(context),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.explore, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Discover & Filter",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: Badge(
                    isLabelVisible: activeFilterCount > 0,
                    label: Text("$activeFilterCount"),
                    backgroundColor: accent,
                    child: const Icon(Icons.tune, color: Colors.white70, size: 18),
                  ),
                ),
                onPressed: () => _showFilterBottomSheet(accent),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              // 1. Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Search anime titles...",
                    hintStyle: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: ThemeService.textDarkMuted, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: ThemeService.textDarkMuted, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: ThemeService.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
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
                  onChanged: _onSearchChanged,
                ),
              ),

              // 2. Quick Genre Carousel
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _genres.length,
                  itemBuilder: (context, index) {
                    final g = _genres[index];
                    final isSel = _selectedGenre == g;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedGenre = g);
                        _loadResults(refresh: true);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? accent : ThemeService.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSel ? accent : ThemeService.border),
                        ),
                        child: Text(
                          g,
                          style: TextStyle(
                            color: isSel ? Colors.black : ThemeService.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // 3. Grid of Anime Cards (Matching Seanime Tenji 3-col style)
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: accent))
                    : _animeList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_off, color: Colors.white24, size: 54),
                                const SizedBox(height: 12),
                                const Text(
                                  "No anime found matching filters",
                                  style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                                  onPressed: _resetFilters,
                                  child: const Text("Reset Filters"),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.65,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _animeList.length + (_isLoadingMore ? 3 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _animeList.length) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: ThemeService.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: ThemeService.border),
                                  ),
                                );
                              }

                              final item = _animeList[index];

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AnimeDetailScreen(media: item),
                                    ),
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: ThemeService.border, width: 1.0),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(9),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              ShikaiNetworkImage(
                                                imageUrl: item.coverImage,
                                                placeholderTitle: item.displayTitle,
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              if (item.averageScore != null)
                                                Positioned(
                                                  top: 4,
                                                  right: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: ThemeService.background.withOpacity(0.85),
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(color: ThemeService.border, width: 0.5),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.star, color: Colors.amber, size: 9),
                                                        const SizedBox(width: 2),
                                                        Text(
                                                          (item.averageScore! / 10).toStringAsFixed(1),
                                                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (item.format != null)
                                                Positioned(
                                                  bottom: 4,
                                                  left: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: ThemeService.background.withOpacity(0.85),
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(color: ThemeService.border, width: 0.5),
                                                    ),
                                                    child: Text(
                                                      item.format!,
                                                      style: const TextStyle(color: ThemeService.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
