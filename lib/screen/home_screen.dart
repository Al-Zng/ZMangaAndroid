import 'package:flutter/material.dart';
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
  @override
  bool get wantKeepAlive => true;

  final _service = MangaService();
  List<Manga> latestManga = [];
  List<Manga> popularManga = [];
  bool isLoadingLatest = false;
  bool isLoadingPopular = false;
  int latestPage = 1;
  bool loadingMoreLatest = false;
  int _lastReloadTrigger = 0;

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
    final appState = context.read<AppState>();
    // فقط أعد التحميل إذا تغيّر العداد فعلاً
    if (appState.reloadTrigger != _lastReloadTrigger) {
      _lastReloadTrigger = appState.reloadTrigger;
      _loadLatest(reset: true);
      _loadPopular();
    }
  }

  Future<void> _loadInitial() async {
    final net = NetworkMonitor.shared;
    final store = context.read<AppState>();
    if (store.cachedLatest?.isNotEmpty ?? false) {
      latestManga = store.cachedLatest!;
    }
    if (store.cachedPopular?.isNotEmpty ?? false) {
      popularManga = store.cachedPopular!;
    }
    if (net.isConnected) {
      await Future.wait([_loadLatest(reset: false), _loadPopular()]);
    }
  }

  Future<void> _loadLatest({bool reset = false}) async {
    if (reset) {
      latestPage = 1;
      setState(() {
        latestManga = [];
        isLoadingLatest = true;
      });
    } else if (latestManga.isEmpty) {
      setState(() => isLoadingLatest = true);
    }
    try {
      final items = await _service.fetchLatest(page: latestPage);
      if (mounted) {
        setState(() {
          if (reset) latestManga = items;
          else latestManga.addAll(items);
          context.read<AppState>().saveCachedLatest(latestManga);
        });
      }
    } catch (e) {
      debugPrint('Error loading latest: $e');
    } finally {
      if (mounted) setState(() => isLoadingLatest = false);
    }
  }

  Future<void> _loadMoreLatest() async {
    if (loadingMoreLatest) return;
    setState(() => loadingMoreLatest = true);
    latestPage++;
    final old = List<Manga>.from(latestManga);
    try {
      final items = await _service.fetchLatest(page: latestPage);
      setState(() {
        latestManga = old + items;
        loadingMoreLatest = false;
        context.read<AppState>().saveCachedLatest(latestManga);
      });
    } catch (e) {
      setState(() => loadingMoreLatest = false);
    }
  }

  Future<void> _loadPopular() async {
    if (popularManga.isEmpty) setState(() => isLoadingPopular = true);
    try {
      final items = await _service.fetchPopular();
      if (mounted) {
        setState(() {
          popularManga = items;
          context.read<AppState>().saveCachedPopular(items);
        });
      }
    } catch (e) {
      debugPrint('Error loading popular: $e');
    } finally {
      if (mounted) setState(() => isLoadingPopular = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<AppState>();
    final net = context.watch<NetworkMonitor>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: !net.isConnected
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.wifi_off, size: 48, color: AppTheme.textTertiary),
                    SizedBox(height: 12),
                    Text('No Internet Connection',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () =>
                    _loadLatest(reset: true).then((_) => _loadPopular()),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _headerBar()),
                    if (store.history.isNotEmpty)
                      SliverToBoxAdapter(
                          child: _continueReadingSection(store)),
                    SliverToBoxAdapter(
                        child: _sectionLabel('POPULAR', Icons.local_fire_department)),
                    SliverToBoxAdapter(child: _popularSection()),
                    SliverToBoxAdapter(
                        child: _sectionLabel('LATEST UPDATES', Icons.bolt)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          if (i < latestManga.length) {
                            return _latestRow(latestManga[i]);
                          } else if (loadingMoreLatest) {
                            return const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator()));
                          }
                          return null;
                        },
                        childCount:
                            latestManga.length + (loadingMoreLatest ? 1 : 0),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _headerBar() => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.book, color: AppTheme.accent, size: 22),
            const SizedBox(width: 6),
            const Text('ZManga',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      );

  Widget _sectionLabel(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 12),
        child: Row(children: [
          Icon(icon, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1.5)),
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
              itemCount:
                  store.history.length > 10 ? 10 : store.history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final p = store.history[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MangaDetailScreen(
                            slug: p.mangaSlug,
                            preloadTitle: p.mangaTitle)),
                  ),
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
                itemCount:
                    popularManga.length > 20 ? 20 : popularManga.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final m = popularManga[i];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MangaDetailScreen(
                              slug: m.slug,
                              preloadTitle: m.title,
                              preloadCover: m.coverURL)),
                    ),
                    child: _PopularCard(manga: m),
                  );
                },
              ),
      );

  Widget _latestRow(Manga manga) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MangaDetailScreen(
                    slug: manga.slug,
                    preloadTitle: manga.title,
                    preloadCover: manga.coverURL)),
          ),
          child: Container(
            decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border, width: 1)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  Hero(
                    tag: 'manga_${manga.slug}',
                    child: CachedMangaImage(
                        url: manga.highQualityCoverURL,
                        width: 90,
                        height: 125,
                        fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        if (manga.latestChapterNumber.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('Chapter ${manga.latestChapterNumber}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accent)),
                          ),
                        const SizedBox(height: 4),
                        if (manga.lastUpdated.isNotEmpty)
                          Text(manga.lastUpdated,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
                  const SizedBox(width: 12),
                ],
              ),
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
      decoration:
          BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedMangaImage(url: progress.mangaCover)),
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
                Text(progress.mangaTitle,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    maxLines: 2),
                Row(children: [
                  const Icon(Icons.book,
                      size: 8, color: AppTheme.accentBright),
                  const SizedBox(width: 4),
                  Text(
                      'Ch.${progress.chapterNumber} · p.${progress.pageIndex + 1}',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.accentBright)),
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
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedMangaImage(
                  url: manga.highQualityCoverURL,
                  width: 120,
                  height: 168)),
          const SizedBox(height: 6),
          Text(manga.title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary),
              maxLines: 2),
        ],
      ),
    );
  }
}