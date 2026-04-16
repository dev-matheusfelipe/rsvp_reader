import 'package:drift/drift.dart';

import 'daos/books_dao.dart';
import 'daos/cached_tokens_dao.dart';
import 'daos/reading_progress_dao.dart';
import 'daos/sync_import_failures_dao.dart';
import 'tables/books_table.dart';
import 'tables/cached_tokens_table.dart';
import 'tables/reading_progress_table.dart';
import 'tables/sync_import_failures_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    BooksTable,
    ReadingProgressTable,
    CachedTokensTable,
    SyncImportFailuresTable,
  ],
  daos: [
    BooksDao,
    ReadingProgressDao,
    CachedTokensDao,
    SyncImportFailuresDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(booksTable, booksTable.syncFileName);
          }
          if (from < 3) {
            await m.createTable(syncImportFailuresTable);
          }
          if (from < 4) {
            await m.addColumn(booksTable, booksTable.source);
            await m.addColumn(booksTable, booksTable.sourceUrl);
            await m.addColumn(booksTable, booksTable.siteName);
          }
        },
      );
}
