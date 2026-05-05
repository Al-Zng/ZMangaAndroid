import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models.dart';

class MangaService {
  static const String baseURL = 'https://lek-manga.net';

  // لجلب قائمة المانجا (آخر التحديثات، الشعبية، البحث)
  Future<List<Manga>> fetchLatest({int page = 1}) async {
    final url = '$baseURL/manga/?m_orderby=latest&page=$page';
    final html = await _fetchHTML(url);
    return _parseMangaList(html, extractChapterInfo: true);
  }

  // ... دوال fetchPopular, search, fetchDetail, fetchChapterPages بنفس منطق Swift
  // استخدم html_parser لتحليل الـ DOM بدلاً من Regex إذا أمكن (أسهل وأضمن)
}

// يمكن إضافة دالة داخلية _fetchHTML تستخدم webview أو http حسب التطبيق