// Byte-for-byte checks against two published worked examples:
//
// 1. ISO/IEC 18004:2015 Annex I.2: "01234567" as a version 1-M symbol.
//    Data and EC codewords are printed in the text (Steps 1-2); the text states
//    that data mask pattern 010 is selected (Step 4); Figure I.2 shows the final
//    symbol (test/fixtures/iso_annex_i_1m_final.txt).
// 2. thonky.com QR Code Tutorial: "HELLO WORLD". The data encoding page gives
//    the 1-Q data codewords, the error correction page works the 1-M EC
//    codewords, and the final page shows the finished 1-Q symbol
//    (test/fixtures/thonky_hello_world_1q_final.txt).
//
// The two sources disagree on mask selection for HELLO WORLD 1-Q. The
// tutorial's data masking page scores all eight masks and says mask 0 has the
// lowest penalty, but its final image carries mask 6 in its format
// information. The penalty reading used here (see penaltyRule3) selects 010
// for the ISO example, as the standard says, and 0 for HELLO WORLD, as the
// masking page says; libqrencode 4 and zint 2 select the same two masks. The
// final-image comparison therefore forces mask 6.

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';
import 'package:qr_gen/src/encoder/codewords.dart';
import 'package:qr_gen/src/encoder/reed_solomon.dart';

import '../support/fixtures.dart';

List<int> _bin(String s) =>
    s.split(' ').map((b) => int.parse(b, radix: 2)).toList();

void _expectGrid(QrMatrix m, List<List<bool>> expected) {
  expect(m.size, expected.length);
  final diffs = <String>[];
  for (var r = 0; r < m.size; r++) {
    for (var c = 0; c < m.size; c++) {
      if (m.isDark(r, c) != expected[r][c]) diffs.add('($r,$c)');
    }
  }
  expect(diffs, isEmpty, reason: 'modules that differ');
}

void main() {
  group('ISO/IEC 18004 Annex I: 01234567 1-M', () {
    final segments = [QrSegment.numeric('01234567')];

    test('data codewords (Step 1)', () {
      expect(
        buildDataCodewords(segments, 1, QrEcLevel.medium),
        _bin('00010000 00100000 00001100 01010110 01100001 10000000 11101100 '
            '00010001 11101100 00010001 11101100 00010001 11101100 00010001 '
            '11101100 00010001'),
      );
    });

    test('error correction codewords (Step 2)', () {
      final data = buildDataCodewords(segments, 1, QrEcLevel.medium);
      expect(
        reedSolomonRemainder(data, 10),
        _bin('10100101 00100100 11010100 11000001 11101101 00110110 11000111 '
            '10000111 00101100 01010101'),
      );
    });

    test('final codeword stream (single block, no interleaving)', () {
      final data = buildDataCodewords(segments, 1, QrEcLevel.medium);
      final all = interleaveWithEc(data, 1, QrEcLevel.medium);
      expect(all.sublist(0, 16), data);
      expect(all.sublist(16), reedSolomonRemainder(data, 10));
    });

    test('mask pattern 010 is selected (Step 4)', () {
      final m = QrEncoder.encode('01234567', ecLevel: QrEcLevel.medium);
      expect(m.version, 1);
      expect(m.ecLevel, QrEcLevel.medium);
      expect(m.mask, 2);
    });

    test('final symbol matches Figure I.2 module for module', () {
      final m = QrEncoder.encode('01234567', ecLevel: QrEcLevel.medium);
      _expectGrid(m, fixtureGrid('iso_annex_i_1m_final.txt'));
    });
  });

  group('thonky.com HELLO WORLD', () {
    final segments = [QrSegment.alphanumeric('HELLO WORLD')];

    test('1-Q data codewords', () {
      expect(buildDataCodewords(segments, 1, QrEcLevel.quartile),
          [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236]);
    });

    test('1-M data and error correction codewords', () {
      final data = buildDataCodewords(segments, 1, QrEcLevel.medium);
      expect(data, [
        32, 91, 11, 120, 209, 114, 220, 77, //
        67, 64, 236, 17, 236, 17, 236, 17,
      ]);
      expect(reedSolomonRemainder(data, 10),
          [196, 35, 39, 119, 235, 215, 231, 226, 93, 23]);
    });

    test('1-Q error correction codewords (read back from the final symbol)',
        () {
      final data = buildDataCodewords(segments, 1, QrEcLevel.quartile);
      expect(reedSolomonRemainder(data, 13),
          [168, 72, 22, 82, 217, 54, 156, 0, 46, 15, 180, 122, 16]);
    });

    test('1-Q mask choice is pattern 0 (data masking page)', () {
      final m = QrEncoder.encode('HELLO WORLD', ecLevel: QrEcLevel.quartile);
      expect(m.version, 1);
      expect(m.mask, 0);
    });

    test('1-Q final symbol (mask 6) matches the tutorial module for module',
        () {
      final m =
          QrEncoder.encode('HELLO WORLD', ecLevel: QrEcLevel.quartile, mask: 6);
      _expectGrid(m, fixtureGrid('thonky_hello_world_1q_final.txt'));
    });
  });
}
