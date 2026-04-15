import '../../database/daos/books_dao.dart';

const _fallbackName = 'book.epub';

/// Returns a sync-folder filename based on [desired] that does not collide
/// with any existing book's syncFileName in [booksDao]. On collision,
/// appends " (2)", " (3)", … before the extension.
Future<String> uniqueSyncFileName({
  required String desired,
  required BooksDao booksDao,
}) async {
  var sanitized = _sanitize(desired);
  if (sanitized.isEmpty) sanitized = _fallbackName;

  final books = await booksDao.getAllBooks();
  final taken = books
      .map((b) => b.syncFileName)
      .whereType<String>()
      .toSet();

  if (!taken.contains(sanitized)) return sanitized;

  final (base, ext) = _splitBaseExt(sanitized);

  for (int i = 2; i < 10000; i++) {
    final candidate = '$base ($i)$ext';
    if (!taken.contains(candidate)) return candidate;
  }
  // Extremely unlikely fallback.
  return '$base (${DateTime.now().millisecondsSinceEpoch})$ext';
}

/// Splits a filename into (base, extension) where the extension includes
/// the leading dot. Handles:
///   "moby.epub"  → ("moby", ".epub")
///   "moby"       → ("moby", "")
///   ".epub"      → ("", ".epub")   // dotfile: whole string is extension
///   "a.b.c"      → ("a.b", ".c")
(String, String) _splitBaseExt(String name) {
  final lastDot = name.lastIndexOf('.');
  if (lastDot < 0) return (name, '');
  if (lastDot == 0) return ('', name);
  return (name.substring(0, lastDot), name.substring(lastDot));
}

/// Strips path separators and control characters that would cause issues
/// when the name is used as a filename in the sync folder.
String _sanitize(String name) {
  return name
      .replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_')
      .trim();
}
