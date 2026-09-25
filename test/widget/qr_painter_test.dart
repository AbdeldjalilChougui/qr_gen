import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';

import '../support/png.dart';

Future<Uint8List> _rgba(QrPainter p, double size) async {
  final image = await p.toImage(size);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Pixels whose colour is neither pure black nor pure white.
int _greyPixels(Uint8List rgba) {
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final pure =
        (r == 0 && g == 0 && b == 0) || (r == 255 && g == 255 && b == 255);
    if (!pure) n++;
  }
  return n;
}

Future<ui.Image> _logoImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 16, 16),
      Paint()..color = const Color(0xFFE53935));
  return recorder.endRecording().toImage(16, 16);
}

final String? _zxing = which('ZXingReader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('construction', () {
    test('encodes data eagerly and exposes the matrix', () {
      final p = QrPainter(data: 'hello', errorCorrectionLevel: QrEcLevel.high);
      expect(p.matrix.ecLevel, QrEcLevel.high);
      expect(p.matrix.version, 1);
    });

    test('throws QrDataTooLongException for oversize data', () {
      expect(() => QrPainter(data: 'a' * 3000),
          throwsA(isA<QrDataTooLongException>()));
    });

    test('withMatrix uses the given matrix', () {
      final m = QrEncoder.encode('x', version: 3);
      expect(QrPainter.withMatrix(matrix: m).matrix, same(m));
    });

    test('shouldRepaint compares inputs', () {
      final m = QrEncoder.encode('x');
      final a = QrPainter.withMatrix(matrix: m);
      expect(a.shouldRepaint(QrPainter.withMatrix(matrix: m)), isFalse);
      expect(
          a.shouldRepaint(QrPainter.withMatrix(
              matrix: m, foregroundColor: const Color(0xFF123456))),
          isTrue);
      expect(
          a.shouldRepaint(QrPainter.withMatrix(
              matrix: m,
              dataModuleStyle:
                  const QrDataModuleStyle(shape: QrModuleShape.circle))),
          isTrue);
    });
  });

  group('layout', () {
    test('modules are whole device pixels and centred', () {
      final p = QrPainter(data: 'layout'); // 21 + 8 = 29 modules.
      final l = p.layout(const Size(300, 300));
      expect(l.moduleSize, 10); // floor(300 / 29).
      expect(l.symbolRect.width, 290);
      expect(l.symbolRect.left, 5);
      expect(l.symbolRect.top, 5);
    });

    test('snapping uses device pixels', () {
      final p = QrPainter(data: 'layout', devicePixelRatio: 3);
      final l = p.layout(const Size(100, 100));
      // 300 device pixels / 29 modules = 10 device pixels per module.
      expect(l.moduleSize * 3, 10);
      expect((l.symbolRect.left * 3) % 1, 0);
    });

    test('quiet zone is at least 4 modules', () {
      final p = QrPainter(data: 'q', quietZone: 6);
      final l = p.layout(const Size(330, 330)); // 21 + 12 = 33 modules.
      expect(l.moduleSize, 10);
      expect(l.qrRect.left - l.symbolRect.left, 60);
      expect(() => QrPainter(data: 'q', quietZone: 3), throwsArgumentError);
    });

    test('embedded image rect is centred and punches out modules', () {
      final p = QrPainter(
        data: 'https://example.com/embedded',
        errorCorrectionLevel: QrEcLevel.high,
        embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(60, 60)),
      );
      const size = Size(400, 400);
      final l = p.layout(size);
      final r = p.embeddedImageRect(size)!;
      expect(r.center.dx, closeTo(l.qrRect.center.dx, 0.01));
      expect(r.center.dy, closeTo(l.qrRect.center.dy, 0.01));
      expect(r.width, 60);
      expect(
          p.isPunchedOut(p.matrix.size ~/ 2, p.matrix.size ~/ 2, size), isTrue);
      expect(p.isPunchedOut(0, 0, size), isFalse);
    });
  });

  group('rendering', () {
    test('toImageData returns a PNG of the requested size', () async {
      final bytes =
          (await QrPainter(data: 'png').toImageData(200))!.buffer.asUint8List();
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
      final header = ByteData.sublistView(bytes, 16, 24);
      expect(header.getUint32(0), 200);
      expect(header.getUint32(4), 200);
    });

    test('square modules are crisp: only pure black and white pixels',
        () async {
      for (final size in [116.0, 203.0, 290.0, 317.0]) {
        final rgba = await _rgba(QrPainter(data: 'crisp $size'), size);
        expect(_greyPixels(rgba), 0, reason: 'size $size');
      }
    });

    test('gap modules are crisp too', () async {
      final rgba = await _rgba(
          QrPainter(
            data: 'gap',
            eyeStyle: const QrEyeStyle(shape: QrModuleShape.gap),
            dataModuleStyle: const QrDataModuleStyle(shape: QrModuleShape.gap),
          ),
          290);
      expect(_greyPixels(rgba), 0);
    });

    test('quiet zone and margins are background', () async {
      const size = 300.0; // module 10 px, 5 px margin, 40 px quiet zone.
      final rgba = await _rgba(QrPainter(data: 'quiet'), size);
      for (var y = 0; y < 45; y++) {
        for (var x = 0; x < size; x++) {
          final i = (y * size.toInt() + x) * 4;
          expect(rgba[i], 255, reason: '($x,$y)');
        }
      }
      // The first module of the top-left finder is dark.
      final i = (50 * size.toInt() + 50) * 4;
      expect(rgba[i], 0);
    });

    test('transparent background leaves light modules clear', () async {
      final rgba =
          await _rgba(QrPainter(data: 'alpha', backgroundColor: null), 290);
      expect(rgba[3], 0); // Top-left pixel alpha.
    });

    test('colours apply to eyes and data separately', () async {
      final rgba = await _rgba(
          QrPainter(
            data: 'colours',
            eyeStyle: const QrEyeStyle(color: Color(0xFFFF0000)),
            dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF0000FF)),
          ),
          290);
      // Centre of the top-left finder's 3x3 core: module (3,3) -> px 75.
      final eye = (75 * 290 + 75) * 4;
      expect(rgba.sublist(eye, eye + 3), [255, 0, 0]);
      var blue = 0;
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i] == 0 && rgba[i + 1] == 0 && rgba[i + 2] == 255) blue++;
      }
      expect(blue, greaterThan(0));
    });
  });

  group('decoded by ZXingReader after rendering', () {
    late Directory tmp;
    setUpAll(() => tmp = Directory.systemTemp.createTempSync('qr_gen_paint_'));
    tearDownAll(() => tmp.deleteSync(recursive: true));

    Future<String> decode(QrPainter p, {double size = 330}) async {
      final png = (await p.toImageData(size))!.buffer.asUint8List();
      final f = File('${tmp.path}/${DateTime.now().microsecondsSinceEpoch}.png')
        ..writeAsBytesSync(png);
      final r = Process.runSync(
          _zxing!, ['-json', '-formats', 'QRCode', f.path],
          stdoutEncoding: utf8);
      final line = (r.stdout as String).trim().split('\n').first;
      if (line.isEmpty) return '<no symbol found>';
      return (jsonDecode(line) as Map<String, Object?>)['Text']! as String;
    }

    test('every eye and module shape', () async {
      for (final eye in QrModuleShape.values) {
        for (final module in QrModuleShape.values) {
          final text = 'shape ${eye.name} ${module.name}';
          final p = QrPainter(
            data: text,
            eyeStyle: QrEyeStyle(shape: eye),
            dataModuleStyle: QrDataModuleStyle(shape: module),
          );
          expect(await decode(p), text, reason: '${eye.name}/${module.name}');
        }
      }
    });

    test('embedded image with punch-out at level H', () async {
      final logo = await _logoImage();
      const text = 'https://example.com/with-a-logo-in-the-middle';
      for (final punchOut in [true, false]) {
        final p = QrPainter(
          data: text,
          errorCorrectionLevel: QrEcLevel.high,
          embeddedImage: logo,
          embeddedImageStyle: QrEmbeddedImageStyle(
              size: const Size(70, 70), punchOut: punchOut),
        );
        expect(await decode(p, size: 400), text, reason: 'punchOut $punchOut');
      }
    });

    test('non-integer sizes and device pixel ratios', () async {
      for (final size in [157.0, 263.5, 401.0]) {
        final text = 'size $size';
        expect(await decode(QrPainter(data: text), size: size), text);
      }
    });
  }, skip: _zxing == null ? 'ZXingReader not installed' : false);
}
