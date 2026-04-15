import 'package:drift/drift.dart';

/// Tracks sync-folder EPUBs whose auto-import failed so we don't retry them
/// on every sync. Device-local (not included in the sync manifest) because
/// a corrupt file on one device may be fine on another.
class SyncImportFailuresTable extends Table {
  TextColumn get fileName => text()();
  TextColumn get errorMessage => text()();
  DateTimeColumn get failedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {fileName};
}
