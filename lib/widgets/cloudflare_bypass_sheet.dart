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
    // استخدم iOS Safari UA — نفس ما يستخدمه HttpService
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

    // انتظر استقرار الصفحة بعد حل Cloudflare
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
        // جرب قراءة الكوكيز من JS (قد لا تشمل HttpOnly)
        final cookieResult = await _controller.runJavaScriptReturningResult(
          r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
        );
        final jsCookies =
            cookieResult.toString().replaceAll('"', '').trim();

        // استخدم WebViewCookieManager لجلب الكوكيز الحقيقية (بما فيها cf_clearance)
        await _extractAndSaveCookies(jsCookies);
        return;
      }

      // إذا تغيّر URL بعيداً عن صفحة التحدي
      if (_pageLoadCount > 1 &&
          currentUrl.contains(_baseDomain) &&
          !isStillChallenge) {
        final cookieResult = await _controller.runJavaScriptReturningResult(
          r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
        );
        final jsCookies =
            cookieResult.toString().replaceAll('"', '').trim();
        await _extractAndSaveCookies(jsCookies);
      }
    } catch (e) {
      debugPrint('CF check error: $e');
    }
  }

  Future<void> _extractAndSaveCookies(String jsCookies) async {
    if (_solved) return;

    try {
      // استخدم WebViewCookieManager لجلب cf_clearance (HttpOnly)
      final cookieManager = WebViewCookieManager();
      final cfCookie = await cookieManager.getCookies(widget.url);

      // ابنِ header الكوكيز من WebViewCookieManager
      final cookieParts = <String>[];
      for (final cookie in cfCookie) {
        cookieParts.add('${cookie.name}=${cookie.value}');
      }

      // أضف كوكيز JS إذا وُجدت
      if (jsCookies.isNotEmpty && jsCookies != 'null') {
        for (final part in jsCookies.split(';')) {
          final trimmed = part.trim();
          if (trimmed.isNotEmpty &&
              !cookieParts
                  .any((c) => c.startsWith(trimmed.split('=')[0]))) {
            cookieParts.add(trimmed);
          }
        }
      }

      if (cookieParts.isEmpty && jsCookies.isEmpty) {
        // لم نجد كوكيز بعد، انتظر أكثر
        return;
      }

      final fullCookieHeader = cookieParts.join('; ');
      final hasCfClearance =
          fullCookieHeader.contains('cf_clearance') || jsCookies.isNotEmpty;

      if (hasCfClearance || _pageLoadCount > 3) {
        await _finalizeSolve(cookies: fullCookieHeader.isNotEmpty ? fullCookieHeader : jsCookies);
      }
    } catch (e) {
      debugPrint('Cookie extract error: $e');
      // fallback: احفظ JS cookies على الأقل
      if (jsCookies.isNotEmpty) {
        await _finalizeSolve(cookies: jsCookies);
      }
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
            // ─── Header ───────────────────────────────────────────
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
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
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

            // ─── WebView ──────────────────────────────────────────
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
