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

  @override
  Widget build(BuildContext context) {
    if (url == null ||
        url!.isEmpty ||
        url!.contains('lekmanga.png') ||
        url!.contains('-512.png') ||
        url!.contains('/favicon')) {
      return _placeholder();
    }
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: const {'Referer': 'https://lekmanga.site'},
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.card,
        child: Center(
          child: Icon(Icons.image, color: AppTheme.textTertiary),
        ),
      );
}