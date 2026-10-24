part of 'pdf_text_extractor.dart';

/// Detached matching data for one unchanged source page. It owns packed text,
/// geometry and character ordering, without PDF, font or renderer references.
/// The caller must invalidate it whenever the source bytes/content change.
class PdfPageSearchIndex {
  PdfPageSearchIndex._(
    this._matcher,
    this._layoutText,
    this._strings,
    this._combined,
    this._text,
    this._offsets,
    this._bounds,
    this._rotations,
    this._orders,
  );

  factory PdfPageSearchIndex._capture(
    _PdfPageTextMatcher matcher,
    String layoutText,
    List<String> strings,
    Map<int, int> combined,
    List<List<Glyph>> sequences,
  ) {
    final slots = HashMap<Glyph, int>.identity();
    final glyphs = <Glyph>[];
    final orders = <Uint32List>[];
    for (final sequence in sequences) {
      orders.add(
        Uint32List.fromList([
          for (final glyph in sequence)
            slots.putIfAbsent(glyph, () {
              glyphs.add(glyph);
              return glyphs.length - 1;
            }),
        ]),
      );
    }
    final text = StringBuffer();
    final offsets = Uint32List(glyphs.length + 1);
    final bounds = Float64List(glyphs.length * 4);
    final rotations = Int32List(glyphs.length);
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      offsets[i] = text.length;
      text.write(glyph.toUnicode);
      final rect = glyph.boundingRect;
      bounds.setRange(i * 4, i * 4 + 4, [
        rect.left,
        rect.top,
        rect.right,
        rect.bottom,
      ]);
      rotations[i] = glyph.rotationAngle;
    }
    offsets[glyphs.length] = text.length;
    return PdfPageSearchIndex._(
      matcher,
      layoutText,
      List.unmodifiable(strings),
      Map.unmodifiable(combined),
      text.toString(),
      offsets,
      bounds,
      rotations,
      List.unmodifiable(orders),
    );
  }

  final _PdfPageTextMatcher _matcher;
  final String _layoutText;
  final List<String> _strings;
  final Map<int, int> _combined;
  final String _text;
  final Uint32List _offsets;
  final Float64List _bounds;
  final Int32List _rotations;
  final List<Uint32List> _orders;

  int get pageIndex => _matcher.pageIndex;
  bool get hasText => _layoutText.trim().isNotEmpty;

  /// Conservative payload accounting, not an estimate of process RSS.
  int get retainedBytes =>
      512 +
      _layoutText.length * 2 +
      _text.length * 2 +
      _strings.fold<int>(0, (n, s) => n + 64 + s.length * 2) +
      _offsets.lengthInBytes +
      _bounds.lengthInBytes +
      _rotations.lengthInBytes +
      _orders.fold<int>(0, (n, order) => n + 64 + order.lengthInBytes) +
      _combined.length * 96;

  /// Uses the original live matcher's bidi, ligature, whitespace and bounds
  /// rules. Only lightweight views are created; no content parsing occurs.
  List<MatchedItem> findText(
    List<String> searchString, {
    TextSearchOption? searchOption,
  }) {
    final query = List<String>.of(searchString);
    final rtl = bidi.Bidi.hasAnyRtl(_layoutText);
    var matched = _matcher._isMatchFound(query, searchOption, _layoutText, rtl);
    if (!matched && !rtl) {
      return <MatchedItem>[];
    }
    if (!matched) {
      for (final text in _strings) {
        if (_matcher._isMatchFound(query, searchOption, text, rtl)) {
          matched = true;
          break;
        }
      }
    }
    final result = <MatchedItem>[];
    if (matched) {
      _matcher._getMatchedItems(
        query,
        searchOption,
        List.of(_strings),
        _combined,
        [for (final order in _orders) _PackedSearchGlyphs(this, order)],
        result,
      );
    }
    return result;
  }
}

class _PackedSearchGlyphs extends ListBase<PdfSearchGlyph> {
  _PackedSearchGlyphs(this.index, this.order);
  final PdfPageSearchIndex index;
  final Uint32List order;
  @override
  int get length => order.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable search data');
  @override
  PdfSearchGlyph operator [](int slot) =>
      _PackedSearchGlyph(index, order[slot]);
  @override
  void operator []=(int slot, PdfSearchGlyph value) =>
      throw UnsupportedError('Immutable search data');
}

class _PackedSearchGlyph implements PdfSearchGlyph {
  _PackedSearchGlyph(this.index, this.slot);
  final PdfPageSearchIndex index;
  final int slot;
  @override
  String get toUnicode =>
      index._text.substring(index._offsets[slot], index._offsets[slot + 1]);
  @override
  Rect get boundingRect {
    final offset = slot * 4;
    return Rect.fromLTRB(
      index._bounds[offset],
      index._bounds[offset + 1],
      index._bounds[offset + 2],
      index._bounds[offset + 3],
    );
  }

  @override
  int get rotationAngle => index._rotations[slot];
}
