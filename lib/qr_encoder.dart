/// The pure-Dart QR Code encoder of qr_gen. It never imports Flutter, so it
/// runs on servers, in CLIs and in isolates.
library;

export 'src/encoder/ec_level.dart';
export 'src/encoder/encoder.dart';
export 'src/encoder/exceptions.dart';
export 'src/encoder/mode.dart';
export 'src/encoder/qr_matrix.dart';
export 'src/encoder/segment.dart' show QrSegment;
