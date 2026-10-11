import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/services/anilist_service.dart';
import 'package:shikai_app/services/manga_service.dart';
import 'package:shikai_app/services/watch_history_service.dart';

/// ---------------------------------------------------------------------------
/// APP PRELOAD SERVICE
/// Warms up home feed metadata and precaches critical hero banners and thumbnails
/// into Flutter's GPU ImageCache during the splash sequence for zero-lag instant rendering.
/// ---------------------------------------------------------------------------
class AppPreloadService {
  static bool isPreloaded = false;
  static bool isPreloading = false;

  // Primary Fold Data
  static List<AnilistMedia> trending = [];
  static List<AnilistMedia> popular = [];
  static List<AnilistMedia> spotlightList = [];
  static List<WatchHistoryItem> continueWatching = [];

  // Secondary Batches
  static List<AnilistMedia> topAiring = [];
  static List<AnilistMedia> movies = [];
  static List<AnilistMedia> recentlyUpdated = [];
  static List<AnilistMedia> topRated = [];
  static List<AnilistMedia> upcoming = [];
  static List<AnilistMedia> trendingManga = [];
  static List<AnilistMedia> actionHits = [];
  static List<AnilistMedia> fantasyHits = [];
  static List<AnilistMedia> romanceHits = [];

  // Callbacks for notifying listeners when secondary batches load
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  static String _cleanUrl(String url) {
    String trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://')) return trimmed.replaceFirst('http://', 'https://');
    return trimmed;
  }

  static const Map<String, String> _imageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };

  /// Preload core home screen metadata and precache hero banners & posters into GPU memory
  static Future<void> preloadAll(BuildContext context) async {
    if (isPreloaded || isPreloading) return;
    isPreloading = true;

    try {
      // 1. Concurrently fetch first-fold critical data: Trending, Popular, Continue Watching
      final coreFutures = await Future.wait([
        AnilistService.getTrendingAnime(page: 1, perPage: 20).catchError((_) => <AnilistMedia>[]),
        AnilistService.getPopularAnime(page: 1, perPage: 20).catchError((_) => <AnilistMedia>[]),
        WatchHistoryService.getContinueWatching().catchError((_) => <WatchHistoryItem>[]),
      ]);

      trending = coreFutures[0] as List<AnilistMedia>;
      popular = coreFutures[1] as List<AnilistMedia>;
      continueWatching = coreFutures[2] as List<WatchHistoryItem>;
      spotlightList = trending.take(8).toList();

      if (!context.mounted) {
        isPreloaded = true;
        isPreloading = false;
        return;
      }

      // 2. Precache top hero banners & thumbnails into Flutter ImageCache
      final List<Future<void>> precacheTasks = [];

      // Hero carousel banners & covers (first 4 items)
      for (final media in spotlightList.take(4)) {
        final bannerUrl = media.bannerImage ?? media.coverImage;
        final cleanBanner = _cleanUrl(bannerUrl);
        if (cleanBanner.isNotEmpty) {
          precacheTasks.add(
            precacheImage(
              NetworkImage(cleanBanner, headers: _imageHeaders),
              context,
            ).catchError((_) {}),
          );
        }

        final cleanCover = _cleanUrl(media.coverImage);
        if (cleanCover.isNotEmpty && cleanCover != cleanBanner) {
          precacheTasks.add(
            precacheImage(
              NetworkImage(cleanCover, headers: _imageHeaders),
              context,
            ).catchError((_) {}),
          );
        }
      }

      // Trending shelf posters (first 6 items)
      for (final media in trending.take(6)) {
        final clean = _cleanUrl(media.coverImage);
        if (clean.isNotEmpty) {
          precacheTasks.add(
            precacheImage(
              NetworkImage(clean, headers: _imageHeaders),
              context,
            ).catchError((_) {}),
          );
        }
      }

      // Continue watching posters (first 3 items)
      for (final item in continueWatching.take(3)) {
        final clean = _cleanUrl(item.coverImage);
        if (clean.isNotEmpty) {
          precacheTasks.add(
            precacheImage(
              NetworkImage(clean, headers: _imageHeaders),
              context,
            ).catchError((_) {}),
          );
        }
      }

      // Allow precache to run with a max timeout of 1200ms so slow networks don't hang
      if (precacheTasks.isNotEmpty) {
        await Future.any([
          Future.wait(precacheTasks),
          Future.delayed(const Duration(milliseconds: 1200)),
        ]);
      }

      isPreloaded = true;

      // 3. Kick off secondary batches asynchronously in background
      _preloadSecondaryBatches();
    } catch (e) {
      debugPrint('[AppPreloadService] Preload error: $e');
    } finally {
      isPreloading = false;
    }
  }

  static void _preloadSecondaryBatches() async {
    try {
      final allSecondary = await Future.wait([
        AnilistService.getTopAiring(page: 1, perPage: 20).catchError((_) => <AnilistMedia>[]),
        AnilistService.getMovies(page: 1, perPage: 16).catchError((_) => <AnilistMedia>[]),
        AnilistService.getRecentlyUpdated(page: 1, perPage: 20).catchError((_) => <AnilistMedia>[]),
        AnilistService.getTopRated(page: 1, perPage: 20).catchError((_) => <AnilistMedia>[]),
        AnilistService.getUpcomingAnime(page: 1, perPage: 16).catchError((_) => <AnilistMedia>[]),
        MangaService.getTrendingManga(page: 1, perPage: 15).catchError((_) => <AnilistMedia>[]),
        AnilistService.getAnimeByGenre('Action', page: 1, perPage: 16).catchError((_) => <AnilistMedia>[]),
        AnilistService.getAnimeByGenre('Fantasy', page: 1, perPage: 16).catchError((_) => <AnilistMedia>[]),
        AnilistService.getAnimeByGenre('Romance', page: 1, perPage: 16).catchError((_) => <AnilistMedia>[]),
      ]);

      topAiring = allSecondary[0];
      movies = allSecondary[1];
      recentlyUpdated = allSecondary[2];
      topRated = allSecondary[3];
      upcoming = allSecondary[4];
      trendingManga = allSecondary[5];
      actionHits = allSecondary[6];
      fantasyHits = allSecondary[7];
      romanceHits = allSecondary[8];

      // Notify home screen exactly ONCE when all secondary catalogs are ready
      _notifyListeners();
    } catch (_) {}
  }
}
