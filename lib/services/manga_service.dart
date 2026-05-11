import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../core/network/http_service.dart';
import '../core/network/user_agent.dart';
import '../core/cloudflare/cloudflare_service.dart';

class MangaService {
  static const String baseURL = 'https://lekmanga.site';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  final _http = HttpService();
  final _cf = CloudflareService();

  WebViewController? _chapterWebViewController;

  // ─── Mutex لـ _fetchHTMLViaWebView ───────────────────────────────
  // يمنع استخدام نفس الـ WebView بشكل متزامن (race condition)
  // السبب: setNavigationDelegate يستبدل الـ delegate السابق فيضيع الـ Completer الأول
  bool _wvBusy = false;
  // ✅ FIX: كل عنصر في القائمة يحمل الـ completer + الـ URL المطلوب
  final _wvQueue = <({Completer<String> completer, String url})>[];

  WebViewController _getChapterWebViewController() {
    if (_chapterWebViewController != null) return _chapterWebViewController!;
    _chapterWebViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ✅ نفس UA كالـ bypass sheet للحصول على نفس الـ cf_clearance cookie
      ..setUserAgent(AppUserAgent.androidChrome);
    return _chapterWebViewController!;
  }

  // MARK: - Core fetchHTML مع Dio + iOS UA + Cookie Injection

  // ─── وقت آخر حل ناجح لـ Cloudflare ─────────────────────────────
  // نستخدمه لتجنب إعادة الطلب عبر Dio (الذي ليس عنده cf_clearance)
  // بعد الحل مباشرة، نوجّه كل الطلبات عبر WebView لمدة 5 دقائق
  DateTime? _lastCfSolveTime;

  bool get _cfSolvedRecently {
    if (_lastCfSolveTime == null) return false;
    return DateTime.now().difference(_lastCfSolveTime!) <
        const Duration(minutes: 2);
  }

  /// يُستدعى من AppState.onCloudflareSolved() قبل أي notifyListeners()
  /// ضروري: يجب أن يُعيَّن قبل أن يُعيد أي widget بناء نفسه ويستدعي fetchHTML
  void markCfSolved() {
    _lastCfSolveTime = DateTime.now();
    // نقل كوكيز WebView إلى Dio (مثل iOS: WKWebsiteDataStore → URLSession)
    // ملاحظة: cf_clearance هي HttpOnly — لا تظهر في document.cookie
    // لكن WebView الخفي يمتلكها في cookie store المشترك ويُرسلها تلقائياً
    _bridgeWebViewCookiesToDio();
  }

  // ✅ FIX BG: إعادة تعيين حالة CF عند العودة من الخلفية
  void resetCfState() {
    _lastCfSolveTime = null;
  }

  // ─── نقل الكوكيز من WebView إلى Dio ───────────────────────────────
  // يُحاكي iOS: WKWebsiteDataStore.getAllCookies → HTTPCookieStorage
  // cf_clearance هي HttpOnly — لا تنتقل هنا لكن WebView يُرسلها تلقائياً
  Future<void> _bridgeWebViewCookiesToDio() async {
    try {
      final wv = _getChapterWebViewController();
      final raw = await wv.runJavaScriptReturningResult(
        '(function(){ try{ return document.cookie||""; }catch(e){ return ""; } })()',
      );
      final cookies = raw.toString().replaceAll('"', '').trim();
      if (cookies.isNotEmpty && cookies != 'null') {
        _http.addSessionCookies(cookies);
      }
    } catch (e) {
      debugPrint('Cookie bridge: $e');
    }
  }

  Future<String> fetchHTML(String urlString, {int retryCount = 0}) async {
    try {
      // ✅ إذا حُل الـ CF مؤخراً، اذهب مباشرة للـ WebView
      // Dio ليس عنده cf_clearance (HttpOnly)، أما WebView فعنده من cookie store المشترك
      if (_cfSolvedRecently && retryCount == 0) {
        try {
          final wvHtml = await _fetchHTMLViaWebView(urlString);
          if (wvHtml.isNotEmpty && !_cf.isCloudflareBlock(200, wvHtml)) {
            return wvHtml;
          }
        } catch (_) {}
        // لو WebView فشل، أكمل بـ Dio كالمعتاد
      }

      final html = await _http.get(urlString);

      final isBlock = _cf.isCloudflareBlock(200, html);
      if (isBlock) {
        // ✅ سقف الـ retry = 1 (مرة واحدة فقط) لمنع الحلقة اللانهائية
        if (retryCount >= 1) {
          throw Exception('Cloudflare challenge could not be solved');
        }

        final appState = AppState.current;
        if (appState == null) return '';

        final solved = await appState.triggerCloudflare(urlString);
        if (solved) {
          _lastCfSolveTime = DateTime.now();
          try {
            final wvHtml = await _fetchHTMLViaWebView(urlString);
            if (wvHtml.isNotEmpty && !_cf.isCloudflareBlock(200, wvHtml)) {
              return wvHtml;
            }
          } catch (_) {}
          // ✅ لا نعيد استدعاء fetchHTML هنا — يسبب حلقة لانهائية
          // إذا فشل WebView بعد الحل، نرمي exception بدل إعادة trigger
          throw Exception('Content unavailable after Cloudflare bypass');
        } else {
          return '';
        }
      }

      return html;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final body = e.response?.data?.toString() ?? '';

      if (_cf.isCloudflareBlock(statusCode, body)) {
        if (retryCount >= 1) {
          throw Exception('Cloudflare challenge could not be solved');
        }
        final appState = AppState.current;
        if (appState == null) return '';
        final solved = await appState.triggerCloudflare(urlString);
        if (solved) {
          _lastCfSolveTime = DateTime.now();
          try {
            final wvHtml = await _fetchHTMLViaWebView(urlString);
            if (wvHtml.isNotEmpty && !_cf.isCloudflareBlock(200, wvHtml)) {
              return wvHtml;
            }
          } catch (_) {}
          // ✅ لا نعيد استدعاء fetchHTML — نرمي exception لمنع الحلقة
          throw Exception('Content unavailable after Cloudflare bypass');
        }
        return '';
      }

      throw Exception('Network error: $e');
    } catch (e) {
      if (e.toString().contains('Cloudflare')) rethrow;
      throw Exception('Network error: $e');
    }
  }

  // MARK: - fetchHTMLViaWebView (Android Chrome UA)
  // مع Mutex لمنع الاستدعاء المتزامن على نفس الـ WebView
  Future<String> _fetchHTMLViaWebView(String urlString) async {
    // لو الـ WebView مشغول، انتظر حتى يفرغ (حد أقصى 65 ثانية)
    if (_wvBusy) {
      final waiter = Completer<String>();
      // ✅ FIX: نحفظ الـ URL مع الـ completer حتى لا نفقده في القائمة
      _wvQueue.add((completer: waiter, url: urlString));
      try {
        return await waiter.future.timeout(const Duration(seconds: 25));
      } catch (_) {
        _wvQueue.removeWhere((e) => e.completer == waiter);
        return '';
      }
    }
    _wvBusy = true;
    try {
      return await _doFetchHTMLViaWebView(urlString);
    } finally {
      _wvBusy = false;
      // أطلق أول منتظر في القائمة بـ URL الصحيح
      if (_wvQueue.isNotEmpty) {
        final next = _wvQueue.removeAt(0);
        if (!next.completer.isCompleted) {
          // ✅ FIX: نستخدم next.url بدل urlString
          _fetchHTMLViaWebView(next.url).then(
            (r) { if (!next.completer.isCompleted) next.completer.complete(r); },
            onError: (e) { if (!next.completer.isCompleted) next.completer.completeError(e); },
          );
        }
      }
    }
  }

  Future<String> _doFetchHTMLViaWebView(String urlString) async {
    final controller = _getChapterWebViewController();
    final completer = Completer<String>();

    controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        // حقن minimal stealth JS
        controller.runJavaScript(
          '(function(){ try { Object.defineProperty(navigator, "webdriver", { get: () => undefined }); } catch(e){} })();',
        ).catchError((_) {});
        // انتظر 3 ثوانٍ لإعطاء Cloudflare وقتاً كافياً لضبط cf_clearance
        await Future.delayed(const Duration(milliseconds: 1500));

        // ✅ FIX: runJavaScriptReturningResult يُرجع نتيجة JSON مُشفَّرة
        // مثال: إذا كانت النتيجة string فتصير `"<html>..."` بعلامات اقتباس خارجية
        // وكل " داخلية تصير \" — ما يكسر الريجكس كلياً
        // الحل: نفك تشفير JSON قبل الاستخدام
        String _decodeJsHtml(dynamic raw) {
          final s = raw?.toString() ?? '';
          if (s.isEmpty) return '';
          try { return jsonDecode(s) as String? ?? s; } catch (_) { return s; }
        }

        final raw1 = await controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );
        final html = _decodeJsHtml(raw1);

        if (_cf.isCloudflareBlock(200, html)) {
          // لا تزال صفحة تحدي — انتظر أكثر
          await Future.delayed(const Duration(seconds: 2));
          final raw2 = await controller.runJavaScriptReturningResult(
            'document.documentElement.outerHTML',
          );
          final html2 = _decodeJsHtml(raw2);
          if (!completer.isCompleted) completer.complete(html2);
        } else {
          if (!completer.isCompleted) completer.complete(html);
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

    String html;
    try {
      html = await fetchHTML(urlString);
    } catch (e) {
      try {
        final wvHTML = await _fetchHTMLViaWebView(urlString);
        final pages = _parseChapterPages(wvHTML);
        if (pages.isEmpty) throw Exception('No pages found');
        return pages;
      } catch (_) {
        throw Exception('Failed to load chapter');
      }
    }

    // محاولة AJAX (الأسرع)
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

    // Parse مباشر من HTML
    final directPages = _parseChapterPages(html);
    if (directPages.isNotEmpty) return directPages;

    // آخر حل: WebView
    try {
      final wvHTML = await _fetchHTMLViaWebView(urlString);
      final wvPages = _parseChapterPages(wvHTML);
      if (wvPages.isEmpty) throw Exception('No chapter images found');
      return wvPages;
    } catch (e) {
      throw Exception('No chapter images found');
    }
  }

  // MARK: - AJAX Image Fetching (via Dio)
  Future<List<String>> _fetchChapterImagesViaAJAX(String chapterId) async {
    final body = 'action=manga_get_chapter_img_list&chapter_id=$chapterId';
    final responseBody =
        await _http.post('$baseURL/wp-admin/admin-ajax.php', body);

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

    return [];
  }

  // ─── دوال التحليل ────────────────────────────────────────────────
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
            .map((w) => w.isNotEmpty
                ? '${w[0].toUpperCase()}${w.substring(1)}'
                : '')
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
                ?.group(1) ??
            html;
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
        authorReg.firstMatch(html)?.group(1)?.let((it) => _stripHTML(it)) ??
            '';

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
        final numberPart = numberReg.firstMatch(block)?.group(1) ?? slugPart;
        final dateReg = RegExp(r'i[^>]*>([^<]+)<');
        final date = dateReg.firstMatch(block)?.group(1)?.trim() ?? '';
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

    final allImgPattern = r'<img\s[^>]*>';
    final imgRegex = RegExp(allImgPattern, dotAll: true, caseSensitive: false);
    for (final match in imgRegex.allMatches(content)) {
      final tag = match.group(0)!;
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
    final startPattern = r'<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>';
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
