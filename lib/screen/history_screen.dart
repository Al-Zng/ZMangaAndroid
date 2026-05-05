import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _showClearDialog = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: ZTheme.bg,
      appBar: AppBar(
        title: const Text('History', style: TextStyle(color: ZTheme.textPrimary)),
        backgroundColor: ZTheme.surface,
        actions: [
          if (store.history.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete, color: ZTheme.danger), onPressed: () => setState(() => _showClearDialog = true)),
        ],
      ),
      body: store.history.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule, size: 48, color: ZTheme.textTertiary),
              const SizedBox(height: 12),
              const Text('No reading history', style: TextStyle(color: ZTheme.textSecondary)),
              const Text('Manga you read will appear here', style: TextStyle(color: ZTheme.textTertiary, fontSize: 13)),
            ]))
          : ListView.builder(
              itemCount: store.history.length,
              itemBuilder: (_, i) {
                final p = store.history[i];
                return ListTile(
                  leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedMangaImage(url: p.mangaCover, width: 50, height: 70)),
                  title: Text(p.mangaTitle, style: const TextStyle(color: ZTheme.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Ch.${p.chapterNumber}', style: const TextStyle(color: ZTheme.accent)),
                        const Text(' · Page ${p.pageIndex + 1}', style: TextStyle(color: ZTheme.textSecondary)),
                      ]),
                      Text(_timeAgo(p.lastRead), style: const TextStyle(color: ZTheme.textTertiary, fontSize: 11)),
                    ],
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: p.mangaSlug, preloadTitle: p.mangaTitle, preloadCover: p.mangaCover))),
                  trailing: const Icon(Icons.chevron_right, color: ZTheme.textTertiary),
                );
              },
            ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}