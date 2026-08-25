enum LoyaltyLedgerEntryType {
  earn,
  redeem,
  adjustment,
  expiration,
  migration,
}

class CustomerLoyaltyBalance {
  const CustomerLoyaltyBalance({
    required this.confirmedPoints,
    required this.pendingPoints,
    required this.legacyPoints,
  });

  final int? confirmedPoints;
  final int pendingPoints;
  final int legacyPoints;

  bool get hasConfirmedBaseline => confirmedPoints != null;

  int get projectedPoints =>
      confirmedPoints == null ? legacyPoints : confirmedPoints! + pendingPoints;
}

LoyaltyLedgerEntryType loyaltyLedgerEntryTypeFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'EARN' => LoyaltyLedgerEntryType.earn,
    'REDEEM' => LoyaltyLedgerEntryType.redeem,
    'ADJUSTMENT' => LoyaltyLedgerEntryType.adjustment,
    'EXPIRATION' => LoyaltyLedgerEntryType.expiration,
    _ => LoyaltyLedgerEntryType.migration,
  };
}

class LoyaltyLedgerEntry {
  const LoyaltyLedgerEntry({
    required this.id,
    required this.merchantId,
    required this.customerId,
    required this.entryType,
    required this.pointsDelta,
    required this.sourceType,
    required this.sourceId,
    required this.policyVersion,
    required this.occurredAt,
    required this.createdAt,
    required this.balanceAfter,
  });

  final String id;
  final String merchantId;
  final String customerId;
  final LoyaltyLedgerEntryType entryType;
  final int pointsDelta;
  final String sourceType;
  final String sourceId;
  final int policyVersion;
  final DateTime occurredAt;
  final DateTime createdAt;
  final int balanceAfter;
}

LoyaltyLedgerEntry loyaltyLedgerEntryFromMap(Map<String, dynamic> map) {
  return LoyaltyLedgerEntry(
    id: map['id'] as String,
    merchantId: map['merchant_id'] as String,
    customerId: map['customer_id'] as String,
    entryType: loyaltyLedgerEntryTypeFromStorage(map['entry_type']),
    pointsDelta: (map['points_delta'] as num).toInt(),
    sourceType: map['source_type'] as String,
    sourceId: map['source_id'] as String,
    policyVersion: (map['policy_version'] as num).toInt(),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      (map['occurred_at'] as num).toInt(),
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['created_at'] as num).toInt(),
    ),
    balanceAfter: (map['balance_after'] as num).toInt(),
  );
}
