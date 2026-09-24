/// Data encoding mode of a segment (ISO/IEC 18004:2015, 7.4 and Table 2).
enum QrMode {
  /// Digits 0-9, 10 bits per 3 digits.
  numeric(0x1, [10, 12, 14]),

  /// Digits, A-Z, space and $%*+-./:, 11 bits per 2 characters.
  alphanumeric(0x2, [9, 11, 13]),

  /// 8-bit bytes (ISO-8859-1 by default, UTF-8 after an ECI designator).
  byte(0x4, [8, 16, 16]),

  /// Shift JIS double-byte characters, 13 bits each.
  kanji(0x8, [8, 10, 12]),

  /// Extended Channel Interpretation designator; carries no characters.
  eci(0x7, [0, 0, 0]);

  const QrMode(this.indicator, this._countBits);

  /// The 4-bit mode indicator.
  final int indicator;

  final List<int> _countBits;

  /// Width of the character count indicator in [version] (Table 3).
  int charCountBits(int version) {
    if (version < 1 || version > 40) {
      throw RangeError.range(version, 1, 40, 'version');
    }
    return _countBits[version <= 9
        ? 0
        : version <= 26
            ? 1
            : 2];
  }
}
