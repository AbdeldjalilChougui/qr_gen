import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/src/encoder/bch.dart';
import 'package:qr_gen/src/encoder/ec_level.dart';
import 'package:qr_gen/src/encoder/mode.dart';
import 'package:qr_gen/src/encoder/segment.dart';
import 'package:qr_gen/src/encoder/tables.dart';

import '../support/fixtures.dart';

QrEcLevel _level(String s) => switch (s) {
      'L' => QrEcLevel.low,
      'M' => QrEcLevel.medium,
      'Q' => QrEcLevel.quartile,
      'H' => QrEcLevel.high,
      _ => throw ArgumentError(s),
    };

/// Whether [expected] is the largest count of [mode] characters that fits
/// [version]/[level]: [expected] characters fit and one more does not. The
/// check builds real segments and measures their bit length.
bool _isCapacity(QrMode mode, int version, QrEcLevel level, int expected) {
  final capacity = dataCodewords(version, level) * 8;
  QrSegment make(int n) => switch (mode) {
        QrMode.numeric => QrSegment.numeric('7' * n),
        QrMode.alphanumeric => QrSegment.alphanumeric('A' * n),
        QrMode.byte => QrSegment.bytes(List<int>.filled(n, 0x61)),
        QrMode.kanji => QrSegment.kanji('点' * n),
        QrMode.eci => throw ArgumentError('eci'),
      };
  bool fits(int n) {
    final bits = QrSegment.totalBits([make(n)], version);
    return bits != null && bits <= capacity;
  }

  return fits(expected) && !fits(expected + 1);
}

void main() {
  group('ISO/IEC 18004:2015 Table 7 (data capacity)', () {
    final rows = fixtureLines('iso_table7.txt');

    test('fixture covers all 40 versions x 4 levels', () {
      expect(rows, hasLength(160));
    });

    for (final row in rows) {
      final f = row.split(' ');
      final version = int.parse(f[0]);
      final level = _level(f[1]);
      test('version $version-${f[1]}', () {
        expect(dataCodewords(version, level), int.parse(f[2]),
            reason: 'data codewords');
        expect(dataCodewords(version, level) * 8, int.parse(f[3]));
        expect(_isCapacity(QrMode.numeric, version, level, int.parse(f[4])),
            isTrue,
            reason: 'numeric capacity ${f[4]}');
        expect(
            _isCapacity(QrMode.alphanumeric, version, level, int.parse(f[5])),
            isTrue,
            reason: 'alphanumeric capacity ${f[5]}');
        expect(
            _isCapacity(QrMode.byte, version, level, int.parse(f[6])), isTrue,
            reason: 'byte capacity ${f[6]}');
        expect(
            _isCapacity(QrMode.kanji, version, level, int.parse(f[7])), isTrue,
            reason: 'kanji capacity ${f[7]}');
      });
    }
  });

  group('ISO/IEC 18004:2015 Table 9 (error correction blocks)', () {
    final rows = fixtureLines('iso_table9.txt');

    test('fixture covers all 40 versions x 4 levels', () {
      expect(rows, hasLength(160));
    });

    for (final row in rows) {
      final f = row.split(' ');
      final version = int.parse(f[0]);
      final level = _level(f[1]);
      test('version $version-${f[1]}', () {
        final groups =
            f.skip(2).map((g) => g.split(':').map(int.parse).toList()).toList();
        final blocks = groups.fold<int>(0, (s, g) => s + g[0]);
        final total = groups.fold<int>(0, (s, g) => s + g[0] * g[1]);
        expect(totalCodewords(version), total);
        expect(numBlocks(version, level), blocks);
        expect(ecCodewordsPerBlock(version, level),
            groups.first[1] - groups.first[2]);
        expect(blockLayout(version, level), [
          for (final g in groups)
            for (var i = 0; i < g[0]; i++) g[2]
        ]);
      });
    }
  });

  test('ISO Table E.1 alignment pattern centres', () {
    final rows = fixtureLines('iso_tableE1.txt');
    expect(rows, hasLength(40));
    for (final row in rows) {
      final f = row.split(' ').map(int.parse).toList();
      final version = f[0];
      final centres = f.skip(2).toList();
      expect(alignmentPatternCentres(version), centres, reason: 'v$version');
      final n = centres.length;
      expect(n == 0 ? 0 : n * n - 3, f[1], reason: 'count v$version');
    }
  });

  test('ISO Table D.1 version information (BCH 18,6)', () {
    final rows = fixtureLines('iso_tableD1.txt');
    expect(rows, hasLength(34));
    for (final row in rows) {
      final f = row.split(' ');
      expect(versionInformation(int.parse(f[0])), int.parse(f[1], radix: 16),
          reason: 'v${f[0]}');
    }
  });

  test('ISO Table C.1 format information (BCH 15,5, masked)', () {
    final rows = fixtureLines('iso_tableC1.txt');
    expect(rows, hasLength(32));
    const levels = {
      1: QrEcLevel.low,
      0: QrEcLevel.medium,
      3: QrEcLevel.quartile,
      2: QrEcLevel.high,
    };
    for (final row in rows) {
      final f = row.split(' ');
      final data = int.parse(f[0], radix: 2);
      final level = levels[data >> 3]!;
      expect(formatInformation(level, data & 7), int.parse(f[1], radix: 16),
          reason: f[0]);
    }
  });

  test('symbol size is 4v + 17', () {
    expect(symbolSize(1), 21);
    expect(symbolSize(7), 45);
    expect(symbolSize(40), 177);
  });
}
