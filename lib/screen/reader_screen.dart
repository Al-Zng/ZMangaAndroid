import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import '../services/download_manager.dart';

class ReaderScreen extends StatefulWidget {
  final Manga manga;
  final Chapter chapter;
  final List<Chapter> allChapters;
  final int initialPage;
  final List<String>? preloadedPages;

  const ReaderScreen({
    Key? key,
    required this.manga,
    required this.chapter,
    required this.allChapters,
    this.initialPage = 0,
    this.preloadedPages,
  }) : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _service = MangaService();
  List<_PageEntry> allPages = [];
  List<_ChapterBoundary> chapterBoundaries = [];
  Set<String> loadedChapters = {};
  bool isLoading = true;
  double loadingProgress = 0;
  int loadedPagesCount = 0;
  int totalPages = 0;
  bool loadingNext = false;
  String? error;
  bool showUI = true;
  late String currentChapterSlug;
  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    currentChapterSlug = widget.chapter.slug;
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      List<String> urls;
      if (widget.preloadedPages != null) {
        urls = widget.preloadedPages!;
      } else {
        final localPages =
            DownloadManager.shared.getPages(widget.manga.slug, widget.chapter.slug);
        if (localPages != null) {
          urls = localPages;
        } else {
          urls = await _service.fetchChapterPages(widget.manga.slug, widget.chapter.slug);
        }
      }
      totalPages = urls.length;
      // محاكاة تحميل اختياري
      for (int i = 0; i < urls.length; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
        setState(() {
          loadedPagesCount = i + 1;
          loadingProgress = loadedPagesCount / totalPages;
        });
      }
      setState(() {
        allPages = urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
        chapterBoundaries = [_ChapterBoundary(widget.chapter.slug, 0)];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
        currentPage = widget.initialPage.clamp(0, allPages.length - 1);
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadNextChapter() async {
    if (loadingNext || chapterBoundaries.isEmpty) return;
    final lastLoaded = chapterBoundaries.last.slug;
    final idx = widget.allChapters.indexWhere((c) => c.slug == lastLoaded);
    if (idx < 0 || idx + 1 >= widget.allChapters.length) return;
    final next = widget.allChapters[idx + 1];
    if (loadedChapters.contains(next.slug)) return;
    setState(() => loadingNext = true);
    try {
      final urls = await _service.fetchChapterPages(widget.manga.slug, next.slug);
      setState(() {
        final startIdx = allPages.length;
        allPages.addAll(urls.map((u) => _PageEntry(next.slug, u)));
        chapterBoundaries.add(_ChapterBoundary(next.slug, startIdx));
        loadedChapters.add(next.slug);
        loadingNext = false;
      });
    } catch (e) {
      setState(() => loadingNext = false);
    }
  }

  void _updateCurrentPage(int idx) {
    if (currentPage == idx) return;
    setState(() => currentPage = idx);
    _saveProgress(idx);
    if (idx >= allPages.length - 5) _loadNextChapter();
  }

  void _saveProgress(int pageIdx) {
    String chSlug = widget.chapter.slug;
    int boundaryStart = 0;
    for (final b in chapterBoundaries.reversed) {
      if (pageIdx >= b.startIndex) {
        chSlug = b.slug;
        boundaryStart = b.startIndex;
        break;
      }
    }
    final chNum = widget.manga.chapters
        .firstWhere((c) => c.slug == chSlug, orElse: () => widget.chapter)
        .number;
    final localIdx = pageIdx - boundaryStart;
    final progress = ReadingProgress(
      mangaSlug: widget.manga.slug,
      mangaTitle: widget.manga.title,
      mangaCover: widget.manga.coverURL,
      chapterSlug: chSlug,
      chapterNumber: chNum,
      pageIndex: localIdx,
    );
    context.read<AppState>().saveProgress(progress);
  }

  void _toggleUI() => setState(() => showUI = !showUI);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isLoading && allPages.isEmpty)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: AppTheme.accent),
                const SizedBox(height: 16),
                if (totalPages > 0)
                  Column(children: [
                    LinearProgressIndicator(value: loadingProgress, color: AppTheme.accent),
                    const SizedBox(height: 8),
                    Text('$loadedPagesCount / $totalPages pages',
                        style: const TextStyle(color: AppTheme.textSecondary)),
                  ]),
              ]),
            )
          else if (error != null)
            Center(child: Text(error!, style: const TextStyle(color: Colors.white54)))
          else if (allPages.isEmpty)
            const Center(child: Text('No pages', style: TextStyle(color: Colors.white54)))
          else
            GestureDetector(
              onTap: _toggleUI,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: allPages.length + (loadingNext ? 1 : 0),
                controller: PageController(initialPage: widget.initialPage),
                onPageChanged: _updateCurrentPage,
                itemBuilder: (_, idx) {
                  if (idx < allPages.length) {
                    if (chapterBoundaries.any((b) => b.startIndex == idx) && idx > 0) {
                      final num = widget.manga.chapters
                          .firstWhere((c) =>
                              c.slug ==
                              chapterBoundaries
                                  .firstWhere((b) => b.startIndex == idx)
                                  .slug)
                          .number;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _chapterSeparator(num),
                          Expanded(child: _pageItem(idx)),
                        ],
                      );
                    }
                    return _pageItem(idx);
                  }
                  return const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent));
                },
              ),
            ),
          // شريط علوي
          if (showUI && !isLoading && allPages.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 48,
                    right: 16,
                    bottom: 14),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.black87, Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter)),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.manga.title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          Text('Chapter $_currentChNum',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ]),
                  ),
                  Text('${currentPage + 1} / ${allPages.length}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
          // زر الإغلاق
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _currentChNum {
    for (final b in chapterBoundaries.reversed) {
      if (currentPage >= b.startIndex) {
        return widget.manga.chapters
            .firstWhere((c) => c.slug == b.slug, orElse: () => widget.chapter)
            .number;
      }
    }
    return widget.chapter.number;
  }

  Widget _pageItem(int idx) =>
      CachedMangaImage(url: allPages[idx].url, fit: BoxFit.fitWidth);

  Widget _chapterSeparator(String number) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: Colors.white12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(20)),
            child: Text('Chapter $number',
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Container(height: 1, color: Colors.white12)),
        ]),
      );
}

class _PageEntry {
  final String chapterSlug;
  final String url;
  _PageEntry(this.chapterSlug, this.url);
}

class _ChapterBoundary {
  final String slug;
  final int startIndex;
  _ChapterBoundary(this.slug, this.startIndex);
}