// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sale.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Sale _$SaleFromJson(Map<String, dynamic> json) {
  return _Sale.fromJson(json);
}

/// @nodoc
mixin _$Sale {
  String get id => throw _privateConstructorUsedError;
  String get customerId => throw _privateConstructorUsedError;
  double get amount => throw _privateConstructorUsedError;
  int get points => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  SaleConfirmationStatus get confirmationStatus =>
      throw _privateConstructorUsedError;
  int? get confirmedPoints => throw _privateConstructorUsedError;
  DateTime? get confirmedAt => throw _privateConstructorUsedError;
  String? get confirmationErrorCode => throw _privateConstructorUsedError;
  int? get loyaltyPolicyVersion => throw _privateConstructorUsedError;
  SaleCancellationStatus get cancellationStatus =>
      throw _privateConstructorUsedError;
  DateTime? get cancelledAt => throw _privateConstructorUsedError;
  String? get cancelledByAppUserId => throw _privateConstructorUsedError;
  String? get cancellationReason => throw _privateConstructorUsedError;
  String? get replacementSaleId => throw _privateConstructorUsedError;

  /// What the sale was before a referral discount, and what the code did.
  ///
  /// All nullable and all absent on an ordinary sale, which is the point: a
  /// sale with no code reads and writes exactly as it did before these
  /// existed, in JSON and in SQLite alike. Every one of them is written by
  /// the server — `firestore.rules` refuses a client that tries — so they
  /// arrive by projection and are never sent back up.
  @JsonKey(
      fromJson: _referralBenefitTypeFromJson,
      toJson: _referralBenefitTypeToJson)
  ReferralBenefitType? get referralBenefitType =>
      throw _privateConstructorUsedError;
  double? get grossAmount => throw _privateConstructorUsedError;
  double? get referralBenefitValue => throw _privateConstructorUsedError;
  double? get referralBenefitAmount => throw _privateConstructorUsedError;
  String? get affiliateCodeId => throw _privateConstructorUsedError;
  @JsonKey(
      fromJson: _referralSaleStatusFromJson, toJson: _referralSaleStatusToJson)
  ReferralSaleStatus? get referralStatus => throw _privateConstructorUsedError;
  List<SaleItem> get items => throw _privateConstructorUsedError;
  bool get synced => throw _privateConstructorUsedError;

  /// Serializes this Sale to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Sale
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SaleCopyWith<Sale> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SaleCopyWith<$Res> {
  factory $SaleCopyWith(Sale value, $Res Function(Sale) then) =
      _$SaleCopyWithImpl<$Res, Sale>;
  @useResult
  $Res call(
      {String id,
      String customerId,
      double amount,
      int points,
      DateTime createdAt,
      DateTime? updatedAt,
      SaleConfirmationStatus confirmationStatus,
      int? confirmedPoints,
      DateTime? confirmedAt,
      String? confirmationErrorCode,
      int? loyaltyPolicyVersion,
      SaleCancellationStatus cancellationStatus,
      DateTime? cancelledAt,
      String? cancelledByAppUserId,
      String? cancellationReason,
      String? replacementSaleId,
      @JsonKey(
          fromJson: _referralBenefitTypeFromJson,
          toJson: _referralBenefitTypeToJson)
      ReferralBenefitType? referralBenefitType,
      double? grossAmount,
      double? referralBenefitValue,
      double? referralBenefitAmount,
      String? affiliateCodeId,
      @JsonKey(
          fromJson: _referralSaleStatusFromJson,
          toJson: _referralSaleStatusToJson)
      ReferralSaleStatus? referralStatus,
      List<SaleItem> items,
      bool synced});
}

/// @nodoc
class _$SaleCopyWithImpl<$Res, $Val extends Sale>
    implements $SaleCopyWith<$Res> {
  _$SaleCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Sale
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? amount = null,
    Object? points = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? confirmationStatus = null,
    Object? confirmedPoints = freezed,
    Object? confirmedAt = freezed,
    Object? confirmationErrorCode = freezed,
    Object? loyaltyPolicyVersion = freezed,
    Object? cancellationStatus = null,
    Object? cancelledAt = freezed,
    Object? cancelledByAppUserId = freezed,
    Object? cancellationReason = freezed,
    Object? replacementSaleId = freezed,
    Object? referralBenefitType = freezed,
    Object? grossAmount = freezed,
    Object? referralBenefitValue = freezed,
    Object? referralBenefitAmount = freezed,
    Object? affiliateCodeId = freezed,
    Object? referralStatus = freezed,
    Object? items = null,
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
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      confirmationStatus: null == confirmationStatus
          ? _value.confirmationStatus
          : confirmationStatus // ignore: cast_nullable_to_non_nullable
              as SaleConfirmationStatus,
      confirmedPoints: freezed == confirmedPoints
          ? _value.confirmedPoints
          : confirmedPoints // ignore: cast_nullable_to_non_nullable
              as int?,
      confirmedAt: freezed == confirmedAt
          ? _value.confirmedAt
          : confirmedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      confirmationErrorCode: freezed == confirmationErrorCode
          ? _value.confirmationErrorCode
          : confirmationErrorCode // ignore: cast_nullable_to_non_nullable
              as String?,
      loyaltyPolicyVersion: freezed == loyaltyPolicyVersion
          ? _value.loyaltyPolicyVersion
          : loyaltyPolicyVersion // ignore: cast_nullable_to_non_nullable
              as int?,
      cancellationStatus: null == cancellationStatus
          ? _value.cancellationStatus
          : cancellationStatus // ignore: cast_nullable_to_non_nullable
              as SaleCancellationStatus,
      cancelledAt: freezed == cancelledAt
          ? _value.cancelledAt
          : cancelledAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cancelledByAppUserId: freezed == cancelledByAppUserId
          ? _value.cancelledByAppUserId
          : cancelledByAppUserId // ignore: cast_nullable_to_non_nullable
              as String?,
      cancellationReason: freezed == cancellationReason
          ? _value.cancellationReason
          : cancellationReason // ignore: cast_nullable_to_non_nullable
              as String?,
      replacementSaleId: freezed == replacementSaleId
          ? _value.replacementSaleId
          : replacementSaleId // ignore: cast_nullable_to_non_nullable
              as String?,
      referralBenefitType: freezed == referralBenefitType
          ? _value.referralBenefitType
          : referralBenefitType // ignore: cast_nullable_to_non_nullable
              as ReferralBenefitType?,
      grossAmount: freezed == grossAmount
          ? _value.grossAmount
          : grossAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      referralBenefitValue: freezed == referralBenefitValue
          ? _value.referralBenefitValue
          : referralBenefitValue // ignore: cast_nullable_to_non_nullable
              as double?,
      referralBenefitAmount: freezed == referralBenefitAmount
          ? _value.referralBenefitAmount
          : referralBenefitAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      affiliateCodeId: freezed == affiliateCodeId
          ? _value.affiliateCodeId
          : affiliateCodeId // ignore: cast_nullable_to_non_nullable
              as String?,
      referralStatus: freezed == referralStatus
          ? _value.referralStatus
          : referralStatus // ignore: cast_nullable_to_non_nullable
              as ReferralSaleStatus?,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<SaleItem>,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SaleImplCopyWith<$Res> implements $SaleCopyWith<$Res> {
  factory _$$SaleImplCopyWith(
          _$SaleImpl value, $Res Function(_$SaleImpl) then) =
      __$$SaleImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String customerId,
      double amount,
      int points,
      DateTime createdAt,
      DateTime? updatedAt,
      SaleConfirmationStatus confirmationStatus,
      int? confirmedPoints,
      DateTime? confirmedAt,
      String? confirmationErrorCode,
      int? loyaltyPolicyVersion,
      SaleCancellationStatus cancellationStatus,
      DateTime? cancelledAt,
      String? cancelledByAppUserId,
      String? cancellationReason,
      String? replacementSaleId,
      @JsonKey(
          fromJson: _referralBenefitTypeFromJson,
          toJson: _referralBenefitTypeToJson)
      ReferralBenefitType? referralBenefitType,
      double? grossAmount,
      double? referralBenefitValue,
      double? referralBenefitAmount,
      String? affiliateCodeId,
      @JsonKey(
          fromJson: _referralSaleStatusFromJson,
          toJson: _referralSaleStatusToJson)
      ReferralSaleStatus? referralStatus,
      List<SaleItem> items,
      bool synced});
}

/// @nodoc
class __$$SaleImplCopyWithImpl<$Res>
    extends _$SaleCopyWithImpl<$Res, _$SaleImpl>
    implements _$$SaleImplCopyWith<$Res> {
  __$$SaleImplCopyWithImpl(_$SaleImpl _value, $Res Function(_$SaleImpl) _then)
      : super(_value, _then);

  /// Create a copy of Sale
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? customerId = null,
    Object? amount = null,
    Object? points = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? confirmationStatus = null,
    Object? confirmedPoints = freezed,
    Object? confirmedAt = freezed,
    Object? confirmationErrorCode = freezed,
    Object? loyaltyPolicyVersion = freezed,
    Object? cancellationStatus = null,
    Object? cancelledAt = freezed,
    Object? cancelledByAppUserId = freezed,
    Object? cancellationReason = freezed,
    Object? replacementSaleId = freezed,
    Object? referralBenefitType = freezed,
    Object? grossAmount = freezed,
    Object? referralBenefitValue = freezed,
    Object? referralBenefitAmount = freezed,
    Object? affiliateCodeId = freezed,
    Object? referralStatus = freezed,
    Object? items = null,
    Object? synced = null,
  }) {
    return _then(_$SaleImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      customerId: null == customerId
          ? _value.customerId
          : customerId // ignore: cast_nullable_to_non_nullable
              as String,
      amount: null == amount
          ? _value.amount
          : amount // ignore: cast_nullable_to_non_nullable
              as double,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      confirmationStatus: null == confirmationStatus
          ? _value.confirmationStatus
          : confirmationStatus // ignore: cast_nullable_to_non_nullable
              as SaleConfirmationStatus,
      confirmedPoints: freezed == confirmedPoints
          ? _value.confirmedPoints
          : confirmedPoints // ignore: cast_nullable_to_non_nullable
              as int?,
      confirmedAt: freezed == confirmedAt
          ? _value.confirmedAt
          : confirmedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      confirmationErrorCode: freezed == confirmationErrorCode
          ? _value.confirmationErrorCode
          : confirmationErrorCode // ignore: cast_nullable_to_non_nullable
              as String?,
      loyaltyPolicyVersion: freezed == loyaltyPolicyVersion
          ? _value.loyaltyPolicyVersion
          : loyaltyPolicyVersion // ignore: cast_nullable_to_non_nullable
              as int?,
      cancellationStatus: null == cancellationStatus
          ? _value.cancellationStatus
          : cancellationStatus // ignore: cast_nullable_to_non_nullable
              as SaleCancellationStatus,
      cancelledAt: freezed == cancelledAt
          ? _value.cancelledAt
          : cancelledAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cancelledByAppUserId: freezed == cancelledByAppUserId
          ? _value.cancelledByAppUserId
          : cancelledByAppUserId // ignore: cast_nullable_to_non_nullable
              as String?,
      cancellationReason: freezed == cancellationReason
          ? _value.cancellationReason
          : cancellationReason // ignore: cast_nullable_to_non_nullable
              as String?,
      replacementSaleId: freezed == replacementSaleId
          ? _value.replacementSaleId
          : replacementSaleId // ignore: cast_nullable_to_non_nullable
              as String?,
      referralBenefitType: freezed == referralBenefitType
          ? _value.referralBenefitType
          : referralBenefitType // ignore: cast_nullable_to_non_nullable
              as ReferralBenefitType?,
      grossAmount: freezed == grossAmount
          ? _value.grossAmount
          : grossAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      referralBenefitValue: freezed == referralBenefitValue
          ? _value.referralBenefitValue
          : referralBenefitValue // ignore: cast_nullable_to_non_nullable
              as double?,
      referralBenefitAmount: freezed == referralBenefitAmount
          ? _value.referralBenefitAmount
          : referralBenefitAmount // ignore: cast_nullable_to_non_nullable
              as double?,
      affiliateCodeId: freezed == affiliateCodeId
          ? _value.affiliateCodeId
          : affiliateCodeId // ignore: cast_nullable_to_non_nullable
              as String?,
      referralStatus: freezed == referralStatus
          ? _value.referralStatus
          : referralStatus // ignore: cast_nullable_to_non_nullable
              as ReferralSaleStatus?,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<SaleItem>,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SaleImpl extends _Sale {
  const _$SaleImpl(
      {required this.id,
      required this.customerId,
      required this.amount,
      required this.points,
      required this.createdAt,
      this.updatedAt,
      this.confirmationStatus = SaleConfirmationStatus.pending,
      this.confirmedPoints,
      this.confirmedAt,
      this.confirmationErrorCode,
      this.loyaltyPolicyVersion,
      this.cancellationStatus = SaleCancellationStatus.active,
      this.cancelledAt,
      this.cancelledByAppUserId,
      this.cancellationReason,
      this.replacementSaleId,
      @JsonKey(
          fromJson: _referralBenefitTypeFromJson,
          toJson: _referralBenefitTypeToJson)
      this.referralBenefitType,
      this.grossAmount,
      this.referralBenefitValue,
      this.referralBenefitAmount,
      this.affiliateCodeId,
      @JsonKey(
          fromJson: _referralSaleStatusFromJson,
          toJson: _referralSaleStatusToJson)
      this.referralStatus,
      final List<SaleItem> items = const <SaleItem>[],
      this.synced = false})
      : _items = items,
        super._();

  factory _$SaleImpl.fromJson(Map<String, dynamic> json) =>
      _$$SaleImplFromJson(json);

  @override
  final String id;
  @override
  final String customerId;
  @override
  final double amount;
  @override
  final int points;
  @override
  final DateTime createdAt;
  @override
  final DateTime? updatedAt;
  @override
  @JsonKey()
  final SaleConfirmationStatus confirmationStatus;
  @override
  final int? confirmedPoints;
  @override
  final DateTime? confirmedAt;
  @override
  final String? confirmationErrorCode;
  @override
  final int? loyaltyPolicyVersion;
  @override
  @JsonKey()
  final SaleCancellationStatus cancellationStatus;
  @override
  final DateTime? cancelledAt;
  @override
  final String? cancelledByAppUserId;
  @override
  final String? cancellationReason;
  @override
  final String? replacementSaleId;

  /// What the sale was before a referral discount, and what the code did.
  ///
  /// All nullable and all absent on an ordinary sale, which is the point: a
  /// sale with no code reads and writes exactly as it did before these
  /// existed, in JSON and in SQLite alike. Every one of them is written by
  /// the server — `firestore.rules` refuses a client that tries — so they
  /// arrive by projection and are never sent back up.
  @override
  @JsonKey(
      fromJson: _referralBenefitTypeFromJson,
      toJson: _referralBenefitTypeToJson)
  final ReferralBenefitType? referralBenefitType;
  @override
  final double? grossAmount;
  @override
  final double? referralBenefitValue;
  @override
  final double? referralBenefitAmount;
  @override
  final String? affiliateCodeId;
  @override
  @JsonKey(
      fromJson: _referralSaleStatusFromJson, toJson: _referralSaleStatusToJson)
  final ReferralSaleStatus? referralStatus;
  final List<SaleItem> _items;
  @override
  @JsonKey()
  List<SaleItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  @JsonKey()
  final bool synced;

  @override
  String toString() {
    return 'Sale(id: $id, customerId: $customerId, amount: $amount, points: $points, createdAt: $createdAt, updatedAt: $updatedAt, confirmationStatus: $confirmationStatus, confirmedPoints: $confirmedPoints, confirmedAt: $confirmedAt, confirmationErrorCode: $confirmationErrorCode, loyaltyPolicyVersion: $loyaltyPolicyVersion, cancellationStatus: $cancellationStatus, cancelledAt: $cancelledAt, cancelledByAppUserId: $cancelledByAppUserId, cancellationReason: $cancellationReason, replacementSaleId: $replacementSaleId, referralBenefitType: $referralBenefitType, grossAmount: $grossAmount, referralBenefitValue: $referralBenefitValue, referralBenefitAmount: $referralBenefitAmount, affiliateCodeId: $affiliateCodeId, referralStatus: $referralStatus, items: $items, synced: $synced)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SaleImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.customerId, customerId) ||
                other.customerId == customerId) &&
            (identical(other.amount, amount) || other.amount == amount) &&
            (identical(other.points, points) || other.points == points) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.confirmationStatus, confirmationStatus) ||
                other.confirmationStatus == confirmationStatus) &&
            (identical(other.confirmedPoints, confirmedPoints) ||
                other.confirmedPoints == confirmedPoints) &&
            (identical(other.confirmedAt, confirmedAt) ||
                other.confirmedAt == confirmedAt) &&
            (identical(other.confirmationErrorCode, confirmationErrorCode) ||
                other.confirmationErrorCode == confirmationErrorCode) &&
            (identical(other.loyaltyPolicyVersion, loyaltyPolicyVersion) ||
                other.loyaltyPolicyVersion == loyaltyPolicyVersion) &&
            (identical(other.cancellationStatus, cancellationStatus) ||
                other.cancellationStatus == cancellationStatus) &&
            (identical(other.cancelledAt, cancelledAt) ||
                other.cancelledAt == cancelledAt) &&
            (identical(other.cancelledByAppUserId, cancelledByAppUserId) ||
                other.cancelledByAppUserId == cancelledByAppUserId) &&
            (identical(other.cancellationReason, cancellationReason) ||
                other.cancellationReason == cancellationReason) &&
            (identical(other.replacementSaleId, replacementSaleId) ||
                other.replacementSaleId == replacementSaleId) &&
            (identical(other.referralBenefitType, referralBenefitType) ||
                other.referralBenefitType == referralBenefitType) &&
            (identical(other.grossAmount, grossAmount) ||
                other.grossAmount == grossAmount) &&
            (identical(other.referralBenefitValue, referralBenefitValue) ||
                other.referralBenefitValue == referralBenefitValue) &&
            (identical(other.referralBenefitAmount, referralBenefitAmount) ||
                other.referralBenefitAmount == referralBenefitAmount) &&
            (identical(other.affiliateCodeId, affiliateCodeId) ||
                other.affiliateCodeId == affiliateCodeId) &&
            (identical(other.referralStatus, referralStatus) ||
                other.referralStatus == referralStatus) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.synced, synced) || other.synced == synced));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        customerId,
        amount,
        points,
        createdAt,
        updatedAt,
        confirmationStatus,
        confirmedPoints,
        confirmedAt,
        confirmationErrorCode,
        loyaltyPolicyVersion,
        cancellationStatus,
        cancelledAt,
        cancelledByAppUserId,
        cancellationReason,
        replacementSaleId,
        referralBenefitType,
        grossAmount,
        referralBenefitValue,
        referralBenefitAmount,
        affiliateCodeId,
        referralStatus,
        const DeepCollectionEquality().hash(_items),
        synced
      ]);

  /// Create a copy of Sale
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SaleImplCopyWith<_$SaleImpl> get copyWith =>
      __$$SaleImplCopyWithImpl<_$SaleImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SaleImplToJson(
      this,
    );
  }
}

abstract class _Sale extends Sale {
  const factory _Sale(
      {required final String id,
      required final String customerId,
      required final double amount,
      required final int points,
      required final DateTime createdAt,
      final DateTime? updatedAt,
      final SaleConfirmationStatus confirmationStatus,
      final int? confirmedPoints,
      final DateTime? confirmedAt,
      final String? confirmationErrorCode,
      final int? loyaltyPolicyVersion,
      final SaleCancellationStatus cancellationStatus,
      final DateTime? cancelledAt,
      final String? cancelledByAppUserId,
      final String? cancellationReason,
      final String? replacementSaleId,
      @JsonKey(
          fromJson: _referralBenefitTypeFromJson,
          toJson: _referralBenefitTypeToJson)
      final ReferralBenefitType? referralBenefitType,
      final double? grossAmount,
      final double? referralBenefitValue,
      final double? referralBenefitAmount,
      final String? affiliateCodeId,
      @JsonKey(
          fromJson: _referralSaleStatusFromJson,
          toJson: _referralSaleStatusToJson)
      final ReferralSaleStatus? referralStatus,
      final List<SaleItem> items,
      final bool synced}) = _$SaleImpl;
  const _Sale._() : super._();

  factory _Sale.fromJson(Map<String, dynamic> json) = _$SaleImpl.fromJson;

  @override
  String get id;
  @override
  String get customerId;
  @override
  double get amount;
  @override
  int get points;
  @override
  DateTime get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  SaleConfirmationStatus get confirmationStatus;
  @override
  int? get confirmedPoints;
  @override
  DateTime? get confirmedAt;
  @override
  String? get confirmationErrorCode;
  @override
  int? get loyaltyPolicyVersion;
  @override
  SaleCancellationStatus get cancellationStatus;
  @override
  DateTime? get cancelledAt;
  @override
  String? get cancelledByAppUserId;
  @override
  String? get cancellationReason;
  @override
  String? get replacementSaleId;

  /// What the sale was before a referral discount, and what the code did.
  ///
  /// All nullable and all absent on an ordinary sale, which is the point: a
  /// sale with no code reads and writes exactly as it did before these
  /// existed, in JSON and in SQLite alike. Every one of them is written by
  /// the server — `firestore.rules` refuses a client that tries — so they
  /// arrive by projection and are never sent back up.
  @override
  @JsonKey(
      fromJson: _referralBenefitTypeFromJson,
      toJson: _referralBenefitTypeToJson)
  ReferralBenefitType? get referralBenefitType;
  @override
  double? get grossAmount;
  @override
  double? get referralBenefitValue;
  @override
  double? get referralBenefitAmount;
  @override
  String? get affiliateCodeId;
  @override
  @JsonKey(
      fromJson: _referralSaleStatusFromJson, toJson: _referralSaleStatusToJson)
  ReferralSaleStatus? get referralStatus;
  @override
  List<SaleItem> get items;
  @override
  bool get synced;

  /// Create a copy of Sale
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SaleImplCopyWith<_$SaleImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
