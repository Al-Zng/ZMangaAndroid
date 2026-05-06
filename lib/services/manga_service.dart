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

  // ------ جلب HTML عبر http (للقوائم والتفاصيل) ------
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
      // لا نرمي استثناء لئلا نكسر التدفق
      return '';
    }
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to load: ${response.statusCode}');
    }
  }

  // ------ جلب صفحات الفصول عبر WebView (مثل iOS تماماً) ------
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
            // انتظر قليلاً ليتم تحميل الصور البطيئة
            await Future.delayed(const Duration(seconds: 2));
            final html = await controller.runJavaScriptReturningResult(
              'document.documentElement.outerHTML',
            ) as String? ?? '';

            if (html.isEmpty) return;

            if (html.contains('Just a moment') ||
                html.contains('Attention Required') ||
                html.contains('Checking your browser')) {
              // Cloudflare لا يزال موجوداً -> نُظهر النافذة
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

  // ------ دوال الجلب العامة ------
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

  // ------ صور الفصل (باستخدام WebView) ------
  Future<List<String>> fetchChapterPages(String mangaSlug, String chapterSlug) async {
    final url = '$baseURL/manga/$mangaSlug/$chapterSlug/';
    final html = await fetchChapterHTMLViaWebView(url);
    return _parseChapterPages(html);
  }

  // ========== دوال تحليل HTML (مقتبسة من مشروع iOS) ==========
  // ... نفس دوال _parseMangaList, _parseMangaCard, _parseMangaSimple,
  //     _parseMangaDetail, _parseChapterPages كما في الردود السابقة ...
  // (لن أكررها لتوفير المساحة، ولكنها موجودة في النسخة الكاملة السابقة)
}