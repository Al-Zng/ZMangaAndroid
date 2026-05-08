import '../cloudflare/cookie_service.dart';

class CloudflareService {
  static final CloudflareService _instance = CloudflareService._internal();
  factory CloudflareService() => _instance;
  CloudflareService._internal();

  bool isCloudflareBlock(int statusCode, String body) {
    return statusCode == 403 ||
        statusCode == 503 ||
        body.contains('Just a moment') ||
        body.contains('cf-browser-verification') ||
        body.contains('Checking your browser') ||
        body.contains('Attention Required') ||
        body.contains('cf_chl_opt') ||
        body.contains('_cf_chl_opt');
  }

  Future<bool> hasValidBypass() => CookieService().hasValidSession();
}
