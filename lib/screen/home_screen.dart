import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import 'manga_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = MangaService();
  List<Manga> latestManga = [];
  List<Manga> popularManga = [];
  bool isLoadingLatest = false;
  bool isLoadingPopular = false;
  int latestPage = 1;
  bool loadingMoreLatest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadInitial();
      context.read<AppState>().addListener(_onReloadTrigger);
    });
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_onReloadTrigger);
    super.dispose();
  }

  void _onReloadTrigger() {
    // عندما triggerReload يُستدعى (بعد غلق Cloudflare)، نُعيد تحميل القوائم
    loadLatest(reset: true);
    loadPopular();
  }

  Future<void> loadInitial() async {
    await Future.wait([loadLatest(reset: false), loadPopular()]);
  }

  Future<void> loadLatest({bool reset = false}) async {
    if (reset) {
      latestPage = 1;
      setState(() { latestManga = []; isLoadingLatest = true; });
    } else if (latestManga.isEmpty) {
      setState(() => isLoadingLatest = true);
    }
    try {
      final items = await _service.fetchLatest(page: latestPage);
      setState(() {
        if (reset) latestManga = items; else latestManga.addAll(items);
        isLoadingLatest = false;
      });
    } catch (e) {
      setState(() => isLoadingLatest = false);
    }
  }

  Future<void> loadMoreLatest() async {
    if (loadingMoreLatest) return;
    setState(() => loadingMoreLatest = true);
    latestPage++;
    final old = List<Manga>.from(latestManga);
    try {
      final items = await _service.fetchLatest(page: latestPage);
      setState(() {
        latestManga = old + items;
        loadingMoreLatest = false;
      });
    } catch (e) {
      setState(() => loadingMoreLatest = false);
    }
  }

  Future<void> loadPopular() async {
    if (popularManga.isEmpty) setState(() => isLoadingPopular = true);
    try {
      final items = await _service.fetchPopular();
      setState(() {
        popularManga = items;
        isLoadingPopular = false;
      });
    } catch (e) {
      setState(() => isLoadingPopular = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: ZTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => loadLatest(reset: true).then((_) => loadPopular()),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _headerBar()),
              if (store.history.isNotEmpty)
                SliverToBoxAdapter(child: _continueReadingSection(store)),
              SliverToBoxAdapter(child: _sectionLabel('POPULAR', Icons.local_fire_department)),
              SliverToBoxAdapter(child: _popularSection()),
              SliverToBoxAdapter(child: _sectionLabel('LATEST UPDATES', Icons.bolt)),
              SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (i < latestManga.length) {
                    return _latestRow(latestManga[i]);
                  } else if (loadingMoreLatest) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                  }
                  return null;
                },
                childCount: latestManga.length + (loadingMoreLatest ? 1 : 0),
              )),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.book, color: ZTheme.accent, size: 22),
            const SizedBox(width: 6),
            Text('ZManga', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: ZTheme.textPrimary)),
          ],
        ),
      );

  Widget _sectionLabel(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 12),
        child: Row(children: [
          Icon(icon, size: 14, color: ZTheme.accent),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ZTheme.textSecondary, letterSpacing: 1.5)),
        ]),
      );

  Widget _continueReadingSection(AppState store) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('CONTINUE READING', Icons.schedule),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: store.history.length > 10 ? 10 : store.history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final p = store.history[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: p.mangaSlug, preloadTitle: p.mangaTitle))),
                  child: _ContinueReadingCard(progress: p),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      );

  Widget _popularSection() => SizedBox(
        height: 190,
        child: isLoadingPopular && popularManga.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: popularManga.length > 20 ? 20 : popularManga.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final m = popularManga[i];
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: m.slug, preloadTitle: m.title, preloadCover: m.coverURL))),
                    child: _PopularCard(manga: m),
                  );
                },
              ),
      );

  Widget _latestRow(Manga manga) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL))),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ZTheme.card, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: manga.highQualityCoverURL, width: 80, height: 110)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(manga.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ZTheme.textPrimary), maxLines: 2),
                      if (manga.latestChapterNumber != null) ...[
                        const SizedBox(height: 4),
                        Text('Chapter ${manga.latestChapterNumber}', style: const TextStyle(color: ZTheme.accent, fontSize: 12)),
                      ],
                      if (manga.lastUpdated != null) ...[
                        const SizedBox(height: 2),
                        Text(manga.lastUpdated!, style: const TextStyle(color: ZTheme.textTertiary, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZTheme.textTertiary),
              ],
            ),
          ),
        ),
      );
}

class _ContinueReadingCard extends StatelessWidget {
  final ReadingProgress progress;
  const _ContinueReadingCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 164,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: progress.mangaCover)),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(progress.mangaTitle, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 2),
                Row(children: [
                  const Icon(Icons.book, size: 8, color: ZTheme.accentBright),
                  const SizedBox(width: 4),
                  Text('Ch.${progress.chapterNumber} · p.${progress.pageIndex + 1}', style: const TextStyle(fontSize: 10, color: ZTheme.accentBright)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  final Manga manga;
  const _PopularCard({required this.manga});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: manga.highQualityCoverURL, width: 120, height: 168)),
          const SizedBox(height: 6),
          Text(manga.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ZTheme.textPrimary), maxLines: 2),
        ],
      ),
    );
  }
}