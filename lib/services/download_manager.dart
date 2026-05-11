import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'manga_service.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager shared = DownloadManager._();
  DownloadManager._() { _load(); }

  Map<String, DownloadedChapter> _downloads = {};
  Map<String, double> _activeDownloads = {};
  final Map<String, DownloadedChapter> _activeMeta = {}; // metadata أثناء التحميل
  List<DownloadTask> _queue = [];
  bool _processingQueue = false;

  static const _dlKey    = 'zmanga_downloads_v2';
  static const _queueKey = 'zmanga_queue_v2';
  // ✅ OPT: عدد الصفحات المتوازية — أسرع تحميل بدون إرهاق الشبكة
  static const _parallelPages = 4;

  Map<String, DownloadedChapter> get downloads      => _downloads;
  Map<String, double>            get activeDownloads => _activeDownloads;
  List<DownloadTask>             get downloadQueue   => _queue;

  bool   isDownloaded(String mangaSlug, String chapterSlug) => _downloads.containsKey('${mangaSlug}_$chapterSlug');
  bool   isDownloading(String mangaSlug, String chapterSlug) => _activeDownloads.containsKey('${mangaSlug}_$chapterSlug');
  double progress(String mangaSlug, String chapterSlug)     => _activeDownloads['${mangaSlug}_$chapterSlug'] ?? 0.0;
  List<String>? getPages(String mangaSlug, String chapterSlug) => _downloads['${mangaSlug}_$chapterSlug']?.pages;

  DownloadedChapter? activeChapterMeta(String key) => _activeMeta[key];

  // ─── إضافة فصل للقائمة ───────────────────────────────────────────
  Future<void> addToQueue({required Manga manga, required Chapter chapter, List<String>? pages}) async {
    if (isDownloaded(manga.slug, chapter.slug) || isDownloading(manga.slug, chapter.slug)) return;
    final task = DownloadTask(
      mangaSlug: manga.slug, chapterSlug: chapter.slug,
      chapterNumber: chapter.number, mangaTitle: manga.title,
      mangaCover: manga.coverURL, pages: pages ?? []);
    _queue.add(task);
    await _saveQueue();
    notifyListeners();
    _processQueue();
  }

  Future<void> addMultipleToQueue({required Manga manga, required List<Chapter> chapters}) async {
    for (final ch in chapters) {
      if (!isDownloaded(manga.slug, ch.slug) && !isDownloading(manga.slug, ch.slug)) {
        _queue.add(DownloadTask(
          mangaSlug: manga.slug, chapterSlug: ch.slug,
          chapterNumber: ch.number, mangaTitle: manga.title,
          mangaCover: manga.coverURL, pages: []));
      }
    }
    await _saveQueue();
    notifyListeners();
    _processQueue();
  }

  // ─── معالجة القائمة ──────────────────────────────────────────────
  void _processQueue() {
    if (_processingQueue || _queue.isEmpty) return;
    _processingQueue = true;
    Future.doWhile(() async {
      if (_queue.isEmpty) { _processingQueue = false; notifyListeners(); return false; }
      final task = _queue.removeAt(0);
      await _saveQueue();
      notifyListeners();
      await _downloadTask(task);
      return true;
    });
  }

  Future<void> _downloadTask(DownloadTask task) async {
    final key = '${task.mangaSlug}_${task.chapterSlug}';
    if (isDownloaded(task.mangaSlug, task.chapterSlug)) return;

    // ✅ FIX: حفظ metadata فوراً قبل بدء التحميل لمنع فقدانها إذا أُغلق التطبيق
    _activeMeta[key] = DownloadedChapter(
      mangaSlug: task.mangaSlug, chapterSlug: task.chapterSlug,
      chapterNumber: task.chapterNumber, mangaTitle: task.mangaTitle,
      mangaCover: task.mangaCover, pages: [], downloadedAt: DateTime.now());
    _activeDownloads[key] = 0.0;
    notifyListeners();

    final dir = await _chapterDir(task.mangaSlug, task.chapterSlug);
    await dir.create(recursive: true);

    List<String> urls = task.pages;
    if (urls.isEmpty) {
      try {
        urls = await MangaService().fetchChapterPages(task.mangaSlug, task.chapterSlug)
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        _activeDownloads.remove(key); _activeMeta.remove(key); notifyListeners(); return;
      }
    }

    // ✅ OPT: تحميل متوازٍ بـ 4 صفحات في نفس الوقت (أسرع بـ 4x)
    final localPaths = List<String?>.filled(urls.length, null);
    int completed = 0;

    Future<void> downloadPage(int i) async {
      final url = urls[i];
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('Referer', 'https://lekmanga.site');
        final resp = await req.close().timeout(const Duration(seconds: 30));
        final bytes = await resp.toList();
        final file = File('${dir.path}/$i.jpg');
        await file.writeAsBytes(bytes.expand((e) => e).toList());
        localPaths[i] = file.path;
        client.close();
      } catch (_) { localPaths[i] = url; }
      completed++;
      _activeDownloads[key] = completed / urls.length;
      if (completed % 3 == 0 || completed == urls.length) notifyListeners();
    }

    // تقسيم إلى مجموعات متوازية
    for (int start = 0; start < urls.length; start += _parallelPages) {
      final end = (start + _parallelPages).clamp(0, urls.length);
      await Future.wait(List.generate(end - start, (j) => downloadPage(start + j)));
    }

    final downloaded = DownloadedChapter(
      mangaSlug: task.mangaSlug, chapterSlug: task.chapterSlug,
      chapterNumber: task.chapterNumber, mangaTitle: task.mangaTitle,
      mangaCover: task.mangaCover,
      pages: localPaths.map((p) => p ?? '').toList(),
      downloadedAt: DateTime.now());
    _downloads[key] = downloaded;
    _activeDownloads.remove(key);
    _activeMeta.remove(key);
    await _save(); // ✅ FIX: حفظ فوري بعد اكتمال كل فصل
    notifyListeners();
  }

  // ─── تحميل مباشر (من manga detail) ──────────────────────────────
  Future<void> downloadChapter({required Manga manga, required Chapter chapter, List<String>? pages}) async {
    await addToQueue(manga: manga, chapter: chapter, pages: pages);
  }

  Future<void> deleteChapter(String mangaSlug, String chapterSlug) async {
    final key = '${mangaSlug}_$chapterSlug';
    try {
      final dir = await _chapterDir(mangaSlug, chapterSlug);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _downloads.remove(key);
    await _save();
    notifyListeners();
  }

  Future<void> removeAllDownloads() async {
    for (final key in List.of(_downloads.keys)) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        try {
          final dir = await _chapterDir(parts[0], parts.sublist(1).join('_'));
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
    _downloads.clear(); _queue.clear(); _activeDownloads.clear(); _activeMeta.clear();
    await _save(); await _saveQueue();
    notifyListeners();
  }

  Future<Directory> _chapterDir(String mangaSlug, String chapterSlug) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/downloads/$mangaSlug/$chapterSlug');
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_downloads.map((k, v) => MapEntry(k, v.toJson())));
      await prefs.setString(_dlKey, json);
    } catch (_) {}
  }

  void _load() {
    SharedPreferences.getInstance().then((prefs) {
      // ✅ FIX: دعم المفتاح القديم أيضاً للتوافق مع الإصدار السابق
      final json = prefs.getString(_dlKey) ?? prefs.getString('zmanga_downloads');
      if (json != null) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          _downloads = map.map((k, v) => MapEntry(k, DownloadedChapter.fromJson(v)));
        } catch (_) {}
      }
      final qJson = prefs.getString(_queueKey) ?? prefs.getString('zmanga_download_queue');
      if (qJson != null) {
        try {
          _queue = (jsonDecode(qJson) as List).map((e) => DownloadTask.fromJson(e)).toList();
          if (_queue.isNotEmpty) _processQueue();
        } catch (_) {}
      }
      notifyListeners();
    });
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_queueKey, jsonEncode(_queue.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  // ✅ إحصائيات للإعدادات
  int get downloadedChapterCount => _downloads.length;
}
