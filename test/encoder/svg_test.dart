import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_gen/qr_encoder.dart';

import '../support/png.dart';

/// Rebuilds the module grid from the path data of [svg].
List<List<bool>> _gridFromSvg(String svg, int size, int quiet) {
  final grid = List.generate(size, (_) => List.filled(size, false));
  final d = RegExp(r' d="([^"]*)"').firstMatch(svg)!.group(1)!;
  for (final m in RegExp(r'M(\d+) (\d+)h(\d+)v1h-(\d+)z').allMatches(d)) {
    final x = int.parse(m.group(1)!) - quiet;
    final y = int.parse(m.group(2)!) - quiet;
    final len = int.parse(m.group(3)!);
    expect(m.group(4), m.group(3));
    for (var i = 0; i < len; i++) {
      expect(grid[y][x + i], isFalse, reason: 'overlap');
      grid[y][x + i] = true;
    }
  }
  return grid;
}

final String? _rsvg = which('rsvg-convert');
final String? _zxing = which('ZXingReader');

void main() {
  test('is a standalone SVG document with crisp edges', () {
    final svg = QrEncoder.encode('svg').toSvg();
    expect(svg, startsWith('<?xml'));
    expect(svg, contains('xmlns="http://www.w3.org/2000/svg"'));
    expect(svg, contains('shape-rendering="crispEdges"'));
    // 21 modules + 2 x 4 quiet zone = 29; 8 px per module.
    expect(svg, contains('viewBox="0 0 29 29"'));
    expect(svg, contains('width="232" height="232"'));
    expect(svg.trim(), endsWith('</svg>'));
  });

  test('path reproduces the module grid exactly', () {
    for (final text in ['01234567', 'HELLO WORLD', 'x' * 300]) {
      final m = QrEncoder.encode(text);
      expect(_gridFromSvg(m.toSvg(), m.size, 4), m.toRows());
      expect(_gridFromSvg(m.toSvg(quietZone: 6), m.size, 6), m.toRows());
    }
  });

  test('options: colours, module size, transparent background', () {
    final m = QrEncoder.encode('opts');
    final svg = m.toSvg(
        darkColor: '#123456', lightColor: null, moduleSize: 3, quietZone: 5);
    expect(svg, contains('fill="#123456"'));
    expect(svg, isNot(contains('<rect')));
    expect(svg, contains('viewBox="0 0 31 31"'));
    expect(svg, contains('width="93"'));
    expect(m.toSvg(lightColor: '#fafafa'), contains('fill="#fafafa"'));
  });

  test('rejects bad arguments and markup in colours', () {
    final m = QrEncoder.encode('bad');
    expect(() => m.toSvg(moduleSize: 0), throwsRangeError);
    expect(() => m.toSvg(quietZone: -1), throwsRangeError);
    expect(() => m.toSvg(darkColor: '"/><script>'), throwsArgumentError);
  });

  test('rasterised with rsvg-convert, decoded by ZXingReader', () {
    final tmp = Directory.systemTemp.createTempSync('qr_gen_svg_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final text in ['https://pub.dev/packages/qr_gen', 'Grüße', '点茗']) {
      final svg = File('${tmp.path}/a.svg')
        ..writeAsStringSync(QrEncoder.encode(text).toSvg(moduleSize: 6));
      final png = '${tmp.path}/a.png';
      expect(Process.runSync(_rsvg!, ['-o', png, svg.path]).exitCode, 0);
      final r = Process.runSync(_zxing!, ['-json', '-formats', 'QRCode', png],
          stdoutEncoding: utf8);
      final j = jsonDecode((r.stdout as String).trim().split('\n').first)
          as Map<String, Object?>;
      expect(j['Text'], text);
    }
  },
      skip: _rsvg == null || _zxing == null
          ? 'rsvg-convert or ZXingReader not installed'
          : false);
}
