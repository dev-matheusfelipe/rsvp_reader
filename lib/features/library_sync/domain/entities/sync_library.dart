import 'dart:convert';

const syncSchemaVersion = 1;

class SyncLibraryProgress {
  final int chapterIndex;
  final int wordIndex;
  final int wpm;
  final DateTime updatedAt;

  const SyncLibraryProgress({
    required this.chapterIndex,
    required this.wordIndex,
    required this.wpm,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'chapterIndex': chapterIndex,
        'wordIndex': wordIndex,
        'wpm': wpm,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory SyncLibraryProgress.fromJson(Map<String, dynamic> json) =>
      SyncLibraryProgress(
        chapterIndex: json['chapterIndex'] as int,
        wordIndex: json['wordIndex'] as int,
        wpm: json['wpm'] as int,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SyncLibraryBook {
  final String id;
  final String title;
  final String? author;
  final int totalWords;
  final int chapterCount;
  final DateTime importedAt;
  final DateTime? lastReadAt;
  final bool hasEpubFile;
  final String? syncFileName;
  final SyncLibraryProgress? progress;
  final DateTime? deletedAt;
  final DateTime updatedAt;

  const SyncLibraryBook({
    required this.id,
    required this.title,
    this.author,
    required this.totalWords,
    required this.chapterCount,
    required this.importedAt,
    this.lastReadAt,
    required this.hasEpubFile,
    this.syncFileName,
    this.progress,
    this.deletedAt,
    required this.updatedAt,
  });

  SyncLibraryBook copyWith({
    String? title,
    String? author,
    int? totalWords,
    int? chapterCount,
    DateTime? importedAt,
    DateTime? lastReadAt,
    bool? hasEpubFile,
    String? syncFileName,
    SyncLibraryProgress? progress,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) {
    return SyncLibraryBook(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      totalWords: totalWords ?? this.totalWords,
      chapterCount: chapterCount ?? this.chapterCount,
      importedAt: importedAt ?? this.importedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      hasEpubFile: hasEpubFile ?? this.hasEpubFile,
      syncFileName: syncFileName ?? this.syncFileName,
      progress: progress ?? this.progress,
      deletedAt: deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'totalWords': totalWords,
        'chapterCount': chapterCount,
        'importedAt': importedAt.toUtc().toIso8601String(),
        'lastReadAt': lastReadAt?.toUtc().toIso8601String(),
        'hasEpubFile': hasEpubFile,
        'syncFileName': syncFileName,
        'progress': progress?.toJson(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory SyncLibraryBook.fromJson(Map<String, dynamic> json) =>
      SyncLibraryBook(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String?,
        totalWords: json['totalWords'] as int? ?? 0,
        chapterCount: json['chapterCount'] as int? ?? 0,
        importedAt: DateTime.parse(json['importedAt'] as String),
        lastReadAt: json['lastReadAt'] == null
            ? null
            : DateTime.parse(json['lastReadAt'] as String),
        hasEpubFile: json['hasEpubFile'] as bool? ?? false,
        syncFileName: json['syncFileName'] as String?,
        progress: json['progress'] == null
            ? null
            : SyncLibraryProgress.fromJson(
                json['progress'] as Map<String, dynamic>),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SyncLibrarySettings {
  final Map<String, dynamic> values;
  final DateTime updatedAt;

  const SyncLibrarySettings({
    required this.values,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'values': values,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory SyncLibrarySettings.fromJson(Map<String, dynamic> json) =>
      SyncLibrarySettings(
        values: Map<String, dynamic>.from(json['values'] as Map),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class SyncLibrary {
  final int schemaVersion;
  final DateTime updatedAt;
  final String updatedBy;
  final SyncLibrarySettings? settings;
  final List<SyncLibraryBook> books;

  const SyncLibrary({
    this.schemaVersion = syncSchemaVersion,
    required this.updatedAt,
    required this.updatedBy,
    this.settings,
    required this.books,
  });

  factory SyncLibrary.empty(String deviceId) => SyncLibrary(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedBy: deviceId,
        books: const [],
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'updatedBy': updatedBy,
        'settings': settings?.toJson(),
        'books': books.map((b) => b.toJson()).toList(),
      };

  factory SyncLibrary.fromJson(Map<String, dynamic> json) => SyncLibrary(
        schemaVersion: json['schemaVersion'] as int? ?? syncSchemaVersion,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        updatedBy: json['updatedBy'] as String? ?? '',
        settings: json['settings'] == null
            ? null
            : SyncLibrarySettings.fromJson(
                json['settings'] as Map<String, dynamic>),
        books: (json['books'] as List? ?? const [])
            .map((b) => SyncLibraryBook.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SyncLibrary.decode(String raw) =>
      SyncLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Merge two books by their per-field updatedAt.
/// Returns the merged book. Caller must pass books with the same id.
SyncLibraryBook mergeBook(SyncLibraryBook a, SyncLibraryBook b) {
  assert(a.id == b.id);
  final newer = a.updatedAt.isAfter(b.updatedAt) ? a : b;
  final older = identical(newer, a) ? b : a;

  final mergedProgress = mergeProgress(a.progress, b.progress);
  final mergedDeletedAt = _laterNullable(a.deletedAt, b.deletedAt);

  return SyncLibraryBook(
    id: a.id,
    title: newer.title,
    author: newer.author ?? older.author,
    totalWords: newer.totalWords != 0 ? newer.totalWords : older.totalWords,
    chapterCount:
        newer.chapterCount != 0 ? newer.chapterCount : older.chapterCount,
    importedAt: _earlier(a.importedAt, b.importedAt),
    lastReadAt: _laterNullable(a.lastReadAt, b.lastReadAt),
    hasEpubFile: a.hasEpubFile || b.hasEpubFile,
    syncFileName: newer.syncFileName ?? older.syncFileName,
    progress: mergedProgress,
    deletedAt: mergedDeletedAt,
    updatedAt: _later(a.updatedAt, b.updatedAt),
  );
}

/// Merge progress records. LWW by updatedAt, with a 60s tiebreaker:
/// if timestamps are within 60s of each other, prefer the larger wordIndex
/// so progress never goes backwards.
SyncLibraryProgress? mergeProgress(
  SyncLibraryProgress? a,
  SyncLibraryProgress? b,
) {
  if (a == null) return b;
  if (b == null) return a;

  final diff = a.updatedAt.difference(b.updatedAt).abs();
  if (diff.inSeconds <= 60) {
    return _globalOrder(a) >= _globalOrder(b) ? a : b;
  }
  return a.updatedAt.isAfter(b.updatedAt) ? a : b;
}

/// Orders progress records without knowledge of chapter word counts:
/// chapterIndex dominates, wordIndex breaks ties.
int _globalOrder(SyncLibraryProgress p) => p.chapterIndex * 1000000 + p.wordIndex;

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

DateTime? _laterNullable(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _later(a, b);
}

/// Merge two libraries. Result contains the union of books, each merged,
/// and the newer of the two settings snapshots.
SyncLibrary mergeLibraries(SyncLibrary a, SyncLibrary b, String deviceId) {
  final byId = <String, SyncLibraryBook>{};
  for (final book in a.books) {
    byId[book.id] = book;
  }
  for (final book in b.books) {
    final existing = byId[book.id];
    byId[book.id] = existing == null ? book : mergeBook(existing, book);
  }

  SyncLibrarySettings? settings;
  if (a.settings == null) {
    settings = b.settings;
  } else if (b.settings == null) {
    settings = a.settings;
  } else {
    settings = a.settings!.updatedAt.isAfter(b.settings!.updatedAt)
        ? a.settings
        : b.settings;
  }

  return SyncLibrary(
    updatedAt: _later(a.updatedAt, b.updatedAt),
    updatedBy: deviceId,
    settings: settings,
    books: byId.values.toList()..sort((x, y) => x.id.compareTo(y.id)),
  );
}
