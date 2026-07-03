import '../../../core/errors/app_exception.dart';
import '../../../core/network/json_api_client.dart';
import '../domain/admin_audit_event.dart';
import '../domain/admin_merchant_summary.dart';
import '../domain/admin_operations_summary.dart';
import '../domain/admin_plan_catalog.dart';

class AdminPortalApi {
  const AdminPortalApi(this._client, this._resolveAccessToken);

  final JsonApiClient _client;
  final Future<String?> Function() _resolveAccessToken;

  Future<List<AdminMerchantSummary>> getMerchants({
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _requireToken();
    final response = await _client.get(
      '/admin/merchants',
      bearerToken: token,
      queryParameters: {
        'search': search,
        'limit': limit,
        'offset': offset,
      },
    );
    return _asMapList(response.data)
        .map(AdminMerchantSummary.fromJson)
        .toList(growable: false);
  }

  Future<AdminMerchantDetail> getMerchant(String merchantId) async {
    final token = await _requireToken();
    final response = await _client.get(
      '/admin/merchants/${Uri.encodeComponent(merchantId)}',
      bearerToken: token,
    );
    return AdminMerchantDetail.fromJson(_asMap(response.data));
  }

  Future<List<AdminAuditEvent>> getAuditEvents({
    String? targetType,
    String? targetId,
    String? merchantId,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _requireToken();
    final response = await _client.get(
      '/admin/audit-events',
      bearerToken: token,
      queryParameters: {
        'target_type': targetType,
        'target_id': targetId,
        'merchant_id': merchantId,
        'limit': limit,
        'offset': offset,
      },
    );
    return _asMapList(response.data)
        .map(AdminAuditEvent.fromJson)
        .toList(growable: false);
  }

  Future<List<AdminPlanCatalogItem>> getPlans() async {
    final token = await _requireToken();
    final response = await _client.get(
      '/admin/plans',
      bearerToken: token,
    );
    return _asMapList(response.data)
        .map(AdminPlanCatalogItem.fromJson)
        .toList(growable: false);
  }

  Future<AdminOperationsSummary> getOperationsSummary() async {
    final token = await _requireToken();
    final response = await _client.get(
      '/admin/operations/summary',
      bearerToken: token,
    );
    return AdminOperationsSummary.fromJson(_asMap(response.data));
  }

  Future<void> upsertPlan({
    required String planCode,
    required int version,
    required String name,
    required bool isActive,
  }) async {
    final token = await _requireToken();
    await _client.post(
      '/admin/plans',
      bearerToken: token,
      body: {
        'plan_code': planCode,
        'version': version,
        'name': name,
        'is_active': isActive,
      },
    );
  }

  Future<void> upsertPrice({
    required String planCode,
    required int pricingVersion,
    required String currency,
    required int amount,
    required String billingPeriod,
    required bool isActive,
  }) async {
    final token = await _requireToken();
    await _client.post(
      '/admin/prices',
      bearerToken: token,
      body: {
        'plan_code': planCode,
        'pricing_version': pricingVersion,
        'currency': currency,
        'amount': amount,
        'billing_period': billingPeriod,
        'is_active': isActive,
      },
    );
  }

  Future<void> upsertPlanFeature({
    required String planCode,
    required int planVersion,
    required String featureKey,
    required bool isEnabled,
    int? limitValue,
    String? unit,
  }) async {
    final token = await _requireToken();
    await _client.post(
      '/admin/plans/${Uri.encodeComponent(planCode)}/features',
      bearerToken: token,
      body: {
        'plan_version': planVersion,
        'feature_key': featureKey,
        'is_enabled': isEnabled,
        'limit_value': limitValue,
        'unit': unit,
      },
    );
  }

  Future<void> overrideEntitlement({
    required String merchantId,
    required String featureKey,
    required bool isEnabled,
    int? limitValue,
    String? unit,
  }) async {
    final token = await _requireToken();
    await _client.post(
      '/admin/merchants/${Uri.encodeComponent(merchantId)}/entitlements',
      bearerToken: token,
      body: {
        'feature_key': featureKey,
        'is_enabled': isEnabled,
        'limit_value': limitValue,
        'unit': unit,
      },
    );
  }

  Future<String> _requireToken() async {
    final token = await _resolveAccessToken();
    if (token == null || token.isEmpty) {
      throw const AuthException();
    }
    return token;
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((row) {
        return row.map((key, value) => MapEntry(key.toString(), value));
      }).toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }
}
