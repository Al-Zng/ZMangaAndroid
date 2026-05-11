import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import '../utils/network_monitor.dart';
import 'manga_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final _service = MangaService();
  List<Manga> latestManga = [];
  List<Manga> popularManga = [];
  bool isLoadingLatest = false;
  bool isLoadingPopular = false;
  bool hasLoadError = false;
  int latestPage = 1;
  bool loadingMoreLatest = false;
  int _lastReloadTrigger = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastReloadTrigger = context.read<AppState>().reloadTrigger;
      _loadInitial();
      context.read<AppState>().addListener(_onReloadTrigger);
    });
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_onReloadTrigger);
    super.dispose();
  }

  void _onReloadTrigger() {
    final t = context.read<AppState>().reloadTrigger;
    if (t != _lastReloadTrigger) { _lastReloadTrigger = t; _loadLatest(reset: true); _loadPopular(); }
  }

  Future<void> _loadInitial() async {
    final store = context.read<AppState>();
    final net = NetworkMonitor.shared;
    if (store.cachedLatest?.isNotEmpty ?? false) setState(() => latestManga = store.cachedLatest!);
    if (store.cachedPopular?.isNotEmpty ?? false) setState(() => popularManga = store.cachedPopular!);
    if (net.isConnected) await Future.wait([_loadLatest(reset: false), _loadPopular()]);
  }

  Future<void> _loadLatest({bool reset = false}) async {
    if (reset) { latestPage = 1; setState(() { latestManga = []; isLoadingLatest = true; }); }
    else if (latestManga.isEmpty) setState(() => isLoadingLatest = true);
    try {
      final items = await _service.fetchLatest(page: latestPage);
      if (!mounted) return;
      setState(() {
        if (reset) latestManga = items; else latestManga.addAll(items);
        isLoadingLatest = false; hasLoadError = false;
      });
      context.read<AppState>().saveCachedLatest(List.from(latestManga));
    } catch (e) {
      if (!mounted) return;
      setState(() { isLoadingLatest = false; if (latestManga.isEmpty) hasLoadError = true; });
    }
  }

  Future<void> _loadMoreLatest() async {
    if (loadingMoreLatest) return;
    setState(() => loadingMoreLatest = true);
    latestPage++;
    final old = List<Manga>.from(latestManga);
    try {
      final items = await _service.fetchLatest(page: latestPage);
      if (!mounted) return;
      setState(() { latestManga = old + items; loadingMoreLatest = false; });
      context.read<AppState>().saveCachedLatest(List.from(latestManga));
    } catch (e) {
      if (!mounted) return;
      setState(() { latestManga = old; loadingMoreLatest = false; });
    }
  }

  Future<void> _loadPopular() async {
    if (popularManga.isEmpty) setState(() => isLoadingPopular = true);
    try {
      final items = await _service.fetchPopular();
      if (!mounted) return;
      setState(() { popularManga = items; isLoadingPopular = false; });
      context.read<AppState>().saveCachedPopular(items);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoadingPopular = false);
    }
  }

  void _openManga(Manga m) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => MangaDetailScreen(slug: m.slug, preloadTitle: m.title, preloadCover: m.coverURL)));

  void _openProgress(ReadingProgress p) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => MangaDetailScreen(slug: p.mangaSlug, preloadTitle: p.mangaTitle, preloadCover: p.mangaCover)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<AppState>();
    final net = context.watch<NetworkMonitor>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: !net.isConnected
            ? _offlineView()
            : RefreshIndicator(
                color: AppTheme.accent,
                backgroundColor: AppTheme.surface,
                onRefresh: () => Future.wait([_loadLatest(reset: true), _loadPopular()]),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollEndNotification && n.metrics.extentAfter < 300 && !loadingMoreLatest) _loadMoreLatest();
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      // ─── Header ────────────────────────────────
                      SliverToBoxAdapter(child: _headerBar()),

                      // ─── Continue Reading ───────────────────────
                      if (store.history.isNotEmpty)
                        SliverToBoxAdapter(child: _section('CONTINUE READING', Icons.schedule_outlined, _continueReading(store))),

                      // ─── Popular ───────────────────────────────
                      SliverToBoxAdapter(child: _section('POPULAR', Icons.local_fire_department_outlined, _popular())),

                      // ─── Latest Updates ─────────────────────────
                      SliverToBoxAdapter(child: _sectionLabel('LATEST UPDATES', Icons.bolt_outlined)),

                      if (isLoadingLatest && latestManga.isEmpty)
                        SliverList(delegate: SliverChildBuilderDelegate(
                          (_, i) => const _SkeletonLatestRow(), childCount: 6))
                      else if (hasLoadError && latestManga.isEmpty)
                        SliverToBoxAdapter(child: _errorView())
                      else
                        SliverList(delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            if (i < latestManga.length) return _latestRow(latestManga[i]);
                            if (loadingMoreLatest) return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)));
                            return null;
                          },
                          childCount: latestManga.length + (loadingMoreLatest ? 1 : 0),
                        )),

                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _headerBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
    child: Row(children: [
      const Icon(Icons.menu_book_rounded, color: AppTheme.accent, size: 22),
      const SizedBox(width: 6),
      Text('ZManga', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    ]),
  );

  Widget _sectionLabel(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(left: 20, bottom: 12, top: 4),
    child: Row(children: [
      Icon(icon, size: 13, color: AppTheme.accent),
      const SizedBox(width: 6),
      Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 1.5)),
    ]),
  );

  Widget _section(String title, IconData icon, Widget content) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_sectionLabel(title, icon), content, const SizedBox(height: 24)],
  );

  Widget _continueReading(AppState store) => SizedBox(
    height: 180,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: store.history.length.clamp(0, 10),
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => _openProgress(store.history[i]),
        child: _ContinueReadingCard(progress: store.history[i]),
      ),
    ),
  );

  Widget _popular() => SizedBox(
    height: 205,
    child: isLoadingPopular && popularManga.isEmpty
        ? ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 6, separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) => const _SkeletonPopularCard())
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: popularManga.length.clamp(0, 20),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openManga(popularManga[i]),
              child: _PopularCard(manga: popularManga[i]))),
  );

  Widget _latestRow(Manga m) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: GestureDetector(
      onTap: () => _openManga(m),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10),
            child: CachedMangaImage(url: m.highQualityCoverURL, width: 72, height: 100)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 2),
            if (m.latestChapterNumber != null) ...[ const SizedBox(height: 5),
              Text('Chapter ${m.latestChapterNumber}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.accent))],
            if (m.lastUpdated != null) ...[ const SizedBox(height: 2),
              Text(m.lastUpdated!, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary))],
          ])),
          const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
        ]),
      ),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
      const Icon(Icons.cloud_off, size: 48, color: AppTheme.textTertiary),
      const SizedBox(height: 12),
      const Text('Failed to load content', style: TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: () { setState(() => hasLoadError = false); _loadLatest(reset: true); _loadPopular(); },
        icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white)),
    ])),
  );

  Widget _offlineView() => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.wifi_off, size: 48, color: AppTheme.textTertiary),
    SizedBox(height: 12),
    Text('No Internet Connection', style: TextStyle(color: AppTheme.textSecondary)),
  ]));
}

// ─── Cards ────────────────────────────────────────────────────────────────────
class _ContinueReadingCard extends StatelessWidget {
  final ReadingProgress progress;
  const _ContinueReadingCard({required this.progress});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116, height: 164,
    child: Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(12),
        child: CachedMangaImage(url: progress.mangaCover)),
      Container(decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.95)]))),
      Positioned(bottom: 0, left: 0, right: 0, child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(progress.mangaTitle,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 2),
          Row(children: [
            const Icon(Icons.auto_stories, size: 8, color: AppTheme.accentBright),
            const SizedBox(width: 4),
            Text('Ch.${progress.chapterNumber} · p.${progress.pageIndex + 1}',
              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.accentBright)),
          ]),
        ]),
      )),
    ]),
  );
}

class _PopularCard extends StatelessWidget {
  final Manga manga;
  const _PopularCard({required this.manga});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(12),
        child: CachedMangaImage(url: manga.highQualityCoverURL, width: 120, height: 168)),
      const SizedBox(height: 6),
      Text(manga.title,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textPrimary), maxLines: 2),
    ]),
  );
}

// ─── Skeleton (shimmer loading) ───────────────────────────────────────────────
class _SkeletonPopularCard extends StatefulWidget {
  const _SkeletonPopularCard();
  @override
  State<_SkeletonPopularCard> createState() => _SkeletonPopularCardState();
}
class _SkeletonPopularCardState extends State<_SkeletonPopularCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 120, height: 180,
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(_anim.value - 1, 0), end: Alignment(_anim.value, 0),
            colors: [AppTheme.card, AppTheme.surface, AppTheme.card],
          ).createShader(rect),
          child: Container(color: Colors.white),
        )),
    ),
  );
}

class _SkeletonLatestRow extends StatefulWidget {
  const _SkeletonLatestRow();
  @override
  State<_SkeletonLatestRow> createState() => _SkeletonLatestRowState();
}
class _SkeletonLatestRowState extends State<_SkeletonLatestRow> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final shimmer = LinearGradient(
        begin: Alignment(_anim.value - 1, 0), end: Alignment(_anim.value, 0),
        colors: [AppTheme.card, AppTheme.surface, AppTheme.card]);
      Widget skel(double w, double h) => Container(
        width: w, height: h, margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: shimmer));
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(width: 72, height: 100, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10), gradient: shimmer)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              skel(double.infinity, 14), skel(140, 12), skel(80, 11),
            ])),
          ]),
        ),
      );
    },
  );
}
