/// Normalizes and validates physical NFC card UIDs (factory identifiers of
/// NTAG21x / Mifare style cards: 4, 7 or 10 bytes). Mirrors the backend
/// normalization in functions/src/customer_nfc.ts so the same UID always
/// maps to the same Firestore document id regardless of separators/case
/// used by the reading device.
class NfcCardUidUtils {
  const NfcCardUidUtils._();

  static const _validHexLengths = {8, 14, 20};

  /// Normalizes a raw UID (which may contain ':' / '-' separators and mixed
  /// case, as commonly rendered by NFC tooling) into upper-case hex.
  ///
  /// Throws [FormatException] for invalid input.
  static String normalize(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s:-]'), '').toUpperCase();
    if (!isValid(cleaned)) {
      throw const FormatException('Invalid NFC card UID.');
    }
    return cleaned;
  }

  static bool isValid(String value) =>
      RegExp(r'^[0-9A-F]+$').hasMatch(value) &&
      _validHexLengths.contains(value.length);

  /// Like [normalize], but returns null instead of throwing.
  static String? tryNormalize(String raw) {
    try {
      return normalize(raw);
    } on FormatException {
      return null;
    }
  }

  /// Converts raw UID bytes read from a tag into the normalized hex form.
  static String fromBytes(List<int> bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return normalize(hex);
  }

  /// Masked form suitable for display/logging (never show the full UID).
  static String maskedLast4(String normalizedUid) => normalizedUid.length <= 4
      ? normalizedUid
      : '••••${normalizedUid.substring(normalizedUid.length - 4)}';
}
