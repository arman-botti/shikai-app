import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Data model representing a parsed IAB VAST 2.0 / 3.0 Linear Video Ad
class VastAdModel {
  final String videoUrl;
  final List<String> impressionUrls;
  final String? clickThroughUrl;
  final Map<String, List<String>> trackingEvents;
  final int skipOffsetSeconds;
  final int durationSeconds;

  VastAdModel({
    required this.videoUrl,
    required this.impressionUrls,
    this.clickThroughUrl,
    required this.trackingEvents,
    this.skipOffsetSeconds = 5,
    this.durationSeconds = 30,
  });

  /// Fire all impression tracking pixels
  void fireImpressions() {
    for (final url in impressionUrls) {
      _pingUrl(url, 'Impression');
    }
  }

  /// Fire specific milestone tracking pixels (e.g. 'start', 'firstQuartile', 'midpoint', 'complete')
  void fireTracking(String event) {
    final urls = trackingEvents[event];
    if (urls != null) {
      for (final url in urls) {
        _pingUrl(url, 'Tracking ($event)');
      }
    }
  }

  /// Fire click tracking and launch sponsor destination
  Future<void> handleClick() async {
    if (clickThroughUrl != null && clickThroughUrl!.isNotEmpty) {
      _pingUrl(clickThroughUrl!, 'ClickThrough Ping');
      await VastAdService.launchExternalUrl(clickThroughUrl!);
    }
  }

  static void _pingUrl(String url, String tag) {
    if (url.isEmpty || !url.startsWith('http')) return;
    http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://shikai.biz/',
      },
    ).then((res) {
      debugPrint('[VastAd] $tag pinged -> status: ${res.statusCode}');
    }).catchError((err) {
      debugPrint('[VastAd] $tag error: $err');
    });
  }
}

/// Service to fetch and parse VAST video tags for Video Player Mid-rolls
class VastAdService {
  static const MethodChannel _channel = MethodChannel('biz.shikai.app/updater');

  /// Active HilltopAds Live VAST Tag URL
  static String vastTagUrl =
      'https://faithfuloccasion.com/d/m.FXz/dIGaNovdZ/GRUX/NeCmA9WuxZRUXlhkfPuTycc1/MPT/Q/y/Mzz/cFt/NvzOU/xaNSDwIi0KMnQw';

  /// Fetch and parse VAST linear video ad with safety timeouts
  static Future<VastAdModel?> fetchAd({String? customTagUrl}) async {
    final targetUrl = customTagUrl ?? vastTagUrl;
    try {
      final uri = Uri.parse(targetUrl);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          'Referer': 'https://shikai.biz/',
          'Accept': 'application/xml, text/xml, */*',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200 || response.body.isEmpty) {
        debugPrint('[VastAd] Empty response or status ${response.statusCode}');
        return null;
      }

      return parseVastXml(response.body);
    } catch (e) {
      debugPrint('[VastAd] Error fetching VAST tag: $e');
      return null;
    }
  }

  /// Robust zero-dependency RegExp VAST XML parser
  static VastAdModel? parseVastXml(String xml) {
    if (!xml.contains('<VAST') || !xml.contains('<MediaFile')) {
      debugPrint('[VastAd] XML does not contain valid VAST MediaFile');
      return null;
    }

    try {
      // 1. Extract MediaFiles (prefer MP4)
      final mediaFileRegex = RegExp(
        r'<MediaFile[^>]*>(?:<!\[CDATA\[)?(https?://[^\]\s<]+)(?:\]\]>)?</MediaFile>',
        caseSensitive: false,
      );
      final mediaMatches = mediaFileRegex.allMatches(xml);
      String? selectedVideoUrl;

      for (final match in mediaMatches) {
        final rawUrl = match.group(1)?.trim();
        if (rawUrl != null && rawUrl.isNotEmpty) {
          if (rawUrl.contains('.mp4') || !rawUrl.contains('.webm')) {
            selectedVideoUrl = rawUrl;
            break;
          }
          selectedVideoUrl ??= rawUrl;
        }
      }

      if (selectedVideoUrl == null || selectedVideoUrl.isEmpty) {
        debugPrint('[VastAd] No suitable video URL found in MediaFiles');
        return null;
      }

      // 2. Extract Impressions
      final impressionRegex = RegExp(
        r'<Impression[^>]*>(?:<!\[CDATA\[)?(https?://[^\]\s<]+)(?:\]\]>)?</Impression>',
        caseSensitive: false,
      );
      final impressions = <String>[];
      for (final match in impressionRegex.allMatches(xml)) {
        final imp = match.group(1)?.trim();
        if (imp != null && imp.isNotEmpty) {
          impressions.add(imp);
        }
      }

      // 3. Extract ClickThrough
      final clickRegex = RegExp(
        r'<ClickThrough[^>]*>(?:<!\[CDATA\[)?(https?://[^\]\s<]+)(?:\]\]>)?</ClickThrough>',
        caseSensitive: false,
      );
      final clickMatch = clickRegex.firstMatch(xml);
      final clickThroughUrl = clickMatch?.group(1)?.trim();

      // 4. Extract Tracking Events
      final trackingRegex = RegExp(
        r'<Tracking[^>]*event=["' "'" r']([a-zA-Z0-9_-]+)["' "'" r'][^>]*>(?:<!\[CDATA\[)?(https?://[^\]\s<]+)(?:\]\]>)?</Tracking>',
        caseSensitive: false,
      );
      final trackingEvents = <String, List<String>>{};
      for (final match in trackingRegex.allMatches(xml)) {
        final event = match.group(1)?.trim().toLowerCase();
        final url = match.group(2)?.trim();
        if (event != null && url != null && url.isNotEmpty) {
          trackingEvents.putIfAbsent(event, () => []).add(url);
        }
      }

      // 5. Skip offset: default 5s
      int skipOffset = 5;
      final skipMatch = RegExp(r'skipoffset=["' "'" r'](\d{2}):(\d{2}):(\d{2})["' "'" r']').firstMatch(xml);
      if (skipMatch != null) {
        final s = int.tryParse(skipMatch.group(3) ?? '') ?? 5;
        skipOffset = s > 0 ? s : 5;
      }
      // Always limit max skip offset to 5s so users never get trapped in non-skippable long ads
      if (skipOffset > 5) {
        skipOffset = 5;
      }

      return VastAdModel(
        videoUrl: selectedVideoUrl,
        impressionUrls: impressions,
        clickThroughUrl: clickThroughUrl,
        trackingEvents: trackingEvents,
        skipOffsetSeconds: skipOffset,
      );
    } catch (e) {
      debugPrint('[VastAd] XML Parse error: $e');
      return null;
    }
  }

  /// Launch destination sponsor in device browser
  static Future<void> launchExternalUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (e) {
      debugPrint('[VastAd] Failed to invoke openUrl: $e');
    }
  }
}
