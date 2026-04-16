import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Result of extracting the main article from an HTML document.
class ExtractedArticle {
  final String? title;
  final String? byline;
  final String? siteName;
  final String contentHtml;

  const ExtractedArticle({
    this.title,
    this.byline,
    this.siteName,
    required this.contentHtml,
  });
}

/// Lightweight readability-style extractor: takes a full HTML document and
/// returns the element most likely to contain the main article body, along
/// with title/byline/site name pulled from `<meta>` tags and the document
/// `<head>`.
///
/// Algorithm (simplified from Mozilla's readability):
///   1. Remove obvious non-content tags (nav, aside, footer, script, style, …).
///   2. Prefer `<article>` / `<main>` / `role="main"` when present and text-heavy.
///   3. Otherwise, score every candidate block (`div`, `section`, `article`)
///      by text length, paragraph density, and positive/negative class-id hints.
///   4. Return the highest-scoring candidate's inner HTML.
class ReadabilityExtractor {
  const ReadabilityExtractor._();

  static const _stripTags = {
    'script', 'style', 'noscript', 'iframe', 'object', 'embed',
    'svg', 'form', 'button', 'input', 'select', 'textarea',
    'nav', 'aside', 'header', 'footer',
  };

  /// Class/id substrings that boost a candidate's score (case-insensitive).
  static final _positivePatterns = RegExp(
    r'article|body|content|entry|main|page|post|story|text|blog',
    caseSensitive: false,
  );

  /// Class/id substrings that penalize a candidate.
  static final _negativePatterns = RegExp(
    r'comment|meta|footer|footnote|sidebar|sponsor|advertis|share|social|'
    r'promo|related|recommend|subscribe|newsletter|popup|modal|nav|menu|'
    r'header|banner|breadcrumb|pagination|author|byline|tag|widget',
    caseSensitive: false,
  );

  static ExtractedArticle extract(String html) {
    final doc = html_parser.parse(html);

    final title = _extractTitle(doc);
    final byline = _extractByline(doc);
    final siteName = _extractSiteName(doc);

    final body = doc.body;
    if (body == null) {
      return ExtractedArticle(
        title: title,
        byline: byline,
        siteName: siteName,
        contentHtml: html,
      );
    }

    _stripNoise(body);

    final best = _findBestCandidate(body);
    final contentHtml = (best ?? body).innerHtml;

    return ExtractedArticle(
      title: title,
      byline: byline,
      siteName: siteName,
      contentHtml: contentHtml,
    );
  }

  static String? _extractTitle(Document doc) {
    final og = doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    if (og != null && og.trim().isNotEmpty) return og.trim();
    final twitter = doc.querySelector('meta[name="twitter:title"]')?.attributes['content'];
    if (twitter != null && twitter.trim().isNotEmpty) return twitter.trim();
    final h1 = doc.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;
    final title = doc.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;
    return null;
  }

  static String? _extractByline(Document doc) {
    final meta = doc.querySelector('meta[name="author"]')?.attributes['content'];
    if (meta != null && meta.trim().isNotEmpty) return meta.trim();
    final article = doc
        .querySelector('meta[property="article:author"]')
        ?.attributes['content'];
    if (article != null && article.trim().isNotEmpty) return article.trim();
    final rel = doc.querySelector('[rel="author"]')?.text.trim();
    if (rel != null && rel.isNotEmpty) return rel;
    return null;
  }

  static String? _extractSiteName(Document doc) {
    final og = doc
        .querySelector('meta[property="og:site_name"]')
        ?.attributes['content'];
    if (og != null && og.trim().isNotEmpty) return og.trim();
    return null;
  }

  static void _stripNoise(Element root) {
    // Iterate over a copy because we're mutating the tree.
    final toRemove = <Element>[];
    for (final el in root.querySelectorAll('*')) {
      final tag = el.localName?.toLowerCase();
      if (tag != null && _stripTags.contains(tag)) {
        toRemove.add(el);
        continue;
      }
      // Drop elements that look like ads/navigation by class/id alone — but
      // only if they have no `<p>` descendants, otherwise we risk eating real
      // article chrome (e.g. sidebars that occasionally hold pull quotes).
      final marker = '${el.id} ${el.className}';
      if (_negativePatterns.hasMatch(marker) &&
          el.querySelectorAll('p').isEmpty) {
        toRemove.add(el);
      }
    }
    for (final el in toRemove) {
      el.remove();
    }
  }

  static Element? _findBestCandidate(Element body) {
    // Fast path: a single <article> or <main> with meaningful text wins.
    for (final tag in const ['article', 'main']) {
      final elements = body.querySelectorAll(tag);
      if (elements.length == 1 && _textLength(elements.first) > 200) {
        return elements.first;
      }
    }
    final roleMain = body.querySelector('[role="main"]');
    if (roleMain != null && _textLength(roleMain) > 200) {
      return roleMain;
    }

    // Otherwise score all plausible containers.
    final candidates = body.querySelectorAll('div, section, article');
    Element? best;
    double bestScore = 0;
    for (final el in candidates) {
      final score = _scoreElement(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    return best;
  }

  /// Score = paragraph-derived text length + commas across <p> children +
  /// class/id hints. The constants roughly follow Mozilla's Readability.
  static double _scoreElement(Element el) {
    final paragraphs = el.querySelectorAll('p');
    if (paragraphs.isEmpty) return 0;

    double score = 0;
    for (final p in paragraphs) {
      final text = p.text.trim();
      if (text.length < 25) continue;
      score += 1;
      score += ','.allMatches(text).length;
      score += (text.length / 100).clamp(0.0, 3.0);
    }

    final marker = '${el.id} ${el.className}';
    if (_positivePatterns.hasMatch(marker)) score += 25;
    if (_negativePatterns.hasMatch(marker)) score -= 25;

    // Penalty for link-heavy blocks (navs that survived _stripNoise).
    final linkDensity = _linkDensity(el);
    score *= (1 - linkDensity);

    return score;
  }

  static int _textLength(Element el) => el.text.trim().length;

  static double _linkDensity(Element el) {
    final textLen = _textLength(el);
    if (textLen == 0) return 0;
    int linkLen = 0;
    for (final a in el.querySelectorAll('a')) {
      linkLen += a.text.trim().length;
    }
    return (linkLen / textLen).clamp(0.0, 1.0);
  }
}
