import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'models.dart';
import 'services/cookie_service.dart';

class AppState extends ChangeNotifier {
  static AppState? current;

  List<ReadingProgress> _history = [];
  List<Manga> _library = [];
  bool _showCloudflareSheet = false;
  String? _cloudflareURL;
  int _reloadTrigger = 0;

  List<ReadingProgress> get history => _history;
  List<Manga> get library => _library;
  bool get showCloudflareSheet => _showCloudflareSheet;
  String? get cloudflareURL => _cloudflareURL;
  int get reloadTrigger => _reloadTrigger;

  AppState() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    await CookieService().init();
    await _loadHistory();
    await _loadLibrary();
  }

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

  bool isInLibrary(Manga manga) =>
      _library.any((m) => m.slug == manga.slug);

  void triggerCloudflare(String url) {
    _cloudflareURL = url;
    _showCloudflareSheet = true;
    notifyListeners();
  }

  void dismissCloudflare() {
    _showCloudflareSheet = false;
    notifyListeners();
  }

  void triggerReload() {
    _reloadTrigger++;
    notifyListeners();
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_history.map((h) => h.toJson()).toList());
    await prefs.setString('zmanga_history', data);
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

  Future<void> _persistLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_library.map((m) => m.toJson()).toList());
    await prefs.setString('zmanga_library', data);
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
}