/// Arithmetic in GF(2^8) with the QR Code field polynomial
/// x^8 + x^4 + x^3 + x^2 + 1 (0x11D), as in ISO/IEC 18004:2015, 7.5.2.
library;

import 'dart:typed_data';

final Uint8List _exp = _buildExp();
final Uint8List _log = _buildLog();

Uint8List _buildExp() {
  final t = Uint8List(512);
  var x = 1;
  for (var i = 0; i < 255; i++) {
    t[i] = x;
    x <<= 1;
    if (x & 0x100 != 0) x ^= 0x11D;
  }
  for (var i = 255; i < 512; i++) {
    t[i] = t[i - 255];
  }
  return t;
}

Uint8List _buildLog() {
  final t = Uint8List(256);
  for (var i = 0; i < 255; i++) {
    t[_exp[i]] = i;
  }
  return t;
}

/// Multiplies two field elements.
int gfMultiply(int a, int b) {
  if (a == 0 || b == 0) return 0;
  return _exp[_log[a] + _log[b]];
}

/// Returns alpha raised to [power] (alpha = 2).
int gfExp(int power) => _exp[power % 255];

/// Returns the discrete logarithm of the non-zero element [a].
int gfLog(int a) {
  if (a == 0) throw ArgumentError('log(0) is undefined');
  return _log[a];
}
