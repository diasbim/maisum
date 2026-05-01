import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

@freezed
class Customer with _$Customer {
  const Customer._();

  const factory Customer({
    required String id,
    required String name,
    required String phone,
    @Default(0) int totalPoints,
    required DateTime createdAt,
    DateTime? updatedAt,
    @Default(false) bool synced,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'total_points': totalPoints,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };
}

Customer customerFromMap(Map<String, dynamic> map) => Customer(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String,
      totalPoints: map['total_points'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      synced: (map['synced'] as int? ?? 0) == 1,
    );
