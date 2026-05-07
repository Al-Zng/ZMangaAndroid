import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../models/models.dart';
import '../state/app_state.dart';

class MangaService {
  static const String baseURL = 'https://lekmanga.site';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  // WebView مخصص فقط لتحميل صفحات الفصول (lazy loading) ولتجاوز Cloudflare
  WebViewController? _chapterWebViewController;

  WebViewController _getChapterWebViewController() {
    if (_chapterWebViewController != null) return _chapterWebViewController!;
    _chapterWebViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      );
    return _chapterWebViewController!;
  }

  // MARK: - fetchHTML عبر URLSession مباشرة
  Future<String> fetchHTML(String urlString) async {
    final uri = Uri.parse(urlString);
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1');
    request.headers.set('Referer', 'https://lekmanga.site');
    request.headers.set('Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    request.headers.set('Accept-Language', 'ar,en;q=0.9');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 403 ||
        responseBody.contains('Just a moment') ||
        responseBody.contains('cf-browser-verification') ||
        responseBody.contains('Checking your browser') ||
        responseBody.contains('Attention Required')) {
      // Cloudflare detected -> trigger popup
      final wvHTML = await _fetchHTMLViaWebView(urlString);
      if (wvHTML.contains('Just a moment') ||
          wvHTML.contains('Checking your browser')) {
        AppState.current?.triggerCloudflare(urlString);
        throw Exception('Cloudflare challenge');
      }
      return wvHTML;
    }
    if (response.statusCode == 200) {
      return responseBody;
    } else {
      throw Exception('Failed to load: ${response.statusCode}');
    }
  }

  // MARK: - fetchHTMLViaWebView (مثل iOS تماماً)
  Future<String> _fetchHTMLViaWebView(String urlString) async {
    final controller = _getChapterWebViewController();
    final completer = Completer<String>();

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        final html = await controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        ) as String? ?? '';
        if (!completer.isCompleted) {
          completer.complete(html);
        }
      },
      onWebResourceError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('WebView error'));
        }
      },
    ));
    controller.loadRequest(Uri.parse(urlString));

    return completer.future.timeout(const Duration(seconds: 30));
  }

  // MARK: - Public API
  Future<List<Manga>> fetchLatest({int page = 1}) async {
    final html =
        await fetchHTML('$baseURL/manga/?m_orderby=latest&page=$page');
    return _parseMangaList(html, extractChapterInfo: true);
  }

  Future<List<Manga>> fetchPopular({int page = 1}) async {
    final html =
        await fetchHTML('$baseURL/manga/?m_orderby=views&page=$page');
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
    final html =
        await fetchHTML('$baseURL/manga-genre/$genre/?page=$page');
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<Manga> fetchDetail(String slug) async {
    final html = await fetchHTML('$baseURL/manga/$slug/');
    if (html.isEmpty) throw Exception('Cloudflare challenge');
    return _parseMangaDetail(html, slug);
  }

  Future<List<String>> fetchChapterPages(
      String mangaSlug, String chapterSlug) async {
    final urlString = '$baseURL/manga/$mangaSlug/$chapterSlug/';

    // 1. جلب HTML أولاً عبر URLSession للحصول على chapter_id
    final html = await fetchHTML(urlString);

    // 2. محاولة AJAX (الأسرع)
    final chapterIdPattern =
        r'(?:wp-manga-current-chap[^>]+data-id|data-id)="(\d+)"';
    final chapterIdRegExp = RegExp(chapterIdPattern);
    final chapterIdMatch = chapterIdRegExp.firstMatch(html);
    if (chapterIdMatch != null) {
      final chapterId = chapterIdMatch.group(1)!;
      try {
        final pages = await _fetchChapterImagesViaAJAX(chapterId);
        if (pages.isNotEmpty) return pages;
      } catch (_) {}
    }

    // 3. محاولة parse مباشر من HTML الأولي
    final directPages = _parseChapterPages(html);
    if (directPages.isNotEmpty) return directPages;

    // 4. آخر حل: WKWebView مع انتظار lazy loading
    final controller = _getChapterWebViewController();
    final completer = Completer<String>();

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        // انتظر الـ lazy loading
        final waitJS = '''
        new Promise((resolve) => {
            let tries = 0;
            const check = () => {
                tries++;
                const imgs = document.querySelectorAll('.reading-content img');
                const ok = Array.from(imgs).some(img => {
                    const s = img.dataset.lazySrc || img.dataset.src || img.src || '';
                    return s.startsWith('http') && !s.includes('data:image');
                });
                if (ok || tries >= 15) resolve(tries);
                else setTimeout(check, 200);
            };
            setTimeout(check, 500);
        });
        ''';
        await controller.runJavaScript(waitJS);
        final finalHTML = await controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        ) as String? ?? '';
        if (!completer.isCompleted) {
          completer.complete(finalHTML);
        }
      },
      onWebResourceError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('WebView error'));
        }
      },
    ));
    controller.loadRequest(Uri.parse(urlString));

    final finalHTML =
        await completer.future.timeout(const Duration(seconds: 30));
    return _parseChapterPages(finalHTML);
  }

  // MARK: - AJAX Image Fetching
  Future<List<String>> _fetchChapterImagesViaAJAX(String chapterId) async {
    final ajaxURL = Uri.parse('$baseURL/wp-admin/admin-ajax.php');
    final client = HttpClient();
    final request = await client.postUrl(ajaxURL);
    request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    request.headers.set('Referer', baseURL);
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    request.headers.set('User-Agent',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1');
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
        if (dict.containsKey('data') && dict['data'] is List) {
          return (dict['data'] as List)
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
    return [];
  }

  // ========================
  // دوال التحليل (مطابقة لـ Swift)
  // ========================
  List<Manga> _parseMangaList(String html,
      {required bool extractChapterInfo}) {
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

  bool _isLogoOnly(String url) =>
      url.toLowerCase().contains('lekmanga.png') ||
      url.toLowerCase().contains('-512.png') ||
      url.toLowerCase().contains('/favicon');

  Manga? _parseMangaCard(String block) {
    final slugReg = RegExp(r'href="https?://[^/]+/manga/([^/"]+)/"');
    final slugMatch = slugReg.firstMatch(block);
    if (slugMatch == null) return null;
    final slug = slugMatch.group(1)!;

    final titleReg1 = RegExp(r'<h3[^>]*>\s*<a[^>]*>([^<]+)</a>');
    final titleReg2 = RegExp(r'<h5[^>]*>\s*<a[^>]*>([^<]+)</a>');
    final title = titleReg1.firstMatch(block)?.group(1) ??
        titleReg2.firstMatch(block)?.group(1) ??
        slug
            .replaceAll('-', ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');

    final allImgTags = _extractHTMLTags('img', block);
    final cover = _extractImageURL(allImgTags);
    if (slug.isEmpty || slug == 'feed' || _isLogoOnly(cover)) return null;
    return Manga(slug: slug, title: _htmlDecode(title), coverURL: cover);
  }

  List<String> _extractHTMLTags(String tagName, String html) {
    final pattern = '<$tagName\\s[^>]*>';
    final regex = RegExp(pattern, dotAll: true, caseSensitive: false);
    return regex.allMatches(html).map((m) => m.group(0)!).toList();
  }

  String _extractImageURL(List<String> tags) {
    for (final tag in tags) {
      final dataLazySrc = RegExp(r'data-lazy-src\s*=\s*"([^"]+)"');
      final match1 = dataLazySrc.firstMatch(tag);
      if (match1 != null && match1.group(1)!.startsWith('http')) {
        return match1.group(1)!;
      }
      final dataSrc = RegExp(r'data-src\s*=\s*"([^"]+)"');
      final match2 = dataSrc.firstMatch(tag);
      if (match2 != null && match2.group(1)!.startsWith('http')) {
        return match2.group(1)!;
      }
      final src = RegExp(r'src\s*=\s*"([^"]+)"');
      final match3 = src.firstMatch(tag);
      if (match3 != null &&
          match3.group(1)!.startsWith('http') &&
          !_isLogoOnly(match3.group(1)!)) {
        return match3.group(1)!;
      }
    }
    return '';
  }

  bool _isValidImageURL(String url) =>
      url.startsWith('http') &&
      ['.jpg', '.jpeg', '.png', '.webp'].any(url.toLowerCase().contains);

  List<Manga> _parseMangaSimple(String html,
      {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final linkPattern = RegExp(
        r'href="(https?://[^/]+/manga/([^/"]+)/)\"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"');
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
    final ch = RegExp(
        r'<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>');
    final chMatch = ch.firstMatch(block)?.group(1)?.trim();
    final time = RegExp(
        r'<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>');
    final timeMatch = time.firstMatch(block)?.group(1)?.trim();
    return _ChapterInfo(chMatch, timeMatch);
  }

  Manga _parseMangaDetail(String html, String slug) {
    final titleReg =
        RegExp(r'<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)');
    final title =
        titleReg.firstMatch(html)?.group(1) ?? slug.replaceAll('-', ' ');
    final summaryBlock =
        RegExp(r'(<div class="summary_image[^"]*">.*?</div>)', dotAll: true)
            .firstMatch(html)
            ?.group(1) ?? html;
    final allImgTags = _extractHTMLTags('img', summaryBlock);
    final cover = _extractImageURL(allImgTags);

    final descReg =
        RegExp(r'<div class="summary__content[^"]*">(.*?)</div>', dotAll: true);
    String description = '';
    if (descReg.firstMatch(html) case var m?) {
      description = _stripHTML(m.group(1)!).trim();
    }
    final ratingReg = RegExp(r'id="averagerate"[^>]*>([^<]+)<');
    final rating = ratingReg.firstMatch(html)?.group(1) ?? '';
    final statusReg = RegExp(
        r'<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>');
    final status = statusReg.firstMatch(html)?.group(1) ?? '';
    final authorReg =
        RegExp(r'class="author-content">(.*?)</div>', dotAll: true);
    final author =
        authorReg.firstMatch(html)?.group(1)?.let((it) => _stripHTML(it)) ?? '';

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
      final linkReg =
          RegExp(r'href="(https?://[^/]+/manga/[^/]+/([^/]+)/)"');
      final linkMatch = linkReg.firstMatch(block);
      if (linkMatch != null) {
        final fullLink = linkMatch.group(1)!;
        final uri = Uri.parse(fullLink);
        final slugPart =
            uri.pathSegments.where((s) => s.isNotEmpty && s != '/').last;
        final numberReg = RegExp(r'>(\d+)</a>');
        final numberPart =
            numberReg.firstMatch(block)?.group(1) ?? slugPart;
        final dateReg = RegExp(
            r'i[^>]*>([^<]+)<');
        final date = dateReg.firstMatch(block)?.group(1)?.trim() ?? '';
        if (slugPart.isNotEmpty &&
            !chapters.any((c) => c.slug == slugPart)) {
          chapters.add(
              Chapter(slug: slugPart, number: numberPart, date: date));
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

    final allImgPattern = r'<img\s[^>]*>';
    final imgRegex = RegExp(allImgPattern, dotAll: true, caseSensitive: false);
    for (final match in imgRegex.allMatches(content)) {
      final tag = match.group(0)!;
      // تجاهل الصور التي لا تحمل أي من هذه السمات (صور أغلفة، أيقونات)
      if (!tag.contains('wp-manga-chapter-img') &&
          !tag.contains('data-src') &&
          !tag.contains('data-lazy-src')) continue;

      final url = RegExp(r'data-lazy-src="([^"]+)"').firstMatch(tag)?.group(1) ??
          RegExp(r'data-src="([^"]+)"').firstMatch(tag)?.group(1) ??
          RegExp(r'src="([^"]+)"').firstMatch(tag)?.group(1);
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
    final startPattern =
        r'<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>';
    final startRegex = RegExp(startPattern, caseSensitive: false);
    final startMatch = startRegex.firstMatch(html);
    if (startMatch == null) return html;

    final startIndex = startMatch.start + startMatch.group(0)!.length;
    final remaining = html.substring(startIndex);
    var depth = 1;
    var currentIndex = 0;

    while (currentIndex < remaining.length && depth > 0) {
      final remainingString = remaining.substring(currentIndex);
      final nextDivRegex = RegExp(r'</?div', caseSensitive: false);
      final nextMatch = nextDivRegex.firstMatch(remainingString);
      if (nextMatch == null) break;

      final tag = nextMatch.group(0)!;
      depth += tag.startsWith('</') ? -1 : 1;
      currentIndex += nextMatch.start + nextMatch.group(0)!.length;
    }

    if (depth == 0) {
      return remaining.substring(
          0, (currentIndex - '</div>'.length).clamp(0, remaining.length));
    }
    return remaining;
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

extension on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}

extension on Object? {
  R let<R>(R Function(dynamic) cb) => cb(this);
}