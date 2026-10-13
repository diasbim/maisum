sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class NetworkException extends AppException {
  const NetworkException([super.message = 'Sem ligação à internet.']);
}

final class AuthException extends AppException {
  const AuthException(
      [super.message = 'Sessão expirada. Faça login novamente.']);
}

final class CustomerFeatureDisabledException extends AppException {
  const CustomerFeatureDisabledException([
    super.message = 'A aplicação de cliente não está disponível.',
  ]);
}

/// Thrown when the user closes the Google account picker without choosing
/// an account. This is a normal, expected user action — not a failure — so
/// it must never be reported as an error or surfaced with error styling.
final class GoogleSignInCancelledException extends AppException {
  const GoogleSignInCancelledException([
    super.message = 'Login cancelado.',
  ]);
}

final class ServerException extends AppException {
  const ServerException(
      {required this.statusCode, String message = 'Erro no servidor.'})
      : super(message);
  final int statusCode;
}

final class DatabaseException extends AppException {
  const DatabaseException([super.message = 'Erro na base de dados local.']);
}

final class UnknownException extends AppException {
  const UnknownException([super.message = 'Algo correu mal. Tente novamente.']);
}
