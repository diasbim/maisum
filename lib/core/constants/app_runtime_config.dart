import 'app_constants.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    this.apiBaseUrl = AppConstants.apiBaseUrl,
    this.enableBackendAuth = AppConstants.enableBackendAuth,
    this.syncTransport = AppConstants.syncTransport,
  });

  final String apiBaseUrl;
  final bool enableBackendAuth;
  final String syncTransport;

  bool get usesBackendSync =>
      syncTransport == AppConstants.syncTransportBackend;

  AppRuntimeConfig copyWith({
    String? apiBaseUrl,
    bool? enableBackendAuth,
    String? syncTransport,
  }) {
    return AppRuntimeConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      enableBackendAuth: enableBackendAuth ?? this.enableBackendAuth,
      syncTransport: syncTransport ?? this.syncTransport,
    );
  }
}
