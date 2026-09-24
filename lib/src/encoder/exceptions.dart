/// Thrown when data cannot be encoded as a QR Code symbol.
class QrEncodeException implements Exception {
  /// Creates an exception with a human-readable [message].
  const QrEncodeException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'QrEncodeException: $message';
}

/// Thrown when the data does not fit the requested (or largest allowed)
/// version at the requested error correction level.
class QrDataTooLongException extends QrEncodeException {
  /// Creates the exception. [bitsNeeded] is null when a segment was too long
  /// for its character count indicator.
  const QrDataTooLongException(super.message,
      {required this.bitsNeeded, required this.bitsAvailable});

  /// Bits the data needs in the largest version tried, if known.
  final int? bitsNeeded;

  /// Data bits available in that version.
  final int bitsAvailable;

  @override
  String toString() => 'QrDataTooLongException: $message';
}
