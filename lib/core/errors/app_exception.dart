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
