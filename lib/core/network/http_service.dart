import 'package:dio/dio.dart';
import '../cloudflare/cookie_service.dart';
import 'user_agent.dart';

class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  HttpService._internal();

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.plain,
    headers: {
      'User-Agent': AppUserAgent.iosSafari,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'ar,en;q=0.9',
    },
  ));

  // ─── كوكيز الجلسة (مُنقولة من WebView بعد حل CF) ─────────────────
  // هذا يُحاكي iOS: WKWebsiteDataStore.getAllCookies → HTTPCookieStorage
  // ملاحظة: cf_clearance هي HttpOnly — لن تظهر هنا
  // لكنها موجودة في WebView cookie store وتُرسل عبر _fetchHTMLViaWebView
  String _sessionCookies = '';

  void addSessionCookies(String cookies) {
    if (cookies.isNotEmpty && cookies != 'null') {
      _sessionCookies = cookies;
    }
  }

  void clearSessionCookies() {
    _sessionCookies = '';
  }

  Future<String> get(String url) async {
    final cookieHeader = await _buildCookieHeader(url);
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: cookieHeader.isNotEmpty ? {'Cookie': cookieHeader} : {},
      ),
    );
    return response.data ?? '';
  }

  Future<String> post(String url, String body, {Map<String, String>? headers}) async {
    final cookieHeader = await _buildCookieHeader(url);
    final mergedHeaders = <String, dynamic>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': 'https://lekmanga.site',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      ...?headers,
    };
    final response = await _dio.post<String>(
      url,
      data: body,
      options: Options(headers: mergedHeaders),
    );
    return response.data ?? '';
  }

  // ─── دمج كوكيز CookieService + session cookies ────────────────────
  Future<String> _buildCookieHeader(String url) async {
    final saved = await CookieService().getCookieHeader();
    final parts = <String>[];
    if (saved.isNotEmpty) parts.add(saved);
    if (_sessionCookies.isNotEmpty) {
      // لا تُكرر الكوكيز الموجودة
      for (final part in _sessionCookies.split(';')) {
        final name = part.split('=').first.trim();
        if (name.isNotEmpty && !saved.contains('$name=')) {
          parts.add(part.trim());
        }
      }
    }
    return parts.join('; ');
  }
}
