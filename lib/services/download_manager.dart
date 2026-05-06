import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'manga_service.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  Map<String, DownloadedChapter> _downloads = {};
  Map<String, double> _activeDownloads = {};
  final String _key = 'downloads';

  DownloadManager() {
    _load();
  }

  Map<String, DownloadedChapter> get downloads => _downloads;
  Map<String, double> get activeDownloads => _activeDownloads;

  bool isDownloaded(String mangaSlug, String chapterSlug) {
    return _downloads.containsKey('${mangaSlug}_$chapterSlug');
  }

  bool isDownloading(String mangaSlug, String chapterSlug) {
    return _activeDownloads.containsKey('${mangaSlug}_$chapterSlug');
  }

  double progress(String mangaSlug, String chapterSlug) {
    return _activeDownloads['${mangaSlug}_$chapterSlug'] ?? 0.0;
  }

  Future<void> downloadChapter({
    required Manga manga,
    required Chapter chapter,
  }) async {
    final key = '${manga.slug}_${chapter.slug}';
    if (isDownloaded(manga.slug, chapter.slug) || isDownloading(manga.slug, chapter.slug)) return;

    _activeDownloads[key] = 0.0;

    final dir = await _getChapterDir(manga.slug, chapter.slug);
    await dir.create(recursive: true);

    List<String> urls;
    try {
      urls = await MangaService().fetchChapterPages(manga.slug, chapter.slug);
    } catch (e) {
      _activeDownloads.remove(key);
      return;
    }

    List<String> localPaths = [];
    final client = HttpClient();
    for (int i = 0; i < urls.length; i++) {
      final url = urls[i];
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Referer', 'https://lekmanga.site');
        final response = await request.close();
        final bytes = await response.toList();
        final file = File('${dir.path}/$i.jpg');
        await file.writeAsBytes(bytes.expand((e) => e).toList());
        localPaths.add(file.path);
      } catch (_) {
        localPaths.add(url); // fallback
      }
      _activeDownloads[key] = (i + 1) / urls.length;
    }

    final downloaded = DownloadedChapter(
      mangaSlug: manga.slug,
      chapterSlug: chapter.slug,
      chapterNumber: chapter.number,
      mangaTitle: manga.title,
      mangaCover: manga.coverURL,
      pages: localPaths,
      downloadedAt: DateTime.now(),
    );
    _downloads[key] = downloaded;
    _activeDownloads.remove(key);
    await _save();
  }

  Future<void> deleteChapter(String mangaSlug, String chapterSlug) async {
    final key = '${mangaSlug}_$chapterSlug';
    final dir = await _getChapterDir(mangaSlug, chapterSlug);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _downloads.remove(key);
    await _save();
  }

  Future<void> removeAllDownloads() async {
    for (final key in _downloads.keys) {
      final parts = key.split('_');
      if (parts.length == 2) {
        final dir = await _getChapterDir(parts[0], parts[1]);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
    _downloads.clear();
    await _save();
  }

  List<String>? getPages(String mangaSlug, String chapterSlug) {
    return _downloads['${mangaSlug}_$chapterSlug']?.pages;
  }

  Future<Directory> _getChapterDir(String mangaSlug, String chapterSlug) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/downloads/$mangaSlug/$chapterSlug');
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_downloads.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_key, jsonStr);
  }

  void _load() {
    final prefs = SharedPreferences.getInstance();
    prefs.then((pref) {
      final jsonStr = pref.getString(_key);
      if (jsonStr != null) {
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        _downloads = map.map((k, v) => MapEntry(k, DownloadedChapter.fromJson(v)));
      }
    });
  }
}