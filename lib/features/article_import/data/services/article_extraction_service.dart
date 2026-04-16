import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/utils/html_stripper.dart';
import '../../../../core/utils/readability_extractor.dart';
import '../../../../core/utils/text_tokenizer.dart';
import '../../../../core/utils/url_utils.dart';
import '../../../epub_import/domain/entities/chapter.dart';
import '../../../epub_import/domain/entities/parsed_book.dart';

/// Fetches a web article by URL, extracts its main content with the
/// [ReadabilityExtractor], and returns a single-chapter [ParsedBook] ready
/// to be persisted and read via the existing RSVP pipeline.
class ArticleExtractionService {
  final http.Client _client;

  ArticleExtractionService({http.Client? client})
      : _client = client ?? http.Client();

  static const _fetchTimeout = Duration(seconds: 20);

  /// Fetches [url] and returns the parsed article + resolved metadata.
  ///
  /// Throws [ArticleExtractionException] if the fetch fails or the page has
  /// no readable content.
  Future<ArticleExtractionResult> extractFromUrl(String url) async {
    final uri = UrlUtils.parseWithHttpsFallback(url);
    if (uri == null) {
      throw ArticleExtractionException('Invalid URL: $url');
    }

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          // Use a desktop-ish UA so sites don't redirect to mobile landing
          // pages (which often contain less of the article body).
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ).timeout(_fetchTimeout);
    } catch (e) {
      throw ArticleExtractionException('Failed to fetch URL: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArticleExtractionException(
        'HTTP ${response.statusCode} when fetching $url',
      );
    }

    // Many sites serve UTF-8 but declare a different charset (or none);
    // `response.body` trusts the header blindly and produces mojibake.
    // Decoding the raw bytes as lenient UTF-8 is almost always right.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    return extractFromHtml(body, url: uri.toString());
  }

  /// Parses [html] directly (no network). Useful for unit tests and for the
  /// Android share target when the system hands us HTML instead of a URL.
  ArticleExtractionResult extractFromHtml(String html, {required String url}) {
    final extracted = ReadabilityExtractor.extract(html);
    final cleanText = HtmlStripper.strip(extracted.contentHtml);

    if (cleanText.trim().isEmpty) {
      throw ArticleExtractionException('No readable content found');
    }

    final tokens = TextTokenizer.tokenize(
      cleanText,
      chapterIndex: 0,
      globalOffset: 0,
    );

    final title = (extracted.title?.trim().isNotEmpty ?? false)
        ? extracted.title!.trim()
        : _fallbackTitle(url);

    final chapter = Chapter(title: title, tokens: tokens);

    return ArticleExtractionResult(
      book: ParsedBook(
        title: title,
        author: extracted.byline ?? '',
        coverImage: null,
        chapters: [chapter],
        totalWords: tokens.length,
      ),
      sourceUrl: url,
      siteName: extracted.siteName,
    );
  }

  String _fallbackTitle(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Article';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return uri.host;
    return segments.last.replaceAll(RegExp(r'[-_]'), ' ');
  }

  void close() => _client.close();
}

class ArticleExtractionResult {
  final ParsedBook book;
  final String sourceUrl;
  final String? siteName;

  const ArticleExtractionResult({
    required this.book,
    required this.sourceUrl,
    this.siteName,
  });
}

class ArticleExtractionException implements Exception {
  final String message;
  const ArticleExtractionException(this.message);
  @override
  String toString() => 'ArticleExtractionException: $message';
}
