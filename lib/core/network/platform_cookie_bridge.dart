import 'dart:io';
import 'package:flutter/services.dart';

/// جسر بين Flutter وAndroid CookieManager.
/// يستخرج الكوكيز (بما فيها HttpOnly مثل cf_clearance) للـ URL المحدد.
/// على iOS يُرجع سلسلة فارغة لأن iOS يتعامل مع الكوكيز تلقائياً عبر URLSession.
class PlatformCookieBridge {
  static const _channel = MethodChannel('zmanga/cookies');

  /// يُرجع سلسلة كوكيز Android WebView لـ URL معين.
  /// مثال: "cf_clearance=xxx; _ga=yyy"
  static Future<String> getCookiesForUrl(String url) async {
    if (!Platform.isAndroid) return '';
    try {
      final result = await _channel.invokeMethod<String>(
        'getCookies',
        {'url': url},
      );
      return result ?? '';
    } catch (_) {
      return '';
    }
  }

  /// يُرجع كوكيز الموقع الأساسي (lekmanga.site) + كوكيز الـ URL المحدد مدمجة.
  /// يضمن حصولنا على cf_clearance حتى لو كان الـ URL على CDN مختلف.
  static Future<String> getMergedCookiesForUrl(String url) async {
    if (!Platform.isAndroid) return '';
    const baseUrl = 'https://lekmanga.site/';
    final baseCookies = await getCookiesForUrl(baseUrl);
    final urlCookies  = await getCookiesForUrl(url);

    if (baseCookies.isEmpty) return urlCookies;
    if (urlCookies.isEmpty)  return baseCookies;

    // ندمج الكوكيز بدون تكرار
    final merged = <String, String>{};
    for (final part in baseCookies.split(';')) {
      final kv = part.trim().split('=');
      if (kv.isNotEmpty && kv[0].isNotEmpty) {
        merged[kv[0]] = kv.sublist(1).join('=');
      }
    }
    for (final part in urlCookies.split(';')) {
      final kv = part.trim().split('=');
      if (kv.isNotEmpty && kv[0].isNotEmpty) {
        merged[kv[0]] = kv.sublist(1).join('=');
      }
    }
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
