import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';
import '../core/cloudflare/cookie_service.dart';
import '../core/network/user_agent.dart';

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
  int _pageLoadCount = 0;

  String get _baseDomain {
    try {
      return Uri.parse(widget.url).host;
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppUserAgent.iosSafari)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          _onPageFinished(url);
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _onPageFinished(String currentUrl) async {
    if (_solved) return;
    _pageLoadCount++;

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || _solved) return;

    await _checkSolved(currentUrl);
  }

  Future<void> _checkSolved(String currentUrl) async {
    if (_solved) return;

    try {
      // فحص عنوان الصفحة
      final rawTitle = await _controller.runJavaScriptReturningResult(
        'document.title || ""',
      );
      final title =
          rawTitle.toString().replaceAll('"', '').toLowerCase().trim();

      final isStillChallenge = title.isEmpty ||
          title.contains('just a moment') ||
          title.contains('cloudflare') ||
          title.contains('checking') ||
          title.contains('please wait') ||
          title.contains('attention required') ||
          title.contains('لحظة') ||
          title.contains('one moment');

      if (!isStillChallenge && _pageLoadCount > 1) {
        await _extractCookiesAndFinalize();
        return;
      }

      if (_pageLoadCount > 1 &&
          currentUrl.contains(_baseDomain) &&
          !isStillChallenge) {
        await _extractCookiesAndFinalize();
      }
    } catch (e) {
      debugPrint('CF check error: $e');
    }
  }

  Future<void> _extractCookiesAndFinalize() async {
    if (_solved) return;

    try {
      // webview_flutter 4.x لا يدعم getCookies — نستخدم JS
      // cf_clearance تكون HttpOnly لكن WebView يشاركها مع Dio تلقائياً
      // عبر shared cookie store على Android (WebView + OkHttp)
      final cookieResult = await _controller.runJavaScriptReturningResult(
        r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
      );
      final jsCookies =
          cookieResult.toString().replaceAll('"', '').trim();

      // احفظ ما نستطيع قراءته (PHPSESSID, wordpress_logged_in, etc.)
      // cf_clearance يُشارك تلقائياً بين WebView و HttpClient على Android
      final cookiesToSave =
          (jsCookies.isNotEmpty && jsCookies != 'null') ? jsCookies : '';

      await _finalizeSolve(cookies: cookiesToSave);
    } catch (e) {
      debugPrint('Cookie extract error: $e');
      await _finalizeSolve(cookies: null);
    }
  }

  Future<void> _finalizeSolve({String? cookies}) async {
    if (_solved) return;
    _solved = true;

    if (cookies != null && cookies.isNotEmpty) {
      try {
        await CookieService().saveCookies(cookies, _baseDomain);
      } catch (_) {}
    }

    widget.appState.onCloudflareSolved();

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _forceClose() {
    if (_solved) return;
    widget.appState.onCloudflareDismissed();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _forceClose(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تحقق من الأمان',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'اضغط على المربع ثم انتظر',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.shield_outlined,
                        size: 20, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _forceClose,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.05),
                      child: const Center(
                          child: CircularProgressIndicator()),
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
