abstract class LocalStreamingProxyInterface {
  Future<int> start();
  Future<void> stop();
  String getPlaybackUrl(String upstreamMasterUrl, {String? referer, String? key, String? audio});
  bool get isRunning;
}
