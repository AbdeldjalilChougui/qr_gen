/// Reed–Solomon error correction codewords (ISO/IEC 18004:2015, 7.5.2).
library;

import 'gf256.dart';

final Map<int, List<int>> _generators = {};

/// Coefficients of the generator polynomial of [degree], highest power first,
/// with the leading 1 omitted: the product of (x - alpha^i) for i < degree.
List<int> reedSolomonGenerator(int degree) {
  if (degree < 1 || degree > 255) {
    throw RangeError.range(degree, 1, 255, 'degree');
  }
  return _generators.putIfAbsent(degree, () {
    final result = List<int>.filled(degree, 0);
    result[degree - 1] = 1; // Start with the monomial x^0.
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < degree; j++) {
        result[j] = gfMultiply(result[j], root);
        if (j + 1 < degree) result[j] ^= result[j + 1];
      }
      root = gfMultiply(root, 2);
    }
    return List.unmodifiable(result);
  });
}

/// The [degree] error correction codewords for [data]: the remainder of
/// data(x) * x^degree divided by the generator polynomial.
List<int> reedSolomonRemainder(List<int> data, int degree) {
  final gen = reedSolomonGenerator(degree);
  final rem = List<int>.filled(degree, 0);
  for (final b in data) {
    final factor = b ^ rem[0];
    for (var i = 0; i < degree - 1; i++) {
      rem[i] = rem[i + 1] ^ gfMultiply(gen[i], factor);
    }
    rem[degree - 1] = gfMultiply(gen[degree - 1], factor);
  }
  return rem;
}
