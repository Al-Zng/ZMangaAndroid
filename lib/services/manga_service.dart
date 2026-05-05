import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../app_state.dart';
import '../models.dart';
import 'cookie_service.dart';

class MangaService {
  static const String baseURL = 'https://lek-manga.net';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  Future<String> fetchHTML(String urlString) async {
    final client = CookieService().client;
    var request = http.Request('GET', Uri.parse(urlString));
    request.headers['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
    request.headers['Referer'] = 'https://lek-manga.net';
    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final html = response.body;
      if (html.contains('Just a moment') ||
          html.contains('cf-browser-verification') ||
          html.contains('Checking your browser') ||
          html.contains('Attention Required')) {
        AppState.current?.triggerCloudflare(urlString);
        // ✅ لا ترمي استثناء – توقف هنا فقط
        return '';
      }
      return html;
    } else {
      throw Exception('Failed to load: ${response.statusCode}');
    }
  }

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
        .where((m) => !m.slug.contains('feed') && m.slug.isNotEmpty)
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
    final html = await fetchHTML(url);
    if (html.isEmpty) return [];
    return _parseChapterPages(html);
  }

  // ---------- دوال التحليل كما هي ----------
  List<Manga> _parseMangaList(String html, {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final cardPattern = RegExp(r'<div class="page-item-detail[^"]*">(.*?)</div>\s*</div>\s*</div>', dotAll: true);
    for (final match in cardPattern.allMatches(html).take(30)) {
      final block = match.group(1)!;
      var manga = _parseMangaCard(block);
      if (manga != null) {
        if (_isLogoOnly(manga.coverURL)) continue;
        if (extractChapterInfo) {
          final info = _parseLatestChapterInfo(block);
          manga = manga.copyWith(latestChapterNumber: info.chapter, lastUpdated: info.time);
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
    final titleReg = RegExp(r'<(?:h3|h4)[^>]*>\s*<a[^>]*>([^<]+)</a>');
    final title = titleReg.firstMatch(block)?.group(1) ?? slug.replaceAll('-', ' ').capitalize();
    final cover = _extractBestImageURL(block);
    if (slug.isEmpty || slug == 'feed' || _isLogoOnly(cover)) return null;
    return Manga(slug: slug, title: _htmlDecode(title), coverURL: cover);
  }

  String _extractBestImageURL(String block) {
    final dataSrcReg = RegExp(r'''<img[^>]+data-src="([^"]+(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"[^>]*>''');
    final match = dataSrcReg.firstMatch(block);
    if (match != null && !_isLogoOnly(match.group(1)!)) return match.group(1)!;
    final srcsetReg = RegExp(r'''<img[^>]+srcset="([^"]+)"[^>]*>''');
    final srcsetMatch = srcsetReg.firstMatch(block);
    if (srcsetMatch != null) {
      final parts = srcsetMatch.group(1)!.split(',');
      for (final p in parts) {
        final candidate = p.trim().split(' ').first;
        if (candidate.startsWith('http') && _isValidImage(candidate) && !_isLogoOnly(candidate)) return candidate;
      }
    }
    final srcReg = RegExp(r'''<img[^>]+src="([^"]+(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"[^>]*>''');
    final srcMatch = srcReg.firstMatch(block);
    if (srcMatch != null && !_isLogoOnly(srcMatch.group(1)!)) return srcMatch.group(1)!;
    return '';
  }

  bool _isValidImage(String url) =>
      url.startsWith('http') && ['jpg', 'jpeg', 'png', 'webp'].any((ext) => url.toLowerCase().contains('.$ext'));

  List<Manga> _parseMangaSimple(String html, {required bool extractChapterInfo}) {
    final results = <Manga>[];
    final linkPattern = RegExp(r'''href="(https?://[^/]+/manga/([^/"]+)/)">?\s*(?:<[^>]+>\s*)*([^<]{3,})"''');
    for (final m in linkPattern.allMatches(html)) {
      final slug = m.group(2)!;
      final rawTitle = m.group(3)!.trim();
      if (slug.isEmpty || rawTitle.isEmpty || rawTitle.length > 200 || slug == 'feed' || slug.contains('cdn-cgi')) continue;
      if (results.any((r) => r.slug == slug)) continue;
      final cover = _extractBestImageURL(html);
      var manga = Manga(slug: slug, title: _htmlDecode(rawTitle), coverURL: _isLogoOnly(cover) ? '' : cover);
      if (extractChapterInfo) {
        final info = _parseLatestChapterInfo(html);
        manga = manga.copyWith(latestChapterNumber: info.chapter, lastUpdated: info.time);
      }
      results.add(manga);
    }
    return results;
  }

  _ChapterInfo _parseLatestChapterInfo(String block) {
    final chReg = RegExp(r'''<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>''');
    final timeReg = RegExp(r'''<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>''');
    final chapter = chReg.firstMatch(block)?.group(1)?.trim();
    final time = timeReg.firstMatch(block)?.group(1)?.trim();
    return _ChapterInfo(chapter, time);
  }

  Manga _parseMangaDetail(String html, String slug) {
    final titleReg = RegExp(r'''<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)''');
    final title = titleReg.firstMatch(html)?.group(1) ?? slug.replaceAll('-', ' ');
    final cover = _extractBestImageURL(html);
    final descReg = RegExp(r'''<div class="summary__content[^"]*">(.*?)</div>''', dotAll: true);
    String description = '';
    if (descReg.firstMatch(html) case var m?) {
      description = stripHTML(m.group(1)!).trim();
    }
    final ratingReg = RegExp(r'''id="averagerate"[^>]*>([^<]+)<''');
    final rating = ratingReg.firstMatch(html)?.group(1) ?? '';
    final statusReg = RegExp(r'''<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>''');
    final status = statusReg.firstMatch(html)?.group(1) ?? '';
    final authorReg = RegExp(r'''class="author-content">(.*?)</div>''', dotAll: true);
    final author = authorReg.firstMatch(html)?.group(1)?.let((it) => stripHTML(it)) ?? '';
    final genres = <String>[];
    final genreReg = RegExp(r'''/manga-genre/[^/]+/">([^<]+)</a>''');
    genreReg.allMatches(html).forEach((m) => genres.add(m.group(1)!));

    final chapters = <Chapter>[];
    final chapLinkReg = RegExp(r'''href="https?://[^/]+/manga/[^/]+/([^/"]+)/"[^>]*>\s*(?:<[^>]*>\s*)*(?:Chapter|الفصل)\s*([\d.]+)''', caseSensitive: false, dotAll: true);
    for (final m in chapLinkReg.allMatches(html)) {
      final cSlug = m.group(1)!;
      final cNum = m.group(2)!;
      if (!chapters.any((c) => c.slug == cSlug)) chapters.add(Chapter(slug: cSlug, number: cNum));
    }
    if (chapters.isEmpty) {
      final fallbackReg = RegExp(r'''href="https?://[^/]+/manga/[^/]+/(\d+(?:-\d+)?)/"[^>]*>''');
      for (final m in fallbackReg.allMatches(html)) {
        final cSlug = m.group(1)!;
        final num = cSlug.replaceAll(RegExp(r'\D'), '');
        if (!chapters.any((c) => c.slug == cSlug)) chapters.add(Chapter(slug: cSlug, number: num));
      }
    }
    chapters.sort((a, b) => (double.tryParse(b.number) ?? 0).compareTo(double.tryParse(a.number) ?? 0));
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
    final readerBlockPatterns = [
      r'''<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>(.*?)</div>\s*</div>''',
      r'''<div[^>]+class="[^"]*read-container[^"]*"[^>]*>(.*?)</div>\s*</div>''',
      r'''<div[^>]+id="[^"]*chapter-content[^"]*"[^>]*>(.*?)</div>''',
    ];
    String? readerBlock;
    for (final pat in readerBlockPatterns) {
      final r = RegExp(pat, dotAll: true).firstMatch(html);
      if (r != null && r.group(1)!.length > 100) { readerBlock = r.group(1)!; break; }
    }
    final searchArea = readerBlock ?? html;

    final pages = <String>[];
    final dataSrcPattern = RegExp(r'''<img[^>]+data-src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)"[^>]*>''', caseSensitive: false);
    dataSrcPattern.allMatches(searchArea).forEach((m) {
      final url = m.group(1)!.trim();
      if (_isChapterImageURL(url) && !pages.contains(url)) pages.add(url);
    });
    if (pages.isEmpty) {
      final srcPattern = RegExp(r'''<img[^>]+src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)"[^>]*>''', caseSensitive: false);
      srcPattern.allMatches(searchArea).forEach((m) {
        final url = m.group(1)!.trim();
        if (_isChapterImageURL(url) && !pages.contains(url)) pages.add(url);
      });
    }
    if (pages.isEmpty) {
      final fallbackPattern = RegExp(r'''(?:data-src|src)="(https?://[^"]+/(?:manga|uploads|content|chapter)[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)"''', caseSensitive: false);
      fallbackPattern.allMatches(html).forEach((m) {
        final url = m.group(1)!.trim();
        if (_isChapterImageURL(url) && !pages.contains(url)) pages.add(url);
      });
    }
    return pages;
  }

  bool _isChapterImageURL(String url) {
    if (!url.startsWith('http') || url.contains('data:image')) return false;
    final lower = url.toLowerCase();
    const blocked = ['lekmanga.png', '-512.png', '/favicon', 'logo', 'banner', 'icon', 'avatar', 'gravatar', 'placeholder', 'ads', 'ad-'];
    if (blocked.any(lower.contains)) return false;
    return ['.jpg', '.jpeg', '.png', '.webp'].any(lower.contains);
  }

  String stripHTML(String html) => html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
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