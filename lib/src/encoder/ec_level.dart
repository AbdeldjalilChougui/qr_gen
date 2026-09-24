/// Error correction level of a QR Code symbol (ISO/IEC 18004:2015, 5.3.8).
///
/// Higher levels restore more damaged data but hold less.
enum QrEcLevel {
  /// Level L: recovers about 7% of codewords.
  low(1),

  /// Level M: recovers about 15% of codewords.
  medium(0),

  /// Level Q: recovers about 25% of codewords.
  quartile(3),

  /// Level H: recovers about 30% of codewords.
  high(2);

  const QrEcLevel(this.formatBits);

  /// The two-bit indicator written into the format information (Table 12).
  final int formatBits;
}
