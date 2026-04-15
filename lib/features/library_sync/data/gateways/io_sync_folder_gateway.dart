import 'dart:io';
import 'dart:typed_data';

import '../../domain/repositories/sync_folder_gateway.dart';

/// Filesystem implementation using dart:io.
///
/// Works with plain filesystem paths. On Android this means the user must
/// pick a folder under `/storage/emulated/0` (e.g. a Drive sync folder
/// exposed there); SAF `content://` URIs are not supported in this impl.
class IoSyncFolderGateway implements SyncFolderGateway {
  const IoSyncFolderGateway();

  String _resolve(String folderPath, String relativePath) =>
      '$folderPath/$relativePath';

  @override
  Future<bool> isReadable(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return false;
    try {
      await dir.list().first.then((_) {}, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readText(String folderPath, String relativePath) async {
    final f = File(_resolve(folderPath, relativePath));
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> writeText(
      String folderPath, String relativePath, String content) async {
    final f = File(_resolve(folderPath, relativePath));
    await f.parent.create(recursive: true);
    await f.writeAsString(content, flush: true);
  }

  @override
  Future<Uint8List?> readBytes(String folderPath, String relativePath) async {
    final f = File(_resolve(folderPath, relativePath));
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> writeBytes(
      String folderPath, String relativePath, Uint8List bytes) async {
    final f = File(_resolve(folderPath, relativePath));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<bool> fileExists(String folderPath, String relativePath) {
    return File(_resolve(folderPath, relativePath)).exists();
  }

  @override
  Future<void> deleteFile(String folderPath, String relativePath) async {
    final f = File(_resolve(folderPath, relativePath));
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> listFiles(
      String folderPath, String relativePath) async {
    final dir = Directory(_resolve(folderPath, relativePath));
    if (!await dir.exists()) return const [];
    final entries = await dir.list().toList();
    final prefix = '${dir.path}/';
    return entries
        .whereType<File>()
        .map((f) => f.path.startsWith(prefix)
            ? f.path.substring(prefix.length)
            : f.path.split(Platform.pathSeparator).last)
        .toList();
  }
}
