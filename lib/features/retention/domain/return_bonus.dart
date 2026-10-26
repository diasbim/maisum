class ReturnBonusStatus {
  static const String active = 'ACTIVE';
  static const String redeemed = 'REDEEMED';
  static const String expired = 'EXPIRED';
  static const String cancelled = 'CANCELLED';
}

class ReturnBonusType {
  static const String discount = 'DISCOUNT';
  static const String extraPoints = 'EXTRA_POINTS';
  static const String freeService = 'FREE_SERVICE';
}

/// F1 Bónus de Regresso: server-issued after a sale, server-redeemed.
/// The client only ever displays and requests redemption of this model;
/// expiration/redemption/duplicate-prevention are always re-checked
/// server-side (see functions/src/retention_engine.ts).
class ReturnBonus {
  const ReturnBonus({
    required this.id,
    required this.customerId,
    required this.type,
    required this.value,
    required this.status,
    required this.issuedAt,
    required this.expiresAt,
    this.sourceSaleId,
    this.redeemedAt,
    this.redemptionSaleId,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String customerId;
  final String type;
  final double value;
  final String status;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? sourceSaleId;
  final DateTime? redeemedAt;
  final String? redemptionSaleId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  bool get isActive => status == ReturnBonusStatus.active;

  bool isExpired(DateTime now) =>
      status == ReturnBonusStatus.active && !expiresAt.isAfter(now);

  bool isRedeemable(DateTime now) => isActive && expiresAt.isAfter(now);

  ReturnBonus copyWith({
    String? status,
    DateTime? redeemedAt,
    String? redemptionSaleId,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return ReturnBonus(
      id: id,
      customerId: customerId,
      type: type,
      value: value,
      status: status ?? this.status,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      sourceSaleId: sourceSaleId,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      redemptionSaleId: redemptionSaleId ?? this.redemptionSaleId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'customer_id': customerId,
        'type': type,
        'value': value,
        'status': status,
        'issued_at': issuedAt.millisecondsSinceEpoch,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'source_sale_id': sourceSaleId,
        'redeemed_at': redeemedAt?.millisecondsSinceEpoch,
        'redemption_sale_id': redemptionSaleId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory ReturnBonus.fromMap(Map<String, dynamic> map) {
    return ReturnBonus(
      id: _readString(map, ['id']),
      customerId: _readString(map, ['customer_id', 'customerId']),
      type: _readString(map, ['type']),
      value: _readDouble(map, ['value']),
      status: _readString(map, ['status']),
      issuedAt: _readDateTime(map, ['issued_at', 'issuedAt']),
      expiresAt: _readDateTime(map, ['expires_at', 'expiresAt']),
      sourceSaleId: _readNullableString(map, ['source_sale_id', 'sourceSaleId']),
      redeemedAt: _readNullableDateTime(map, ['redeemed_at', 'redeemedAt']),
      redemptionSaleId:
          _readNullableString(map, ['redemption_sale_id', 'redemptionSaleId']),
      createdAt: _readDateTime(map, ['created_at', 'createdAt']),
      updatedAt: _readDateTime(map, ['updated_at', 'updatedAt']),
      synced: _readBool(map, ['synced']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReturnBonus &&
        other.id == id &&
        other.customerId == customerId &&
        other.type == type &&
        other.value == value &&
        other.status == status &&
        other.issuedAt == issuedAt &&
        other.expiresAt == expiresAt &&
        other.sourceSaleId == sourceSaleId &&
        other.redeemedAt == redeemedAt &&
        other.redemptionSaleId == redemptionSaleId &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.synced == synced;
  }

  @override
  int get hashCode => Object.hash(
        id,
        customerId,
        type,
        value,
        status,
        issuedAt,
        expiresAt,
        sourceSaleId,
        redeemedAt,
        redemptionSaleId,
        createdAt,
        updatedAt,
        synced,
      );
}

String _readString(Map<String, dynamic> map, List<String> keys) {
  final value = _readNullableString(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required string: ${keys.join('/')}');
}

String? _readNullableString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

double _readDouble(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

DateTime _readDateTime(Map<String, dynamic> map, List<String> keys) {
  final value = _readNullableDateTime(map, keys);
  if (value != null) return value;
  throw ArgumentError('Missing required date: ${keys.join('/')}');
}

DateTime? _readNullableDateTime(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String && value.isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is DateTime) return value;
  }
  return null;
}

bool _readBool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is num) return value.toInt() == 1;
  }
  return false;
}
