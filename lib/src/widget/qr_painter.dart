import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../encoder/ec_level.dart';
import '../encoder/encoder.dart';
import '../encoder/qr_matrix.dart';
import 'styles.dart';

/// Where a [QrPainter] puts the symbol inside a given size.
@immutable
class QrLayout {
  /// Creates a layout.
  const QrLayout({
    required this.moduleSize,
    required this.symbolRect,
    required this.qrRect,
  });

  /// Side of one module in logical pixels. When snapping is possible this is
  /// a whole number of device pixels.
  final double moduleSize;

  /// The symbol including its quiet zone.
  final Rect symbolRect;

  /// The module grid only.
  final Rect qrRect;
}

/// Paints a QR Code symbol. Also renders it off screen with [toImage] and
/// [toImageData].
///
/// Module edges are snapped to whole device pixels (see [devicePixelRatio]),
/// so square modules render without anti-aliasing seams between them.
class QrPainter extends CustomPainter {
  /// Encodes [data] immediately. Throws [QrDataTooLongException] when it does
  /// not fit, and [ArgumentError] when [quietZone] is below 4.
  QrPainter({
    required String data,
    int? version,
    QrEcLevel errorCorrectionLevel = QrEcLevel.medium,
    int quietZone = 4,
    Color? backgroundColor = const Color(0xFFFFFFFF),
    Color foregroundColor = const Color(0xFF000000),
    QrEyeStyle eyeStyle = const QrEyeStyle(),
    QrDataModuleStyle dataModuleStyle = const QrDataModuleStyle(),
    ui.Image? embeddedImage,
    QrEmbeddedImageStyle embeddedImageStyle = const QrEmbeddedImageStyle(),
    double devicePixelRatio = 1.0,
  }) : this.withMatrix(
          matrix: QrEncoder.encode(data,
              version: version, ecLevel: errorCorrectionLevel),
          quietZone: quietZone,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          eyeStyle: eyeStyle,
          dataModuleStyle: dataModuleStyle,
          embeddedImage: embeddedImage,
          embeddedImageStyle: embeddedImageStyle,
          devicePixelRatio: devicePixelRatio,
        );

  /// Paints an already encoded [matrix].
  QrPainter.withMatrix({
    required this.matrix,
    this.quietZone = 4,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.foregroundColor = const Color(0xFF000000),
    this.eyeStyle = const QrEyeStyle(),
    this.dataModuleStyle = const QrDataModuleStyle(),
    this.embeddedImage,
    this.embeddedImageStyle = const QrEmbeddedImageStyle(),
    this.devicePixelRatio = 1.0,
  }) {
    if (quietZone < 4) {
      throw ArgumentError.value(
          quietZone, 'quietZone', 'Must be at least 4 modules');
    }
    if (devicePixelRatio <= 0) {
      throw ArgumentError.value(devicePixelRatio, 'devicePixelRatio');
    }
  }

  /// The symbol being painted.
  final QrMatrix matrix;

  /// Light modules around the symbol; at least 4.
  final int quietZone;

  /// Fill for the whole canvas, or null for transparent.
  final Color? backgroundColor;

  /// Colour of dark modules unless a style overrides it.
  final Color foregroundColor;

  /// Style of the three finder patterns.
  final QrEyeStyle eyeStyle;

  /// Style of the other modules.
  final QrDataModuleStyle dataModuleStyle;

  /// Image drawn in the centre, if any.
  final ui.Image? embeddedImage;

  /// Size and punch-out behaviour of [embeddedImage].
  final QrEmbeddedImageStyle embeddedImageStyle;

  /// Device pixels per logical pixel, used to snap modules to whole device
  /// pixels. [toImage] always renders at 1.
  final double devicePixelRatio;

  /// Computes where the symbol goes in [size]: centred, square, with each
  /// module a whole number of device pixels wide whenever at least one
  /// device pixel per module is available.
  QrLayout layout(Size size) {
    final dpr = devicePixelRatio;
    final total = matrix.size + 2 * quietZone;
    final side = math.min(size.width, size.height) * dpr;
    var modulePx = (side / total).floorToDouble();
    if (modulePx < 1) modulePx = side / total;
    final symbolPx = modulePx * total;
    final left = ((size.width * dpr - symbolPx) / 2).floorToDouble();
    final top = ((size.height * dpr - symbolPx) / 2).floorToDouble();
    final m = modulePx / dpr;
    final symbol =
        Rect.fromLTWH(left / dpr, top / dpr, symbolPx / dpr, symbolPx / dpr);
    return QrLayout(
      moduleSize: m,
      symbolRect: symbol,
      qrRect: Rect.fromLTWH(symbol.left + quietZone * m,
          symbol.top + quietZone * m, matrix.size * m, matrix.size * m),
    );
  }

  /// Where [embeddedImage] is drawn in [size], or null without an image
  /// size to use. The rectangle is reported even before the image loads, so
  /// the punched-out area does not jump.
  Rect? embeddedImageRect(Size size) {
    final l = layout(size);
    final s = embeddedImageStyle.size ??
        Size(l.qrRect.width / 5, l.qrRect.height / 5);
    if (s.isEmpty) return null;
    return Rect.fromCenter(
        center: l.qrRect.center, width: s.width, height: s.height);
  }

  bool _hasImage() => embeddedImage != null || embeddedImageStyle.size != null;

  /// Whether the module at [row], [col] is left out under the embedded
  /// image when painting at [size]. Finder patterns are never punched out.
  bool isPunchedOut(int row, int col, Size size) {
    if (!_hasImage() || !embeddedImageStyle.punchOut) return false;
    return _punchTest(layout(size), embeddedImageRect(size))(row, col);
  }

  bool Function(int, int) _punchTest(QrLayout l, Rect? image) {
    if (!_hasImage() || !embeddedImageStyle.punchOut || image == null) {
      return (_, __) => false;
    }
    final m = l.moduleSize;
    const eps = 1e-6;
    return (r, c) {
      if (matrix.isFinderModule(r, c)) return false;
      final x = l.qrRect.left + c * m, y = l.qrRect.top + r * m;
      return x + m > image.left + eps &&
          x < image.right - eps &&
          y + m > image.top + eps &&
          y < image.bottom - eps;
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor!);
    }
    final l = layout(size);
    final imageRect = _hasImage() ? embeddedImageRect(size) : null;
    final punched = _punchTest(l, imageRect);

    _paintData(canvas, l, punched);
    _paintEyes(canvas, l);

    final image = embeddedImage;
    if (image != null && imageRect != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  (double, double) _gapInsets(QrLayout l) {
    final px = l.moduleSize * devicePixelRatio;
    final gapPx = px >= 4 ? math.max(1, (px * 0.12).round()) : 0;
    final a = (gapPx ~/ 2) / devicePixelRatio;
    final b = (gapPx - gapPx ~/ 2) / devicePixelRatio;
    return (a, b);
  }

  void _paintData(Canvas canvas, QrLayout l, bool Function(int, int) punched) {
    final n = matrix.size;
    final m = l.moduleSize;
    final o = l.qrRect.topLeft;
    bool dark(int r, int c) =>
        r >= 0 &&
        c >= 0 &&
        r < n &&
        c < n &&
        !matrix.isFinderModule(r, c) &&
        matrix.isDark(r, c) &&
        !punched(r, c);

    final path = Path();
    final shape = dataModuleStyle.shape;
    final (ga, gb) = _gapInsets(l);
    for (var r = 0; r < n; r++) {
      final y = o.dy + r * m;
      var c = 0;
      while (c < n) {
        if (!dark(r, c)) {
          c++;
          continue;
        }
        final x = o.dx + c * m;
        switch (shape) {
          case QrModuleShape.square:
            final start = c;
            while (c < n && dark(r, c)) {
              c++;
            }
            path.addRect(
                Rect.fromLTWH(o.dx + start * m, y, (c - start) * m, m));
            continue;
          case QrModuleShape.gap:
            path.addRect(Rect.fromLTRB(x + ga, y + ga, x + m - gb, y + m - gb));
          case QrModuleShape.circle:
            path.addOval(Rect.fromCircle(
                center: Offset(x + m / 2, y + m / 2), radius: m * 0.45));
          case QrModuleShape.rounded:
            final up = dark(r - 1, c), down = dark(r + 1, c);
            final left = dark(r, c - 1), right = dark(r, c + 1);
            final rad = Radius.circular(m / 2);
            path.addRRect(RRect.fromRectAndCorners(
              Rect.fromLTWH(x, y, m, m),
              topLeft: up || left ? Radius.zero : rad,
              topRight: up || right ? Radius.zero : rad,
              bottomLeft: down || left ? Radius.zero : rad,
              bottomRight: down || right ? Radius.zero : rad,
            ));
        }
        c++;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = dataModuleStyle.color ?? foregroundColor
        ..isAntiAlias =
            shape == QrModuleShape.circle || shape == QrModuleShape.rounded,
    );
  }

  void _paintEyes(Canvas canvas, QrLayout l) {
    final n = matrix.size;
    final m = l.moduleSize;
    final o = l.qrRect.topLeft;
    final shape = eyeStyle.shape;
    final path = Path()..fillType = PathFillType.evenOdd;
    final (ga, gb) = _gapInsets(l);
    for (final (r0, c0) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
      final outer = Rect.fromLTWH(o.dx + c0 * m, o.dy + r0 * m, 7 * m, 7 * m);
      switch (shape) {
        case QrModuleShape.square:
          path
            ..addRect(outer)
            ..addRect(outer.deflate(m))
            ..addRect(outer.deflate(2 * m));
        case QrModuleShape.rounded:
          path
            ..addRRect(RRect.fromRectAndRadius(outer, Radius.circular(2 * m)))
            ..addRRect(RRect.fromRectAndRadius(
                outer.deflate(m), Radius.circular(1.4 * m)))
            ..addRRect(RRect.fromRectAndRadius(
                outer.deflate(2 * m), Radius.circular(0.9 * m)));
        case QrModuleShape.circle:
          path
            ..addOval(outer)
            ..addOval(outer.deflate(m))
            ..addOval(outer.deflate(2 * m));
        case QrModuleShape.gap:
          // The ring and the core are drawn whole, each inset by the gap.
          // Splitting the eye into separate modules would break the
          // 1:1:3:1:1 runs that readers use to find the symbol.
          path
            ..addRect(Rect.fromLTRB(outer.left + ga, outer.top + ga,
                outer.right - gb, outer.bottom - gb))
            ..addRect(Rect.fromLTRB(outer.left + m - gb, outer.top + m - gb,
                outer.right - m + ga, outer.bottom - m + ga))
            ..addRect(Rect.fromLTRB(
                outer.left + 2 * m + ga,
                outer.top + 2 * m + ga,
                outer.right - 2 * m - gb,
                outer.bottom - 2 * m - gb));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = eyeStyle.color ?? foregroundColor
        ..isAntiAlias =
            shape == QrModuleShape.circle || shape == QrModuleShape.rounded,
    );
  }

  QrPainter _atUnitRatio() => devicePixelRatio == 1.0
      ? this
      : QrPainter.withMatrix(
          matrix: matrix,
          quietZone: quietZone,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          eyeStyle: eyeStyle,
          dataModuleStyle: dataModuleStyle,
          embeddedImage: embeddedImage,
          embeddedImageStyle: embeddedImageStyle,
        );

  /// Renders the symbol into a square image [size] pixels wide (rounded to
  /// a whole number, at least 1).
  Future<ui.Image> toImage(double size) async {
    final px = math.max(1, size.round());
    final recorder = ui.PictureRecorder();
    _atUnitRatio().paint(Canvas(recorder), Size(px.toDouble(), px.toDouble()));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(px, px);
    } finally {
      picture.dispose();
    }
  }

  /// Renders the symbol like [toImage] and encodes it, as PNG by default.
  Future<ByteData?> toImageData(double size,
      {ui.ImageByteFormat format = ui.ImageByteFormat.png}) async {
    final image = await toImage(size);
    try {
      return await image.toByteData(format: format);
    } finally {
      image.dispose();
    }
  }

  @override
  bool shouldRepaint(QrPainter oldDelegate) =>
      !identical(oldDelegate.matrix, matrix) ||
      oldDelegate.quietZone != quietZone ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.foregroundColor != foregroundColor ||
      oldDelegate.eyeStyle != eyeStyle ||
      oldDelegate.dataModuleStyle != dataModuleStyle ||
      !identical(oldDelegate.embeddedImage, embeddedImage) ||
      oldDelegate.embeddedImageStyle != embeddedImageStyle ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
