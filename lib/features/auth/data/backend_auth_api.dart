import '../../../core/network/api_response.dart';
import '../../../core/network/json_api_client.dart';
import '../domain/backend_bootstrap_session.dart';

class BackendAuthApi {
  const BackendAuthApi(this._client);

  final JsonApiClient _client;

  Future<ApiResponse<Map<String, dynamic>>> requestOtp({
    required String phone,
    String? deviceId,
  }) async {
    final response = await _client.post(
      '/auth/otp/request',
      body: {'phone': phone, if (deviceId != null) 'device_id': deviceId},
    );
    return ApiResponse<Map<String, dynamic>>(
      success: response.success,
      data: _mapData(response.data),
      message: response.message,
    );
  }

  Future<BackendBootstrapSession> verifyOtp({
    required String phone,
    required String code,
    String? verificationId,
    String? deviceId,
  }) async {
    final response = await _client.post(
      '/auth/otp/verify',
      body: {
        'phone': phone,
        'code': code,
        if (verificationId != null) 'verification_id': verificationId,
        if (deviceId != null) 'device_id': deviceId,
      },
    );
    return BackendBootstrapSession.fromJson(_requiredData(response));
  }

  Future<BackendBootstrapSession> exchangeFirebaseSession({
    required String firebaseIdToken,
    required String phone,
    String? deviceId,
  }) async {
    final response = await _client.post(
      '/auth/session/exchange',
      body: {
        'firebase_id_token': firebaseIdToken,
        'phone': phone,
        if (deviceId != null) 'device_id': deviceId,
      },
    );
    return BackendBootstrapSession.fromJson(_requiredData(response));
  }

  Future<BackendBootstrapSession> refreshSession({
    required String refreshToken,
    String? deviceId,
  }) async {
    final response = await _client.post(
      '/auth/refresh',
      body: {
        'refresh_token': refreshToken,
        if (deviceId != null) 'device_id': deviceId,
      },
    );
    return BackendBootstrapSession.fromJson(_requiredData(response));
  }

  Future<BackendBootstrapSession> restoreSession({
    required String accessToken,
    String? deviceId,
  }) async {
    final response = await _client.get(
      '/auth/restore',
      bearerToken: accessToken,
      queryParameters: {if (deviceId != null) 'device_id': deviceId},
    );
    return BackendBootstrapSession.fromJson(_requiredData(response));
  }

  Map<String, dynamic> _requiredData(ApiResponse<dynamic> response) {
    final data = _mapData(response.data);
    if (data == null) {
      throw StateError('Backend auth response did not include data');
    }
    return data;
  }

  Map<String, dynamic>? _mapData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
