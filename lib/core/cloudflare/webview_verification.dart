import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../network/user_agent.dart';
import 'cookie_service.dart';

class VerificationScreen extends StatefulWidget {
  final String url;
  const VerificationScreen({super.key, required this.url});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final WebViewController _controller;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppUserAgent.iosSafari)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          await _checkVerification();
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _checkVerification() async {
    if (_solved) return;

    final title = await _controller.getTitle();
    final isChallenged = title == null ||
        title.toLowerCase().contains('just a moment') ||
        title.toLowerCase().contains('cloudflare');

    if (!isChallenged) {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie'
      ) as String;
      
      // Clean up the string result from runJavaScriptReturningResult
      String cleanCookies = cookies.replaceAll('"', '');
      
      if (cleanCookies.contains('cf_clearance')) {
        _solved = true;
        await CookieService().saveCookies(cleanCookies);
        if (mounted) Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Verification'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
