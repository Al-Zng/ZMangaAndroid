import 'package:dio/dio.dart';
import '../cloudflare/cookie_service.dart';
import 'user_agent.dart';

class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  HttpService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': AppUserAgent.iosSafari,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'ar,en;q=0.9',
    },
  ));

  Dio get dio {
    _dio.interceptors.clear();
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final cookieService = CookieService();
        final cookieHeader = await cookieService.getCookieHeader();
        if (cookieHeader.isNotEmpty) {
          options.headers['Cookie'] = cookieHeader;
        }
        options.headers['Referer'] = 'https://lekmanga.site/';
        options.headers['Origin'] = 'https://lekmanga.site';
        return handler.next(options);
      },
    ));
    return _dio;
  }

  Future<Response> get(String url, {Map<String, dynamic>? queryParameters, Options? options}) async {
    return dio.get(url, queryParameters: queryParameters, options: options);
  }

  Future<Response> post(String url, {dynamic data, Options? options}) async {
    return dio.post(url, data: data, options: options);
  }
}
