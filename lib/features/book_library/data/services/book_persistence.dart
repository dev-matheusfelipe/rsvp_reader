import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../database/app_database.dart';
import '../../../../database/daos/books_dao.dart';
import '../../../../database/daos/cached_tokens_dao.dart';
import '../../../../database/tables/book_source.dart';
import '../../../epub_import/domain/entities/parsed_book.dart';

/// Inserts a [ParsedBook] and all its tokenized chapters. Shared between
/// the EPUB and article import pipelines — both produce a `ParsedBook` and
/// then need the same Book row + per-chapter cached-tokens fan-out.
///
/// Returns the generated book id.
Future<String> persistParsedBook({
  required ParsedBook book,
  required BooksDao booksDao,
  required CachedTokensDao tokensDao,
  String source = BookSource.epub,
  String? id,
  String? filePath,
  String? syncFileName,
  String? sourceUrl,
  String? siteName,
  Uint8List? coverImage,
}) async {
  final bookId = id ?? const Uuid().v4();
  final effectiveCover = coverImage ?? book.coverImage;

  await booksDao.insertBook(BooksTableCompanion.insert(
    id: bookId,
    title: book.title,
    author: book.author.isEmpty ? const Value.absent() : Value(book.author),
    filePath: filePath ?? '',
    coverImage: Value(effectiveCover),
    totalWords: Value(book.totalWords),
    chapterCount: Value(book.chapters.length),
    importedAt: DateTime.now(),
    syncFileName: Value(syncFileName),
    source: Value(source),
    sourceUrl: Value(sourceUrl),
    siteName: Value(siteName),
  ));

  for (int i = 0; i < book.chapters.length; i++) {
    final chapter = book.chapters[i];
    final tokensJson = jsonEncode(
      chapter.tokens.map((t) => t.toJson()).toList(),
    );
    await tokensDao.insertChapterTokens(CachedTokensTableCompanion.insert(
      bookId: bookId,
      chapterIndex: i,
      chapterTitle: Value(chapter.title),
      tokensJson: tokensJson,
      wordCount: chapter.tokens.length,
      paragraphCount: Value(
        chapter.tokens.isEmpty ? 0 : chapter.tokens.last.paragraphIndex + 1,
      ),
    ));
  }

  return bookId;
}
