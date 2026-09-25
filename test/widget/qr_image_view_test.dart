import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_gen.dart';

import '../support/png.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

QrPainter _painterOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(QrImageView),
    matching: find.byType(CustomPaint),
  ));
  return paint.painter! as QrPainter;
}

void main() {
  testWidgets('renders a QrPainter at the requested size', (tester) async {
    await tester.pumpWidget(_host(const QrImageView(data: 'hello', size: 200)));
    expect(tester.getSize(find.byType(QrImageView)), const Size(200, 200));
    final p = _painterOf(tester);
    expect(p.matrix.version, 1);
    expect(p.matrix.ecLevel, QrEcLevel.medium);
  });

  testWidgets('padding adds to the size', (tester) async {
    await tester.pumpWidget(_host(const QrImageView(
        data: 'hello', size: 200, padding: EdgeInsets.all(10))));
    expect(tester.getSize(find.byType(QrImageView)), const Size(220, 220));
  });

  testWidgets('fills the available space when size is null', (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
        width: 150, height: 300, child: QrImageView(data: 'fill'))));
    final paint = find.descendant(
        of: find.byType(QrImageView), matching: find.byType(CustomPaint));
    expect(tester.getSize(paint), const Size(150, 150));
  });

  testWidgets('passes version, level and styles to the painter',
      (tester) async {
    await tester.pumpWidget(_host(const QrImageView(
      data: 'styled',
      version: 5,
      errorCorrectionLevel: QrEcLevel.high,
      eyeStyle: QrEyeStyle(shape: QrModuleShape.circle),
      dataModuleStyle: QrDataModuleStyle(shape: QrModuleShape.rounded),
      foregroundColor: Color(0xFF004D40),
      size: 180,
    )));
    final p = _painterOf(tester);
    expect(p.matrix.version, 5);
    expect(p.matrix.ecLevel, QrEcLevel.high);
    expect(p.eyeStyle.shape, QrModuleShape.circle);
    expect(p.dataModuleStyle.shape, QrModuleShape.rounded);
    expect(p.foregroundColor, const Color(0xFF004D40));
  });

  testWidgets('quiet zone of at least 4 modules is laid out', (tester) async {
    await tester.pumpWidget(_host(const QrImageView(data: 'quiet', size: 290)));
    final p = _painterOf(tester);
    expect(p.quietZone, 4);
    final l = p.layout(const Size(290, 290));
    expect(l.qrRect.left - l.symbolRect.left, 4 * l.moduleSize);
    expect(() => QrImageView(data: 'x', quietZone: 2), throwsAssertionError);
  });

  testWidgets('uses the device pixel ratio for snapping', (tester) async {
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(const QrImageView(data: 'dpr', size: 120)));
    expect(_painterOf(tester).devicePixelRatio, 2.5);
  });

  testWidgets('embedded image is loaded and placed in the centre',
      (tester) async {
    final png = encodeGreyPng(4, 4, List.filled(16, 128));
    await tester.pumpWidget(_host(QrImageView(
      data: 'https://example.com/logo',
      errorCorrectionLevel: QrEcLevel.high,
      size: 300,
      embeddedImage: MemoryImage(png),
      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(50, 50)),
    )));
    // Image decoding happens outside the fake clock.
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && _painterOf(tester).embeddedImage == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    final p = _painterOf(tester);
    expect(p.embeddedImage, isA<ui.Image>());
    final rect = p.embeddedImageRect(const Size(300, 300))!;
    expect(rect.size, const Size(50, 50));
    expect(rect.center, const Offset(150, 150));
    expect(p.embeddedImageStyle.punchOut, isTrue);
  });

  testWidgets('errorStateBuilder runs when the data is too long',
      (tester) async {
    Object? seen;
    await tester.pumpWidget(_host(QrImageView(
      data: 'a' * 3000,
      size: 200,
      errorStateBuilder: (context, error) {
        seen = error;
        return const Text('Too long');
      },
    )));
    expect(find.text('Too long'), findsOneWidget);
    expect(seen, isA<QrDataTooLongException>());
    expect(
        find.byType(CustomPaint).evaluate().where((e) {
          return (e.widget as CustomPaint).painter is QrPainter;
        }),
        isEmpty);
  });

  testWidgets('errorStateBuilder runs when a fixed version is too small',
      (tester) async {
    await tester.pumpWidget(_host(QrImageView(
      data: 'this does not fit version one at level H',
      version: 1,
      errorCorrectionLevel: QrEcLevel.high,
      errorStateBuilder: (context, error) => const Text('error'),
    )));
    expect(find.text('error'), findsOneWidget);
  });

  testWidgets('without errorStateBuilder an error renders an empty box',
      (tester) async {
    await tester.pumpWidget(_host(QrImageView(data: 'a' * 3000, size: 120)));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(QrImageView)), const Size(120, 120));
  });

  testWidgets('re-encodes when data changes', (tester) async {
    await tester.pumpWidget(_host(const QrImageView(data: 'one', size: 100)));
    final first = _painterOf(tester).matrix;
    await tester.pumpWidget(_host(QrImageView(data: 'two' * 20, size: 100)));
    final second = _painterOf(tester).matrix;
    expect(second.version, greaterThan(first.version));
  });

  testWidgets('withMatrix renders a precomputed matrix', (tester) async {
    final m = QrEncoder.encode('pre', version: 4);
    await tester
        .pumpWidget(_host(QrImageView.withMatrix(matrix: m, size: 100)));
    expect(_painterOf(tester).matrix, same(m));
  });

  testWidgets('semantics: image with the default label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const QrImageView(data: 'sem', size: 100)));
    expect(
      tester.getSemantics(find.byType(QrImageView)),
      matchesSemantics(label: 'QR code', isImage: true),
    );
    handle.dispose();
  });

  testWidgets('semantics: custom label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const QrImageView(
        data: 'sem', size: 100, semanticsLabel: 'Link to the menu')));
    expect(find.bySemanticsLabel('Link to the menu'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(QrImageView)),
      matchesSemantics(label: 'Link to the menu', isImage: true),
    );
    handle.dispose();
  });
}
