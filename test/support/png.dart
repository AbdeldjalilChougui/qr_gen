import 'dart:io';
import 'dart:typed_data';

import 'package:qr_gen/qr_encoder.dart';

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc(body));
  return [
    ...len.buffer.asUint8List(),
    ...body,
    ...crc.buffer.asUint8List(),
  ];
}

/// Encodes a greyscale image (`pixels[y * width + x]`, 0 = black) as PNG.
Uint8List encodeGreyPng(int width, int height, List<int> pixels) {
  final raw = <int>[];
  for (var y = 0; y < height; y++) {
    raw.add(0); // Filter: none.
    raw.addAll(pixels.sublist(y * width, (y + 1) * width));
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // Bit depth.
    ..setUint8(9, 0) // Greyscale.
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ..._chunk('IHDR', ihdr.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibCodec().encode(raw)),
    ..._chunk('IEND', const []),
  ]);
}

/// Renders [m] with a 4-module quiet zone at [scale] pixels per module.
Uint8List matrixToPng(QrMatrix m, {int scale = 4, int quiet = 4}) {
  final side = (m.size + 2 * quiet) * scale;
  final px = List<int>.filled(side * side, 255);
  for (var r = 0; r < m.size; r++) {
    for (var c = 0; c < m.size; c++) {
      if (!m.isDark(r, c)) continue;
      for (var dy = 0; dy < scale; dy++) {
        final y = (r + quiet) * scale + dy;
        px.fillRange(y * side + (c + quiet) * scale,
            y * side + (c + quiet + 1) * scale, 0);
      }
    }
  }
  return encodeGreyPng(side, side, px);
}

/// Path of an executable on PATH, or null.
String? which(String tool) {
  try {
    final r = Process.runSync('which', [tool]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
  } on ProcessException {
    return null;
  }
}
