import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';

// مطابق لـ iOS CloudflareSheet + CloudflareWebViewRepresentable
class CloudflareBypassSheet extends StatefulWidget {
  final String url;
  final AppState appState;

  const CloudflareBypassSheet({
    super.key,
    required this.url,
    required this.appState,
  });

  @override
  State<CloudflareBypassSheet> createState() => _CloudflareBypassSheetState();
}

class _CloudflareBypassSheetState extends State<CloudflareBypassSheet> {
  late WebViewController _controller;
  bool _solved = false;
  bool _isLoading = true;
  int _navCount = 0;
  final String _originalUrl;

  _CloudflareBypassSheetState() : _originalUrl = '';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          _didFinishNavigation(url);
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  // مطابق لـ iOS Coordinator.webView(_:didFinish:)
  Future<void> _didFinishNavigation(String currentUrl) async {
    if (_solved) return;
    _navCount++;

    // انتظر استقرار الصفحة
    await Future.delayed(const Duration(milliseconds: 800));
    if (_solved || !mounted) return;

    // فحص URL — مثل iOS
    final currentUri = Uri.tryParse(currentUrl);
    final originalUri = Uri.tryParse(widget.url);
    final urlChanged = currentUri?.host != originalUri?.host ||
        (currentUrl != widget.url &&
            !currentUrl.contains('cdn-cgi/l/chk_jschl'));

    if (urlChanged && _navCount > 1) {
      await _checkTitleAndSucceed();
      return;
    }

    await _checkTitleAndSucceed();
  }

  // مطابق لـ iOS evaluateJavaScript("document.title")
  Future<void> _checkTitleAndSucceed() async {
    if (_solved) return;
    try {
      final rawTitle =
          await _controller.runJavaScriptReturningResult('document.title');
      final title = rawTitle.toString().replaceAll('"', '').toLowerCase().trim();

      final isCloudflare = title.contains('just a moment') ||
          title.contains('attention required') ||
          title.contains('checking your browser') ||
          title.contains('cloudflare') ||
          title.contains('please wait');

      if (!isCloudflare && title.isNotEmpty) {
        await _copyCookiesAndSucceed();
      }
    } catch (e) {
      debugPrint('CF title check error: $e');
    }
  }

  // مطابق لـ iOS copyCookiesAndSucceed
  // في Android: الكوكيز موجودة في الـ WebView CookieManager — 
  // MangaService يستخدم نفس الـ WebView فالكوكيز مشتركة تلقائياً
  Future<void> _copyCookiesAndSucceed() async {
    if (_solved) return;
    _solved = true;

    // مثل iOS: store.cookiesReady = true, store.activeChallenge = nil, store.triggerReload()
    widget.appState.onCloudflareSolved();

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _cancel() {
    if (_solved) return;
    // مثل iOS: store.activeChallenge = nil (بدون triggerReload)
    widget.appState.onCloudflareDismissed();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _cancel(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            // ─── Header — مطابق لـ iOS NavigationView + toolbar ──────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      // Cancel — مثل iOS "Cancel" button
                      TextButton(
                        onPressed: _cancel,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFCC8C14),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('إغلاق',
                            style: TextStyle(fontSize: 15)),
                      ),
                      const Spacer(),
                      // Icon + Title — مثل iOS shield icon
                      if (_isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFCC8C14)),
                        )
                      else
                        const Icon(Icons.shield_outlined,
                            color: Color(0xFFCC8C14), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'تحقق من الأمان',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      // Done — مثل iOS "Done" button
                      TextButton(
                        onPressed: _solved ? null : _copyCookiesAndSucceed,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFCC8C14),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('تم',
                            style: TextStyle(fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Subtitle
                  Text(
                    'أكمل التحقق أدناه للمتابعة',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            // ─── WebView ──────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    Container(
                      color: const Color(0xFF0F0F0F).withOpacity(0.6),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFCC8C14)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
