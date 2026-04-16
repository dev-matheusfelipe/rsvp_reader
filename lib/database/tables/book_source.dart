/// Values for [BooksTable.source]. Kept as plain string constants (not an
/// enum) so they map directly to the Drift text column without a converter.
abstract final class BookSource {
  static const String epub = 'epub';
  static const String article = 'article';
}
