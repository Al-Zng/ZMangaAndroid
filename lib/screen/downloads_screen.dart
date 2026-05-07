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
  final DownloadManager dm = DownloadManager.shared; // تم التصحيح من Download Manager.shared إلى DownloadManager.shared

  void _openDownloadedChapter(DownloadedChapter chapter) {
    final manga = Manga(
        slug: chapter.mangaSlug,
        title: chapter.mangaTitle,
        coverURL: chapter.mangaCover);
    final chap = Chapter(
        slug: chapter.chapterSlug,
        number: chapter.chapterNumber,
        pages: chapter.pages);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: manga,
          chapter: chap,
          allChapters: [chap],
          initialPage: 0,
          preloadedPages: chapter.pages,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloading = dm.activeDownloads.keys.toList();
    final completed = dm.downloads.values.toList();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Downloads', style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          if (completed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.danger),
              onPressed: () => dm.removeAllDownloads(),
            ),
        ],
      ),
      body: completed.isEmpty && downloading.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.download, size: 48, color: AppTheme.textTertiary),
                  SizedBox(height: 12),
                  Text('No downloads yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : ListView(
              children: [
                if (downloading.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('DOWNLOADING',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary)),
                  ),
                ...downloading.map((key) {
                  final progress = dm.activeDownloads[key] ?? 0;
                  final parts = key.split('_');
                  final chapter = DownloadedChapter(
                    mangaSlug: parts[0],
                    chapterSlug: parts[1],
                    chapterNumber: '...',
                    mangaTitle: 'Loading...',
                    mangaCover: '',
                    pages: [],
                    downloadedAt: DateTime.now(),
                  );
                  return ListTile(
                    leading: const SizedBox(
                        width: 50,
                        height: 70,
                        child:
                            Icon(Icons.downloading, color: AppTheme.accent)),
                    title: Text('Ch. ${chapter.chapterNumber}',
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                            value: progress, color: AppTheme.accent),
                        Text('${(progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color: AppTheme.textTertiary, fontSize: 11)),
                      ],
                    ),
                  );
                }),
                if (completed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('COMPLETED',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary)),
                  ),
                ...completed.map((chapter) {
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedMangaImage(
                          url: chapter.mangaCover, width: 50, height: 70),
                    ),
                    title: Text(chapter.mangaTitle,
                        style: const TextStyle(color: AppTheme.textPrimary)),
                    subtitle: Text('Chapter ${chapter.chapterNumber}',
                        style: const TextStyle(color: AppTheme.accent)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.danger),
                      onPressed: () => dm.deleteChapter(
                          chapter.mangaSlug, chapter.chapterSlug),
                    ),
                    onTap: () => _openDownloadedChapter(chapter),
                  );
                }),
              ],
            ),
    );
  }
}