/// Data codeword construction and block interleaving (ISO/IEC 18004:2015,
/// 7.4.9, 7.4.10 and 7.6).
library;

import 'ec_level.dart';
import 'exceptions.dart';
import 'reed_solomon.dart';
import 'segment.dart';
import 'tables.dart';

/// Builds the data codewords for [segments]: mode and count indicators, data,
/// terminator, bit padding and alternating 0xEC/0x11 pad codewords.
///
/// Throws [QrDataTooLongException] when the segments do not fit.
List<int> buildDataCodewords(
    List<QrSegment> segments, int version, QrEcLevel level) {
  final capacityBits = dataCodewords(version, level) * 8;
  final needed = QrSegment.totalBits(segments, version);
  if (needed == null || needed > capacityBits) {
    throw QrDataTooLongException(
      'Data needs ${needed ?? 'more than the count indicator allows'} bits; '
      'version $version-${level.name} holds $capacityBits',
      bitsNeeded: needed,
      bitsAvailable: capacityBits,
    );
  }
  final bits = <bool>[];
  void append(int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add((value >> i) & 1 == 1);
    }
  }

  for (final s in segments) {
    append(s.mode.indicator, 4);
    append(s.numChars, s.mode.charCountBits(version));
    bits.addAll(s.bits);
  }
  final terminator = capacityBits - bits.length;
  append(0, terminator < 4 ? terminator : 4);
  append(0, (8 - bits.length % 8) % 8);

  final out = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var v = 0;
    for (var k = 0; k < 8; k++) {
      v = (v << 1) | (bits[i + k] ? 1 : 0);
    }
    out.add(v);
  }
  for (var pad = 0xEC; out.length < capacityBits ~/ 8; pad ^= 0xEC ^ 0x11) {
    out.add(pad);
  }
  return out;
}

/// Splits [data] into blocks, appends each block's Reed–Solomon codewords and
/// interleaves them: data codewords column by column, then EC codewords.
List<int> interleaveWithEc(List<int> data, int version, QrEcLevel level) {
  final layout = blockLayout(version, level);
  final ecLen = ecCodewordsPerBlock(version, level);
  if (data.length != dataCodewords(version, level)) {
    throw ArgumentError.value(data.length, 'data.length',
        'Expected ${dataCodewords(version, level)} codewords');
  }
  final dataBlocks = <List<int>>[];
  final ecBlocks = <List<int>>[];
  var offset = 0;
  for (final len in layout) {
    final block = data.sublist(offset, offset + len);
    offset += len;
    dataBlocks.add(block);
    ecBlocks.add(reedSolomonRemainder(block, ecLen));
  }
  final maxData = layout.last;
  final out = <int>[];
  for (var i = 0; i < maxData; i++) {
    for (final b in dataBlocks) {
      if (i < b.length) out.add(b[i]);
    }
  }
  for (var i = 0; i < ecLen; i++) {
    for (final b in ecBlocks) {
      out.add(b[i]);
    }
  }
  return out;
}
