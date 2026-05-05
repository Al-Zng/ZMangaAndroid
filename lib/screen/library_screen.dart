import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _sortBy = 'Date Added';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    List<Manga> sorted = List.from(store.library);
    if (_sortBy == 'Title') sorted.sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      backgroundColor: ZTheme.bg,
      appBar: AppBar(
        title: const Text('Library', style: TextStyle(color: ZTheme.textPrimary)),
        backgroundColor: ZTheme.surface,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: ZTheme.textSecondary),
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (_) => ['Date Added', 'Title'].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
          ),
        ],
      ),
      body: store.library.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.library_books, size: 48, color: ZTheme.textTertiary),
                const SizedBox(height: 12),
                const Text('Your library is empty', style: TextStyle(color: ZTheme.textSecondary)),
                const Text('Add manga from their detail page', style: TextStyle(color: ZTheme.textTertiary, fontSize: 13)),
              ]),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 16),
              itemCount: sorted.length,
              itemBuilder: (_, i) {
                final m = sorted[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: m.slug, preloadTitle: m.title, preloadCover: m.coverURL))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: m.highQualityCoverURL)),
                            Positioned(top: 4, right: 4, child: Icon(Icons.favorite, size: 16, color: ZTheme.accent)),
                          ],
                        ),
                      ),
                      Text(m.title, maxLines: 2, style: const TextStyle(fontSize: 11, color: ZTheme.textPrimary)),
                      if (m.genres.isNotEmpty)
                        Text(m.genres.take(2).join(' · '), style: const TextStyle(fontSize: 10, color: ZTheme.textTertiary)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}