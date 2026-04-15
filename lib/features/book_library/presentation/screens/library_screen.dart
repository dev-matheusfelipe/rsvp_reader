import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../database/app_database.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../epub_import/presentation/providers/epub_import_provider.dart';
import '../../../library_sync/presentation/providers/library_sync_provider.dart';
import '../../../library_sync/presentation/providers/sync_config_provider.dart';
import '../providers/book_library_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final libraryAsync = ref.watch(categorizedLibraryProvider);
    final importState = ref.watch(epubImportProvider);

    // Show snackbar if sync fails (only transitions into error).
    ref.listen<LibrarySyncState>(librarySyncProvider, (prev, next) {
      if (next.stage == SyncStage.error &&
          prev?.stage != SyncStage.error &&
          next.errorMessage != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.syncFailed(next.errorMessage!)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
      }
    });

    // React to import state changes: navigate on success, show snackbar on error.
    ref.listen(epubImportProvider, (prev, next) {
      if (next.status == ImportStatus.done && next.importedBookId != null) {
        context.push('/reader/${next.importedBookId}');
        ref.read(epubImportProvider.notifier).reset();
      } else if (next.status == ImportStatus.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.importError),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        ref.read(epubImportProvider.notifier).reset();
      }
    });

    final syncState = ref.watch(librarySyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: syncState.isImporting
            ? _ImportProgressBar(
                current: syncState.importCurrent ?? 0,
                total: syncState.importTotal ?? 0,
                fileName: syncState.importFileName ?? '',
                l10n: l10n,
              )
            : null,
      ),
      body: libraryAsync.when(
        data: (categorized) {
          final syncConfigured = ref.watch(syncConfigProvider).isConfigured;
          final scroll = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: categorized.isEmpty
                ? [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(context, l10n),
                    ),
                  ]
                : [
                    _buildSection(
                      context,
                      ref,
                      l10n,
                      title: l10n.librarySectionInProgress,
                      books: categorized.inProgress,
                    ),
                    _buildSection(
                      context,
                      ref,
                      l10n,
                      title: l10n.librarySectionNotStarted,
                      books: categorized.notStarted,
                    ),
                    _buildSection(
                      context,
                      ref,
                      l10n,
                      title: l10n.librarySectionRead,
                      books: categorized.read,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
          );

          if (!syncConfigured) return scroll;
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(librarySyncProvider.notifier).triggerSync(),
            child: scroll,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importState.status == ImportStatus.processing
            ? null
            : () => ref.read(epubImportProvider.notifier).importFromFilePicker(),
        icon: importState.status == ImportStatus.processing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
        label: Text(
          importState.status == ImportStatus.processing
              ? l10n.importing
              : l10n.importBook,
        ),
      ),
    );
  }

  /// Renders a section header + grid for the given list of books.
  /// Returns an empty sliver if the list is empty.
  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n, {
    required String title,
    required List<BooksTableData> books,
  }) {
    if (books.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withAlpha(204),
                ),
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final book = books[index];
                return BookCard(
                  book: book,
                  onTap: () => context.push('/reader/${book.id}'),
                  onLongPress: () => _showBookActions(
                    context,
                    ref,
                    book.id,
                    book.title,
                    l10n,
                  ),
                );
              },
              childCount: books.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(77),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.emptyLibrary,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.emptyLibrarySubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
          ),
        ],
      ),
    );
  }

  void _showBookActions(
    BuildContext context,
    WidgetRef ref,
    String bookId,
    String title,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  title,
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(l10n.markAsRead),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  await ref.read(markBookAsReadProvider(bookId))();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(l10n.markedAsRead(title)),
                        behavior: SnackBarBehavior.floating,
                      ));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmDelete(context, ref, bookId, title, l10n);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String bookId,
    String title,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteBook),
        content: Text(l10n.deleteBookConfirm(title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(deleteBookProvider(bookId))();
            },
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressBar extends StatelessWidget implements PreferredSizeWidget {
  final int current;
  final int total;
  final String fileName;
  final AppLocalizations l10n;

  const _ImportProgressBar({
    required this.current,
    required this.total,
    required this.fileName,
    required this.l10n,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    final displayName = fileName.isEmpty ? '…' : fileName;
    return SizedBox(
      height: preferredSize.height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: fraction == 0 ? null : fraction,
            minHeight: 2,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.syncImportingProgress(
                      current + 1 > total ? total : current + 1,
                      total,
                      displayName,
                    ),
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
