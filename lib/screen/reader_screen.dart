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

  // إعدادات القارئ
  bool autoLoadNextChapter = true;
  bool tapToScrollEnabled = false;
  bool zoomEnabled = false;
  bool optimizationEnabled = false;
  bool preloadNextChapter = false;
  bool keepScreenOn = false;
  bool reduceMotion = false;

  @override
  void initState() {
    super.initState();
    currentChapterSlug = widget.chapter.slug;
    _loadSettings();
    _loadInitial();
  }

  void _loadSettings() {
    // يمكن ربطها بـ SharedPreferences لاحقاً
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
            _dm.getPages(widget.manga.slug, widget.chapter.slug);
        if (localPages != null) {
          urls = localPages;
        } else if (widget.isOfflineMode) {
          throw Exception('Not available offline');
        } else {
          urls = await _service.fetchChapterPages(
              widget.manga.slug, widget.chapter.slug);
        }
      }
      totalPages = urls.length;
      // محاكاة تحميل سريعة
      for (int i = 0; i < urls.length && i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
        setState(() {
          loadedPagesCount = i + 1;
          loadingProgress = loadedPagesCount / totalPages;
        });
      }
      if (urls.isEmpty) {
        throw Exception('No images found for this chapter');
      }
      setState(() {
        allPages =
            urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
        chapterBoundaries = [
          _ChapterBoundary(widget.chapter.slug, 0)
        ];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
        currentPage =
            widget.initialPage.clamp(0, allPages.length - 1);
        loadedPagesCount = totalPages;
        loadingProgress = 1.0;
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
    if (!autoLoadNextChapter) return;
    final lastLoaded = chapterBoundaries.last.slug;
    final idx =
        widget.allChapters.indexWhere((c) => c.slug == lastLoaded);
    if (idx < 0 || idx + 1 >= widget.allChapters.length) return;
    final next = widget.allChapters[idx + 1];
    if (loadedChapters.contains(next.slug)) return;
    setState(() => loadingNext = true);
    try {
      List<String> urls;
      final localPages =
          _dm.getPages(widget.manga.slug, next.slug);
      if (localPages != null) {
        urls = localPages;
      } else if (widget.isOfflineMode) {
        setState(() => loadingNext = false);
        return;
      } else {
        urls = await _service.fetchChapterPages(
            widget.manga.slug, next.slug);
      }
      setState(() {
        final startIdx = allPages.length;
        allPages
            .addAll(urls.map((u) => _PageEntry(next.slug, u)));
        chapterBoundaries
            .add(_ChapterBoundary(next.slug, startIdx));
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
        .firstWhere((c) => c.slug == chSlug,
            orElse: () => widget.chapter)
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

  String get currentChNum {
    for (final b in chapterBoundaries.reversed) {
      if (currentPage >= b.startIndex) {
        return widget.manga.chapters
            .firstWhere((c) => c.slug == b.slug,
                orElse: () => widget.chapter)
            .number;
      }
    }
    return widget.chapter.number;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isLoading && allPages.isEmpty)
            _loadingView()
          else if (error != null && allPages.isEmpty)
            _errorView()
          else if (allPages.isEmpty)
            const Center(
                child: Text('No pages',
                    style: TextStyle(color: Colors.white54)))
          else
            GestureDetector(
              onTap: _handleTap,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount:
                    allPages.length + (loadingNext ? 1 : 0),
                controller: PageController(
                    initialPage: widget.initialPage),
                onPageChanged: _updateCurrentPage,
                itemBuilder: (_, idx) {
                  if (idx < allPages.length) {
                    if (chapterBoundaries
                            .any((b) => b.startIndex == idx) &&
                        idx > 0) {
                      final num = widget.manga.chapters
                          .firstWhere((c) =>
                              c.slug ==
                              chapterBoundaries
                                  .firstWhere(
                                      (b) => b.startIndex == idx)
                                  .slug)
                          .number;
                      return Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          _chapterSeparator(num),
                          Expanded(child: _pageItem(idx)),
                        ],
                      );
                    }
                    return _pageItem(idx);
                  }
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accent));
                },
              ),
            ),
          // زر الإغلاق
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          // الشريط العلوي
          if (showUI && !isLoading && allPages.isNotEmpty)
            _topBar(),
          // الشريط السفلي
          if (showUI && !isLoading && allPages.isNotEmpty)
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _bottomBar()),
        ],
      ),
    );
  }

  void _handleTap() {
    if (tapToScrollEnabled && currentPage < allPages.length - 1) {
      // انتقل للصفحة التالية
      setState(() => currentPage = currentPage + 1);
    } else {
      _toggleUI();
    }
  }

  Widget _loadingView() => Center(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: AppTheme.accent),
              const SizedBox(height: 16),
              if (totalPages > 0) ...[
                LinearProgressIndicator(
                    value: loadingProgress,
                    color: AppTheme.accent),
                const SizedBox(height: 8),
                Text('$loadedPagesCount / $totalPages pages',
                    style: const TextStyle(
                        color: AppTheme.textSecondary)),
              ],
            ]),
      );

  Widget _errorView() => Center(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber,
                  color: AppTheme.danger, size: 44),
              const SizedBox(height: 12),
              Text(error!,
                  style:
                      const TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _loadInitial,
                  child: const Text('Retry')),
            ]),
      );

  Widget _pageItem(int idx) =>
      CachedMangaImage(url: allPages[idx].url, fit: BoxFit.fitWidth);

  Widget _chapterSeparator(String number) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          Expanded(
              child: Container(
                  height: 1, color: Colors.white12)),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                border: Border.all(
                    color: AppTheme.accent.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(20)),
            child: Text('Chapter $number',
                style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
              child: Container(
                  height: 1, color: Colors.white12)),
        ]),
      );

  Widget _topBar() => Positioned(
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
                    Text('Chapter $currentChNum',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12)),
                  ]),
            ),
            Text('${currentPage + 1} / ${allPages.length}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ]),
        ),
      );

  Widget _bottomBar() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // زر الصفحة الحالية
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                  '${currentPage + 1} / ${allPages.length}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ),
          ),
          // شريط التقدم
          Container(
            height: 2,
            child: LinearProgressIndicator(
              value: allPages.isNotEmpty
                  ? (currentPage + 1) / allPages.length
                  : 0,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.accent),
            ),
          ),
          const SizedBox(height: 20),
        ],
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