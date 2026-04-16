import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../database/app_database.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../article_import/presentation/providers/article_import_provider.dart';
import '../../../article_import/presentation/widgets/import_article_dialog.dart';
import '../../../epub_import/presentation/providers/epub_import_provider.dart';
import '../../../library_sync/presentation/providers/library_sync_provider.dart';
import '../../../library_sync/presentation/providers/sync_config_provider.dart';
import '../providers/book_library_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final importState = ref.watch(epubImportProvider);
    final articleImportState = ref.watch(articleImportProvider);

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

    // Article-import navigation + error snackbars are handled globally in
    // `_ArticleImportCoordinator` (app.dart) so share-sheet imports work
    // from any screen, not just the library.

    final syncState = ref.watch(librarySyncProvider);
    final onArticlesTab = _tabController.index == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: _AppBarBottom(
          tabController: _tabController,
          l10n: l10n,
          syncState: syncState,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LibraryList(kind: LibraryKind.books),
          _LibraryList(kind: LibraryKind.articles),
        ],
      ),
      floatingActionButton: _buildFab(
        l10n: l10n,
        importState: importState,
        articleImportState: articleImportState,
        onArticlesTab: onArticlesTab,
      ),
    );
  }

  /// The FAB's action, icon, and label all depend on the same two bits of
  /// state (active tab + busy status) — compute them together instead of in
  /// three parallel helpers.
  Widget _buildFab({
    required AppLocalizations l10n,
    required ImportState importState,
    required ArticleImportState articleImportState,
    required bool onArticlesTab,
  }) {
    final bool busy;
    final VoidCallback? onPressed;
    final String label;
    final IconData idleIcon;

    if (onArticlesTab) {
      busy = articleImportState.status == ArticleImportStatus.fetching ||
          articleImportState.status == ArticleImportStatus.processing;
      onPressed = busy
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => const ImportArticleDialog(),
              );
      label = switch (articleImportState.status) {
        ArticleImportStatus.fetching => l10n.importArticleFetching,
        ArticleImportStatus.processing => l10n.importing,
        _ => l10n.importArticle,
      };
      idleIcon = Icons.link;
    } else {
      busy = importState.status == ImportStatus.processing;
      onPressed = busy
          ? null
          : () => ref.read(epubImportProvider.notifier).importFromFilePicker();
      label = busy ? l10n.importing : l10n.importBook;
      idleIcon = Icons.add;
    }

    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(idleIcon),
      label: Text(label),
    );
  }
}

/// AppBar `bottom` that layers the Books/Articles tab bar on top of an
/// optional sync progress indicator.
class _AppBarBottom extends StatelessWidget implements PreferredSizeWidget {
  final TabController tabController;
  final AppLocalizations l10n;
  final LibrarySyncState syncState;

  const _AppBarBottom({
    required this.tabController,
    required this.l10n,
    required this.syncState,
  });

  static const _tabsHeight = 48.0;
  static const _progressHeight = 48.0;

  @override
  Size get preferredSize => Size.fromHeight(
        syncState.isImporting ? _tabsHeight + _progressHeight : _tabsHeight,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (syncState.isImporting)
          _ImportProgressBar(
            current: syncState.importCurrent ?? 0,
            total: syncState.importTotal ?? 0,
            fileName: syncState.importFileName ?? '',
            l10n: l10n,
          ),
        TabBar(
          controller: tabController,
          tabs: [
            Tab(text: l10n.libraryTabBooks),
            Tab(text: l10n.libraryTabArticles),
          ],
        ),
      ],
    );
  }
}

/// Renders the categorized library for a given [LibraryKind], including
/// empty-state and pull-to-refresh (when sync is configured).
class _LibraryList extends ConsumerWidget {
  final LibraryKind kind;

  const _LibraryList({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final categorizedAsync = ref.watch(categorizedLibraryProvider(kind));

    return categorizedAsync.when(
      data: (categorized) {
        // Only the Books tab participates in sync; articles are local-only.
        final syncConfigured = kind == LibraryKind.books &&
            ref.watch(syncConfigProvider).isConfigured;

        final scroll = CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: categorized.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(kind: kind, l10n: l10n),
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
    );
  }

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

class _EmptyState extends StatelessWidget {
  final LibraryKind kind;
  final AppLocalizations l10n;

  const _EmptyState({required this.kind, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isArticles = kind == LibraryKind.articles;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isArticles ? Icons.article_outlined : Icons.menu_book_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(77),
          ),
          const SizedBox(height: 16),
          Text(
            isArticles ? l10n.emptyArticles : l10n.emptyLibrary,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            isArticles
                ? l10n.emptyArticlesSubtitle
                : l10n.emptyLibrarySubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ImportProgressBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    final displayName = fileName.isEmpty ? '…' : fileName;
    return SizedBox(
      height: 48,
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
