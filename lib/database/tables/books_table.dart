import 'package:drift/drift.dart';

class BooksTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get filePath => text()();
  BlobColumn get coverImage => blob().nullable()();
  IntColumn get totalWords => integer().withDefault(const Constant(0))();
  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get importedAt => dateTime()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();

  /// Filename used when storing this book's EPUB in the sync folder. We keep
  /// the user's original filename (with numeric suffix to disambiguate
  /// collisions) instead of the UUID so the folder is browsable.
  /// Null for books imported before the sync-filename feature landed.
  TextColumn get syncFileName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
