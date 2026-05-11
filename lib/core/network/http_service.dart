import 'package:dio/dio.dart';
import '../cloudflare/cookie_service.dart';
import 'user_agent.dart';
import 'platform_cookie_bridge.dart';

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
      'Referer': 'https://lekmanga.site',
    },
  ));

  // ─── كوكيز الجلسة (مُنقولة من WebView بعد حل CF) ─────────────────
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

  // ─── دمج كوكيز من ثلاثة مصادر ────────────────────────────────────
  // ✅ FIX SESSION + SEARCH: نضيف كوكيز Android CookieManager التي تحتوي
  // على cf_clearance (HttpOnly) — مطابق لما يفعله iOS:
  //   WKWebsiteDataStore.default().httpCookieStore.getAllCookies()
  //   → HTTPCookieStorage.shared → URLSession
  Future<String> _buildCookieHeader(String url) async {
    final saved         = await CookieService().getCookieHeader();
    final androidCookies = await PlatformCookieBridge.getMergedCookiesForUrl(url);

    final merged = <String, String>{};
    _parseCookies(saved, merged);            // أولوية منخفضة
    _parseCookies(_sessionCookies, merged);  // أولوية متوسطة
    _parseCookies(androidCookies, merged);   // أعلى أولوية — يغلب على ما سبق

    if (merged.isEmpty) return '';
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _parseCookies(String raw, Map<String, String> out) {
    if (raw.isEmpty) return;
    for (final part in raw.split(';')) {
      final kv = part.trim().split('=');
      if (kv.isNotEmpty && kv[0].trim().isNotEmpty) {
        out[kv[0].trim()] = kv.sublist(1).join('=').trim();
      }
    }
  }
}
