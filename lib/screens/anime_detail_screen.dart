import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/anivexa_episode.dart';
import 'package:shikai_app/models/franchise_data.dart';
import 'package:shikai_app/services/anivexa_service.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/player_screen.dart';
import 'package:shikai_app/screens/manga_detail_screen.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class AnimeDetailScreen extends StatefulWidget {
  final AnilistMedia media;

  const AnimeDetailScreen({Key? key, required this.media}) : super(key: key);

  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  int _selectedEpisode = 1;
  String _selectedAudio = 'sub'; // 'sub' or 'dub'
  bool _isSynopsisExpanded = false;

  bool _isAscending = true;

  // Watch history & Watched tracking
  Set<int> _watchedEpisodes = {};
  WatchHistoryItem? _historyItem;
  bool _isBookmarked = false;
  bool _unwatchedOnly = false; // Filter to unwatched episodes

  // Anivexa API Episodes
  List<AnivexaEpisode> _subEpisodes = [];
  List<AnivexaEpisode> _dubEpisodes = [];
  bool _isLoadingEpisodes = true;

  // Franchise Universe & Seasons Engine
  FranchiseData? _franchiseData;
  bool _isLoadingFranchise = true;
  FranchiseCategory _selectedFranchiseCategory = FranchiseCategory.seasons;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await Future.wait([
      _loadAnivexaEpisodes(),
      _loadWatchStatus(),
      _loadFranchise(),
    ]);
  }

  Future<void> _loadFranchise() async {
    try {
      final data = await AnilistService.getAnimeFranchise(widget.media.id);
      if (mounted) {
        setState(() {
          _franchiseData = data;
          _isLoadingFranchise = false;
          final avail = data.availableCategories;
          if (avail.isNotEmpty && !avail.contains(_selectedFranchiseCategory)) {
            _selectedFranchiseCategory = avail.first;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingFranchise = false);
    }
  }

  Future<void> _loadWatchStatus() async {
    final watched = await WatchHistoryService.getWatchedEpisodeNumbers(widget.media.id);
    final historyList = await WatchHistoryService.getContinueWatching();
    final isBookmarked = await WatchHistoryService.isInWatchlist(widget.media.id);

    WatchHistoryItem? history;
    try {
      history = historyList.firstWhere((h) => h.anilistId == widget.media.id);
    } catch (_) {
      history = null;
    }

    if (mounted) {
      setState(() {
        _watchedEpisodes = watched;
        _historyItem = history;
        _isBookmarked = isBookmarked;

        // Auto-select episode: resume if in progress, else first unwatched
        final total = (_selectedAudio == 'dub' ? _dubEpisodes.length : _subEpisodes.length);
        final maxEp = total > 0 ? total : (widget.media.episodes ?? 12);

        int targetEp = 1;
        if (history != null && history.progressPercentage < 0.9) {
          targetEp = history.episodeNumber;
        } else {
          for (int i = 1; i <= maxEp; i++) {
            if (!_watchedEpisodes.contains(i)) {
              targetEp = i;
              break;
            }
          }
        }
        _selectedEpisode = targetEp;
      });
    }
  }

  Future<void> _toggleWatchlist() async {
    await WatchHistoryService.toggleWatchlist(widget.media.toJson());
    final isBookmarked = await WatchHistoryService.isInWatchlist(widget.media.id);
    if (mounted) {
      setState(() {
        _isBookmarked = isBookmarked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isBookmarked ? "Added to Watchlist ❤️" : "Removed from Watchlist"),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleEpisodeWatched(int epNum) async {
    final isNowWatched = await WatchHistoryService.toggleEpisodeWatched(widget.media.id, epNum);
    setState(() {
      if (isNowWatched) {
        _watchedEpisodes.add(epNum);
      } else {
        _watchedEpisodes.remove(epNum);
      }
    });
  }

  Future<void> _loadAnivexaEpisodes() async {
    final epMap = await AnivexaService.getEpisodes(widget.media.id);
    List<AnivexaEpisode> sub = epMap['sub'] ?? [];
    List<AnivexaEpisode> dub = epMap['dub'] ?? [];

    // Smart Fallback: If provider catalog returns 0 episodes, synthesize from AniList episode count
    if (sub.isEmpty) {
      final total = widget.media.episodes ?? 12;
      if (total > 0) {
        sub = List.generate(
          total,
          (i) => AnivexaEpisode(
            number: i + 1,
            title: 'Episode ${i + 1}',
            audio: 'sub',
            watchId: '${widget.media.id}/${i + 1}',
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _subEpisodes = sub;
        _dubEpisodes = dub;
        _isLoadingEpisodes = false;
      });
    }
  }

  void _watchEpisode(int episodeNumber) async {
    setState(() {
      _selectedEpisode = episodeNumber;
    });

    final currentEpisodesList = _selectedAudio == 'dub' ? _dubEpisodes : _subEpisodes;
    final totalEps = currentEpisodesList.isNotEmpty
        ? currentEpisodesList.length
        : (widget.media.episodes ?? 12);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          anilistId: widget.media.id,
          title: widget.media.displayTitle,
          coverImage: widget.media.coverImage,
          episodeNumber: episodeNumber,
          totalEpisodes: totalEps,
          initialAudio: _selectedAudio,
          episodes: currentEpisodesList,
        ),
      ),
    );

    // Refresh watch status after returning from video playback
    _loadWatchStatus();
  }

  String _formatEpisodeDisplayTitle(AnivexaEpisode ep) {
    String rawTitle = ep.title.trim();
    final animeTitle = widget.media.title.trim();
    final englishTitle = widget.media.englishTitle.trim();

    // Strip anime title prefix if present (e.g. "Bleach Episode 1: The Day" -> "The Day")
    if (animeTitle.isNotEmpty && rawTitle.toLowerCase().startsWith(animeTitle.toLowerCase())) {
      rawTitle = rawTitle.substring(animeTitle.length).trim();
    } else if (englishTitle.isNotEmpty && rawTitle.toLowerCase().startsWith(englishTitle.toLowerCase())) {
      rawTitle = rawTitle.substring(englishTitle.length).trim();
    }

    // Strip leading punctuation/delimiters like "-", ":", "•"
    rawTitle = rawTitle.replaceAll(RegExp(r'^[-:•–—\s]+'), '').trim();

    // Strip redundant "Episode X" or "Ep X" prefix if followed by a real name
    final epPrefixRegex = RegExp(r'^(Episode|Ep|EP)\s*\d+[-:•–—\s]*', caseSensitive: false);
    final stripped = rawTitle.replaceFirst(epPrefixRegex, '').trim();

    if (stripped.isNotEmpty && !stripped.toLowerCase().startsWith('episode')) {
      return "Episode ${ep.number} • $stripped";
    }
    return "Episode ${ep.number}";
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final currentEpisodesList = _selectedAudio == 'dub' ? _dubEpisodes : _subEpisodes;
    final totalEpisodes = currentEpisodesList.isNotEmpty
        ? currentEpisodesList.length
        : (media.episodes ?? 12);

    // Direct clean episodes list without range chunk barriers
    List<AnivexaEpisode> visibleEpisodes = [];
    if (currentEpisodesList.isNotEmpty) {
      visibleEpisodes = currentEpisodesList.where((ep) {
        if (_unwatchedOnly) {
          return !_watchedEpisodes.contains(ep.number);
        }
        return true;
      }).toList();

      if (!_isAscending) {
        visibleEpisodes = visibleEpisodes.reversed.toList();
      }
    }

    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        return Scaffold(
          backgroundColor: ThemeService.background,
          body: CustomScrollView(
            slivers: [
              // 1. Seanime-Style Immersive Backdrop SliverAppBar
              SliverAppBar(
                expandedHeight: 310,
                pinned: true,
                elevation: 0,
                backgroundColor: ThemeService.background,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: ThemeService.surface.withOpacity(0.85),
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
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: ThemeService.surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: ThemeService.border),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                            color: _isBookmarked ? accent : Colors.white,
                            size: 20,
                          ),
                          onPressed: _toggleWatchlist,
                        ),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      ShikaiNetworkImage(
                        imageUrl: media.bannerImage ?? media.coverImage,
                        placeholderTitle: media.displayTitle,
                      ),
                      // Seanime Tenji Top & Bottom Gradients
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.72),
                              Colors.black.withOpacity(0.2),
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
                      // Overlap Poster & Info Row on Banner
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 95,
                              height: 135,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: ThemeService.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.6),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ShikaiNetworkImage(
                                imageUrl: media.coverImage,
                                placeholderTitle: media.displayTitle,
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    media.displayTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (media.averageScore != null)
                                        _buildPill(
                                          icon: Icons.star,
                                          iconColor: Colors.amber,
                                          label: (media.averageScore! / 10).toStringAsFixed(1),
                                          color: ThemeService.surface,
                                          textColor: Colors.white,
                                          border: ThemeService.border,
                                        ),
                                      if (media.format != null)
                                        _buildPill(
                                          label: media.format!,
                                          color: ThemeService.surface,
                                          textColor: ThemeService.textMuted,
                                          border: ThemeService.border,
                                        ),
                                      _buildPill(
                                        label: "$totalEpisodes EPS",
                                        color: accent.withOpacity(0.18),
                                        textColor: accent,
                                        border: accent.withOpacity(0.4),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Seanime Controls & Metadata Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Audio Toggle Bar (Sub / Dub)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: ThemeService.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ThemeService.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildAudioTab(
                                title: "🇯🇵 Japanese Sub",
                                count: _subEpisodes.isNotEmpty ? _subEpisodes.length : totalEpisodes,
                                isSelected: _selectedAudio == 'sub',
                                accent: accent,
                                onTap: () => setState(() => _selectedAudio = 'sub'),
                              ),
                            ),
                            Expanded(
                              child: _buildAudioTab(
                                title: "🇬🇧 English Dub",
                                count: _dubEpisodes.isNotEmpty ? _dubEpisodes.length : 0,
                                isSelected: _selectedAudio == 'dub',
                                accent: accent,
                                onTap: () => setState(() => _selectedAudio = 'dub'),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Big Play Selected Episode Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.play_arrow, size: 24, color: Colors.white),
                          label: Text(
                            (_historyItem != null &&
                                    _historyItem!.episodeNumber == _selectedEpisode &&
                                    _historyItem!.positionSeconds > 10 &&
                                    _historyItem!.progressPercentage < 0.9)
                                ? "Resume EP $_selectedEpisode (${(_historyItem!.positionSeconds ~/ 60)}m ${(_historyItem!.positionSeconds % 60)}s)"
                                : _watchedEpisodes.contains(_selectedEpisode)
                                    ? "Replay Episode $_selectedEpisode"
                                    : "Watch Episode $_selectedEpisode",
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          onPressed: () => _watchEpisode(_selectedEpisode),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Enhanced Synopsis with Read More / Show Less Toggle
                      if (media.description != null && media.description!.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSynopsisExpanded = !_isSynopsisExpanded;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: ThemeService.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ThemeService.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Synopsis",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _isSynopsisExpanded ? "Show Less" : "Read More",
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          _isSynopsisExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: accent,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  media.description!.replaceAll(RegExp(r'<[^>]*>|\\n'), ' ').trim(),
                                  maxLines: _isSynopsisExpanded ? null : 4,
                                  overflow: _isSynopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD1D5DB),
                                    fontSize: 13.5,
                                    height: 1.5,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Franchise Universe & Related Series Section
                      _buildFranchiseSection(accent),

                      // Seanime-Style Episodes Header with Range Selector & Order Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "Episodes",
                                style: TextStyle(color: Colors.white, fontSize: 17.5, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "($totalEpisodes)",
                                style: const TextStyle(color: ThemeService.textMuted, fontSize: 14),
                              ),
                              if (_isLoadingEpisodes) ...[
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(color: accent, strokeWidth: 2),
                                ),
                              ],
                            ],
                          ),
                          // Ascending / Descending Toggle
                          IconButton(
                            tooltip: _isAscending ? "Oldest First" : "Latest First",
                            icon: Icon(
                              _isAscending ? Icons.arrow_downward : Icons.arrow_upward,
                              color: accent,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _isAscending = !_isAscending;
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Filter Chips: All Episodes vs Unwatched Only
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilterChip(
                            label: Text("All ($totalEpisodes)"),
                            selected: !_unwatchedOnly,
                            selectedColor: accent.withOpacity(0.18),
                            checkmarkColor: accent,
                            labelStyle: TextStyle(
                              color: !_unwatchedOnly ? accent : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: !_unwatchedOnly ? accent : ThemeService.border,
                              ),
                            ),
                            onSelected: (val) {
                              setState(() => _unwatchedOnly = false);
                            },
                          ),
                          FilterChip(
                            avatar: const Icon(Icons.remove_red_eye_outlined, size: 14, color: Colors.amberAccent),
                            label: Text(
                              "Remaining (${(totalEpisodes - _watchedEpisodes.length).clamp(0, totalEpisodes)})",
                            ),
                            selected: _unwatchedOnly,
                            selectedColor: Colors.amberAccent.withOpacity(0.18),
                            checkmarkColor: Colors.amberAccent,
                            labelStyle: TextStyle(
                              color: _unwatchedOnly ? Colors.amberAccent : ThemeService.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            backgroundColor: ThemeService.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: _unwatchedOnly ? Colors.amberAccent : ThemeService.border,
                              ),
                            ),
                            onSelected: (val) {
                              setState(() => _unwatchedOnly = true);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // 3. Seanime Episode List Items
              if (visibleEpisodes.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final ep = visibleEpisodes[index];
                        final isSelected = ep.number == _selectedEpisode;
                        final isWatched = _watchedEpisodes.contains(ep.number);

                        return Opacity(
                          opacity: isWatched ? 0.75 : 1.0,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? accent.withOpacity(0.12) : ThemeService.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? accent : ThemeService.border,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _watchEpisode(ep.number),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Row(
                                  children: [
                                    // Episode 16:9 Thumbnail
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: ThemeService.border),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: Stack(
                                          children: [
                                            ShikaiNetworkImage(
                                              imageUrl: (ep.image != null && ep.image!.isNotEmpty)
                                                  ? ep.image!
                                                  : (media.bannerImage ?? media.coverImage),
                                              width: 110,
                                              height: 66,
                                              placeholderTitle: 'EP ${ep.number}',
                                              borderRadius: BorderRadius.circular(7),
                                            ),
                                            Positioned.fill(
                                              child: Center(
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    isSelected ? Icons.play_arrow : Icons.play_arrow_outlined,
                                                    color: isSelected ? accent : Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Episode Title & Metadata
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatEpisodeDisplayTitle(ep),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? accent
                                                  : isWatched
                                                      ? ThemeService.textMuted
                                                      : Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Row(
                                            children: [
                                              if (isWatched) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981).withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF10B981)),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        ep.duration != null ? "${(ep.duration! / 60).round()}m" : "Completed",
                                                        style: const TextStyle(
                                                          color: Color(0xFF10B981),
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                              ],
                                              if (ep.duration != null)
                                                Text(
                                                  "${(ep.duration! / 60).round()}m",
                                                  style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                                                ),
                                            ],
                                          ),
                                          if (ep.description != null && ep.description!.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              ep.description!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Checkmark Toggle Button
                                    IconButton(
                                      icon: Icon(
                                        isWatched ? Icons.check_circle : Icons.radio_button_unchecked,
                                        color: isWatched ? const Color(0xFF10B981) : ThemeService.textDarkMuted,
                                        size: 20,
                                      ),
                                      tooltip: isWatched ? "Clear progress" : "Mark completed",
                                      onPressed: () => _toggleEpisodeWatched(ep.number),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: visibleEpisodes.length,
                    ),
                  ),
                )
              else if (_unwatchedOnly)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: ThemeService.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ThemeService.border),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.done_all, color: Color(0xFF10B981), size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          "All Caught Up!",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "You've watched all episodes in this range.",
                          style: TextStyle(color: ThemeService.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => setState(() => _unwatchedOnly = false),
                          child: const Text("Show All Episodes", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isLoadingEpisodes)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: ThemeService.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ThemeService.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 110,
                                height: 66,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 140,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 70,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.04),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: 4,
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: ThemeService.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ThemeService.border),
                    ),
                    child: const Center(
                      child: Text(
                        "No episodes available for this selection.",
                        style: TextStyle(color: ThemeService.textMuted, fontSize: 13),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 60),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildAudioTab({
    required String title,
    required int count,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            "$title ($count)",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Colors.white : ThemeService.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    IconData? icon,
    Color? iconColor,
    required String label,
    required Color color,
    required Color textColor,
    Color? border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFranchiseSection(Color accent) {
    if (_isLoadingFranchise) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.layers_rounded, color: accent, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Franchise & Seasons",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(color: accent, strokeWidth: 2),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 215,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                itemBuilder: (_, __) => Container(
                  width: 126,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: ThemeService.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ThemeService.border),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_franchiseData == null || _franchiseData!.isEmpty) {
      return const SizedBox.shrink();
    }

    final categories = _franchiseData!.availableCategories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final currentCategoryItems = _franchiseData!.itemsForCategory(_selectedFranchiseCategory);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.layers_rounded, color: accent, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                "Franchise & Seasons",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: ThemeService.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ThemeService.border),
                ),
                child: Text(
                  "${_franchiseData!.totalCount}",
                  style: const TextStyle(
                    color: ThemeService.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                "Chronological Timeline",
                style: TextStyle(
                  color: ThemeService.textDarkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category Chips Bar (Seasons / Movies / OVAs / Manga)
          if (categories.length > 1) ...[
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cat = categories[idx];
                  final isSelected = cat == _selectedFranchiseCategory;
                  final count = _franchiseData!.itemsForCategory(cat).length;
                  final label = _franchiseData!.categoryLabel(cat);

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedFranchiseCategory = cat);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? accent.withOpacity(0.18) : ThemeService.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? accent : ThemeService.border,
                          width: isSelected ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : ThemeService.textMuted,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected ? accent.withOpacity(0.3) : Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "$count",
                              style: TextStyle(
                                color: isSelected ? accent : ThemeService.textDarkMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Horizontal Shelf of Franchise Cards
          if (currentCategoryItems.isNotEmpty)
            SizedBox(
              height: 228,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: currentCategoryItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = currentCategoryItems[index];
                  return RepaintBoundary(
                    child: _buildFranchiseCard(context, item, accent),
                  );
                },
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                "No entries in this category",
                style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFranchiseCard(BuildContext context, FranchiseItem item, Color accent) {
    final isCurrent = item.isCurrent;

    return GestureDetector(
      onTap: () {
        if (isCurrent) {
          HapticFeedback.selectionClick();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Already viewing ${item.seasonLabel} (${item.displayTitle})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              backgroundColor: const Color(0xFF1F2438),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 1400),
            ),
          );
          return;
        }

        if (item.isManga) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MangaDetailScreen(manga: item.rawMedia),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AnimeDetailScreen(media: item.rawMedia),
            ),
          );
        }
      },
      child: SizedBox(
        width: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster Container with Glowing Active Border & Badges
            Container(
              height: 165,
              width: 126,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent ? accent : ThemeService.border,
                  width: isCurrent ? 2.0 : 1.0,
                ),
                boxShadow: [
                  if (isCurrent)
                    BoxShadow(
                      color: accent.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isCurrent ? 8 : 9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShikaiNetworkImage(
                      imageUrl: item.coverImage,
                      placeholderTitle: item.displayTitle,
                      borderRadius: BorderRadius.circular(isCurrent ? 8 : 9),
                    ),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.65),
                            Colors.transparent,
                            Colors.black.withOpacity(0.9),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    // Top-Left Smart Season Tag Pill with Icon
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: item.tagColor.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: item.tagColor.withOpacity(0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.tagIcon, size: 9, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              item.seasonTag,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Top-Right "ACTIVE" Badge if Current Media
                    if (isCurrent)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Text(
                            "ACTIVE",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    // Bottom Metadata Row (Format & Score/Episodes)
                    Positioned(
                      bottom: 5,
                      left: 6,
                      right: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (item.format != null)
                            Text(
                              item.format!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          if (item.averageScore != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 9),
                                const SizedBox(width: 2),
                                Text(
                                  (item.averageScore! / 10).toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          else if (item.episodes != null)
                            Text(
                              "${item.episodes} Ep",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Clean Stripped Season Title (e.g. "Season 2", "Entertainment District Arc")
            Text(
              item.shortTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? accent : const Color(0xFFE4E4E7),
                fontSize: 11.5,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                height: 1.22,
              ),
            ),
            const SizedBox(height: 2),
            // Release Year & Subtitle Label
            Text(
              item.releaseYear != null ? "${item.releaseYear} • ${item.seasonLabel}" : item.seasonLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeService.textDarkMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
