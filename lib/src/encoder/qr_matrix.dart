import 'dart:typed_data';

import 'ec_level.dart';
import 'svg.dart';

/// A finished QR Code symbol: a square grid of dark and light modules plus
/// the parameters it was encoded with.
///
/// The grid excludes the quiet zone. Row 0, column 0 is the top-left module.
class QrMatrix {
  /// Wraps a row-major module grid ([modules] length must be a square whose
  /// side is `4 * version + 17`; non-zero means dark).
  QrMatrix.fromModules(
    Uint8List modules, {
    required this.version,
    required this.ecLevel,
    required this.mask,
  })  : size = version * 4 + 17,
        _modules = Uint8List.fromList(modules) {
    if (version < 1 || version > 40) {
      throw RangeError.range(version, 1, 40, 'version');
    }
    if (mask < 0 || mask > 7) throw RangeError.range(mask, 0, 7, 'mask');
    if (modules.length != size * size) {
      throw ArgumentError.value(
          modules.length, 'modules.length', 'Expected ${size * size}');
    }
  }

  final Uint8List _modules;

  /// Symbol version, 1 to 40.
  final int version;

  /// Error correction level.
  final QrEcLevel ecLevel;

  /// Data mask pattern, 0 to 7.
  final int mask;

  /// Modules per side (`4 * version + 17`).
  final int size;

  /// Whether the module at [row], [col] is dark.
  bool isDark(int row, int col) {
    RangeError.checkValueInInterval(row, 0, size - 1, 'row');
    RangeError.checkValueInInterval(col, 0, size - 1, 'col');
    return _modules[row * size + col] != 0;
  }

  /// The grid as rows of booleans (`true` = dark).
  List<List<bool>> toRows() => [
        for (var r = 0; r < size; r++)
          [for (var c = 0; c < size; c++) _modules[r * size + c] != 0],
      ];

  /// Whether [row], [col] lies inside one of the three 7x7 finder patterns
  /// (the "eyes").
  bool isFinderModule(int row, int col) =>
      (row < 7 && col < 7) ||
      (row < 7 && col >= size - 7) ||
      (row >= size - 7 && col < 7);

  /// Renders the symbol as a standalone SVG document.
  ///
  /// The drawing is in module units; [moduleSize] sets the `width` and
  /// `height` attributes in pixels. [quietZone] light modules surround the
  /// symbol (the standard asks for at least 4). [darkColor] and [lightColor]
  /// are CSS colours; pass `null` as [lightColor] for a transparent
  /// background.
  String toSvg({
    int quietZone = 4,
    int moduleSize = 8,
    String darkColor = '#000000',
    String? lightColor = '#ffffff',
  }) =>
      matrixToSvg(
        size,
        (r, c) => _modules[r * size + c] != 0,
        quietZone: quietZone,
        moduleSize: moduleSize,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// A text drawing of the grid using `██` for dark and two spaces for light.
  @override
  String toString() {
    final b = StringBuffer();
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        b.write(_modules[r * size + c] != 0 ? '██' : '  ');
      }
      b.writeln();
    }
    return b.toString();
  }
}
