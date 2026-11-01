/// Decode content strings to bytes before applying the font's character map.
bool _space(int c) =>
    c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

List<int> decodePdfStringBytes(String token) {
  if (token.startsWith('<')) {
    String hex = token
        .substring(1, token.length - 1)
        .replaceAll(RegExp(r'[\x00\x09\x0A\x0C\x0D\x20]'), '');
    if (hex.length.isOdd) {
      hex += '0';
    }
    return <int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
  final List<int> result = <int>[];
  for (int i = 1; i < token.length - 1; i++) {
    int c = token.codeUnitAt(i);
    if (c == 92 && i + 1 < token.length - 1) {
      c = token.codeUnitAt(++i);
      if (c >= 48 && c <= 55) {
        int value = c - 48;
        for (int n = 1; n < 3 && i + 1 < token.length - 1; n++) {
          final int next = token.codeUnitAt(i + 1);
          if (next < 48 || next > 55) {
            break;
          }
          value = value * 8 + next - 48;
          i++;
        }
        result.add(value & 255);
        continue;
      }
      if (c == 10 || c == 13) {
        if (c == 13 &&
            i + 1 < token.length - 1 &&
            token.codeUnitAt(i + 1) == 10)
          i++;
        continue;
      }
      c = <int, int>{110: 10, 114: 13, 116: 9, 98: 8, 102: 12}[c] ?? c;
    }
    result.add(c & 255);
  }
  return result;
}

/// Keep TJ spacing adjustments and string boundaries. Escaped delimiters
/// and balanced nested parentheses belong to the string, not the array.
Iterable<String> pdfStringTokens(String input) sync* {
  int i = input.startsWith('[') ? 1 : 0;
  while (i < input.length) {
    final int c = input.codeUnitAt(i);
    if (_space(c) || c == 93) {
      i++;
      continue;
    }
    final int start = i++;
    if (c == 40) {
      int depth = 1;
      while (i < input.length && depth > 0) {
        final int next = input.codeUnitAt(i++);
        if (next == 92) {
          if (i < input.length) {
            i++;
          }
        } else if (next == 40) {
          depth++;
        } else if (next == 41) {
          depth--;
        }
      }
    } else if (c == 60) {
      while (i < input.length && input.codeUnitAt(i++) != 62) {}
    } else {
      while (i < input.length &&
          !_space(input.codeUnitAt(i)) &&
          !<int>[40, 60, 93].contains(input.codeUnitAt(i))) {
        i++;
      }
    }
    yield input.substring(start, i);
  }
}
