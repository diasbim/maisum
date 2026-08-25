enum MerchantItemType {
  service,
  product,
}

extension MerchantItemTypeX on MerchantItemType {
  String get dbValue => switch (this) {
        MerchantItemType.service => 'SERVICE',
        MerchantItemType.product => 'PRODUCT',
      };

  String get label => switch (this) {
        MerchantItemType.service => 'Serviço',
        MerchantItemType.product => 'Produto',
      };
}

MerchantItemType merchantItemTypeFromDb(Object? value) {
  final normalized = value?.toString().trim().toUpperCase();
  return switch (normalized) {
    'PRODUCT' => MerchantItemType.product,
    _ => MerchantItemType.service,
  };
}

class MerchantItem {
  const MerchantItem({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    required this.displayOrder,
    required this.createdAt,
    required this.updatedAt,
    this.merchantId,
    this.defaultPrice,
    this.synced = false,
  });

  final String id;
  final String? merchantId;
  final String name;
  final MerchantItemType type;
  final double? defaultPrice;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  MerchantItem copyWith({
    String? id,
    String? merchantId,
    String? name,
    MerchantItemType? type,
    Object? defaultPrice = _keep,
    bool? isActive,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return MerchantItem(
      id: id ?? this.id,
      merchantId: merchantId ?? this.merchantId,
      name: name ?? this.name,
      type: type ?? this.type,
      defaultPrice: identical(defaultPrice, _keep)
          ? this.defaultPrice
          : (defaultPrice as num?)?.toDouble(),
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() => toDbMap();

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'name': name,
        'type': type.dbValue,
        'default_price': defaultPrice,
        'is_active': isActive ? 1 : 0,
        'display_order': displayOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory MerchantItem.fromJson(Map<String, dynamic> json) {
    return MerchantItem(
      id: _readString(json, ['id']),
      merchantId: _readOptionalString(json, ['merchant_id', 'merchantId']),
      name: _readString(json, ['name']),
      type: merchantItemTypeFromDb(json['type']),
      defaultPrice: _readOptionalDouble(
        json,
        ['default_price', 'defaultPrice'],
      ),
      isActive: _readBool(json, ['is_active', 'isActive'], fallback: true),
      displayOrder: _readInt(json, ['display_order', 'displayOrder']),
      createdAt: _readDateTime(json, ['created_at', 'createdAt']),
      updatedAt: _readDateTime(json, ['updated_at', 'updatedAt']),
      synced: _readBool(json, ['synced']),
    );
  }
}

MerchantItem merchantItemFromMap(Map<String, dynamic> map) =>
    MerchantItem.fromJson(map);

const _keep = Object();

String _readString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  throw ArgumentError('Missing required string: ${keys.join('/')}');
}

String? _readOptionalString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

double? _readOptionalDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
  }
  return null;
}

int _readInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

DateTime _readDateTime(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.trim().isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is DateTime) return value;
  }
  throw ArgumentError('Missing required date: ${keys.join('/')}');
}

bool _readBool(
  Map<String, dynamic> json,
  List<String> keys, {
  bool fallback = false,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is num) return value.toInt() == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true') return true;
      if (normalized == '0' || normalized == 'false') return false;
    }
  }
  return fallback;
}
