import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'cookie_service.dart';

class MangaService {
  static const String baseURL = 'https://lekmanga.site';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  // ------ جلب HTML عبر http ------
  Future<String> fetchHTML(String urlString) async {
    final client = CookieService().client;
    var request = http.Request('GET', Uri.parse(urlString));
    request.headers['User-Agent'] =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
    request.headers['Referer'] = 'https://lekmanga.site';
    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 403 ||
        response.body.contains('Just a moment') ||
        response.body.contains('cf-browser-verification') ||
        response.body.contains('Checking your browser') ||
        response.body.contains('Attention Required')) {
      AppState.current?.triggerCloudflare(urlString);
      return '';
    }
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to load: ${response.statusCode}');
    }
  }

  // ------ جلب HTML الفصل عبر WebView ------
  Future<String> fetchChapterHTMLViaWebView(String urlString) async {
    final completer = Completer<String>();
    late final WebViewController controller;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            await Future.delayed(const Duration(seconds: 2));
            final html = await controller.runJavaScriptReturningResult(
              'document.documentElement.outerHTML',
            ) as String? ?? '';

            if (html.isEmpty) return;
            if (html.contains('Just a moment') ||
                html.contains('Attention Required') ||
                html.contains('Checking your browser')) {
              AppState.current?.triggerCloudflare(urlString);
              if (!completer.isCompleted) {
                completer.completeError(Exception('Cloudflare Challenge'));
              }
            } else {
              if (!completer.isCompleted) {
                completer.complete(html);
              }
            }
          },
          onWebResourceError: (error) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('WebView error: ${error.description}'));
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(urlString));

    return completer.future.timeout(const Duration(seconds: 30));
  }

  // ------ Public API ------
  Future<List<Manga>> fetchLatest({int page = 1}) async {
    final url = '$baseURL/manga/?m_orderby=latest&page=$page';
    final html = await fetchHTML(url);
    if (html.isEmpty) return [];
    return _parseMangaList(html, extractChapterInfo: true);
  }

  Future<List<Manga>> fetchPopular({int page = 1}) async {
    final url = '$baseURL/manga/?m_orderby=views&page=$page';
    final html = await fetchHTML(url);
    if (html.isEmpty) return [];
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<List<Manga>> search(String query, {int page = 1}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final url = '$baseURL/?s=$encoded&post_type=wp-manga&page=$page';
    final html = await fetchHTML(url);
    if (html.isEmpty) return [];
    return _parseMangaList(html, extractChapterInfo: false)
        .where((m) => !m.slug.contains('feed') && m.slug.isNotEmpty && m.coverURL.isNotEmpty)
        .toList();
  }

  Future<List<Manga>> fetchByGenre(String genre, {int page = 1}) async {
    final url = '$baseURL/manga-genre/$genre/?page=$page';
    final html = await fetchHTML(url);
    if (html.isEmpty) return [];
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<Manga> fetchDetail(String slug) async {
    final url = '$baseURL/manga/$slug/';
    final html = await fetchHTML(url);
    if (html.isEmpty) throw Exception('Cloudflare challenge');
    return _parseMangaDetail(html, slug);
  }

  Future<List<String>> fetchChapterPages(String mangaSlug, String chapterSlug) async {
    final url = '$baseURL/manga/$mangaSlug/$chapterSlug/';
    final html = await fetchChapterHTMLViaWebView(url);
    return _parseChapterPages(html);
  }

  // ========================
  // دوال التحليل الداخلية
  // ========================
  List<Manga> _parseMangaList(String html, {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final cardPattern = RegExp(
      r'<div class="page-item-detail[^"]*manga[^"]*">(.*?)</div>\s*</div>\s*</div>',
      dotAll: true,
    );
    for (final match in cardPattern.allMatches(html).take(30)) {
      final block = match.group(1)!;
      var manga = _parseMangaCard(block);
      if (manga != null) {
        if (manga.coverURL.isEmpty || _isLogoOnly(manga.coverURL)) continue;
        if (extractChapterInfo) {
          final info = _parseLatestChapterInfo(block);
          manga = manga.copyWith(
            latestChapterNumber: info.chapter,
            lastUpdated: info.time,
          );
        }
        results.add(manga);
      }
    }
    if (results.isEmpty) {
      results.addAll(_parseMangaSimple(html, extractChapterInfo: extractChapterInfo));
    }
    return results;
  }

  bool _isLogoOnly(String url) =>
      url.toLowerCase().contains('lekmanga.png') ||
      url.toLowerCase().contains('-512.png') ||
      url.toLowerCase().contains('/favicon');

  Manga? _parseMangaCard(String block) {
    final slugReg = RegExp(r'href="https?://[^/]+/manga/([^/"]+)/"');
    final slugMatch = slugReg.firstMatch(block);
    if (slugMatch == null) return null;
    final slug = slugMatch.group(1)!;

    final titleReg = RegExp(r'<h3[^>]*>\s*<a[^>]*>([^<]+)</a>');
    final titleMatch = titleReg.firstMatch(block);
    final title = titleMatch?.group(1) ??
        slug.replaceAll('-', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');

    final cover = _extractBestImageURL(block);
    if (slug.isEmpty || slug == 'feed' || _isLogoOnly(cover)) return null;
    return Manga(slug: slug, title: _htmlDecode(title), coverURL: cover);
  }

  String _extractBestImageURL(String block) {
    // محاولة srcset أولاً
    final srcsetReg = RegExp(r'<img[^>]+srcset="([^"]+)"[^>]*>');
    final srcsetMatch = srcsetReg.firstMatch(block);
    if (srcsetMatch != null) {
      final parts = srcsetMatch.group(1)!.split(',');
      for (final part in parts) {
        final candidate = part.trim().split(' ').first;
        if (candidate.startsWith('http') && _isValidImageURL(candidate) && !_isLogoOnly(candidate)) {
          return candidate;
        }
      }
    }
    // data-src
    final dataSrc = RegExp(r'data-src="([^"]+)"');
    final dataSrcMatch = dataSrc.firstMatch(block);
    if (dataSrcMatch != null && !_isLogoOnly(dataSrcMatch.group(1)!)) {
      return dataSrcMatch.group(1)!;
    }
    // src عادي
    final srcReg = RegExp(r'src="([^"]+)"');
    final srcMatch = srcReg.firstMatch(block);
    if (srcMatch != null && _isValidImageURL(srcMatch.group(1)!) && !_isLogoOnly(srcMatch.group(1)!)) {
      return srcMatch.group(1)!;
    }
    return '';
  }

  bool _isValidImageURL(String url) =>
      url.startsWith('http') && ['.jpg', '.jpeg', '.png', '.webp'].any(url.toLowerCase().contains);

  List<Manga> _parseMangaSimple(String html, {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final linkPattern = RegExp(r'href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})');
    for (final match in linkPattern.allMatches(html)) {
      final slug = match.group(2)!;
      final rawTitle = match.group(3)!.trim();
      if (slug.isEmpty || rawTitle.isEmpty || rawTitle.length > 200 || slug == 'feed' || slug.contains('cdn-cgi')) continue;
      if (results.any((m) => m.slug == slug)) continue;

      final block = html.substring(match.start, html.length.clamp(0, match.start + 2000));
      final cover = _extractBestImageURL(block);
      var manga = Manga(
        slug: slug,
        title: _htmlDecode(rawTitle),
        coverURL: _isLogoOnly(cover) ? '' : cover,
      );
      if (extractChapterInfo) {
        final info = _parseLatestChapterInfo(block);
        manga = manga.copyWith(latestChapterNumber: info.chapter, lastUpdated: info.time);
      }
      results.add(manga);
    }
    return results;
  }

  _ChapterInfo _parseLatestChapterInfo(String block) {
    final ch = RegExp(r'<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>');
    final chMatch = ch.firstMatch(block)?.group(1)?.trim();
    final time = RegExp(r'<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>');
    final timeMatch = time.firstMatch(block)?.group(1)?.trim();
    return _ChapterInfo(chMatch, timeMatch);
  }

  Manga _parseMangaDetail(String html, String slug) {
    final titleReg = RegExp(r'<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)');
    final title = titleReg.firstMatch(html)?.group(1) ?? slug.replaceAll('-', ' ');
    final cover = _extractBestImageURL(html);
    final descReg = RegExp(r'<div class="summary__content[^"]*">(.*?)</div>', dotAll: true);
    String description = '';
    if (descReg.firstMatch(html) case var m?) {
      description = _stripHTML(m.group(1)!).trim();
    }
    final ratingReg = RegExp(r'id="averagerate"[^>]*>([^<]+)<');
    final rating = ratingReg.firstMatch(html)?.group(1) ?? '';
    final statusReg = RegExp(r'<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>');
    final status = statusReg.firstMatch(html)?.group(1) ?? '';
    final authorReg = RegExp(r'class="author-content">(.*?)</div>', dotAll: true);
    final author = authorReg.firstMatch(html)?.group(1)?.let((it) => _stripHTML(it)) ?? '';

    final genres = <String>[];
    final genreReg = RegExp(r'/manga-genre/[^/]+/">([^<]+)</a>');
    for (final m in genreReg.allMatches(html)) {
      genres.add(m.group(1)!);
    }

    final chapters = <Chapter>[];
    final chapterBlockReg = RegExp(r'<li class="wp-manga-chapter[^"]*">(.*?)</li>', dotAll: true);
    for (final m in chapterBlockReg.allMatches(html)) {
      final block = m.group(1)!;
      final linkReg = RegExp(r'href="(https?://[^/]+/manga/[^/]+/([^/]+)/)"');
      final linkMatch = linkReg.firstMatch(block);
      if (linkMatch != null) {
        final slug = linkMatch.group(2)!;
        final numberReg = RegExp(r'>(\d+)</a>');
        final number = numberReg.firstMatch(block)?.group(1) ?? slug;
        final dateReg = RegExp(r'class="chapter-release-date"[^>]*>\s*(?:<[^>]+>)?([^<]+)<');
        final date = dateReg.firstMatch(block)?.group(1)?.trim() ?? '';
        if (!chapters.any((c) => c.slug == slug)) {
          chapters.add(Chapter(slug: slug, number: number, date: date));
        }
      }
    }

    chapters.sort((a, b) => (int.tryParse(b.number) ?? 0).compareTo(int.tryParse(a.number) ?? 0));

    return Manga(
      slug: slug,
      title: _htmlDecode(title),
      coverURL: cover,
      genres: genres,
      status: status,
      rating: rating,
      description: description,
      chapters: chapters,
      author: author,
    );
  }

  List<String> _parseChapterPages(String html) {
    final readingReg = RegExp(
      r'<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>(.*?)</div>\s*</div>',
      dotAll: true,
    );
    final searchArea = readingReg.firstMatch(html)?.group(1) ?? html;

    final pages = <String>[];
    final imgPattern = RegExp(r'<img[^>]+(?:data-src|data-lazy-src|src)="([^"]+)"[^>]*>');
    for (final match in imgPattern.allMatches(searchArea)) {
      final url = match.group(1)!;
      if (url.startsWith('http') &&
          !url.contains('data:image') &&
          !_isLogoOnly(url) &&
          ['.jpg', '.jpeg', '.png', '.webp'].any(url.toLowerCase().contains)) {
        pages.add(url);
      }
    }
    return pages;
  }

  String _stripHTML(String html) => html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  String _htmlDecode(String str) => str
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ');
}

class _ChapterInfo {
  final String? chapter;
  final String? time;
  _ChapterInfo(this.chapter, this.time);
}

extension on String {
  String capitalize() => '${this[0].toUpperCase()}${substring(1)}';
}
extension on Object? {
  R let<R>(R Function(dynamic) cb) => cb(this);
}