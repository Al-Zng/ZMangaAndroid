import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final String slug;
  final String preloadTitle;
  final String preloadCover;
  const MangaDetailScreen({Key? key, required this.slug, this.preloadTitle = '', this.preloadCover = ''}) : super(key: key);

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  final _service = MangaService();
  Manga? manga;
  bool isLoading = true;
  String? error;
  bool chapterSortAsc = false;
  bool showChapterError = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() { isLoading = true; error = null; });
    try {
      final m = await _service.fetchDetail(widget.slug);
      setState(() { manga = m; isLoading = false; });
    } catch (e) {
      setState(() { isLoading = false; error = e.toString(); });
    }
  }

  List<Chapter> get sortedChapters {
    if (manga == null) return [];
    final list = List<Chapter>.from(manga!.chapters);
    list.sort((a, b) {
      final na = double.tryParse(a.number) ?? 0;
      final nb = double.tryParse(b.number) ?? 0;
      return chapterSortAsc ? na.compareTo(nb) : nb.compareTo(na);
    });
    return list;
  }

  Chapter? get firstChapter {
    if (manga == null || manga!.chapters.isEmpty) return null;
    return manga!.chapters.reduce((a, b) => (double.tryParse(a.number) ?? 0) < (double.tryParse(b.number) ?? 0) ? a : b);
  }

  void _startReading() {
    if (manga == null || manga!.chapters.isEmpty) {
      setState(() => showChapterError = true);
      return;
    }
    Chapter target;
    final progress = context.read<AppState>().history.firstWhere(
      (p) => p.mangaSlug == widget.slug,
      orElse: () => ReadingProgress(mangaSlug: '', mangaTitle: '', mangaCover: '', chapterSlug: '', chapterNumber: '', pageIndex: 0),
    );
    if (progress.mangaSlug.isNotEmpty) {
      final found = manga!.chapters.firstWhere((c) => c.slug == progress.chapterSlug, orElse: () => firstChapter!);
      target = found;
    } else {
      target = firstChapter!;
    }
    _openReader(target);
  }

  void _openReader(Chapter ch) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(manga: manga!, chapter: ch, allChapters: sortedChapters)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: ZTheme.bg,
      appBar: AppBar(
        backgroundColor: ZTheme.surface,
        title: Text(manga?.title ?? widget.preloadTitle, style: const TextStyle(color: ZTheme.textPrimary, fontSize: 16)),
        actions: [
          if (manga != null)
            IconButton(
              icon: Icon(store.isInLibrary(manga!) ? Icons.favorite : Icons.favorite_border,
                  color: store.isInLibrary(manga!) ? ZTheme.accent : ZTheme.textSecondary),
              onPressed: () => store.isInLibrary(manga!) ? store.removeFromLibrary(manga!) : store.addToLibrary(manga!),
            ),
        ],
      ),
      body: isLoading ? _loadingState() : error != null ? _errorState() : _content(manga!, store),
    );
  }

  Widget _loadingState() => Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 110, height: 155, decoration: BoxDecoration(color: ZTheme.card, borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.preloadTitle.isEmpty ? 'Loading...' : widget.preloadTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ZTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Container(height: 12, width: double.infinity, color: ZTheme.card),
                  const SizedBox(height: 6),
                  Container(height: 12, width: 80, color: ZTheme.card),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: ZTheme.danger),
          const SizedBox(height: 12),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: ZTheme.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loadDetail, child: const Text('Retry')),
        ]),
      );

  Widget _content(Manga m, AppState store) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroSection(m, store),
          const Divider(color: ZTheme.border, height: 1),
          const SizedBox(height: 16),
          if (m.description.isNotEmpty) ...[
            _description(m.description),
            const Divider(color: ZTheme.border, height: 1),
            const SizedBox(height: 16),
          ],
          _chaptersHeader(m.chapters.length),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedChapters.length,
            separatorBuilder: (_, __) => const Divider(color: ZTheme.border, indent: 16),
            itemBuilder: (_, i) {
              final ch = sortedChapters[i];
              final progress = store.history.firstWhere(
                (p) => p.mangaSlug == m.slug && p.chapterSlug == ch.slug,
                orElse: () => ReadingProgress(mangaSlug: '', mangaTitle: '', mangaCover: '', chapterSlug: '', chapterNumber: '', pageIndex: 0),
              );
              return _chapterTile(ch, progress);
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _heroSection(Manga m, AppState store) {
    final cover = m.highQualityCoverURL;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: cover, width: 110, height: 155)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ZTheme.textPrimary), maxLines: 3),
                if (m.author.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(m.author, style: const TextStyle(color: ZTheme.textSecondary, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [
                    if (m.status.isNotEmpty) _statusBadge(m.status),
                    if (m.rating.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 12, color: ZTheme.accent),
                        const SizedBox(width: 3),
                        Text(m.rating, style: const TextStyle(color: ZTheme.textSecondary, fontSize: 12)),
                      ]),
                  ],
                ),
                if (m.genres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5, runSpacing: 5,
                    children: m.genres.map((g) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: ZTheme.accentDim, borderRadius: BorderRadius.circular(20)),
                      child: Text(g, style: const TextStyle(color: ZTheme.accent, fontSize: 10)),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                if (firstChapter != null)
                  _readingButton(store, firstChapter!)
                else
                  const Text('No chapters available', style: TextStyle(color: ZTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readingButton(AppState store, Chapter firstChap) {
    final hasProgress = store.history.any((p) => p.mangaSlug == widget.slug);
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: ZTheme.accent, foregroundColor: ZTheme.bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      icon: const Icon(Icons.play_arrow, size: 16),
      label: Text(hasProgress ? 'Continue' : 'Start Reading', style: const TextStyle(fontWeight: FontWeight.w600)),
      onPressed: _startReading,
    );
  }

  Widget _description(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SYNOPSIS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ZTheme.textSecondary, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: ZTheme.textSecondary, fontSize: 14, height: 1.4)),
          ],
        ),
      );

  Widget _chaptersHeader(int count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Text('$count CHAPTERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ZTheme.textSecondary, letterSpacing: 2)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => chapterSortAsc = !chapterSortAsc),
              child: Row(children: [
                Icon(chapterSortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: ZTheme.textSecondary),
                const SizedBox(width: 4),
                Text(chapterSortAsc ? 'Oldest' : 'Newest', style: const TextStyle(color: ZTheme.textSecondary, fontSize: 12)),
              ]),
            ),
          ],
        ),
      );

  Widget _chapterTile(Chapter ch, ReadingProgress progress) => InkWell(
        onTap: () => _openReader(ch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Chapter ${ch.number}', style: TextStyle(color: progress.mangaSlug.isNotEmpty ? ZTheme.textTertiary : ZTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
                      if (progress.mangaSlug.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('· p.${progress.pageIndex + 1}', style: const TextStyle(color: ZTheme.accent, fontSize: 12)),
                      ],
                    ]),
                    if (ch.date.isNotEmpty) Text(ch.date, style: const TextStyle(color: ZTheme.textTertiary, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ZTheme.textTertiary, size: 16),
            ],
          ),
        ),
      );

  Widget _statusBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: text.toLowerCase().contains('ongoing') ? const Color(0xFF4CAF82).withOpacity(0.12) : ZTheme.textTertiary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
            color: text.toLowerCase().contains('ongoing') ? const Color(0xFF4CAF82) : ZTheme.textTertiary)),
      );
}