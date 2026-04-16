import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../../../database/app_database.dart';
import '../../../../database/tables/book_source.dart';
import '../../../library_sync/presentation/providers/library_sync_provider.dart';

/// Stream of all books, sorted by last read date.
final bookLibraryProvider = StreamProvider<List<BooksTableData>>((ref) {
  final booksDao = ref.watch(booksDaoProvider);
  return booksDao.watchAllBooks();
});

/// Books grouped by reading status, each list pre-sorted for display.
class CategorizedBooks {
  final List<BooksTableData> inProgress;
  final List<BooksTableData> notStarted;
  final List<BooksTableData> read;

  const CategorizedBooks({
    required this.inProgress,
    required this.notStarted,
    required this.read,
  });

  bool get isEmpty =>
      inProgress.isEmpty && notStarted.isEmpty && read.isEmpty;
}

/// The kind of content to show in a library tab. Drives the `source` column
/// filter in [categorizedLibraryProvider] and the empty-state copy.
enum LibraryKind { books, articles }

/// Books in the library split into "in progress", "not started", and "read",
/// filtered by [LibraryKind] (books → source='epub', articles → source='article').
///
/// Sorting:
/// - inProgress: most recently read first
/// - notStarted: most recently imported first
/// - read: most recently finished first (by lastReadAt)
final categorizedLibraryProvider =
    FutureProvider.family<CategorizedBooks, LibraryKind>((ref, kind) async {
  final books = await ref.watch(bookLibraryProvider.future);
  final progressDao = ref.read(readingProgressDaoProvider);
  final tokensDao = ref.read(cachedTokensDaoProvider);

  final wantedSource =
      kind == LibraryKind.articles ? BookSource.article : BookSource.epub;
  final filtered = books.where((b) => b.source == wantedSource);

  final inProgress = <BooksTableData>[];
  final notStarted = <BooksTableData>[];
  final read = <BooksTableData>[];

  for (final book in filtered) {
    final progress = await progressDao.getProgressForBook(book.id);
    if (progress == null || book.totalWords <= 0) {
      notStarted.add(book);
      continue;
    }

    final wordsBefore = await tokensDao.getWordCountBeforeChapter(
      book.id,
      progress.chapterIndex,
    );
    final globalIdx = wordsBefore + progress.wordIndex;
    final fraction = (globalIdx / book.totalWords).clamp(0.0, 1.0);

    if (fraction >= 0.99) {
      read.add(book);
    } else {
      inProgress.add(book);
    }
  }

  // inProgress is already sorted by lastReadAt desc (from watchAllBooks).
  notStarted.sort((a, b) => b.importedAt.compareTo(a.importedAt));
  read.sort((a, b) {
    final aDate = a.lastReadAt ?? a.importedAt;
    final bDate = b.lastReadAt ?? b.importedAt;
    return bDate.compareTo(aDate);
  });

  return CategorizedBooks(
    inProgress: inProgress,
    notStarted: notStarted,
    read: read,
  );
});

/// Reading progress for a book as a fraction in [0.0, 1.0].
/// Re-evaluates whenever the book list changes (lastReadAt updates after a
/// reading session, which causes [bookLibraryProvider] to emit).
final bookProgressProvider =
    FutureProvider.family<double, String>((ref, bookId) async {
  // Recompute after each reading session.
  ref.watch(bookLibraryProvider);

  final progress =
      await ref.read(readingProgressDaoProvider).getProgressForBook(bookId);
  if (progress == null) return 0.0;

  final book = await ref.read(booksDaoProvider).getBookById(bookId);
  if (book == null || book.totalWords <= 0) return 0.0;

  final wordsBefore = await ref
      .read(cachedTokensDaoProvider)
      .getWordCountBeforeChapter(bookId, progress.chapterIndex);

  final globalIndex = wordsBefore + progress.wordIndex;
  return (globalIndex / book.totalWords).clamp(0.0, 1.0);
});

/// Delete a book and all its associated data.
final deleteBookProvider =
    Provider.family<Future<void> Function(), String>((ref, bookId) {
  return () async {
    final booksDao = ref.read(booksDaoProvider);
    final tokensDao = ref.read(cachedTokensDaoProvider);
    final progressDao = ref.read(readingProgressDaoProvider);

    await tokensDao.deleteTokensForBook(bookId);
    await progressDao.deleteProgressForBook(bookId);
    await booksDao.deleteBook(bookId);

    // Propagate deletion to the sync folder as a tombstone.
    await ref.read(librarySyncProvider.notifier).pushDelete(bookId);
  };
});

/// Jump a book's reading progress to the end so it shows up under "Read".
/// Picks the last chapter's wordCount as the cursor. If that cache row is
/// missing, derives the word count from totalWords so the library's 99%
/// threshold still flips.
final markBookAsReadProvider =
    Provider.family<Future<void> Function(), String>((ref, bookId) {
  return () async {
    final booksDao = ref.read(booksDaoProvider);
    final tokensDao = ref.read(cachedTokensDaoProvider);
    final progressDao = ref.read(readingProgressDaoProvider);

    final book = await booksDao.getBookById(bookId);
    if (book == null || book.chapterCount <= 0) return;

    final lastChapterIndex = book.chapterCount - 1;
    final lastChapter =
        await tokensDao.getTokensForChapter(bookId, lastChapterIndex);
    int lastWordIndex;
    if (lastChapter != null) {
      lastWordIndex = lastChapter.wordCount;
    } else {
      // Tokens cache missing for the last chapter — fall back to whatever
      // totalWords - (words before last chapter) gives us, so the
      // categorizedLibraryProvider's fraction computation still reaches 1.0.
      final wordsBefore =
          await tokensDao.getWordCountBeforeChapter(bookId, lastChapterIndex);
      final remaining = book.totalWords - wordsBefore;
      lastWordIndex = remaining > 0 ? remaining : book.totalWords;
    }

    final existing = await progressDao.getProgressForBook(bookId);
    await progressDao.upsertProgress(ReadingProgressTableCompanion(
      bookId: Value(bookId),
      chapterIndex: Value(lastChapterIndex),
      wordIndex: Value(lastWordIndex),
      wpm: Value(existing?.wpm ?? AppConstants.defaultWpm),
      updatedAt: Value(DateTime.now()),
    ));
    await booksDao.updateLastReadAt(bookId);

    // Push updated progress to the sync folder.
    ref.read(librarySyncProvider.notifier).schedulePush();
  };
});
