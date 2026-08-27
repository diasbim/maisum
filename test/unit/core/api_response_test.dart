import 'package:flutter_test/flutter_test.dart';
import 'package:maisum/core/errors/app_exception.dart';
import 'package:maisum/core/network/api_response.dart';

void main() {
  test('preserves HTTP status for a non-JSON error response', () {
    expect(
      () => parseJsonApiResponse(403, '<html>Forbidden</html>'),
      throwsA(
        isA<ServerException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              'Erro no servidor.',
            ),
      ),
    );
  });

  test('uses the server message for a JSON error response', () {
    expect(
      () => parseJsonApiResponse(
        401,
        '{"success":false,"message":"Unauthorized"}',
      ),
      throwsA(
        isA<ServerException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.message, 'message', 'Unauthorized'),
      ),
    );
  });
}
