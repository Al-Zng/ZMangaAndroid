import 'package:flutter/material.dart';
import '../theme.dart';
import '../models.dart';
import '../services/manga_service.dart';
import 'manga_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _service = MangaService();
  List<Manga> results = [];
  bool isLoading = false;
  int page = 1;
  bool hasMore = true;
  bool loadingMore = false;
  String? selectedGenre;
  static const genres = ['درامـا', 'رومانسى', 'فانتازا', 'أكشن', 'كوميدى', 'رعب', 'خيال علمى', 'مغامرات', 'رياضة'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search({bool reset = true}) async {
    final query = _controller.text.trim();
    if (query.isEmpty && selectedGenre == null) return;
    if (reset) { page = 1; hasMore = true; results.clear(); setState(() => isLoading = true); }
    try {
      List<Manga> items;
      if (query.isNotEmpty) {
        items = await _service.search(query, page: page);
      } else {
        items = await _service.fetchByGenre(selectedGenre!, page: page);
      }
      setState(() {
        if (reset) results = items; else results.addAll(items);
        hasMore = items.isNotEmpty;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _loadMore() {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    page++;
    _search(reset: false).then((_) => setState(() => loadingMore = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _searchBar(),
            _genrePills(),
            const Divider(color: ZTheme.border),
            Expanded(
              child: isLoading && results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty && _controller.text.isNotEmpty
                      ? _emptyState()
                      : results.isEmpty
                          ? _browsePrompt()
                          : _resultsGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _controller,
          style: const TextStyle(color: ZTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search manga...',
            hintStyle: const TextStyle(color: ZTheme.textTertiary),
            prefixIcon: const Icon(Icons.search, color: ZTheme.textSecondary),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.cancel, color: ZTheme.textTertiary), onPressed: () { _controller.clear(); results.clear(); setState(() {}); })
                : null,
            filled: true,
            fillColor: ZTheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ZTheme.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ZTheme.border)),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _search(),
        ),
      );

  Widget _genrePills() => SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _pill('All', selected: selectedGenre == null, onTap: () { selectedGenre = null; results.clear(); setState(() {}); }),
            ...genres.map((g) => _pill(g, selected: selectedGenre == g, onTap: () { selectedGenre = g; results.clear(); setState(() => _search()); })),
          ],
        ),
      );

  Widget _pill(String text, {required bool selected, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? ZTheme.accent : ZTheme.card,
              borderRadius: BorderRadius.circular(20),
              border: selected ? null : Border.all(color: ZTheme.border),
            ),
            child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? ZTheme.bg : ZTheme.textSecondary)),
          ),
        ),
      );

  Widget _resultsGrid() => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification && notification.metrics.extentAfter < 200) _loadMore();
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 14),
          itemCount: results.length + (loadingMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= results.length) return const Center(child: CircularProgressIndicator());
            final m = results[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MangaDetailScreen(slug: m.slug, preloadTitle: m.title, preloadCover: m.coverURL))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedMangaImage(url: m.highQualityCoverURL))),
                  Text(m.title, maxLines: 2, style: const TextStyle(fontSize: 11, color: ZTheme.textPrimary)),
                ],
              ),
            );
          },
        ),
      );

  Widget _emptyState() => Center(child: Text('No results for "${_controller.text}"', style: const TextStyle(color: ZTheme.textSecondary)));
  Widget _browsePrompt() => const Center(child: Text('Search or browse by genre', style: TextStyle(color: ZTheme.textSecondary)));
}