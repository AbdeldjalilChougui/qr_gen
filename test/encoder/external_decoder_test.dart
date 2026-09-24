// Cross-checks against independent, widely used implementations that are
// installed on the development machine:
//
// - zbarimg (ZBar) and ZXingReader (zxing-cpp) decode PNGs written by the
//   test, so every symbol is read back by third-party decoders.
// - qrencode (libqrencode) encodes the same single-mode inputs; the module
//   grids, including the mask it selects, must be identical.
//
// These tools are not part of the Dart toolchain, so each group is skipped
// (with the reason printed) when its tool is not on PATH. See the README,
// "Verification".

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_encoder.dart';

import '../support/png.dart';

final String? _zbar = which('zbarimg');
final String? _zxing = which('ZXingReader');
final String? _qrencode = which('qrencode');

late Directory _tmp;
var _counter = 0;

File _writePng(QrMatrix m, {int scale = 4}) {
  final f = File('${_tmp.path}/qr_${_counter++}.png');
  f.writeAsBytesSync(matrixToPng(m, scale: scale));
  return f;
}

String _zbarDecode(File f) {
  final r =
      Process.runSync(_zbar!, ['-q', '--raw', f.path], stdoutEncoding: utf8);
  expect(r.exitCode, 0, reason: 'zbarimg failed: ${r.stderr}');
  final out = r.stdout as String;
  return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
}

Map<String, Object?> _zxingDecode(File f) {
  final r = Process.runSync(
      _zxing!, ['-json', '-formats', 'QRCode', '-ispure', f.path],
      stdoutEncoding: utf8);
  expect(r.exitCode, 0, reason: 'ZXingReader failed: ${r.stderr}');
  final line = (r.stdout as String).trim().split('\n').first;
  return jsonDecode(line) as Map<String, Object?>;
}

const _levelLetter = {
  QrEcLevel.low: 'L',
  QrEcLevel.medium: 'M',
  QrEcLevel.quartile: 'Q',
  QrEcLevel.high: 'H',
};

final List<String> _samples = [
  '01234567',
  'HELLO WORLD',
  'https://pub.dev/packages/qr_gen',
  'WIFI:T:WPA;S:my network;P:correct horse battery staple;;',
  'Grüße aus Köln',
  'Привет, мир',
  'مرحبا بالعالم',
  '点茗 日本語のテキスト',
  'emoji 😀🎉 mixed 12345678901234567890 TEXT',
  'x' * 1000,
  List.generate(2000, (i) => '${i % 10}').join(),
];

void main() {
  setUpAll(() => _tmp = Directory.systemTemp.createTempSync('qr_gen_test_'));
  tearDownAll(() => _tmp.deleteSync(recursive: true));

  group('ZXingReader (zxing-cpp) decodes our symbols', () {
    test('samples at every EC level', () {
      for (final text in _samples) {
        for (final level in QrEcLevel.values) {
          final m = QrEncoder.encode(text, ecLevel: level);
          final j = _zxingDecode(_writePng(m));
          expect(j['Text'], text, reason: '$text ${level.name}');
          expect(j['Version'], '${m.version}');
          expect(j['ECLevel'], _levelLetter[level]);
          expect(j['DataMask'], m.mask);
        }
      }
    });

    test('every version 1..40 (level M)', () {
      for (var v = 1; v <= 40; v++) {
        final text = 'version $v';
        final m = QrEncoder.encode(text, version: v);
        final j = _zxingDecode(_writePng(m, scale: 3));
        expect(j['Text'], text);
        expect(j['Version'], '$v');
      }
    });

    test('random binary payloads', () {
      final rnd = Random(7);
      for (var i = 0; i < 10; i++) {
        final bytes =
            List.generate(1 + rnd.nextInt(400), (_) => rnd.nextInt(256));
        final m = QrEncoder.encodeBytes(bytes);
        final j = _zxingDecode(_writePng(m, scale: 3));
        final got = (j['Bytes']! as String)
            .split(' ')
            .map((h) => int.parse(h, radix: 16))
            .toList();
        expect(got, bytes);
      }
    });
  }, skip: _zxing == null ? 'ZXingReader not installed' : false);

  group('zbarimg (ZBar) decodes our symbols', () {
    test('samples', () {
      for (final text in _samples) {
        final m = QrEncoder.encode(text);
        final f = _writePng(m);
        // ZBar converts to UTF-8, honouring the ECI designator when present
        // and guessing the character set otherwise.
        expect(_zbarDecode(f), text, reason: text);
      }
    });

    test('every version 1..40 at level H', () {
      for (var v = 1; v <= 40; v++) {
        final text = 'ZBAR $v';
        final m = QrEncoder.encode(text, version: v, ecLevel: QrEcLevel.high);
        expect(_zbarDecode(_writePng(m, scale: 3)), text);
      }
    });
  }, skip: _zbar == null ? 'zbarimg not installed' : false);

  group('libqrencode produces identical symbols', () {
    List<List<bool>> qrencode(
        String text, QrEcLevel level, List<String> extra) {
      final r = Process.runSync(_qrencode!, [
        '-l', _levelLetter[level]!, '-t', 'ASCII', '-m', '0', ...extra, text, //
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return (r.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => [for (var i = 0; i < l.length; i += 2) l[i] == '#'])
          .toList();
    }

    void compare(String text, List<String> extra) {
      for (final level in QrEcLevel.values) {
        final theirs = qrencode(text, level, extra);
        final version = (theirs.length - 17) ~/ 4;
        final ours = QrEncoder.encode(text, ecLevel: level, version: version);
        expect(ours.toRows(), theirs,
            reason: '"$text" ${level.name} v$version');
      }
    }

    test('numeric inputs', () {
      final rnd = Random(3);
      for (var i = 0; i < 12; i++) {
        compare(
            List.generate(1 + rnd.nextInt(600), (_) => '${rnd.nextInt(10)}')
                .join(),
            []);
      }
    });

    test('alphanumeric inputs without digits', () {
      const letters = r'ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
      final rnd = Random(4);
      for (var i = 0; i < 12; i++) {
        compare(
            List.generate(1 + rnd.nextInt(400),
                (_) => letters[rnd.nextInt(letters.length)]).join(),
            []);
      }
    });

    test('8-bit inputs', () {
      final rnd = Random(5);
      for (var i = 0; i < 12; i++) {
        compare(
            List.generate(1 + rnd.nextInt(300),
                (_) => String.fromCharCode(0x61 + rnd.nextInt(26))).join(),
            ['-8']);
      }
    });
  }, skip: _qrencode == null ? 'qrencode not installed' : false);
}
