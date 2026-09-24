import 'codewords.dart';
import 'ec_level.dart';
import 'exceptions.dart';
import 'matrix_builder.dart';
import 'mode.dart';
import 'qr_matrix.dart';
import 'segment.dart';
import 'segmenter.dart';
import 'tables.dart' as tables;

/// Encodes data into QR Code symbols following ISO/IEC 18004:2015.
///
/// Pure Dart: usable from servers, CLIs and isolates.
abstract final class QrEncoder {
  /// Encodes [data] as text.
  ///
  /// The text is split into numeric, alphanumeric, byte and (when [kanji] is
  /// true) Kanji segments so that the bit stream is as short as possible.
  /// Byte segments use ISO-8859-1 when the text allows it, otherwise UTF-8
  /// with an ECI designator (see [utf8Eci]).
  ///
  /// With [version] null, the smallest version between [minVersion] and
  /// [maxVersion] that holds the data is used. With [mask] null, the mask
  /// with the lowest penalty score is chosen.
  ///
  /// Throws [QrDataTooLongException] if the data does not fit, and
  /// [RangeError] for invalid [version], [mask] or version bounds.
  static QrMatrix encode(
    String data, {
    QrEcLevel ecLevel = QrEcLevel.medium,
    int? version,
    int? mask,
    int minVersion = tables.minVersion,
    int maxVersion = tables.maxVersion,
    bool kanji = true,
    bool utf8Eci = true,
  }) {
    _checkRange(version, minVersion, maxVersion, mask);
    List<QrSegment> segmentsFor(int v) =>
        segmentText(data, version: v, kanji: kanji, utf8Eci: utf8Eci);
    if (version != null) {
      return _build(segmentsFor(version), version, ecLevel, mask);
    }
    List<QrSegment>? segs;
    int? needed;
    for (var v = minVersion; v <= maxVersion; v++) {
      if (segs == null || v == 10 || v == 27) segs = segmentsFor(v);
      needed = QrSegment.totalBits(segs, v);
      if (needed != null && needed <= tables.dataCodewords(v, ecLevel) * 8) {
        return _build(segs, v, ecLevel, mask);
      }
    }
    throw _tooLong(needed, maxVersion, ecLevel);
  }

  /// Encodes raw [bytes] as a single byte-mode segment, without an ECI
  /// designator.
  static QrMatrix encodeBytes(
    List<int> bytes, {
    QrEcLevel ecLevel = QrEcLevel.medium,
    int? version,
    int? mask,
    int minVersion = tables.minVersion,
    int maxVersion = tables.maxVersion,
  }) =>
      encodeSegments(
        [QrSegment.bytes(bytes)],
        ecLevel: ecLevel,
        version: version,
        mask: mask,
        minVersion: minVersion,
        maxVersion: maxVersion,
      );

  /// Encodes caller-built [segments] as given.
  static QrMatrix encodeSegments(
    List<QrSegment> segments, {
    QrEcLevel ecLevel = QrEcLevel.medium,
    int? version,
    int? mask,
    int minVersion = tables.minVersion,
    int maxVersion = tables.maxVersion,
  }) {
    _checkRange(version, minVersion, maxVersion, mask);
    if (version != null) return _build(segments, version, ecLevel, mask);
    int? needed;
    for (var v = minVersion; v <= maxVersion; v++) {
      needed = QrSegment.totalBits(segments, v);
      if (needed != null && needed <= tables.dataCodewords(v, ecLevel) * 8) {
        return _build(segments, v, ecLevel, mask);
      }
    }
    throw _tooLong(needed, maxVersion, ecLevel);
  }

  /// The smallest version that holds [data] at [ecLevel], or null if none.
  static int? minimumVersion(String data,
      {QrEcLevel ecLevel = QrEcLevel.medium,
      bool kanji = true,
      bool utf8Eci = true}) {
    List<QrSegment>? segs;
    for (var v = 1; v <= 40; v++) {
      if (segs == null || v == 10 || v == 27) {
        segs = segmentText(data, version: v, kanji: kanji, utf8Eci: utf8Eci);
      }
      final needed = QrSegment.totalBits(segs, v);
      if (needed != null && needed <= tables.dataCodewords(v, ecLevel) * 8) {
        return v;
      }
    }
    return null;
  }

  static void _checkRange(int? version, int minV, int maxV, int? mask) {
    if (version != null) {
      RangeError.checkValueInInterval(version, 1, 40, 'version');
    }
    RangeError.checkValueInInterval(minV, 1, 40, 'minVersion');
    RangeError.checkValueInInterval(maxV, minV, 40, 'maxVersion');
    if (mask != null) RangeError.checkValueInInterval(mask, 0, 7, 'mask');
  }

  static QrDataTooLongException _tooLong(
          int? needed, int version, QrEcLevel level) =>
      QrDataTooLongException(
        'Data does not fit version $version at level ${level.name}'
        '${needed == null ? '' : ' ($needed bits needed)'}; '
        'capacity is ${tables.dataCodewords(version, level) * 8} bits',
        bitsNeeded: needed,
        bitsAvailable: tables.dataCodewords(version, level) * 8,
      );

  static QrMatrix _build(
      List<QrSegment> segments, int version, QrEcLevel level, int? mask) {
    for (final s in segments) {
      if (s.mode != QrMode.eci &&
          s.numChars >= 1 << s.mode.charCountBits(version)) {
        throw QrDataTooLongException(
          'A ${s.mode.name} segment of ${s.numChars} characters is too long '
          'for version $version',
          bitsNeeded: null,
          bitsAvailable: tables.dataCodewords(version, level) * 8,
        );
      }
    }
    final data = buildDataCodewords(segments, version, level);
    final all = interleaveWithEc(data, version, level);
    final builder = MatrixBuilder(version)..placeCodewords(all);
    final chosen = mask ?? builder.applyBestMask(level);
    if (mask != null) {
      builder
        ..applyMask(mask)
        ..drawFormatBits(level, mask);
    }
    return QrMatrix.fromModules(builder.modules,
        version: version, ecLevel: level, mask: chosen);
  }
}
