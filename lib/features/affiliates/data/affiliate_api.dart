import '../../../core/network/api_response.dart';
import '../../../core/network/json_api_client.dart';
import '../domain/merchant_affiliate_dtos.dart';

/// Everything the merchant app asks the affiliate API, in one place.
///
/// The business is never named in a request: the server reads it from the
/// authenticated session, so a till cannot address another shop's affiliates by
/// sending a different id. For the same reason nothing here accepts a merchant
/// id parameter — there is only ever the caller's own.
///
/// Reads are open to any authenticated staff; writes are refused with `403`
/// unless the caller owns the business. The repository above decides whether to
/// offer the button, but this layer does not pretend the check is local: an
/// operator who gets past the UI still gets the server's refusal.
class AffiliateApi {
  const AffiliateApi(this._client, this._resolveAccessToken);

  final JsonApiClient _client;
  final Future<String?> Function() _resolveAccessToken;

  // ── affiliates ─────────────────────────────────────────────────────────────

  Future<AffiliatePage<MerchantAffiliate>> listAffiliates({
    String? search,
    String? status,
    int? limit,
    int? offset,
  }) async {
    final response = await _client.get(
      '/merchant/affiliates',
      bearerToken: await _requireToken(),
      queryParameters: <String, Object?>{
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    );
    return AffiliatePage.fromEnvelope(
      response.envelope,
      response.data,
      MerchantAffiliate.fromMap,
    );
  }

  Future<MerchantAffiliate> createAffiliate({
    required String name,
    required String phone,
    required String benefitType,
    required double benefitValue,
    int? usageLimit,
    bool? firstVisitOnly,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool includeUsageLimit = false,
  }) async {
    final response = await _client.post(
      '/merchant/affiliates',
      bearerToken: await _requireToken(),
      body: <String, Object?>{
        'name': name,
        'phone': phone,
        'benefit_type': benefitType,
        'benefit_value': benefitValue,
        // `null` is meaningful here — it is how "no limit" is expressed — so
        // the key is only dropped when the caller had nothing to say at all.
        if (includeUsageLimit || usageLimit != null) 'usage_limit': usageLimit,
        if (firstVisitOnly != null) 'first_visit_only': firstVisitOnly,
        if (startsAt != null) 'starts_at': startsAt.millisecondsSinceEpoch,
        if (expiresAt != null) 'expires_at': expiresAt.millisecondsSinceEpoch,
      },
    );
    return MerchantAffiliate.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliate> getAffiliate(String affiliateId) async {
    final response = await _client.get(
      '/merchant/affiliates/$affiliateId',
      bearerToken: await _requireToken(),
    );
    return MerchantAffiliate.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliate> renameAffiliate({
    required String affiliateId,
    required String name,
  }) async {
    final response = await _client.patch(
      '/merchant/affiliates/$affiliateId',
      bearerToken: await _requireToken(),
      body: <String, Object?>{'name': name},
    );
    return MerchantAffiliate.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliate> activateAffiliate(String affiliateId) async {
    final response = await _client.post(
      '/merchant/affiliates/$affiliateId/activate',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliate.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliate> deactivateAffiliate(String affiliateId) async {
    final response = await _client.post(
      '/merchant/affiliates/$affiliateId/deactivate',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliate.fromMap(_requireMap(response));
  }

  // ── codes ──────────────────────────────────────────────────────────────────

  Future<AffiliatePage<MerchantAffiliateCode>> listCodes({
    String? affiliateId,
    String? status,
    int? limit,
    int? offset,
  }) async {
    final response = await _client.get(
      '/merchant/affiliate-codes',
      bearerToken: await _requireToken(),
      queryParameters: <String, Object?>{
        if (affiliateId != null) 'affiliate_id': affiliateId,
        if (status != null && status.isNotEmpty) 'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    );
    return AffiliatePage.fromEnvelope(
      response.envelope,
      response.data,
      MerchantAffiliateCode.fromMap,
    );
  }

  Future<MerchantAffiliateCode> getCode(String codeId) async {
    final response = await _client.get(
      '/merchant/affiliate-codes/$codeId',
      bearerToken: await _requireToken(),
    );
    return MerchantAffiliateCode.fromMap(_requireMap(response));
  }

  /// Edits a code's terms.
  ///
  /// Only the keys present are applied, and `starts_at`/`expires_at` travel
  /// together because the server validates them as a pair: sending one alone is
  /// answered with `invalid_dates` rather than a half-applied change.
  Future<MerchantAffiliateCode> updateCode({
    required String codeId,
    String? benefitType,
    double? benefitValue,
    DateTime? startsAt,
    DateTime? expiresAt,
    int? usageLimit,
    bool? firstVisitOnly,
    bool clearUsageLimit = false,
  }) async {
    final response = await _client.patch(
      '/merchant/affiliate-codes/$codeId',
      bearerToken: await _requireToken(),
      body: <String, Object?>{
        if (benefitType != null && benefitValue != null) ...<String, Object?>{
          'benefit_type': benefitType,
          'benefit_value': benefitValue,
        },
        if (startsAt != null && expiresAt != null) ...<String, Object?>{
          'starts_at': startsAt.millisecondsSinceEpoch,
          'expires_at': expiresAt.millisecondsSinceEpoch,
        },
        if (clearUsageLimit)
          'usage_limit': null
        else if (usageLimit != null)
          'usage_limit': usageLimit,
        if (firstVisitOnly != null) 'first_visit_only': firstVisitOnly,
      },
    );
    return MerchantAffiliateCode.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliateCode> enableCode(String codeId) async {
    final response = await _client.post(
      '/merchant/affiliate-codes/$codeId/enable',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliateCode.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliateCode> disableCode(String codeId) async {
    final response = await _client.post(
      '/merchant/affiliate-codes/$codeId/disable',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliateCode.fromMap(_requireMap(response));
  }

  // ── rewards ────────────────────────────────────────────────────────────────

  Future<AffiliatePage<MerchantAffiliateReward>> listRewards({
    String? affiliateId,
    String? status,
    int? limit,
    int? offset,
  }) async {
    final response = await _client.get(
      '/merchant/affiliate-rewards',
      bearerToken: await _requireToken(),
      queryParameters: <String, Object?>{
        if (affiliateId != null) 'affiliate_id': affiliateId,
        if (status != null && status.isNotEmpty) 'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    );
    return AffiliatePage.fromEnvelope(
      response.envelope,
      response.data,
      MerchantAffiliateReward.fromMap,
    );
  }

  Future<MerchantAffiliateReward> approveReward(String rewardId) async {
    final response = await _client.post(
      '/merchant/affiliate-rewards/$rewardId/approve',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliateReward.fromMap(_requireMap(response));
  }

  Future<MerchantAffiliateReward> cancelReward(String rewardId) async {
    final response = await _client.post(
      '/merchant/affiliate-rewards/$rewardId/cancel',
      bearerToken: await _requireToken(),
      body: const <String, Object?>{},
    );
    return MerchantAffiliateReward.fromMap(_requireMap(response));
  }

  // ── referrals ──────────────────────────────────────────────────────────────

  Future<AffiliatePage<MerchantReferralAttribution>> listReferrals({
    String? affiliateId,
    String? status,
    int? limit,
    int? offset,
  }) async {
    final response = await _client.get(
      '/merchant/referrals',
      bearerToken: await _requireToken(),
      queryParameters: <String, Object?>{
        if (affiliateId != null) 'affiliate_id': affiliateId,
        if (status != null && status.isNotEmpty) 'status': status,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    );
    return AffiliatePage.fromEnvelope(
      response.envelope,
      response.data,
      MerchantReferralAttribution.fromMap,
    );
  }

  Future<MerchantReferralDetail> getReferral(String attributionId) async {
    final response = await _client.get(
      '/merchant/referrals/$attributionId',
      bearerToken: await _requireToken(),
    );
    return MerchantReferralDetail.fromMap(_requireMap(response));
  }

  // ── metrics ────────────────────────────────────────────────────────────────

  Future<AffiliateMetricsSummary> merchantMetrics() async {
    final response = await _client.get(
      '/merchant/affiliates/metrics',
      bearerToken: await _requireToken(),
    );
    return AffiliateMetricsSummary.fromMap(_requireMap(response));
  }

  Future<AffiliateMetricsSummary> affiliateMetrics(String affiliateId) async {
    final response = await _client.get(
      '/merchant/affiliates/$affiliateId/metrics',
      bearerToken: await _requireToken(),
    );
    return AffiliateMetricsSummary.fromMap(_requireMap(response));
  }

  Future<String> _requireToken() async {
    final token = await _resolveAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sessão expirada. Faça login novamente.');
    }
    return token;
  }

  Map<String, dynamic> _requireMap(ApiResponse<dynamic> response) {
    final value = response.data;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('Resposta sem dados do servidor.');
  }
}
