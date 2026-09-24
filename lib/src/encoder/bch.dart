/// BCH-protected format and version information (ISO/IEC 18004:2015, 7.9
/// and 7.10, Annexes C and D).
library;

import 'ec_level.dart';

/// The 15-bit format information for [level] and [mask], after the BCH(15,5)
/// code is appended and the result is XORed with 101010000010010.
int formatInformation(QrEcLevel level, int mask) {
  if (mask < 0 || mask > 7) throw RangeError.range(mask, 0, 7, 'mask');
  final data = (level.formatBits << 3) | mask;
  var rem = data;
  for (var i = 0; i < 10; i++) {
    rem = (rem << 1) ^ ((rem >> 9) * 0x537);
  }
  return ((data << 10) | (rem & 0x3FF)) ^ 0x5412;
}

/// The 18-bit version information for [version] (7 to 40): the version number
/// followed by its BCH(18,6) code.
int versionInformation(int version) {
  if (version < 7 || version > 40) {
    throw RangeError.range(version, 7, 40, 'version');
  }
  var rem = version;
  for (var i = 0; i < 12; i++) {
    rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
  }
  return (version << 12) | (rem & 0xFFF);
}
