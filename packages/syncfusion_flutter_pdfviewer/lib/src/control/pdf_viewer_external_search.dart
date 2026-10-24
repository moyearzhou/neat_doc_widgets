part of '../pdfviewer.dart';

extension _PdfViewerExternalSearch on SfPdfViewerState {
  void _applyExternalSearchResults() {
    _killTextSearchIsolate();
    final result = _pdfViewerController._pdfTextSearchResult;
    result._removeListener(_handleTextSearch);
    result._addListener(_handleTextSearch);
    final previousIndex = result.currentInstanceIndex;
    _textCollection = _pdfViewerController._externalSearchMatches;
    _isSearchStarted = true;
    _pdfViewerController.clearSelection();
    _deselectAnnotation();
    if (_textCollection!.isEmpty) {
      result._currentOccurrenceIndex = 0;
      result._totalSearchTextCount = 0;
      result._updateResult(false);
    } else {
      result._currentOccurrenceIndex = previousIndex.clamp(
        1,
        _textCollection!.length,
      );
      result._totalSearchTextCount = _textCollection!.length;
      result._updateResult(true);
      // Appending another page must not repeatedly navigate to the first hit.
      if (previousIndex == 0 && _pdfPages.isNotEmpty) {
        _isPageChanged = false;
        _jumpToSearchInstance();
      }
    }
    result._updateSearchCompletedStatus(
      _pdfViewerController._externalSearchCompleted,
    );
    _checkMount();
  }
}
