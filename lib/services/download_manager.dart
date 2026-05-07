import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'manga_service.dart';

class DownloadManager {
  static final DownloadManager shared = DownloadManager._();
  DownloadManager._();

  Map<String, DownloadedChapter> _downloads = {};
  Map<String, double> _activeDownloads = {};
  List<DownloadTask> _downloadQueue = [];
  bool _isProcessingQueue = false;

  final String _downloadsKey = 'zmanga_downloads';
  final String _queueKey = 'zmanga_download_queue';

  DownloadManager() {
    _load();
  }

  Map<String, DownloadedChapter> get downloads => _downloads;
  Map<String, double> get activeDownloads => _activeDownloads;
  List<DownloadTask> get downloadQueue => _downloadQueue;
  bool get isProcessingQueue => _isProcessingQueue;

  bool isDownloaded(String mangaSlug, String chapterSlug) {
    return _downloads.containsKey('${mangaSlug}_$chapterSlug');
  }

  bool isDownloading(String mangaSlug, String chapterSlug) {
    return _activeDownloads.containsKey('${mangaSlug}_$chapterSlug');
  }

  double progress(String mangaSlug, String chapterSlug) {
    return _activeDownloads['${mangaSlug}_$chapterSlug'] ?? 0.0;
  }

  Future<void> addToQueue({
    required Manga manga,
    required Chapter chapter,
    required List<String> pages,
  }) async {
    final task = DownloadTask(
      mangaSlug: manga.slug,
      chapterSlug: chapter.slug,
      chapterNumber: chapter.number,
      mangaTitle: manga.title,
      mangaCover: manga.coverURL,
      pages: pages,
    );
    _downloadQueue.add(task);
    await _saveQueue();
    _processQueue();
  }

  Future<void> addMultipleToQueue({
    required Manga manga,
    required List<Chapter> chapters,
    required Map<String, List<String>> pagesMap,
  }) async {
    for (var chapter in chapters) {
      if (pagesMap.containsKey(chapter.slug)) {
        final task = DownloadTask(
          mangaSlug: manga.slug,
          chapterSlug: chapter.slug,
          chapterNumber: chapter.number,
          mangaTitle: manga.title,
          mangaCover: manga.coverURL,
          pages: pagesMap[chapter.slug]!,
        );
        _downloadQueue.add(task);
      }
    }
    await _saveQueue();
    _processQueue();
  }

  void _processQueue() {
    if (_isProcessingQueue || _downloadQueue.isEmpty) return;
    _isProcessingQueue = true;

    Future.doWhile(() async {
      if (_downloadQueue.isEmpty) {
        _isProcessingQueue = false;
        return false;
      }
      final task = _downloadQueue.removeAt(0);
      await _saveQueue();
      await _downloadChapterFromTask(task);
      return true;
    });
  }

  Future<void> _downloadChapterFromTask(DownloadTask task) async {
    final key = '${task.mangaSlug}_${task.chapterSlug}';
    if (isDownloaded(task.mangaSlug, task.chapterSlug)) return;

    _activeDownloads[key] = 0.0;

    final dir = await _getChapterDir(task.mangaSlug, task.chapterSlug);
    await dir.create(recursive: true);

    List<String> localPaths = [];
    final client = HttpClient();

    for (int i = 0; i < task.pages.length; i++) {
      final url = task.pages[i];
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Referer', 'https://lekmanga.site');
        final response = await request.close();
        final bytes = await response.toList();
        final file = File('${dir.path}/$i.jpg');
        await file.writeAsBytes(bytes.expand((e) => e).toList());
        localPaths.add(file.path);
      } catch (_) {
        localPaths.add(url);
      }
      _activeDownloads[key] = (i + 1) / task.pages.length;
    }

    final downloaded = DownloadedChapter(
      mangaSlug: task.mangaSlug,
      chapterSlug: task.chapterSlug,
      chapterNumber: task.chapterNumber,
      mangaTitle: task.mangaTitle,
      mangaCover: task.mangaCover,
      pages: localPaths,
      downloadedAt: DateTime.now(),
    );
    _downloads[key] = downloaded;
    _activeDownloads.remove(key);
    await _save();
  }

  Future<void> downloadChapter({
    required Manga manga,
    required Chapter chapter,
    List<String>? pages,
  }) async {
    final key = '${manga.slug}_${chapter.slug}';
    if (isDownloaded(manga.slug, chapter.slug) ||
        isDownloading(manga.slug, chapter.slug)) return;

    _activeDownloads[key] = 0.0;

    final dir = await _getChapterDir(manga.slug, chapter.slug);
    await dir.create(recursive: true);

    List<String> urls;
    if (pages != null) {
      urls = pages;
    } else {
      try {
        urls =
            await MangaService().fetchChapterPages(manga.slug, chapter.slug);
      } catch (e) {
        _activeDownloads.remove(key);
        return;
      }
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
        localPaths.add(url);
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
    _downloadQueue.clear();
    await _save();
    await _saveQueue();
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
    final jsonStr =
        jsonEncode(_downloads.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_downloadsKey, jsonStr);
  }

  void _load() {
    SharedPreferences.getInstance().then((prefs) {
      final jsonStr = prefs.getString(_downloadsKey);
      if (jsonStr != null) {
        final Map<String, dynamic> map = jsonDecode(jsonStr);
        _downloads =
            map.map((k, v) => MapEntry(k, DownloadedChapter.fromJson(v)));
      }
      final queueStr = prefs.getString(_queueKey);
      if (queueStr != null) {
        final List<dynamic> list = jsonDecode(queueStr);
        _downloadQueue = list.map((e) => DownloadTask.fromJson(e)).toList();
        if (_downloadQueue.isNotEmpty) {
          _processQueue();
        }
      }
    });
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(_downloadQueue.map((e) => e.toJson()).toList());
    await prefs.setString(_queueKey, jsonStr);
  }
}