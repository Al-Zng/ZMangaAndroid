import 'package:dio/dio.dart';

import '../cloudflare/cookie_service.dart';
import 'user_agent.dart';

class HttpService {
  static final HttpService _instance = HttpService._internal();

  factory HttpService() => _instance;

  HttpService._internal();

  final Dio dio = Dio();

  final CookieService _cookieService = CookieService();

  Future<void> initialize() async {
    dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (status) => status != null,
      headers: {
        'User-Agent': AppUserAgent.iosSafari,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookieHeader =
              await _cookieService.getCookieHeader();

          if (cookieHeader.isNotEmpty) {
            options.headers['Cookie'] = cookieHeader;
          }

          options.headers['User-Agent'] =
              AppUserAgent.iosSafari;

          handler.next(options);
        },
      ),
    );
  }
}