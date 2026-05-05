import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class CookieService {
  static final CookieService _instance = CookieService._internal();
  factory CookieService() => _instance;
  CookieService._internal();

  late PersistCookieJar _cookieJar;
  http.Client? _client;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _cookieJar = PersistCookieJar(storage: FileStorage(dir.path));
  }

  CookieJar get cookieJar => _cookieJar;

  http.Client get client {
    _client ??= HttpClientWithJar(cookieJar: _cookieJar);
    return _client!;
  }

  /// استبدال الكوكيز من WebView
  Future<void> setCookiesFromList(List<Map<String, String>> cookies) async {
    final uri = Uri.parse('https://lek-manga.net');
    final cookiesToSave = cookies.map((c) {
      return Cookie(c['name']!, c['value']!)
        ..domain = c['domain'] ?? uri.host
        ..path = c['path'] ?? '/'
        ..httpOnly = c['httpOnly']?.toLowerCase() == 'true'
        ..secure = c['secure']?.toLowerCase() == 'true';
    }).toList();
    await _cookieJar.saveFromResponse(uri, cookiesToSave);
  }
}

class HttpClientWithJar extends http.BaseClient {
  final CookieJar cookieJar;
  final http.Client _inner = http.Client();

  HttpClientWithJar({required this.cookieJar});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final cookies = await cookieJar.loadForRequest(uri);
    final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    if (cookieString.isNotEmpty) {
      request.headers['Cookie'] = cookieString;
    }
    final response = await _inner.send(request);
    if (response.headers.containsKey('set-cookie')) {
      final setCookieHeaders = response.headers['set-cookie']!;
      await cookieJar.saveFromResponse(
        uri,
        setCookieHeaders.map((s) => Cookie.fromSetCookieValue(s)).toList(),
      );
    }
    return response;
  }
}