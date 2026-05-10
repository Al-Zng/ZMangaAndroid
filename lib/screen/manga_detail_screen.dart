import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/cached_image.dart';
import '../services/manga_service.dart';
import '../services/download_manager.dart';
import 'reader_screen.dart';

class MangaDetailScreen extends StatefulWidget {
  final String slug;
  final String preloadTitle;
  final String preloadCover;

  const MangaDetailScreen({
    super.key,
    required this.slug,
    this.preloadTitle = '',
    this.preloadCover = '',
  });

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  final _service = MangaService();
  final _dm = DownloadManager.shared;
  Manga? manga;
  bool isLoading = true;
  String? error;
  bool chapterSortAsc = false;
  bool showChapterError = false;
  bool multiSelectMode = false;
  final Set<String> selectedChapters = {};
  final Set<String> downloadingChapters = {};

  @override
  void initState() {
    super.initState();
    _dm.addListener(_onDmChanged);
    _loadDetail();
  }

  @override
  void dispose() {
    _dm.removeListener(_onDmChanged);
    super.dispose();
  }

  // ✅ FIX: استمع لتغييرات التحميل لتحديث أيقونات الفصول
  void _onDmChanged() { if (mounted) setState(() {}); }

  Future<void> _loadDetail() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final cached = context.read<AppState>().mangaCache[widget.slug];
      if (cached != null) {
        setState(() {
          manga = cached;
          isLoading = false;
        });
        _service.fetchDetail(widget.slug).then((m) {
          if (mounted) {
            setState(() => manga = m);
            context.read<AppState>().cacheManga(m);
          }
        }).catchError((_) {});
        return;
      }
      // ✅ FIX: timeout 45 ثانية لمنع الـ loading اللا متناهي
      final m = await _service.fetchDetail(widget.slug)
          .timeout(const Duration(seconds: 45),
              onTimeout: () => throw Exception('Loading timeout. Tap Retry'));
      if (!mounted) return;
      setState(() {
        manga = m;
        isLoading = false;
      });
      context.read<AppState>().cacheManga(m);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  List<Chapter> get sortedChapters {
    if (manga == null) return [];
    final list = List<Chapter>.from(manga!.chapters);
    list.sort((a, b) {
      final na = double.tryParse(a.number) ?? 0;
      final nb = double.tryParse(b.number) ?? 0;
      return chapterSortAsc ? na.compareTo(nb) : nb.compareTo(na);
    });
    return list;
  }

  Chapter? get firstChapter {
    if (manga == null || manga!.chapters.isEmpty) return null;
    return manga!.chapters.reduce((a, b) =>
        (double.tryParse(a.number) ?? 0) < (double.tryParse(b.number) ?? 0)
            ? a
            : b);
  }

  void _startReading() {
    if (manga == null || manga!.chapters.isEmpty) {
      setState(() => showChapterError = true);
      return;
    }
    Chapter target;
    final progress = context.read<AppState>().history.firstWhere(
          (p) => p.mangaSlug == widget.slug,
          orElse: () => ReadingProgress(
              mangaSlug: '',
              mangaTitle: '',
              mangaCover: '',
              chapterSlug: '',
              chapterNumber: '',
              pageIndex: 0),
        );
    if (progress.mangaSlug.isNotEmpty) {
      target = manga!.chapters.firstWhere(
        (c) => c.slug == progress.chapterSlug,
        orElse: () => firstChapter!,
      );
    } else {
      target = firstChapter!;
    }
    _openReader(target);
  }

  void _openReader(Chapter ch) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: manga!,
          chapter: ch,
          allChapters: sortedChapters,
        ),
      ),
    );
  }

  // ✅ FIX: تحميل فصل واحد (يُستدعى من قائمة الضغطة المطولة)
  Future<void> _downloadSingleChapter(Chapter chapter) async {
    if (_dm.isDownloaded(manga!.slug, chapter.slug) ||
        _dm.isDownloading(manga!.slug, chapter.slug) ||
        downloadingChapters.contains(chapter.slug)) return;

    downloadingChapters.add(chapter.slug);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Downloading Chapter ${chapter.number}...'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppTheme.surface),
    );

    try {
      final pages = await _service.fetchChapterPages(manga!.slug, chapter.slug)
          .timeout(const Duration(seconds: 45));
      await _dm.downloadChapter(manga: manga!, chapter: chapter, pages: pages);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Download failed: ${e.toString().replaceAll("Exception: ", "")}'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
    downloadingChapters.remove(chapter.slug);
    if (mounted) setState(() {});
  }

  Future<void> _downloadSelectedChapters() async {
    final chapters = manga!.chapters
        .where((c) => selectedChapters.contains(c.slug))
        .toList();
    selectedChapters.clear();
    setState(() => multiSelectMode = false);

    for (final chapter in chapters) {
      downloadingChapters.add(chapter.slug);
      setState(() {});
      try {
        final pages = await _service.fetchChapterPages(
            manga!.slug, chapter.slug)
            .timeout(const Duration(seconds: 45));
        await _dm.downloadChapter(
            manga: manga!, chapter: chapter, pages: pages);
      } catch (_) {}
      downloadingChapters.remove(chapter.slug);
      setState(() {});
    }
  }

  // ✅ FIX: قائمة سياق الضغطة المطولة
  void _onChapterLongPress(Chapter ch) {
    final isDownloaded = _dm.isDownloaded(manga!.slug, ch.slug);
    final isDownloading = _dm.isDownloading(manga!.slug, ch.slug) ||
        downloadingChapters.contains(ch.slug);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── عنوان
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Chapter ${ch.number}',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(color: AppTheme.border, height: 1),
              // ─── قراءة
              ListTile(
                leading: const Icon(Icons.menu_book, color: AppTheme.textSecondary),
                title: const Text('Read', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _openReader(ch);
                },
              ),
              // ─── تحميل / محذوف
              if (isDownloaded)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                  title: const Text('Delete Download',
                      style: TextStyle(color: AppTheme.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    _dm.deleteChapter(manga!.slug, ch.slug);
                  },
                )
              else if (isDownloading)
                const ListTile(
                  leading: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent)),
                  title: Text('Downloading...',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              else
                ListTile(
                  leading: const Icon(Icons.download, color: AppTheme.accent),
                  title: const Text('Download Chapter',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadSingleChapter(ch);
                  },
                ),
              // ─── تحديد متعدد
              ListTile(
                leading: const Icon(Icons.checklist, color: AppTheme.textSecondary),
                title: const Text('Select Chapters',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    multiSelectMode = true;
                    selectedChapters.add(ch.slug);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(manga?.title ?? widget.preloadTitle,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 16)),
        actions: [
          if (manga != null)
            IconButton(
              icon: Icon(
                  store.isInLibrary(manga!)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: store.isInLibrary(manga!)
                      ? AppTheme.accent
                      : AppTheme.textSecondary),
              onPressed: () => store.isInLibrary(manga!)
                  ? store.removeFromLibrary(manga!)
                  : store.addToLibrary(manga!),
            ),
          if (manga != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
              onSelected: (val) {
                if (val == 'want') {
                  store.isWantToRead(manga!)
                      ? store.removeWantToRead(manga!)
                      : store.addWantToRead(manga!);
                } else if (val == 'complete') {
                  store.isCompleted(manga!)
                      ? store.removeCompleted(manga!)
                      : store.addCompleted(manga!);
                } else if (val == 'multi') {
                  setState(() {
                    multiSelectMode = !multiSelectMode;
                    if (!multiSelectMode) selectedChapters.clear();
                  });
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'want',
                    child: Text(store.isWantToRead(manga!)
                        ? 'Remove Want to Read'
                        : 'Want to Read')),
                PopupMenuItem(
                    value: 'complete',
                    child: Text(store.isCompleted(manga!)
                        ? 'Unmark Completed'
                        : 'Completed')),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: 'multi',
                    child: Text(multiSelectMode
                        ? 'Cancel Selection'
                        : 'Select Chapters')),
              ],
            ),
        ],
      ),
      body: isLoading
          ? _loadingState()
          : error != null
              ? _errorState()
              : _content(manga!, store),
    );
  }

  Widget _loadingState() => const Center(
      child: CircularProgressIndicator(color: AppTheme.accent));

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppTheme.danger),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(error!,
                  style: const TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadDetail,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white),
                child: const Text('Retry')),
          ],
        ),
      );

  Widget _content(Manga m, AppState store) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedMangaImage(
                        url: m.highQualityCoverURL, width: 110, height: 155)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary)),
                      if (m.author.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(m.author,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (m.status.isNotEmpty) _statusBadge(m.status),
                          if (m.rating.isNotEmpty)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.star,
                                  size: 12, color: AppTheme.accent),
                              const SizedBox(width: 3),
                              Text(m.rating,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12)),
                            ]),
                        ],
                      ),
                      if (m.genres.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: m.genres
                              .map((g) => Chip(
                                    label: Text(g,
                                        style: const TextStyle(
                                            color: AppTheme.accent,
                                            fontSize: 10)),
                                    backgroundColor: AppTheme.accentDim,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (firstChapter != null)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Start Reading'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.bg),
                          onPressed: _startReading,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.border),
          if (m.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('SYNOPSIS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                      letterSpacing: 2)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(m.description,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
            ),
            const Divider(color: AppTheme.border),
          ],
          if (multiSelectMode)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: Text('Download (${selectedChapters.length})'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.bg),
                      onPressed: selectedChapters.isEmpty
                          ? null
                          : _downloadSelectedChapters,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      multiSelectMode = false;
                      selectedChapters.clear();
                    }),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${m.chapters.length} CHAPTERS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 2)),
                InkWell(
                  onTap: () =>
                      setState(() => chapterSortAsc = !chapterSortAsc),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        chapterSortAsc
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 12,
                        color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(chapterSortAsc ? 'Oldest' : 'Newest',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                ),
              ],
            ),
          ),

          // ✅ hint للمستخدم
          if (!multiSelectMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Hold chapter to download or select',
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 11)),
            ),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedChapters.length,
            itemBuilder: (_, i) {
              final ch = sortedChapters[i];
              final progress = store.history.firstWhere(
                (p) =>
                    p.mangaSlug == m.slug && p.chapterSlug == ch.slug,
                orElse: () => ReadingProgress(
                    mangaSlug: '',
                    mangaTitle: '',
                    mangaCover: '',
                    chapterSlug: '',
                    chapterNumber: '',
                    pageIndex: 0),
              );
              final isDownloaded = _dm.isDownloaded(m.slug, ch.slug);
              final isDownloading = downloadingChapters.contains(ch.slug) ||
                  _dm.isDownloading(m.slug, ch.slug);

              return ListTile(
                leading: multiSelectMode
                    ? Icon(
                        selectedChapters.contains(ch.slug)
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: selectedChapters.contains(ch.slug)
                            ? AppTheme.accent
                            : AppTheme.textTertiary)
                    : null,
                title: Text('Chapter ${ch.number}',
                    style: TextStyle(
                        color: progress.mangaSlug.isNotEmpty
                            ? AppTheme.textTertiary
                            : AppTheme.textPrimary,
                        fontSize: 14)),
                subtitle: Row(children: [
                  if (progress.mangaSlug.isNotEmpty) ...[
                    Text('p.${progress.pageIndex + 1}',
                        style: const TextStyle(
                            color: AppTheme.accent, fontSize: 12)),
                    const SizedBox(width: 8),
                  ],
                  if (isDownloaded)
                    const Icon(Icons.download_done,
                        color: AppTheme.success, size: 16),
                  if (isDownloading) ...[
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent)),
                    const SizedBox(width: 4),
                    Text('${(_dm.progress(m.slug, ch.slug) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: AppTheme.textTertiary, fontSize: 11)),
                  ],
                ]),
                trailing: const Icon(Icons.chevron_right,
                    color: AppTheme.textTertiary),
                onTap: () {
                  if (multiSelectMode) {
                    setState(() {
                      if (selectedChapters.contains(ch.slug)) {
                        selectedChapters.remove(ch.slug);
                      } else {
                        selectedChapters.add(ch.slug);
                      }
                    });
                  } else {
                    _openReader(ch);
                  }
                },
                // ✅ FIX: الضغطة المطولة تفتح قائمة سياق فيها خيار التحميل
                onLongPress: multiSelectMode ? null : () => _onChapterLongPress(ch),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _statusBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: text.toLowerCase().contains('ongoing')
              ? const Color(0xFF4CAF82).withOpacity(0.12)
              : AppTheme.textTertiary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: text.toLowerCase().contains('ongoing')
                    ? const Color(0xFF4CAF82)
                    : AppTheme.textTertiary)),
      );
}
