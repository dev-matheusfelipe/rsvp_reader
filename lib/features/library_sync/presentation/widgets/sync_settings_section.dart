import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:saf_util/saf_util.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../rsvp_reader/domain/entities/display_settings.dart';
import '../../../rsvp_reader/presentation/providers/display_settings_provider.dart';
import '../providers/library_sync_provider.dart';
import '../providers/sync_config_provider.dart';

class SyncSettingsSection extends ConsumerWidget {
  const SyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(displaySettingsProvider);
    final config = ref.watch(syncConfigProvider);
    final syncState = ref.watch(librarySyncProvider);

    final textColor = settings.wordColor;
    final mutedColor = textColor.withAlpha(160);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsSync.toUpperCase(),
          style: TextStyle(
            color: textColor.withAlpha(140),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.syncHelp,
          style: TextStyle(color: mutedColor, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        _FolderRow(settings: settings, l10n: l10n),
        const SizedBox(height: 8),
        _SyncStatusRow(settings: settings, l10n: l10n, state: syncState),
        if (config.isConfigured) ...[
          const SizedBox(height: 8),
          _toggleTile(
            context: context,
            settings: settings,
            title: l10n.syncAutoSync,
            subtitle: l10n.syncAutoSyncDesc,
            value: config.autoSync,
            onChanged: (v) =>
                ref.read(syncConfigProvider.notifier).setAutoSync(v),
          ),
          _toggleTile(
            context: context,
            settings: settings,
            title: l10n.syncEpubFiles,
            subtitle: l10n.syncEpubFilesDesc,
            value: config.syncEpubs,
            onChanged: (v) =>
                ref.read(syncConfigProvider.notifier).setSyncEpubs(v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(color: textColor.withAlpha(80)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: syncState.stage == SyncStage.syncing
                      ? null
                      : () => ref
                          .read(librarySyncProvider.notifier)
                          .triggerSync(),
                  icon: syncState.stage == SyncStage.syncing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: textColor,
                          ),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(syncState.stage == SyncStage.syncing
                      ? l10n.syncInProgress
                      : l10n.syncNow),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await ref
                      .read(syncConfigProvider.notifier)
                      .setFolderPath(null);
                },
                style: TextButton.styleFrom(foregroundColor: mutedColor),
                child: Text(l10n.syncDisconnect),
              ),
            ],
          ),
          _FailedImportsSection(settings: settings, l10n: l10n),
        ],
      ],
    );
  }

  Widget _toggleTile({
    required BuildContext context,
    required DisplaySettings settings,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      activeThumbColor: settings.orpColor,
      title: Text(title, style: TextStyle(color: settings.wordColor)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
            color: settings.wordColor.withAlpha(160), fontSize: 12),
      ),
    );
  }
}

class _FolderRow extends ConsumerWidget {
  final DisplaySettings settings;
  final AppLocalizations l10n;

  const _FolderRow({required this.settings, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(syncConfigProvider);
    final textColor = settings.wordColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: textColor.withAlpha(60)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, color: textColor.withAlpha(180), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.syncFolderLabel,
                  style: TextStyle(
                    color: textColor.withAlpha(140),
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _prettyPath(config.folderPath) ?? l10n.syncNoFolderSelected,
                  style: TextStyle(color: textColor, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickFolder(context, ref),
            style: TextButton.styleFrom(foregroundColor: settings.orpColor),
            child: Text(l10n.syncChooseFolder),
          ),
        ],
      ),
    );
  }

  String? _prettyPath(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('content://')) return raw;
    // SAF tree URI looks like:
    //   content://<authority>/tree/primary%3ADocuments%2FRSVP
    // Decode the last path segment so the user sees "primary:Documents/RSVP".
    try {
      final uri = Uri.parse(raw);
      final last = uri.pathSegments.isEmpty ? raw : uri.pathSegments.last;
      return Uri.decodeComponent(last);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    String? path;
    if (Platform.isAndroid) {
      // Use SAF so the user can pick folders from any installed storage
      // provider (Google Drive, Dropbox, OneDrive, local storage) and we get
      // a persistable URI we can write to across app restarts.
      final doc = await SafUtil().pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      path = doc?.uri;
    } else {
      path = await FilePicker.platform.getDirectoryPath();
    }
    if (path == null || path.isEmpty) return;
    await ref.read(syncConfigProvider.notifier).setFolderPath(path);
    // Kick off an initial sync right after picking.
    if (context.mounted) {
      await ref.read(librarySyncProvider.notifier).triggerSync();
    }
  }
}

class _FailedImportsSection extends ConsumerWidget {
  final DisplaySettings settings;
  final AppLocalizations l10n;

  const _FailedImportsSection({required this.settings, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failuresAsync = ref.watch(syncImportFailuresProvider);
    return failuresAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (failures) {
        if (failures.isEmpty) return const SizedBox.shrink();
        final textColor = settings.wordColor;
        final mutedColor = textColor.withAlpha(160);
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    l10n.syncFailedImportsTitle(failures.length),
                    style: TextStyle(
                      color: textColor.withAlpha(200),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.syncFailedImportsHelp,
                style:
                    TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 8),
              for (final f in failures)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.fileName,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.errorMessage,
                              style: TextStyle(
                                color: mutedColor,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(librarySyncProvider.notifier)
                              .retryFailedImport(f.fileName);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: settings.orpColor,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(l10n.syncRetry),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final DisplaySettings settings;
  final AppLocalizations l10n;
  final LibrarySyncState state;

  const _SyncStatusRow({
    required this.settings,
    required this.l10n,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final mutedColor = settings.wordColor.withAlpha(160);

    if (state.stage == SyncStage.error && state.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          l10n.syncFailed(state.errorMessage!),
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
      );
    }

    final lastLabel = state.lastSyncedAt != null
        ? DateFormat.yMMMd().add_Hm().format(state.lastSyncedAt!.toLocal())
        : l10n.syncNever;

    return Text(
      l10n.syncLastSyncedAt(lastLabel),
      style: TextStyle(color: mutedColor, fontSize: 12),
    );
  }
}
