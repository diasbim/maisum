class CustomerFeatureFlags {
  const CustomerFeatureFlags({
    required this.appEnabled,
    required this.redemptionEnabled,
    required this.qrEnabled,
    required this.pushEnabled,
    required this.deepLinksEnabled,
  });

  final bool appEnabled;
  final bool redemptionEnabled;
  final bool qrEnabled;
  final bool pushEnabled;
  final bool deepLinksEnabled;

  factory CustomerFeatureFlags.fromJson(Map<String, dynamic> json) =>
      CustomerFeatureFlags(
        appEnabled: json['customer_app_enabled'] == true,
        redemptionEnabled: json['customer_redemption_enabled'] == true,
        qrEnabled: json['customer_qr_enabled'] == true,
        pushEnabled: json['customer_push_enabled'] == true,
        deepLinksEnabled: json['customer_deep_links_enabled'] == true,
      );
}

class CustomerSessionDto {
  const CustomerSessionDto({
    required this.phone,
    required this.flags,
    required this.relationshipCount,
  });

  final String phone;
  final CustomerFeatureFlags flags;
  final int relationshipCount;

  factory CustomerSessionDto.fromJson(Map<String, dynamic> json) {
    final relationships = json['business_relationships'];
    return CustomerSessionDto(
      phone: json['phone_e164'] as String? ?? '',
      flags: CustomerFeatureFlags.fromJson(
        (json['feature_flags'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{
              'customer_app_enabled': json['customer_app_enabled']
            },
      ),
      relationshipCount: relationships is List ? relationships.length : 0,
    );
  }
}

class CustomerReward {
  const CustomerReward({
    required this.id,
    required this.businessId,
    required this.name,
    required this.description,
    required this.pointsRequired,
    required this.confirmedPoints,
    required this.pointsRemaining,
    required this.eligible,
    this.expiresAt,
  });

  final String id;
  final String businessId;
  final String name;
  final String? description;
  final int pointsRequired;
  final int confirmedPoints;
  final int pointsRemaining;
  final bool eligible;
  final DateTime? expiresAt;

  factory CustomerReward.fromJson(Map<String, dynamic> json) => CustomerReward(
        id: json['reward_id'] as String? ?? '',
        businessId: json['business_id'] as String? ?? '',
        name: json['name'] as String? ?? 'Recompensa',
        description: json['description'] as String?,
        pointsRequired: (json['points_required'] as num?)?.toInt() ?? 0,
        confirmedPoints: (json['confirmed_points'] as num?)?.toInt() ?? 0,
        pointsRemaining: (json['points_remaining'] as num?)?.toInt() ?? 0,
        eligible: json['eligible'] == true,
        expiresAt: _optionalDateTime(json['expires_at']),
      );
}

class CustomerBusiness {
  const CustomerBusiness({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.confirmedPoints,
    required this.rewards,
    this.logoUrl,
    this.lastVisitAt,
    this.nextReward,
  });

  final String id;
  final String name;
  final String? address;
  final String? phone;
  final int confirmedPoints;
  final List<CustomerReward> rewards;
  final String? logoUrl;
  final DateTime? lastVisitAt;
  final CustomerReward? nextReward;

  factory CustomerBusiness.fromJson(Map<String, dynamic> json) =>
      CustomerBusiness(
        id: json['business_id'] as String? ?? '',
        name: json['name'] as String? ?? 'Negócio',
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        confirmedPoints: (json['confirmed_points'] as num?)?.toInt() ?? 0,
        logoUrl: json['logo_url'] as String?,
        lastVisitAt: _optionalDateTime(json['last_visit_at']),
        rewards: ((json['rewards'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => CustomerReward.fromJson({
                  ...item.cast<String, dynamic>(),
                  'business_id': json['business_id'],
                }))
            .toList(),
        nextReward: json['next_reward'] is Map
            ? CustomerReward.fromJson({
                ...(json['next_reward'] as Map).cast<String, dynamic>(),
                'business_id': json['business_id'],
              })
            : null,
      );
}

class CustomerActivity {
  const CustomerActivity({
    required this.id,
    required this.businessId,
    required this.type,
    required this.pointsDelta,
    required this.occurredAt,
    this.rewardId,
    this.businessName,
    this.rewardName,
    this.redemptionStatus,
  });

  final String id;
  final String businessId;
  final String type;
  final int pointsDelta;
  final DateTime occurredAt;
  final String? rewardId;
  final String? businessName;
  final String? rewardName;
  final CustomerRedemptionStatus? redemptionStatus;

  factory CustomerActivity.fromJson(Map<String, dynamic> json) =>
      CustomerActivity(
        id: json['entry_id'] as String? ?? '',
        businessId: json['business_id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        pointsDelta: (json['points_delta'] as num?)?.toInt() ?? 0,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          (json['occurred_at'] as num?)?.toInt() ?? 0,
        ),
        rewardId: json['reward_id'] as String?,
        businessName: json['business_name'] as String?,
        rewardName: json['reward_name'] as String?,
        redemptionStatus: json['redemption_status'] == null
            ? null
            : _customerRedemptionStatus(json['redemption_status']),
      );
}

class CustomerPreferences {
  const CustomerPreferences({
    required this.notificationsEnabled,
    required this.marketingEnabled,
    required this.deepLinksEnabled,
  });

  final bool notificationsEnabled;
  final bool marketingEnabled;
  final bool deepLinksEnabled;

  factory CustomerPreferences.fromJson(Map<String, dynamic> json) =>
      CustomerPreferences(
        notificationsEnabled: json['notifications_enabled'] != false,
        marketingEnabled: json['marketing_enabled'] == true,
        deepLinksEnabled: json['deep_links_enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'notifications_enabled': notificationsEnabled,
        'marketing_enabled': marketingEnabled,
        'deep_links_enabled': deepLinksEnabled,
      };
}

class CustomerProfile {
  const CustomerProfile({
    required this.displayName,
    required this.phone,
    required this.linkedBusinessCount,
    required this.preferences,
  });

  final String? displayName;
  final String phone;
  final int linkedBusinessCount;
  final CustomerPreferences preferences;

  factory CustomerProfile.fromJson(Map<String, dynamic> json) =>
      CustomerProfile(
        displayName: json['display_name'] as String?,
        phone: json['phone_e164'] as String? ?? '',
        linkedBusinessCount:
            (json['linked_business_count'] as num?)?.toInt() ?? 0,
        preferences: CustomerPreferences.fromJson(
          (json['preferences'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        ),
      );
}

class CustomerQr {
  const CustomerQr({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
  factory CustomerQr.fromJson(Map<String, dynamic> json) => CustomerQr(
        token: json['token'] as String? ?? '',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['expires_at'] as num?)?.toInt() ?? 0,
        ),
      );
}

enum CustomerRedemptionStatus { pending, consumed, expired }

CustomerRedemptionStatus _customerRedemptionStatus(dynamic value) {
  return switch (value?.toString().toUpperCase()) {
    'CONSUMED' => CustomerRedemptionStatus.consumed,
    'EXPIRED' => CustomerRedemptionStatus.expired,
    _ => CustomerRedemptionStatus.pending,
  };
}

class CustomerRedemptionReceipt {
  const CustomerRedemptionReceipt({
    required this.id,
    required this.businessId,
    required this.rewardId,
    required this.code,
    required this.pointsSpent,
    required this.confirmedPoints,
    required this.redeemedAt,
    required this.codeExpiresAt,
    required this.status,
    this.consumedAt,
  });

  final String id;
  final String businessId;
  final String rewardId;
  final String code;
  final int pointsSpent;
  final int? confirmedPoints;
  final DateTime redeemedAt;
  final DateTime codeExpiresAt;
  final CustomerRedemptionStatus status;
  final DateTime? consumedAt;

  CustomerRedemptionReceipt copyWith({
    CustomerRedemptionStatus? status,
    DateTime? consumedAt,
  }) {
    return CustomerRedemptionReceipt(
      id: id,
      businessId: businessId,
      rewardId: rewardId,
      code: code,
      pointsSpent: pointsSpent,
      confirmedPoints: confirmedPoints,
      redeemedAt: redeemedAt,
      codeExpiresAt: codeExpiresAt,
      status: status ?? this.status,
      consumedAt: consumedAt ?? this.consumedAt,
    );
  }

  factory CustomerRedemptionReceipt.fromJson(Map<String, dynamic> json) {
    final redeemedAt = DateTime.fromMillisecondsSinceEpoch(
      (json['redeemed_at'] as num?)?.toInt() ?? 0,
    );
    final explicitCodeExpiry =
        (json['redemption_code_expires_at'] as num?)?.toInt();
    return CustomerRedemptionReceipt(
      id: json['redemption_id'] as String? ?? '',
      businessId: json['business_id'] as String? ?? '',
      rewardId: json['reward_id'] as String? ?? '',
      code: json['redemption_code'] as String? ?? '',
      pointsSpent: (json['points_spent'] as num?)?.toInt() ?? 0,
      confirmedPoints: (json['confirmed_points'] as num?)?.toInt(),
      redeemedAt: redeemedAt,
      codeExpiresAt: explicitCodeExpiry == null
          ? redeemedAt.add(const Duration(minutes: 15))
          : DateTime.fromMillisecondsSinceEpoch(explicitCodeExpiry),
      status: _customerRedemptionStatus(json['fulfillment_status']),
      consumedAt: _optionalDateTime(json['consumed_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'redemption_id': id,
        'business_id': businessId,
        'reward_id': rewardId,
        'redemption_code': code,
        'points_spent': pointsSpent,
        'confirmed_points': confirmedPoints,
        'redeemed_at': redeemedAt.millisecondsSinceEpoch,
        'redemption_code_expires_at': codeExpiresAt.millisecondsSinceEpoch,
        'fulfillment_status': status.name.toUpperCase(),
        'consumed_at': consumedAt?.millisecondsSinceEpoch,
      };
}

class MerchantRedemptionPreview {
  const MerchantRedemptionPreview({
    required this.receipt,
    required this.customerName,
    required this.customerPhone,
    required this.rewardName,
    required this.businessName,
    required this.idempotentReplay,
  });

  final CustomerRedemptionReceipt receipt;
  final String customerName;
  final String? customerPhone;
  final String rewardName;
  final String businessName;
  final bool idempotentReplay;

  factory MerchantRedemptionPreview.fromJson(Map<String, dynamic> json) {
    final customer =
        (json['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reward =
        (json['reward'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MerchantRedemptionPreview(
      receipt: CustomerRedemptionReceipt.fromJson(json),
      customerName: customer['name'] as String? ?? 'Cliente MaisUm',
      customerPhone: customer['phone'] as String?,
      rewardName: reward['name'] as String? ?? 'Prémio',
      businessName: json['business_name'] as String? ?? 'Negócio',
      idempotentReplay: json['idempotent_replay'] == true,
    );
  }
}

DateTime? _optionalDateTime(dynamic value) {
  if (value is! num || value.toInt() <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(value.toInt());
}
