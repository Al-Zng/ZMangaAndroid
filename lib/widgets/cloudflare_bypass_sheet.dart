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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => _checkIfSolved(),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _checkIfSolved() async {
    if (_solved) return;

    // استخرج الكوكيز من الـ WebView عبر JavaScript
    final rawCookies = await _controller.runJavaScriptReturningResult(
      'document.cookie',
    ) as String? ?? '';

    // تحقق من وجود cf_clearance
    if (rawCookies.contains('cf_clearance')) {
      _solved = true;

      // احفظ الكوكيز في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cf_cookies', rawCookies);

      // أغلق الـ Sheet وأعد التحميل
      if (mounted) {
        widget.appState.dismissCloudflare();
        widget.appState.triggerReload();
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: const Text(
              'حل تحدي الأمان',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
