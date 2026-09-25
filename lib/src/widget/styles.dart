import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How modules (or the finder "eyes") are drawn.
enum QrModuleShape {
  /// Plain squares. Adjacent modules merge with no seams.
  square,

  /// Squares whose outer corners are rounded where they have no neighbour.
  rounded,

  /// A dot per module.
  circle,

  /// Squares with a small gap around each module.
  gap,
}

/// Style of the three finder patterns (the "eyes").
@immutable
class QrEyeStyle {
  /// Creates an eye style. A null [color] uses the foreground colour.
  const QrEyeStyle({this.shape = QrModuleShape.square, this.color});

  /// Shape of the eyes.
  final QrModuleShape shape;

  /// Colour of the eyes, or null for the foreground colour.
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is QrEyeStyle && other.shape == shape && other.color == color;

  @override
  int get hashCode => Object.hash(shape, color);
}

/// Style of the data modules (everything except the eyes).
@immutable
class QrDataModuleStyle {
  /// Creates a data module style. A null [color] uses the foreground colour.
  const QrDataModuleStyle({this.shape = QrModuleShape.square, this.color});

  /// Shape of each data module.
  final QrModuleShape shape;

  /// Colour of the data modules, or null for the foreground colour.
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is QrDataModuleStyle &&
      other.shape == shape &&
      other.color == color;

  @override
  int get hashCode => Object.hash(shape, color);
}

/// Placement of an image embedded in the centre of the symbol.
@immutable
class QrEmbeddedImageStyle {
  /// Creates an embedded image style.
  const QrEmbeddedImageStyle({this.size, this.punchOut = true});

  /// Size of the image in logical pixels. Null uses a fifth of the symbol
  /// width (without the quiet zone).
  final Size? size;

  /// Whether modules under the image are left out instead of drawn beneath
  /// it. Either way those modules are lost to the reader, so pick a higher
  /// error correction level (Q or H) when embedding an image.
  final bool punchOut;

  @override
  bool operator ==(Object other) =>
      other is QrEmbeddedImageStyle &&
      other.size == size &&
      other.punchOut == punchOut;

  @override
  int get hashCode => Object.hash(size, punchOut);
}
