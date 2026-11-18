import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_player_screen.dart';
import 'package:shikai_app/services/download_service.dart';
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

  void _downloadEpisodePrompt({required int season, required int episode}) {
    final detail = _detail;
    if (detail == null) return;

    final subjectId = _selectedDubId ?? detail.id;
    var detailPath = detail.detailPath;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _QualityDownloadPicker(
        title: detail.title,
        season: season,
        episode: episode,
        subjectId: subjectId,
        detailPath: detailPath,
      ),
    );
  }

  void _showSeriesDownloadSheet() {
    final detail = _detail;
    if (detail == null) return;

    final subjectId = _selectedDubId ?? detail.id;
    var detailPath = detail.detailPath;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SeriesDownloadSheet(
        detail: detail,
        seasons: _seasons,
        initialSeason: _selectedSeason > 0 ? _selectedSeason : (_seasons.isNotEmpty ? _seasons.first.season : 1),
        subjectId: subjectId,
        detailPath: detailPath,
        onDownloadEpisode: (s, ep) => _downloadEpisodePrompt(season: s, episode: ep),
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
                Row(
                  children: [
                    Expanded(
                      flex: 6,
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
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: ThemeService.crimson.withOpacity(0.6), width: 1.4),
                          backgroundColor: ThemeService.crimson.withOpacity(0.12),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _downloadEpisodePrompt(season: 0, episode: 0),
                        icon: const Icon(Icons.download_rounded, size: 20, color: ThemeService.crimson),
                        label: const Text(
                          'Download',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              if (detail.isSeries) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeService.crimson,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final s = _seasons.isNotEmpty ? _seasons.first.season : 1;
                          _play(season: s, episode: 1);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          _seasons.isNotEmpty ? 'Play S${_seasons.first.season} E1' : 'Play',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: ThemeService.crimson.withOpacity(0.6), width: 1.4),
                          backgroundColor: ThemeService.crimson.withOpacity(0.12),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showSeriesDownloadSheet,
                        icon: const Icon(Icons.download_rounded, size: 19, color: ThemeService.crimson),
                        label: const Text(
                          'Download Episodes',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
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
          onLongPress: () => _downloadEpisodePrompt(season: season.season, episode: episode),
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

class _QualityDownloadPicker extends StatefulWidget {
  final String title;
  final int season;
  final int episode;
  final String subjectId;
  final String? detailPath;

  const _QualityDownloadPicker({
    Key? key,
    required this.title,
    required this.season,
    required this.episode,
    required this.subjectId,
    this.detailPath,
  }) : super(key: key);

  @override
  State<_QualityDownloadPicker> createState() => _QualityDownloadPickerState();
}

class _QualityDownloadPickerState extends State<_QualityDownloadPicker> {
  bool _isLoading = true;
  String? _error;
  List<MovieboxStream> _streams = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final streams = await MovieboxService.getStreams(
        widget.subjectId,
        season: widget.season,
        episode: widget.episode,
        detailPath: widget.detailPath,
      );

      final playable = streams.where((s) => s.isMp4 && s.url.isNotEmpty).toList();
      final fullLength = playable
          .where((s) => s.durationSec == null || s.durationSec! > 120)
          .toList();
      final list = fullLength.isNotEmpty ? fullLength : playable;

      if (!mounted) return;
      setState(() {
        _streams = list;
        _isLoading = false;
        if (list.isEmpty) {
          _error = 'No direct downloadable streams found for this episode.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to fetch streams: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startDirectDownload(MovieboxStream stream) async {
    final epLabel = widget.episode > 0 ? '_S${widget.season}E${widget.episode}' : '';
    final filename = '${widget.title}${epLabel}_${stream.quality}.mp4';
    final downloadTitle = widget.episode > 0
        ? '${widget.title} S${widget.season}E${widget.episode} (${stream.quality})'
        : '${widget.title} (${stream.quality})';

    Navigator.pop(context);

    final success = await DownloadService.startDownload(
      url: stream.url,
      title: downloadTitle,
      filename: filename,
      headers: stream.headers,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              const Icon(Icons.download_done_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Download started: $filename\nCheck notification bar!'
                      : 'Opened download stream in external downloader',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEp = widget.episode > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeService.crimson.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded, color: ThemeService.crimson, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isEp ? 'Season ${widget.season} • Episode ${widget.episode}' : 'Movie Direct Download',
                      style: const TextStyle(color: ThemeService.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'CHOOSE QUALITY TO DOWNLOAD',
            style: TextStyle(color: ThemeService.textDarkMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: ThemeService.crimson, strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text('Resolving direct high-speed streams...', style: TextStyle(color: ThemeService.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                ),
              ),
            )
          else
            Column(
              children: _streams.map((s) {
                final sizeLabel = s.sizeMb > 0
                    ? (s.sizeMb >= 1024
                        ? '${(s.sizeMb / 1024).toStringAsFixed(1)} GB'
                        : '${s.sizeMb.round()} MB')
                    : 'Direct MP4';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ThemeService.crimson.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.quality,
                        style: const TextStyle(color: ThemeService.crimson, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      'Direct MP4 • $sizeLabel',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      s.codec != null ? 'Codec: ${s.codec}' : '100% Direct Download',
                      style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                    ),
                    trailing: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeService.crimson,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _startDirectDownload(s),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _SeriesDownloadSheet extends StatefulWidget {
  final MovieboxDetail detail;
  final List<MovieboxSeason> seasons;
  final int initialSeason;
  final String subjectId;
  final String? detailPath;
  final void Function(int season, int episode) onDownloadEpisode;

  const _SeriesDownloadSheet({
    Key? key,
    required this.detail,
    required this.seasons,
    required this.initialSeason,
    required this.subjectId,
    this.detailPath,
    required this.onDownloadEpisode,
  }) : super(key: key);

  @override
  State<_SeriesDownloadSheet> createState() => _SeriesDownloadSheetState();
}

class _SeriesDownloadSheetState extends State<_SeriesDownloadSheet> {
  late int _selectedSeason;
  int _selectedChunk = 0;
  static const int _chunkSize = 25;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.initialSeason;
  }

  @override
  Widget build(BuildContext context) {
    final currentSeason = widget.seasons.firstWhere(
      (s) => s.season == _selectedSeason,
      orElse: () => widget.seasons.isNotEmpty ? widget.seasons.first : const MovieboxSeason(season: 1, episodeCount: 1),
    );

    final totalEpisodes = currentSeason.episodeCount;
    final totalChunks = (totalEpisodes / _chunkSize).ceil();
    final clampedChunk = _selectedChunk >= totalChunks ? 0 : _selectedChunk;
    final startEp = (clampedChunk * _chunkSize) + 1;
    final endEp = ((clampedChunk + 1) * _chunkSize).clamp(1, totalEpisodes);
    final visibleCount = (endEp - startEp + 1).clamp(0, totalEpisodes);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
          ),
          child: Column(
            children: [
              // Header Drag Handle & Info
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ThemeService.crimson.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.download_for_offline_rounded, color: ThemeService.crimson, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.detail.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${widget.seasons.length} Seasons • $totalEpisodes Episodes in S$_selectedSeason',
                                style: const TextStyle(color: ThemeService.textMuted, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Season Selector Pills (Horizontal Scroll)
              if (widget.seasons.length > 1)
                Container(
                  height: 38,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.seasons.length,
                    itemBuilder: (context, index) {
                      final s = widget.seasons[index];
                      final isSel = s.season == _selectedSeason;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSeason = s.season;
                            _selectedChunk = 0;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSel ? ThemeService.crimson : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSel ? ThemeService.crimson : const Color(0xFF334155),
                            ),
                          ),
                          child: Text(
                            'Season ${s.season}',
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Episode Chunk Selector for 25+ episodes (Bigg Boss special!)
              if (totalEpisodes > _chunkSize)
                Container(
                  height: 32,
                  margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: totalChunks,
                    itemBuilder: (context, chunkIdx) {
                      final cStart = (chunkIdx * _chunkSize) + 1;
                      final cEnd = ((chunkIdx + 1) * _chunkSize).clamp(1, totalEpisodes);
                      final isSel = chunkIdx == clampedChunk;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedChunk = chunkIdx),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSel ? ThemeService.crimson.withOpacity(0.2) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel ? ThemeService.crimson : const Color(0xFF334155),
                            ),
                          ),
                          child: Text(
                            '$cStart - $cEnd',
                            style: TextStyle(
                              color: isSel ? ThemeService.crimson : ThemeService.textMuted,
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const Divider(color: Color(0xFF334155), height: 1),

              // Sequence-wise Episodes List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: visibleCount,
                  itemBuilder: (context, index) {
                    final epNum = startEp + index;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$epNum',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Episode $epNum',
                                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'S$_selectedSeason : E$epNum • Direct HD MP4',
                                  style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeService.crimson,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Download', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              widget.onDownloadEpisode(_selectedSeason, epNum);
                            },
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
