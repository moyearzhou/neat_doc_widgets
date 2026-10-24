part of 'pdf_text_extractor.dart';

/// A single page's original matches and summary lines. No parsed PDF resources
/// or renderer are retained by this result; callers can discard it per page.
class PdfPageTextSearchResult {
  PdfPageTextSearchResult._(
    this.searchText,
    this.matches,
    this.textLines,
    this.searchIndex,
  );

  /// Compact keyword-independent matching input, when explicitly requested.
  final PdfPageSearchIndex? searchIndex;

  /// Keyword-independent layout text; safe to retain without PDF resources.
  final PdfPageSearchText searchText;

  /// Whether layout extraction found searchable text on the page.
  bool get hasText => searchText.layoutText.trim().isNotEmpty;

  /// Matches in the same order and coordinates as [PdfTextExtractor.findText].
  final List<MatchedItem> matches;

  /// Summary lines for matching pages, or all pages when building an index.
  final List<TextLine> textLines;
}

/// Lightweight layout-search text for one unchanged source page. It is not a
/// reflow paragraph: clients must preserve its ordering and whitespace when
/// using it to prefilter the original matcher. No glyph/font graph is retained.
class PdfPageSearchText {
  PdfPageSearchText._(this.pageIndex, this.layoutText);

  final int pageIndex;
  final String layoutText;

  /// Conservative prefilter for the default case-insensitive search. RTL pages
  /// always need the original geometry path, which can find shaped variants.
  bool mayContain(String query) =>
      bidi.Bidi.hasAnyRtl(layoutText) ||
      layoutText.toLowerCase().contains(query.toLowerCase());
}

class _PageSearchRecords {
  _PageSearchRecords(this.page);
  final PdfPage page;
  PdfRecordCollection? records;
  bool loaded = false;
  String layoutText = '';
  ImageRenderer? summaryRenderer;
  bool collectSummary = false;
  bool buildIndex = false;
  PdfPageSearchIndex? searchIndex;
}

extension _PdfPageTextSearch on PdfTextExtractor {
  PdfPageTextSearchResult _searchPageWithRecords(
    List<String> searchString,
    int pageIndex,
    TextSearchOption? searchOption,
    PdfPageSearchText? cachedText,
    bool includeTextLines,
    bool buildSearchIndex,
  ) {
    _checkPageNumber(pageIndex);
    if (cachedText != null && cachedText.pageIndex != pageIndex) {
      throw ArgumentError.value(
        cachedText.pageIndex,
        'cachedText',
        'Wrong page',
      );
    }
    final page = _document.pages[pageIndex];
    final helper = PdfPageHelper.getHelper(page);
    final changed = _checkPageDictionary(page);
    final contentChanged = _checkContentArray(page);
    final extracting = helper.isTextExtraction;
    final wasLayout = _isLayout;
    final scope = _PageSearchRecords(page);
    scope.collectSummary = includeTextLines || buildSearchIndex;
    scope.buildIndex = buildSearchIndex;
    _pageSearchRecords = scope;
    try {
      _currentPageIndex = pageIndex;
      final matches = _searchInBackground(
        page,
        searchString,
        searchOption,
        cachedPageText: cachedText?.layoutText,
      );
      // Matching has its own glyph sequence; line-only padding/whitespace
      // cannot change the legacy matcher's offsets or coordinates.
      final lines =
          !includeTextLines || (matches.isEmpty && !buildSearchIndex)
              ? <TextLine>[]
              : _getTextLine(page, rendered: scope.summaryRenderer);
      return PdfPageTextSearchResult._(
        cachedText ?? PdfPageSearchText._(pageIndex, scope.layoutText),
        matches,
        lines,
        scope.searchIndex,
      );
    } finally {
      _pageSearchRecords = null;
      scope.summaryRenderer = null;
      scope.records?.recordCollection.clear();
      scope.records = null;
      helper.contents.changed = contentChanged;
      helper.dictionary!.changed = changed;
      helper.isTextExtraction = extracting;
      _isLayout = wasLayout;
    }
  }
}
