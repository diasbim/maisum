import 'json_api_transport_io.dart'
    if (dart.library.html) 'json_api_transport_web.dart';

import 'api_response.dart';

abstract class JsonApiTransport {
  Future<ApiResponse<dynamic>> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    String? bearerToken,
  });
}

JsonApiTransport createJsonApiTransport({Object? httpClient}) {
  return createPlatformJsonApiTransport(httpClient: httpClient);
}
