import 'package:flutter/material.dart';
import 'cookie_service.dart';
import 'webview_verification.dart';
import '../../state/app_state.dart';

class CloudflareService {
  static final CloudflareService _instance = CloudflareService._internal();
  factory CloudflareService() => _instance;
  CloudflareService._internal();

  final _cookieService = CookieService();

  Future<void> ensureVerified(BuildContext context, String url) async {
    if (await _cookieService.hasValidSession()) {
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VerificationScreen(url: url),
        fullscreenDialog: true,
      ),
    );

    if (result == true) {
      AppState.current?.triggerReload();
    }
  }

  bool isCloudflareResponse(int statusCode, String body) {
    return statusCode == 403 ||
        statusCode == 503 ||
        body.contains('Just a moment') ||
        body.contains('cf-browser-verification');
  }
}
