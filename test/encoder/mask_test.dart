import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/src/encoder/mask.dart';

Uint8List _grid(List<String> rows) {
  final n = rows.length;
  final out = Uint8List(n * n);
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      out[r * n + c] = rows[r][c] == '1' ? 1 : 0;
    }
  }
  return out;
}

void main() {
  group('mask conditions (ISO Table 10, i = row, j = column)', () {
    test('each pattern matches its formula', () {
      bool ref(int m, int i, int j) => switch (m) {
            0 => (i + j) % 2 == 0,
            1 => i % 2 == 0,
            2 => j % 3 == 0,
            3 => (i + j) % 3 == 0,
            4 => (i ~/ 2 + j ~/ 3) % 2 == 0,
            5 => (i * j) % 2 + (i * j) % 3 == 0,
            6 => ((i * j) % 2 + (i * j) % 3) % 2 == 0,
            _ => ((i + j) % 2 + (i * j) % 3) % 2 == 0,
          };
      for (var m = 0; m < 8; m++) {
        for (var i = 0; i < 30; i++) {
          for (var j = 0; j < 30; j++) {
            expect(maskBit(m, i, j), ref(m, i, j), reason: 'mask $m ($i,$j)');
          }
        }
      }
    });
  });

  group('penalty rules (ISO 7.8.3.1)', () {
    test('N1: runs of 5 or more score 3 + (length - 5)', () {
      // Row 0: run of 7 dark (3 + 2) and the rest alternates.
      // Columns alternate so they add nothing.
      final g = _grid([
        '11111110',
        '01010101',
        '10101010',
        '01010101',
        '10101010',
        '01010101',
        '10101010',
        '01010101',
      ]);
      expect(penaltyRule1(g, 8), 5);
    });

    test('N1 counts rows and columns, both colours', () {
      final light = Uint8List(21 * 21);
      // Each of 21 rows and 21 columns is one run of 21: 3 + 16 = 19.
      expect(penaltyRule1(light, 21), 19 * 42);
    });

    test('N2: 3 per overlapping 2x2 same-colour block', () {
      final light = Uint8List(21 * 21);
      expect(penaltyRule2(light, 21), 3 * 20 * 20);
      final g = _grid(['1100', '1100', '0010', '0101']);
      // Blocks: (0,0) dark; (0,2) light 0,0/0,0? rows 0-1 cols 2-3 = 0000.
      expect(penaltyRule2(g, 4), 6);
    });

    test('N3: 1:1:3:1:1 run pattern with 4 light modules on one side', () {
      int row(String r) {
        final rows = List.filled(r.length, '0' * r.length);
        rows[0] = r;
        return penaltyRule3(_grid(rows), r.length);
      }

      // Light area after the pattern.
      expect(row('1100101110100001'), 40);
      // Light area before the pattern.
      expect(row('1000010111010011'), 40);
      // Light on both sides still counts once.
      expect(row('000010111010000'), 40);
      // Only 2 light modules on each side: no penalty.
      expect(row('1100101110100111'), 0);
      // The outer dark runs must be exactly 1 wide (2:1:3:1:1 is not it).
      expect(row('0000110111010000'), 0);
    });

    test('N3: the quiet zone counts as light', () {
      int row(String r) {
        final rows = List.filled(r.length, '0' * r.length);
        rows[0] = r;
        return penaltyRule3(_grid(rows), r.length);
      }

      // Pattern starting at the left edge.
      expect(row('101110101111111'), 40);
      // Pattern ending at the right edge.
      expect(row('111111101011101'), 40);
      // A short light run that reaches the edge continues into the quiet zone.
      expect(row('1110101110100'), 40);
    });

    test('N3: scaled ratios (2:2:6:2:2) count too', () {
      final rows = List.filled(30, '0' * 30);
      rows[0] = '000000001100111111001100000000';
      expect(penaltyRule3(_grid(rows), 30), 40);
    });

    test('N3 also scans columns', () {
      final rows = List.generate(11, (_) => '00000000000'.split(''));
      const col = '10111010000';
      for (var r = 0; r < 11; r++) {
        rows[r][3] = col[r];
      }
      expect(penaltyRule3(_grid(rows.map((r) => r.join()).toList()), 11), 40);
    });

    test('N4: 10 per 5% step away from 50% dark', () {
      Uint8List withDark(int dark) {
        final g = Uint8List(100 * 100 ~/ 100 * 1)..fillRange(0, dark, 1);
        return g;
      }

      expect(penaltyRule4(withDark(50), 10), 0);
      expect(penaltyRule4(withDark(45), 10), 0);
      expect(penaltyRule4(withDark(55), 10), 0);
      expect(penaltyRule4(withDark(44), 10), 10);
      expect(penaltyRule4(withDark(60), 10), 10);
      expect(penaltyRule4(withDark(61), 10), 20);
      expect(penaltyRule4(withDark(0), 10), 90);
      expect(penaltyRule4(withDark(100), 10), 90);
    });

    test('total is the sum of the four rules', () {
      final light = Uint8List(21 * 21);
      expect(
        penaltyScore(light, 21),
        penaltyRule1(light, 21) +
            penaltyRule2(light, 21) +
            penaltyRule3(light, 21) +
            penaltyRule4(light, 21),
      );
    });
  });
}
