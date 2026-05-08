import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// مدير الكوكيز المركزي — مشابه لـ WKWebsiteDataStore في iOS
class CFCookieManager {
  static final CFCookieManager shared = CFCookieManager._();
  CFCookieManager._();

  // الكوكيز المستخرجة من WebView بعد حل التحدي
  String _cookieHeader = '';
  String get cookieHeader => _cookieHeader;
  bool get hasCookies => _cookieHeader.isNotEmpty;

  // استخرج الكوكيز من WebView (يعمل مع HttpOnly أيضاً)
  Future<void> extractFromWebView(WebViewController controller) async {
    try {
      // محاولة 1: document.cookie (للكوكيز غير HttpOnly)
      final jsResult = await controller.runJavaScriptReturningResult(
        r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
      );
      final jsCookies = jsResult.toString().replaceAll('"', '').trim();

      // محاولة 2: اقرأ من SharedPreferences إذا كان محفوظاً سابقاً
      final prefs = await SharedPreferences.getInstance();
      final savedCookies = prefs.getString('cf_cookies') ?? '';

      // دمج الاثنين
      final combined = <String>{};
      for (final c in [jsCookies, savedCookies]) {
        if (c.isNotEmpty) {
          combined.addAll(c.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty));
        }
      }

      _cookieHeader = combined.join('; ');

      if (_cookieHeader.isNotEmpty) {
        await prefs.setString('cf_cookies', _cookieHeader);
        debugPrint('CFCookieManager: extracted ${combined.length} cookies');
      }
    } catch (e) {
      debugPrint('CFCookieManager extract error: $e');
    }
  }

  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cookieHeader = prefs.getString('cf_cookies') ?? '';
    } catch (_) {}
  }

  void clear() {
    _cookieHeader = '';
    SharedPreferences.getInstance().then((p) => p.remove('cf_cookies'));
  }
}
