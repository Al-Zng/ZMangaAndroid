import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CookieService {
  static const _cookiesKey = 'cloudflare_cookies';
  static const _expiryKey = 'cloudflare_expiry';

  Future<void> saveCookies({
    required Map<String, String> cookies,
    String? cfClearance,
    String? phpSessionId,
    String? wordpressLoggedIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      'cookies': cookies,
      'cf_clearance': cfClearance,
      'PHPSESSID': phpSessionId,
      'wordpress_logged_in': wordpressLoggedIn,
      'saved_at': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(
      _cookiesKey,
      jsonEncode(data),
    );

    await prefs.setInt(
      _expiryKey,
      DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
    );
  }

  Future<String> getCookieHeader() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_cookiesKey);

    if (raw == null) return '';

    final decoded = jsonDecode(raw);

    final Map<String, dynamic> cookies =
        Map<String, dynamic>.from(decoded['cookies']);

    return cookies.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }

  Future<bool> hasValidSession() async {
    final prefs = await SharedPreferences.getInstance();

    final expiry = prefs.getInt(_expiryKey);

    if (expiry == null) return false;

    if (DateTime.now().millisecondsSinceEpoch > expiry) {
      await clearCookies();
      return false;
    }

    final raw = prefs.getString(_cookiesKey);

    if (raw == null) return false;

    final decoded = jsonDecode(raw);

    return decoded['cf_clearance'] != null;
  }

  Future<void> clearCookies() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_cookiesKey);
    await prefs.remove(_expiryKey);
  }
}