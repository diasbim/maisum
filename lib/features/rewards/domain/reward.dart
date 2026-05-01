import 'package:freezed_annotation/freezed_annotation.dart';

part 'reward.freezed.dart';
part 'reward.g.dart';

@freezed
class Reward with _$Reward {
  const Reward._();

  const factory Reward({
    required String id,
    required String name,
    required int pointsRequired,
    String? description,
    @Default(true) bool active,
    required DateTime createdAt,
    @Default(false) bool synced,
  }) = _Reward;

  factory Reward.fromJson(Map<String, dynamic> json) =>
      _$RewardFromJson(json);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'points_required': pointsRequired,
        'description': description,
        'active': active ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'synced': synced ? 1 : 0,
      };
}

Reward rewardFromMap(Map<String, dynamic> map) => Reward(
      id: map['id'] as String,
      name: map['name'] as String,
      pointsRequired: map['points_required'] as int,
      description: map['description'] as String?,
      active: (map['active'] as int? ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      synced: (map['synced'] as int? ?? 0) == 1,
    );
