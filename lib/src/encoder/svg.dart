/// Pure-Dart SVG output for a module grid.
library;

final RegExp _unsafe = RegExp('[<>&"]');

/// Builds an SVG document for a [size] x [size] grid where [isDark] reports
/// each module. Horizontal runs of dark modules become single rectangles of
/// one path, drawn with `shape-rendering="crispEdges"`.
String matrixToSvg(
  int size,
  bool Function(int row, int col) isDark, {
  required int quietZone,
  required int moduleSize,
  required String darkColor,
  required String? lightColor,
}) {
  if (quietZone < 0) throw RangeError.value(quietZone, 'quietZone');
  if (moduleSize < 1) throw RangeError.value(moduleSize, 'moduleSize');
  for (final c in [darkColor, if (lightColor != null) lightColor]) {
    if (_unsafe.hasMatch(c)) {
      throw ArgumentError.value(c, 'color', 'Contains markup characters');
    }
  }
  final total = size + 2 * quietZone;
  final px = total * moduleSize;
  final path = StringBuffer();
  for (var r = 0; r < size; r++) {
    var c = 0;
    while (c < size) {
      if (!isDark(r, c)) {
        c++;
        continue;
      }
      final start = c;
      while (c < size && isDark(r, c)) {
        c++;
      }
      final len = c - start;
      path.write('M${start + quietZone} ${r + quietZone}h${len}v1h-${len}z');
    }
  }
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
    ..write('<svg xmlns="http://www.w3.org/2000/svg" version="1.1" ')
    ..write('width="$px" height="$px" viewBox="0 0 $total $total" ')
    ..write('shape-rendering="crispEdges">\n');
  if (lightColor != null) {
    b.write('<rect width="$total" height="$total" fill="$lightColor"/>\n');
  }
  b.write('<path fill="$darkColor" d="$path"/>\n</svg>\n');
  return b.toString();
}
