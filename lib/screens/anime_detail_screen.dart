import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/anivexa_episode.dart';
import 'package:shikai_app/services/anivexa_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/player_screen.dart';
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

  // Seanime style pagination & sorting
  int _selectedRangeIndex = 0;
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

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await Future.wait([
      _loadAnivexaEpisodes(),
      _loadWatchStatus(),
    ]);
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

        // Automatically position range bucket to include this episode
        const chunkSize = 25;
        _selectedRangeIndex = ((_selectedEpisode - 1) / chunkSize).floor();
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

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final currentEpisodesList = _selectedAudio == 'dub' ? _dubEpisodes : _subEpisodes;
    final totalEpisodes = currentEpisodesList.isNotEmpty
        ? currentEpisodesList.length
        : (media.episodes ?? 12);

    // Seanime-style Range Buckets (25 episodes per chunk)
    const chunkSize = 25;
    final numRanges = (totalEpisodes / chunkSize).ceil().clamp(1, 100);
    if (_selectedRangeIndex >= numRanges) {
      _selectedRangeIndex = 0;
    }

    final startEp = (_selectedRangeIndex * chunkSize) + 1;
    final endEp = ((_selectedRangeIndex + 1) * chunkSize).clamp(1, totalEpisodes);

    // Filter and sort for the active batch
    List<AnivexaEpisode> visibleEpisodes = [];
    if (currentEpisodesList.isNotEmpty) {
      visibleEpisodes = currentEpisodesList.where((ep) {
        final inRange = ep.number >= startEp && ep.number <= endEp;
        if (!inRange) return false;
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
                              "Unwatched (${(totalEpisodes - _watchedEpisodes.length).clamp(0, totalEpisodes)})",
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

                      // Range Bucket Chips (e.g. 1-25, 26-50...)
                      if (numRanges > 1) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: numRanges,
                            itemBuilder: (context, index) {
                              final rStart = (index * chunkSize) + 1;
                              final rEnd = ((index + 1) * chunkSize).clamp(1, totalEpisodes);
                              final isRangeActive = index == _selectedRangeIndex;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedRangeIndex = index;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isRangeActive ? accent : ThemeService.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isRangeActive ? accent : ThemeService.border),
                                  ),
                                  child: Text(
                                    "$rStart - $rEnd",
                                    style: TextStyle(
                                      color: isRangeActive ? Colors.white : ThemeService.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

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
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? accent
                                                      : ThemeService.background,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: isSelected ? accent : ThemeService.border),
                                                ),
                                                child: Text(
                                                  "EP ${ep.number}",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              if (isWatched)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981).withOpacity(0.18),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.check, size: 10, color: Color(0xFF10B981)),
                                                      SizedBox(width: 2),
                                                      Text(
                                                        "Watched",
                                                        style: TextStyle(
                                                          color: Color(0xFF10B981),
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (ep.duration != null)
                                                Text(
                                                  "${(ep.duration! / 60).round()}m",
                                                  style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            ep.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? accent
                                                  : isWatched
                                                      ? ThemeService.textMuted
                                                      : Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                                      tooltip: isWatched ? "Mark as unwatched" : "Mark as watched",
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
              else
                // Fallback Grid for any anime where Anivexa metadata is still loading
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.4,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final epNum = _isAscending ? (startEp + index) : (endEp - index);
                        final isSelected = epNum == _selectedEpisode;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _watchEpisode(epNum),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? accent : ThemeService.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? accent : ThemeService.border,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                "$epNum",
                                style: TextStyle(
                                  color: isSelected ? Colors.white : ThemeService.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: (endEp - startEp + 1).clamp(0, totalEpisodes),
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
}
