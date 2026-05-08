import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/models.dart';
import '../state/app_state.dart';

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

  // WebView مخصص لجلب صفحات الفصول فقط (lazy loading)
  // يجب أن يكون مرتبطاً بـ WebViewWidget في الـ widget tree
  WebViewController? _chapterWebViewController;

  WebViewController getChapterWebViewController() {
    if (_chapterWebViewController != null) return _chapterWebViewController!;
    _chapterWebViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      );
    return _chapterWebViewController!;
  }

  // MARK: - fetchHTML عبر HttpClient مباشرة — مثل iOS URLSession
  // الكوكيز تأتي من WebView CookieManager بعد حل Cloudflare
  Future<String> fetchHTML(String urlString) async {
    final uri = Uri.parse(urlString);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Mobile Safari/537.36');
      request.headers.set('Referer', baseURL);
      request.headers
          .set('Accept', 'text/html,application/xhtml+xml,*/*;q=0.8');
      request.headers.set('Accept-Language', 'ar,en;q=0.9');

      // حقن كوكيز Cloudflare من WebView CookieManager
      await _injectWebViewCookies(request, uri);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      final isCloudflare = response.statusCode == 403 ||
          response.statusCode == 503 ||
          body.contains('Just a moment') ||
          body.contains('cf-browser-verification') ||
          body.contains('Checking your browser') ||
          body.contains('Attention Required') ||
          body.contains('cf_chl_opt');

      if (isCloudflare) {
        AppState.current?.triggerCloudflare(urlString);
        throw ZMangaError.cloudflareChallenge;
      }

      if (response.statusCode == 200) return body;
      throw Exception('HTTP ${response.statusCode}');
    } finally {
      client.close();
    }
  }

  // استخرج كوكيز من AppState وأضفها للطلب
  Future<void> _injectWebViewCookies(HttpClientRequest request, Uri uri) async {
    try {
      final cookies = AppState.current?.cfCookies;
      if (cookies != null && cookies.isNotEmpty) {
        request.headers.set('Cookie', cookies);
      }
    } catch (_) {}
  }

  // MARK: - fetchHTMLViaWebView للفصول فقط
  // يُستخدم فقط عند الحاجة لـ lazy loading
  Future<String> fetchHTMLViaWebView(String urlString) async {
    final controller = getChapterWebViewController();
    final completer = Completer<String>();
    bool done = false;

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        if (done) return;
        await Future.delayed(const Duration(milliseconds: 500));
        if (done) return;

        // انتظر lazy loading
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
          completer.completeError(Exception('WebView error'));
        }
      },
    ));

    controller.loadRequest(Uri.parse(urlString));

    return completer.future.timeout(const Duration(seconds: 30));
  }

  // MARK: - Public API
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

    // AJAX
    final chapterId = _firstCapture(
        r'(?:wp-manga-current-chap[^>]+data-id|data-id)="(\d+)"', html);
    if (chapterId != null) {
      try {
        final pages = await _fetchChapterImagesViaAJAX(chapterId);
        if (pages.isNotEmpty) return pages;
      } catch (_) {}
    }

    final directPages = _parseChapterPages(html);
    if (directPages.isNotEmpty) return directPages;

    return [];
  }

  Future<List<String>> _fetchChapterImagesViaAJAX(String chapterId) async {
    final ajaxURL = Uri.parse('$baseURL/wp-admin/admin-ajax.php');
    final client = HttpClient();
    try {
      final request = await client.postUrl(ajaxURL);
      request.headers
          .set('Content-Type', 'application/x-www-form-urlencoded');
      request.headers.set('Referer', baseURL);
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Mobile Safari/537.36');
      request.write(
          'action=manga_get_chapter_img_list&chapter_id=$chapterId');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        try {
          final List<dynamic> arr = jsonDecode(body);
          return arr
              .map((e) => e['url'] as String?)
              .where((u) => u != null && u.startsWith('http'))
              .cast<String>()
              .toList();
        } catch (_) {}
        try {
          final Map<String, dynamic> dict = jsonDecode(body);
          if (dict['data'] is Map && dict['data']['images'] is List) {
            return (dict['data']['images'] as List)
                .map((e) => e['url'] as String?)
                .where((u) => u != null && u.startsWith('http'))
                .cast<String>()
                .toList();
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return [];
  }

  // ─── Parse ────────────────────────────────────────────────────────
  List<Manga> _parseMangaList(String html, {required bool extractChapterInfo}) {
    if (html.isEmpty) return [];
    final results = <Manga>[];
    final cardPattern = RegExp(
      r'<div class="page-item-detail[^"]*manga[^"]*">(.*?)</div>\s*</div>\s*</div>',
      dotAll: true,
    );
    for (final match in cardPattern.allMatches(html).take(30)) {
      final block = match.group(1)!;
      var manga = _parseMangaCard(block);
      if (manga == null) continue;
      if (manga.coverURL.isEmpty || _isLogoOnly(manga.coverURL)) continue;
      if (extractChapterInfo) {
        final info = _parseLatestChapterInfo(block);
        manga = manga.copyWith(
            latestChapterNumber: info.chapter, lastUpdated: info.time);
      }
      results.add(manga);
    }
    if (results.isEmpty) {
      results.addAll(
          _parseMangaSimple(html, extractChapterInfo: extractChapterInfo));
    }
    return results;
  }

  bool _isLogoOnly(String url) {
    final l = url.toLowerCase();
    return l.contains('lekmanga.png') ||
        l.contains('-512.png') ||
        l.contains('/favicon');
  }

  Manga? _parseMangaCard(String block) {
    final slug =
        _firstCapture(r'href="https?://[^/]+/manga/([^/"]+)/"', block);
    if (slug == null || slug.isEmpty || slug == 'feed') return null;
    final title =
        _firstCapture(r'<h3[^>]*>\s*<a[^>]*>([^<]+)</a>', block) ??
        _firstCapture(r'<h5[^>]*>\s*<a[^>]*>([^<]+)</a>', block) ??
        slug.replaceAll('-', ' ');
    final cover = _extractImageURL(_extractHTMLTags('img', block));
    if (_isLogoOnly(cover)) return null;
    return Manga(slug: slug, title: _htmlDecode(title), coverURL: cover);
  }

  List<String> _extractHTMLTags(String tag, String html) =>
      RegExp('<$tag\\s[^>]*>', dotAll: true, caseSensitive: false)
          .allMatches(html)
          .map((m) => m.group(0)!)
          .toList();

  String _extractImageURL(List<String> tags) {
    for (final tag in tags) {
      final m1 = RegExp(r'data-lazy-src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m1 != null && m1.group(1)!.startsWith('http')) return m1.group(1)!;
      final m2 = RegExp(r'data-src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m2 != null && m2.group(1)!.startsWith('http')) return m2.group(1)!;
      final m3 = RegExp(r'src\s*=\s*"([^"]+)"').firstMatch(tag);
      if (m3 != null && m3.group(1)!.startsWith('http') && !_isLogoOnly(m3.group(1)!)) {
        return m3.group(1)!;
      }
    }
    return '';
  }

  List<Manga> _parseMangaSimple(String html, {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final rx = RegExp(
        r'href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"');
    for (final m in rx.allMatches(html)) {
      final slug = m.group(2)!;
      final rawTitle = m.group(3)!.trim();
      if (slug.isEmpty || rawTitle.isEmpty || rawTitle.length > 200 ||
          slug == 'feed' || slug.contains('cdn-cgi')) continue;
      if (results.any((x) => x.slug == slug)) continue;
      final end = (m.start + 2000).clamp(0, html.length);
      final block = html.substring(m.start, end);
      final cover = _extractImageURL(_extractHTMLTags('img', block));
      var manga = Manga(
          slug: slug,
          title: _htmlDecode(rawTitle),
          coverURL: _isLogoOnly(cover) ? '' : cover);
      if (extractChapterInfo) {
        final info = _parseLatestChapterInfo(block);
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
    final summaryBlock =
        _firstCapture(r'(<div class="summary_image[^"]*">.*?</div>)', html) ??
            html;
    final cover = _extractImageURL(_extractHTMLTags('img', summaryBlock));
    final descRaw = _firstCapture(
        r'<div class="summary__content[^"]*">(.*?)</div>', html);
    final description = descRaw != null ? _stripHTML(descRaw).trim() : '';
    final rating =
        _firstCapture(r'id="averagerate"[^>]*>([^<]+)<', html) ?? '';
    final status = _firstCapture(
            r'<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>',
            html) ??
        '';
    final authorRaw =
        _firstCapture(r'class="author-content">(.*?)</div>', html);
    final author = authorRaw != null ? _stripHTML(authorRaw) : '';
    final genres = RegExp(r'/manga-genre/[^/]+/">([^<]+)</a>')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();

    final chapters = <Chapter>[];
    final chapBlock =
        RegExp(r'<li class="wp-manga-chapter[^"]*">(.*?)</li>', dotAll: true);
    for (final m in chapBlock.allMatches(html)) {
      final block = m.group(1)!;
      final fullLink = _firstCapture(
          r'href="(https?://[^/]+/manga/[^/]+/([^/]+)/)"', block);
      if (fullLink != null) {
        final uri = Uri.parse(fullLink);
        final slugPart =
            uri.pathSegments.where((s) => s.isNotEmpty && s != '/').last;
        final num = _firstCapture(r'>(\d+)</a>', block) ?? slugPart;
        final date = _firstCapture(r'i[^>]*>([^<]+)<', block)?.trim() ?? '';
        if (slugPart.isNotEmpty && !chapters.any((c) => c.slug == slugPart)) {
          chapters.add(Chapter(slug: slugPart, number: num, date: date));
        }
      }
    }
    if (chapters.isEmpty) {
      final fb = RegExp(
          r'href="https?://[^/]+/manga/[^/]+/([\d]+(?:-[\d]+)?)/\"[^>]*>\s*(?:<[^>]*>\s*)*(\d+)"');
      for (final m in fb.allMatches(html)) {
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
        author: author);
  }

  List<String> _parseChapterPages(String html) {
    final content = _extractReadingContent(html);
    final seen = <String>{};
    final pages = <String>[];
    for (final m in RegExp(r'<img\s[^>]*>',
            dotAll: true, caseSensitive: false)
        .allMatches(content)) {
      final tag = m.group(0)!;
      if (!tag.contains('wp-manga-chapter-img') &&
          !tag.contains('data-src') &&
          !tag.contains('data-lazy-src')) continue;
      final url = _firstCapture(r'data-lazy-src="([^"]+)"', tag) ??
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
    final startMatch = RegExp(
            r'<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>',
            caseSensitive: false)
        .firstMatch(html);
    if (startMatch == null) return html;
    final remaining = html.substring(startMatch.start + startMatch.group(0)!.length);
    var depth = 1;
    var idx = 0;
    while (idx < remaining.length && depth > 0) {
      final sub = remaining.substring(idx);
      final next = RegExp(r'</?div', caseSensitive: false).firstMatch(sub);
      if (next == null) break;
      depth += next.group(0)!.startsWith('</') ? -1 : 1;
      idx += next.start + next.group(0)!.length;
    }
    if (depth == 0) {
      return remaining.substring(
          0, (idx - '</div>'.length).clamp(0, remaining.length));
    }
    return remaining;
  }

  String? _firstCapture(String pattern, String text) {
    final m = RegExp(pattern, dotAll: true).firstMatch(text);
    if (m == null || m.groupCount < 1) return null;
    return m.group(1);
  }

  String _stripHTML(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  String _htmlDecode(String s) => s
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
