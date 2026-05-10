import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/download_manager.dart';
import '../widgets/cached_image.dart';
import 'reader_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager dm = DownloadManager.shared;

  @override
  void initState() {
    super.initState();
    // ✅ FIX: نستمع لتغييرات DownloadManager ونُعيد بناء الشاشة تلقائياً
    dm.addListener(_onDownloadChanged);
  }

  void _onDownloadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    dm.removeListener(_onDownloadChanged);
    super.dispose();
  }

  List<DownloadedMangaGroup> get downloadedMangas {
    final grouped = dm.downloads.values
        .fold<Map<String, List<DownloadedChapter>>>({}, (map, chapter) {
      map.putIfAbsent(chapter.mangaSlug, () => []);
      map[chapter.mangaSlug]!.add(chapter);
      return map;
    });

    return grouped.entries.map((entry) {
      final slug = entry.key;
      final chapters = entry.value;
      final first = chapters.first;
      final uniqueChapters = chapters.toSet().toList()
        ..sort((a, b) =>
            (double.tryParse(b.chapterNumber) ?? 0)
                .compareTo(double.tryParse(a.chapterNumber) ?? 0));
      return DownloadedMangaGroup(
        mangaSlug: slug,
        mangaTitle: first.mangaTitle,
        mangaCover: first.mangaCover,
        chapters: uniqueChapters,
      );
    }).toList()
      ..sort((a, b) => a.mangaTitle.compareTo(b.mangaTitle));
  }

  void _openDownloadedManga(DownloadedMangaGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadedMangaDetailScreen(
          mangaSlug: group.mangaSlug,
          mangaTitle: group.mangaTitle,
          mangaCover: group.mangaCover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloading = dm.activeDownloads.keys.toList();
    final completed = downloadedMangas;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Downloads',
            style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          if (dm.downloads.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.danger),
              onPressed: () => _confirmDeleteAll(context),
            ),
        ],
      ),
      body: completed.isEmpty && downloading.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, size: 48,
                      color: AppTheme.textTertiary),
                  SizedBox(height: 12),
                  Text('No downloads yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : ListView(
              children: [
                if (downloading.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('DOWNLOADING',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.5)),
                  ),
                  ...downloading.map((key) {
                    final progress = dm.activeDownloads[key] ?? 0;
                    final parts = key.split('_');
                    // ✅ FIX: تحاول الحصول على معلومات أفضل من _downloads إن وُجدت
                    final knownChapter = dm.downloads[key];
                    final mangaTitle = knownChapter?.mangaTitle ?? parts.first;
                    final chNum = knownChapter?.chapterNumber ?? '...';
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: knownChapter != null
                            ? CachedMangaImage(
                                url: knownChapter.mangaCover,
                                width: 50,
                                height: 70)
                            : const SizedBox(
                                width: 50,
                                height: 70,
                                child: Icon(Icons.downloading,
                                    color: AppTheme.accent)),
                      ),
                      title: Text(mangaTitle,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chapter $chNum',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                              value: progress, color: AppTheme.accent,
                              backgroundColor: AppTheme.border),
                          const SizedBox(height: 2),
                          Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  color: AppTheme.textTertiary,
                                  fontSize: 11)),
                        ],
                      ),
                    );
                  }),
                ],
                if (completed.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('COMPLETED',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.5)),
                  ),
                  ...completed.map((group) {
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedMangaImage(
                            url: group.mangaCover,
                            width: 50,
                            height: 70),
                      ),
                      title: Text(group.mangaTitle,
                          style: const TextStyle(
                              color: AppTheme.textPrimary)),
                      subtitle: Text(
                          '${group.chapters.length} chapters downloaded',
                          style: const TextStyle(
                              color: AppTheme.textSecondary)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppTheme.textTertiary),
                      onTap: () => _openDownloadedManga(group),
                    );
                  }),
                ],
              ],
            ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete All Downloads',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure? This cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              dm.removeAllDownloads();
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

class DownloadedMangaDetailScreen extends StatefulWidget {
  final String mangaSlug;
  final String mangaTitle;
  final String mangaCover;

  const DownloadedMangaDetailScreen({
    super.key,
    required this.mangaSlug,
    required this.mangaTitle,
    required this.mangaCover,
  });

  @override
  State<DownloadedMangaDetailScreen> createState() =>
      _DownloadedMangaDetailScreenState();
}

class _DownloadedMangaDetailScreenState
    extends State<DownloadedMangaDetailScreen> {
  final DownloadManager dm = DownloadManager.shared;
  bool chapterSortAsc = false;

  @override
  void initState() {
    super.initState();
    dm.addListener(_onChanged);
  }

  void _onChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    dm.removeListener(_onChanged);
    super.dispose();
  }

  List<DownloadedChapter> get downloadedChapters {
    return dm.downloads.values
        .where((c) => c.mangaSlug == widget.mangaSlug)
        .toList()
      ..sort((a, b) => chapterSortAsc
          ? (double.tryParse(a.chapterNumber) ?? 0)
              .compareTo(double.tryParse(b.chapterNumber) ?? 0)
          : (double.tryParse(b.chapterNumber) ?? 0)
              .compareTo(double.tryParse(a.chapterNumber) ?? 0));
  }

  void _openChapter(DownloadedChapter downloadedChapter) {
    final manga = Manga(
      slug: widget.mangaSlug,
      title: widget.mangaTitle,
      coverURL: widget.mangaCover,
    );
    final chapter = Chapter(
      slug: downloadedChapter.chapterSlug,
      number: downloadedChapter.chapterNumber,
      pages: downloadedChapter.pages,
    );

    final allChapters = downloadedChapters
        .map((dc) => Chapter(
              slug: dc.chapterSlug,
              number: dc.chapterNumber,
              pages: dc.pages,
            ))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: manga,
          chapter: chapter,
          allChapters: allChapters,
          initialPage: 0,
          preloadedPages: downloadedChapter.pages,
          isOfflineMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapters = downloadedChapters;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(widget.mangaTitle,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      ),
      body: chapters.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 48, color: AppTheme.textTertiary),
                  SizedBox(height: 12),
                  Text('No downloaded chapters',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedMangaImage(
                            url: widget.mangaCover,
                            width: 110,
                            height: 155),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.mangaTitle,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary)),
                            const SizedBox(height: 8),
                            Text('${chapters.length} chapters downloaded',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Text('${chapters.length} CHAPTERS',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                              letterSpacing: 2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            setState(() => chapterSortAsc = !chapterSortAsc),
                        child: Row(children: [
                          Icon(
                              chapterSortAsc
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 12,
                              color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(chapterSortAsc ? 'Oldest' : 'Newest',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12)),
                        ]),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: chapters.length,
                    separatorBuilder: (_, __) => const Divider(
                        color: AppTheme.border, indent: 16),
                    itemBuilder: (_, i) {
                      final dc = chapters[i];
                      return ListTile(
                        title: Text('Chapter ${dc.chapterNumber}',
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14)),
                        subtitle: const Row(children: [
                          Icon(Icons.download_done,
                              color: AppTheme.success, size: 14),
                          SizedBox(width: 4),
                          Text('Downloaded',
                              style: TextStyle(
                                  color: AppTheme.success, fontSize: 12)),
                        ]),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppTheme.textTertiary, size: 20),
                              onPressed: () => _confirmDelete(dc),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppTheme.textTertiary),
                          ],
                        ),
                        onTap: () => _openChapter(dc),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _confirmDelete(DownloadedChapter dc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Chapter',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Delete Chapter ${dc.chapterNumber}?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              dm.deleteChapter(dc.mangaSlug, dc.chapterSlug);
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
