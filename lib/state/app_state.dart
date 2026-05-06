import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';
import '../services/cookie_service.dart';

class AppState extends ChangeNotifier {
  static AppState? current;

  List<ReadingProgress> _history = [];
  List<Manga> _library = [];
  List<Manga> _wantToRead = [];
  List<Manga> _completed = [];
  bool _showCloudflareSheet = false;
  String? _cloudflareURL;
  int _reloadTrigger = 0;
  List<Manga>? _cachedLatest;
  List<Manga>? _cachedPopular;
  Map<String, Manga> _mangaCache = {};

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

  AppState() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    await CookieService().init();
    await _loadAll();
  }

  // ... جميع دوال الإضافة والحذف والتخزين (موجودة بالتفصيل في مشروعك السابق)
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
}