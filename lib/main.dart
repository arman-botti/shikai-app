import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/stream_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/anime_detail_screen.dart';
import 'package:shikai_app/screens/anime_catalog_screen.dart';
import 'package:shikai_app/screens/schedule_screen.dart';
import 'package:shikai_app/screens/discover_screen.dart';
import 'package:shikai_app/screens/manga_screen.dart';
import 'package:shikai_app/screens/manga_detail_screen.dart';
import 'package:shikai_app/screens/library_screen.dart';
import 'package:shikai_app/services/manga_service.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';
import 'package:shikai_app/services/anime_aggregator_service.dart';
import 'package:shikai_app/services/update_service.dart';
import 'package:shikai_app/widgets/update_dialog.dart';
import 'package:shikai_app/screens/splash_screen.dart';
import 'package:shikai_app/services/app_preload_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure in-memory image cache limits for high-speed scrolling
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 * 1024 * 1024; // 160 MB max
  PaintingBinding.instance.imageCache.maximumSize = 500; // 500 downsampled image textures
  // Initialize user theme preference
  await ThemeService.init();
  // Initialize native in-app client-side proxy (0% Oracle VM bandwidth)
  await StreamService.initLocalProxy();
  runApp(const ShikaiApp());
}

class ShikaiApp extends StatelessWidget {
  const ShikaiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        return MaterialApp(
          title: 'Shikai',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: ThemeService.background,
            canvasColor: ThemeService.background,
            cardColor: ThemeService.surface,
            primaryColor: accent,
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: accent,
              surface: ThemeService.surface,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

class ShikaiHomeScreen extends StatefulWidget {
  const ShikaiHomeScreen({Key? key}) : super(key: key);

  @override
  State<ShikaiHomeScreen> createState() => _ShikaiHomeScreenState();
}

class _ShikaiHomeScreenState extends State<ShikaiHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  bool _isLoading = true;

  List<AnilistMedia> _spotlightList = [];
  List<AnilistMedia> _trending = [];
  List<AnilistMedia> _popular = [];
  List<AnilistMedia> _topAiring = [];
  List<AnilistMedia> _movies = [];
  List<AnilistMedia> _recentlyUpdated = [];
  List<AnilistMedia> _topRated = [];
  List<AnilistMedia> _upcoming = [];
  List<AnilistMedia> _actionHits = [];
  List<AnilistMedia> _fantasyHits = [];
  List<AnilistMedia> _romanceHits = [];
  List<WatchHistoryItem> _continueWatching = [];
  List<AnilistMedia> _trendingManga = [];
  String _topTenFilter = 'today';

  final ScrollController _homeScrollController = ScrollController();
  List<AnilistMedia> _infiniteFeed = [];
  int _infinitePage = 1;
  bool _isLoadingMoreInfinite = false;
  bool _hasMoreInfinite = true;

  final PageController _spotlightController = PageController();
  int _spotlightIndex = 0;
  final ValueNotifier<int> _spotlightIndexNotifier = ValueNotifier<int>(0);
  Timer? _spotlightTimer;

  final List<String> _genres = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Horror',
    'Isekai',
    'Mecha',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ];

  @override
  void initState() {
    super.initState();
    _homeScrollController.addListener(_onHomeScroll);
    AppPreloadService.addListener(_onPreloadSecondaryUpdate);

    if (AppPreloadService.isPreloaded && AppPreloadService.trending.isNotEmpty) {
      // 1. INSTANTLY HYDRATE FROM PRELOAD CACHE (Zero Delay, Zero Blank Skeletons!)
      _trending = AppPreloadService.trending;
      _popular = AppPreloadService.popular;
      _spotlightList = AppPreloadService.spotlightList;
      _continueWatching = AppPreloadService.continueWatching;
      _infiniteFeed = List.from(AppPreloadService.popular);
      _topAiring = AppPreloadService.topAiring;
      _movies = AppPreloadService.movies;
      _recentlyUpdated = AppPreloadService.recentlyUpdated;
      _topRated = AppPreloadService.topRated;
      _upcoming = AppPreloadService.upcoming;
      _trendingManga = AppPreloadService.trendingManga;
      _actionHits = AppPreloadService.actionHits;
      _fantasyHits = AppPreloadService.fantasyHits;
      _romanceHits = AppPreloadService.romanceHits;
      _isLoading = false;
      _startSpotlightTimer();
    } else {
      _loadAnilistData();
      _loadContinueWatching();
    }

    // In-App Update Check: silently checks GitHub Releases after 2.5s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      UpdateService.checkForUpdate().then((updateInfo) {
        if (mounted && updateInfo != null && updateInfo.hasUpdate) {
          UpdateDialog.show(context, updateInfo);
        }
      }).catchError((_) {});
    });
  }

  void _onPreloadSecondaryUpdate() {
    if (!mounted) return;
    setState(() {
      if (AppPreloadService.topAiring.isNotEmpty && _topAiring.isEmpty) {
        _topAiring = AppPreloadService.topAiring;
      }
      if (AppPreloadService.movies.isNotEmpty && _movies.isEmpty) {
        _movies = AppPreloadService.movies;
      }
      if (AppPreloadService.recentlyUpdated.isNotEmpty && _recentlyUpdated.isEmpty) {
        _recentlyUpdated = AppPreloadService.recentlyUpdated;
      }
      if (AppPreloadService.topRated.isNotEmpty && _topRated.isEmpty) {
        _topRated = AppPreloadService.topRated;
      }
      if (AppPreloadService.upcoming.isNotEmpty && _upcoming.isEmpty) {
        _upcoming = AppPreloadService.upcoming;
      }
      if (AppPreloadService.trendingManga.isNotEmpty && _trendingManga.isEmpty) {
        _trendingManga = AppPreloadService.trendingManga;
      }
      if (AppPreloadService.actionHits.isNotEmpty && _actionHits.isEmpty) {
        _actionHits = AppPreloadService.actionHits;
      }
      if (AppPreloadService.fantasyHits.isNotEmpty && _fantasyHits.isEmpty) {
        _fantasyHits = AppPreloadService.fantasyHits;
      }
      if (AppPreloadService.romanceHits.isNotEmpty && _romanceHits.isEmpty) {
        _romanceHits = AppPreloadService.romanceHits;
      }
    });
  }

  @override
  void dispose() {
    AppPreloadService.removeListener(_onPreloadSecondaryUpdate);
    _spotlightTimer?.cancel();
    _spotlightController.dispose();
    _spotlightIndexNotifier.dispose();
    _homeScrollController.removeListener(_onHomeScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  void _onHomeScroll() {
    if (!_homeScrollController.hasClients) return;
    final maxScroll = _homeScrollController.position.maxScrollExtent;
    final currentScroll = _homeScrollController.position.pixels;
    if (maxScroll - currentScroll <= 600) {
      if (!_isLoadingMoreInfinite && _hasMoreInfinite) {
        _loadMoreInfiniteFeed();
      }
    }
  }

  Future<void> _loadMoreInfiniteFeed() async {
    if (_isLoadingMoreInfinite || !_hasMoreInfinite) return;
    setState(() {
      _isLoadingMoreInfinite = true;
    });

    try {
      _infinitePage++;
      final more = await AnilistService.getPopularAnime(page: _infinitePage, perPage: 24);
      if (mounted) {
        setState(() {
          if (more.isEmpty) {
            _hasMoreInfinite = false;
          } else {
            final existingIds = _infiniteFeed.map((e) => e.id).toSet();
            final unique = more.where((m) => !existingIds.contains(m.id)).toList();
            if (unique.isEmpty) {
              _hasMoreInfinite = false;
            } else {
              _infiniteFeed.addAll(unique);
            }
          }
          _isLoadingMoreInfinite = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMoreInfinite = false;
        });
      }
    }
  }

  void _startSpotlightTimer() {
    _spotlightTimer?.cancel();
    _spotlightTimer = Timer.periodic(const Duration(milliseconds: 5500), (timer) {
      final isVisible = _homeScrollController.hasClients && _homeScrollController.offset < 360;
      if (_spotlightList.isNotEmpty && _spotlightController.hasClients && isVisible) {
        final next = (_spotlightIndex + 1) % _spotlightList.length;
        _spotlightController.animateToPage(
          next,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Future<void> _loadContinueWatching() async {
    final history = await WatchHistoryService.getContinueWatching();
    if (mounted) {
      setState(() {
        _continueWatching = history;
      });
    }
  }

  Future<void> _loadAnilistData() async {
    try {
      // Phase 1 (Instant First-Fold): Load Trending & Popular first (<300ms)
      final topFold = await Future.wait([
        AnilistService.getTrendingAnime(page: 1, perPage: 20),
        AnilistService.getPopularAnime(page: 1, perPage: 20),
      ]);

      if (mounted) {
        setState(() {
          _trending = topFold[0];
          _popular = topFold[1];
          _infiniteFeed = List.from(topFold[1]);
          _spotlightList = _trending.take(8).toList();
          _infinitePage = 1;
          _hasMoreInfinite = true;
          _isLoading = false; // Immediately reveal UI with zero stutter!
        });
        _startSpotlightTimer();
      }

      // Phase 2 (Progressive Batch 1): Top Airing, Movies, Recently Updated
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      final batch1 = await Future.wait([
        AnilistService.getTopAiring(page: 1, perPage: 20),
        AnilistService.getMovies(page: 1, perPage: 16),
        AnilistService.getRecentlyUpdated(page: 1, perPage: 20),
      ]);
      if (mounted) {
        setState(() {
          _topAiring = batch1[0];
          _movies = batch1[1];
          _recentlyUpdated = batch1[2];
        });
      }

      // Phase 3 (Progressive Batch 2): Top Rated, Upcoming Anime, Trending Manga
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      final batch2 = await Future.wait([
        AnilistService.getTopRated(page: 1, perPage: 20),
        AnilistService.getUpcomingAnime(page: 1, perPage: 16),
        MangaService.getTrendingManga(page: 1, perPage: 15),
      ]);
      if (mounted) {
        setState(() {
          _topRated = batch2[0];
          _upcoming = batch2[1];
          _trendingManga = batch2[2];
        });
      }

      // Phase 4 (Progressive Batch 3): Genre Hits (Action, Fantasy, Romance)
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
      final batch3 = await Future.wait([
        AnilistService.getAnimeByGenre('Action', page: 1, perPage: 16),
        AnilistService.getAnimeByGenre('Fantasy', page: 1, perPage: 16),
        AnilistService.getAnimeByGenre('Romance', page: 1, perPage: 16),
      ]);
      if (mounted) {
        setState(() {
          _actionHits = batch3[0];
          _fantasyHits = batch3[1];
          _romanceHits = batch3[2];
        });
      }
    } catch (e) {
      debugPrint('[Home] Catalog load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openDetail(AnilistMedia media) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeDetailScreen(media: media),
      ),
    );
    _loadContinueWatching();
  }

  void _openCatalog(String title, String mode, {String? genre}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnimeCatalogScreen(title: title, mode: mode, genre: genre),
      ),
    );
    _loadContinueWatching();
  }

  void _openSchedule() async {
    _spotlightTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScheduleScreen()),
    );
    if (mounted) {
      setState(() => _currentIndex = 0);
      _startSpotlightTimer();
    }
  }

  void _openManga() async {
    _spotlightTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MangaScreen()),
    );
    if (mounted) {
      setState(() => _currentIndex = 0);
      _startSpotlightTimer();
    }
  }

  void _openMangaDetail(AnilistMedia manga) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MangaDetailScreen(manga: manga)),
    );
  }

  void _openLibrary() async {
    _spotlightTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LibraryScreen()),
    );
    if (mounted) {
      setState(() => _currentIndex = 0);
      _startSpotlightTimer();
    }
  }

  void _openDiscover({String? genre, String? format}) async {
    _spotlightTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiscoverScreen(initialGenre: genre, initialFormat: format),
      ),
    );
    if (mounted) {
      setState(() => _currentIndex = 0);
      _startSpotlightTimer();
    }
  }

  void _pickRandomAnime() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text("Summoning random anime... 🎲"),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    final media = await AnilistService.getRandomAnime();
    if (media != null && mounted) {
      _openDetail(media);
    }
  }

  void _openSearch() {
    showSearch(
      context: context,
      delegate: AnimeSearchDelegate(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: ThemeService.background,
          extendBodyBehindAppBar: true,
          extendBody: true,
          // 1. FULLY FUNCTIONAL SEANIME NAVIGATION DRAWER (The 3 bars "///")
          drawer: _buildNavigationDrawer(accent),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 54,
            leading: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ThemeService.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ThemeService.border),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.menu, color: Colors.white, size: 20),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
            ),
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: ThemeService.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ThemeService.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: accent.withOpacity(0.6), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "SHIKAI",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ".BIZ",
                      style: TextStyle(
                        color: accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            centerTitle: true,
            actions: [
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: "Surprise Me (Random Anime 🎲)",
                    icon: const Icon(Icons.casino_outlined, color: Colors.white, size: 19),
                    onPressed: _pickRandomAnime,
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.search, color: Colors.white, size: 20),
                    onPressed: _openSearch,
                  ),
                ),
              ),
            ],
          ),
          body: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: accent),
                )
              : RefreshIndicator(
                  color: accent,
                  backgroundColor: const Color(0xFF121624),
                  onRefresh: () async {
                    await _loadAnilistData();
                    await _loadContinueWatching();
                  },
                  child: ListView(
                    controller: _homeScrollController,
                    cacheExtent: 500,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                        // 1. DYNAMIC AUTO-PLAYING HERO SPOTLIGHT CAROUSEL
                        if (_spotlightList.isNotEmpty)
                          _buildHeroCarousel(_spotlightList, accent)
                        else
                          const SizedBox(height: 100),

                        // 2. CONTINUE WATCHING (User Watch History)
                        if (_continueWatching.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildContinueWatchingSection(),
                        ],

                        // 3. QUICK AIRING SCHEDULE BAR
                        _buildScheduleQuickBar(accent),

                        const SizedBox(height: 8),

                        // 4. TRENDING NOW 🔥 (Top Trending with working See All)
                        if (_trending.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Trending Now 🔥",
                            mode: "trending",
                            list: _trending,
                            isSmall: false,
                          ),

                        // TRENDING MANGA & WEBTOONS 📖
                        if (_trendingManga.isNotEmpty)
                          _buildMangaHorizontalSection(accent),

                        // 5. TOP 10 ANIME RANKINGS (Today / Week / Month)
                        _buildTopTenSection(accent),

                        // 6. LATEST UPDATED EPISODES 🔄
                        if (_recentlyUpdated.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Latest Updated Episodes 🔄",
                            mode: "updated",
                            list: _recentlyUpdated,
                            isSmall: true,
                          ),

                        // 7. TOP AIRING TODAY ⚡
                        if (_topAiring.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Top Airing Today ⚡",
                            mode: "airing",
                            list: _topAiring,
                            isSmall: true,
                          ),

                        // 8. ANIME MOVIES & FILMS 🎬
                        if (_movies.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Anime Movies & Films 🎬",
                            mode: "movies",
                            list: _movies,
                            isSmall: true,
                          ),

                        // 9. ALL TIME POPULAR CLASSICS 🌟
                        if (_popular.isNotEmpty)
                          _buildHorizontalSection(
                            title: "All Time Popular Classics 🌟",
                            mode: "popular",
                            list: _popular,
                            isSmall: true,
                          ),

                        // 10. HIGHEST RATED MASTERPIECES 👑
                        if (_topRated.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Highest Rated Masterpieces 👑",
                            mode: "top_rated",
                            list: _topRated,
                            isSmall: true,
                          ),

                        // 11. ACTION & SHOUNEN BATTLES ⚔️
                        if (_actionHits.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Action & Shounen Battles ⚔️",
                            mode: "genre",
                            list: _actionHits,
                            isSmall: true,
                            genre: "Action",
                          ),

                        // 12. FANTASY & ISEKAI WORLDS 🪄
                        if (_fantasyHits.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Fantasy & Isekai Worlds 🪄",
                            mode: "genre",
                            list: _fantasyHits,
                            isSmall: true,
                            genre: "Fantasy",
                          ),

                        // 13. ROMANCE & SLICE OF LIFE 🌸
                        if (_romanceHits.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Romance & Slice of Life 🌸",
                            mode: "genre",
                            list: _romanceHits,
                            isSmall: true,
                            genre: "Romance",
                          ),

                        // 14. ANTICIPATED UPCOMING ⏳
                        if (_upcoming.isNotEmpty)
                          _buildHorizontalSection(
                            title: "Anticipated Upcoming ⏳",
                            mode: "upcoming",
                            list: _upcoming,
                            isSmall: true,
                          ),

                        // 15. EXPLORE BY GENRE
                        _buildGenreSection(),

                        // 16. ENDLESS ANIME FEED ("Dher Sara Anime" - Infinite Exploration)
                        _buildInfiniteFeedSection(accent),

                        const SizedBox(height: 110),
                      ],
                    ),
                  ),

          // SEANIME HIGH-PERFORMANCE BOTTOM NAVIGATION BAR (GPU Optimized)
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: ThemeService.surface,
              border: Border(
                top: BorderSide(color: ThemeService.border, width: 1),
              ),
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: accent,
              unselectedItemColor: ThemeService.textDarkMuted,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              currentIndex: _currentIndex,
              onTap: (index) {
                if (index == 1) {
                  _openDiscover();
                } else if (index == 2) {
                  _openManga();
                } else if (index == 3) {
                  _openSchedule();
                } else if (index == 4) {
                  _openLibrary();
                }
              },
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
                    BottomNavigationBarItem(icon: Icon(Icons.movie_filter_outlined), activeIcon: Icon(Icons.movie_filter), label: "Anime"),
                    BottomNavigationBarItem(icon: Icon(Icons.auto_stories_outlined), activeIcon: Icon(Icons.auto_stories), label: "Manga"),
                    BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: "Schedule"),
                    BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), activeIcon: Icon(Icons.video_library), label: "Library"),
                  ],
                ),
              ),
        );
      },
    );
  }

  // Quick Airing Schedule Action Bar (Seanime Tenji Card)
  Widget _buildScheduleQuickBar(Color accent) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeService.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeService.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.calendar_month, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Airing Schedule",
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  "Daily releases, times & countdowns",
                  style: TextStyle(color: ThemeService.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: ThemeService.border),
              backgroundColor: ThemeService.background,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _openSchedule,
            child: Text("View ›", style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Top 10 Rankings Section matching Seanime Tenji
  Widget _buildTopTenSection(Color accent) {
    if (_trending.isEmpty) return const SizedBox.shrink();
    final topTen = _trending.take(10).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, left: 16.0, right: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: ThemeService.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ThemeService.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.trending_up, color: accent, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          "TOP 10 ANIME",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Filter Tabs (Today, Week, Month)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: ThemeService.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: Row(
                    children: ['today', 'week', 'month'].map((tab) {
                      final isSel = _topTenFilter == tab;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _topTenFilter = tab;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel ? accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            tab[0].toUpperCase() + tab.substring(1),
                            style: TextStyle(
                              color: isSel ? Colors.white : ThemeService.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Top 10 items
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topTen.length,
              itemBuilder: (context, index) {
                final anime = topTen[index];
                final rank = index + 1;
                final rankStr = rank < 10 ? "0$rank" : "$rank";

                Color rankColor;
                if (rank == 1) {
                  rankColor = accent;
                } else if (rank == 2) {
                  rankColor = Colors.amberAccent;
                } else if (rank == 3) {
                  rankColor = const Color(0xFF00D2FF);
                } else {
                  rankColor = ThemeService.textDarkMuted;
                }

                return InkWell(
                  onTap: () => _openDetail(anime),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        // Rank Number
                        SizedBox(
                          width: 32,
                          child: Text(
                            rankStr,
                            style: TextStyle(
                              color: rankColor,
                              fontSize: rank <= 3 ? 18 : 16,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Poster Thumbnail
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: ShikaiNetworkImage(
                            imageUrl: anime.coverImage,
                            placeholderTitle: anime.displayTitle,
                            width: 38,
                            height: 52,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title & Rating
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anime.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (anime.averageScore != null) ...[
                                    const Icon(Icons.star, color: Colors.amber, size: 12),
                                    const SizedBox(width: 3),
                                    Text(
                                      (anime.averageScore! / 10).toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (anime.format != null)
                                    Flexible(
                                      child: Text(
                                        "${anime.format} • ${anime.episodes ?? '?'} EPS",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // NAVIGATION DRAWER (The 3 Bars "///" Hamburger Menu)
  // --------------------------------------------------------------------------
  Widget _buildNavigationDrawer(Color accent) {
    return Drawer(
      backgroundColor: ThemeService.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 18,
              left: 18,
              right: 18,
            ),
            decoration: const BoxDecoration(
              color: ThemeService.surface,
              border: Border(bottom: BorderSide(color: ThemeService.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: accent.withOpacity(0.6), blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "SHIKAI",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withOpacity(0.4)),
                      ),
                      child: Text(
                        ".BIZ",
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hd_outlined, color: Color(0xFF10B981), size: 14),
                          SizedBox(width: 4),
                          Text(
                            "Ultra HD Engine",
                            style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ThemeService.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ThemeService.border),
                      ),
                      child: Text(
                        ThemeService.themeLabel,
                        style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          ListTile(
            leading: Icon(Icons.home_filled, color: accent),
            title: const Text("Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.auto_stories_outlined, color: accent),
            title: const Text("Manga & Webtoons 📖", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openManga();
            },
          ),
          ListTile(
            leading: Icon(Icons.video_library_outlined, color: accent),
            title: const Text("My Library 📚", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openLibrary();
            },
          ),
          ListTile(
            leading: Icon(Icons.calendar_month_outlined, color: accent),
            title: const Text("Airing Schedule (Calendar 📅)", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openSchedule();
            },
          ),
          ListTile(
            leading: Icon(Icons.explore_outlined, color: accent),
            title: const Text("Discover & Advanced Filter 🧭", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openDiscover();
            },
          ),
          ListTile(
            leading: const Icon(Icons.movie_outlined, color: Colors.amberAccent),
            title: const Text("Anime Movies 🎬", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openCatalog("Anime Movies 🎬", "movies");
            },
          ),
          ListTile(
            leading: const Icon(Icons.casino_outlined, color: Colors.cyanAccent),
            title: const Text("Surprise Me (Random Anime 🎲)", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _pickRandomAnime();
            },
          ),
          ListTile(
            leading: const Icon(Icons.translate, color: Colors.orangeAccent),
            title: const Text("DesiDub (Hindi Dubs 🇮🇳)", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openCatalog("Hindi Dubbed Anime 🇮🇳", "trending");
            },
          ),
          ListTile(
            leading: Icon(Icons.history, color: accent),
            title: const Text("Continue Watching", style: TextStyle(color: Colors.white)),
            trailing: _continueWatching.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "${_continueWatching.length}",
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                : null,
            onTap: () {
              Navigator.pop(context);
              _openCatalog("Continue Watching", "history");
            },
          ),
          ListTile(
            leading: Icon(Icons.bookmark_outline, color: accent),
            title: const Text("My Watchlist", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openCatalog("My Watchlist", "watchlist");
            },
          ),

          const Divider(color: ThemeService.border),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "GENRES & CATEGORIES",
              style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ),

          ..._genres.map((g) => ListTile(
            dense: true,
            leading: const Icon(Icons.category_outlined, color: ThemeService.textMuted, size: 18),
            title: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            onTap: () {
              Navigator.pop(context);
              _openCatalog("$g Anime", "genre", genre: g);
            },
          )),

          const Divider(color: ThemeService.border),

          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.white70),
            title: const Text("App Settings", style: TextStyle(color: Colors.white70)),
            onTap: () {
              Navigator.pop(context);
              _showSettingsModal();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text("Clear Watch History", style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.pop(context);
              await WatchHistoryService.clearAll();
              if (!mounted) return;
              _loadContinueWatching();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Watch history cleared.")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: ThemeService.textMuted),
            title: const Text("About Shikai", style: TextStyle(color: ThemeService.textMuted)),
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CONTINUE WATCHING SHELF (Seanime Tenji 16:9 Shelf)
  // --------------------------------------------------------------------------
  Widget _buildContinueWatchingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.play_circle_filled, color: ThemeService.currentAccent, size: 20),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "Continue Watching",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _openCatalog("Continue Watching", "history"),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    "See All ›",
                    style: TextStyle(
                      color: ThemeService.currentAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: _continueWatching.length,
            itemBuilder: (context, index) {
              final item = _continueWatching[index];
              return GestureDetector(
                onTap: () async {
                  AnilistMedia? media;
                  try {
                    media = await AnilistService.getAnimeDetails(item.anilistId);
                  } catch (_) {}
                  media ??= AnilistMedia(
                    id: item.anilistId,
                    title: item.title,
                    englishTitle: item.title,
                    coverImage: item.coverImage,
                    bannerImage: item.coverImage,
                    genres: const [],
                  );
                  if (mounted) {
                    _openDetail(media);
                  }
                },
                child: Container(
                  width: 220,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ThemeService.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      children: [
                        // Background poster with dark fade
                        Positioned.fill(
                          child: ShikaiNetworkImage(
                            imageUrl: item.coverImage,
                            placeholderTitle: item.title,
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  ThemeService.background.withOpacity(0.88),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        // Play icon in center
                        Positioned.fill(
                          child: Center(
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.play_arrow, color: ThemeService.currentAccent, size: 24),
                            ),
                          ),
                        ),
                        // Top-left episode pill
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: ThemeService.background.withOpacity(0.85),
                              borderRadius: const BorderRadius.only(
                                bottomRight: Radius.circular(8),
                              ),
                              border: Border.all(color: ThemeService.border),
                            ),
                            child: Text(
                              "EP ${item.episodeNumber}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // Title & Episode Info
                        Positioned(
                          bottom: 8,
                          left: 10,
                          right: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 5),
                              // Seanime Brand Progress Bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: item.progressPercentage > 0 ? item.progressPercentage : 0.05,
                                  backgroundColor: Colors.white24,
                                  valueColor: AlwaysStoppedAnimation<Color>(ThemeService.currentAccent),
                                  minHeight: 3,
                                ),
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
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // FEATURED HERO CAROUSEL (Authentic Seanime Tenji discover-hero-carousel)
  // --------------------------------------------------------------------------
  Widget _buildHeroCarousel(List<AnilistMedia> items, Color accent) {
    if (items.isEmpty) {
      return const SizedBox(height: 100);
    }

    return RepaintBoundary(
      child: SizedBox(
        height: 350,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
          PageView.builder(
            controller: _spotlightController,
            itemCount: items.length,
            onPageChanged: (idx) {
              _spotlightIndex = idx;
              _spotlightIndexNotifier.value = idx;
            },
            itemBuilder: (context, idx) {
              final media = items[idx];
              final bannerUrl = media.bannerImage ?? media.coverImage;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Featured Background Image
                  ShikaiNetworkImage(
                    imageUrl: bannerUrl,
                    placeholderTitle: media.displayTitle,
                  ),
                  // Multi-layer gradients matching discover-hero-carousel.tsx
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.72),
                          Colors.black.withOpacity(0.22),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          ThemeService.background.withOpacity(0.4),
                          ThemeService.background.withOpacity(0.85),
                          ThemeService.background,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.35, 0.72, 1.0],
                      ),
                    ),
                  ),
                  // Spotlight Content Info
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges Row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "# ${idx + 1} SPOTLIGHT",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            if (media.averageScore != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ThemeService.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: ThemeService.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 11),
                                    const SizedBox(width: 3),
                                    Text(
                                      (media.averageScore! / 10).toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (media.format != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ThemeService.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: ThemeService.border),
                                ),
                                child: Text(
                                  media.format!,
                                  style: const TextStyle(color: ThemeService.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Title
                        Text(
                          media.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Genres
                        Text(
                          media.genres.take(3).map((g) => g.toUpperCase()).join(" • "),
                          style: const TextStyle(
                            color: ThemeService.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Actions Row
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: const Text("Watch Now", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              onPressed: () => _openDetail(media),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: ThemeService.surface,
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: ThemeService.border),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text("Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              onPressed: () => _openDetail(media),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          // Page Indicator Pills at Bottom Right
          Positioned(
            bottom: 8,
            right: 16,
            child: ValueListenableBuilder<int>(
              valueListenable: _spotlightIndexNotifier,
              builder: (context, activeIndex, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(items.length, (i) {
                    final isSelected = i == activeIndex;
                    return GestureDetector(
                      onTap: () {
                        _spotlightController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: isSelected ? 22 : 6,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: isSelected ? accent : Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

  // --------------------------------------------------------------------------
  // HORIZONTAL SECTION WITH SEANIME TENJI MEDIA CARDS
  // --------------------------------------------------------------------------
  Widget _buildHorizontalSection({
    required String title,
    required String mode,
    required List<AnilistMedia> list,
    required bool isSmall,
    String? genre,
  }) {
    final cardWidth = isSmall ? 120.0 : 145.0;
    final posterHeight = isSmall ? 170.0 : 205.0;
    final totalHeight = isSmall ? 225.0 : 265.0;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 22.0),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 17.5, fontWeight: FontWeight.bold),
                ),
                // WORKING "SEE ALL" BUTTON
                InkWell(
                  onTap: () => _openCatalog(title, mode, genre: genre),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      "See All ›",
                      style: TextStyle(
                        color: ThemeService.currentAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: totalHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemExtent: cardWidth + 8.0,
              cacheExtent: 300,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final item = list[index];
                return RepaintBoundary(
                  child: GestureDetector(
                    onTap: () => _openDetail(item),
                    child: Container(
                      width: cardWidth,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Seanime 2:3 Media Poster Card
                        Container(
                          height: posterHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ShikaiNetworkImage(
                                  imageUrl: item.coverImage,
                                  placeholderTitle: item.displayTitle,
                                ),
                                // Gradient fade at bottom of poster
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          ThemeService.background.withOpacity(0.7),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                // Top-Left Badge (Episode or Airing status)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: ThemeService.background.withOpacity(0.85),
                                      borderRadius: const BorderRadius.only(
                                        bottomRight: Radius.circular(8),
                                      ),
                                      border: Border.all(color: ThemeService.border),
                                    ),
                                    child: Text(
                                      item.episodes != null ? "EP ${item.episodes}" : "AIRING",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                // Score badge (Bottom-Left or Top-Right)
                                if (item.averageScore != null)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: ThemeService.surface.withOpacity(0.92),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: ThemeService.border),
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
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 1-line crisp title
                        Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Metadata: Format • Episodes
                        Text(
                          "${item.format ?? 'TV'} • ${item.episodes != null ? '${item.episodes} EPS' : 'Ongoing'}",
                          style: const TextStyle(
                            color: ThemeService.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

  // --------------------------------------------------------------------------
  // TRENDING MANGA SECTION
  // --------------------------------------------------------------------------
  Widget _buildMangaHorizontalSection(Color accent) {
    if (_trendingManga.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Trending Manga & Webtoons 📖",
                    style: TextStyle(color: Colors.white, fontSize: 17.5, fontWeight: FontWeight.bold),
                  ),
                  InkWell(
                    onTap: _openManga,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        "Explore Manga ›",
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 270,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemExtent: 148.0,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                itemCount: _trendingManga.length,
                itemBuilder: (context, index) {
                  final item = _trendingManga[index];
                  return GestureDetector(
                    onTap: () => _openMangaDetail(item),
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 195,
                              decoration: BoxDecoration(
                                border: Border.all(color: ThemeService.border),
                              ),
                              child: ShikaiNetworkImage(
                                imageUrl: item.coverImage,
                                placeholderTitle: item.displayTitle,
                                fit: BoxFit.cover,
                                width: 140,
                                isManga: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.chapters != null ? "${item.chapters} Chs" : "Ongoing",
                            style: const TextStyle(color: ThemeService.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // GENRE CHIPS SECTION (Seanime Tenji Tags)
  // --------------------------------------------------------------------------
  Widget _buildGenreSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, left: 16.0, right: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Browse Genres",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _genres.map((g) {
              return ActionChip(
                backgroundColor: ThemeService.surface,
                label: Text(g, style: const TextStyle(color: ThemeService.textMuted, fontSize: 12)),
                side: const BorderSide(color: ThemeService.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onPressed: () => _openCatalog("$g Anime", "genre", genre: g),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ENDLESS ANIME FEED ("Dher Sara Anime" - Infinite Exploration Feed)
  // --------------------------------------------------------------------------
  Widget _buildInfiniteFeedSection(Color accent) {
    if (_infiniteFeed.isEmpty && !_isLoadingMoreInfinite) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 26.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "More Anime to Explore 🚀",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        "Endless collection • Keeps loading as you scroll down",
                        style: TextStyle(
                          color: ThemeService.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.all_inclusive, size: 13, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        "INFINITE",
                        style: TextStyle(
                          color: accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3-Column Endless Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _infiniteFeed.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.57,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
              ),
              itemBuilder: (context, index) {
                final anime = _infiniteFeed[index];
                return RepaintBoundary(child: _buildGridAnimeCard(anime, accent));
              },
            ),
          ),

          // Endless Loading Spinner
          if (_isLoadingMoreInfinite)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Summoning more anime... ⚡",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!_hasMoreInfinite)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  "You've explored the entire anime galaxy! 🌌",
                  style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridAnimeCard(AnilistMedia item, Color accent) {
    return GestureDetector(
      onTap: () => _openDetail(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeService.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShikaiNetworkImage(
                      imageUrl: item.coverImage,
                      placeholderTitle: item.displayTitle,
                    ),
                    // Score Pill
                    if (item.averageScore != null)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: ThemeService.surface.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 9),
                              const SizedBox(width: 2),
                              Text(
                                (item.averageScore! / 10).toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Episode Pill
                    if (item.episodes != null)
                      Positioned(
                        bottom: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: ThemeService.background.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: Text(
                            "EP ${item.episodes}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            item.format ?? 'TV',
            style: const TextStyle(
              color: ThemeService.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeService.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("App Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bolt, color: ThemeService.currentAccent),
                title: const Text("Streaming Engine", style: TextStyle(color: Colors.white)),
                subtitle: const Text("Ultra-fast direct stream active", style: TextStyle(color: ThemeService.textMuted, fontSize: 12)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text("Clear Watch History", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await WatchHistoryService.clearAll();
                  if (!mounted) return;
                  _loadContinueWatching();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeService.surface,
        title: const Text("Shikai Anime v2.0", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Powered by high-performance streaming architecture and AniList catalog.\n\nEnjoy seamless, crystal-clear anime streaming directly on your device.",
          style: TextStyle(color: ThemeService.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: ThemeService.currentAccent)),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// ANILIST LIVE SEARCH DELEGATE (Seanime Tenji styling)
// ----------------------------------------------------------------------------
class AnimeSearchDelegate extends SearchDelegate {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: ThemeService.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: ThemeService.surface,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: ThemeService.textMuted),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text("Search anime (e.g. Solo Leveling, Naruto, Bleach)", style: TextStyle(color: Colors.white38)),
      );
    }
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<AnilistMedia>>(
      future: AnimeAggregatorService.searchUnified(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: ThemeService.currentAccent));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text("No anime found matching your search.", style: TextStyle(color: ThemeService.textMuted)),
          );
        }

        final results = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ThemeService.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ThemeService.border),
              ),
              child: ListTile(
                leading: ShikaiNetworkImage(
                  imageUrl: item.coverImage,
                  placeholderTitle: item.displayTitle,
                  width: 44,
                  height: 60,
                  borderRadius: BorderRadius.circular(6),
                ),
                title: Text(item.displayTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: Text(item.genres.join(', '), style: const TextStyle(color: ThemeService.textMuted, fontSize: 11.5)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: ThemeService.textDarkMuted),
                onTap: () {
                  close(context, null);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AnimeDetailScreen(media: item)),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
