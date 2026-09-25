// Byte-for-byte checks against reference symbols.
//
// 1. ISO/IEC 18004:2015 Annex I: "01234567" as a version 1-M symbol. The
//    standard gives the data codewords, the error correction codewords and
//    the selected data mask pattern (010).
// 2. Symbols generated with qrencode 4.1.1 (libqrencode) for "01234567" 1-M
//    and "HELLO WORLD" 1-M and 1-Q (test/fixtures/qrencode_*.txt; the command
//    line is in each file's header). Their codewords are read back with the
//    test-only decoder (test/support/decoder.dart), which also confirms the
//    text, version, level and mask. The encoder must reproduce the codewords,
//    the mask and every module.

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';
import 'package:qr_gen/src/encoder/codewords.dart';
import 'package:qr_gen/src/encoder/reed_solomon.dart';

import '../support/decoder.dart';
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

/// Checks our encoder against a qrencode-generated fixture.
void _checkQrencodeFixture({
  required String fixture,
  required String text,
  required QrSegment segment,
  required QrEcLevel level,
  required int ecBits,
  required int ecLength,
}) {
  final grid = fixtureGrid(fixture);
  final reference = decodeGrid(grid);

  test('fixture decodes to the input (test-only decoder)', () {
    expect(reference.text, text);
    expect(reference.version, 1);
    expect(reference.ecBits, ecBits);
  });

  test('data codewords match', () {
    expect(
        buildDataCodewords([segment], 1, level), reference.dataBlocks.single);
  });

  test('error correction codewords match', () {
    final data = buildDataCodewords([segment], 1, level);
    expect(reedSolomonRemainder(data, ecLength), reference.ecBlocks.single);
  });

  test('mask choice matches (${reference.mask})', () {
    expect(QrEncoder.encode(text, ecLevel: level).mask, reference.mask);
  });

  test('final symbol matches module for module', () {
    _expectGrid(QrEncoder.encode(text, ecLevel: level), grid);
  });
}

void main() {
  group('ISO/IEC 18004:2015 Annex I: 01234567 1-M', () {
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
  });

  group('qrencode 4.1.1: 01234567 1-M', () {
    _checkQrencodeFixture(
      fixture: 'qrencode_01234567_1m.txt',
      text: '01234567',
      segment: QrSegment.numeric('01234567'),
      level: QrEcLevel.medium,
      ecBits: 0,
      ecLength: 10,
    );
  });

  group('qrencode 4.1.1: HELLO WORLD 1-M', () {
    _checkQrencodeFixture(
      fixture: 'qrencode_hello_world_1m.txt',
      text: 'HELLO WORLD',
      segment: QrSegment.alphanumeric('HELLO WORLD'),
      level: QrEcLevel.medium,
      ecBits: 0,
      ecLength: 10,
    );
  });

  group('qrencode 4.1.1: HELLO WORLD 1-Q', () {
    _checkQrencodeFixture(
      fixture: 'qrencode_hello_world_1q.txt',
      text: 'HELLO WORLD',
      segment: QrSegment.alphanumeric('HELLO WORLD'),
      level: QrEcLevel.quartile,
      ecBits: 3,
      ecLength: 13,
    );
  });
}
