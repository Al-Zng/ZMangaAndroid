import 'dart:async';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:flutter/foundation.dart';
import '../core/network/http_service.dart';
import '../core/cloudflare/cloudflare_service.dart';
import '../models/models.dart';
import '../state/app_state.dart';

class MangaService {
  static const String baseURL = 'https://lekmanga.site';
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  final HttpService _http = HttpService();
  final CloudflareService _cf = CloudflareService();

  Future<String> fetchHTML(String urlString, {int retryCount = 0}) async {
    try {
      final response = await _http.get(urlString);
      final body = response.data.toString();

      if (_cf.isCloudflareResponse(response.statusCode ?? 0, body)) {
        if (retryCount >= 1) throw Exception('Cloudflare challenge failed');
        
        final appState = AppState.current;
        if (appState != null) {
          final solved = await appState.triggerCloudflare(urlString);
          if (solved) {
            return fetchHTML(urlString, retryCount: retryCount + 1);
          }
        }
        throw Exception('Cloudflare challenge not solved');
      }

      return body;
    } on DioException catch (e) {
      if (e.response != null && _cf.isCloudflareResponse(e.response!.statusCode ?? 0, e.response!.data.toString())) {
        if (retryCount >= 1) throw Exception('Cloudflare challenge failed');
        final appState = AppState.current;
        if (appState != null) {
          final solved = await appState.triggerCloudflare(urlString);
          if (solved) {
            return fetchHTML(urlString, retryCount: retryCount + 1);
          }
        }
      }
      throw Exception('Network error: ${e.message}');
    }
  }

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
    final html = await fetchHTML('$baseURL/?s=$encoded&post_type=wp-manga&page=$page');
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<List<Manga>> fetchByGenre(String genre, {int page = 1}) async {
    final html = await fetchHTML('$baseURL/manga-genre/$genre/?page=$page');
    return _parseMangaList(html, extractChapterInfo: false);
  }

  Future<Manga> fetchDetail(String slug) async {
    final html = await fetchHTML('$baseURL/manga/$slug/');
    return _parseMangaDetail(html, slug);
  }

  Future<List<String>> fetchChapterPages(String mangaSlug, String chapterSlug) async {
    final urlString = '$baseURL/manga/$mangaSlug/$chapterSlug/';
    final html = await fetchHTML(urlString);
    
    // Try AJAX first as in iOS
    final chapterIdPattern = r'data-id="(\d+)"';
    final match = RegExp(chapterIdPattern).firstMatch(html);
    if (match != null) {
      final chapterId = match.group(1)!;
      final ajaxPages = await _fetchChapterImagesViaAJAX(chapterId);
      if (ajaxPages.isNotEmpty) return ajaxPages;
    }

    return _parseChapterPages(html);
  }

  Future<List<String>> _fetchChapterImagesViaAJAX(String chapterId) async {
    try {
      final response = await _http.post(
        '$baseURL/wp-admin/admin-ajax.php',
        data: {
          'action': 'manga_get_chapter_img_list',
          'chapter_id': chapterId,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data.map((e) => e['url'] as String).toList();
        } else if (data is Map && data['data'] != null && data['data']['images'] != null) {
          return (data['data']['images'] as List).map((e) => e['url'] as String).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  List<Manga> _parseMangaList(String html, {required bool extractChapterInfo}) {
    final document = parse(html);
    final items = document.querySelectorAll('.page-item-detail');
    final results = <Manga>[];

    for (var item in items) {
      final titleElement = item.querySelector('.post-title h3 a');
      final imgElement = item.querySelector('img');
      final link = titleElement?.attributes['href'];
      
      if (titleElement != null && link != null) {
        final title = titleElement.text.trim();
        final slug = link.split('/').where((s) => s.isNotEmpty).last;
        final coverURL = imgElement?.attributes['data-src'] ?? imgElement?.attributes['src'] ?? '';

        results.add(Manga(
          title: title,
          slug: slug,
          coverURL: coverURL,
        ));
      }
    }
    return results;
  }

  Manga _parseMangaDetail(String html, String slug) {
    final document = parse(html);
    final title = document.querySelector('.post-title h1')?.text.trim() ?? '';
    final coverURL = document.querySelector('.summary_image img')?.attributes['data-src'] ?? 
                     document.querySelector('.summary_image img')?.attributes['src'] ?? '';
    final description = document.querySelector('.description-summary')?.text.trim() ?? '';
    
    final chapters = <Chapter>[];
    final chapterElements = document.querySelectorAll('.wp-manga-chapter');
    for (var element in chapterElements) {
      final linkElement = element.querySelector('a');
      final name = linkElement?.text.trim() ?? '';
      final url = linkElement?.attributes['href'] ?? '';
      final chapterSlug = url.split('/').where((s) => s.isNotEmpty).last;
      
      if (name.isNotEmpty && chapterSlug.isNotEmpty) {
        chapters.add(Chapter(name: name, slug: chapterSlug));
      }
    }

    return Manga(
      title: title,
      slug: slug,
      coverURL: coverURL,
      description: description,
      chapters: chapters,
    );
  }

  List<String> _parseChapterPages(String html) {
    final document = parse(html);
    final images = document.querySelectorAll('.reading-content img');
    return images
        .map((e) => e.attributes['data-src'] ?? e.attributes['src'] ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
