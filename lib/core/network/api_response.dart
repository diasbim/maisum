import 'dart:convert';

import '../errors/app_exception.dart';

class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.envelope,
  });

  final bool success;
  final T? data;
  final String? message;

  /// The decoded response object as it arrived, when the body was a JSON
  /// object.
  ///
  /// Some endpoints put per-request facts beside `data` rather than inside it —
  /// paging and truncation, for instance — and those are the ones a caller has
  /// to read to know whether the list it received is the whole list.
  final Map<String, dynamic>? envelope;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromData,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool? ?? true,
      data: fromData != null && json['data'] != null
          ? fromData(json['data'])
          : null,
      message: json['message'] as String?,
      envelope: json,
    );
  }
}

ApiResponse<dynamic> parseJsonApiResponse(int statusCode, String responseText) {
  dynamic decoded;
  if (responseText.isEmpty) {
    decoded = <String, dynamic>{'success': statusCode < 400};
  } else {
    try {
      decoded = jsonDecode(responseText);
    } on FormatException {
      if (statusCode >= 400) {
        throw ServerException(
          statusCode: statusCode,
          message: 'Erro no servidor.',
        );
      }
      rethrow;
    }
  }

  if (statusCode >= 400) {
    final message =
        decoded is Map<String, dynamic> ? decoded['message'] as String? : null;
    throw ServerException(
      statusCode: statusCode,
      message: message ?? 'Erro no servidor.',
    );
  }

  if (decoded is! Map<String, dynamic>) {
    return ApiResponse<dynamic>(success: true, data: decoded);
  }

  return ApiResponse<dynamic>.fromJson(decoded, (data) => data);
}
