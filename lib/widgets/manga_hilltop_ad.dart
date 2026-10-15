import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MangaHilltopAd extends StatefulWidget {
  final VoidCallback? onDismiss;

  const MangaHilltopAd({Key? key, this.onDismiss}) : super(key: key);

  @override
  State<MangaHilltopAd> createState() => _MangaHilltopAdState();
}

class _MangaHilltopAdState extends State<MangaHilltopAd> {
  WebViewController? _controller;
  bool _isVisible = true;
  bool _isLoaded = false;
  static const MethodChannel _updaterChannel = MethodChannel('biz.shikai.app/updater');

  static const String _hilltopHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      background: transparent !important;
      width: 100%;
      height: 100%;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
  </style>
</head>
<body>
  <script>
  (function(xpma){
  var d = document,
      s = d.createElement('script'),
      l = d.currentScript || d.scripts[d.scripts.length - 1];
  s.settings = xpma || {};
  s.src = "https://quarrelsomebitter.com/b/XPVYs.dxGrlk0WY/WJck/gevm/9UuXZDUnlbk-PyTbch1/MNjNEN4/N/j/U/tSNFz/Uly/M/TQgH2cOXQJ";
  s.async = true;
  s.referrerPolicy = 'no-referrer-when-downgrade';
  l.parentNode.insertBefore(s, l);
  })({})
  </script>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoaded = true);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.startsWith('https://shikai.biz') || url.startsWith('about:blank')) {
              return NavigationDecision.navigate;
            }
            // External ad click: open in user default browser to register click conversion
            try {
              _updaterChannel.invokeMethod('openUrl', {'url': url});
            } catch (_) {}
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_hilltopHtml, baseUrl: 'https://shikai.biz/');

    _controller = controller;
  }

  void _dismiss() {
    setState(() => _isVisible = false);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      height: 95,
      decoration: BoxDecoration(
        color: const Color(0xFF141419).withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. WebView rendering the Hilltop Ad Script
          if (_controller != null)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isLoaded ? 1.0 : 0.0,
                child: WebViewWidget(controller: _controller!),
              ),
            ),

          // 2. Sponsored badge (Top Left)
          Positioned(
            left: 8,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                "AD • SPONSORED",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // 3. Dismiss (X) Button (Top Right)
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: _dismiss,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
