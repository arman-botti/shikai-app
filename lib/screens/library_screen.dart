import 'package:flutter/material.dart';
import 'package:shikai_app/services/watch_history_service.dart';
import 'package:shikai_app/services/manga_history_service.dart';
import 'package:shikai_app/services/theme_service.dart';
import 'package:shikai_app/widgets/shikai_network_image.dart';
import 'package:shikai_app/services/update_service.dart';
import 'package:shikai_app/widgets/update_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<WatchHistoryItem> _watchHistory = [];
  List<MangaHistoryItem> _readingHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final watch = await WatchHistoryService.getContinueWatching();
    final read = await MangaHistoryService.getContinueReading();
    if (mounted) {
      setState(() {
        _watchHistory = watch;
        _readingHistory = read;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.currentAccent;

    return Scaffold(
      backgroundColor: ThemeService.background,
      appBar: AppBar(
        backgroundColor: ThemeService.background,
        elevation: 0,
        title: const Text(
          "My Library",
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => _showSettingsModal(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: "Watching (${_watchHistory.length})"),
            Tab(text: "Reading (${_readingHistory.length})"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWatchList(),
                _buildReadingList(),
              ],
            ),
    );
  }

  Widget _buildWatchList() {
    if (_watchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline, size: 56, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text("No anime watched yet", style: TextStyle(color: ThemeService.textMuted, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _watchHistory.length,
      itemBuilder: (context, index) {
        final item = _watchHistory[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: ThemeService.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeService.border),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: ShikaiNetworkImage(
              imageUrl: item.coverImage,
              placeholderTitle: item.title,
              width: 60,
              height: 80,
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  "Episode ${item.episodeNumber}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: item.progressPercentage,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(ThemeService.currentAccent),
                  minHeight: 3.5,
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
              onPressed: () async {
                await WatchHistoryService.remove(item.anilistId);
                _loadHistory();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadingList() {
    if (_readingHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 56, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text("No manga read yet", style: TextStyle(color: ThemeService.textMuted, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _readingHistory.length,
      itemBuilder: (context, index) {
        final item = _readingHistory[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: ThemeService.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeService.border),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: ShikaiNetworkImage(
              imageUrl: item.coverImage,
              placeholderTitle: item.title,
              width: 60,
              height: 80,
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  "Chapter ${item.chapterNumber} (Page ${item.pageIndex + 1}/${item.totalPages})",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: item.progressPercentage,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(ThemeService.currentAccent),
                  minHeight: 3.5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettingsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ThemeService.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text("Clear Watch History", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await WatchHistoryService.clearAll();
                    _loadHistory();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.auto_stories_outlined, color: Colors.redAccent),
                  title: const Text("Clear Reading History", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await MangaHistoryService.clearAll();
                    _loadHistory();
                  },
                ),
                const Divider(color: Colors.white12, height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_rounded, color: ThemeService.currentAccent),
                  title: const Text("Check for Updates", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Current Version: v${UpdateService.currentVersion}", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ThemeService.currentAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ThemeService.currentAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      "Check",
                      style: TextStyle(color: ThemeService.currentAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 12),
                            Text("Checking for updates..."),
                          ],
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    final updateInfo = await UpdateService.checkForUpdate();
                    if (!context.mounted) return;
                    if (updateInfo != null && updateInfo.hasUpdate) {
                      UpdateDialog.show(context, updateInfo);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                              SizedBox(width: 8),
                              Text("Shikai is up to date (v${UpdateService.currentVersion})"),
                            ],
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
