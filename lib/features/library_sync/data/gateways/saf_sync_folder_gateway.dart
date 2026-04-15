import 'dart:convert';
import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../../domain/repositories/sync_folder_gateway.dart';

/// Android SAF-backed gateway.
///
/// [folderPath] is a `content://` tree URI previously returned by
/// [SafUtil.pickDirectory] with persistable write permission. All paths are
/// resolved relative to that tree URI; nested directories are created on
/// demand during writes.
class SafSyncFolderGateway implements SyncFolderGateway {
  final SafUtil _util;
  final SafStream _stream;

  SafSyncFolderGateway({SafUtil? util, SafStream? stream})
      : _util = util ?? SafUtil(),
        _stream = stream ?? SafStream();

  List<String> _split(String relativePath) {
    return relativePath.split('/').where((p) => p.isNotEmpty).toList();
  }

  String _mimeFor(String fileName) {
    if (fileName.endsWith('.json')) return 'application/json';
    if (fileName.endsWith('.epub')) return 'application/epub+zip';
    return 'application/octet-stream';
  }

  @override
  Future<bool> isReadable(String folderPath) async {
    try {
      final doc = await _util.stat(folderPath, true);
      return doc != null && doc.isDir;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readText(String folderPath, String relativePath) async {
    final bytes = await readBytes(folderPath, relativePath);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeText(
      String folderPath, String relativePath, String content) async {
    await writeBytes(
        folderPath, relativePath, Uint8List.fromList(utf8.encode(content)));
  }

  @override
  Future<Uint8List?> readBytes(String folderPath, String relativePath) async {
    final parts = _split(relativePath);
    if (parts.isEmpty) return null;
    final doc = await _util.child(folderPath, parts);
    if (doc == null || doc.isDir) return null;
    return _stream.readFileBytes(doc.uri);
  }

  @override
  Future<void> writeBytes(
      String folderPath, String relativePath, Uint8List bytes) async {
    final parts = _split(relativePath);
    if (parts.isEmpty) {
      throw ArgumentError('Cannot write to an empty relative path');
    }
    final fileName = parts.last;
    final dirParts = parts.sublist(0, parts.length - 1);

    final String parentUri;
    if (dirParts.isEmpty) {
      parentUri = folderPath;
    } else {
      final parent = await _util.mkdirp(folderPath, dirParts);
      parentUri = parent.uri;
    }

    await _stream.writeFileBytes(
      parentUri,
      fileName,
      _mimeFor(fileName),
      bytes,
      overwrite: true,
    );
  }

  @override
  Future<bool> fileExists(String folderPath, String relativePath) async {
    final parts = _split(relativePath);
    if (parts.isEmpty) return false;
    final doc = await _util.child(folderPath, parts);
    return doc != null && !doc.isDir;
  }

  @override
  Future<void> deleteFile(String folderPath, String relativePath) async {
    final parts = _split(relativePath);
    if (parts.isEmpty) return;
    final doc = await _util.child(folderPath, parts);
    if (doc == null || doc.isDir) return;
    await _util.delete(doc.uri, false);
  }

  @override
  Future<List<String>> listFiles(
      String folderPath, String relativePath) async {
    final parts = _split(relativePath);
    String dirUri;
    if (parts.isEmpty) {
      dirUri = folderPath;
    } else {
      final doc = await _util.child(folderPath, parts);
      if (doc == null || !doc.isDir) return const [];
      dirUri = doc.uri;
    }
    final children = await _util.list(dirUri);
    return children.where((c) => !c.isDir).map((c) => c.name).toList();
  }
}
