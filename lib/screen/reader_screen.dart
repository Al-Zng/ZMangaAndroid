import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';

class ReaderScreen extends StatefulWidget {
  final Manga manga;
  final Chapter chapter;
  final List<Chapter> allChapters;
  const ReaderScreen({Key? key, required this.manga, required this.chapter, required this.allChapters}) : super(key: key);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _service = MangaService();
  List<_PageEntry> allPages = [];
  List<_ChapterBoundary> chapterBoundaries = [];
  Set<String> loadedChapters = {};
  bool isLoading = true;
  bool loadingNext = false;
  String? error;
  bool showUI = true;
  late String currentChapterSlug;
  int currentPage = 0;

  @override
  void initState() {
    super.initState();
    currentChapterSlug = widget.chapter.slug;
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() { isLoading = true; error = null; });
    try {
      final urls = await _service.fetchChapterPages(widget.manga.slug, widget.chapter.slug);
      setState(() {
        allPages = urls.map((u) => _PageEntry(widget.chapter.slug, u)).toList();
        chapterBoundaries = [_ChapterBoundary(widget.chapter.slug, 0)];
        loadedChapters = {widget.chapter.slug};
        isLoading = false;
      });
    } catch (e) {
      setState(() { error = e.toString(); isLoading = false; });
    }
  }

  Future<void> _loadNextChapter() async {
    if (loadingNext || chapterBoundaries.isEmpty) return;
    final lastLoaded = chapterBoundaries.last.slug;
    final idx = widget.allChapters.indexWhere((c) => c.slug == lastLoaded);
    if (idx < 0 || idx + 1 >= widget.allChapters.length) return;
    final next = widget.allChapters[idx + 1];
    if (loadedChapters.contains(next.slug)) return;
    setState(() => loadingNext = true);
    try {
      final urls = await _service.fetchChapterPages(widget.manga.slug, next.slug);
      setState(() {
        final startIdx = allPages.length;
        allPages.addAll(urls.map((u) => _PageEntry(next.slug, u)));
        chapterBoundaries.add(_ChapterBoundary(next.slug, startIdx));
        loadedChapters.add(next.slug);
        loadingNext = false;
      });
    } catch (e) {
      setState(() => loadingNext = false);
    }
  }

  void _updateCurrentPage(int idx) {
    if (currentPage == idx) return;
    setState(() => currentPage = idx);
    _saveProgress(idx);
    if (idx >= allPages.length - 5) _loadNextChapter();
  }

  void _saveProgress(int pageIdx) {
    String chSlug = widget.chapter.slug;
    int boundaryStart = 0;
    for (final b in chapterBoundaries.reversed) {
      if (pageIdx >= b.startIndex) {
        chSlug = b.slug;
        boundaryStart = b.startIndex;
        break;
      }
    }
    final chNum = widget.manga.chapters.firstWhere((c) => c.slug == chSlug, orElse: () => widget.chapter).number;
    final localIdx = pageIdx - boundaryStart;
    final progress = ReadingProgress(
      mangaSlug: widget.manga.slug,
      mangaTitle: widget.manga.title,
      mangaCover: widget.manga.coverURL,
      chapterSlug: chSlug,
      chapterNumber: chNum,
      pageIndex: localIdx,
    );
    context.read<AppState>().saveProgress(progress);
  }

  String get currentChapterNumber {
    for (final b in chapterBoundaries.reversed) {
      if (currentPage >= b.startIndex) {
        return widget.manga.chapters.firstWhere((c) => c.slug == b.slug, orElse: () => widget.chapter).number;
      }
    }
    return widget.chapter.number;
  }

  void _toggleUI() {
    setState(() { showUI = !showUI; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isLoading && allPages.isEmpty)
            const Center(child: CircularProgressIndicator(color: ZTheme.accent))
          else if (error != null && allPages.isEmpty)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber, color: ZTheme.danger, size: 44),
              Text(error!, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadInitial, child: const Text('Retry')),
            ]))
          else if (allPages.isEmpty)
            const Center(child: Text('No pages', style: TextStyle(color: Colors.white54)))
          else
            GestureDetector(
              onTap: _toggleUI,
              child: ListView.builder(
                itemCount: allPages.length + (loadingNext ? 1 : 0),
                itemBuilder: (_, idx) {
                  if (idx < allPages.length) {
                    if (chapterBoundaries.any((b) => b.startIndex == idx) && idx > 0) {
                      final num = widget.manga.chapters.firstWhere((c) => c.slug == chapterBoundaries.firstWhere((b) => b.startIndex == idx).slug).number;
                      return Column(
                        children: [
                          _chapterSeparator(num),
                          _pageItem(idx),
                        ],
                      );
                    }
                    return _pageItem(idx);
                  } else {
                    return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: ZTheme.accent)));
                  }
                },
              ),
            ),
          if (showUI) _topBar(),
          if (showUI) _bottomBar(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageItem(int idx) {
    final entry = allPages[idx];
    return CachedMangaImage(url: entry.url, fit: BoxFit.fitWidth);
  }

  Widget _chapterSeparator(String number) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: Colors.white12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ZTheme.accent.withOpacity(0.1),
              border: Border.all(color: ZTheme.accent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Chapter $number', style: const TextStyle(color: ZTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Container(height: 1, color: Colors.white12)),
        ]),
      );

  Widget _topBar() => Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 48, right: 16, bottom: 14),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.manga.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Chapter $currentChapterNumber', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (allPages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text('$currentPage / ${allPages.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
            ],
          ),
        ),
      );

  Widget _bottomBar() => Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          height: 3,
          child: LinearProgressIndicator(
            value: allPages.isNotEmpty ? (currentPage + 1) / allPages.length : 0,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(ZTheme.accent),
          ),
        ),
      );
}

class _PageEntry {
  final String chapterSlug;
  final String url;
  _PageEntry(this.chapterSlug, this.url);
}

class _ChapterBoundary {
  final String slug;
  final int startIndex;
  _ChapterBoundary(this.slug, this.startIndex);
}