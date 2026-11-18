import 'package:flutter/services.dart';

class DownloadService {
  static const MethodChannel _channel = MethodChannel('biz.shikai.app/updater');

  /// Starts a direct background download via Android's native DownloadManager
  /// Returns true if enqueued successfully
  static Future<bool> startDownload({
    required String url,
    required String title,
    required String filename,
    Map<String, String>? headers,
  }) async {
    try {
      final cleanName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final res = await _channel.invokeMethod('downloadFile', {
        'url': url,
        'title': title,
        'filename': cleanName,
        'headers': headers ?? {},
      });
      return res != null;
    } catch (_) {
      // Fallback to opening in external browser / 1DM / ADM
      return openExternal(url);
    }
  }

  /// Opens the direct stream URL in external browser / 1DM / ADM
  static Future<bool> openExternal(String url) async {
    try {
      final res = await _channel.invokeMethod('openUrl', {'url': url});
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
