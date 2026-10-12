import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shikai_app/services/security_vault.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String changelog;
  final String apkDownloadUrl;
  final bool hasUpdate;
  final String? publishedAt;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.hasUpdate,
    this.publishedAt,
  });
}

class UpdateService {
  static const String currentVersion = '1.0.13';
  static const int currentBuildNumber = 14;
  static const String githubOwner = 'arman-botti';
  static const String githubRepo = 'shikai-app';
  static String get fallbackVersionUrl => '${SecurityVault.shikaiBase}/api/app/version';

  static const MethodChannel _updaterChannel = MethodChannel('biz.shikai.app/updater');

  /// Compare two semantic version strings (e.g. '1.0.1' vs '1.0.0')
  static bool isVersionNewer(String remote, String current) {
    try {
      final cleanRemote = remote.replaceAll(RegExp(r'^[vV]'), '').trim();
      final cleanCurrent = current.replaceAll(RegExp(r'^[vV]'), '').trim();

      final remoteParts = cleanRemote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      final maxLen = remoteParts.length > currentParts.length ? remoteParts.length : currentParts.length;
      for (int i = 0; i < maxLen; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Check GitHub Releases for the latest version with automatic Shikai API fallback
  static Future<UpdateInfo?> checkForUpdate() async {
    // 1. Primary Check: GitHub Releases API
    try {
      final githubUri = Uri.parse('https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest');
      final res = await http.get(
        githubUri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Shikai-App/$currentVersion',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tag = (data['tag_name'] as String? ?? '').trim();
        final body = (data['body'] as String? ?? '').trim();
        final publishedAt = data['published_at'] as String?;

        String apkUrl = '';
        if (data['assets'] != null && data['assets'] is List) {
          final assets = data['assets'] as List;
          final apkAsset = assets.firstWhere(
            (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            apkUrl = apkAsset['browser_download_url'] ?? '';
          }
        }

        final cleanTag = tag.replaceAll(RegExp(r'^[vV]'), '');
        final hasNewer = isVersionNewer(cleanTag, currentVersion) && apkUrl.isNotEmpty;

        return UpdateInfo(
          latestVersion: cleanTag.isNotEmpty ? cleanTag : currentVersion,
          currentVersion: currentVersion,
          changelog: body.isNotEmpty ? body : '• Performance improvements and bug fixes',
          apkDownloadUrl: apkUrl,
          hasUpdate: hasNewer,
          publishedAt: publishedAt,
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] GitHub check error: $e');
    }

    // 2. Secondary Fallback: Shikai Server API Endpoint
    try {
      final fallbackUri = Uri.parse(fallbackVersionUrl);
      final res = await http.get(fallbackUri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final remoteVersion = (data['version'] as String? ?? '').trim();
        final apkUrl = (data['download_url'] as String? ?? '').trim();
        final changelog = (data['changelog'] as String? ?? '').trim();

        final hasNewer = isVersionNewer(remoteVersion, currentVersion) && apkUrl.isNotEmpty;
        return UpdateInfo(
          latestVersion: remoteVersion.isNotEmpty ? remoteVersion : currentVersion,
          currentVersion: currentVersion,
          changelog: changelog.isNotEmpty ? changelog : '• New features and updates available',
          apkDownloadUrl: apkUrl,
          hasUpdate: hasNewer,
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] Fallback check error: $e');
    }

    return null;
  }

  /// Download the new APK with progress tracking and trigger Android package installer
  static Future<bool> downloadAndInstallApk({
    required String apkUrl,
    required void Function(int receivedBytes, int totalBytes, double progress) onProgress,
  }) async {
    try {
      final cacheDirStr = await _updaterChannel.invokeMethod<String>('getCacheDirectory');
      if (cacheDirStr == null || cacheDirStr.isEmpty) {
        throw Exception('Unable to locate app cache directory');
      }

      final apkFile = File('$cacheDirStr/shikai_update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      request.headers['User-Agent'] = 'Shikai-App-Updater/$currentVersion';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(receivedBytes, totalBytes, progress);
      }

      await sink.flush();
      await sink.close();
      client.close();

      // Trigger native Android package installer
      final installSuccess = await _updaterChannel.invokeMethod<bool>(
        'installApk',
        {'filePath': apkFile.absolute.path},
      );

      return installSuccess == true;
    } catch (e) {
      debugPrint('[UpdateService] Download & Install failed: $e');
      rethrow;
    }
  }
}
