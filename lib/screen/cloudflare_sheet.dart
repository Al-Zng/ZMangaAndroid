import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';
import '../services/cookie_service.dart';
import '../theme/app_theme.dart';

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
      ..loadRequest(Uri.parse(store.cloudflareURL!));
  }

  Future<void> _extractAndSaveCookies() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "JSON.stringify(document.cookie.split('; ').filter(Boolean).map(c => {var i = c.indexOf('='); return {name: c.substring(0, i), value: c.substring(i+1)}}))"
      );
      if (result is String && result.isNotEmpty && result != 'null') {
        final List<dynamic> cookiesList = jsonDecode(result);
        final List<Map<String, String>> cookies = cookiesList.map((c) {
          return {
            'name': c['name']?.toString() ?? '',
            'value': c['value']?.toString() ?? '',
            'domain': 'lekmanga.site',
            'path': '/',
            'httpOnly': 'false',
            'secure': 'true',
          };
        }).toList();
        await CookieService().setCookiesFromList(cookies);
      }
    } catch (e) {
      debugPrint('Cookie extraction failed: $e');
    }
  }

  Future<void> _onDone() async {
    await _extractAndSaveCookies();
    if (!mounted) return;
    final store = context.read<AppState>();
    store.dismissCloudflare();
    store.triggerReload();
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: const Text('Security Check'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _onDone,
              child: const Text('Done', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}