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
  List<Manga>? _cachedLatest;
  List<Manga>? _cachedPopular;
  Map<String, Manga> _mangaCache = {};

  // ─── Cloudflare ─────────────────────────────────────────────────
  bool _showCloudflareSheet = false;
  String? _cloudflareURL;
  int _reloadTrigger = 0;
  final List<Completer<bool>> _cfWaiters = [];

  // ─── Settings ───────────────────────────────────────────────────
  bool _autoLoadNextChapter = true;
  bool _reduceMotion = false;
  bool _keepScreenOn = false;

  // Getters
  List<ReadingProgress> get history       => _history;
  List<Manga>           get library       => _library;
  List<Manga>           get wantToRead    => _wantToRead;
  List<Manga>           get completed     => _completed;
  List<Manga>?          get cachedLatest  => _cachedLatest;
  List<Manga>?          get cachedPopular => _cachedPopular;
  Map<String, Manga>    get mangaCache    => _mangaCache;
  bool get showCloudflareSheet => _showCloudflareSheet;
  String? get cloudflareURL    => _cloudflareURL;
  int get reloadTrigger        => _reloadTrigger;
  bool get autoLoadNextChapter => _autoLoadNextChapter;
  bool get reduceMotion        => _reduceMotion;
  bool get keepScreenOn        => _keepScreenOn;

  AppState() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadHistory(),
      _loadLibrary(),
      _loadWantToRead(),
      _loadCompleted(),
      _loadCached(),
      _loadMangaCache(),
      _loadSettings(),
    ]);
  }

  // ─── Settings ────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    _autoLoadNextChapter = p.getBool('setting_auto_load_next')  ?? true;
    _reduceMotion        = p.getBool('setting_reduce_motion')   ?? false;
    _keepScreenOn        = p.getBool('setting_keep_screen_on')  ?? false;
    notifyListeners();
  }

  Future<void> setAutoLoadNextChapter(bool v) async { _autoLoadNextChapter = v; notifyListeners(); (await SharedPreferences.getInstance()).setBool('setting_auto_load_next', v); }
  Future<void> setReduceMotion(bool v)        async { _reduceMotion = v; notifyListeners(); (await SharedPreferences.getInstance()).setBool('setting_reduce_motion', v); }
  Future<void> setKeepScreenOn(bool v)        async { _keepScreenOn = v; notifyListeners(); (await SharedPreferences.getInstance()).setBool('setting_keep_screen_on', v); }

  // ─── History ─────────────────────────────────────────────────────
  void saveProgress(ReadingProgress p) {
    _history.removeWhere((h) => h.mangaSlug == p.mangaSlug);
    _history.insert(0, p);
    if (_history.length > 200) _history = _history.sublist(0, 200);
    _persistHistory();
    notifyListeners();
  }

  void clearHistory() { _history.clear(); _persistHistory(); notifyListeners(); }

  Future<void> _persistHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('zmanga_history', jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('zmanga_history');
    if (d != null) { _history = (jsonDecode(d) as List).map((e) => ReadingProgress.fromJson(e)).toList(); notifyListeners(); }
  }

  // ─── Library ─────────────────────────────────────────────────────
  void addToLibrary(Manga m)      { if (!_library.any((x) => x.slug == m.slug)) { _library.insert(0, m); _persistLibrary(); notifyListeners(); } }
  void removeFromLibrary(Manga m) { _library.removeWhere((x) => x.slug == m.slug); _persistLibrary(); notifyListeners(); }
  bool isInLibrary(Manga m)       => _library.any((x) => x.slug == m.slug);

  Future<void> _persistLibrary() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('zmanga_library', jsonEncode(_library.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadLibrary() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('zmanga_library');
    if (d != null) { _library = (jsonDecode(d) as List).map((e) => Manga.fromJson(e)).toList(); notifyListeners(); }
  }

  // ─── Want To Read ────────────────────────────────────────────────
  void addWantToRead(Manga m)      { if (!_wantToRead.any((x) => x.slug == m.slug)) { _wantToRead.insert(0, m); _persistWantToRead(); notifyListeners(); } }
  void removeWantToRead(Manga m)   { _wantToRead.removeWhere((x) => x.slug == m.slug); _persistWantToRead(); notifyListeners(); }
  bool isWantToRead(Manga m)       => _wantToRead.any((x) => x.slug == m.slug);

  Future<void> _persistWantToRead() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('zmanga_want_to_read', jsonEncode(_wantToRead.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadWantToRead() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('zmanga_want_to_read');
    if (d != null) { _wantToRead = (jsonDecode(d) as List).map((e) => Manga.fromJson(e)).toList(); notifyListeners(); }
  }

  // ─── Completed ───────────────────────────────────────────────────
  void addCompleted(Manga m)      { if (!_completed.any((x) => x.slug == m.slug)) { _completed.insert(0, m); _persistCompleted(); notifyListeners(); } }
  void removeCompleted(Manga m)   { _completed.removeWhere((x) => x.slug == m.slug); _persistCompleted(); notifyListeners(); }
  bool isCompleted(Manga m)       => _completed.any((x) => x.slug == m.slug);

  Future<void> _persistCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('zmanga_completed', jsonEncode(_completed.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadCompleted() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('zmanga_completed');
    if (d != null) { _completed = (jsonDecode(d) as List).map((e) => Manga.fromJson(e)).toList(); notifyListeners(); }
  }

  // ─── Cache ───────────────────────────────────────────────────────
  void saveCachedLatest(List<Manga> items) { _cachedLatest = items; _persistCached(); }
  void saveCachedPopular(List<Manga> items) { _cachedPopular = items; _persistCached(); }

  Future<void> _persistCached() async {
    final p = await SharedPreferences.getInstance();
    if (_cachedLatest  != null) await p.setString('zmanga_cached_latest',  jsonEncode(_cachedLatest!.map((e) => e.toJson()).toList()));
    if (_cachedPopular != null) await p.setString('zmanga_cached_popular', jsonEncode(_cachedPopular!.map((e) => e.toJson()).toList()));
  }

  Future<void> _loadCached() async {
    final p = await SharedPreferences.getInstance();
    final l = p.getString('zmanga_cached_latest');
    if (l != null) _cachedLatest  = (jsonDecode(l) as List).map((e) => Manga.fromJson(e)).toList();
    final o = p.getString('zmanga_cached_popular');
    if (o != null) _cachedPopular = (jsonDecode(o) as List).map((e) => Manga.fromJson(e)).toList();
  }

  // ─── Manga Cache ─────────────────────────────────────────────────
  void cacheManga(Manga m) { _mangaCache[m.slug] = m; _persistMangaCache(); }

  Future<void> _persistMangaCache() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('zmanga_manga_cache', jsonEncode(_mangaCache.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> _loadMangaCache() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString('zmanga_manga_cache');
    if (d != null) {
      final m = jsonDecode(d) as Map<String, dynamic>;
      _mangaCache = m.map((k, v) => MapEntry(k, Manga.fromJson(v)));
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
    for (final c in _cfWaiters) { if (!c.isCompleted) c.complete(true); }
    _cfWaiters.clear();
  }

  void onCloudflareDismissed() {
    _showCloudflareSheet = false;
    notifyListeners();
    for (final c in _cfWaiters) { if (!c.isCompleted) c.complete(false); }
    _cfWaiters.clear();
  }

  void dismissCloudflare() => onCloudflareDismissed();

  // ✅ FIX BG: عندما يعود التطبيق من الخلفية بعد 3+ دقائق
  // نُعيد تعيين حالة CF حتى لا يتعلق المحتوى في loading
  void markCfExpiredFromBackground() {
    MangaService().resetCfState();
    notifyListeners();
  }

  void triggerReload() { _reloadTrigger++; notifyListeners(); }
}
