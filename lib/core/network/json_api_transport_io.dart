import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'api_response.dart';
import 'json_api_transport.dart';

JsonApiTransport createPlatformJsonApiTransport({Object? httpClient}) {
  return IoJsonApiTransport(
    httpClient: httpClient is HttpClient ? httpClient : null,
  );
}

class IoJsonApiTransport implements JsonApiTransport {
  IoJsonApiTransport({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  @override
  Future<ApiResponse<dynamic>> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    String? bearerToken,
  }) async {
    try {
      final request = await _httpClient
          .openUrl(method, uri)
          .timeout(AppConstants.connectTimeout);

      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      headers?.forEach(request.headers.set);

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(
            AppConstants.receiveTimeout,
          );
      final responseText = await response.transform(utf8.decoder).join();
      return parseJsonApiResponse(response.statusCode, responseText);
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Tempo de ligação excedido.');
    } on AppException {
      rethrow;
    } catch (_) {
      throw const UnknownException();
    }
  }
}
