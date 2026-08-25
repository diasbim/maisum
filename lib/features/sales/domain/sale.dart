import 'package:freezed_annotation/freezed_annotation.dart';

import 'sale_item.dart';

part 'sale.freezed.dart';
part 'sale.g.dart';

enum SaleConfirmationStatus { pending, confirmed, rejected, baselineRequired }

extension SaleConfirmationStatusStorage on SaleConfirmationStatus {
  String get storageValue => switch (this) {
        SaleConfirmationStatus.pending => 'PENDING',
        SaleConfirmationStatus.confirmed => 'CONFIRMED',
        SaleConfirmationStatus.rejected => 'REJECTED',
        SaleConfirmationStatus.baselineRequired => 'BASELINE_REQUIRED',
      };
}

@freezed
class Sale with _$Sale {
  const Sale._();

  const factory Sale({
    required String id,
    required String customerId,
    required double amount,
    required int points,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(SaleConfirmationStatus.pending)
    SaleConfirmationStatus confirmationStatus,
    int? confirmedPoints,
    DateTime? confirmedAt,
    String? confirmationErrorCode,
    int? loyaltyPolicyVersion,
    @Default(<SaleItem>[]) List<SaleItem> items,
    @Default(false) bool synced,
  }) = _Sale;

  factory Sale.fromJson(Map<String, dynamic> json) => _$SaleFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'points': points,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
        'confirmation_status': confirmationStatus.storageValue,
        'confirmed_points': confirmedPoints,
        'confirmed_at': confirmedAt?.millisecondsSinceEpoch,
        'confirmation_error_code': confirmationErrorCode,
        'loyalty_policy_version': loyaltyPolicyVersion,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toClientSyncMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'points': points,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? createdAt).millisecondsSinceEpoch,
      };
}

Sale saleFromMap(Map<String, dynamic> map) => Sale(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      points: map['points'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as num).toInt(),
            ),
      confirmationStatus:
          _saleConfirmationStatusFromStorage(map['confirmation_status']),
      confirmedPoints: (map['confirmed_points'] as num?)?.toInt(),
      confirmedAt: map['confirmed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['confirmed_at'] as num).toInt(),
            ),
      confirmationErrorCode: map['confirmation_error_code'] as String?,
      loyaltyPolicyVersion: (map['loyalty_policy_version'] as num?)?.toInt(),
      items: saleItemsFromValue(map['items']),
      synced: (map['synced'] as int? ?? 0) == 1,
    );

SaleConfirmationStatus _saleConfirmationStatusFromStorage(Object? value) {
  return switch (value?.toString().toUpperCase()) {
    'CONFIRMED' => SaleConfirmationStatus.confirmed,
    'REJECTED' => SaleConfirmationStatus.rejected,
    'BASELINE_REQUIRED' => SaleConfirmationStatus.baselineRequired,
    _ => SaleConfirmationStatus.pending,
  };
}
