class SyncConfig {
  final String? folderPath;
  final bool syncEpubs;
  final bool autoSync;
  final String deviceId;
  final DateTime? lastSyncedAt;

  const SyncConfig({
    this.folderPath,
    this.syncEpubs = true,
    this.autoSync = true,
    required this.deviceId,
    this.lastSyncedAt,
  });

  bool get isConfigured => folderPath != null && folderPath!.isNotEmpty;
  bool get isActive => isConfigured && autoSync;

  SyncConfig copyWith({
    String? folderPath,
    bool? clearFolderPath,
    bool? syncEpubs,
    bool? autoSync,
    String? deviceId,
    DateTime? lastSyncedAt,
    bool? clearLastSyncedAt,
  }) {
    return SyncConfig(
      folderPath: (clearFolderPath ?? false) ? null : (folderPath ?? this.folderPath),
      syncEpubs: syncEpubs ?? this.syncEpubs,
      autoSync: autoSync ?? this.autoSync,
      deviceId: deviceId ?? this.deviceId,
      lastSyncedAt: (clearLastSyncedAt ?? false)
          ? null
          : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }
}
