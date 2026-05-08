import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../network/user_agent.dart';
import 'cookie_service.dart';

class WebViewVerification {
  final CookieService _cookieService = CookieService();

  Future<bool> verifyCloudflare({
    required BuildContext context,
    required String url,
  }) async {
    final completer = Completer<bool>();

    late final WebViewController controller;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppUserAgent.iosSafari)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String currentUrl) async {
            try {
              final cookieManager = WebViewCookieManager();

              final cookies = await cookieManager.getCookies(currentUrl);

              if (cookies.isEmpty) return;

              String? cfClearance;
              String? phpSessionId;
              String? wordpressLoggedIn;

              final Map<String, String> cookieMap = {};

              for (final cookie in cookies) {
                cookieMap[cookie.name] = cookie.value;

                if (cookie.name == 'cf_clearance') {
                  cfClearance = cookie.value;
                }

                if (cookie.name == 'PHPSESSID') {
                  phpSessionId = cookie.value;
                }

                if (cookie.name.contains('wordpress_logged_in')) {
                  wordpressLoggedIn = cookie.value;
                }
              }

              if (cfClearance != null && cfClearance.isNotEmpty) {
                await _cookieService.saveCookies(
                  cookies: cookieMap,
                  cfClearance: cfClearance,
                  phpSessionId: phpSessionId,
                  wordpressLoggedIn: wordpressLoggedIn,
                );

                if (!completer.isCompleted) {
                  completer.complete(true);
                }

                Navigator.of(context).pop();
              }
            } catch (e) {
              debugPrint('Cookie extraction error: $e');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: WebViewWidget(
              controller: controller,
            ),
          ),
        );
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => false,
    );
  }
}