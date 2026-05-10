class AppUserAgent {
  // ─── Android Chrome — للـ Cloudflare bypass WebView ───────────────
  // يجب أن يكون متوافقاً مع ما هو موجود فعلاً داخل Android WebView (Chrome/V8)
  // أي تناقض بين UA وخصائص المتصفح = Cloudflare يعيد التحدي فوراً
  static const String androidChrome =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  // ─── iOS Safari — للطلبات عبر Dio فقط (لا للـ WebView) ──────────
  // Dio لا يملك canvas/JS fingerprint، لذا iOS Safari مقبول هنا
  static const String iosSafari =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
      'Version/17.0 Mobile/15E148 Safari/604.1';
}
