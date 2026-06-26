import 'app_constants.dart';

class AppRuntimeConfig {
  const AppRuntimeConfig({
    this.apiBaseUrl = AppConstants.apiBaseUrl,
    this.cloudFunctionsApiBaseUrl = AppConstants.cloudFunctionsApiBaseUrl,
    this.enableBackendAuth = AppConstants.enableBackendAuth,
  });

  final String apiBaseUrl;
  final String cloudFunctionsApiBaseUrl;
  final bool enableBackendAuth;

  AppRuntimeConfig copyWith({
    String? apiBaseUrl,
    String? cloudFunctionsApiBaseUrl,
    bool? enableBackendAuth,
  }) {
    return AppRuntimeConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      cloudFunctionsApiBaseUrl:
          cloudFunctionsApiBaseUrl ?? this.cloudFunctionsApiBaseUrl,
      enableBackendAuth: enableBackendAuth ?? this.enableBackendAuth,
    );
  }
}
