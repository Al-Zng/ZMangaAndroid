import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/manga_service.dart';
import '../widgets/cached_image.dart';
import 'manga_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _service = MangaService();

  List<Manga> results = [];
  bool isLoading = false;
  bool _hasSearched = false;
  bool _isError = false;
  int page = 1;
  bool hasMore = true;
  bool loadingMore = false;
  String? selectedGenre;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  static const _genres = ['درامـا','رومانسى','فانتازا','أكشن','كوميدى','رعب','خيال علمى','مغامرات','رياضة'];

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); _focus.dispose(); super.dispose(); }

  // ✅ FIX SEARCH: منطق بحث مُصحَّح — يفرّق بين خطأ شبكة و"لا نتائج"
  Future<void> _runSearch({bool reset = true}) async {
    final query = _controller.text.trim();
    if (query.isEmpty && selectedGenre == null) return;

    if (reset) {
      page = 1; hasMore = true;
      setState(() { results = []; isLoading = true; _hasSearched = false; _isError = false; });
    }

    try {
      List<Manga> items;
      if (query.isNotEmpty) {
        items = await _service.search(query, page: page);
      } else {
        items = await _service.fetchByGenre(selectedGenre!, page: page);
      }

      // ✅ FIX: فلترة نتائج فارغة أو مكررة (مطابق iOS)
      final seen = results.map((m) => m.slug).toSet();
      final fresh = items.where((m) => m.coverURL.isNotEmpty && !seen.contains(m.slug)).toList();

      if (!mounted) return;
      setState(() {
        if (reset) results = fresh; else results.addAll(fresh);
        hasMore = items.isNotEmpty;
        isLoading = false;
        _hasSearched = true;
        _isError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { isLoading = false; _hasSearched = true; _isError = true; });
    }
  }

  void _loadMore() {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    page++;
    _runSearch(reset: false).then((_) {
      if (mounted) setState(() => loadingMore = false);
    });
  }

  void _onQueryChanged(String val) {
    setState(() {}); // تحديث زر clear
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() { results = []; _hasSearched = false; _isError = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _runSearch();
    });
  }

  void _clearSearch() {
    _controller.clear(); _debounce?.cancel();
    setState(() { results = []; _hasSearched = false; _isError = false; selectedGenre = null; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(child: Column(children: [
        _searchBar(),
        _genrePills(),
        const Divider(height: 1, color: AppTheme.border),
        Expanded(child: _body()),
      ])),
    );
  }

  Widget _body() {
    if (isLoading && results.isEmpty) return const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2));
    if (_isError && results.isEmpty) return _errorState();
    if (_hasSearched && results.isEmpty) return _emptyState();
    if (results.isEmpty) return _browsePrompt();
    return _grid();
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.search, color: AppTheme.textSecondary, size: 18)),
        Expanded(child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search manga...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 15),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          onChanged: _onQueryChanged,
          onSubmitted: (_) { _debounce?.cancel(); _runSearch(); },
        )),
        if (_controller.text.isNotEmpty)
          GestureDetector(
            onTap: _clearSearch,
            child: const Padding(padding: EdgeInsets.all(12),
              child: Icon(Icons.cancel, color: AppTheme.textTertiary, size: 18)),
          ),
      ]),
    ),
  );

  Widget _genrePills() => SizedBox(
    height: 50,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      children: [
        _pill('All', selectedGenre == null, () {
          _debounce?.cancel();
          setState(() { selectedGenre = null; results = []; _hasSearched = false; });
        }),
        ..._genres.map((g) => _pill(g, selectedGenre == g, () {
          _debounce?.cancel();
          _controller.clear();
          setState(() { selectedGenre = g; results = []; _hasSearched = false; });
          _runSearch();
        })),
      ],
    ),
  );

  Widget _pill(String text, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: AppTheme.border),
        ),
        child: Text(text, style: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: selected ? AppTheme.bg : AppTheme.textSecondary)),
      ),
    ),
  );

  Widget _grid() => NotificationListener<ScrollNotification>(
    onNotification: (n) {
      if (n is ScrollEndNotification && n.metrics.extentAfter < 200) _loadMore();
      return false;
    },
    child: GridView.builder(
      padding: const EdgeInsets.all(16),
      // ✅ OPT: Adaptive minimum width مطابق iOS
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12, mainAxisSpacing: 14),
      itemCount: results.length + (loadingMore ? 1 : 0),
      // ✅ OPT: addRepaintBoundaries=true افتراضي — يمنع إعادة رسم الكل
      itemBuilder: (_, i) {
        if (i >= results.length) return const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2));
        final m = results[i];
        return RepaintBoundary(child: _SearchCard(manga: m));
      },
    ),
  );

  Widget _emptyState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.search_off, size: 48, color: AppTheme.textTertiary),
    const SizedBox(height: 12),
    Text(selectedGenre != null ? 'No results for "$selectedGenre"' : 'No results for "${_controller.text}"',
        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)),
  ]));

  Widget _browsePrompt() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.manage_search, size: 56, color: AppTheme.textTertiary),
    const SizedBox(height: 12),
    Text('Search or browse by genre', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 15)),
  ]));

  Widget _errorState() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, size: 48, color: AppTheme.textTertiary),
    const SizedBox(height: 12),
    Text('Connection error. Try again.', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
    const SizedBox(height: 12),
    ElevatedButton(onPressed: _runSearch,
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
      child: const Text('Retry')),
  ]));
}

class _SearchCard extends StatelessWidget {
  final Manga manga;
  const _SearchCard({required this.manga});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(context, MaterialPageRoute(
      builder: (_) => MangaDetailScreen(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL))),
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
