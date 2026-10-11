import 'package:flutter/material.dart';
import 'package:shikai_app/models/airing_schedule_item.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/screens/anime_detail_screen.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<AiringScheduleItem> _allItems = [];
  bool _isLoading = true;
  String _selectedDay = 'today';
  String _searchQuery = '';

  final List<Map<String, String>> _days = [
    {'id': 'today', 'label': 'Today'},
    {'id': 'all', 'label': 'All Days'},
    {'id': '0', 'label': 'Sun'},
    {'id': '1', 'label': 'Mon'},
    {'id': '2', 'label': 'Tue'},
    {'id': '3', 'label': 'Wed'},
    {'id': '4', 'label': 'Thu'},
    {'id': '5', 'label': 'Fri'},
    {'id': '6', 'label': 'Sat'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    final items = await AnilistService.getAiringSchedule();
    if (mounted) {
      setState(() {
        _allItems = items;
        _isLoading = false;
      });
    }
  }

  List<AiringScheduleItem> get _filteredItems {
    final now = DateTime.now();

    return _allItems.where((item) {
      final airDate = DateTime.fromMillisecondsSinceEpoch(item.airingAt * 1000);
      final itemDayOfWeek = airDate.weekday == 7 ? '0' : airDate.weekday.toString();

      // Day filter
      if (_selectedDay == 'today') {
        if (airDate.year != now.year || airDate.month != now.month || airDate.day != now.day) {
          return false;
        }
      } else if (_selectedDay != 'all' && itemDayOfWeek != _selectedDay) {
        return false;
      }

      // Search filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = item.media.displayTitle.toLowerCase();
        final genres = item.media.genres.join(' ').toLowerCase();
        return title.contains(q) || genres.contains(q);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (context, accent, _) {
        final filtered = _filteredItems;

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
                  child: Icon(Icons.calendar_month, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Airing Schedule",
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
                  child: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                ),
                onPressed: _loadSchedule,
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Search in schedule...",
                    hintStyle: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: ThemeService.textDarkMuted, size: 20),
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
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // 2. Day Selector Tabs (Horizontal list)
              SizedBox(
                height: 42,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _days.length,
                  itemBuilder: (context, index) {
                    final d = _days[index];
                    final isSelected = d['id'] == _selectedDay;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedDay = d['id']!),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? accent : ThemeService.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? accent : ThemeService.border,
                          ),
                        ),
                        child: Text(
                          d['label']!,
                          style: TextStyle(
                            color: isSelected ? Colors.black : ThemeService.textMuted,
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

              // 3. Schedule Items List
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: accent))
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.event_busy, color: Colors.white24, size: 54),
                                const SizedBox(height: 12),
                                const Text(
                                  "No anime airing in this period",
                                  style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isNotEmpty ? "Try a different search query" : "Check another day tab",
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isAired = (item.airingAt - (DateTime.now().millisecondsSinceEpoch ~/ 1000)) <= 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: ThemeService.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: ThemeService.border),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AnimeDetailScreen(media: item.media),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        // Poster Thumbnail
                                        ShikaiNetworkImage(
                                          imageUrl: item.media.coverImage,
                                          placeholderTitle: item.media.displayTitle,
                                          width: 55,
                                          height: 80,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        const SizedBox(width: 12),

                                        // Anime details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Episode & Time row
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: accent.withOpacity(0.18),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: accent.withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      "EP ${item.episode}",
                                                      style: TextStyle(
                                                        color: accent,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    item.airingTimeFormatted,
                                                    style: const TextStyle(color: ThemeService.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isAired ? ThemeService.border : const Color(0xFF10B981).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      item.countdownText,
                                                      style: TextStyle(
                                                        color: isAired ? ThemeService.textDarkMuted : const Color(0xFF10B981),
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),

                                              Text(
                                                item.media.displayTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(height: 4),

                                              Text(
                                                item.media.genres.take(2).join(" • "),
                                                style: const TextStyle(color: ThemeService.textDarkMuted, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_ios, color: ThemeService.textDarkMuted, size: 13),
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
        );
      },
    );
  }
}
