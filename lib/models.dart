class Manga {
  final String slug;
  final String title;
  final String coverURL;
  List<String> genres;
  String status;
  String rating;
  String description;
  List<Chapter> chapters;
  String author;
  String? latestChapterNumber;
  String? lastUpdated;

  Manga({
    required this.slug,
    required this.title,
    this.coverURL = '',
    this.genres = const [],
    this.status = '',
    this.rating = '',
    this.description = '',
    this.chapters = const [],
    this.author = '',
    this.latestChapterNumber,
    this.lastUpdated,
  });

  String get highQualityCoverURL {
    final patterns = ['-110x150', '-150x200', '-200x300', '-300x450', '-193x278', '-350x476'];
    String url = coverURL;
    for (var p in patterns) {
      url = url.replaceAll(p, '');
    }
    return url;
  }

  factory Manga.fromJson(Map<String, dynamic> json) => Manga(
    slug: json['slug'] ?? '',
    title: json['title'] ?? '',
    coverURL: json['coverURL'] ?? '',
    genres: List<String>.from(json['genres'] ?? []),
    status: json['status'] ?? '',
    rating: json['rating'] ?? '',
    description: json['description'] ?? '',
    chapters: (json['chapters'] as List<dynamic>?)?.map((e) => Chapter.fromJson(e)).toList() ?? [],
    author: json['author'] ?? '',
    latestChapterNumber: json['latestChapterNumber'],
    lastUpdated: json['lastUpdated'],
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'title': title,
    'coverURL': coverURL,
    'genres': genres,
    'status': status,
    'rating': rating,
    'description': description,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'author': author,
    'latestChapterNumber': latestChapterNumber,
    'lastUpdated': lastUpdated,
  };
}

class Chapter {
  final String slug;
  final String number;
  String title;
  String date;
  List<String> pages;

  Chapter({
    required this.slug,
    required this.number,
    this.title = '',
    this.date = '',
    this.pages = const [],
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    slug: json['slug'] ?? '',
    number: json['number'] ?? '',
    title: json['title'] ?? '',
    date: json['date'] ?? '',
    pages: List<String>.from(json['pages'] ?? []),
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'number': number,
    'title': title,
    'date': date,
    'pages': pages,
  };
}

class ReadingProgress {
  final String mangaSlug;
  final String mangaTitle;
  final String mangaCover;
  final String chapterSlug;
  final String chapterNumber;
  final int pageIndex;
  final DateTime lastRead;

  ReadingProgress({
    required this.mangaSlug,
    required this.mangaTitle,
    required this.mangaCover,
    required this.chapterSlug,
    required this.chapterNumber,
    required this.pageIndex,
    DateTime? lastRead,
  }) : lastRead = lastRead ?? DateTime.now();

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
    mangaSlug: json['mangaSlug'] ?? '',
    mangaTitle: json['mangaTitle'] ?? '',
    mangaCover: json['mangaCover'] ?? '',
    chapterSlug: json['chapterSlug'] ?? '',
    chapterNumber: json['chapterNumber'] ?? '',
    pageIndex: json['pageIndex'] ?? 0,
    lastRead: json['lastRead'] != null ? DateTime.parse(json['lastRead']) : DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'mangaSlug': mangaSlug,
    'mangaTitle': mangaTitle,
    'mangaCover': mangaCover,
    'chapterSlug': chapterSlug,
    'chapterNumber': chapterNumber,
    'pageIndex': pageIndex,
    'lastRead': lastRead.toIso8601String(),
  };
}