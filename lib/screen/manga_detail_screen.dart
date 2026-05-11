import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import '../services/download_manager.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final String slug;
  final String preloadTitle;
  final String preloadCover;

  const MangaDetailScreen({super.key, required this.slug, this.preloadTitle = '', this.preloadCover = ''});

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  final _service = MangaService();
  Manga? manga;
  bool isLoading = true;
  String? error;
  bool sortAsc = false;
  bool multiSelect = false;
  final Set<String> selected = {};

  List<Chapter> get sorted {
    if (manga == null) return [];
    final list = List<Chapter>.from(manga!.chapters);
    list.sort((a, b) {
      final na = double.tryParse(a.number) ?? 0;
      final nb = double.tryParse(b.number) ?? 0;
      return sortAsc ? na.compareTo(nb) : nb.compareTo(na);
    });
    return list;
  }

  Chapter? get _firstChapter {
    if (manga == null || manga!.chapters.isEmpty) return null;
    return manga!.chapters.reduce((a, b) =>
        (double.tryParse(a.number) ?? 0) < (double.tryParse(b.number) ?? 0) ? a : b);
  }

  @override
  void initState() { super.initState(); _loadDetail(); }

  Future<void> _loadDetail() async {
    setState(() { isLoading = true; error = null; });
    try {
      final cached = context.read<AppState>().mangaCache[widget.slug];
      if (cached != null) {
        setState(() { manga = cached; isLoading = false; });
        // تحديث في الخلفية بصمت
        _service.fetchDetail(widget.slug).then((m) {
          if (mounted) { setState(() => manga = m); context.read<AppState>().cacheManga(m); }
        }).catchError((_) {});
        return;
      }
      final m = await _service.fetchDetail(widget.slug)
          .timeout(const Duration(seconds: 45), onTimeout: () => throw Exception('Loading timeout — tap Retry'));
      if (!mounted) return;
      setState(() { manga = m; isLoading = false; });
      context.read<AppState>().cacheManga(m);
    } catch (e) {
      if (!mounted) return;
      setState(() { isLoading = false; error = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  void _openReader(Chapter ch) => Navigator.push(context, MaterialPageRoute(
    builder: (_) => ReaderScreen(manga: manga!, chapter: ch, allChapters: sorted)));

  void _startReading() {
    if (manga == null || manga!.chapters.isEmpty) return;
    final progress = context.read<AppState>().history.firstWhere(
      (p) => p.mangaSlug == widget.slug, orElse: () => ReadingProgress(
        mangaSlug: '', mangaTitle: '', mangaCover: '', chapterSlug: '', chapterNumber: '', pageIndex: 0));
    final ch = progress.mangaSlug.isNotEmpty
        ? manga!.chapters.firstWhere((c) => c.slug == progress.chapterSlug, orElse: () => _firstChapter!)
        : _firstChapter!;
    _openReader(ch);
  }

  void _onLongPress(Chapter ch) {
    final dm = DownloadManager.shared;
    final isDl = dm.isDownloaded(manga!.slug, ch.slug);
    final isIng = dm.isDownloading(manga!.slug, ch.slug);

    showModalBottomSheet(context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('Chapter ${ch.number}', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16))),
          const Divider(color: AppTheme.border, height: 1),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined, color: AppTheme.textSecondary),
            title: Text('Read', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15)),
            onTap: () { Navigator.pop(context); _openReader(ch); }),
          if (isDl)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: Text('Delete Download', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 15)),
              onTap: () { Navigator.pop(context); dm.deleteChapter(manga!.slug, ch.slug); setState(() {}); })
          else if (isIng)
            ListTile(
              leading: const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)),
              title: Text('Downloading...', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)))
          else
            ListTile(
              leading: const Icon(Icons.download_outlined, color: AppTheme.accent),
              title: Text('Download Chapter', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15)),
              onTap: () { Navigator.pop(context); _downloadSingle(ch); }),
          ListTile(
            leading: const Icon(Icons.checklist_outlined, color: AppTheme.textSecondary),
            title: Text('Select Chapters', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15)),
            onTap: () { Navigator.pop(context); setState(() { multiSelect = true; selected.add(ch.slug); }); }),
        ],
      ))));
  }

  Future<void> _downloadSingle(Chapter ch) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Downloading Chapter ${ch.number}...'),
      duration: const Duration(seconds: 2), backgroundColor: AppTheme.surface));
    await DownloadManager.shared.downloadChapter(manga: manga!, chapter: ch);
    if (mounted) setState(() {});
  }

  Future<void> _downloadSelected() async {
    final chs = manga!.chapters.where((c) => selected.contains(c.slug)).toList();
    selected.clear(); setState(() => multiSelect = false);
    await DownloadManager.shared.addMultipleToQueue(manga: manga!, chapters: chs);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    // ✅ OPT: نستخدم context.watch على DownloadManager مباشرة
    final dm = context.watch<DownloadManager>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textSecondary),
          onPressed: () => Navigator.pop(context)),
        title: Text(manga?.title ?? widget.preloadTitle,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (manga != null) ...[
            IconButton(
              icon: Icon(store.isInLibrary(manga!) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: store.isInLibrary(manga!) ? AppTheme.accent : AppTheme.textSecondary),
              onPressed: () => store.isInLibrary(manga!)
                  ? store.removeFromLibrary(manga!) : store.addToLibrary(manga!)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
              color: AppTheme.surface,
              onSelected: (v) {
                if (v == 'want') store.isWantToRead(manga!) ? store.removeWantToRead(manga!) : store.addWantToRead(manga!);
                else if (v == 'done') store.isCompleted(manga!) ? store.removeCompleted(manga!) : store.addCompleted(manga!);
                else if (v == 'select') setState(() { multiSelect = !multiSelect; if (!multiSelect) selected.clear(); });
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'want', child: Text(store.isWantToRead(manga!) ? 'Remove Want to Read' : 'Want to Read')),
                PopupMenuItem(value: 'done', child: Text(store.isCompleted(manga!)  ? 'Mark Uncompleted'   : 'Mark Completed')),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'select', child: Text(multiSelect ? 'Cancel Selection' : 'Select Chapters')),
              ],
            ),
          ],
        ],
      ),
      body: isLoading ? _loadingView()
          : error != null ? _errorView()
          : _body(store, dm),
    );
  }

  Widget _loadingView() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 110, height: 155, decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.preloadTitle.isEmpty ? 'Loading...' : widget.preloadTitle,
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Container(height: 12, width: 120, decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(4))),
      ])),
    ])),
    const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)),
  ]);

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 40, color: AppTheme.danger),
    const SizedBox(height: 12),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(error!, style: GoogleFonts.inter(color: AppTheme.textSecondary), textAlign: TextAlign.center)),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _loadDetail,
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
      child: const Text('Retry')),
  ]));

  Widget _body(AppState store, DownloadManager dm) {
    final m = manga!;
    final chapters = sorted;
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ─── Header ───────────────────────────────────────────────────
      Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: CachedMangaImage(url: m.highQualityCoverURL, width: 110, height: 155)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          if (m.author.isNotEmpty) ...[const SizedBox(height: 4),
            Text(m.author, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary))],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (m.status.isNotEmpty) _statusBadge(m.status),
            if (m.rating.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 13, color: AppTheme.accent),
              const SizedBox(width: 3),
              Text(m.rating, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ]),
          if (m.genres.isNotEmpty) ...[const SizedBox(height: 8),
            Wrap(spacing: 5, runSpacing: 4, children: m.genres.map((g) =>
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.accentDim, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.3))),
                child: Text(g, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.accent)))).toList())],
          const SizedBox(height: 12),
          if (_firstChapter != null)
            ElevatedButton.icon(icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start Reading'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
              onPressed: _startReading),
        ])),
      ])),

      // ─── Synopsis ───────────────────────────────────────────────
      if (m.description.isNotEmpty) ...[
        const Divider(color: AppTheme.border, height: 1),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SYNOPSIS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(m.description, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
        ])),
        const SizedBox(height: 14),
      ],

      const Divider(color: AppTheme.border, height: 1),

      // ─── Multi-select bar ─────────────────────────────────────────
      if (multiSelect) Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.download), label: Text('Download (${selected.length})'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black87),
          onPressed: selected.isEmpty ? null : _downloadSelected)),
        const SizedBox(width: 8),
        TextButton(onPressed: () => setState(() { multiSelect = false; selected.clear(); }),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary))),
      ])),

      // ─── Chapter header ───────────────────────────────────────────
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [
        Text('${m.chapters.length} CHAPTERS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 1.5)),
        const Spacer(),
        GestureDetector(onTap: () => setState(() => sortAsc = !sortAsc),
          child: Row(children: [
            Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(sortAsc ? 'Oldest' : 'Newest', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
      ])),

      if (!multiSelect) Padding(padding: const EdgeInsets.only(left: 16, bottom: 6),
        child: Text('Hold to download or select', style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 11))),

      // ─── Chapters ─────────────────────────────────────────────────
      ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: chapters.length,
        separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1, indent: 16),
        itemBuilder: (_, i) {
          final ch = chapters[i];
          final prog = store.history.firstWhere(
            (p) => p.mangaSlug == m.slug && p.chapterSlug == ch.slug,
            orElse: () => ReadingProgress(mangaSlug: '', mangaTitle: '', mangaCover: '', chapterSlug: '', chapterNumber: '', pageIndex: 0));
          final isDl  = dm.isDownloaded(m.slug, ch.slug);
          final isIng = dm.isDownloading(m.slug, ch.slug);
          final prog2 = dm.progress(m.slug, ch.slug);

          return RepaintBoundary(child: ListTile(
            leading: multiSelect ? Icon(
              selected.contains(ch.slug) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: selected.contains(ch.slug) ? AppTheme.accent : AppTheme.textTertiary) : null,
            title: Text('Chapter ${ch.number}', style: GoogleFonts.inter(
              color: prog.mangaSlug.isNotEmpty ? AppTheme.textTertiary : AppTheme.textPrimary,
              fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Row(children: [
              if (prog.mangaSlug.isNotEmpty) ...[
                Text('p.${prog.pageIndex + 1}', style: GoogleFonts.inter(color: AppTheme.accent, fontSize: 12)),
                const SizedBox(width: 8)],
              if (isDl) const Icon(Icons.download_done, color: AppTheme.success, size: 14),
              if (isIng) ...[
                const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accent)),
                const SizedBox(width: 4),
                Text('${(prog2 * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 11))],
            ]),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
            onTap: multiSelect
                ? () => setState(() { selected.contains(ch.slug) ? selected.remove(ch.slug) : selected.add(ch.slug); })
                : () => _openReader(ch),
            onLongPress: multiSelect ? null : () => _onLongPress(ch),
          ));
        },
      ),
      const SizedBox(height: 40),
    ]));
  }

  Widget _statusBadge(String text) {
    final isOngoing = text.toLowerCase().contains('ongoing') || text.contains('مستمر');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isOngoing ? AppTheme.success : AppTheme.textTertiary).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
        color: isOngoing ? AppTheme.success : AppTheme.textTertiary)));
  }
}
