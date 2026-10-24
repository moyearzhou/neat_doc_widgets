part of 'pdf_text_extractor.dart';

/// Shared by live extraction and detached compact search data. Keeping the
/// original matching/bounds rules here prevents warm queries changing semantics.
class _PdfPageTextMatcher {
  _PdfPageTextMatcher(this.pageIndex, this.rotation, this.origin);

  factory _PdfPageTextMatcher.fromPage(PdfPage page, int pageIndex) {
    final helper = PdfPageHelper.getHelper(page);
    final box =
        !helper.cropBox.isEmpty && helper.cropBox != helper.mediaBox
            ? helper.cropBox
            : helper.mediaBox;
    return _PdfPageTextMatcher(
      pageIndex,
      page.rotation,
      Offset(-box.left, box.top),
    );
  }

  final int pageIndex;
  final PdfPageRotateAngle rotation;
  final Offset origin;

  Rect _calculateBounds(Rect bounds) =>
      origin == Offset.zero
          ? bounds
          : Rect.fromLTWH(
            bounds.left + origin.dx,
            bounds.top + origin.dy,
            bounds.width,
            bounds.height,
          );

  bool _isMatchFound(
    List<String> searchString,
    TextSearchOption? searchOption,
    String pageText,
    bool containsRtl,
  ) {
    ArabicShapeRenderer? shapeRenderer;
    if (containsRtl) {
      shapeRenderer = ArabicShapeRenderer();
    }
    bool isMatched = false;
    for (int i = 0; i < searchString.length; i++) {
      final String term = searchString[i];
      if (searchOption != null &&
          (searchOption == TextSearchOption.caseSensitive ||
              searchOption == TextSearchOption.both)) {
        if (pageText.contains(term)) {
          isMatched = true;
          if (!containsRtl) {
            break;
          }
        }
      } else if (pageText.toLowerCase().contains(term.toLowerCase())) {
        isMatched = true;
        if (!containsRtl) {
          break;
        }
      }
      if (containsRtl && bidi.Bidi.hasAnyRtl(term)) {
        final String renderedTerm = shapeRenderer!.shape(term.split(''), 0);
        if (pageText.toLowerCase().contains(renderedTerm.toLowerCase())) {
          if (!searchString.contains(renderedTerm)) {
            searchString.add(renderedTerm);
          }
          isMatched = true;
        }
        if (term != renderedTerm && term.length < 5) {
          List<String> termCollection = <String>[term];
          for (int j = 0; j < term.length; j++) {
            if (shapeRenderer.arabicMapTable.containsKey(term[j])) {
              final List<String>? shapedChars =
                  shapeRenderer.arabicMapTable[term[j]];
              if (shapedChars != null && shapedChars.isNotEmpty) {
                final List<String> tempTermCollection = termCollection.toList();
                for (final String char in shapedChars) {
                  for (final String tempTerm in termCollection) {
                    final List<String> termList = tempTerm.split('');
                    termList[j] = char;
                    final String tempRenderedTerm = termList.join();
                    if (!tempTermCollection.contains(tempRenderedTerm)) {
                      tempTermCollection.add(tempRenderedTerm);
                      if (!searchString.contains(tempRenderedTerm) &&
                          pageText.toLowerCase().contains(
                            tempRenderedTerm.toLowerCase(),
                          )) {
                        searchString.add(tempRenderedTerm);
                        isMatched = true;
                      }
                    }
                  }
                }
                termCollection.clear();
                termCollection = tempTermCollection.toList();
                tempTermCollection.clear();
              }
            }
          }
          termCollection.clear();
        }
      }
    }
    return isMatched;
  }

  void _getMatchedItems(
    List<String> searchString,
    TextSearchOption? searchOption,
    List<String> renderedStringCollection,
    Map<int, int> combinedGlyphLength,
    List<List<PdfSearchGlyph>?> glyphListCollection,
    List<MatchedItem> result,
  ) {
    if (renderedStringCollection.isNotEmpty &&
        renderedStringCollection[0] != '') {
      final Map<String, List<int>> mappedIndexes = <String, List<int>>{};
      final List<int> textLengthCollection = <int>[];
      for (int i = 0; i < renderedStringCollection.length; i++) {
        if (searchOption == null ||
            (searchOption != TextSearchOption.caseSensitive &&
                searchOption != TextSearchOption.both)) {
          renderedStringCollection[i] =
              renderedStringCollection[i].toLowerCase();
        }
        textLengthCollection.add(renderedStringCollection[i].length);
      }
      for (final String term in searchString) {
        if (term != '' && !mappedIndexes.containsKey(term)) {
          final List<int> indexes = <int>[];
          final String currentText =
              (searchOption != null &&
                      (searchOption == TextSearchOption.caseSensitive ||
                          searchOption == TextSearchOption.both))
                  ? term
                  : term.toLowerCase();
          int startIndex = 0;
          final int length = currentText.length;
          for (int i = 0; i < renderedStringCollection.length; i++) {
            while (startIndex <= textLengthCollection[i] &&
                renderedStringCollection[i].contains(currentText, startIndex)) {
              int index = renderedStringCollection[i].indexOf(
                currentText,
                startIndex,
              );
              final int tempIndex = index;
              if (searchOption != null &&
                  (searchOption == TextSearchOption.wholeWords ||
                      searchOption == TextSearchOption.both)) {
                if (index == 0 ||
                    _hasEscapeCharacter(
                      renderedStringCollection[i][index - 1],
                    )) {
                  if (index + length == textLengthCollection[i]) {
                    if (combinedGlyphLength.isNotEmpty) {
                      index = _checkCombinedTextIndex(
                        index,
                        combinedGlyphLength,
                      );
                    }
                    indexes.add(index);
                  } else if (_hasEscapeCharacter(
                    renderedStringCollection[i][index + length],
                  )) {
                    if (combinedGlyphLength.isNotEmpty) {
                      index = _checkCombinedTextIndex(
                        index,
                        combinedGlyphLength,
                      );
                    }
                    indexes.add(index);
                  }
                }
              } else {
                if (combinedGlyphLength.isNotEmpty) {
                  index = _checkCombinedTextIndex(index, combinedGlyphLength);
                }
                indexes.add(index);
              }
              startIndex = tempIndex + 1;
            }
            if (indexes.isNotEmpty) {
              for (final int index in indexes) {
                if (glyphListCollection[i] != null &&
                    index < glyphListCollection[i]!.length) {
                  final List<Rect> rect = _calculatedTextounds(
                    glyphListCollection[i]!,
                    term,
                    index,
                    bidi.Bidi.hasAnyRtl(term),
                  );
                  result.add(
                    MatchedItemHelper.initialize(term, rect, pageIndex),
                  );
                }
              }
              break;
            }
          }
        }
      }
    }
  }

  int _checkCombinedTextIndex(
    int textIndex,
    Map<int, int> combinedGlyphLength,
  ) {
    int adjustableLength = 0;
    combinedGlyphLength.forEach((int index, int length) {
      if (index < textIndex) {
        adjustableLength += length - 1;
      }
    });
    return textIndex - adjustableLength;
  }

  List<Rect> _calculatedTextounds(
    List<PdfSearchGlyph> glyphs,
    String text,
    int index,
    bool isRTL,
  ) {
    Rect textBounds = Rect.zero;
    if (!isRTL) {
      textBounds = _getLTRBounds(glyphs, text, index);
    } else {
      final bool isBidi = bidi.Bidi.hasAnyLtr(text);
      String tempString = '';
      if (isBidi) {
        final Map<int, String> textCollection = <int, String>{};
        final List<Rect> boundsCollection = <Rect>[];
        int indexValue = index;
        for (int i = 0; i < text.length; i++) {
          if (i < text.length - 1 &&
              (((bidi.Bidi.startsWithRtl(text[i]) || text[i] == ' ') &&
                      (glyphs[index + i].boundingRect.left -
                                  (glyphs[index + i + 1].boundingRect.left +
                                      glyphs[index + i + 1].boundingRect.width))
                              .abs() <
                          0.001) ||
                  (bidi.Bidi.startsWithLtr(text[i]) &&
                      ((glyphs[index + i].boundingRect.left +
                                      glyphs[index + i].boundingRect.width) -
                                  glyphs[index + i + 1].boundingRect.left)
                              .abs() <
                          0.001))) {
            tempString += glyphs[index + i].toUnicode;
          } else {
            tempString += glyphs[index + i].toUnicode;
            textCollection[indexValue] = tempString;
            indexValue = index + i + 1;
            tempString = '';
          }
        }
        textCollection.forEach((int key, String value) {
          if (bidi.Bidi.hasAnyRtl(value)) {
            boundsCollection.add(
              _calculateBounds(_getRTLBounds(glyphs, value, key)),
            );
          } else {
            boundsCollection.add(
              _calculateBounds(_getLTRBounds(glyphs, value, key)),
            );
          }
        });
        return boundsCollection;
      } else {
        textBounds = _getRTLBounds(glyphs, text, index);
      }
    }
    return <Rect>[_calculateBounds(textBounds)];
  }

  Rect _getLTRBounds(List<PdfSearchGlyph> glyphs, String text, int index) {
    final PdfSearchGlyph startGlyph = glyphs[index];
    double x = startGlyph.boundingRect.left;
    double y = startGlyph.boundingRect.top;
    double width = 0;
    double height = startGlyph.boundingRect.height;
    //For complex script glyph mapping
    int endIndex = index + text.length - 1;
    int length = text.length;
    String tempString = '';
    for (int i = 0; i < text.length; i++) {
      tempString += glyphs[index + i].toUnicode;
      if (tempString == text) {
        endIndex = index + i;
        length = i + 1;
        break;
      }
    }
    final PdfSearchGlyph endGlyph = glyphs[endIndex];
    if (startGlyph.boundingRect.top == endGlyph.boundingRect.top ||
        (startGlyph.boundingRect.top - endGlyph.boundingRect.top).abs() <
            0.001) {
      if (x > endGlyph.boundingRect.left) {
        width = (x - endGlyph.boundingRect.left) + endGlyph.boundingRect.width;
        if (rotation == PdfPageRotateAngle.rotateAngle0 ||
            rotation == PdfPageRotateAngle.rotateAngle180) {
          width = startGlyph.boundingRect.height;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.width;
            if (glyphs[index + i].boundingRect.height > width) {
              width = glyphs[index + i].boundingRect.height;
            }
          }
        } else {
          width = startGlyph.boundingRect.width;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.height;
            if (glyphs[index + i].boundingRect.width > width) {
              width = glyphs[index + i].boundingRect.width;
            }
          }
        }
        x -= width;
      } else {
        width = (endGlyph.boundingRect.left - x) + endGlyph.boundingRect.width;
      }
    } else if (startGlyph.boundingRect.left == endGlyph.boundingRect.left ||
        (startGlyph.boundingRect.left - endGlyph.boundingRect.left).abs() <
            0.001) {
      if (startGlyph.boundingRect.top != endGlyph.boundingRect.top &&
          !((startGlyph.boundingRect.top - endGlyph.boundingRect.top).abs() <
              0.001)) {
        height = 0;
        if (rotation == PdfPageRotateAngle.rotateAngle0 ||
            rotation == PdfPageRotateAngle.rotateAngle180) {
          width = startGlyph.boundingRect.height;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.width;
            if (glyphs[index + i].boundingRect.height > 0) {
              width = glyphs[index + i].boundingRect.height;
            }
          }
        } else {
          width = startGlyph.boundingRect.width;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.height;
            width = glyphs[index + i].boundingRect.width;
          }
        }
        if (y > endGlyph.boundingRect.top || startGlyph.rotationAngle == 270) {
          x = startGlyph.boundingRect.left - width + 1;
          y = startGlyph.boundingRect.top - height;
        } else if (y < endGlyph.boundingRect.top ||
            startGlyph.rotationAngle == 90) {
          x = startGlyph.boundingRect.left - 1;
          y = startGlyph.boundingRect.top;
        }
      }
    }
    return Rect.fromLTWH(x, y, width, height);
  }

  Rect _getRTLBounds(List<PdfSearchGlyph> glyphs, String text, int index) {
    final PdfSearchGlyph startGlyph = glyphs[index];
    double x = startGlyph.boundingRect.left;
    final double y = startGlyph.boundingRect.top;
    double width = 0;
    final double height = startGlyph.boundingRect.height;
    //For complex script glyph mapping
    int endIndex = index + text.length - 1;
    String tempString = '';
    for (int i = 0; i < text.length; i++) {
      tempString += glyphs[index + i].toUnicode;
      if (tempString == text) {
        endIndex = index + i;
        break;
      }
    }
    final PdfSearchGlyph endGlyph = glyphs[endIndex];
    if (startGlyph.boundingRect.top == endGlyph.boundingRect.top ||
        (startGlyph.boundingRect.top - endGlyph.boundingRect.top).abs() <
            0.001) {
      width = (x - endGlyph.boundingRect.left) + startGlyph.boundingRect.width;
      x = startGlyph.boundingRect.left + startGlyph.boundingRect.width - width;
    }
    return Rect.fromLTWH(x, y, width, height);
  }

  bool _hasEscapeCharacter(String text) {
    return text.contains(' ') ||
        text.contains(r'\u0007') ||
        text.contains(r'\') ||
        text.contains(r'\b') ||
        text.contains(r'\f') ||
        text.contains(r'\r') ||
        text.contains(r'\t') ||
        text.contains(r'\n') ||
        text.contains(r'\v') ||
        text.contains(r"\'") ||
        text.contains(r'\u0000');
  }
}
