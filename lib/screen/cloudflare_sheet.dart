import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../app_state.dart';
import '../services/cookie_service.dart';
import '../theme.dart';

class CloudflareSheet extends StatefulWidget {
  const CloudflareSheet({super.key});

  @override
  State<CloudflareSheet> createState() => _CloudflareSheetState();
}

class _CloudflareSheetState extends State<CloudflareSheet> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppState>();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // يمكننا هنا التحقق من اختفاء صفحة التحدي
          },
        ),
      )
      ..loadRequest(Uri.parse(store.cloudflareURL!));
  }

  /// استخراج جميع الكوكيز من WebView الحالي وحفظها في CookieJar
  Future<void> _extractAndSaveCookies() async {
    try {
      // جلب الكوكيز بصيغة JSON من JavaScript
      final result = await _controller.runJavaScriptReturningResult(
        "JSON.stringify(document.cookie.split('; ').filter(Boolean).map(c => {var i = c.indexOf('='); return {name: c.substring(0, i), value: c.substring(i+1)}}))"
      );

      if (result is String && result.isNotEmpty && result != 'null') {
        final List<dynamic> cookiesList = jsonDecode(result);
        final List<Map<String, String>> cookies = cookiesList.map((c) {
          return {
            'name': c['name']?.toString() ?? '',
            'value': c['value']?.toString() ?? '',
            'domain': 'lek-manga.net',
            'path': '/',
            'httpOnly': 'false',
            'secure': 'true',
          };
        }).toList();

        // حفظها عبر CookieService (وهي تستخدم PersistentCookieJar)
        await CookieService().setCookiesFromList(cookies);
      }
    } catch (e) {
      debugPrint('Failed to extract cookies: $e');
    }
  }

  /// الضغط على "Done" أو إكمال التحقق بنجاح
  Future<void> _onComplete() async {
    await _extractAndSaveCookies();

    if (!mounted) return;
    final store = context.read<AppState>();
    store.dismissCloudflare();
    store.triggerReload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZTheme.bg,
      appBar: AppBar(
        backgroundColor: ZTheme.surface,
        title: const Text(
          'Security Check',
          style: TextStyle(color: ZTheme.textPrimary),
        ),
        leading: TextButton(
          onPressed: () {
            context.read<AppState>().dismissCloudflare();
          },
          child: const Text('Cancel', style: TextStyle(color: ZTheme.accent)),
        ),
        actions: [
          TextButton(
            onPressed: _onComplete,
            child: const Text('Done', style: TextStyle(color: ZTheme.accent)),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}