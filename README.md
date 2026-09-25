# qr_gen

A maintained QR code generator for Flutter and Dart. The ISO/IEC 18004:2015
encoder is written from the standard in pure Dart, and a widget, a painter
with PNG export, and SVG output sit on top of it.

[![pub package](https://img.shields.io/pub/v/qr_gen.svg)](https://pub.dev/packages/qr_gen)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

**Encoder** (`package:qr_gen/qr_encoder.dart`, pure Dart, no Flutter import)

- All 40 versions. The smallest version that holds the data is picked
  automatically, or you can fix one, or bound the search with
  `minVersion`/`maxVersion`.
- Error correction levels L, M, Q and H (`QrEcLevel.low` … `QrEcLevel.high`).
- Numeric, alphanumeric, byte and Kanji modes.
- **Optimal segmentation.** A dynamic program over modes splits the text into
  segments with the fewest bits, taking into account the count-indicator
  widths for each version range.
- Byte mode uses ISO-8859-1 when the text allows it. Otherwise it uses
  UTF-8 and prepends an ECI designator (assignment 26). The designator can be
  turned off with `utf8Eci: false`.
- Kanji mode for Shift JIS characters (JIS X 0208). It can be turned off
  with `kanji: false`.
- Reed–Solomon error correction over GF(256), block interleaving, all eight
  mask patterns scored with the four penalty rules, and BCH format and
  version information.
- Output is a `QrMatrix`: the module grid as booleans (`isDark`, `toRows`),
  plus `version`, `ecLevel` and `mask`. `QrMatrix.toSvg()` produces an SVG
  string in pure Dart.

**Flutter**

- `QrImageView`: the widget. It takes `data`, `version` (null for automatic),
  `errorCorrectionLevel`, `size`, `padding`, a quiet zone of at least 4
  modules, colours, eye and data-module styles (`square`, `rounded`,
  `circle`, `gap`), and an `embeddedImage` with a size and an option to punch
  out the modules underneath it. It also takes `semanticsLabel` and
  `errorStateBuilder`.
- `QrPainter`: a `CustomPainter`, with `toImage(size)` and
  `toImageData(size, format: ImageByteFormat.png)` for export.
- **Crisp rendering.** Each module is a whole number of device pixels, and
  square modules are drawn without anti-aliasing, so no seams or grey edges
  appear between modules. The widget passes the screen's device pixel ratio
  to the painter.

## Install

```yaml
dependencies:
  qr_gen: ^0.1.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:qr_gen/qr_gen.dart';

class TicketCode extends StatelessWidget {
  const TicketCode({super.key});

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: 'https://example.com/tickets/42',
      size: 220,
      errorCorrectionLevel: QrEcLevel.high,
      eyeStyle: const QrEyeStyle(shape: QrModuleShape.rounded),
      dataModuleStyle: const QrDataModuleStyle(shape: QrModuleShape.circle),
      embeddedImage: const AssetImage('assets/logo.png'),
      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(44, 44)),
      semanticsLabel: 'Ticket 42',
      errorStateBuilder: (context, error) =>
          const Center(child: Text('Too much data for a QR code')),
    );
  }
}
```

Export a PNG:

```dart
Future<ByteData?> ticketPng() =>
    QrPainter(data: 'https://example.com/tickets/42').toImageData(512);
```

The encoder without Flutter, for a server or CLI:

```dart
import 'package:qr_gen/qr_encoder.dart';

void main() {
  final qr = QrEncoder.encode('HELLO WORLD', ecLevel: QrEcLevel.quartile);
  print('version ${qr.version}, mask ${qr.mask}, ${qr.size}x${qr.size}');
  print(qr.isDark(0, 0)); // true: top-left finder pattern
  final svg = qr.toSvg(moduleSize: 10);
  print(svg.length);
}
```

Other entry points are `QrEncoder.encodeBytes(bytes)`,
`QrEncoder.encodeSegments([...])` (with `QrSegment.numeric`, `.alphanumeric`,
`.bytes`, `.kanji` and `.eci`), and `QrEncoder.minimumVersion(text)`. When the
data does not fit, a `QrDataTooLongException` is thrown. It reports
`bitsNeeded` and `bitsAvailable`.

The `example/` directory is a runnable Flutter app. It encodes text as you
type, switches styles and levels, embeds a logo, copies the SVG and renders a
PNG.

## Migrating from qr_flutter

qr_flutter 4.1.0 is the latest release (May 2023). Most of its API maps one
to one:

| qr_flutter | qr_gen |
| --- | --- |
| `import 'package:qr_flutter/qr_flutter.dart'` | `import 'package:qr_gen/qr_gen.dart'` |
| `QrImageView(data: ...)` | `QrImageView(data: ...)` |
| `version: QrVersions.auto` | `version: null` (the default) |
| `version: 5` | `version: 5` |
| `errorCorrectionLevel: QrErrorCorrectLevel.L / M / Q / H` | `errorCorrectionLevel: QrEcLevel.low / medium / quartile / high` |
| `eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: c)` | `eyeStyle: QrEyeStyle(shape: QrModuleShape.circle, color: c)` |
| `dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: c)` | `dataModuleStyle: QrDataModuleStyle(shape: QrModuleShape.circle, color: c)` |
| `gapless: false` | `dataModuleStyle: QrDataModuleStyle(shape: QrModuleShape.gap)` |
| `foregroundColor` (deprecated there) | `foregroundColor` |
| `embeddedImageStyle: QrEmbeddedImageStyle(size: s)` | `embeddedImageStyle: QrEmbeddedImageStyle(size: s, punchOut: true)` |
| `errorStateBuilder: (context, error) => ...` | the same |
| `semanticsLabel: 'qr code'` | `semanticsLabel: 'QR code'` (the default) |
| `QrImageView.withQr(qr: qrCode)` | `QrImageView.withMatrix(matrix: QrEncoder.encode(...))` |
| `QrPainter(data: d, version: QrVersions.auto, color: c, emptyColor: e)` | `QrPainter(data: d, foregroundColor: c, backgroundColor: e)` |
| `painter.toImageData(512, format: ImageByteFormat.png)` | the same |
| `QrValidator.validate(...)` | `try { QrEncoder.encode(...) } on QrDataTooLongException` |

Behaviour differences to check when you migrate:

- **Default error correction level is M**, not L. Pass
  `errorCorrectionLevel: QrEcLevel.low` to keep the old density.
- **Default padding is zero**, not 10 logical pixels. The quiet zone (4
  modules, required by the standard) is always drawn inside `size`. Add
  `padding: EdgeInsets.all(10)` if your layout relied on the old padding.
- **Default background is white**, not transparent, because the quiet zone
  must be light for scanners. Pass `backgroundColor: null` for transparency.
- **Non-Latin-1 text is marked as UTF-8 with an ECI designator.** qr_flutter
  wrote UTF-8 bytes without saying so. If a legacy reader mishandles ECI,
  pass `utf8Eci: false` to `QrEncoder.encode` and use
  `QrImageView.withMatrix`.
- Modules under an embedded image are punched out by default. Set
  `punchOut: false` to draw them under the image. Either way, use level Q or H
  with a logo.
- `embeddedImageEmitsError`, `constrainErrorBounds` and the image tint
  `color` are not provided.

## Verification

- **Worked examples, byte for byte.** For ISO/IEC 18004:2015 Annex I
  ("01234567", 1-M), the tests check the data codewords, the EC codewords,
  the selected mask (010) and the full final symbol from Figure I.2. For the
  thonky.com "HELLO WORLD" tutorial, they check the 1-Q data codewords, the
  1-M and 1-Q EC codewords, and the final 1-Q symbol.
- **Standard tables.** For all 160 version/level pairs, data codewords and
  the numeric, alphanumeric, byte and Kanji capacities are checked against
  ISO Table 7, and the block structure against Table 9. Alignment positions
  are checked against Table E.1, version information against Table D.1, and
  format information against Table C.1.
- **Round trips.** A test-only decoder (`test/support/decoder.dart`) is
  written separately from `lib/`. It checks finder, timing, format and version
  BCH, and Reed–Solomon syndromes, then parses the segments. Every version and
  level, every mask, random mixed-mode text and binary data all decode back
  to the input.
- **Third-party tools** (local check, not part of CI):
  - `test/encoder/external_decoder_test.dart` writes PNGs and decodes them
    with `ZXingReader` (zxing-cpp) and `zbarimg` (ZBar).
  - The same test compares grids with `qrencode` (libqrencode 4.1.1). For
    single-mode inputs, the output matches module for module, including the
    chosen mask.
  - `test/widget/qr_painter_test.dart` decodes `QrPainter` output with
    ZXingReader for every eye/module shape pair and with an embedded image.
  - `test/encoder/svg_test.dart` rasterises the SVG with `rsvg-convert`.

  Each group is skipped, with a message, when its tool is not on `PATH`. On
  Arch/Manjaro, install `zbar`, `zxing-cpp`, `qrencode` and `librsvg`.

## Limitations

- Model 2 QR Code only. Micro QR, rMQR, Structured Append and FNC1 (GS1)
  modes are not implemented.
- The only ECI assignment written automatically is 26 (UTF-8). Others can be
  written with `QrSegment.eci(n)` in `encodeSegments`.
- Kanji mode covers the JIS X 0208 characters on which CPython's `shift_jis`
  and `cp932` codecs agree. Other characters fall back to byte mode.
- Mask selection: the standard's rule for the finder-like pattern (penalty
  rule 3) leaves room for interpretation. qr_gen counts each 1:1:3:1:1 run
  pattern once when a 4-module light area lies on either side, and treats
  space outside the symbol as light (the quiet zone). This reproduces the ISO
  Annex I choice (mask 010) and matches libqrencode. Other encoders may pick
  a different mask for the same data. Every mask is valid and decodes the
  same.
- The thonky.com tutorial's final HELLO WORLD image uses mask 6, but its own
  penalty walkthrough selects mask 0, which is what qr_gen selects. The test
  reproduces the image by forcing mask 6.
- Rounded and circle shapes are anti-aliased by design. Only the square and
  gap shapes are guaranteed free of grey pixels.

## Data sources

- **ISO/IEC 18004:2015**, *Information technology — Automatic identification
  and data capture techniques — QR Code bar code symbology specification*.
  The tests use factual values from it: Tables 7, 9, C.1, D.1 and E.1, and
  the Annex I example with its Figure I.2 symbol grid. They are in
  `test/fixtures/`. The encoder's own tables are checked against these.
  Two samples from Figure I.2 fell on annotation arrows and were corrected by
  inspection, as the fixture header explains.
- **thonky.com QR Code Tutorial** (CC BY-NC 4.0): the HELLO WORLD codewords
  and the final 1-Q symbol grid (`test/fixtures/thonky_hello_world_1q_final.txt`),
  used for testing only.
- **Kanji table** (`lib/src/encoder/kanji_table.dart`): generated by
  `tool/gen_kanji_table.py` from CPython's `shift_jis` codec (JIS X 0208
  mapping), cross-checked with `cp932`.

## License

MIT. See [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
