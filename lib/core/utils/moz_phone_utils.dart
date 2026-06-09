import 'moz_phone_validator.dart';

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

    throw const FormatException(
        'Número de telefone inválido. Use: 8X XXX XXXX');
  }

  /// Normalises a raw phone input to local 9-digit format (8XXXXXXXX).
  static String normalizeToLocal(String raw) {
    final e164 = normalizeToE164(raw);
    return e164.substring(4);
  }

  static bool _isValidLocal(String local) {
    return MozPhoneValidator.isValidLocalPhone(local) &&
        _validPrefixes.any((p) => local.startsWith(p));
  }

  /// Masks a phone number for UI display, keeping only the last 4 digits.
  static String maskForDisplay(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return trimmed;

    final last4 = digits.substring(digits.length - 4);
    final maskedLocal = '*** *** $last4';

    if (digits.startsWith('258') && digits.length >= 12) {
      return '+258 $maskedLocal';
    }
    if (digits.length == 9) {
      return maskedLocal;
    }
    return '*** *** $last4';
  }

  /// Returns an error string or null — suitable for [TextFormField.validator].
  static String? validatorMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Insira o numero de telefone';
    }
    try {
      normalizeToE164(value.trim());
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }
}
