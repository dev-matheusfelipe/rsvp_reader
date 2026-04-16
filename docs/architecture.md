# Architecture

## Pattern

Feature-based Clean Architecture with internal layers per feature:

- `domain/entities/` — pure models (freezed or plain Dart)
- `data/` — services and repository implementations
- `presentation/` — providers (Riverpod), screens, and widgets

---

## Features and Responsibilities

### book_library
Main screen. Displays a grid of imported books with cover, title, and progress. Includes a FAB to import EPUB files. Uses a reactive DB stream (`watchAllBooks`).

---

### epub_import
Pipeline:

EPUB bytes → `epub_pro` → chapters → `HtmlStripper` → `TextTokenizer` → `List<WordToken>` → cached in SQLite

Each `WordToken` already includes precomputed `orpIndex` and `timingMultiplier`, ensuring zero computation during the RSVP loop.

`HtmlStripper` maintains three tag sets:

- `_blockTags` — generate paragraph breaks  
- `_breakTags` — (`br`, `hr`) generate line breaks  
- `_skipTags` — (`style`, `script`, `noscript`, `head`, `meta`, `link`, `title`, `object`, `embed`, `svg`, `iframe`, `template`) — entire subtree is ignored to prevent CSS/JS leakage into the text  

---

### rsvp_reader
Core feature. Contains:

- **RsvpEngineNotifier** (`rsvp_engine_provider.dart`)  
  Ticker-based engine. Controls play/pause/seek/speed/ramp-up and `ReaderMode` (rsvp/scroll/ereader).  
  Methods like `enterEreaderMode`, `exitEreaderMode`, and `toggleEreaderMode` manage the third mode.  
  Saves reading progress on pause and when entering ereader mode.

- **RsvpWordDisplay** (`rsvp_word_display.dart`)  
  Renders words with ORP using `RichText` + `TextSpan`.  
  Supports auto-scaling for long words and configurable positioning.  
  Optionally renders a **focus line** below the word (full-width, edge-to-edge), either standalone or combined with a progress bar.

- **ContextScrollView** (`context_scroll_view.dart`)  
  Scroll mode. Virtualized list of all chapters (headers + paragraphs).  
  Highlights the current word with a rounded "pill" and subtle glow.  
  Uses a local `ValueNotifier` (not Riverpod) for scroll updates and implements **velocity-based stepping** (word/sentence/paragraph).  
  Syncs with the engine only when scrolling ends.  
  Supports `showHighlight: false` for ereader mode (no pill, no tap-to-seek).

- **RsvpControls** (`rsvp_controls.dart`)  
  Includes play/pause, skip, seek slider with **chapter markers** (visual-only via `IgnorePointer`),  
  and a value indicator showing chapter title during drag.  
  Also includes WPM controls and chapter navigation.  
  Hidden in ereader mode.

- **DisplaySettingsPanel** (`display_settings_panel.dart`)  
  Shared widget containing all display/reading settings.  
  Accepts optional `bookId` — if provided, updates the engine in real time.  
  Serves as the single source of truth.

- **ReaderSettingsSheet** (`reader_settings_sheet.dart`)  
  Bottom sheet (`DraggableScrollableSheet`) wrapping `DisplaySettingsPanel(bookId: ...)`.

- **ChapterListSheet** (`chapter_list_sheet.dart`)  
  Bottom sheet listing chapters for navigation.

---

### settings
Full-screen settings page that wraps `DisplaySettingsPanel()` (without `bookId`) plus an About section.  
Visually identical to the reader bottom sheet (same colors and components from `DisplaySettings`).

---

## State Management

**Riverpod 2 without code generation** (avoids `source_gen` conflicts with `drift_dev`).

Main providers:

- `appDatabaseProvider` — Drift DB instance, overridden in `main`
- `booksDaoProvider`, `readingProgressDaoProvider`, `cachedTokensDaoProvider` — DAOs
- `rsvpEngineProvider(bookId)` — `StateNotifierProvider.family`, RSVP engine per book
- `displaySettingsProvider` — persisted `DisplaySettings` via `SharedPreferences`
- `bookLibraryProvider` — `StreamProvider` with book list
- `epubImportProvider` — `StateNotifier` for import flow

---

## Database (Drift/SQLite)

3 tables:

- `BooksTable` — metadata (id, title, author, filePath, coverImage, totalWords, chapterCount, importedAt, lastReadAt)
- `ReadingProgressTable` — per-book position (bookId PK, chapterIndex, wordIndex, wpm, updatedAt)
- `CachedTokensTable` — preprocessed tokens per chapter (bookId, chapterIndex, chapterTitle, tokensJson, wordCount, paragraphCount)

Tokens are serialized as JSON in SQLite.  
Approximately 2–3MB for a 100K-word book.

---

## Data Flow

**Import Flow:**
EPUB file → epub_pro → HtmlStripper → TextTokenizer → WordToken[] → SQLite cache

**Reading Flow:**
SQLite cache → Chapter[] → RsvpEngine (Ticker) → RsvpWordDisplay / ContextScrollView

**Configuration Flow:**
SharedPreferences ↔ DisplaySettingsNotifier ↔ RsvpEngine.displaySettings

---

## i18n

Localization is managed using ARB files located in `lib/l10n/` (`app_en.arb`, `app_pt.arb`).

Generated files are located in `lib/l10n/generated/`.

Import:

```dart
import '...l10n/generated/app_localizations.dart';
