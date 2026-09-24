/// Version and error correction tables (ISO/IEC 18004:2015, Tables 1, 9 and
/// E.1). Every value is checked against the standard in
/// test/encoder/tables_test.dart.
library;

import 'ec_level.dart';

/// Smallest QR Code version.
const int minVersion = 1;

/// Largest QR Code version.
const int maxVersion = 40;

// Values for versions 1 to 40, one row per level in the order L, M, Q, H.
// Error correction codewords per block.
const List<String> _ecCodewordsPerBlockRows = [
  '7 10 15 20 26 18 20 24 30 18 20 24 26 30 22 24 28 30 28 '
      '28 28 28 30 30 26 28 30 30 30 30 30 30 30 30 30 30 30 30 '
      '30 30',
  '10 16 26 18 24 16 18 22 22 26 30 22 22 24 24 28 28 26 26 '
      '26 26 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 '
      '28 28',
  '13 22 18 26 18 24 18 22 20 24 28 26 24 20 30 24 28 28 26 '
      '30 28 30 30 30 30 28 30 30 30 30 30 30 30 30 30 30 30 30 '
      '30 30',
  '17 28 22 16 22 28 26 26 24 28 24 28 22 24 24 30 28 28 26 '
      '28 30 24 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 '
      '30 30',
];

// Number of error correction blocks.
const List<String> _numBlocksRows = [
  '1 1 1 1 1 2 2 2 2 4 4 4 4 4 6 6 6 6 7 8 8 9 9 10 12 12 '
      '12 13 14 15 16 17 18 19 19 20 21 22 24 25',
  '1 1 1 2 2 4 4 4 5 5 5 8 9 9 10 10 11 13 14 16 17 17 18 '
      '20 21 23 25 26 28 29 31 33 35 37 38 40 43 45 47 49',
  '1 1 2 2 4 4 6 6 8 8 8 10 12 16 12 17 16 18 21 20 23 23 '
      '25 27 29 34 34 35 38 40 43 45 48 51 53 56 59 62 65 68',
  '1 1 2 4 4 4 5 6 8 8 11 11 16 16 18 16 19 21 25 25 25 34 '
      '30 32 35 37 40 42 45 48 51 54 57 60 63 66 70 74 77 81',
];

List<List<int>> _parse(List<String> rows) => [
      for (final row in rows) [-1, ...row.split(' ').map(int.parse)],
    ];

final List<List<int>> _ecCodewordsPerBlock = _parse(_ecCodewordsPerBlockRows);
final List<List<int>> _numBlocks = _parse(_numBlocksRows);

int _row(QrEcLevel level) => switch (level) {
      QrEcLevel.low => 0,
      QrEcLevel.medium => 1,
      QrEcLevel.quartile => 2,
      QrEcLevel.high => 3,
    };

void _checkVersion(int version) {
  if (version < minVersion || version > maxVersion) {
    throw RangeError.range(version, minVersion, maxVersion, 'version');
  }
}

/// Modules per side of a [version] symbol.
int symbolSize(int version) {
  _checkVersion(version);
  return version * 4 + 17;
}

/// Number of modules available for data and EC codewords (including the
/// remainder bits) once function patterns and format/version areas are
/// excluded.
int rawDataModules(int version) {
  _checkVersion(version);
  var result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    final numAlign = version ~/ 7 + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

/// Total codewords (data + EC) in a [version] symbol (Table 1).
int totalCodewords(int version) => rawDataModules(version) ~/ 8;

/// Error correction codewords per block.
int ecCodewordsPerBlock(int version, QrEcLevel level) {
  _checkVersion(version);
  return _ecCodewordsPerBlock[_row(level)][version];
}

/// Number of error correction blocks.
int numBlocks(int version, QrEcLevel level) {
  _checkVersion(version);
  return _numBlocks[_row(level)][version];
}

/// Number of data codewords (Table 7).
int dataCodewords(int version, QrEcLevel level) =>
    totalCodewords(version) -
    ecCodewordsPerBlock(version, level) * numBlocks(version, level);

/// Data codewords in each block, in block order. Shorter blocks come first
/// and the longer ones hold one extra data codeword (Table 9).
List<int> blockLayout(int version, QrEcLevel level) {
  final blocks = numBlocks(version, level);
  final total = totalCodewords(version);
  final ec = ecCodewordsPerBlock(version, level);
  final numLong = total % blocks;
  final shortData = total ~/ blocks - ec;
  return [
    for (var i = 0; i < blocks; i++)
      i < blocks - numLong ? shortData : shortData + 1,
  ];
}

/// Row/column coordinates of alignment pattern centres (Table E.1).
List<int> alignmentPatternCentres(int version) {
  _checkVersion(version);
  if (version == 1) return const [];
  final numAlign = version ~/ 7 + 2;
  final step = (version * 8 + numAlign * 3 + 5) ~/ (numAlign * 4 - 4) * 2;
  final size = symbolSize(version);
  final result = <int>[6];
  for (var pos = size - 7; result.length < numAlign; pos -= step) {
    result.insert(1, pos);
  }
  return result;
}
