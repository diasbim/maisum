import 'app_constants.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    this.apiBaseUrl = AppConstants.apiBaseUrl,
    this.cloudFunctionsApiBaseUrl = AppConstants.cloudFunctionsApiBaseUrl,
    this.enableBackendAuth = AppConstants.enableBackendAuth,
    this.syncTransport = AppConstants.syncTransport,
  });

  final String apiBaseUrl;
  final String cloudFunctionsApiBaseUrl;
  final bool enableBackendAuth;
  final String syncTransport;

  bool get usesBackendSync =>
      syncTransport == AppConstants.syncTransportBackend;

  AppRuntimeConfig copyWith({
    String? apiBaseUrl,
    String? cloudFunctionsApiBaseUrl,
    bool? enableBackendAuth,
    String? syncTransport,
  }) {
    return AppRuntimeConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      cloudFunctionsApiBaseUrl:
          cloudFunctionsApiBaseUrl ?? this.cloudFunctionsApiBaseUrl,
      enableBackendAuth: enableBackendAuth ?? this.enableBackendAuth,
      syncTransport: syncTransport ?? this.syncTransport,
    );
  }
}
