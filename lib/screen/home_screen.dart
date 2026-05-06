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
    _loadLatest(reset: true);
    _loadPopular();
  }

  Future<void> _loadInitial() async {
    final net = NetworkMonitor.shared;
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
      setState(() {
        if (reset) latestManga = items;
        else latestManga.addAll(items);
        isLoadingLatest = false;
        context.read<AppState>().saveCachedLatest(latestManga);
      });
    } catch (e) {
      setState(() => isLoadingLatest = false);
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
      setState(() {
        popularManga = items;
        isLoadingPopular = false;
        context.read<AppState>().saveCachedPopular(items);
      });
    } catch (e) {
      setState(() => isLoadingPopular = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    final net = context.watch<NetworkMonitor>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('ZManga', style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: !net.isConnected
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.wifi_off, size: 48, color: AppTheme.textTertiary),
                  SizedBox(height: 12),
                  Text('No Internet Connection', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadLatest(reset: true).then((_) => _loadPopular()),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (store.history.isNotEmpty) ...[
                            _sectionLabel('CONTINUE READING', Icons.schedule),
                            SizedBox(
                              height: 180,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: store.history.length > 10 ? 10 : store.history.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (_, i) {
                                  final p = store.history[i];
                                  return GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MangaDetailScreen(
                                          slug: p.mangaSlug,
                                          preloadTitle: p.mangaTitle,
                                        ),
                                      ),
                                    ),
                                    child: _ContinueReadingCard(progress: p),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          _sectionLabel('POPULAR', Icons.local_fire_department),
                          SizedBox(
                            height: 190,
                            child: isLoadingPopular && popularManga.isEmpty
                                ? const Center(child: CircularProgressIndicator())
                                : ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: popularManga.length > 20 ? 20 : popularManga.length,
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
                                              preloadCover: m.coverURL,
                                            ),
                                          ),
                                        ),
                                        child: _PopularCard(manga: m),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 24),
                          _sectionLabel('LATEST UPDATES', Icons.bolt),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i < latestManga.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MangaDetailScreen(
                                    slug: latestManga[i].slug,
                                    preloadTitle: latestManga[i].title,
                                    preloadCover: latestManga[i].coverURL,
                                  ),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.card,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedMangaImage(
                                        url: latestManga[i].highQualityCoverURL,
                                        width: 80,
                                        height: 110,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            latestManga[i].title,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                            maxLines: 2,
                                          ),
                                          if (latestManga[i].latestChapterNumber != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Chapter ${latestManga[i].latestChapterNumber}',
                                              style: const TextStyle(
                                                color: AppTheme.accent,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          if (latestManga[i].lastUpdated != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              latestManga[i].lastUpdated!,
                                              style: const TextStyle(
                                                color: AppTheme.textTertiary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else if (loadingMoreLatest) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return null;
                      },
                      childCount: latestManga.length + (loadingMoreLatest ? 1 : 0),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 14, color: AppTheme.accent),
      const SizedBox(width: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    ]);
  }
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedMangaImage(url: progress.mangaCover),
          ),
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
                Text(
                  progress.mangaTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                ),
                Row(children: [
                  const Icon(Icons.book, size: 8, color: AppTheme.accentBright),
                  const SizedBox(width: 4),
                  Text(
                    'Ch.${progress.chapterNumber} · p.${progress.pageIndex + 1}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.accentBright),
                  ),
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
              height: 168,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manga.title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}