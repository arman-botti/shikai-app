import 'package:flutter/material.dart';
import 'package:shikai_app/services/theme_service.dart';

class ShikaiNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? placeholderTitle;
  final bool isManga;

  const ShikaiNetworkImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderTitle,
    this.isManga = false,
  }) : super(key: key);

  String _cleanUrl(String url) {
    String trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://')) return trimmed.replaceFirst('http://', 'https://');
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = _cleanUrl(imageUrl);
    final radius = borderRadius ?? BorderRadius.zero;

    if (cleaned.isEmpty) {
      return _buildFallback(context, radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        cleaned,
        width: width,
        height: height,
        fit: fit,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: ThemeService.surface,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                  color: ThemeService.currentAccent.withOpacity(0.5),
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback(context, radius);
        },
      ),
    );
  }

  Widget _buildFallback(BuildContext context, BorderRadius radius) {
    String initials = '';
    if (placeholderTitle != null && placeholderTitle!.trim().isNotEmpty) {
      final words = placeholderTitle!.trim().split(RegExp(r'\s+'));
      if (words.length >= 2) {
        initials = '${words[0][0]}${words[1][0]}'.toUpperCase();
      } else if (words.isNotEmpty && words[0].isNotEmpty) {
        initials = words[0].substring(0, words[0].length >= 3 ? 3 : words[0].length).toUpperCase();
      }
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: [
            ThemeService.surface,
            ThemeService.background.withOpacity(0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: ThemeService.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isManga ? Icons.auto_stories_rounded : Icons.movie_creation_outlined,
            color: Colors.white12,
            size: (width != null && width! < 60) ? 20 : 36,
          ),
          if (initials.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                initials,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: (width != null && width! < 60) ? 9 : 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
