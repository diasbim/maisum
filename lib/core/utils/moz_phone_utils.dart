/// Utility for Mozambique phone number validation and normalisation.
class MozPhoneUtils {
  // Valid Mozambican prefixes (first two digits of a 9-digit local number)
  static const _validPrefixes = ['82', '83', '84', '85', '86', '87'];

  /// Normalises a raw phone input to E.164 format (+258XXXXXXXXX).
  ///
  /// Accepts:
  ///  • 9-digit local number (8X XXX XXXX, with optional spaces)
  ///  • +258XXXXXXXXX
  ///  • 258XXXXXXXXX
  ///
  /// Throws [FormatException] for invalid input.
  static String normalizeToE164(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\s\-]'), '');

    if (clean.startsWith('+258')) {
      final local = clean.substring(4);
      if (_isValidLocal(local)) return '+258$local';
    } else if (clean.startsWith('258') && clean.length == 12) {
      final local = clean.substring(3);
      if (_isValidLocal(local)) return '+258$local';
    } else if (clean.length == 9 && _isValidLocal(clean)) {
      return '+258$clean';
    }

    throw const FormatException('Número de telefone inválido. Use: 8X XXX XXXX');
  }

  static bool _isValidLocal(String local) {
    if (local.length != 9) return false;
    if (!RegExp(r'^\d{9}$').hasMatch(local)) return false;
    return _validPrefixes.any((p) => local.startsWith(p));
  }

  /// Returns an error string or null — suitable for [TextFormField.validator].
  static String? validatorMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Insira o número de telefone';
    }
    try {
      normalizeToE164(value.trim());
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }
}
