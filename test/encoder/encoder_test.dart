import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_encoder.dart';
import 'package:qr_gen/src/encoder/tables.dart' show dataCodewords;

void main() {
  test('the encoder is pure Dart (no Flutter or dart:ui imports)', () {
    final files = [
      File('lib/qr_encoder.dart'),
      ...Directory('lib/src/encoder').listSync().whereType<File>(),
    ];
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains('package:flutter'), isFalse, reason: f.path);
      expect(src.contains('dart:ui'), isFalse, reason: f.path);
    }
  });

  group('version selection', () {
    test('picks the smallest version that fits', () {
      // 1-L holds 41 digits, 2-L holds 77 (ISO Table 7).
      expect(QrEncoder.encode('1' * 41, ecLevel: QrEcLevel.low).version, 1);
      expect(QrEncoder.encode('1' * 42, ecLevel: QrEcLevel.low).version, 2);
      expect(QrEncoder.encode('1' * 77, ecLevel: QrEcLevel.low).version, 2);
      expect(QrEncoder.encode('1' * 78, ecLevel: QrEcLevel.low).version, 3);
      // Higher levels need bigger symbols for the same data.
      expect(QrEncoder.encode('a' * 14, ecLevel: QrEcLevel.medium).version, 1);
      expect(QrEncoder.encode('a' * 14, ecLevel: QrEcLevel.high).version, 2);
    });

    test('accounts for wider count indicators from version 10', () {
      // 9-L holds 230 bytes. 231 bytes need version 10, where the byte count
      // indicator is 16 bits.
      expect(QrEncoder.encode('a' * 230, ecLevel: QrEcLevel.low).version, 9);
      expect(QrEncoder.encode('a' * 231, ecLevel: QrEcLevel.low).version, 10);
    });

    test('minimumVersion agrees with encode', () {
      for (final n in [1, 20, 100, 500, 1000]) {
        final text = 'x' * n;
        expect(QrEncoder.minimumVersion(text), QrEncoder.encode(text).version);
      }
      expect(QrEncoder.minimumVersion('a' * 3000), isNull);
    });

    test('minVersion and maxVersion bound the search', () {
      expect(QrEncoder.encode('hi', minVersion: 5).version, 5);
      expect(() => QrEncoder.encode('a' * 100, maxVersion: 3),
          throwsA(isA<QrDataTooLongException>()));
    });

    test('a fixed version is honoured or rejected', () {
      final m = QrEncoder.encode('hi', version: 7);
      expect(m.version, 7);
      expect(m.size, 45);
      expect(() => QrEncoder.encode('a' * 100, version: 1),
          throwsA(isA<QrDataTooLongException>()));
    });
  });

  group('errors', () {
    test('data too long for version 40 throws QrDataTooLongException', () {
      final e =
          _catch(() => QrEncoder.encode('a' * 2954, ecLevel: QrEcLevel.low));
      expect(e, isA<QrDataTooLongException>());
      final t = e as QrDataTooLongException;
      expect(t.bitsAvailable, dataCodewords(40, QrEcLevel.low) * 8);
      expect(t.bitsNeeded, greaterThan(t.bitsAvailable));
      expect(t.toString(), contains('QrDataTooLongException'));
    });

    test('invalid arguments throw RangeError', () {
      expect(() => QrEncoder.encode('x', version: 0), throwsRangeError);
      expect(() => QrEncoder.encode('x', version: 41), throwsRangeError);
      expect(() => QrEncoder.encode('x', mask: 8), throwsRangeError);
      expect(() => QrEncoder.encode('x', minVersion: 5, maxVersion: 4),
          throwsRangeError);
    });
  });

  group('QrMatrix', () {
    test('reports version, level, mask and size', () {
      final m = QrEncoder.encode('HELLO', ecLevel: QrEcLevel.high);
      expect(m.version, 1);
      expect(m.ecLevel, QrEcLevel.high);
      expect(m.mask, inInclusiveRange(0, 7));
      expect(m.size, 21);
      expect(m.toRows(), hasLength(21));
      expect(m.toRows().every((r) => r.length == 21), isTrue);
    });

    test('finder patterns are in the three corners', () {
      final m = QrEncoder.encode('finder');
      for (final (r, c) in [(0, 0), (0, m.size - 7), (m.size - 7, 0)]) {
        expect(m.isDark(r, c), isTrue);
        expect(m.isDark(r + 1, c + 1), isFalse);
        expect(m.isDark(r + 3, c + 3), isTrue);
        expect(m.isFinderModule(r + 3, c + 3), isTrue);
      }
      expect(m.isFinderModule(m.size - 1, m.size - 1), isFalse);
    });

    test('isDark checks bounds', () {
      final m = QrEncoder.encode('x');
      expect(() => m.isDark(-1, 0), throwsRangeError);
      expect(() => m.isDark(0, 21), throwsRangeError);
    });

    test('toString draws the grid', () {
      final s = QrEncoder.encode('x').toString();
      expect(s.split('\n').where((l) => l.isNotEmpty), hasLength(21));
    });

    test('encoding is deterministic', () {
      final a = QrEncoder.encode('same input').toRows();
      final b = QrEncoder.encode('same input').toRows();
      expect(a, b);
    });
  });
}

Object? _catch(void Function() f) {
  try {
    f();
  } catch (e) {
    return e;
  }
  return null;
}
