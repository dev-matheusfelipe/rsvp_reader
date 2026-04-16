/// URL helpers shared between the share-sheet handler, the import-article
/// dialog, and the extraction service.
abstract final class UrlUtils {
  /// Scans [raw] for the first `http://` or `https://` token. Returns null
  /// if none is found.
  ///
  /// Browsers sometimes share text like "Page Title\nhttps://…" — splitting
  /// on whitespace and picking the first URL-ish token handles that case.
  static String? extractHttpUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    for (final token in trimmed.split(RegExp(r'\s+'))) {
      if (token.startsWith('http://') || token.startsWith('https://')) {
        return token;
      }
    }
    return null;
  }

  /// Parses [raw] as a URL, inferring `https://` when no scheme is given.
  /// Returns null when the input can't be coerced into a valid absolute URL.
  static Uri? parseWithHttpsFallback(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }
}
