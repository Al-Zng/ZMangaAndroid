import 'package:shared_preferences/shared_preferences.dart';

class CookieService {
  static final CookieService _instance = CookieService._internal();
  factory CookieService() => _instance;
  CookieService._internal();

  static const _kCookies = 'cf_cookies_v2';
  static const _kDomain = 'cf_domain_v2';
  static const _kTimestamp = 'cf_timestamp_v2';

  // صلاحية الكوكيز: 23 ساعة (cf_clearance تنتهي بعد 24)
  static const Duration _validity = Duration(hours: 23);

  Future<void> saveCookies(String cookies, String domain) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCookies, cookies);
    await prefs.setString(_kDomain, domain);
    await prefs.setInt(_kTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  Future<String> getCookieHeader() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCookies) ?? '';
  }

  Future<bool> hasValidSession() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_kTimestamp);
    if (ts == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age < _validity.inMilliseconds;
  }

  Future<void> clearCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCookies);
    await prefs.remove(_kDomain);
    await prefs.remove(_kTimestamp);
  }
}
