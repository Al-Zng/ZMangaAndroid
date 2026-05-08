import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';

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
      final uri = Uri.parse(widget.url);
      return uri.host;
    } catch (_) {
      return '';
    }
  }

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
        onPageStarted: (url) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          _onPageFinished(url);
        },
        onNavigationRequest: (request) {
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _onPageFinished(String currentUrl) async {
    if (_solved) return;
    _pageLoadCount++;

    // انتظر استقرار الـ DOM
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _solved) return;

    await _attemptSolve(currentUrl);
  }

  Future<void> _attemptSolve(String currentUrl) async {
    if (_solved) return;

    try {
      // فحص عنوان الصفحة
      final titleResult = await _controller.runJavaScriptReturningResult(
        'document.title',
      );
      final title = titleResult.toString().replaceAll('"', '').toLowerCase();

      final bool isChallengePage =
          title.contains('just a moment') ||
          title.contains('cloudflare') ||
          title.contains('checking your browser') ||
          title.contains('please wait') ||
          title.contains('attention required') ||
          title.contains('لحظة') ||
          title.isEmpty;

      // إذا لم تعد صفحة تحدي بعد أول تحميل
      if (!isChallengePage && _pageLoadCount > 1) {
        await _finalizeSolve();
        return;
      }

      // محاولة قراءة الكوكيز القابلة للقراءة عبر JS
      final cookieResult = await _controller.runJavaScriptReturningResult(
        r'''
        (function() {
          try {
            var c = document.cookie;
            if (c && c.length > 0) { return c; }
          } catch(e) {}
          return '__empty__';
        })()
        ''',
      );

      final cookieStr = cookieResult.toString().replaceAll('"', '');
      if (cookieStr != '__empty__' &&
          cookieStr.isNotEmpty &&
          cookieStr != 'null') {
        // وُجدت كوكيز — يعني الـ challenge انتهى
        if (_pageLoadCount > 1) {
          await _finalizeSolve(cookies: cookieStr);
          return;
        }
      }

      // فحص: هل الصفحة الحالية هي صفحة المحتوى الأصلي؟
      if (!isChallengePage && currentUrl.contains(_baseDomain)) {
        await _finalizeSolve();
      }
    } catch (e) {
      debugPrint('CF check error: $e');
    }
  }

  Future<void> _finalizeSolve({String? cookies}) async {
    if (_solved) return;
    _solved = true;

    try {
      if (cookies != null && cookies.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cf_cookies', cookies);
        await prefs.setString('cf_domain', _baseDomain);
        await prefs.setInt(
          'cf_timestamp',
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      if (mounted) {
        widget.appState.dismissCloudflare();
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.of(context).pop(true);
          widget.appState.triggerReload();
        }
      }
    } catch (e) {
      debugPrint('CF finalize error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!_solved) {
          widget.appState.dismissCloudflare();
        }
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'حل تحدي الأمان',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.security, size: 20),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      widget.appState.dismissCloudflare();
                      Navigator.of(context).pop(false);
                    },
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
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            if (!_solved)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.amber.withOpacity(0.1),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'اضغط على مربع "أنا لست روبوت" وانتظر حتى يكتمل',
                        style: TextStyle(fontSize: 12),
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
