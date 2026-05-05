import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
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
      ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1')
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // يمكنك إضافة تحقق من النجاح هنا
        },
      ))
      ..loadRequest(Uri.parse(store.cloudflareURL!));
  }

  Future<void> _done() async {
    try {
      final cookiesJs = await _controller.runJavaScriptReturningResult(
        "JSON.stringify(document.cookie.split('; ').filter(Boolean).map(c => {var parts = c.split('='); return {name: parts[0], value: parts.slice(1).join('=')}}))"
      );
      // In real implementation, you'd parse the string and call CookieService().setCookiesFromList
      // For simplicity, we just notify and close
    } catch (_) {}
    if (!mounted) return;
    context.read<AppState>().dismissCloudflare();
    context.read<AppState>().triggerReload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZTheme.bg,
      appBar: AppBar(
        backgroundColor: ZTheme.surface,
        title: const Text('Security Check'),
        leading: TextButton(onPressed: () => context.read<AppState>().dismissCloudflare(), child: const Text('Cancel')),
        actions: [TextButton(onPressed: _done, child: const Text('Done'))],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}