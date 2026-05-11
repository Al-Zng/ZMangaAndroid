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
import '../core/network/platform_cookie_bridge.dart';
import '../core/network/user_agent.dart';

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

  // ✅ FIX READER NAV: ScrollController بدل PageController — تمرير حر بدون snap
  // مطابق لـ iOS: ScrollView(.vertical) + LazyVStack
  late final ScrollController _scrollCtrl;

  // GlobalKey لكل صفحة — لتتبع الصفحة الحالية بدقة عبر موضع العنصر في الشاشة
  final List<GlobalKey> _pageKeys = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _scrollCtrl.addListener(_onScroll);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── تتبع الصفحة الحالية عند التمرير ────────────────────────────
  // نفحص أي عنصر يقع منتصفه في منتصف الشاشة — مطابق لـ iOS's GeometryReader
  void _onScroll() {
    if (!mounted || _pageKeys.isEmpty) return;
    final screenMidY = MediaQuery.sizeOf(context).height / 2;

    // نبحث في نافذة محدودة حول الصفحة الحالية لتحسين الأداء
    final start = (currentPage - 4).clamp(0, _pageKeys.length - 1);
    final end   = (currentPage + 6).clamp(0, _pageKeys.length - 1);

    for (int i = start; i <= end; i++) {
      final ctx = _pageKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top    = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (top <= screenMidY && bottom > screenMidY) {
        if (currentPage != i) {
          currentPage = i;
          _saveProgress(i);
          _preCacheAround(i);
          if (i >= allPages.length - 5) _loadNextChapter();
          if (mounted) setState(() {}); // تحديث العداد وشريط التقدم فقط
        }
        return;
      }
    }
  }

  Future<void> _loadInitial() async {
    setState(() { isLoading = true; error = null; allPages = []; _pageKeys.clear(); });
    try {
      final urls = await _resolvePages(widget.manga.slug, widget.chapter.slug);
      if (!mounted) return;
      if (urls.isEmpty) throw Exception('No chapter images found');
      final entries = urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
      setState(() {
        allPages = entries;
        boundaries = [_Boundary(widget.chapter.slug, 0)];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
        currentPage = widget.initialPage.clamp(0, allPages.length - 1);
        // إنشاء GlobalKey لكل صفحة
        _pageKeys.addAll(List.generate(allPages.length, (_) => GlobalKey()));
      });

      // ✅ التمرير للصفحة الأولى بعد البناء
      if (widget.initialPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPage(widget.initialPage));
      }
      _preCacheAround(currentPage);
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString().replaceAll('Exception: ', ''); isLoading = false; });
    }
  }

  // التمرير التلقائي لصفحة معينة (للصفحة الأولى عند بدء القراءة)
  void _scrollToPage(int pageIdx) {
    if (pageIdx <= 0 || pageIdx >= _pageKeys.length) return;
    final ctx = _pageKeys[pageIdx].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
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

  // ✅ OPT: Pre-cache الصفحات المجاورة — نمرر الـ Referer الديناميكي
  void _preCacheAround(int idx) {
    const distance = 3;
    final start = (idx - 1).clamp(0, allPages.length - 1);
    final end   = (idx + distance).clamp(0, allPages.length - 1);
    for (int i = start; i <= end; i++) {
      final url = allPages[i].url;
      if (!url.startsWith('/')) {
        precacheImage(
          CachedNetworkImageProvider(
            url,
            headers: {'Referer': _ReaderPageImage._refererFor(url)},
          ),
          context,
        );
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
        // ✅ نضيف GlobalKey للصفحات الجديدة
        _pageKeys.addAll(List.generate(urls.length, (_) => GlobalKey()));
      });
    } catch (_) {
      if (mounted) setState(() => loadingNext = false);
    }
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
          // ✅ FIX READER NAV: ListView.builder بدل PageView — تمرير حر بدون snap
          // مطابق تماماً لـ iOS: ScrollView(.vertical) + LazyVStack(spacing: 0)
          GestureDetector(
            onTap: () => setState(() => showUI = !showUI),
            child: ListView.builder(
              controller: _scrollCtrl,
              scrollDirection: Axis.vertical,
              physics: const BouncingScrollPhysics(), // iOS-like bounce
              padding: EdgeInsets.zero,
              itemCount: allPages.length + (loadingNext ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= allPages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)),
                  );
                }

                // فاصل بين الفصول
                Widget pageWidget;
                if (boundaries.any((b) => b.startIndex == i) && i > 0) {
                  final boundary = boundaries.firstWhere((b) => b.startIndex == i);
                  final num = widget.allChapters.firstWhere(
                    (c) => c.slug == boundary.slug,
                    orElse: () => widget.chapter).number;
                  pageWidget = Column(mainAxisSize: MainAxisSize.min, children: [
                    _ChapterSeparator(number: num),
                    _ReaderPageImage(url: allPages[i].url),
                  ]);
                } else {
                  pageWidget = _ReaderPageImage(url: allPages[i].url);
                }

                // نلف كل عنصر بـ KeyedSubtree لتتبع موضعه في الشاشة
                return KeyedSubtree(key: _pageKeys[i], child: pageWidget);
              },
            ),
          ),

        // ─── Top bar ──────────────────────────────────────────────
        if (showUI && allPages.isNotEmpty)
          Positioned(top: 0, left: 0, right: 0, child: _topBar()),

        // ─── زر الإغلاق (دائماً في الأعلى) ───────────────────────
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
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ClipRRect(borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: allPages.isNotEmpty ? (currentPage + 1) / allPages.length : 0,
          backgroundColor: Colors.white12, color: AppTheme.accent, minHeight: 2))),
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

// ✅ FIX PLACEHOLDER: صورة الفصل مع كوكيز Android WebView + Referer ديناميكي
// مطابق لـ iOS: CachedAsyncImage التي تقرأ WKWebsiteDataStore cookies وتضبط
// الـ Referer بناءً على domain الصورة (s3.lekmanga.com → Referer: lekmanga.com)
class _ReaderPageImage extends StatefulWidget {
  final String url;
  const _ReaderPageImage({super.key, required this.url});

  // Referer ديناميكي — يطابق domain الصورة بدلاً من إرسال lekmanga.site دائماً
  // iOS: let mainDomain = components.suffix(2).joined(separator: ".")
  static String _refererFor(String url) {
    try {
      final uri = Uri.parse(url);
      final parts = uri.host.split('.');
      if (parts.length >= 2) {
        return 'https://${parts.sublist(parts.length - 2).join('.')}/';
      }
      return 'https://lekmanga.site/';
    } catch (_) {
      return 'https://lekmanga.site/';
    }
  }

  @override
  State<_ReaderPageImage> createState() => _ReaderPageImageState();
}

class _ReaderPageImageState extends State<_ReaderPageImage> {
  // نبني الـ headers مرة واحدة فقط عند init
  late final Future<Map<String, String>> _headersFuture;

  @override
  void initState() {
    super.initState();
    _headersFuture = _buildHeaders();
  }

  Future<Map<String, String>> _buildHeaders() async {
    // نقرأ كوكيز Android CookieManager (بما فيها cf_clearance) — مطابق iOS
    final cookies = await PlatformCookieBridge.getMergedCookiesForUrl(widget.url);
    final referer = _ReaderPageImage._refererFor(widget.url);
    return {
      'Referer': referer,
      'User-Agent': AppUserAgent.androidChrome,
      if (cookies.isNotEmpty) 'Cookie': cookies,
    };
  }

  @override
  Widget build(BuildContext context) {
    // صورة محلية (تحميل مسبق offline)
    if (widget.url.startsWith('/')) {
      return Image.file(
        File(widget.url),
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => const _PageError(),
      );
    }

    return FutureBuilder<Map<String, String>>(
      future: _headersFuture,
      builder: (ctx, snap) {
        // بمجرد اكتمال الـ headers نبدأ تحميل الصورة
        // الـ Future سريع جداً (< 10ms) لأنه مجرد MethodChannel محلي
        if (!snap.hasData) {
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.6,
            child: const Center(
              child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            ),
          );
        }
        return CachedNetworkImage(
          imageUrl: widget.url,
          httpHeaders: snap.data!,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          fadeInDuration: const Duration(milliseconds: 150),
          // placeholder حتى يتم التحميل
          placeholder: (_, __) => SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.6,
            child: const Center(
              child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => const _PageError(),
        );
      },
    );
  }
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
