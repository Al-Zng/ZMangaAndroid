import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/download_manager.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

enum Category { favorites, wantToRead, completed, downloaded }

enum SortOption { dateAdded, title }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Category _selectedCategory = Category.favorites;
  SortOption _sortOption = SortOption.dateAdded;

  List<Manga> _displayedManga(AppState store) {
    List<Manga> list;
    switch (_selectedCategory) {
      case Category.favorites:
        list = store.library;
        break;
      case Category.wantToRead:
        list = store.wantToRead;
        break;
      case Category.completed:
        list = store.completed;
        break;
      case Category.downloaded:
        final slugs = DownloadManager().downloads.values.map((e) => e.mangaSlug).toSet();
        list = (store.library + store.wantToRead + store.completed)
            .where((m) => slugs.contains(m.slug))
            .toList();
        break;
    }
    if (_sortOption == SortOption.title) {
      list.sort((a, b) => a.title.compareTo(b.title));
    }
    return list;
  }

  void _removeFromCurrentCategory(AppState store, Manga manga) {
    switch (_selectedCategory) {
      case Category.favorites:
        store.removeFromLibrary(manga);
        break;
      case Category.wantToRead:
        store.removeWantToRead(manga);
        break;
      case Category.completed:
        store.removeCompleted(manga);
        break;
      case Category.downloaded:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    final items = _displayedManga(store);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Library', style: TextStyle(color: AppTheme.textPrimary)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: AppTheme.textSecondary),
            onSelected: (val) => setState(() {
              _sortOption = val == 'Title' ? SortOption.title : SortOption.dateAdded;
            }),
            itemBuilder: (_) => ['Date Added', 'Title']
                .map((s) => PopupMenuItem(value: s, child: Text(s)))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Category tabs
          Container(
            height: 50,
            color: AppTheme.surface,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: Category.values.map((cat) {
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Chip(
                      label: Text(
                        cat.name[0].toUpperCase() + cat.name.substring(1),
                        style: TextStyle(
                          color: selected ? AppTheme.bg : AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: selected ? AppTheme.accent : AppTheme.card,
                      side: BorderSide(color: selected ? Colors.transparent : AppTheme.border),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(color: AppTheme.border, height: 1),
          // Grid
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.library_books, size: 48, color: AppTheme.textTertiary),
                        const SizedBox(height: 12),
                        const Text('No manga here', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final m = items[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MangaDetailScreen(
                              slug: m.slug,
                              preloadTitle: m.title,
                              preloadCover: m.coverURL,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedMangaImage(url: m.highQualityCoverURL),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(Icons.favorite, size: 16, color: AppTheme.accent),
                                  ),
                                ],
                              ),
                            ),
                            Text(m.title, maxLines: 2, style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}