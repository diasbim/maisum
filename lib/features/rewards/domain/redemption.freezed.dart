// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'redemption.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Redemption _$RedemptionFromJson(Map<String, dynamic> json) {
  return _Redemption.fromJson(json);
}

/// @nodoc
mixin _$Redemption {
  String get id => throw _privateConstructorUsedError;
  String get customerId => throw _privateConstructorUsedError;
  String get rewardId => throw _privateConstructorUsedError;
  int get pointsSpent => throw _privateConstructorUsedError;
  DateTime get redeemedAt => throw _privateConstructorUsedError;
  bool get synced => throw _privateConstructorUsedError;

  /// Serializes this Redemption to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Redemption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RedemptionCopyWith<Redemption> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RedemptionCopyWith<$Res> {
  factory $RedemptionCopyWith(
          Redemption value, $Res Function(Redemption) then) =
      _$RedemptionCopyWithImpl<$Res, Redemption>;
  @useResult
  $Res call(
      {String id,
      String customerId,
      String rewardId,
      int pointsSpent,
      DateTime redeemedAt,
      bool synced});
}

/// @nodoc
class _$RedemptionCopyWithImpl<$Res, $Val extends Redemption>
    implements $RedemptionCopyWith<$Res> {
  _$RedemptionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Redemption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? rewardId = null,
    Object? pointsSpent = null,
    Object? redeemedAt = null,
    Object? synced = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      rewardId: null == rewardId
          ? _value.rewardId
          : rewardId // ignore: cast_nullable_to_non_nullable
              as String,
      pointsSpent: null == pointsSpent
          ? _value.pointsSpent
          : pointsSpent // ignore: cast_nullable_to_non_nullable
              as int,
      redeemedAt: null == redeemedAt
          ? _value.redeemedAt
          : redeemedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RedemptionImplCopyWith<$Res>
    implements $RedemptionCopyWith<$Res> {
  factory _$$RedemptionImplCopyWith(
          _$RedemptionImpl value, $Res Function(_$RedemptionImpl) then) =
      __$$RedemptionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String customerId,
      String rewardId,
      int pointsSpent,
      DateTime redeemedAt,
      bool synced});
}

/// @nodoc
class __$$RedemptionImplCopyWithImpl<$Res>
    extends _$RedemptionCopyWithImpl<$Res, _$RedemptionImpl>
    implements _$$RedemptionImplCopyWith<$Res> {
  __$$RedemptionImplCopyWithImpl(
      _$RedemptionImpl _value, $Res Function(_$RedemptionImpl) _then)
      : super(_value, _then);

  /// Create a copy of Redemption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? rewardId = null,
    Object? pointsSpent = null,
    Object? redeemedAt = null,
    Object? synced = null,
  }) {
    return _then(_$RedemptionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      rewardId: null == rewardId
          ? _value.rewardId
          : rewardId // ignore: cast_nullable_to_non_nullable
              as String,
      pointsSpent: null == pointsSpent
          ? _value.pointsSpent
          : pointsSpent // ignore: cast_nullable_to_non_nullable
              as int,
      redeemedAt: null == redeemedAt
          ? _value.redeemedAt
          : redeemedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RedemptionImpl extends _Redemption {
  const _$RedemptionImpl(
      {required this.id,
      required this.customerId,
      required this.rewardId,
      required this.pointsSpent,
      required this.redeemedAt,
      this.synced = false})
      : super._();

  factory _$RedemptionImpl.fromJson(Map<String, dynamic> json) =>
      _$$RedemptionImplFromJson(json);

  @override
  final String id;
  @override
  final String customerId;
  @override
  final String rewardId;
  @override
  final int pointsSpent;
  @override
  final DateTime redeemedAt;
  @override
  @JsonKey()
  final bool synced;

  @override
  String toString() {
    return 'Redemption(id: $id, customerId: $customerId, rewardId: $rewardId, pointsSpent: $pointsSpent, redeemedAt: $redeemedAt, synced: $synced)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RedemptionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.customerId, customerId) ||
                other.customerId == customerId) &&
            (identical(other.rewardId, rewardId) ||
                other.rewardId == rewardId) &&
            (identical(other.pointsSpent, pointsSpent) ||
                other.pointsSpent == pointsSpent) &&
            (identical(other.redeemedAt, redeemedAt) ||
                other.redeemedAt == redeemedAt) &&
            (identical(other.synced, synced) || other.synced == synced));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, customerId, rewardId, pointsSpent, redeemedAt, synced);

  /// Create a copy of Redemption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RedemptionImplCopyWith<_$RedemptionImpl> get copyWith =>
      __$$RedemptionImplCopyWithImpl<_$RedemptionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RedemptionImplToJson(
      this,
    );
  }
}

abstract class _Redemption extends Redemption {
  const factory _Redemption(
      {required final String id,
      required final String customerId,
      required final String rewardId,
      required final int pointsSpent,
      required final DateTime redeemedAt,
      final bool synced}) = _$RedemptionImpl;
  const _Redemption._() : super._();

  factory _Redemption.fromJson(Map<String, dynamic> json) =
      _$RedemptionImpl.fromJson;

  @override
  String get id;
  @override
  String get customerId;
  @override
  String get rewardId;
  @override
  int get pointsSpent;
  @override
  DateTime get redeemedAt;
  @override
  bool get synced;

  /// Create a copy of Redemption
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RedemptionImplCopyWith<_$RedemptionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
