class MangaChapter {
  final String id;
  final String chapterNumber;
  final String title;
  final String? volume;
  final String? releaseDate;
  final String? scanlationGroup;
  final int totalPages;
  bool isRead;
  int lastPage;
  final String? url;
  final String? source;

  MangaChapter({
    required this.id,
    required this.chapterNumber,
    required this.title,
    this.volume,
    this.releaseDate,
    this.scanlationGroup,
    this.totalPages = 0,
    this.isRead = false,
    this.lastPage = 0,
    this.url,
    this.source,
  });

  String get displayTitle {
    if (title.isNotEmpty && title != chapterNumber) {
      return "Ch. $chapterNumber - $title";
    }
    return "Chapter $chapterNumber";
  }

  factory MangaChapter.fromJson(Map<String, dynamic> json) {
    return MangaChapter(
      id: json['id'] ?? '',
      chapterNumber: json['chapterNumber'] ?? '1',
      title: json['title'] ?? '',
      volume: json['volume'],
      releaseDate: json['releaseDate'],
      scanlationGroup: json['scanlationGroup'],
      totalPages: json['totalPages'] ?? 0,
      isRead: json['isRead'] ?? false,
      lastPage: json['lastPage'] ?? 0,
      url: json['url']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapterNumber': chapterNumber,
    'title': title,
    'volume': volume,
    'releaseDate': releaseDate,
    'scanlationGroup': scanlationGroup,
    'totalPages': totalPages,
    'isRead': isRead,
    'lastPage': lastPage,
    if (url != null) 'url': url,
    if (source != null) 'source': source,
  };
}
