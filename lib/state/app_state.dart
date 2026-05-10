import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../models/models.dart';
import '../services/manga_service.dart';

class AppState extends ChangeNotifier {
  static AppState? current;

  List<ReadingProgress> _history = [];
  List<Manga> _library = [];
  List<Manga> _wantToRead = [];
  List<Manga> _completed = [];

  // ─── Cloudflare state ───────────────────────────────────────────
  bool _showCloudflareSheet = false;
  String? _cloudflareURL;
  int _reloadTrigger = 0;

  // Completers waiting for CF to be solved
  final List<Completer<bool>> _cfWaiters = [];

  // ─── Cache ───────────────────────────────────────────────────────
  List<Manga>? _cachedLatest;
  List<Manga>? _cachedPopular;
  Map<String, Manga> _mangaCache = {};

  // ─── Settings ────────────────────────────────────────────────────
  // ✅ FIX: كل الإعدادات متصلة وتُحفظ
  bool _lowEndMode = false;
  bool _autoLoadNextChapter = true;
  bool _reduceMotion = false;
  bool _keepScreenOn = false;

  List<ReadingProgress> get history => _history;
  List<Manga> get library => _library;
  List<Manga> get wantToRead => _wantToRead;
  List<Manga> get completed => _completed;
  bool get showCloudflareSheet => _showCloudflareSheet;
  String? get cloudflareURL => _cloudflareURL;
  int get reloadTrigger => _reloadTrigger;
  List<Manga>? get cachedLatest => _cachedLatest;
  List<Manga>? get cachedPopular => _cachedPopular;
  Map<String, Manga> get mangaCache => _mangaCache;

  // ✅ Settings getters
  bool get lowEndMode => _lowEndMode;
  bool get autoLoadNextChapter => _autoLoadNextChapter;
  bool get reduceMotion => _reduceMotion;
  bool get keepScreenOn => _keepScreenOn;

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
    await _loadSettings();
  }

  // ─── Settings ────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _lowEndMode = prefs.getBool('setting_low_end_mode') ?? false;
    _autoLoadNextChapter = prefs.getBool('setting_auto_load_next') ?? true;
    _reduceMotion = prefs.getBool('setting_reduce_motion') ?? false;
    _keepScreenOn = prefs.getBool('setting_keep_screen_on') ?? false;
    notifyListeners();
  }

  Future<void> setLowEndMode(bool val) async {
    _lowEndMode = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_low_end_mode', val);
  }

  Future<void> setAutoLoadNextChapter(bool val) async {
    _autoLoadNextChapter = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_auto_load_next', val);
  }

  Future<void> setReduceMotion(bool val) async {
    _reduceMotion = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_reduce_motion', val);
  }

  Future<void> setKeepScreenOn(bool val) async {
    _keepScreenOn = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setting_keep_screen_on', val);
  }

  // ─── History ─────────────────────────────────────────────────────
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

  // ─── Library ─────────────────────────────────────────────────────
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

  // ─── Want to Read ────────────────────────────────────────────────
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
    await prefs.setString('zmanga_want_to_read',
        jsonEncode(_wantToRead.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadWantToRead() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('zmanga_want_to_read');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _wantToRead = list.map((e) => Manga.fromJson(e)).toList();
      notifyListeners();
    }
  }

  // ─── Completed ───────────────────────────────────────────────────
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

  bool isCompleted(Manga manga) =>
      _completed.any((m) => m.slug == manga.slug);

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

  // ─── Cache ───────────────────────────────────────────────────────
  void saveCachedLatest(List<Manga> items) {
    _cachedLatest = items;
    _persistCached();
  }

  void saveCachedPopular(List<Manga> items) {
    _cachedPopular = items;
    _persistCached();
  }

  Future<void> _persistCached() async {
    final prefs = await SharedPreferences.getInstance();
    if (_cachedLatest != null) {
      await prefs.setString('zmanga_cached_latest',
          jsonEncode(_cachedLatest!.map((e) => e.toJson()).toList()));
    }
    if (_cachedPopular != null) {
      await prefs.setString('zmanga_cached_popular',
          jsonEncode(_cachedPopular!.map((e) => e.toJson()).toList()));
    }
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

  // ─── Manga Detail Cache ──────────────────────────────────────────
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

  // ─── Cloudflare ──────────────────────────────────────────────────
  Future<bool> triggerCloudflare(String url) {
    if (_showCloudflareSheet) {
      final c = Completer<bool>();
      _cfWaiters.add(c);
      return c.future;
    }

    _cloudflareURL = url;
    _showCloudflareSheet = true;
    notifyListeners();

    final c = Completer<bool>();
    _cfWaiters.add(c);
    return c.future;
  }

  void onCloudflareSolved() {
    _showCloudflareSheet = false;
    MangaService().markCfSolved();
    notifyListeners();

    for (final c in _cfWaiters) {
      if (!c.isCompleted) c.complete(true);
    }
    _cfWaiters.clear();
  }

  void onCloudflareDismissed() {
    _showCloudflareSheet = false;
    notifyListeners();

    for (final c in _cfWaiters) {
      if (!c.isCompleted) c.complete(false);
    }
    _cfWaiters.clear();
  }

  void dismissCloudflare() => onCloudflareDismissed();

  void triggerReload() {
    _reloadTrigger++;
    notifyListeners();
  }
}
