import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';
import 'package:qr_gen/src/encoder/segmenter.dart';

String _bits(QrSegment s) => s.bits.map((b) => b ? '1' : '0').join();

void main() {
  group('segment bit encodings (ISO 7.4)', () {
    test('numeric groups of 3, 2 and 1 digits', () {
      // ISO 7.4.3 example: 01234567 -> 012 345 67.
      final s = QrSegment.numeric('01234567');
      expect(s.mode, QrMode.numeric);
      expect(s.numChars, 8);
      expect(_bits(s), '0000001100' '0101011001' '1000011');
      expect(_bits(QrSegment.numeric('8')), '1000');
    });

    test('alphanumeric pairs (ISO 7.4.4 example AC-42)', () {
      final s = QrSegment.alphanumeric('AC-42');
      expect(_bits(s), '00111001110' '11100111001' '000010');
    });

    test('byte mode is 8 bits per byte', () {
      final s = QrSegment.bytes([0x00, 0xff, 0x41]);
      expect(_bits(s), '00000000' '11111111' '01000001');
      expect(s.numChars, 3);
    });

    test('kanji mode (ISO 7.4.6 examples)', () {
      // 点 = 0x935F -> 0xD9F, 茗 = 0xE4AA -> 0x1AAA.
      expect(_bits(QrSegment.kanji('点')), '0110110011111');
      expect(_bits(QrSegment.kanji('茗')), '1101010101010');
      expect(QrSegment.canEncodeKanji('点'.runes.first), isTrue);
      expect(QrSegment.canEncodeKanji('A'.runes.first), isFalse);
      expect(QrSegment.canEncodeKanji('é'.runes.first), isFalse);
    });

    test('ECI designators of 1, 2 and 3 bytes (ISO 7.4.2.2)', () {
      expect(_bits(QrSegment.eci(26)), '00011010');
      expect(_bits(QrSegment.eci(1000)), '10' '00001111101000');
      expect(_bits(QrSegment.eci(100000)), '110' '000011000011010100000');
    });

    test('invalid input is rejected', () {
      expect(() => QrSegment.numeric('12a'), throwsArgumentError);
      expect(() => QrSegment.alphanumeric('abc'), throwsArgumentError);
      expect(() => QrSegment.kanji('A'), throwsArgumentError);
      expect(() => QrSegment.bytes([256]), throwsArgumentError);
      expect(() => QrSegment.eci(1000000), throwsArgumentError);
    });

    test('total bits includes mode indicator and count indicator', () {
      // 4 + 10 + 27 for 1-M numeric 01234567.
      expect(QrSegment.totalBits([QrSegment.numeric('01234567')], 1), 41);
      // Count indicator widths change at versions 10 and 27.
      expect(
          QrSegment.totalBits([
            QrSegment.bytes([1])
          ], 9),
          4 + 8 + 8);
      expect(
          QrSegment.totalBits([
            QrSegment.bytes([1])
          ], 10),
          4 + 16 + 8);
      expect(QrSegment.totalBits([QrSegment.numeric('1')], 27), 4 + 14 + 4);
      // 256 bytes do not fit an 8-bit count indicator.
      expect(
          QrSegment.totalBits([QrSegment.bytes(List.filled(256, 1))], 9), null);
    });
  });

  group('optimal segmentation', () {
    test('pure inputs use a single segment of the tightest mode', () {
      expect(segmentText('0123456789', version: 1).single.mode, QrMode.numeric);
      expect(segmentText('HELLO WORLD', version: 1).single.mode,
          QrMode.alphanumeric);
      expect(segmentText('hello', version: 1).single.mode, QrMode.byte);
      expect(segmentText('点茗', version: 1).single.mode, QrMode.kanji);
      expect(segmentText('', version: 1), isEmpty);
    });

    test('non-Latin-1 text gets a UTF-8 ECI designator', () {
      final segs = segmentText('héllo мир', version: 1, kanji: false);
      expect(segs.first.mode, QrMode.eci);
      expect(segs.first.bits.length, 8);
      expect(segs[1].mode, QrMode.byte);
      expect(segs[1].numChars, utf8.encode('héllo мир').length);
    });

    test('Latin-1 text is byte mode without ECI', () {
      final segs = segmentText('héllo', version: 1);
      expect(segs.single.mode, QrMode.byte);
      expect(segs.single.numChars, 5);
    });

    test('ECI can be turned off (UTF-8 bytes without a designator)', () {
      final segs = segmentText('мир', version: 1, kanji: false, utf8Eci: false);
      expect(segs.single.mode, QrMode.byte);
      expect(segs.single.numChars, 6);
    });

    test('long digit runs inside text become numeric segments', () {
      final segs =
          segmentText('abc0123456789012345678901234567890xyz', version: 1);
      expect(segs.map((s) => s.mode).toList(),
          [QrMode.byte, QrMode.numeric, QrMode.byte]);
    });

    test('matches exhaustive search on random short strings', () {
      final rnd = Random(18004);
      const alphabet = ['0', '7', 'A', 'Z', ' ', r'$', 'a', 'z', 'é', '点', 'Ж'];
      for (var round = 0; round < 150; round++) {
        final len = 1 + rnd.nextInt(6);
        final text =
            List.generate(len, (_) => alphabet[rnd.nextInt(alphabet.length)])
                .join();
        for (final version in [1, 10, 27]) {
          final ours =
              QrSegment.totalBits(segmentText(text, version: version), version);
          expect(ours, _bruteForce(text, version),
              reason: '"$text" at version $version');
          // And the segments reproduce the text.
          expect(_decodeSegments(segmentText(text, version: version)), text);
        }
      }
    });
  });
}

const _alnum = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

/// Minimum bit length over every per-character mode assignment.
int _bruteForce(String text, int version) {
  final runes = text.runes.toList();
  var best = 1 << 30;
  for (final utf8Scheme in [false, true]) {
    final options = <List<QrMode>>[];
    var feasible = true;
    for (final r in runes) {
      final c = String.fromCharCode(r);
      final m = <QrMode>[];
      if ('0123456789'.contains(c)) m.add(QrMode.numeric);
      if (_alnum.contains(c)) m.add(QrMode.alphanumeric);
      if (utf8Scheme || r < 256) m.add(QrMode.byte);
      if (QrSegment.canEncodeKanji(r)) m.add(QrMode.kanji);
      if (m.isEmpty) feasible = false;
      options.add(m);
    }
    if (!feasible) continue;
    void walk(int i, List<QrMode> chosen) {
      if (i == runes.length) {
        final segs = <QrSegment>[if (utf8Scheme) QrSegment.eci(26)];
        var start = 0;
        for (var j = 1; j <= runes.length; j++) {
          if (j == runes.length || chosen[j] != chosen[start]) {
            final part = String.fromCharCodes(runes.sublist(start, j));
            segs.add(switch (chosen[start]) {
              QrMode.numeric => QrSegment.numeric(part),
              QrMode.alphanumeric => QrSegment.alphanumeric(part),
              QrMode.kanji => QrSegment.kanji(part),
              _ => QrSegment.bytes(
                  utf8Scheme ? utf8.encode(part) : latin1.encode(part)),
            });
            start = j;
          }
        }
        final bits = QrSegment.totalBits(segs, version);
        if (bits != null && bits < best) best = bits;
        return;
      }
      for (final m in options[i]) {
        chosen.add(m);
        walk(i + 1, chosen);
        chosen.removeLast();
      }
    }

    walk(0, []);
  }
  return best;
}

/// Reassembles text from segments (test helper; mirrors decoder behaviour).
String _decodeSegments(List<QrSegment> segs) {
  var utf8Mode = false;
  final out = StringBuffer();
  for (final s in segs) {
    switch (s.mode) {
      case QrMode.eci:
        utf8Mode = true;
      case QrMode.byte:
        final bytes = <int>[];
        for (var i = 0; i < s.bits.length; i += 8) {
          var v = 0;
          for (var k = 0; k < 8; k++) {
            v = (v << 1) | (s.bits[i + k] ? 1 : 0);
          }
          bytes.add(v);
        }
        out.write(utf8Mode ? utf8.decode(bytes) : latin1.decode(bytes));
      default:
        out.write(s.text);
    }
  }
  return out.toString();
}
