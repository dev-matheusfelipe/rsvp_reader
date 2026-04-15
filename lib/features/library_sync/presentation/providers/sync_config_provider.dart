import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/sync_config.dart';

const _prefix = 'sync_';
const _kFolderPath = '${_prefix}folderPath';
const _kSyncEpubs = '${_prefix}syncEpubs';
const _kAutoSync = '${_prefix}autoSync';
const _kDeviceId = '${_prefix}deviceId';
const _kLastSyncedAt = '${_prefix}lastSyncedAt';

class SyncConfigNotifier extends StateNotifier<SyncConfig> {
  final SharedPreferencesAsync _prefs;
  bool _loaded = false;

  SyncConfigNotifier(this._prefs) : super(const SyncConfig(deviceId: '')) {
    load();
  }

  bool get isLoaded => _loaded;

  Future<void> load() async {
    var deviceId = await _prefs.getString(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _prefs.setString(_kDeviceId, deviceId);
    }

    final folderPath = await _prefs.getString(_kFolderPath);
    final syncEpubs = await _prefs.getBool(_kSyncEpubs) ?? true;
    final autoSync = await _prefs.getBool(_kAutoSync) ?? true;
    final lastSyncedMs = await _prefs.getInt(_kLastSyncedAt);

    state = SyncConfig(
      folderPath: (folderPath == null || folderPath.isEmpty) ? null : folderPath,
      syncEpubs: syncEpubs,
      autoSync: autoSync,
      deviceId: deviceId,
      lastSyncedAt: lastSyncedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSyncedMs),
    );
    _loaded = true;
  }

  Future<void> setFolderPath(String? path) async {
    if (path == null || path.isEmpty) {
      await _prefs.remove(_kFolderPath);
      state = state.copyWith(clearFolderPath: true);
    } else {
      await _prefs.setString(_kFolderPath, path);
      state = state.copyWith(folderPath: path);
    }
  }

  Future<void> setSyncEpubs(bool value) async {
    await _prefs.setBool(_kSyncEpubs, value);
    state = state.copyWith(syncEpubs: value);
  }

  Future<void> setAutoSync(bool value) async {
    await _prefs.setBool(_kAutoSync, value);
    state = state.copyWith(autoSync: value);
  }

  Future<void> markSyncedAt(DateTime when) async {
    await _prefs.setInt(_kLastSyncedAt, when.millisecondsSinceEpoch);
    state = state.copyWith(lastSyncedAt: when);
  }
}

final syncConfigProvider =
    StateNotifierProvider<SyncConfigNotifier, SyncConfig>((ref) {
  return SyncConfigNotifier(SharedPreferencesAsync());
});
