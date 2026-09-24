import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_encoder.dart';

import '../support/decoder.dart';

const _ecBits = {
  QrEcLevel.low: 1,
  QrEcLevel.medium: 0,
  QrEcLevel.quartile: 3,
  QrEcLevel.high: 2,
};

void _roundTrip(String text,
    {QrEcLevel ecLevel = QrEcLevel.medium, int? version}) {
  final m = QrEncoder.encode(text, ecLevel: ecLevel, version: version);
  final d = decodeGrid(m.toRows());
  expect(d.text, text, reason: 'decoded text');
  expect(d.version, m.version);
  expect(d.mask, m.mask);
  expect(d.ecBits, _ecBits[ecLevel]);
}

void main() {
  group('round trip through the test-only decoder', () {
    test('reference strings', () {
      _roundTrip('01234567');
      _roundTrip('HELLO WORLD', ecLevel: QrEcLevel.quartile);
      _roundTrip('https://example.com/path?q=1&r=two');
      _roundTrip('Grüße aus Köln');
      _roundTrip('Привет, мир! 你好 🌍');
      _roundTrip('点茗 QR コード 2026');
      _roundTrip('');
    });

    test('large mixed payloads at every level', () {
      final rnd = Random(40);
      for (var v = 1; v <= 40; v++) {
        for (final level in QrEcLevel.values) {
          // Fill most of the capacity with mixed content.
          final bytes = (v * v * 2 + 10).clamp(1, 1200);
          final text = List.generate(
              bytes, (i) => String.fromCharCode(0x20 + rnd.nextInt(95))).join();
          final m = QrEncoder.encode(text, ecLevel: level, version: null);
          final d = decodeGrid(m.toRows());
          expect(d.text, text, reason: 'v$v ${level.name}');
        }
      }
    });

    test('each fixed version 1..40 decodes', () {
      for (var v = 1; v <= 40; v++) {
        for (final level in QrEcLevel.values) {
          _roundTrip('QR $v', ecLevel: level, version: v);
        }
      }
    });

    test('each forced mask decodes', () {
      for (var mask = 0; mask < 8; mask++) {
        final m = QrEncoder.encode('mask test', mask: mask);
        expect(m.mask, mask);
        expect(decodeGrid(m.toRows()).text, 'mask test');
      }
    });

    test('random mixed-mode strings', () {
      final rnd = Random(2015);
      const pool = '0123456789ABCDEFXYZ \$%*+-./:abcxyzéü€点茗日本語Жж😀';
      final runes = pool.runes.toList();
      for (var i = 0; i < 60; i++) {
        final len = rnd.nextInt(120);
        final text = String.fromCharCodes(
            List.generate(len, (_) => runes[rnd.nextInt(runes.length)]));
        _roundTrip(text, ecLevel: QrEcLevel.values[rnd.nextInt(4)]);
      }
    });

    test('raw bytes', () {
      final bytes = List.generate(300, (i) => (i * 37) & 0xFF);
      final m = QrEncoder.encodeBytes(bytes, ecLevel: QrEcLevel.low);
      expect(decodeGrid(m.toRows()).bytes, bytes);
    });

    test('maximum capacity: 7089 digits, 4296 alphanumerics, 2953 bytes', () {
      final digits = List.generate(7089, (i) => '${i % 10}').join();
      final m = QrEncoder.encode(digits, ecLevel: QrEcLevel.low);
      expect(m.version, 40);
      expect(decodeGrid(m.toRows()).text, digits);

      final alnum = 'AB' * 2148;
      expect(QrEncoder.encode(alnum, ecLevel: QrEcLevel.low).version, 40);

      final bytes = 'a' * 2953;
      final mb = QrEncoder.encode(bytes, ecLevel: QrEcLevel.low);
      expect(mb.version, 40);
      expect(utf8.encode(decodeGrid(mb.toRows()).text), utf8.encode(bytes));
    });
  });
}
