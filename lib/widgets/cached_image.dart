import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

class CachedMangaImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;

  const CachedMangaImage({
    super.key,
    this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  static bool _isBadUrl(String u) =>
      u.isEmpty ||
      u.contains('lekmanga.png') ||
      u.contains('-512.png') ||
      u.contains('/favicon');

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || _isBadUrl(u)) return _placeholder();

    // ✅ OPT: حجم cache يوازن بين الجودة وذاكرة الجهاز
    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final cacheW = width  != null ? (width!  * devicePixelRatio).toInt() : null;
    final cacheH = height != null ? (height! * devicePixelRatio).toInt() : null;

    return CachedNetworkImage(
      imageUrl: u,
      httpHeaders: const {'Referer': 'https://lekmanga.site'},
      width: width,
      height: height,
      fit: fit,
      // ✅ OPT: تحديد حجم الذاكرة المؤقتة للصور يمنع OOM على الأجهزة الضعيفة
      memCacheWidth:  cacheW,
      memCacheHeight: cacheH,
      // ✅ OPT: Fade سريع بدل absent فجأة
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (_, __) => _placeholder(),
      errorWidget:  (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    width: width, height: height,
    color: AppTheme.card,
    child: const Center(
      child: Icon(Icons.image_outlined, color: AppTheme.textTertiary, size: 24),
    ),
  );
}

/// ✅ OPT: Pre-cache صورة بحجم محدد — يُستخدم في ReaderScreen لتحميل الصفحات المجاورة
Future<void> precacheMangaImage(String url, BuildContext context) {
  return precacheImage(
    CachedNetworkImageProvider(
      url,
      headers: const {'Referer': 'https://lekmanga.site'},
    ),
    context,
  );
}
