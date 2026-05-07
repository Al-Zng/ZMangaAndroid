import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'models/manga.dart';

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<Manga> _library = [];
  List<Manga> _recentManga = [];
  List<Map<String, dynamic>> _downloads = [];
  bool _isDarkMode = true;
  String _baseUrl = 'https://zmanga.org';
  bool _cookiesReady = false;
  String? _userAgent;
  Map<String, String> _cloudflareCookies = {};
  List<Manga> _searchResults = [];
  bool _isLoading = false;
  int _currentPage = 1;
  String _currentGenre = '';
  String _currentSearch = '';

  AppState(this._prefs) {
    _loadPreferences();
  }

  // Getters
  List<Manga> get library => _library;
  List<Manga> get recentManga => _recentManga;
  List<Map<String, dynamic>> get downloads => _downloads;
  bool get isDarkMode => _isDarkMode;
  String get baseUrl => _baseUrl;
  bool get cookiesReady => _cookiesReady;
  String? get userAgent => _userAgent;
  Map<String, String> get cloudflareCookies => _cloudflareCookies;
  List<Manga> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  int get currentPage => _currentPage;
  String get currentGenre => _currentGenre;
  String get currentSearch => _currentSearch;

  static AppState? current(BuildContext context) {
    try {
      return context.read<AppState>();
    } catch (e) {
      return null;
    }
  }

  // Initialize preferences
  void _loadPreferences() {
    final libraryJson = _prefs.getString('library');
    if (libraryJson != null) {
      final List<dynamic> decoded = jsonDecode(libraryJson);
      _library = decoded.map((item) => Manga.fromJson(item)).toList();
    }

    final recentJson = _prefs.getString('recentManga');
    if (recentJson != null) {
      final List<dynamic> decoded = jsonDecode(recentJson);
      _recentManga = decoded.map((item) => Manga.fromJson(item)).toList();
    }

    final downloadsJson = _prefs.getString('downloads');
    if (downloadsJson != null) {
      final List<dynamic> decoded = jsonDecode(downloadsJson);
      _downloads = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    _isDarkMode = _prefs.getBool('isDarkMode') ?? true;
    _baseUrl = _prefs.getString('baseUrl') ?? 'https://zmanga.org';
    _cookiesReady = _prefs.getBool('cookiesReady') ?? false;
    _userAgent = _prefs.getString('userAgent');
    
    final cookiesJson = _prefs.getString('cloudflareCookies');
    if (cookiesJson != null) {
      final Map<String, dynamic> decoded = jsonDecode(cookiesJson);
      _cloudflareCookies = decoded.map((key, value) => MapEntry(key, value.toString()));
    }

    notifyListeners();
  }

  // Cloudflare bypass methods
  void triggerCloudflare(String url) {
    _cookiesReady = false;
    _prefs.setBool('cookiesReady', false);
    notifyListeners();
  }

  void setCookiesReady(bool ready) {
    _cookiesReady = ready;
    _prefs.setBool('cookiesReady', ready);
    notifyListeners();
  }

  void setCloudflareCookies(Map<String, String> cookies) {
    _cloudflareCookies = cookies;
    _prefs.setString('cloudflareCookies', jsonEncode(cookies));
    notifyListeners();
  }

  void setUserAgent(String userAgent) {
    _userAgent = userAgent;
    _prefs.setString('userAgent', userAgent);
    notifyListeners();
  }

  // Search methods
  void setSearchResults(List<Manga> results) {
    _searchResults = results;
    notifyListeners();
  }

  void appendSearchResults(List<Manga> results) {
    _searchResults.addAll(results);
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    _currentPage = 1;
    _currentGenre = '';
    _currentSearch = '';
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setCurrentPage(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void setCurrentGenre(String genre) {
    _currentGenre = genre;
    _currentPage = 1;
    notifyListeners();
  }

  void setCurrentSearch(String search) {
    _currentSearch = search;
    _currentPage = 1;
    notifyListeners();
  }

  // Library management
  void addToLibrary(Manga manga) {
    if (!_library.any((m) => m.url == manga.url)) {
      _library.insert(0, manga);
      _saveLibrary();
    }
  }

  void removeFromLibrary(String mangaUrl) {
    _library.removeWhere((manga) => manga.url == mangaUrl);
    _saveLibrary();
  }

  bool isInLibrary(String mangaUrl) {
    return _library.any((manga) => manga.url == mangaUrl);
  }

  void _saveLibrary() {
    final jsonData = _library.map((manga) => manga.toJson()).toList();
    _prefs.setString('library', jsonEncode(jsonData));
    notifyListeners();
  }

  // Recent manga
  void addToRecent(Manga manga) {
    _recentManga.removeWhere((m) => m.url == manga.url);
    _recentManga.insert(0, manga);
    if (_recentManga.length > 50) {
      _recentManga = _recentManga.sublist(0, 50);
    }
    _saveRecentManga();
  }

  void _saveRecentManga() {
    final jsonData = _recentManga.map((manga) => manga.toJson()).toList();
    _prefs.setString('recentManga', jsonEncode(jsonData));
    notifyListeners();
  }

  // Downloads management
  void addDownload(Map<String, dynamic> downloadInfo) {
    _downloads.insert(0, downloadInfo);
    _saveDownloads();
  }

  void removeDownload(String chapterUrl) {
    _downloads.removeWhere((d) => d['chapterUrl'] == chapterUrl);
    _saveDownloads();
  }

  bool isDownloaded(String chapterUrl) {
    return _downloads.any((d) => d['chapterUrl'] == chapterUrl);
  }

  void _saveDownloads() {
    _prefs.setString('downloads', jsonEncode(_downloads));
    notifyListeners();
  }

  // Settings
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    _prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
    _prefs.setString('baseUrl', url);
    notifyListeners();
  }

  void clearCache() {
    _prefs.remove('cloudflareCookies');
    _prefs.remove('recentManga');
    _prefs.remove('downloads');
    _cloudflareCookies = {};
    _recentManga = [];
    _downloads = [];
    _cookiesReady = false;
    _userAgent = null;
    _prefs.setBool('cookiesReady', false);
    _prefs.remove('userAgent');
    notifyListeners();
  }

  void clearLibrary() {
    _library = [];
    _prefs.remove('library');
    notifyListeners();
  }
}