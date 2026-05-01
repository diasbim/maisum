import 'package:freezed_annotation/freezed_annotation.dart';

part 'sale.freezed.dart';
part 'sale.g.dart';

@freezed
class Sale with _$Sale {
  const Sale._();

  const factory Sale({
    required String id,
    required String customerId,
    required double amount,
    required int points,
    required DateTime createdAt,
    @Default(false) bool synced,
  }) = _Sale;

  factory Sale.fromJson(Map<String, dynamic> json) => _$SaleFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'customer_id': customerId,
        'amount': amount,
        'points': points,
        'created_at': createdAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };
}

Sale saleFromMap(Map<String, dynamic> map) => Sale(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      points: map['points'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      synced: (map['synced'] as int? ?? 0) == 1,
    );
