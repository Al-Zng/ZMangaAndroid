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

  // ✅ FIX: وضع الأجهزة الضعيفة — يُستدعى من AppState
  bool get _lowEnd => context.read<AppState>().lowEndMode;
  bool get _autoLoad => context.read<AppState>().autoLoadNextChapter;

  // ✅ للريدر البسيط (وضع الأجهزة الضعيفة)
  final _scrollController = ScrollController();
  late Chapter _currentChapter;
  bool _loadingPrevNext = false;

  @override
  void initState() {
    super.initState();
    currentChapterSlug = widget.chapter.slug;
    _currentChapter = widget.chapter;
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      isLoading = true;
      error = null;
      allPages = [];
    });
    try {
      List<String> urls;
      if (widget.preloadedPages != null && widget.preloadedPages!.isNotEmpty) {
        urls = widget.preloadedPages!;
      } else {
        final localPages =
            _dm.getPages(widget.manga.slug, widget.chapter.slug);
        if (localPages != null) {
          urls = localPages;
        } else if (widget.isOfflineMode) {
          throw Exception('Not available offline');
        } else {
          // ✅ FIX: timeout 45 ثانية لمنع الـ loading اللا متناهي
          urls = await _service
              .fetchChapterPages(widget.manga.slug, widget.chapter.slug)
              .timeout(const Duration(seconds: 45),
                  onTimeout: () =>
                      throw Exception('Loading timeout — tap Retry'));
        }
      }

      if (urls.isEmpty) {
        throw Exception('No chapter images found');
      }

      totalPages = urls.length;

      setState(() {
        allPages = urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
        chapterBoundaries = [_ChapterBoundary(widget.chapter.slug, 0)];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
        loadingProgress = 1.0;
        loadedPagesCount = totalPages;
        currentPage = widget.initialPage.clamp(0, allPages.length - 1);
      });
    } catch (e) {
      setState(() {
        error = e.toString().replaceAll('Exception: ', '');
        isLoading = false;
        allPages = [];
      });
    }
  }

  // ─── تحميل الفصل التالي (وضع الأجهزة العادية فقط) ─────────────
  Future<void> _loadNextChapter() async {
    if (loadingNext || chapterBoundaries.isEmpty) return;
    if (!_autoLoad) return;
    final lastLoaded = chapterBoundaries.last.slug;
    final idx =
        widget.allChapters.indexWhere((c) => c.slug == lastLoaded);
    if (idx < 0 || idx + 1 >= widget.allChapters.length) return;
    final next = widget.allChapters[idx + 1];
    if (loadedChapters.contains(next.slug)) return;
    setState(() => loadingNext = true);
    try {
      List<String> urls;
      final localPages = _dm.getPages(widget.manga.slug, next.slug);
      if (localPages != null) {
        urls = localPages;
      } else if (widget.isOfflineMode) {
        setState(() => loadingNext = false);
        return;
      } else {
        urls = await _service
            .fetchChapterPages(widget.manga.slug, next.slug)
            .timeout(const Duration(seconds: 30));
      }
      if (urls.isEmpty) {
        setState(() => loadingNext = false);
        return;
      }
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
    if (!_lowEnd && idx >= allPages.length - 5) _loadNextChapter();
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

  // ─── وضع الأجهزة الضعيفة: تنقل بين الفصول ──────────────────────
  int get _currentChapterIndex =>
      widget.allChapters.indexWhere((c) => c.slug == _currentChapter.slug);

  bool get _hasPrevChapter => _currentChapterIndex > 0;
  bool get _hasNextChapter =>
      _currentChapterIndex >= 0 &&
      _currentChapterIndex < widget.allChapters.length - 1;

  Future<void> _goToChapter(Chapter ch) async {
    setState(() => _loadingPrevNext = true);
    _currentChapter = ch;
    currentChapterSlug = ch.slug;
    try {
      List<String> urls;
      final localPages = _dm.getPages(widget.manga.slug, ch.slug);
      if (localPages != null) {
        urls = localPages;
      } else {
        urls = await _service
            .fetchChapterPages(widget.manga.slug, ch.slug)
            .timeout(const Duration(seconds: 40),
                onTimeout: () => throw Exception('Loading timeout'));
      }
      setState(() {
        allPages = urls.map((u) => _PageEntry(ch.slug, u)).toList();
        chapterBoundaries = [_ChapterBoundary(ch.slug, 0)];
        loadedChapters = {ch.slug};
        currentPage = 0;
        totalPages = urls.length;
        _loadingPrevNext = false;
      });
      // scroll للأعلى
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (e) {
      setState(() => _loadingPrevNext = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowEnd = context.watch<AppState>().lowEndMode;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ─── المحتوى الرئيسي ────────────────────────────────────
          if (isLoading && allPages.isEmpty)
            _loadingView()
          else if (error != null && allPages.isEmpty)
            _errorView()
          else if (allPages.isEmpty)
            const Center(
                child: Text('No pages',
                    style: TextStyle(color: Colors.white54)))
          else if (lowEnd)
            // ✅ FIX: وضع الأجهزة الضعيفة — ListView بسيط بدون PageView
            _lowEndReader()
          else
            // وضع الأجهزة العادية — PageView كالمعتاد
            GestureDetector(
              onTap: _toggleUI,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: allPages.length + (loadingNext ? 1 : 0),
                controller: PageController(initialPage: widget.initialPage),
                onPageChanged: _updateCurrentPage,
                itemBuilder: (_, idx) {
                  if (idx < allPages.length) {
                    if (chapterBoundaries.any((b) => b.startIndex == idx) &&
                        idx > 0) {
                      final b = chapterBoundaries
                          .firstWhere((b) => b.startIndex == idx);
                      final num = widget.manga.chapters
                          .firstWhere((c) => c.slug == b.slug,
                              orElse: () => widget.chapter)
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

          // ─── الشريط العلوي ──────────────────────────────────────
          if (showUI && !isLoading && allPages.isNotEmpty) _topBar(),

          // ✅ FIX: زر الإغلاق يجب أن يكون بعد _topBar() في Stack
          //    حتى يُرسم فوقه ولا يُحجب به
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: _closeButton(),
              ),
            ),
          ),

          // ─── الشريط السفلي ──────────────────────────────────────
          if (showUI && !isLoading && allPages.isNotEmpty)
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: lowEnd ? _lowEndBottomBar() : _bottomBar()),
        ],
      ),
    );
  }

  // ✅ FIX: زر الإغلاق مع خلفية معتمة للوضوح
  Widget _closeButton() => Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ),
      );

  // ─── وضع الأجهزة الضعيفة ─────────────────────────────────────────
  Widget _lowEndReader() {
    if (_loadingPrevNext) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    return GestureDetector(
      onTap: _toggleUI,
      child: ListView.builder(
        controller: _scrollController,
        // ✅ cacheExtent صغير لتوفير الذاكرة
        cacheExtent: 200,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemCount: allPages.length,
        itemBuilder: (_, idx) {
          _updateCurrentPage(idx);
          return CachedMangaImage(
              url: allPages[idx].url, fit: BoxFit.fitWidth);
        },
      ),
    );
  }

  Widget _lowEndBottomBar() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black87],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 8,
            top: 12,
            left: 16,
            right: 16),
        child: Row(
          children: [
            // ─── الفصل السابق
            _navButton(
              icon: Icons.skip_previous,
              label: 'Previous',
              enabled: _hasPrevChapter && !_loadingPrevNext,
              onTap: _hasPrevChapter
                  ? () => _goToChapter(
                      widget.allChapters[_currentChapterIndex - 1])
                  : null,
            ),
            const Spacer(),
            // ─── رقم الفصل الحالي
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ch. ${_currentChapter.number}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                Text(
                  '${currentPage + 1} / ${allPages.length}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const Spacer(),
            // ─── الفصل التالي
            _navButton(
              icon: Icons.skip_next,
              label: 'Next',
              enabled: _hasNextChapter && !_loadingPrevNext,
              onTap: _hasNextChapter
                  ? () => _goToChapter(
                      widget.allChapters[_currentChapterIndex + 1])
                  : null,
            ),
          ],
        ),
      );

  Widget _navButton({
    required IconData icon,
    required String label,
    required bool enabled,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color:
                  enabled ? AppTheme.accent : Colors.white12,
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: enabled ? Colors.white : Colors.white30, size: 18),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: enabled ? Colors.white : Colors.white30,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  // ─── UI المشترك ───────────────────────────────────────────────────
  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            if (totalPages > 0) ...[
              LinearProgressIndicator(
                  value: loadingProgress, color: AppTheme.accent),
              const SizedBox(height: 8),
              Text('$loadedPagesCount / $totalPages pages',
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ] else
              const Text('Loading chapter...',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, color: AppTheme.danger, size: 48),
              const SizedBox(height: 16),
              Text(
                error ?? 'Failed to load chapter',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      );

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

  Widget _topBar() => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 52, // ✅ مسافة للزر X (48px) + padding
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
                            color: Colors.white54, fontSize: 12)),
                  ]),
            ),
            Text('${currentPage + 1} / ${allPages.length}',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      );

  Widget _bottomBar() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${currentPage + 1} / ${allPages.length}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ),
          ),
          Container(
            height: 2,
            child: LinearProgressIndicator(
              value: allPages.isNotEmpty
                  ? (currentPage + 1) / allPages.length
                  : 0,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.accent),
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
