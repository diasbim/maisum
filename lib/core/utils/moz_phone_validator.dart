class MozPhoneValidator {
  static final RegExp _phoneRegExp = RegExp(r'^(82|83|84|85|86|87)\d{7}$');

  static bool isValidLocalPhone(String input) {
    final digits = _digitsOnly(input);
    return _phoneRegExp.hasMatch(digits);
  }

  static String? validationMessage(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) {
      return 'Introduza o número de telemóvel';
    }

    if (!isValidLocalPhone(value)) {
      return 'Número inválido. Use os prefixos 82–87 e 9 dígitos.';
    }

    return null;
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }
}
