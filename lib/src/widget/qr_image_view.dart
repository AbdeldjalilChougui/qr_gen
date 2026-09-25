import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../encoder/ec_level.dart';
import '../encoder/encoder.dart';
import '../encoder/exceptions.dart';
import '../encoder/qr_matrix.dart';
import 'qr_painter.dart';
import 'styles.dart';

/// Builds a replacement widget when the data cannot be encoded. [error] is
/// usually a [QrDataTooLongException].
typedef QrErrorBuilder = Widget Function(BuildContext context, Object error);

/// A widget that shows a QR Code.
///
/// ```dart
/// QrImageView(
///   data: 'https://pub.dev/packages/qr_gen',
///   size: 200,
///   errorCorrectionLevel: QrEcLevel.quartile,
/// )
/// ```
class QrImageView extends StatefulWidget {
  /// Encodes [data] and shows it.
  const QrImageView({
    super.key,
    required String this.data,
    this.version,
    this.errorCorrectionLevel = QrEcLevel.medium,
    this.size,
    this.padding = EdgeInsets.zero,
    this.quietZone = 4,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.foregroundColor = const Color(0xFF000000),
    this.eyeStyle = const QrEyeStyle(),
    this.dataModuleStyle = const QrDataModuleStyle(),
    this.embeddedImage,
    this.embeddedImageStyle = const QrEmbeddedImageStyle(),
    this.semanticsLabel = 'QR code',
    this.errorStateBuilder,
  })  : matrix = null,
        assert(quietZone >= 4, 'The quiet zone must be at least 4 modules'),
        assert(version == null || (version >= 1 && version <= 40),
            'version must be 1 to 40, or null for automatic');

  /// Shows an already encoded [matrix].
  const QrImageView.withMatrix({
    super.key,
    required QrMatrix this.matrix,
    this.size,
    this.padding = EdgeInsets.zero,
    this.quietZone = 4,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.foregroundColor = const Color(0xFF000000),
    this.eyeStyle = const QrEyeStyle(),
    this.dataModuleStyle = const QrDataModuleStyle(),
    this.embeddedImage,
    this.embeddedImageStyle = const QrEmbeddedImageStyle(),
    this.semanticsLabel = 'QR code',
  })  : data = null,
        version = null,
        errorCorrectionLevel = QrEcLevel.medium,
        errorStateBuilder = null,
        assert(quietZone >= 4, 'The quiet zone must be at least 4 modules');

  /// Text to encode (null when built with [QrImageView.withMatrix]).
  final String? data;

  /// Precomputed symbol (null when built from [data]).
  final QrMatrix? matrix;

  /// Symbol version 1 to 40, or null to use the smallest that fits.
  final int? version;

  /// Error correction level.
  final QrEcLevel errorCorrectionLevel;

  /// Side of the square symbol area (excluding [padding]). Null fills the
  /// smaller of the available width and height.
  final double? size;

  /// Space around the symbol area, filled with [backgroundColor].
  final EdgeInsetsGeometry padding;

  /// Light modules around the symbol; the standard requires at least 4.
  final int quietZone;

  /// Background, or null for transparent.
  final Color? backgroundColor;

  /// Colour of dark modules unless [eyeStyle] or [dataModuleStyle] sets one.
  final Color foregroundColor;

  /// Style of the three finder patterns.
  final QrEyeStyle eyeStyle;

  /// Style of the other modules.
  final QrDataModuleStyle dataModuleStyle;

  /// Image shown in the centre, such as a logo.
  final ImageProvider? embeddedImage;

  /// Size and punch-out behaviour of [embeddedImage].
  final QrEmbeddedImageStyle embeddedImageStyle;

  /// Label announced by screen readers.
  final String semanticsLabel;

  /// Builds the widget shown when [data] cannot be encoded. Without it an
  /// empty box of the same size is shown.
  final QrErrorBuilder? errorStateBuilder;

  @override
  State<QrImageView> createState() => _QrImageViewState();
}

class _QrImageViewState extends State<QrImageView> {
  QrMatrix? _matrix;
  Object? _error;
  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _encode();
  }

  @override
  void didUpdateWidget(QrImageView old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data ||
        old.version != widget.version ||
        old.errorCorrectionLevel != widget.errorCorrectionLevel ||
        !identical(old.matrix, widget.matrix)) {
      _encode();
    }
    if (old.embeddedImage != widget.embeddedImage) _resolveImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  void _encode() {
    final given = widget.matrix;
    if (given != null) {
      _matrix = given;
      _error = null;
      return;
    }
    try {
      _matrix = QrEncoder.encode(widget.data!,
          version: widget.version, ecLevel: widget.errorCorrectionLevel);
      _error = null;
    } on QrEncodeException catch (e) {
      _matrix = null;
      _error = e;
    } on RangeError catch (e) {
      _matrix = null;
      _error = e;
    }
  }

  void _resolveImage() {
    final provider = widget.embeddedImage;
    if (provider == null) {
      _stopListening();
      _setImage(null);
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stopListening();
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      if (!mounted) {
        info.dispose();
        return;
      }
      setState(() => _setImage(info.image.clone()));
      info.dispose();
    });
    stream.addListener(_listener!);
  }

  void _setImage(ui.Image? image) {
    _image?.dispose();
    _image = image;
  }

  void _stopListening() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    _setImage(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;
    final layout = LayoutBuilder(builder: (context, constraints) {
      final side = widget.size ?? _fill(constraints, widget.padding);
      if (matrix == null) {
        final builder = widget.errorStateBuilder;
        return Padding(
          padding: widget.padding,
          child: builder != null
              ? builder(context, _error!)
              : SizedBox(width: side, height: side),
        );
      }
      final paint = Center(
        widthFactor: 1,
        heightFactor: 1,
        child: CustomPaint(
          size: Size.square(side),
          painter: QrPainter.withMatrix(
            matrix: matrix,
            quietZone: widget.quietZone,
            backgroundColor: widget.backgroundColor,
            foregroundColor: widget.foregroundColor,
            eyeStyle: widget.eyeStyle,
            dataModuleStyle: widget.dataModuleStyle,
            embeddedImage: _image,
            embeddedImageStyle: widget.embeddedImageStyle,
            devicePixelRatio:
                MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
          ),
        ),
      );
      final padded = Padding(padding: widget.padding, child: paint);
      final bg = widget.backgroundColor;
      return bg == null ? padded : ColoredBox(color: bg, child: padded);
    });
    if (matrix == null) return layout;
    return Semantics(
      container: true,
      image: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(child: layout),
    );
  }

  static double _fill(BoxConstraints c, EdgeInsetsGeometry padding) {
    final inset = padding.resolve(TextDirection.ltr);
    final w = c.maxWidth - inset.horizontal;
    final h = c.maxHeight - inset.vertical;
    final side = w.isFinite
        ? (h.isFinite ? math.min(w, h) : w)
        : (h.isFinite ? h : 200.0);
    return math.max(0, side);
  }
}
