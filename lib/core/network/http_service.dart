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

  Future<String> get(String url) async {
    // حقن كوكيز Cloudflare المحفوظة
    final cookieHeader = await CookieService().getCookieHeader();
    final headers = <String, String>{};
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _dio.get<String>(
      url,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  Future<String> post(String url, String body, {Map<String, String>? headers}) async {
    final cookieHeader = await CookieService().getCookieHeader();
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
}
