class Manga {
  final String slug;
  final String title;
  final String coverURL;
  final List<String> genres;
  final String status;
  final String rating;
  final String description;
  final List<Chapter> chapters;
  final String author;
  final String artist;

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
    this.artist = '',
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

  Manga copyWith({
    String? slug, String? title, String? coverURL, List<String>? genres,
    String? status, String? rating, String? description, List<Chapter>? chapters,
    String? author, String? artist, String? latestChapterNumber, String? lastUpdated,
  }) => Manga(
    slug: slug ?? this.slug, title: title ?? this.title,
    coverURL: coverURL ?? this.coverURL, genres: genres ?? this.genres,
    status: status ?? this.status, rating: rating ?? this.rating,
    description: description ?? this.description, chapters: chapters ?? this.chapters,
    author: author ?? this.author, artist: artist ?? this.artist,
    latestChapterNumber: latestChapterNumber ?? this.latestChapterNumber,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );

  Map<String, dynamic> toJson() => {
    'slug': slug, 'title': title, 'coverURL': coverURL, 'genres': genres,
    'status': status, 'rating': rating, 'description': description,
    'chapters': chapters.map((c) => c.toJson()).toList(), 'author': author,
    'artist': artist, 'latestChapterNumber': latestChapterNumber, 'lastUpdated': lastUpdated,
  };

  factory Manga.fromJson(Map<String, dynamic> json) => Manga(
    slug: json['slug'] ?? '', title: json['title'] ?? '',
    coverURL: json['coverURL'] ?? '', genres: List<String>.from(json['genres'] ?? []),
    status: json['status'] ?? '', rating: json['rating'] ?? '',
    description: json['description'] ?? '', chapters: (json['chapters'] as List<dynamic>?)
        ?.map((e) => Chapter.fromJson(e)).toList() ?? [],
    author: json['author'] ?? '', artist: json['artist'] ?? '',
    latestChapterNumber: json['latestChapterNumber'], lastUpdated: json['lastUpdated'],
  );
}

class Chapter {
  final String slug;
  final String number;
  String title;
  String date;
  List<String> pages;

  Chapter({required this.slug, required this.number, this.title = '', this.date = '', this.pages = const []});

  Map<String, dynamic> toJson() => {'slug': slug, 'number': number, 'title': title, 'date': date, 'pages': pages};
  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    slug: json['slug'] ?? '', number: json['number'] ?? '',
    title: json['title'] ?? '', date: json['date'] ?? '',
    pages: List<String>.from(json['pages'] ?? []),
  );
}

class ReadingProgress {
  final String mangaSlug, mangaTitle, mangaCover, chapterSlug, chapterNumber;
  final int pageIndex;
  final DateTime lastRead;

  ReadingProgress({required this.mangaSlug, required this.mangaTitle, required this.mangaCover,
    required this.chapterSlug, required this.chapterNumber, required this.pageIndex, DateTime? lastRead})
      : lastRead = lastRead ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'mangaSlug': mangaSlug, 'mangaTitle': mangaTitle, 'mangaCover': mangaCover,
    'chapterSlug': chapterSlug, 'chapterNumber': chapterNumber,
    'pageIndex': pageIndex, 'lastRead': lastRead.toIso8601String(),
  };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
    mangaSlug: json['mangaSlug'] ?? '', mangaTitle: json['mangaTitle'] ?? '',
    mangaCover: json['mangaCover'] ?? '', chapterSlug: json['chapterSlug'] ?? '',
    chapterNumber: json['chapterNumber'] ?? '', pageIndex: json['pageIndex'] ?? 0,
    lastRead: json['lastRead'] != null ? DateTime.parse(json['lastRead']) : DateTime.now(),
  );
}

class DownloadedChapter {
  final String mangaSlug, chapterSlug, chapterNumber, mangaTitle, mangaCover;
  final List<String> pages;
  final DateTime downloadedAt;

  DownloadedChapter({required this.mangaSlug, required this.chapterSlug, required this.chapterNumber,
    required this.mangaTitle, required this.mangaCover, required this.pages, required this.downloadedAt});

  Map<String, dynamic> toJson() => {
    'mangaSlug': mangaSlug, 'chapterSlug': chapterSlug, 'chapterNumber': chapterNumber,
    'pages': pages, 'downloadedAt': downloadedAt.toIso8601String(),
  };

  factory DownloadedChapter.fromJson(Map<String, dynamic> json) => DownloadedChapter(
    mangaSlug: json['mangaSlug'], chapterSlug: json['chapterSlug'],
    chapterNumber: json['chapterNumber'], mangaTitle: json['mangaTitle'] ?? '',
    mangaCover: json['mangaCover'] ?? '', pages: List<String>.from(json['pages'] ?? []),
    downloadedAt: DateTime.parse(json['downloadedAt']),
  );
}