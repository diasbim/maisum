import '../../catalog/domain/merchant_item.dart';

class SaleItemInput {
  const SaleItemInput({
    required this.merchantItemId,
    required this.nameSnapshot,
    required this.typeSnapshot,
    this.quantity = 1,
    this.unitPrice,
  });

  factory SaleItemInput.fromMerchantItem(
    MerchantItem item, {
    int quantity = 1,
    double? unitPrice,
  }) {
    return SaleItemInput(
      merchantItemId: item.id,
      nameSnapshot: item.name,
      typeSnapshot: item.type,
      quantity: quantity,
      unitPrice: unitPrice ?? item.defaultPrice,
    );
  }

  final String merchantItemId;
  final String nameSnapshot;
  final MerchantItemType typeSnapshot;
  final int quantity;
  final double? unitPrice;

  double? get subtotal =>
      unitPrice == null ? null : unitPrice! * quantity.clamp(1, 999);

  SaleItemInput copyWith({
    String? merchantItemId,
    String? nameSnapshot,
    MerchantItemType? typeSnapshot,
    int? quantity,
    Object? unitPrice = _keep,
  }) {
    return SaleItemInput(
      merchantItemId: merchantItemId ?? this.merchantItemId,
      nameSnapshot: nameSnapshot ?? this.nameSnapshot,
      typeSnapshot: typeSnapshot ?? this.typeSnapshot,
      quantity: quantity ?? this.quantity,
      unitPrice: identical(unitPrice, _keep)
          ? this.unitPrice
          : (unitPrice as num?)?.toDouble(),
    );
  }
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.saleId,
    required this.merchantItemId,
    required this.nameSnapshot,
    required this.typeSnapshot,
    required this.quantity,
    required this.createdAt,
    required this.updatedAt,
    this.merchantId,
    this.unitPrice,
    this.subtotal,
    this.synced = false,
  });

  final String id;
  final String? merchantId;
  final String saleId;
  final String merchantItemId;
  final String nameSnapshot;
  final MerchantItemType typeSnapshot;
  final int quantity;
  final double? unitPrice;
  final double? subtotal;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;

  Map<String, dynamic> toJson() => toDbMap();

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'merchant_id': merchantId,
        'sale_id': saleId,
        'merchant_item_id': merchantItemId,
        'name_snapshot': nameSnapshot,
        'type_snapshot': typeSnapshot.dbValue,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: _readString(json, ['id']),
      merchantId: _readOptionalString(json, ['merchant_id', 'merchantId']),
      saleId: _readString(json, ['sale_id', 'saleId']),
      merchantItemId: _readString(
        json,
        ['merchant_item_id', 'merchantItemId'],
      ),
      nameSnapshot: _readString(json, ['name_snapshot', 'nameSnapshot']),
      typeSnapshot: merchantItemTypeFromDb(
        json['type_snapshot'] ?? json['typeSnapshot'],
      ),
      quantity: _readInt(json, ['quantity'], fallback: 1),
      unitPrice: _readOptionalDouble(json, ['unit_price', 'unitPrice']),
      subtotal: _readOptionalDouble(json, ['subtotal']),
      createdAt: _readDateTime(json, ['created_at', 'createdAt']),
      updatedAt: _readDateTime(json, ['updated_at', 'updatedAt']),
      synced: _readBool(json, ['synced']),
    );
  }
}

SaleItem saleItemFromMap(Map<String, dynamic> map) => SaleItem.fromJson(map);

List<SaleItem> saleItemsFromValue(Object? value) {
  if (value is List<SaleItem>) return value;
  if (value is List) {
    return value
        .whereType<Map>()
        .map((entry) => SaleItem.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }
  return const <SaleItem>[];
}

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

int _readInt(
  Map<String, dynamic> json,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return fallback;
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

bool _readBool(Map<String, dynamic> json, List<String> keys) {
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
  return false;
}
