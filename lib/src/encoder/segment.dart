import 'kanji_table.dart';
import 'mode.dart';

/// Characters of the alphanumeric mode, in value order (Table 5).
const String alphanumericCharset =
    r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

final List<int> _alnumTable = () {
  final t = List<int>.filled(128, -1);
  for (var i = 0; i < alphanumericCharset.length; i++) {
    t[alphanumericCharset.codeUnitAt(i)] = i;
  }
  return t;
}();

Map<int, int>? _kanjiByRune;

Map<int, int> _kanjiIndex() {
  var map = _kanjiByRune;
  if (map != null) return map;
  map = <int, int>{};
  for (var v = 0; v < kanjiTable.length; v++) {
    final unit = kanjiTable.codeUnitAt(v);
    if (unit != 0) map[unit] = v;
  }
  return _kanjiByRune = map;
}

/// 13-bit Kanji mode value for [rune], or null when it cannot be encoded.
int? kanjiValue(int rune) => _kanjiIndex()[rune];

/// One segment of a QR Code bit stream: a mode, a character count and the
/// data bits that follow the count indicator.
class QrSegment {
  QrSegment._(this.mode, this.numChars, this.bits, [this.text]);

  /// Numeric mode segment for a string of ASCII digits.
  factory QrSegment.numeric(String digits) {
    final bits = <bool>[];
    for (var i = 0; i < digits.length; i += 3) {
      final end = i + 3 < digits.length ? i + 3 : digits.length;
      var value = 0;
      for (var k = i; k < end; k++) {
        final d = digits.codeUnitAt(k) - 0x30;
        if (d < 0 || d > 9) {
          throw ArgumentError.value(digits, 'digits', 'Not numeric');
        }
        value = value * 10 + d;
      }
      _append(bits, value, (end - i) * 3 + 1);
    }
    return QrSegment._(QrMode.numeric, digits.length, bits, digits);
  }

  /// Alphanumeric mode segment (digits, A-Z, space and `$%*+-./:`).
  factory QrSegment.alphanumeric(String text) {
    if (!isAlphanumeric(text)) {
      throw ArgumentError.value(text, 'text', 'Not alphanumeric');
    }
    final bits = <bool>[];
    var i = 0;
    for (; i + 1 < text.length; i += 2) {
      final v = _alnumValue(text.codeUnitAt(i)) * 45 +
          _alnumValue(text.codeUnitAt(i + 1));
      _append(bits, v, 11);
    }
    if (i < text.length) _append(bits, _alnumValue(text.codeUnitAt(i)), 6);
    return QrSegment._(QrMode.alphanumeric, text.length, bits, text);
  }

  /// Byte mode segment. Values must be in 0..255.
  factory QrSegment.bytes(List<int> data) {
    final bits = <bool>[];
    for (final b in data) {
      if (b < 0 || b > 255) {
        throw ArgumentError.value(b, 'data', 'Byte out of range');
      }
      _append(bits, b, 8);
    }
    return QrSegment._(QrMode.byte, data.length, bits);
  }

  /// Kanji mode segment. Every character must be a Shift JIS double-byte
  /// character in the Kanji mode ranges (see [canEncodeKanji]).
  factory QrSegment.kanji(String text) {
    final bits = <bool>[];
    var count = 0;
    for (final rune in text.runes) {
      final v = kanjiValue(rune);
      if (v == null) {
        throw ArgumentError.value(text, 'text', 'Not encodable in Kanji mode');
      }
      _append(bits, v, 13);
      count++;
    }
    return QrSegment._(QrMode.kanji, count, bits, text);
  }

  /// ECI designator segment for [assignment] (0 to 999999). 26 is UTF-8.
  factory QrSegment.eci(int assignment) {
    final bits = <bool>[];
    if (assignment < 0) {
      throw ArgumentError.value(assignment, 'assignment', 'Negative');
    } else if (assignment < 1 << 7) {
      _append(bits, assignment, 8);
    } else if (assignment < 1 << 14) {
      _append(bits, 2, 2);
      _append(bits, assignment, 14);
    } else if (assignment < 1000000) {
      _append(bits, 6, 3);
      _append(bits, assignment, 21);
    } else {
      throw ArgumentError.value(assignment, 'assignment', 'Must be < 1000000');
    }
    return QrSegment._(QrMode.eci, 0, bits);
  }

  /// The mode of this segment.
  final QrMode mode;

  /// Characters (bytes in byte mode) counted by the count indicator.
  final int numChars;

  /// Data bits after the count indicator, most significant first.
  final List<bool> bits;

  /// Source text for numeric, alphanumeric and Kanji segments.
  final String? text;

  /// Whether [text] contains only ASCII digits.
  static bool isNumeric(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  /// Whether [text] contains only alphanumeric-mode characters.
  static bool isAlphanumeric(String text) {
    for (var i = 0; i < text.length; i++) {
      if (_alnumValue(text.codeUnitAt(i)) < 0) return false;
    }
    return true;
  }

  /// Alphanumeric value of a UTF-16 code unit, or -1 (Table 5).
  static int alphanumericValue(int codeUnit) => _alnumValue(codeUnit);

  static int _alnumValue(int c) {
    if (c < 0x80) return _alnumTable[c];
    return -1;
  }

  /// Whether the Unicode code point [rune] can be written in Kanji mode.
  static bool canEncodeKanji(int rune) => kanjiValue(rune) != null;

  /// Bits needed for [segments] in [version], including mode and count
  /// indicators, or null when a count does not fit its indicator.
  static int? totalBits(List<QrSegment> segments, int version) {
    var total = 0;
    for (final s in segments) {
      final ccBits = s.mode.charCountBits(version);
      if (s.numChars >= 1 << ccBits && s.mode != QrMode.eci) return null;
      total += 4 + ccBits + s.bits.length;
    }
    return total;
  }

  static void _append(List<bool> bits, int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add((value >> i) & 1 == 1);
    }
  }

  @override
  String toString() => 'QrSegment(${mode.name}, $numChars)';
}
