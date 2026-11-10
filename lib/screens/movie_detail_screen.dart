import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_player_screen.dart';
import 'package:shikai_app/services/moviebox_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

typedef MovieboxDetailLoader = Future<MovieboxDetail> Function(String subjectId);
typedef MovieboxSeasonsLoader = Future<List<MovieboxSeason>> Function(String subjectId);

class MovieDetailScreen extends StatefulWidget {
  final String subjectId;
  final String title;
  final String? cover;
  final String? detailPath;
  final bool isSeries;
  final MovieboxDetailLoader? detailLoader;
  final MovieboxSeasonsLoader? seasonsLoader;

  const MovieDetailScreen({
    Key? key,
    required this.subjectId,
    required this.title,
    this.cover,
    this.detailPath,
    this.isSeries = false,
    this.detailLoader,
    this.seasonsLoader,
  }) : super(key: key);

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  MovieboxDetail? _detail;
  List<MovieboxSeason> _seasons = [];
  String? _selectedDubId;
  int _selectedSeason = 0;

  bool _isLoading = true;
  bool _isResolving = false;
  String? _error;
  String _resolvingLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final detailLoader = widget.detailLoader ?? MovieboxService.getDetail;
      final detail = await detailLoader(widget.subjectId);
      final seasonsLoader = widget.seasonsLoader ?? MovieboxService.getSeasons;
      final seasons = detail.isSeries ? await seasonsLoader(detail.id) : <MovieboxSeason>[];

      if (!mounted) return;
      setState(() {
        _detail = detail;
        _seasons = seasons;
        _selectedSeason = seasons.isNotEmpty ? seasons.first.season : 0;
        _selectedDubId = detail.id;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _play({int season = 0, int episode = 0}) async {
    final detail = _detail;
    if (detail == null || _isResolving) return;

    final subjectId = _selectedDubId ?? detail.id;
    setState(() {
      _isResolving = true;
      _resolvingLabel = episode > 0 ? 'Resolving S$season E$episode...' : 'Resolving stream...';
    });

    try {
      var detailPath = detail.detailPath;
      if (subjectId != detail.id) {
        try {
          final dubDetail = await MovieboxService.getDetail(subjectId);
          if (dubDetail.detailPath != null && dubDetail.detailPath!.isNotEmpty) {
            detailPath = dubDetail.detailPath;
          }
        } catch (_) {}
      }

      final streams = await MovieboxService.getStreams(
        subjectId,
        season: season,
        episode: episode,
        detailPath: detailPath,
      );

      var playable = streams.where((s) => s.isMp4 && s.url.isNotEmpty).toList();
      final fullLength = playable
          .where((s) => s.durationSec == null || s.durationSec! > 120)
          .toList();
      if (fullLength.isNotEmpty) playable = fullLength;

      if (!mounted) return;
      setState(() => _isResolving = false);

      if (playable.isEmpty) {
        _showUnavailable();
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoviePlayerScreen(
            title: detail.title,
            subtitle: episode > 0 ? 'Season $season • Episode $episode' : null,
            streams: playable,
            subjectId: subjectId,
            season: season,
            episode: episode,
            seasons: _seasons,
            detailPath: detailPath,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stream error: $e')),
      );
    }
  }

  void _showUnavailable() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeService.surface,
        title: const Text('Stream not available', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'MovieBox pe is title ka stream abhi available nahi hai. Doosra audio ya episode try karo.',
          style: TextStyle(color: ThemeService.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: ThemeService.crimson)),
          ),
        ],
      ),
    );
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
                color: Colors.black.withOpacity(0.5),
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
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_isResolving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.72),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: ThemeService.crimson),
                      const SizedBox(height: 16),
                      Text(
                        _resolvingLabel,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ThemeService.crimson));
    }

    if (_error != null || _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: ThemeService.textMuted, size: 46),
              const SizedBox(height: 14),
              Text(
                _error ?? 'Detail load nahi hui',
                textAlign: TextAlign.center,
                style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: ThemeService.crimson),
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final dubs = <MovieboxDub>[
      MovieboxDub(id: detail.id, name: 'Original Audio'),
      ...detail.dubs.where((d) => d.id.isNotEmpty && d.id != detail.id),
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildHero(detail),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetaRow(detail),
              if (detail.genre != null && detail.genre!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: detail.genre!
                      .split(',')
                      .map((g) => g.trim())
                      .where((g) => g.isNotEmpty)
                      .map((g) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: ThemeService.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: ThemeService.border),
                            ),
                            child: Text(
                              g,
                              style: const TextStyle(color: ThemeService.textMuted, fontSize: 10.5),
                            ),
                          ))
                      .toList(),
                ),
              ],
              if (detail.description != null && detail.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  detail.description!.trim(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.55),
                ),
              ],
              if (dubs.length > 1) ...[
                const SizedBox(height: 20),
                const Text(
                  'AUDIO',
                  style: TextStyle(
                    color: ThemeService.textDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: dubs.length,
                    itemBuilder: (context, index) {
                      final dub = dubs[index];
                      final selected = _selectedDubId == dub.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDubId = dub.id),
                        child: Container(
                          margin: const EdgeInsets.only(right: 7),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? ThemeService.crimson : ThemeService.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? ThemeService.crimson : ThemeService.border,
                            ),
                          ),
                          child: Text(
                            dub.name,
                            style: TextStyle(
                              color: selected ? Colors.white : ThemeService.textMuted,
                              fontSize: 11.5,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (!detail.isSeries || _seasons.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeService.crimson,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _play(),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      'Watch Now',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              if (detail.isSeries) ...[
                const Text(
                  'SEASONS',
                  style: TextStyle(
                    color: ThemeService.textDarkMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 9),
                if (_seasons.isEmpty)
                  const Text(
                    'Episodes unavailable',
                    style: TextStyle(color: ThemeService.textMuted, fontSize: 12),
                  )
                else ...[
                  SizedBox(
                    height: 34,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _seasons.length,
                      itemBuilder: (context, index) {
                        final season = _seasons[index];
                        final selected = _selectedSeason == season.season;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSeason = season.season),
                          child: Container(
                            margin: const EdgeInsets.only(right: 7),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? ThemeService.crimson : ThemeService.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected ? ThemeService.crimson : ThemeService.border,
                              ),
                            ),
                            child: Text(
                              'Season ${season.season}',
                              style: TextStyle(
                                color: selected ? Colors.white : ThemeService.textMuted,
                                fontSize: 11.5,
                                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildEpisodeGrid(),
                ],
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero(MovieboxDetail detail) {
    final image = detail.cover ?? widget.cover ?? '';
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ShikaiNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              placeholderTitle: detail.title,
            ),
          ),
          Container(color: Colors.black.withOpacity(0.32)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.35),
                  ThemeService.background,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ShikaiNetworkImage(
                    imageUrl: image,
                    width: 92,
                    height: 136,
                    borderRadius: BorderRadius.circular(9),
                    placeholderTitle: detail.title,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        detail.title,
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
                      Text(
                        [
                          if (detail.releaseDate != null && detail.releaseDate!.length >= 4)
                            detail.releaseDate!.substring(0, 4),
                          if (detail.duration != null) detail.duration!,
                          if (detail.country != null) detail.country!,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                      ),
                      if (detail.rating != null && detail.rating! > 0) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                detail.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'IMDb',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(MovieboxDetail detail) {
    final pills = <Widget>[];

    if (detail.rating != null && detail.rating! > 0) {
      pills.add(_pill(
        icon: Icons.star,
        iconColor: Colors.amber,
        text: detail.rating!.toStringAsFixed(1),
      ));
    }
    pills.add(_pill(
      icon: detail.isSeries ? Icons.live_tv : Icons.movie_outlined,
      iconColor: ThemeService.crimson,
      text: detail.isSeries ? 'TV Series' : 'Movie',
    ));
    if (detail.language != null && detail.language!.isNotEmpty) {
      pills.add(_pill(
        icon: Icons.translate,
        iconColor: const Color(0xFF10B981),
        text: detail.language!.split(',').first.trim(),
      ));
    }

    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  Widget _pill({required IconData icon, required Color iconColor, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ThemeService.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: ThemeService.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeGrid() {
    final season = _seasons.firstWhere(
      (s) => s.season == _selectedSeason,
      orElse: () => _seasons.first,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(season.episodeCount, (index) {
        final episode = index + 1;
        return GestureDetector(
          onTap: () => _play(season: season.season, episode: episode),
          child: Container(
            width: 52,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ThemeService.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ThemeService.border),
            ),
            child: Text(
              '$episode',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }),
    );
  }
}
