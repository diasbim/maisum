import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'api_response.dart';

class JsonApiClient {
  JsonApiClient({HttpClient? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? HttpClient(),
      _baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  final HttpClient _httpClient;
  final String _baseUrl;

  String get baseUrl => _baseUrl;

  Future<ApiResponse<dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? queryParameters,
    String? bearerToken,
  }) {
    return _send(
      'GET',
      path,
      headers: headers,
      queryParameters: queryParameters,
      bearerToken: bearerToken,
    );
  }

  Future<ApiResponse<dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? queryParameters,
    Object? body,
    String? bearerToken,
  }) {
    return _send(
      'POST',
      path,
      headers: headers,
      queryParameters: queryParameters,
      body: body,
      bearerToken: bearerToken,
    );
  }

  Future<ApiResponse<dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? queryParameters,
    Object? body,
    String? bearerToken,
  }) async {
    final uri = _buildUri(path, queryParameters);

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
      final decoded = responseText.isEmpty
          ? <String, dynamic>{'success': response.statusCode < 400}
          : jsonDecode(responseText);

      if (response.statusCode >= 400) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String?
            : null;
        throw ServerException(
          statusCode: response.statusCode,
          message: message ?? 'Erro no servidor.',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        return ApiResponse<dynamic>(success: true, data: decoded);
      }

      return ApiResponse<dynamic>.fromJson(decoded, (data) => data);
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

  Uri _buildUri(String path, Map<String, Object?>? queryParameters) {
    final normalizedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    final filteredQuery = <String, String>{};
    queryParameters?.forEach((key, value) {
      if (value != null) {
        filteredQuery[key] = value.toString();
      }
    });
    if (filteredQuery.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: {...uri.queryParameters, ...filteredQuery},
    );
  }
}
