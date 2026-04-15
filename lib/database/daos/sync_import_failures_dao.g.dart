// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_import_failures_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncImportFailuresDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncImportFailuresTableTable get syncImportFailuresTable =>
      attachedDatabase.syncImportFailuresTable;
  SyncImportFailuresDaoManager get managers =>
      SyncImportFailuresDaoManager(this);
}

class SyncImportFailuresDaoManager {
  final _$SyncImportFailuresDaoMixin _db;
  SyncImportFailuresDaoManager(this._db);
  $$SyncImportFailuresTableTableTableManager get syncImportFailuresTable =>
      $$SyncImportFailuresTableTableTableManager(
        _db.attachedDatabase,
        _db.syncImportFailuresTable,
      );
}
