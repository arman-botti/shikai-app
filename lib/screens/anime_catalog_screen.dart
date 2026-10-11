import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/anime_detail_screen.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class AnimeCatalogScreen extends StatefulWidget {
  final String title;
  final String mode; // 'trending', 'popular', 'airing', 'genre', 'watchlist'
  final String? genre;

  const AnimeCatalogScreen({
    Key? key,
    required this.title,
    required this.mode,
    this.genre,
  }) : super(key: key);

  @override
  State<AnimeCatalogScreen> createState() => _AnimeCatalogScreenState();
}

class _AnimeCatalogScreenState extends State<AnimeCatalogScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<AnilistMedia> _animeList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadAnime(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore && widget.mode != 'watchlist') {
        _loadAnime();
      }
    }
  }

  Future<void> _loadAnime({bool refresh = false}) async {
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

    try {
      List<AnilistMedia> newItems = [];

      if (widget.mode == 'watchlist') {
        final watchlist = await WatchHistoryService.getWatchlist();
        newItems = watchlist.map((j) => AnilistMedia.fromJson(j)).toList();
        _hasMore = false;
      } else if (widget.mode == 'history') {
        final history = await WatchHistoryService.getContinueWatching();
        newItems = history.map((h) => AnilistMedia(
          id: h.anilistId,
          title: h.title,
          englishTitle: h.title,
          coverImage: h.coverImage,
          genres: ['EP ${h.episodeNumber}'],
        )).toList();
        _hasMore = false;
      } else if (widget.mode == 'trending') {
        newItems = await AnilistService.getTrendingAnime(page: _page, perPage: 21);
      } else if (widget.mode == 'popular') {
        newItems = await AnilistService.getPopularAnime(page: _page, perPage: 21);
      } else if (widget.mode == 'airing') {
        newItems = await AnilistService.getTopAiring(page: _page, perPage: 21);
      } else if (widget.mode == 'movies') {
        newItems = await AnilistService.getMovies(page: _page, perPage: 21);
      } else if (widget.mode == 'updated') {
        newItems = await AnilistService.getRecentlyUpdated(page: _page, perPage: 21);
      } else if (widget.mode == 'top_rated') {
        newItems = await AnilistService.getTopRated(page: _page, perPage: 21);
      } else if (widget.mode == 'upcoming') {
        newItems = await AnilistService.getUpcomingAnime(page: _page, perPage: 21);
      } else if (widget.mode == 'genre' && widget.genre != null) {
        newItems = await AnilistService.getAnimeByGenre(widget.genre!, page: _page, perPage: 21);
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _animeList.clear();
          }
          _animeList.addAll(newItems);
          _isLoading = false;
          _isLoadingMore = false;
          if (newItems.length < 21) {
            _hasMore = false;
          } else {
            _page++;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        return Scaffold(
          backgroundColor: ThemeService.background,
          appBar: AppBar(
            backgroundColor: ThemeService.background,
            elevation: 0,
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
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 17),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 17.5, fontWeight: FontWeight.bold),
            ),
          ),
          body: RefreshIndicator(
            color: accent,
            backgroundColor: ThemeService.surface,
            onRefresh: () => _loadAnime(refresh: true),
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: accent),
                  )
                : _animeList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.movie_outlined,
                              size: 54,
                              color: ThemeService.textDarkMuted,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.mode == 'watchlist'
                                  ? "Your watchlist is empty."
                                  : "No anime found in this category.",
                              style: const TextStyle(color: ThemeService.textMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.all(12.0),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 14,
                                childAspectRatio: 0.57,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = _animeList[index];
                                  return _buildAnimeGridCard(item, accent);
                                },
                                childCount: _animeList.length,
                              ),
                            ),
                          ),
                          if (_isLoadingMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Center(
                                  child: CircularProgressIndicator(color: accent, strokeWidth: 2),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 40),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }

  Widget _buildAnimeGridCard(AnilistMedia item, Color accent) {
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
          // Seanime Media Poster Card
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
                      borderRadius: BorderRadius.circular(11),
                    ),
                    // Gradient Shadow
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            ThemeService.background.withOpacity(0.7),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.6, 1.0],
                        ),
                      ),
                    ),
                    // Score Badge
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
                                style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Episodes Count Pill at Bottom-Left
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
          // Title
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
}
