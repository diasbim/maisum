// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'api_response.dart';
import 'json_api_transport.dart';

JsonApiTransport createPlatformJsonApiTransport({Object? httpClient}) {
  return const WebJsonApiTransport();
}

class WebJsonApiTransport implements JsonApiTransport {
  const WebJsonApiTransport();

  @override
  Future<ApiResponse<dynamic>> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    String? bearerToken,
  }) async {
    final request = html.HttpRequest();

    try {
      request.open(method, uri.toString());
      request.setRequestHeader('Accept', 'application/json');
      request.setRequestHeader('Content-Type', 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.setRequestHeader('Authorization', 'Bearer $bearerToken');
      }
      headers?.forEach(request.setRequestHeader);

      final completer = Completer<ApiResponse<dynamic>>();
      request.onLoad.listen((_) {
        try {
          completer.complete(parseJsonApiResponse(
            request.status ?? 0,
            request.responseText ?? '',
          ));
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      });
      request.onError.listen((_) => completer.completeError(
            const NetworkException(),
            StackTrace.current,
          ));
      request.onTimeout.listen((_) => completer.completeError(
            const NetworkException('Tempo de ligação excedido.'),
            StackTrace.current,
          ));

      request.timeout = AppConstants.receiveTimeout.inMilliseconds;
      request.send(body == null ? null : jsonEncode(body));
      return completer.future.timeout(AppConstants.receiveTimeout);
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const NetworkException('Tempo de ligação excedido.');
    } catch (_) {
      throw const UnknownException();
    }
  }
}
