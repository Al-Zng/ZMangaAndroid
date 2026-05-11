import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/download_manager.dart';
import '../widgets/cached_image.dart';
import 'reader_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: نستخدم context.watch على DownloadManager المُسجَّل في Provider
    final dm = context.watch<DownloadManager>();
    final downloading = dm.activeDownloads.keys.toList();
    final groups = _buildGroups(dm);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Downloads', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          if (dm.downloads.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context, dm),
              child: Text('Clear All', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 15))),
        ],
      ),
      body: groups.isEmpty && downloading.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.download_outlined, size: 56, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text('No downloads yet', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)),
            ]))
          : ListView(children: [
              if (downloading.isNotEmpty) ...[
                _header('DOWNLOADING'),
                ...downloading.map((key) {
                  final prog = dm.activeDownloads[key] ?? 0;
                  final meta = dm.downloads[key] ?? dm.activeChapterMeta(key);
                  return _DownloadingRow(key: key, meta: meta, progress: prog);
                }),
              ],
              if (dm.downloadQueue.isNotEmpty) ...[
                _header('QUEUED (${dm.downloadQueue.length})'),
                ...dm.downloadQueue.take(3).map((t) => ListTile(
                  leading: const Icon(Icons.queue, color: AppTheme.textTertiary, size: 20),
                  title: Text(t.mangaTitle, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
                  subtitle: Text('Chapter ${t.chapterNumber}', style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12)),
                )),
              ],
              if (groups.isNotEmpty) ...[
                _header('COMPLETED (${dm.downloads.length} chapters)'),
                ...groups.map((g) => _MangaGroupRow(group: g)),
              ],
            ]),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
        color: AppTheme.textSecondary, letterSpacing: 1.5)));

  List<DownloadedMangaGroup> _buildGroups(DownloadManager dm) {
    final grouped = <String, List<DownloadedChapter>>{};
    for (final ch in dm.downloads.values) {
      grouped.putIfAbsent(ch.mangaSlug, () => []).add(ch);
    }
    final groups = grouped.entries.map((e) {
      final chs = e.value..sort((a, b) => (double.tryParse(b.chapterNumber) ?? 0).compareTo(double.tryParse(a.chapterNumber) ?? 0));
      return DownloadedMangaGroup(mangaSlug: e.key, mangaTitle: chs.first.mangaTitle, mangaCover: chs.first.mangaCover, chapters: chs);
    }).toList()..sort((a, b) => a.mangaTitle.compareTo(b.mangaTitle));
    return groups;
  }

  void _confirmClearAll(BuildContext context, DownloadManager dm) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Delete All Downloads', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      content: Text('All downloaded chapters will be permanently deleted.', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary))),
        TextButton(onPressed: () { dm.removeAllDownloads(); Navigator.pop(context); },
          child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w600))),
      ],
    ));
  }
}

// ─── Downloading row ──────────────────────────────────────────────────────────
class _DownloadingRow extends StatelessWidget {
  final String key;
  final DownloadedChapter? meta;
  final double progress;
  const _DownloadingRow({required this.key, this.meta, required this.progress});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: meta != null
        ? ClipRRect(borderRadius: BorderRadius.circular(6),
            child: CachedMangaImage(url: meta!.mangaCover, width: 44, height: 60))
        : Container(width: 44, height: 60, decoration: BoxDecoration(
            color: AppTheme.card, borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.downloading, color: AppTheme.accent, size: 20)),
    title: Text(meta?.mangaTitle ?? '...', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Chapter ${meta?.chapterNumber ?? "..."}', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress, color: AppTheme.accent,
          backgroundColor: AppTheme.border, minHeight: 4)),
      const SizedBox(height: 2),
      Text('${(progress * 100).toStringAsFixed(0)}%',
        style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 11)),
    ]),
  );
}

// ─── Manga group row ──────────────────────────────────────────────────────────
class _MangaGroupRow extends StatelessWidget {
  final DownloadedMangaGroup group;
  const _MangaGroupRow({required this.group});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: ClipRRect(borderRadius: BorderRadius.circular(8),
      child: CachedMangaImage(url: group.mangaCover, width: 46, height: 64)),
    title: Text(group.mangaTitle, style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${group.chapters.length} chapters downloaded', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
    onTap: () => Navigator.push(context, MaterialPageRoute(
      builder: (_) => _DownloadedDetailScreen(group: group))),
  );
}

// ─── Detail screen ────────────────────────────────────────────────────────────
class _DownloadedDetailScreen extends StatefulWidget {
  final DownloadedMangaGroup group;
  const _DownloadedDetailScreen({required this.group});
  @override
  State<_DownloadedDetailScreen> createState() => _DownloadedDetailScreenState();
}

class _DownloadedDetailScreenState extends State<_DownloadedDetailScreen> {
  bool _ascending = false;

  List<DownloadedChapter> get _sortedChapters {
    final list = List.of(widget.group.chapters);
    list.sort((a, b) {
      final na = double.tryParse(a.chapterNumber) ?? 0;
      final nb = double.tryParse(b.chapterNumber) ?? 0;
      return _ascending ? na.compareTo(nb) : nb.compareTo(na);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final chapters = _sortedChapters;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(widget.group.mangaTitle,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        // ─── Manga info ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: CachedMangaImage(url: widget.group.mangaCover, width: 90, height: 127)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.group.mangaTitle,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.download_done, size: 14, color: AppTheme.success),
                const SizedBox(width: 5),
                Text('${chapters.length} chapters', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
              ]),
            ])),
          ]),
        ),
        const Divider(color: AppTheme.border, height: 1),
        // ─── Sort bar ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${chapters.length} CHAPTERS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _ascending = !_ascending),
              child: Row(children: [
                Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(_ascending ? 'Oldest' : 'Newest', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        // ─── Chapter list ────────────────────────────────────────────
        Expanded(child: ListView.separated(
          itemCount: chapters.length,
          separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1, indent: 16),
          itemBuilder: (_, i) {
            final ch = chapters[i];
            return ListTile(
              title: Text('Chapter ${ch.chapterNumber}',
                style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Row(children: [
                const Icon(Icons.download_done, size: 12, color: AppTheme.success),
                const SizedBox(width: 4),
                Text('Downloaded', style: GoogleFonts.inter(color: AppTheme.success, fontSize: 12)),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.textTertiary, size: 20),
                  onPressed: () => _confirmDelete(context, dm, ch)),
                const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
              ]),
              onTap: () => _openChapter(context, ch),
            );
          },
        )),
      ]),
    );
  }

  void _openChapter(BuildContext context, DownloadedChapter dc) {
    final manga = Manga(slug: widget.group.mangaSlug, title: widget.group.mangaTitle, coverURL: widget.group.mangaCover);
    final chapter = Chapter(slug: dc.chapterSlug, number: dc.chapterNumber, pages: dc.pages);
    final allChapters = _sortedChapters.map((d) => Chapter(slug: d.chapterSlug, number: d.chapterNumber, pages: d.pages)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(
      manga: manga, chapter: chapter, allChapters: allChapters,
      initialPage: 0, preloadedPages: dc.pages, isOfflineMode: true)));
  }

  void _confirmDelete(BuildContext context, DownloadManager dm, DownloadedChapter ch) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Delete Chapter', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      content: Text('Delete Chapter ${ch.chapterNumber}?', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary))),
        TextButton(onPressed: () { dm.deleteChapter(ch.mangaSlug, ch.chapterSlug); Navigator.pop(context); Navigator.pop(context); },
          child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w600))),
      ],
    ));
  }
}
