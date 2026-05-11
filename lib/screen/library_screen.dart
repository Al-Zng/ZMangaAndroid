import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/download_manager.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

enum _Category { favorites, wantToRead, completed, downloaded }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Category _cat = _Category.favorites;

  List<Manga> _items(AppState store) {
    switch (_cat) {
      case _Category.favorites:  return store.library;
      case _Category.wantToRead: return store.wantToRead;
      case _Category.completed:  return store.completed;
      case _Category.downloaded:
        final slugs = DownloadManager.shared.downloads.values.map((e) => e.mangaSlug).toSet();
        final all = {...store.library, ...store.wantToRead, ...store.completed};
        return all.where((m) => slugs.contains(m.slug)).toList();
    }
  }

  static const _labels = {
    _Category.favorites:  ('Favorites',  Icons.heart_broken_outlined),
    _Category.wantToRead: ('Want to Read', Icons.bookmark_outline),
    _Category.completed:  ('Completed',  Icons.check_circle_outline),
    _Category.downloaded: ('Downloads',  Icons.download_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    final items = _items(store);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Library', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
      ),
      body: Column(children: [
        // ─── Category Pills ────────────────────────────────────────
        Container(
          height: 50, color: AppTheme.surface,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: _Category.values.map((cat) {
              final selected = cat == _cat;
              final info = _labels[cat]!;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _cat = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accent : AppTheme.card,
                      borderRadius: BorderRadius.circular(20),
                      border: selected ? null : Border.all(color: AppTheme.border)),
                    child: Row(children: [
                      Icon(info.$2, size: 13, color: selected ? AppTheme.bg : AppTheme.textSecondary),
                      const SizedBox(width: 5),
                      Text(info.$1, style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: selected ? AppTheme.bg : AppTheme.textSecondary)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(color: AppTheme.border, height: 1),
        // ─── Grid ──────────────────────────────────────────────────
        Expanded(child: items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.library_books_outlined, size: 56, color: AppTheme.textTertiary),
                const SizedBox(height: 12),
                Text('Nothing here yet', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)),
              ]))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 0.62,
                  crossAxisSpacing: 10, mainAxisSpacing: 14),
                itemCount: items.length,
                itemBuilder: (_, i) => RepaintBoundary(child: _LibraryCard(manga: items[i], category: _cat)),
              )),
      ]),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final Manga manga;
  final _Category category;
  const _LibraryCard({required this.manga, required this.category});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
      MangaDetailScreen(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedMangaImage(url: manga.highQualityCoverURL, fit: BoxFit.cover))),
      const SizedBox(height: 5),
      Text(manga.title, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
    ]),
  );
}
