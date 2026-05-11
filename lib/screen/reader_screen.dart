import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/manga_service.dart';
import '../services/download_manager.dart';

class ReaderScreen extends StatefulWidget {
  final Manga manga;
  final Chapter chapter;
  final List<Chapter> allChapters;
  final int initialPage;
  final List<String>? preloadedPages;
  final bool isOfflineMode;

  const ReaderScreen({
    super.key,
    required this.manga,
    required this.chapter,
    required this.allChapters,
    this.initialPage = 0,
    this.preloadedPages,
    this.isOfflineMode = false,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _service = MangaService();
  final _dm = DownloadManager.shared;

  List<_PageEntry> allPages = [];
  List<_Boundary>  boundaries = [];
  Set<String> loadedChapters = {};

  bool isLoading = true;
  bool loadingNext = false;
  String? error;
  bool showUI = true;
  int currentPage = 0;

  late PageController _pageCtrl;

  // ✅ OPT: Pre-cache المسافة (عدد الصفحات قبل وبعد)
  static const _preCacheDistance = 3;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: widget.initialPage);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadInitial();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() { isLoading = true; error = null; allPages = []; });
    try {
      List<String> urls = await _resolvePages(widget.manga.slug, widget.chapter.slug);
      if (!mounted) return;
      if (urls.isEmpty) throw Exception('No chapter images found');
      setState(() {
        allPages = urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
        boundaries = [_Boundary(widget.chapter.slug, 0)];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
        currentPage = widget.initialPage.clamp(0, allPages.length - 1);
      });
      // ✅ OPT: Pre-cache الصفحات الأولى فوراً
      _preCacheAround(currentPage);
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString().replaceAll('Exception: ', ''); isLoading = false; });
    }
  }

  Future<List<String>> _resolvePages(String mangaSlug, String chapterSlug) async {
    if (widget.preloadedPages?.isNotEmpty ?? false) return widget.preloadedPages!;
    final local = _dm.getPages(mangaSlug, chapterSlug);
    if (local != null) return local;
    if (widget.isOfflineMode) throw Exception('Chapter not available offline');
    return _service.fetchChapterPages(mangaSlug, chapterSlug)
        .timeout(const Duration(seconds: 45), onTimeout: () => throw Exception('Loading timeout — tap Retry'));
  }

  // ✅ OPT: Pre-cache صفحات مجاورة بشكل استباقي
  void _preCacheAround(int idx) {
    final start = (idx - 1).clamp(0, allPages.length - 1);
    final end   = (idx + _preCacheDistance).clamp(0, allPages.length - 1);
    for (int i = start; i <= end; i++) {
      final url = allPages[i].url;
      if (!url.startsWith('/')) { // skip local paths
        precacheImage(CachedNetworkImageProvider(url, headers: const {'Referer': 'https://lekmanga.site'}), context);
      }
    }
  }

  Future<void> _loadNextChapter() async {
    if (loadingNext) return;
    final autoLoad = context.read<AppState>().autoLoadNextChapter;
    if (!autoLoad) return;
    final lastSlug = boundaries.last.slug;
    final idx = widget.allChapters.indexWhere((c) => c.slug == lastSlug);
    if (idx < 0 || idx + 1 >= widget.allChapters.length) return;
    final next = widget.allChapters[idx + 1];
    if (loadedChapters.contains(next.slug)) return;

    setState(() => loadingNext = true);
    try {
      final urls = await _resolvePages(widget.manga.slug, next.slug)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        final startIdx = allPages.length;
        allPages.addAll(urls.map((u) => _PageEntry(next.slug, u)));
        boundaries.add(_Boundary(next.slug, startIdx));
        loadedChapters.add(next.slug);
        loadingNext = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingNext = false);
    }
  }

  void _onPageChanged(int idx) {
    if (currentPage == idx) return;
    setState(() => currentPage = idx);
    _saveProgress(idx);
    _preCacheAround(idx);
    if (idx >= allPages.length - 5) _loadNextChapter();
  }

  void _saveProgress(int pageIdx) {
    String slug = widget.chapter.slug;
    int boundaryStart = 0;
    for (final b in boundaries.reversed) {
      if (pageIdx >= b.startIndex) { slug = b.slug; boundaryStart = b.startIndex; break; }
    }
    final num = widget.allChapters.firstWhere((c) => c.slug == slug, orElse: () => widget.chapter).number;
    context.read<AppState>().saveProgress(ReadingProgress(
      mangaSlug: widget.manga.slug, mangaTitle: widget.manga.title,
      mangaCover: widget.manga.coverURL, chapterSlug: slug,
      chapterNumber: num, pageIndex: pageIdx - boundaryStart));
  }

  String get _currentChNum {
    for (final b in boundaries.reversed) {
      if (currentPage >= b.startIndex) {
        return widget.allChapters.firstWhere((c) => c.slug == b.slug, orElse: () => widget.chapter).number;
      }
    }
    return widget.chapter.number;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ─── Content ─────────────────────────────────────────────
        if (isLoading && allPages.isEmpty)
          _loadingView()
        else if (error != null && allPages.isEmpty)
          _errorView()
        else if (allPages.isEmpty)
          const Center(child: Text('No pages', style: TextStyle(color: Colors.white54)))
        else
          GestureDetector(
            onTap: () => setState(() => showUI = !showUI),
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: allPages.length + (loadingNext ? 1 : 0),
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) {
                if (i >= allPages.length) return const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2));
                if (boundaries.any((b) => b.startIndex == i) && i > 0) {
                  final num = widget.allChapters.firstWhere(
                    (c) => c.slug == boundaries.firstWhere((b) => b.startIndex == i).slug,
                    orElse: () => widget.chapter).number;
                  return _PageWithSeparator(url: allPages[i].url, chapterNumber: num);
                }
                return _ReaderPage(url: allPages[i].url);
              },
            ),
          ),

        // ─── Top bar ──────────────────────────────────────────────
        if (showUI && allPages.isNotEmpty)
          Positioned(top: 0, left: 0, right: 0, child: _topBar()),

        // ─── Close button (always on top) ─────────────────────────
        SafeArea(child: Align(alignment: Alignment.topLeft,
          child: Padding(padding: const EdgeInsets.only(top: 8, left: 8),
            child: _CloseButton(onTap: () => Navigator.pop(context))))),

        // ─── Bottom bar ───────────────────────────────────────────
        if (showUI && allPages.isNotEmpty)
          Positioned(bottom: 0, left: 0, right: 0, child: _bottomBar()),
      ]),
    );
  }

  Widget _topBar() => Container(
    padding: EdgeInsets.only(
      top: MediaQuery.of(context).padding.top + 8, left: 52, right: 16, bottom: 16),
    decoration: const BoxDecoration(gradient: LinearGradient(
      colors: [Colors.black87, Colors.transparent],
      begin: Alignment.topCenter, end: Alignment.bottomCenter)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.manga.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('Chapter $_currentChNum', style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ])),
      Text('${currentPage + 1} / ${allPages.length}',
        style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]),
  );

  Widget _bottomBar() => Container(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
    decoration: const BoxDecoration(gradient: LinearGradient(
      colors: [Colors.transparent, Colors.black54],
      begin: Alignment.topCenter, end: Alignment.bottomCenter)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ClipRRect(borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: allPages.isNotEmpty ? (currentPage + 1) / allPages.length : 0,
            backgroundColor: Colors.white12, color: AppTheme.accent, minHeight: 2))),
    ]),
  );

  Widget _loadingView() => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
    SizedBox(height: 16),
    Text('Loading chapter...', style: TextStyle(color: Colors.white54, fontSize: 13)),
  ]));

  Widget _errorView() => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 48),
      const SizedBox(height: 16),
      Text(error ?? 'Failed to load', style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(onPressed: _loadInitial, icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white)),
      const SizedBox(height: 12),
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Back', style: TextStyle(color: Colors.white54))),
    ])));
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: const Padding(padding: EdgeInsets.all(8),
        child: Icon(Icons.close, color: Colors.white, size: 22))));
}

class _ReaderPage extends StatelessWidget {
  final String url;
  const _ReaderPage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('/')) {
      return Image.file(
        File(url),
        width: double.infinity, fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => const _PageError());
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: const {'Referer': 'https://lekmanga.site'},
      width: double.infinity,
      fit: BoxFit.fitWidth,
      fadeInDuration: const Duration(milliseconds: 150),
      errorWidget: (_, __, ___) => const _PageError());
  }
}

class _PageWithSeparator extends StatelessWidget {
  final String url;
  final String chapterNumber;
  const _PageWithSeparator({required this.url, required this.chapterNumber});
  @override
  Widget build(BuildContext context) => Column(children: [
    _ChapterSeparator(number: chapterNumber),
    Expanded(child: _ReaderPage(url: url)),
  ]);
}

class _ChapterSeparator extends StatelessWidget {
  final String number;
  const _ChapterSeparator({required this.number});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [
      Expanded(child: Container(height: 1, color: Colors.white12)),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.accentDim,
          border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(20)),
        child: Text('Chapter $number',
          style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: Container(height: 1, color: Colors.white12)),
    ]),
  );
}

class _PageError extends StatelessWidget {
  const _PageError();
  @override
  Widget build(BuildContext context) => Container(
    height: 200, color: AppTheme.card,
    child: const Center(child: Icon(Icons.broken_image_outlined, color: AppTheme.textTertiary, size: 48)));
}

class _PageEntry { final String chapterSlug; final String url; _PageEntry(this.chapterSlug, this.url); }
class _Boundary  { final String slug; final int startIndex; _Boundary(this.slug, this.startIndex); }
