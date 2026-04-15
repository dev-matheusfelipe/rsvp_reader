import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_reader/features/library_sync/domain/entities/sync_library.dart';

DateTime _t(int offsetSec) =>
    DateTime.utc(2026, 1, 1).add(Duration(seconds: offsetSec));

SyncLibraryBook _book({
  required String id,
  String title = 'Book',
  int totalWords = 1000,
  DateTime? importedAt,
  DateTime? lastReadAt,
  bool hasEpubFile = false,
  String? syncFileName,
  SyncLibraryProgress? progress,
  DateTime? deletedAt,
  required int updatedAtSec,
}) {
  return SyncLibraryBook(
    id: id,
    title: title,
    author: 'Author',
    totalWords: totalWords,
    chapterCount: 5,
    importedAt: importedAt ?? _t(0),
    lastReadAt: lastReadAt,
    hasEpubFile: hasEpubFile,
    syncFileName: syncFileName,
    progress: progress,
    deletedAt: deletedAt,
    updatedAt: _t(updatedAtSec),
  );
}

SyncLibraryProgress _progress({
  int chapter = 0,
  int word = 0,
  int wpm = 300,
  required int atSec,
}) {
  return SyncLibraryProgress(
    chapterIndex: chapter,
    wordIndex: word,
    wpm: wpm,
    updatedAt: _t(atSec),
  );
}

void main() {
  group('mergeProgress', () {
    test('takes the non-null when one side is null', () {
      final p = _progress(chapter: 1, word: 10, atSec: 100);
      expect(mergeProgress(null, p), equals(p));
      expect(mergeProgress(p, null), equals(p));
    });

    test('last-write-wins when timestamps differ by more than 60s', () {
      final older = _progress(chapter: 5, word: 500, atSec: 0);
      final newer = _progress(chapter: 0, word: 10, atSec: 120);
      expect(mergeProgress(older, newer), newer);
      expect(mergeProgress(newer, older), newer);
    });

    test('within 60s prefers higher progress (wordIndex tiebreaker)', () {
      final a = _progress(chapter: 2, word: 100, atSec: 100);
      final b = _progress(chapter: 2, word: 200, atSec: 130);
      expect(mergeProgress(a, b), b);
      expect(mergeProgress(b, a), b);
    });

    test('within 60s with different chapters prefers higher chapter', () {
      final a = _progress(chapter: 3, word: 50, atSec: 100);
      final b = _progress(chapter: 2, word: 500, atSec: 110);
      expect(mergeProgress(a, b), a);
    });
  });

  group('mergeBook', () {
    test('later updatedAt wins on title', () {
      final a = _book(id: 'x', title: 'Old', updatedAtSec: 0);
      final b = _book(id: 'x', title: 'New', updatedAtSec: 100);
      final merged = mergeBook(a, b);
      expect(merged.title, 'New');
    });

    test('earliest importedAt is preserved', () {
      final a = _book(id: 'x', importedAt: _t(0), updatedAtSec: 100);
      final b = _book(id: 'x', importedAt: _t(500), updatedAtSec: 200);
      final merged = mergeBook(a, b);
      expect(merged.importedAt, _t(0));
    });

    test('later lastReadAt wins', () {
      final a = _book(id: 'x', lastReadAt: _t(10), updatedAtSec: 100);
      final b = _book(id: 'x', lastReadAt: _t(50), updatedAtSec: 20);
      expect(mergeBook(a, b).lastReadAt, _t(50));
    });

    test('hasEpubFile is OR of both sides', () {
      final a = _book(id: 'x', hasEpubFile: true, updatedAtSec: 0);
      final b = _book(id: 'x', hasEpubFile: false, updatedAtSec: 100);
      expect(mergeBook(a, b).hasEpubFile, isTrue);
    });

    test('progress is merged with wordIndex tiebreaker', () {
      final a = _book(
        id: 'x',
        progress: _progress(chapter: 2, word: 500, atSec: 100),
        updatedAtSec: 100,
      );
      final b = _book(
        id: 'x',
        progress: _progress(chapter: 2, word: 800, atSec: 130),
        updatedAtSec: 130,
      );
      expect(mergeBook(a, b).progress!.wordIndex, 800);
    });

    test('tombstone: deletedAt on either side wins', () {
      final a = _book(id: 'x', deletedAt: _t(100), updatedAtSec: 100);
      final b = _book(id: 'x', updatedAtSec: 200);
      expect(mergeBook(a, b).deletedAt, _t(100));
    });

    test('syncFileName: propagates from whichever side has it', () {
      final a = _book(id: 'x', updatedAtSec: 0);
      final b = _book(id: 'x', syncFileName: 'moby.epub', updatedAtSec: 100);
      expect(mergeBook(a, b).syncFileName, 'moby.epub');
      expect(mergeBook(b, a).syncFileName, 'moby.epub');
    });

    test('syncFileName: newer wins when both sides set it', () {
      final a = _book(
          id: 'x', syncFileName: 'old.epub', updatedAtSec: 50);
      final b = _book(
          id: 'x', syncFileName: 'new.epub', updatedAtSec: 100);
      expect(mergeBook(a, b).syncFileName, 'new.epub');
    });
  });

  group('mergeLibraries', () {
    test('union of books by id', () {
      final a = SyncLibrary(
        updatedAt: _t(0),
        updatedBy: 'devA',
        books: [
          _book(id: 'b1', updatedAtSec: 0),
          _book(id: 'b2', updatedAtSec: 0),
        ],
      );
      final b = SyncLibrary(
        updatedAt: _t(100),
        updatedBy: 'devB',
        books: [
          _book(id: 'b2', updatedAtSec: 100),
          _book(id: 'b3', updatedAtSec: 100),
        ],
      );
      final merged = mergeLibraries(a, b, 'devMerger');
      expect(merged.books.map((x) => x.id), ['b1', 'b2', 'b3']);
      expect(merged.updatedBy, 'devMerger');
    });

    test('settings: newer updatedAt wins', () {
      final a = SyncLibrary(
        updatedAt: _t(0),
        updatedBy: 'devA',
        settings: SyncLibrarySettings(
          values: {'wpm': 250},
          updatedAt: _t(0),
        ),
        books: const [],
      );
      final b = SyncLibrary(
        updatedAt: _t(100),
        updatedBy: 'devB',
        settings: SyncLibrarySettings(
          values: {'wpm': 400},
          updatedAt: _t(100),
        ),
        books: const [],
      );
      final merged = mergeLibraries(a, b, 'd');
      expect(merged.settings!.values['wpm'], 400);
    });

    test('settings: preserves the only non-null side', () {
      final a = SyncLibrary(
        updatedAt: _t(0),
        updatedBy: 'devA',
        settings: SyncLibrarySettings(
          values: {'wpm': 250},
          updatedAt: _t(0),
        ),
        books: const [],
      );
      final b = SyncLibrary(
        updatedAt: _t(100),
        updatedBy: 'devB',
        books: const [],
      );
      final merged = mergeLibraries(a, b, 'd');
      expect(merged.settings!.values['wpm'], 250);
    });
  });

  group('JSON roundtrip', () {
    test('library serializes and deserializes', () {
      final original = SyncLibrary(
        updatedAt: _t(100),
        updatedBy: 'dev-1',
        settings: SyncLibrarySettings(
          values: {'wpm': 350, 'font': 'Inter'},
          updatedAt: _t(90),
        ),
        books: [
          _book(
            id: 'b1',
            title: 'Hello',
            progress: _progress(chapter: 1, word: 42, atSec: 80),
            lastReadAt: _t(85),
            hasEpubFile: true,
            syncFileName: 'hello.epub',
            updatedAtSec: 100,
          ),
          _book(
            id: 'b2',
            deletedAt: _t(90),
            updatedAtSec: 95,
          ),
        ],
      );
      final roundtripped = SyncLibrary.decode(original.encode());
      expect(roundtripped.books.length, 2);
      expect(roundtripped.books[0].id, 'b1');
      expect(roundtripped.books[0].progress!.wordIndex, 42);
      expect(roundtripped.books[0].hasEpubFile, isTrue);
      expect(roundtripped.books[0].syncFileName, 'hello.epub');
      expect(roundtripped.books[1].deletedAt, _t(90));
      expect(roundtripped.settings!.values['wpm'], 350);
      expect(roundtripped.updatedBy, 'dev-1');
    });
  });
}
