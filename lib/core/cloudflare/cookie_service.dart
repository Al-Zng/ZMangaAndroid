import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CookieService {
  static final CookieService _instance = CookieService._internal();
  factory CookieService() => _instance;
  CookieService._internal();

  final _storage = const FlutterSecureStorage();
  static const String _cookieKey = 'zmanga_cookies';
  static const String _expiryKey = 'zmanga_cookie_expiry';

  Future<void> saveCookies(String cookies) async {
    await _storage.write(key: _cookieKey, value: cookies);
    // Set expiry to 24 hours from now for cf_clearance usually
    final expiry = DateTime.now().add(const Duration(hours: 24));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_expiryKey, expiry.millisecondsSinceEpoch);
  }

  Future<String> getCookieHeader() async {
    final cookies = await _storage.read(key: _cookieKey);
    return cookies ?? '';
  }

  Future<bool> hasValidSession() async {
    final cookies = await _storage.read(key: _cookieKey);
    if (cookies == null || cookies.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final expiryMs = prefs.getInt(_expiryKey);
    if (expiryMs == null) return false;

    final expiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
    return DateTime.now().isBefore(expiry);
  }

  Future<void> clearCookies() async {
    await _storage.delete(key: _cookieKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_expiryKey);
  }
}
