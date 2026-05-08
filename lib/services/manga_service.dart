import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/models.dart';
import '../state/app_state.dart';

// نفس ZMangaError في iOS
class ZMangaError implements Exception {
  final String message;
  const ZMangaError(this.message);
  @override
  String toString() => message;

  static const cloudflareChallenge =
      ZMangaError('Cloudflare verification required');
}

class MangaService {
  static const String baseURL = 'https://lekmanga.site';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  // WebView مشترك لجلب HTML — نفس iOS WKWebView approach
  WebViewController? _sharedWebView;
  bool _webViewBusy = false;

  WebViewController _getSharedWebView() {
    if (_sharedWebView != null) return _sharedWebView!;
    _sharedWebView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      );
    return _sharedWebView!;
  }

  // MARK: - fetchHTML عبر WebView — مثل iOS fetchHTMLViaWebView
  // الفرق الجوهري عن iOS: Android WebView وHttpClient مخازن كوكيز منفصلة
  // الحل: نستخدم الـ WebView لكل الطلبات، فالكوكيز محفوظة تلقائياً فيه
  Future<String> _fetchHTMLViaWebView(String urlString) async {
    // انتظر إذا كان الـ WebView مشغولاً
    int waitCount = 0;
    while (_webViewBusy && waitCount < 30) {
      await Future.delayed(const Duration(milliseconds: 200));
      waitCount++;
    }
    _webViewBusy = true;

    final controller = _getSharedWebView();
    final completer = Completer<String>();
    bool done = false;
    int navCount = 0;

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        navCount++;
        if (done) return;

        // انتظر استقرار الصفحة
        await Future.delayed(const Duration(milliseconds: 600));
        if (done) return;

        // قرأ عنوان الصفحة — نفس منطق iOS Coordinator
        String title = '';
        try {
          final rawTitle =
              await controller.runJavaScriptReturningResult('document.title');
          title = rawTitle.toString().replaceAll('"', '').toLowerCase().trim();
        } catch (_) {}

        final isCloudflare = title.isEmpty ||
            title.contains('just a moment') ||
            title.contains('cloudflare') ||
            title.contains('checking') ||
            title.contains('please wait') ||
            title.contains('attention required');

        if (isCloudflare && navCount == 1) {
          // لا تزال صفحة تحدي — انتظر navigation أخرى
          return;
        }

        if (!isCloudflare || navCount > 1) {
          // نجح أو تجاوزنا — اقرأ HTML
          done = true;
          _webViewBusy = false;
          try {
            final html = await controller.runJavaScriptReturningResult(
              'document.documentElement.outerHTML',
            );
            final htmlStr = html.toString();
            // أزل علامات الاقتباس المحيطة إن وُجدت
            completer.complete(htmlStr);
          } catch (e) {
            completer.completeError(e);
          }
        }
      },
      onWebResourceError: (error) {
        if (!done) {
          done = true;
          _webViewBusy = false;
          completer.completeError(Exception('WebView error: ${error.description}'));
        }
      },
    ));

    controller.loadRequest(Uri.parse(urlString));

    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        done = true;
        _webViewBusy = false;
        throw TimeoutException('WebView timeout');
      },
    );
  }

  // MARK: - fetchHTML الرئيسي — مثل iOS fetchHTML
  Future<String> fetchHTML(String urlString) async {
    // أولاً: جرب عبر WebView (يحمل الكوكيز تلقائياً)
    try {
      final html = await _fetchHTMLViaWebView(urlString);

      // فحص Cloudflare في النتيجة
      final isCloudflare = html.contains('Just a moment') ||
          html.contains('cf-browser-verification') ||
          html.contains('Checking your browser') ||
          html.contains('Attention Required') ||
          html.contains('cf_chl_opt');

      if (isCloudflare) {
        // مثل iOS: أطلق sheet وارمِ exception
        AppState.current?.triggerCloudflare(urlString);
        throw ZMangaError.cloudflareChallenge;
      }

      return html;
    } catch (e) {
      if (e is ZMangaError) rethrow;
      // خطأ في الشبكة أو WebView — أعِد رمي
      rethrow;
    }
  }

  // MARK: - AJAX مع HttpClient (للطلبات التي لا تحتاج كوكيز Cloudflare عادةً)
  Future<List<String>> _fetchChapterImagesViaAJAX(String chapterId) async {
    final ajaxURL = Uri.parse('$baseURL/wp-admin/admin-ajax.php');
    final client = HttpClient();
    try {
      final request = await client.postUrl(ajaxURL);
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.headers.set('Referer', baseURL);
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Mobile Safari/537.36');
      request.write('action=manga_get_chapter_img_list&chapter_id=$chapterId');
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        try {
          final List<dynamic> arr = jsonDecode(responseBody);
          return arr
              .map((e) => e['url'] as String?)
              .where((url) => url != null && url.startsWith('http'))
              .cast<String>()
              .toList();
        } catch (_) {}
        try {
          final Map<String, dynamic> dict = jsonDecode(responseBody);
          if (dict['data'] is Map && dict['data']['images'] is List) {
            return (dict['data']['images'] as List)
                .map((e) => e['url'] as String?)
                .where((url) => url != null && url.startsWith('http'))
                .cast<String>()
                .toList();
          }
        } catch (_) {}
        if (responseBody.contains('<img')) {
          return _parseChapterPages(responseBody);
        }
      }
    } finally {
      client.close();
    }
    return [];
  }

  // MARK: - Public API — مطابق لـ iOS
  Future<List<Manga>> fetchLatest({int page = 1}) async {
    final html = await fetchHTML('$baseURL/manga/?m_orderby=latest&page=$page');
    return _parseMangaList(html, extractChapterInfo: true);
  }

  Future<List<Manga>> fetchPopular({int page = 1}) async {
    final html = await fetchHTML('$baseURL/manga/?m_orderby=views&page=$page');
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<List<Manga>> search(String query, {int page = 1}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final html =
        await fetchHTML('$baseURL/?s=$encoded&post_type=wp-manga&page=$page');
    return _parseMangaList(html, extractChapterInfo: false)
        .where((m) =>
            !m.slug.contains('feed') &&
            m.slug.isNotEmpty &&
            m.coverURL.isNotEmpty)
        .toList();
  }

  Future<List<Manga>> fetchByGenre(String genre, {int page = 1}) async {
    final html = await fetchHTML('$baseURL/manga-genre/$genre/?page=$page');
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<Manga> fetchDetail(String slug) async {
    final html = await fetchHTML('$baseURL/manga/$slug/');
    return _parseMangaDetail(html, slug);
  }

  Future<List<String>> fetchChapterPages(
      String mangaSlug, String chapterSlug) async {
    final urlString = '$baseURL/manga/$mangaSlug/$chapterSlug/';

    final html = await fetchHTML(urlString);

    // AJAX (أسرع)
    final chapterId = _firstCapture(
      r'(?:wp-manga-current-chap[^>]+data-id|data-id)="(\d+)"',
      html,
    );
    if (chapterId != null) {
      try {
        final pages = await _fetchChapterImagesViaAJAX(chapterId);
        if (pages.isNotEmpty) return pages;
      } catch (_) {}
    }

    // Parse مباشر
    final directPages = _parseChapterPages(html);
    if (directPages.isNotEmpty) return directPages;

    // WebView مع انتظار lazy loading — مثل iOS النهاية
    try {
      final controller = _getSharedWebView();
      // استخدم WebView موجود لكن اقرأ الصور بعد تحميل lazy
      final wvHTML = await _fetchHTMLViaWebViewWithLazyWait(urlString);
      return _parseChapterPages(wvHTML);
    } catch (_) {
      return [];
    }
  }

  Future<String> _fetchHTMLViaWebViewWithLazyWait(String urlString) async {
    int waitCount = 0;
    while (_webViewBusy && waitCount < 30) {
      await Future.delayed(const Duration(milliseconds: 200));
      waitCount++;
    }
    _webViewBusy = true;

    final controller = _getSharedWebView();
    final completer = Completer<String>();
    bool done = false;

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        if (done) return;

        // انتظر lazy loading — مثل iOS waitJS
        await Future.delayed(const Duration(milliseconds: 500));
        if (done) return;

        // تحقق من وجود الصور
        for (int i = 0; i < 15; i++) {
          if (done) return;
          try {
            final result = await controller.runJavaScriptReturningResult('''
              (function() {
                var imgs = document.querySelectorAll('.reading-content img');
                for(var j=0; j<imgs.length; j++) {
                  var s = imgs[j].dataset.lazySrc || imgs[j].dataset.src || imgs[j].src || '';
                  if(s.startsWith('http') && !s.includes('data:image')) return 'ok';
                }
                return '';
              })()
            ''');
            if (result.toString().contains('ok')) break;
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (!done) {
          done = true;
          _webViewBusy = false;
          try {
            final html = await controller
                .runJavaScriptReturningResult('document.documentElement.outerHTML');
            completer.complete(html.toString());
          } catch (e) {
            completer.completeError(e);
          }
        }
      },
      onWebResourceError: (error) {
        if (!done) {
          done = true;
          _webViewBusy = false;
          completer.completeError(Exception('WebView error'));
        }
      },
    ));

    controller.loadRequest(Uri.parse(urlString));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        done = true;
        _webViewBusy = false;
        throw TimeoutException('Lazy load timeout');
      },
    );
  }

  // ─── دوال التحليل — مطابقة لـ iOS ────────────────────────────────
  List<Manga> _parseMangaList(String html,
      {required bool extractChapterInfo}) {
    if (html.isEmpty) return [];
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
      results.addAll(
          _parseMangaSimple(html, extractChapterInfo: extractChapterInfo));
    }
    return results;
  }

  bool _isLogoOnly(String url) {
    final lower = url.toLowerCase();
    return lower.contains('lekmanga.png') ||
        lower.contains('-512.png') ||
        lower.contains('/favicon');
  }

  Manga? _parseMangaCard(String block) {
    final slug =
        _firstCapture(r'href="https?://[^/]+/manga/([^/"]+)/"', block);
    if (slug == null || slug.isEmpty) return null;

    final title = _firstCapture(r'<h3[^>]*>\s*<a[^>]*>([^<]+)</a>', block) ??
        _firstCapture(r'<h5[^>]*>\s*<a[^>]*>([^<]+)</a>', block) ??
        slug.replaceAll('-', ' ');

    final allImgTags = _extractHTMLTags('img', block);
    final cover = _extractImageURL(allImgTags);
    if (slug.isEmpty || slug == 'feed' || _isLogoOnly(cover)) return null;
    return Manga(slug: slug, title: _htmlDecode(title), coverURL: cover);
  }

  List<String> _extractHTMLTags(String tagName, String html) {
    final regex = RegExp('<$tagName\\s[^>]*>',
        dotAll: true, caseSensitive: false);
    return regex.allMatches(html).map((m) => m.group(0)!).toList();
  }

  String _extractImageURL(List<String> tags) {
    for (final tag in tags) {
      final m1 = RegExp(r'data-lazy-src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m1 != null && m1.group(1)!.startsWith('http')) return m1.group(1)!;
      final m2 = RegExp(r'data-src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m2 != null && m2.group(1)!.startsWith('http')) return m2.group(1)!;
      final m3 = RegExp(r'src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m3 != null &&
          m3.group(1)!.startsWith('http') &&
          !_isLogoOnly(m3.group(1)!)) {
        return m3.group(1)!;
      }
    }
    return '';
  }

  List<Manga> _parseMangaSimple(String html,
      {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final linkPattern = RegExp(
        r'href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"');
    for (final match in linkPattern.allMatches(html)) {
      final slug = match.group(2)!;
      final rawTitle = match.group(3)!.trim();
      if (slug.isEmpty ||
          rawTitle.isEmpty ||
          rawTitle.length > 200 ||
          slug == 'feed' ||
          slug.contains('cdn-cgi')) continue;
      if (results.any((m) => m.slug == slug)) continue;

      final searchStart = match.start;
      final searchEnd = (searchStart + 2000).clamp(0, html.length);
      final searchBlock = html.substring(searchStart, searchEnd);
      final allImgTags = _extractHTMLTags('img', searchBlock);
      final cover = _extractImageURL(allImgTags);
      var manga = Manga(
        slug: slug,
        title: _htmlDecode(rawTitle),
        coverURL: _isLogoOnly(cover) ? '' : cover,
      );
      if (extractChapterInfo) {
        final info = _parseLatestChapterInfo(searchBlock);
        manga = manga.copyWith(
            latestChapterNumber: info.chapter, lastUpdated: info.time);
      }
      results.add(manga);
    }
    return results;
  }

  _ChapterInfo _parseLatestChapterInfo(String block) {
    final ch = _firstCapture(
        r'<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>', block);
    final time = _firstCapture(
        r'<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>', block);
    return _ChapterInfo(ch?.trim(), time?.trim());
  }

  Manga _parseMangaDetail(String html, String slug) {
    final title = _firstCapture(
            r'<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)', html) ??
        slug.replaceAll('-', ' ');

    final summaryBlock = _firstCapture(
            r'(<div class="summary_image[^"]*">.*?</div>)', html) ??
        html;
    final allImgTags = _extractHTMLTags('img', summaryBlock);
    final cover = _extractImageURL(allImgTags);

    final descRaw =
        _firstCapture(r'<div class="summary__content[^"]*">(.*?)</div>', html);
    final description =
        descRaw != null ? _stripHTML(descRaw).trim() : '';

    final rating =
        _firstCapture(r'id="averagerate"[^>]*>([^<]+)<', html) ?? '';
    final status = _firstCapture(
            r'<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>',
            html) ??
        '';
    final authorRaw =
        _firstCapture(r'class="author-content">(.*?)</div>', html);
    final author = authorRaw != null ? _stripHTML(authorRaw) : '';

    final genres = <String>[];
    final genreReg = RegExp(r'/manga-genre/[^/]+/">([^<]+)</a>');
    for (final m in genreReg.allMatches(html)) {
      genres.add(m.group(1)!);
    }

    final chapters = <Chapter>[];
    final chapterBlockReg =
        RegExp(r'<li class="wp-manga-chapter[^"]*">(.*?)</li>', dotAll: true);
    for (final m in chapterBlockReg.allMatches(html)) {
      final block = m.group(1)!;
      final fullLink =
          _firstCapture(r'href="(https?://[^/]+/manga/[^/]+/([^/]+)/)"', block);
      if (fullLink != null) {
        final uri = Uri.parse(fullLink);
        final slugPart =
            uri.pathSegments.where((s) => s.isNotEmpty && s != '/').last;
        final numberPart =
            _firstCapture(r'>(\d+)</a>', block) ?? slugPart;
        final date = _firstCapture(r'i[^>]*>([^<]+)<', block)?.trim() ?? '';
        if (slugPart.isNotEmpty && !chapters.any((c) => c.slug == slugPart)) {
          chapters.add(Chapter(slug: slugPart, number: numberPart, date: date));
        }
      }
    }
    if (chapters.isEmpty) {
      final fallbackReg = RegExp(
          r'href="https?://[^/]+/manga/[^/]+/([\d]+(?:-[\d]+)?)/\"[^>]*>\s*(?:<[^>]*>\s*)*(\d+)"');
      for (final m in fallbackReg.allMatches(html)) {
        final s = m.group(1)!;
        final n = m.group(2)!;
        if (!chapters.any((c) => c.slug == s)) {
          chapters.add(Chapter(slug: s, number: n));
        }
      }
    }
    chapters.sort((a, b) =>
        (int.tryParse(b.number) ?? 0).compareTo(int.tryParse(a.number) ?? 0));

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
    final content = _extractReadingContent(html);
    final seen = <String>{};
    final pages = <String>[];

    final imgRegex =
        RegExp(r'<img\s[^>]*>', dotAll: true, caseSensitive: false);
    for (final match in imgRegex.allMatches(content)) {
      final tag = match.group(0)!;
      if (!tag.contains('wp-manga-chapter-img') &&
          !tag.contains('data-src') &&
          !tag.contains('data-lazy-src')) continue;

      final url =
          _firstCapture(r'data-lazy-src="([^"]+)"', tag) ??
          _firstCapture(r'data-src="([^"]+)"', tag) ??
          _firstCapture(r'src="([^"]+)"', tag);
      if (url != null &&
          url.startsWith('http') &&
          !url.contains('data:image') &&
          !_isLogoOnly(url) &&
          !seen.contains(url)) {
        seen.add(url);
        pages.add(url.trim());
      }
    }
    return pages;
  }

  String _extractReadingContent(String html) {
    final startPattern = RegExp(
        r'<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>',
        caseSensitive: false);
    final startMatch = startPattern.firstMatch(html);
    if (startMatch == null) return html;

    final startIndex = startMatch.start + startMatch.group(0)!.length;
    final remaining = html.substring(startIndex);
    var depth = 1;
    var currentIndex = 0;

    while (currentIndex < remaining.length && depth > 0) {
      final sub = remaining.substring(currentIndex);
      final nextDiv =
          RegExp(r'</?div', caseSensitive: false).firstMatch(sub);
      if (nextDiv == null) break;
      final tag = nextDiv.group(0)!;
      depth += tag.startsWith('</') ? -1 : 1;
      currentIndex += nextDiv.start + nextDiv.group(0)!.length;
    }

    if (depth == 0) {
      return remaining.substring(
          0, (currentIndex - '</div>'.length).clamp(0, remaining.length));
    }
    return remaining;
  }

  String? _firstCapture(String pattern, String text) {
    final match =
        RegExp(pattern, dotAll: true).firstMatch(text);
    if (match == null || match.groupCount < 1) return null;
    return match.group(1);
  }

  String _stripHTML(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

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
