// A small, test-only QR Code decoder for clean (undamaged, unrotated) module
// grids. It is written independently of lib/: it takes the block structure
// and alignment positions from the ISO tables in test/fixtures, and has its
// own GF(256), BCH and mask code. Only the Kanji character table is shared.

import 'dart:convert';

import 'package:qr_gen/src/encoder/kanji_table.dart';

import 'fixtures.dart';

/// Result of decoding a grid.
class Decoded {
  Decoded(this.text, this.version, this.ecBits, this.mask, this.bytes,
      this.dataBlocks, this.ecBlocks);

  /// Decoded text (byte segments as ISO-8859-1 unless an ECI 26 was seen).
  final String text;

  /// Version derived from the grid size.
  final int version;

  /// Two EC level bits from the format information (L=01, M=00, Q=11, H=10).
  final int ecBits;

  /// Mask pattern from the format information.
  final int mask;

  /// Raw bytes of byte-mode segments.
  final List<int> bytes;

  /// Data codewords of each block, de-interleaved.
  final List<List<int>> dataBlocks;

  /// Error correction codewords of each block, de-interleaved.
  final List<List<int>> ecBlocks;
}

final _blocks = <String, List<List<int>>>{};
final _align = <int, List<int>>{};

void _loadTables() {
  if (_blocks.isNotEmpty) return;
  for (final line in fixtureLines('iso_table9.txt')) {
    final f = line.split(' ');
    _blocks['${f[0]}${f[1]}'] = [
      for (final g in f.skip(2)) g.split(':').map(int.parse).toList(),
    ];
  }
  for (final line in fixtureLines('iso_tableE1.txt')) {
    final f = line.split(' ').map(int.parse).toList();
    _align[f[0]] = f.skip(2).toList();
  }
}

// GF(256) with 0x11D.
final List<int> _exp = List.filled(512, 0);
final List<int> _log = List.filled(256, 0);
bool _gfReady = false;
void _gf() {
  if (_gfReady) return;
  var x = 1;
  for (var i = 0; i < 255; i++) {
    _exp[i] = x;
    _log[x] = i;
    x <<= 1;
    if (x > 255) x ^= 0x11D;
  }
  for (var i = 255; i < 512; i++) {
    _exp[i] = _exp[i - 255];
  }
  _gfReady = true;
}

int _mul(int a, int b) => a == 0 || b == 0 ? 0 : _exp[_log[a] + _log[b]];

bool _mask(int m, int i, int j) => switch (m) {
      0 => (i + j) % 2 == 0,
      1 => i % 2 == 0,
      2 => j % 3 == 0,
      3 => (i + j) % 3 == 0,
      4 => (i ~/ 2 + j ~/ 3) % 2 == 0,
      5 => (i * j) % 2 + (i * j) % 3 == 0,
      6 => ((i * j) % 2 + (i * j) % 3) % 2 == 0,
      _ => ((i + j) % 2 + (i * j) % 3) % 2 == 0,
    };

int _bchRemainder(int value, int poly, int polyDegree) {
  var v = value;
  final top = 1 << polyDegree;
  for (var bit = 31; bit >= polyDegree; bit--) {
    if (v & (1 << bit) != 0) v ^= poly << (bit - polyDegree);
  }
  return v & (top - 1);
}

/// Decodes a clean grid (`grid[row][col]`, true = dark).
Decoded decodeGrid(List<List<bool>> grid) {
  _loadTables();
  _gf();
  final n = grid.length;
  if ((n - 17) % 4 != 0) throw StateError('Bad size $n');
  final version = (n - 17) ~/ 4;

  // Format information, both copies.
  int readBits(List<(int, int)> cells) {
    var v = 0;
    for (final (r, c) in cells) {
      v = (v << 1) | (grid[r][c] ? 1 : 0);
    }
    return v;
  }

  // Copy 1, bit 14 first.
  final copy1 = <(int, int)>[
    for (var c = 0; c <= 5; c++) (8, c),
    (8, 7),
    (8, 8),
    (7, 8),
    for (var r = 5; r >= 0; r--) (r, 8),
  ];
  final copy2 = <(int, int)>[
    for (var r = n - 1; r >= n - 7; r--) (r, 8),
    for (var c = n - 8; c < n; c++) (8, c),
  ];
  final f1 = readBits(copy1);
  final f2 = readBits(copy2);
  if (f1 != f2) throw StateError('Format copies differ');
  final fmt = f1 ^ 0x5412;
  if (_bchRemainder(fmt, 0x537, 10) != 0) throw StateError('Format BCH');
  final ecBits = fmt >> 13;
  final mask = (fmt >> 10) & 7;
  if (!grid[n - 8][8]) throw StateError('Dark module missing');

  if (version >= 7) {
    final a = <(int, int)>[];
    final b = <(int, int)>[];
    for (var i = 17; i >= 0; i--) {
      a.add((i ~/ 3, n - 11 + i % 3));
      b.add((n - 11 + i % 3, i ~/ 3));
    }
    final va = readBits(a), vb = readBits(b);
    if (va != vb) throw StateError('Version copies differ');
    if (va >> 12 != version) throw StateError('Version info ${va >> 12}');
    if (_bchRemainder(va, 0x1F25, 12) != 0) throw StateError('Version BCH');
  }

  // Function pattern map.
  final fn = List.generate(n, (_) => List.filled(n, false));
  void rect(int r0, int c0, int h, int w) {
    for (var r = r0; r < r0 + h; r++) {
      for (var c = c0; c < c0 + w; c++) {
        if (r >= 0 && r < n && c >= 0 && c < n) fn[r][c] = true;
      }
    }
  }

  rect(0, 0, 9, 9);
  rect(0, n - 8, 9, 8);
  rect(n - 8, 0, 8, 9);
  rect(6, 0, 1, n);
  rect(0, 6, n, 1);
  final centres = _align[version]!;
  for (final r in centres) {
    for (final c in centres) {
      final nearTop = r < 9, nearLeft = c < 9;
      final nearBottom = r > n - 9, nearRight = c > n - 9;
      if ((nearTop && nearLeft) ||
          (nearTop && nearRight) ||
          (nearBottom && nearLeft)) {
        continue; // Would overlap a finder pattern.
      }
      rect(r - 2, c - 2, 5, 5);
    }
  }
  if (version >= 7) {
    rect(0, n - 11, 6, 3);
    rect(n - 11, 0, 3, 6);
  }

  // Check the finder patterns and timing.
  for (final (r0, c0) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
    for (var dr = 0; dr < 7; dr++) {
      for (var dc = 0; dc < 7; dc++) {
        final d = [dr, dc, 6 - dr, 6 - dc].reduce((a, b) => a < b ? a : b);
        if (grid[r0 + dr][c0 + dc] != (d != 1)) {
          throw StateError('Finder at ($r0,$c0) broken');
        }
      }
    }
  }
  for (var i = 8; i < n - 8; i++) {
    if (grid[6][i] != i.isEven || grid[i][6] != i.isEven) {
      throw StateError('Timing broken at $i');
    }
  }

  // Read the zigzag.
  final bits = <int>[];
  for (var right = n - 1; right >= 1; right -= 2) {
    if (right == 6) right = 5;
    final up = ((n - 1 - right) ~/ 2).isEven;
    for (var v = 0; v < n; v++) {
      final r = up ? n - 1 - v : v;
      for (final c in [right, right - 1]) {
        if (fn[r][c]) continue;
        bits.add((grid[r][c] ^ _mask(mask, r, c)) ? 1 : 0);
      }
    }
  }
  final codewords = <int>[];
  for (var i = 0; i + 8 <= bits.length; i += 8) {
    var v = 0;
    for (var k = 0; k < 8; k++) {
      v = (v << 1) | bits[i + k];
    }
    codewords.add(v);
  }

  // De-interleave.
  final level = switch (ecBits) { 1 => 'L', 0 => 'M', 3 => 'Q', _ => 'H' };
  final groups = _blocks['$version$level']!;
  final dataLens = <int>[];
  final ecLen = groups.first[1] - groups.first[2];
  for (final g in groups) {
    for (var i = 0; i < g[0]; i++) {
      dataLens.add(g[2]);
    }
  }
  final blocks = [
    for (final l in dataLens) <int>[for (var i = 0; i < l; i++) 0]
  ];
  var p = 0;
  final maxLen = dataLens.reduce((a, b) => a > b ? a : b);
  for (var i = 0; i < maxLen; i++) {
    for (var b = 0; b < blocks.length; b++) {
      if (i < dataLens[b]) blocks[b][i] = codewords[p++];
    }
  }
  final ecBlocks = [for (final _ in dataLens) List.filled(ecLen, 0)];
  for (var i = 0; i < ecLen; i++) {
    for (var b = 0; b < blocks.length; b++) {
      ecBlocks[b][i] = codewords[p++];
    }
  }
  // Syndromes must all be zero for an undamaged block.
  final data = <int>[];
  for (var b = 0; b < blocks.length; b++) {
    final cw = [...blocks[b], ...ecBlocks[b]];
    for (var i = 0; i < ecLen; i++) {
      var s = 0;
      for (final c in cw) {
        s = _mul(s, _exp[i]) ^ c;
      }
      if (s != 0) throw StateError('Block $b syndrome $i = $s');
    }
    data.addAll(blocks[b]);
  }

  // Parse the bit stream.
  var pos = 0;
  final totalBits = data.length * 8;
  int take(int len) {
    var v = 0;
    for (var k = 0; k < len; k++) {
      final bit = (data[(pos + k) >> 3] >> (7 - ((pos + k) & 7))) & 1;
      v = (v << 1) | bit;
    }
    pos += len;
    return v;
  }

  int cc(List<int> w) => w[version <= 9 ? 0 : (version <= 26 ? 1 : 2)];
  const alnum = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
  final out = StringBuffer();
  final allBytes = <int>[];
  var utf8Mode = false;
  while (pos + 4 <= totalBits) {
    final mode = take(4);
    if (mode == 0) break;
    switch (mode) {
      case 0x7:
        var eci = take(8);
        if (eci & 0x80 != 0) {
          eci = eci & 0x40 == 0
              ? ((eci & 0x3F) << 8) | take(8)
              : ((eci & 0x1F) << 16) | take(16);
        }
        if (eci != 26) throw StateError('Unsupported ECI $eci');
        utf8Mode = true;
      case 0x1:
        var count = take(cc([10, 12, 14]));
        while (count >= 3) {
          out.write(take(10).toString().padLeft(3, '0'));
          count -= 3;
        }
        if (count == 2) out.write(take(7).toString().padLeft(2, '0'));
        if (count == 1) out.write(take(4).toString());
      case 0x2:
        var count = take(cc([9, 11, 13]));
        while (count >= 2) {
          final v = take(11);
          out
            ..write(alnum[v ~/ 45])
            ..write(alnum[v % 45]);
          count -= 2;
        }
        if (count == 1) out.write(alnum[take(6)]);
      case 0x4:
        final count = take(cc([8, 16, 16]));
        final bytes = [for (var i = 0; i < count; i++) take(8)];
        allBytes.addAll(bytes);
        out.write(utf8Mode ? utf8.decode(bytes) : latin1.decode(bytes));
      case 0x8:
        final count = take(cc([8, 10, 12]));
        for (var i = 0; i < count; i++) {
          final v = take(13);
          final ch = kanjiTable.codeUnitAt(v);
          if (ch == 0) throw StateError('Unmapped Kanji value $v');
          out.writeCharCode(ch);
        }
      default:
        throw StateError('Unknown mode $mode');
    }
  }
  return Decoded(
      out.toString(), version, ecBits, mask, allBytes, blocks, ecBlocks);
}
