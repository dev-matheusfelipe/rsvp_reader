import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../database/app_database.dart';
import '../../../../database/tables/book_source.dart';
import '../providers/book_library_provider.dart';

class BookCard extends ConsumerWidget {
  final BooksTableData book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const BookCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  /// For articles we prefer the site name over the (often empty) author
  /// field — it's the clearer attribution for web content.
  String? get _subtitle {
    if (book.source == BookSource.article) {
      final site = book.siteName;
      if (site != null && site.isNotEmpty) return site;
      final author = book.author;
      if (author != null && author.isNotEmpty) return author;
      final url = book.sourceUrl;
      if (url != null && url.isNotEmpty) {
        return Uri.tryParse(url)?.host ?? url;
      }
      return null;
    }
    return book.author;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(bookProgressProvider(book.id)).valueOrNull ?? 0.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceVariant,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image or placeholder
            Expanded(
              flex: 3,
              child: book.coverImage != null
                  ? Image.memory(
                      book.coverImage!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: theme.colorScheme.primary.withAlpha(30),
                      child: Center(
                        child: Icon(
                          book.source == BookSource.article
                              ? Icons.article_rounded
                              : Icons.menu_book_rounded,
                          size: 48,
                          color: theme.colorScheme.primary.withAlpha(128),
                        ),
                      ),
                    ),
            ),
            // Book info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (_subtitle != null)
                      Text(
                        _subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(153),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const Spacer(),
                    // Reading progress
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.onSurface.withAlpha(38),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progress * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(153),
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
