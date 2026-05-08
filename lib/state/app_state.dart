import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';

class AppState extends ChangeNotifier {
  static AppState? current;

  List<ReadingProgress> _history = [];
  List<Manga> _library = [];
  List<Manga> _wantToRead = [];
  List<Manga> _completed = [];

  // ─── Cloudflare ───────────────────────────────────────────────────
  bool _showCloudflareSheet = false;
  String? _cloudflareURL;
  String? _cfCookies; // كوكيز Cloudflare المحفوظة من الـ sheet
  int _reloadTrigger = 0;

  // ─── Cache ────────────────────────────────────────────────────────
  List<Manga>? _cachedLatest;
  List<Manga>? _cachedPopular;
  Map<String, Manga> _mangaCache = {};

  List<ReadingProgress> get history => _history;
  List<Manga> get library => _library;
  List<Manga> get wantToRead => _wantToRead;
  List<Manga> get completed => _completed;
  bool get showCloudflareSheet => _showCloudflareSheet;
  String? get cloudflareURL => _cloudflareURL;
  String? get cfCookies => _cfCookies;
  int get reloadTrigger => _reloadTrigger;
  List<Manga>? get cachedLatest => _cachedLatest;
  List<Manga>? get cachedPopular => _cachedPopular;
  Map<String, Manga> get mangaCache => _mangaCache;

  AppState() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    await _loadHistory();
    await _loadLibrary();
    await _loadWantToRead();
    await _loadCompleted();
    await _loadCached();
    await _loadMangaCache();
  }

  // ─── History ──────────────────────────────────────────────────────
  void saveProgress(ReadingProgress progress) {
    _history.removeWhere((p) => p.mangaSlug == progress.mangaSlug);
    _history.insert(0, progress);
    if (_history.length > 200) _history = _history.sublist(0, 200);
    _persistHistory();
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _persistHistory();
    notifyListeners();
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'zmanga_history', jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_history');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _history = list.map((e) => ReadingProgress.fromJson(e)).toList();
      notifyListeners();
    }
  }

  // ─── Library ──────────────────────────────────────────────────────
  void addToLibrary(Manga manga) {
    if (_library.any((m) => m.slug == manga.slug)) return;
    _library.insert(0, manga);
    _persistLibrary();
    notifyListeners();
  }

  void removeFromLibrary(Manga manga) {
    _library.removeWhere((m) => m.slug == manga.slug);
    _persistLibrary();
    notifyListeners();
  }

  bool isInLibrary(Manga manga) => _library.any((m) => m.slug == manga.slug);

  Future<void> _persistLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'zmanga_library', jsonEncode(_library.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_library');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _library = list.map((e) => Manga.fromJson(e)).toList();
      notifyListeners();
    }
  }

  // ─── Want to Read ─────────────────────────────────────────────────
  void addWantToRead(Manga manga) {
    if (_wantToRead.any((m) => m.slug == manga.slug)) return;
    _wantToRead.insert(0, manga);
    _persistWantToRead();
    notifyListeners();
  }

  void removeWantToRead(Manga manga) {
    _wantToRead.removeWhere((m) => m.slug == manga.slug);
    _persistWantToRead();
    notifyListeners();
  }

  bool isWantToRead(Manga manga) =>
      _wantToRead.any((m) => m.slug == manga.slug);

  Future<void> _persistWantToRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zmanga_wanttoread',
        jsonEncode(_wantToRead.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadWantToRead() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_wanttoread');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _wantToRead = list.map((e) => Manga.fromJson(e)).toList();
      notifyListeners();
    }
  }

  // ─── Completed ────────────────────────────────────────────────────
  void addCompleted(Manga manga) {
    if (_completed.any((m) => m.slug == manga.slug)) return;
    _completed.insert(0, manga);
    _persistCompleted();
    notifyListeners();
  }

  void removeCompleted(Manga manga) {
    _completed.removeWhere((m) => m.slug == manga.slug);
    _persistCompleted();
    notifyListeners();
  }

  bool isCompleted(Manga manga) => _completed.any((m) => m.slug == manga.slug);

  Future<void> _persistCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zmanga_completed',
        jsonEncode(_completed.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_completed');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _completed = list.map((e) => Manga.fromJson(e)).toList();
      notifyListeners();
    }
  }

  // ─── Home Caching ─────────────────────────────────────────────────
  void saveCachedLatest(List<Manga> items) {
    _cachedLatest = items;
    _persistCached('zmanga_cached_latest', items);
  }

  void saveCachedPopular(List<Manga> items) {
    _cachedPopular = items;
    _persistCached('zmanga_cached_popular', items);
  }

  Future<void> _persistCached(String key, List<Manga> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final latest = prefs.getString('zmanga_cached_latest');
    if (latest != null) {
      _cachedLatest =
          (jsonDecode(latest) as List).map((e) => Manga.fromJson(e)).toList();
    }
    final popular = prefs.getString('zmanga_cached_popular');
    if (popular != null) {
      _cachedPopular =
          (jsonDecode(popular) as List).map((e) => Manga.fromJson(e)).toList();
    }
  }

  // ─── Manga Cache ──────────────────────────────────────────────────
  void cacheManga(Manga manga) {
    _mangaCache[manga.slug] = manga;
    _persistMangaCache();
  }

  Future<void> _persistMangaCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zmanga_manga_cache',
        jsonEncode(_mangaCache.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _loadMangaCache() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_manga_cache');
    if (data != null) {
      final map = jsonDecode(data) as Map<String, dynamic>;
      _mangaCache = map.map((k, v) => MapEntry(k, Manga.fromJson(v)));
      notifyListeners();
    }
  }

  // ─── Cloudflare — نفس منطق iOS تماماً ────────────────────────────

  /// يُطلق من MangaService عند اكتشاف Cloudflare
  /// يرمي exception مثل iOS — لا ينتظر
  void triggerCloudflare(String url) {
    if (_showCloudflareSheet) return; // لا تفتح sheet ثانية
    _cloudflareURL = url;
    _showCloudflareSheet = true;
    notifyListeners();
  }

  /// يُستدعى من CloudflareBypassSheet عند النجاح — مثل iOS
  void onCloudflareSolved({String? cookies}) {
    _showCloudflareSheet = false;
    if (cookies != null && cookies.isNotEmpty) _cfCookies = cookies;
    notifyListeners();
    _reloadTrigger++;
    notifyListeners();
  }

  /// يُستدعى عند الإغلاق بالإجبار
  void onCloudflareDismissed() {
    _showCloudflareSheet = false;
    notifyListeners();
    // لا نُطلق reload — المستخدم أغلق بالإجبار
  }

  // للتوافق
  void dismissCloudflare() => onCloudflareDismissed();

  void triggerReload() {
    _reloadTrigger++;
    notifyListeners();
  }
}
