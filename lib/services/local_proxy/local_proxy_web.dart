import 'package:shikai_app/services/local_proxy/local_proxy_interface.dart';
import 'package:shikai_app/services/security_vault.dart';

class LocalStreamingProxyWeb implements LocalStreamingProxyInterface {
  @override
  bool get isRunning => true;

  @override
  Future<int> start() async => 0;

  @override
  Future<void> stop() async {}

  @override
  String getPlaybackUrl(String upstreamMasterUrl, {String? referer, String? key, String? audio}) {
    // In web browser (which enforces CORS and forbids Referer header spoofing),
    // route through Shikai Edge proxy for web preview
    if (upstreamMasterUrl.contains('fetch8') ||
        upstreamMasterUrl.contains('fetch9') ||
        upstreamMasterUrl.contains('vividcdn') ||
        upstreamMasterUrl.contains('fallencdn')) {
      final keyParam = (key != null && key.isNotEmpty) ? '&key=${Uri.encodeComponent(key)}' : '';
      return '${SecurityVault.shikaiBase}/api/anivexa/playlist-child?url=${Uri.encodeComponent(upstreamMasterUrl)}$keyParam&ref=${Uri.encodeComponent(SecurityVault.flixReferer)}';
    }
    return upstreamMasterUrl;
  }
}

LocalStreamingProxyInterface getLocalStreamingProxy() => LocalStreamingProxyWeb();
