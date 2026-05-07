import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _showClearAlert = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('History',
            style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          if (store.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.danger),
              onPressed: () => setState(() => _showClearAlert = true),
            ),
        ],
      ),
      body: store.history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.schedule, size: 48,
                      color: AppTheme.textTertiary),
                  SizedBox(height: 12),
                  Text('No reading history',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  Text('Manga you read will appear here',
                      style: TextStyle(
                          color: AppTheme.textTertiary, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: store.history.length,
              itemBuilder: (_, i) {
                final p = store.history[i];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedMangaImage(
                        url: p.mangaCover, width: 50, height: 70),
                  ),
                  title: Text(p.mangaTitle,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Ch. ${p.chapterNumber}',
                            style: const TextStyle(color: AppTheme.accent)),
                        Text(' · Page ${p.pageIndex + 1}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary)),
                      ]),
                      Text(_timeAgo(p.lastRead),
                          style: const TextStyle(
                              color: AppTheme.textTertiary, fontSize: 11)),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppTheme.textTertiary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MangaDetailScreen(
                        slug: p.mangaSlug,
                        preloadTitle: p.mangaTitle,
                        preloadCover: p.mangaCover,
                      ),
                    ),
                  ),
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