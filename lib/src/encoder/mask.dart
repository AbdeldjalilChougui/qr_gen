/// Data mask patterns and the mask penalty score (ISO/IEC 18004:2015, 7.8).
library;

import 'dart:typed_data';

/// Whether mask pattern [mask] inverts the module at [row], [col] (Table 10).
bool maskBit(int mask, int row, int col) {
  final i = row, j = col;
  switch (mask) {
    case 0:
      return (i + j) % 2 == 0;
    case 1:
      return i % 2 == 0;
    case 2:
      return j % 3 == 0;
    case 3:
      return (i + j) % 3 == 0;
    case 4:
      return (i ~/ 2 + j ~/ 3) % 2 == 0;
    case 5:
      return (i * j) % 2 + (i * j) % 3 == 0;
    case 6:
      return ((i * j) % 2 + (i * j) % 3) % 2 == 0;
    case 7:
      return ((i + j) % 2 + (i * j) % 3) % 2 == 0;
  }
  throw RangeError.range(mask, 0, 7, 'mask');
}

/// Feature 1: adjacent modules of one colour in a row or column. A run of
/// 5 + i modules scores 3 + i.
int penaltyRule1(Uint8List m, int size) {
  var score = 0;
  for (var pass = 0; pass < 2; pass++) {
    for (var a = 0; a < size; a++) {
      var run = 0;
      var colour = -1;
      for (var b = 0; b < size; b++) {
        final v = pass == 0 ? m[a * size + b] : m[b * size + a];
        if (v == colour) {
          run++;
        } else {
          if (run >= 5) score += run - 2;
          colour = v;
          run = 1;
        }
      }
      if (run >= 5) score += run - 2;
    }
  }
  return score;
}

/// Feature 2: every 2x2 block of one colour scores 3 (overlapping blocks are
/// counted separately, which equals 3 x (m - 1) x (n - 1) for an m x n block).
int penaltyRule2(Uint8List m, int size) {
  var score = 0;
  for (var r = 0; r < size - 1; r++) {
    for (var c = 0; c < size - 1; c++) {
      final v = m[r * size + c];
      if (v == m[r * size + c + 1] &&
          v == m[(r + 1) * size + c] &&
          v == m[(r + 1) * size + c + 1]) {
        score += 3;
      }
    }
  }
  return score;
}

/// Feature 3: a dark:light:dark:light:dark run pattern in the ratio
/// 1:1:3:1:1 (runs of n, n, 3n, n, n modules) in a row or column, preceded
/// or followed by a light area at least 4n modules wide, scores 40 per
/// occurrence (once, even if both sides are light).
///
/// Space outside the symbol counts as light, because the symbol is always
/// surrounded by the light quiet zone. With this reading the encoder selects
/// the mask given in the ISO/IEC 18004:2015 Annex I example (010) and the
/// same masks as libqrencode.
int penaltyRule3(Uint8List m, int size) {
  var score = 0;
  final runs = List<int>.filled(size + 2, 0);
  for (var pass = 0; pass < 2; pass++) {
    for (var a = 0; a < size; a++) {
      // runs[0] is a light run (possibly empty); runs alternate light/dark,
      // so dark runs sit at odd indices.
      var count = 0;
      var colour = 0;
      var len = 0;
      for (var b = 0; b < size; b++) {
        final v = pass == 0 ? m[a * size + b] : m[b * size + a];
        if (v == colour) {
          len++;
        } else {
          runs[count++] = len;
          colour = v;
          len = 1;
        }
      }
      runs[count++] = len;
      for (var i = 3; i + 2 < count; i += 2) {
        final n = runs[i] ~/ 3;
        if (n == 0 || runs[i] % 3 != 0) continue;
        if (runs[i - 2] != n ||
            runs[i - 1] != n ||
            runs[i + 1] != n ||
            runs[i + 2] != n) {
          continue;
        }
        // A light run that touches the symbol edge continues into the quiet
        // zone: runs[0] (before, when i == 3) and the last run (after).
        final lightBefore = i == 3 || runs[i - 3] >= 4 * n;
        final lightAfter = i + 4 >= count || runs[i + 3] >= 4 * n;
        if (lightBefore || lightAfter) score += 40;
      }
    }
  }
  return score;
}

/// Feature 4: 10 points for each full 5% step the proportion of dark
/// modules deviates from 50%, beyond the 45%-55% band.
int penaltyRule4(Uint8List m, int size) {
  var dark = 0;
  for (final v in m) {
    dark += v;
  }
  final total = size * size;
  // k = ceil(|dark% - 50| / 5) - 1, computed in integers.
  final k = (((dark * 20 - total * 10).abs() + total - 1) ~/ total) - 1;
  return (k < 0 ? 0 : k) * 10;
}

/// Sum of the four penalty features for the symbol [m] of [size] x [size].
int penaltyScore(Uint8List m, int size) =>
    penaltyRule1(m, size) +
    penaltyRule2(m, size) +
    penaltyRule3(m, size) +
    penaltyRule4(m, size);
