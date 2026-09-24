/// Module placement (ISO/IEC 18004:2015, 7.7), masking (7.8) and format and
/// version information placement (7.9, 7.10).
library;

import 'dart:typed_data';

import 'bch.dart';
import 'ec_level.dart';
import 'mask.dart';
import 'tables.dart';

/// Builds the module grid of one symbol. Modules are stored row-major with
/// 1 = dark.
class MatrixBuilder {
  /// Starts a [version] symbol with all function patterns drawn.
  MatrixBuilder(this.version)
      : size = symbolSize(version),
        modules = Uint8List(symbolSize(version) * symbolSize(version)),
        function = Uint8List(symbolSize(version) * symbolSize(version)) {
    _drawFunctionPatterns();
  }

  /// Symbol version.
  final int version;

  /// Modules per side.
  final int size;

  /// Module colours, row-major, 1 = dark.
  final Uint8List modules;

  /// 1 where a module belongs to a function pattern or a reserved area.
  final Uint8List function;

  void _set(int row, int col, bool dark) {
    modules[row * size + col] = dark ? 1 : 0;
    function[row * size + col] = 1;
  }

  void _drawFunctionPatterns() {
    for (var i = 0; i < size; i++) {
      _set(6, i, i.isEven);
      _set(i, 6, i.isEven);
    }
    _drawFinder(3, 3);
    _drawFinder(3, size - 4);
    _drawFinder(size - 4, 3);
    final centres = alignmentPatternCentres(version);
    final last = centres.length - 1;
    for (var i = 0; i < centres.length; i++) {
      for (var j = 0; j < centres.length; j++) {
        if ((i == 0 && j == 0) ||
            (i == 0 && j == last) ||
            (i == last && j == 0)) {
          continue;
        }
        _drawAlignment(centres[i], centres[j]);
      }
    }
    drawFormatBits(QrEcLevel.medium, 0); // Reserve; overwritten later.
    _drawVersion();
  }

  void _drawFinder(int row, int col) {
    for (var dr = -4; dr <= 4; dr++) {
      for (var dc = -4; dc <= 4; dc++) {
        final r = row + dr, c = col + dc;
        if (r < 0 || r >= size || c < 0 || c >= size) continue;
        final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
        _set(r, c, dist != 2 && dist != 4);
      }
    }
  }

  void _drawAlignment(int row, int col) {
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
        _set(row + dr, col + dc, dist != 1);
      }
    }
  }

  /// Writes both copies of the format information for [level] and [mask],
  /// plus the dark module.
  void drawFormatBits(QrEcLevel level, int mask) {
    final bits = formatInformation(level, mask);
    bool bit(int i) => (bits >> i) & 1 == 1;
    for (var i = 0; i <= 5; i++) {
      _set(i, 8, bit(i));
    }
    _set(7, 8, bit(6));
    _set(8, 8, bit(7));
    _set(8, 7, bit(8));
    for (var i = 9; i < 15; i++) {
      _set(8, 14 - i, bit(i));
    }
    for (var i = 0; i < 8; i++) {
      _set(8, size - 1 - i, bit(i));
    }
    for (var i = 8; i < 15; i++) {
      _set(size - 15 + i, 8, bit(i));
    }
    _set(size - 8, 8, true);
  }

  void _drawVersion() {
    if (version < 7) return;
    final bits = versionInformation(version);
    for (var i = 0; i < 18; i++) {
      final dark = (bits >> i) & 1 == 1;
      final a = size - 11 + i % 3, b = i ~/ 3;
      _set(b, a, dark);
      _set(a, b, dark);
    }
  }

  /// Places [codewords] in the two-module-wide zigzag, starting at the bottom
  /// right. Remainder bits stay light.
  void placeCodewords(List<int> codewords) {
    final totalBits = codewords.length * 8;
    var i = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      final upward = (right + 1) & 2 == 0;
      for (var vert = 0; vert < size; vert++) {
        final row = upward ? size - 1 - vert : vert;
        for (var j = 0; j < 2; j++) {
          final col = right - j;
          if (function[row * size + col] == 1) continue;
          if (i < totalBits) {
            modules[row * size + col] =
                (codewords[i >> 3] >> (7 - (i & 7))) & 1;
            i++;
          }
        }
      }
    }
    if (i != totalBits) {
      throw StateError('Placed $i of $totalBits bits');
    }
  }

  /// XORs mask [mask] over every non-function module. Applying it twice
  /// undoes it.
  void applyMask(int mask) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final idx = r * size + c;
        if (function[idx] == 0 && maskBit(mask, r, c)) modules[idx] ^= 1;
      }
    }
  }

  /// Chooses the mask with the lowest penalty score (the lowest-numbered
  /// mask wins ties), applies it and writes the matching format information.
  /// Returns the mask.
  int applyBestMask(QrEcLevel level) {
    var best = 0;
    var bestScore = -1;
    for (var m = 0; m < 8; m++) {
      applyMask(m);
      drawFormatBits(level, m);
      final score = penaltyScore(modules, size);
      if (bestScore < 0 || score < bestScore) {
        best = m;
        bestScore = score;
      }
      applyMask(m);
    }
    applyMask(best);
    drawFormatBits(level, best);
    return best;
  }
}
