import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('History', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          if (store.history.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, store),
              child: Text('Clear', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 15)),
            ),
        ],
      ),
      body: store.history.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.access_time_outlined, size: 56, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text('No reading history', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Manga you read will appear here', style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 13)),
            ]))
          : ListView.separated(
              // ✅ OPT: itemExtent ثابت يسرّع التمرير بشكل كبير
              itemCount: store.history.length,
              separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1, indent: 78),
              itemBuilder: (_, i) {
                final p = store.history[i];
                return RepaintBoundary(child: _HistoryRow(progress: p));
              },
            ),
    );
  }

  void _confirmClear(BuildContext ctx, AppState store) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Clear History', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      content: Text('Remove all reading history?', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary))),
        TextButton(onPressed: () { store.clearHistory(); Navigator.pop(ctx); },
          child: Text('Clear', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w600))),
      ],
    ));
  }
}

class _HistoryRow extends StatelessWidget {
  final ReadingProgress progress;
  const _HistoryRow({required this.progress});

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours   < 1) return '${d.inMinutes}m ago';
    if (d.inDays    < 1) return '${d.inHours}h ago';
    if (d.inDays    < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: ClipRRect(borderRadius: BorderRadius.circular(8),
      child: CachedMangaImage(url: progress.mangaCover, width: 46, height: 64, fit: BoxFit.cover)),
    title: Text(progress.mangaTitle,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 2),
      Row(children: [
        const Icon(Icons.auto_stories, size: 11, color: AppTheme.accent),
        const SizedBox(width: 4),
        Text('Ch. ${progress.chapterNumber}', style: GoogleFonts.inter(color: AppTheme.accent, fontSize: 12)),
        Text(' · Page ${progress.pageIndex + 1}', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
      ]),
      const SizedBox(height: 2),
      Text(_timeAgo(progress.lastRead), style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 11)),
    ]),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
      MangaDetailScreen(slug: progress.mangaSlug, preloadTitle: progress.mangaTitle, preloadCover: progress.mangaCover))),
  );
}
