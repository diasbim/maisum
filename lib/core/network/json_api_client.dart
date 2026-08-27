import '../constants/app_constants.dart';
import 'api_response.dart';
import 'json_api_transport.dart';

class JsonApiClient {
  JsonApiClient({Object? httpClient, String? baseUrl})
      : _transport = createJsonApiTransport(httpClient: httpClient),
        _baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  final JsonApiTransport _transport;
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

  Future<ApiResponse<dynamic>> patch(
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? queryParameters,
    Object? body,
    String? bearerToken,
  }) {
    return _send(
      'PATCH',
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
    return _transport.send(
      method,
      _buildUri(path, queryParameters),
      headers: headers,
      body: body,
      bearerToken: bearerToken,
    );
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
