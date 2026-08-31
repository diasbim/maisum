// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'customer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Customer _$CustomerFromJson(Map<String, dynamic> json) {
  return _Customer.fromJson(json);
}

/// @nodoc
mixin _$Customer {
  String get id => throw _privateConstructorUsedError;
  String? get merchantId => throw _privateConstructorUsedError;
  String? get canonicalCustomerId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get phone => throw _privateConstructorUsedError;
  int get totalPoints => throw _privateConstructorUsedError;
  int? get confirmedPoints => throw _privateConstructorUsedError;
  CustomerAccountState get accountState => throw _privateConstructorUsedError;
  BusinessCustomerStatus get relationshipStatus =>
      throw _privateConstructorUsedError;
  CustomerLifecycleStage get lifecycleStage =>
      throw _privateConstructorUsedError;
  CustomerRetentionStatus get retentionStatus =>
      throw _privateConstructorUsedError;
  DateTime? get firstVisitAt => throw _privateConstructorUsedError;
  DateTime? get lastVisitAt => throw _privateConstructorUsedError;
  int get totalVisits => throw _privateConstructorUsedError;
  double get totalSpent => throw _privateConstructorUsedError;
  double get averageSpend => throw _privateConstructorUsedError;
  int? get averageVisitIntervalDays => throw _privateConstructorUsedError;
  CustomerConsentStatus get marketingConsentStatus =>
      throw _privateConstructorUsedError;
  CustomerConsentStatus get whatsappConsentStatus =>
      throw _privateConstructorUsedError;
  int get schemaVersion => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  DateTime? get archivedAt => throw _privateConstructorUsedError;
  String? get archivedByAppUserId => throw _privateConstructorUsedError;
  bool get synced => throw _privateConstructorUsedError;

  /// Serializes this Customer to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CustomerCopyWith<Customer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CustomerCopyWith<$Res> {
  factory $CustomerCopyWith(Customer value, $Res Function(Customer) then) =
      _$CustomerCopyWithImpl<$Res, Customer>;
  @useResult
  $Res call(
      {String id,
      String? merchantId,
      String? canonicalCustomerId,
      String name,
      String phone,
      int totalPoints,
      int? confirmedPoints,
      CustomerAccountState accountState,
      BusinessCustomerStatus relationshipStatus,
      CustomerLifecycleStage lifecycleStage,
      CustomerRetentionStatus retentionStatus,
      DateTime? firstVisitAt,
      DateTime? lastVisitAt,
      int totalVisits,
      double totalSpent,
      double averageSpend,
      int? averageVisitIntervalDays,
      CustomerConsentStatus marketingConsentStatus,
      CustomerConsentStatus whatsappConsentStatus,
      int schemaVersion,
      DateTime createdAt,
      DateTime? updatedAt,
      DateTime? archivedAt,
      String? archivedByAppUserId,
      bool synced});
}

/// @nodoc
class _$CustomerCopyWithImpl<$Res, $Val extends Customer>
    implements $CustomerCopyWith<$Res> {
  _$CustomerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? merchantId = freezed,
    Object? canonicalCustomerId = freezed,
    Object? name = null,
    Object? phone = null,
    Object? totalPoints = null,
    Object? confirmedPoints = freezed,
    Object? accountState = null,
    Object? relationshipStatus = null,
    Object? lifecycleStage = null,
    Object? retentionStatus = null,
    Object? firstVisitAt = freezed,
    Object? lastVisitAt = freezed,
    Object? totalVisits = null,
    Object? totalSpent = null,
    Object? averageSpend = null,
    Object? averageVisitIntervalDays = freezed,
    Object? marketingConsentStatus = null,
    Object? whatsappConsentStatus = null,
    Object? schemaVersion = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? archivedAt = freezed,
    Object? archivedByAppUserId = freezed,
    Object? synced = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      merchantId: freezed == merchantId
          ? _value.merchantId
          : merchantId // ignore: cast_nullable_to_non_nullable
              as String?,
      canonicalCustomerId: freezed == canonicalCustomerId
          ? _value.canonicalCustomerId
          : canonicalCustomerId // ignore: cast_nullable_to_non_nullable
              as String?,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      phone: null == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String,
      totalPoints: null == totalPoints
          ? _value.totalPoints
          : totalPoints // ignore: cast_nullable_to_non_nullable
              as int,
      confirmedPoints: freezed == confirmedPoints
          ? _value.confirmedPoints
          : confirmedPoints // ignore: cast_nullable_to_non_nullable
              as int?,
      accountState: null == accountState
          ? _value.accountState
          : accountState // ignore: cast_nullable_to_non_nullable
              as CustomerAccountState,
      relationshipStatus: null == relationshipStatus
          ? _value.relationshipStatus
          : relationshipStatus // ignore: cast_nullable_to_non_nullable
              as BusinessCustomerStatus,
      lifecycleStage: null == lifecycleStage
          ? _value.lifecycleStage
          : lifecycleStage // ignore: cast_nullable_to_non_nullable
              as CustomerLifecycleStage,
      retentionStatus: null == retentionStatus
          ? _value.retentionStatus
          : retentionStatus // ignore: cast_nullable_to_non_nullable
              as CustomerRetentionStatus,
      firstVisitAt: freezed == firstVisitAt
          ? _value.firstVisitAt
          : firstVisitAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastVisitAt: freezed == lastVisitAt
          ? _value.lastVisitAt
          : lastVisitAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVisits: null == totalVisits
          ? _value.totalVisits
          : totalVisits // ignore: cast_nullable_to_non_nullable
              as int,
      totalSpent: null == totalSpent
          ? _value.totalSpent
          : totalSpent // ignore: cast_nullable_to_non_nullable
              as double,
      averageSpend: null == averageSpend
          ? _value.averageSpend
          : averageSpend // ignore: cast_nullable_to_non_nullable
              as double,
      averageVisitIntervalDays: freezed == averageVisitIntervalDays
          ? _value.averageVisitIntervalDays
          : averageVisitIntervalDays // ignore: cast_nullable_to_non_nullable
              as int?,
      marketingConsentStatus: null == marketingConsentStatus
          ? _value.marketingConsentStatus
          : marketingConsentStatus // ignore: cast_nullable_to_non_nullable
              as CustomerConsentStatus,
      whatsappConsentStatus: null == whatsappConsentStatus
          ? _value.whatsappConsentStatus
          : whatsappConsentStatus // ignore: cast_nullable_to_non_nullable
              as CustomerConsentStatus,
      schemaVersion: null == schemaVersion
          ? _value.schemaVersion
          : schemaVersion // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      archivedAt: freezed == archivedAt
          ? _value.archivedAt
          : archivedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      archivedByAppUserId: freezed == archivedByAppUserId
          ? _value.archivedByAppUserId
          : archivedByAppUserId // ignore: cast_nullable_to_non_nullable
              as String?,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CustomerImplCopyWith<$Res>
    implements $CustomerCopyWith<$Res> {
  factory _$$CustomerImplCopyWith(
          _$CustomerImpl value, $Res Function(_$CustomerImpl) then) =
      __$$CustomerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String? merchantId,
      String? canonicalCustomerId,
      String name,
      String phone,
      int totalPoints,
      int? confirmedPoints,
      CustomerAccountState accountState,
      BusinessCustomerStatus relationshipStatus,
      CustomerLifecycleStage lifecycleStage,
      CustomerRetentionStatus retentionStatus,
      DateTime? firstVisitAt,
      DateTime? lastVisitAt,
      int totalVisits,
      double totalSpent,
      double averageSpend,
      int? averageVisitIntervalDays,
      CustomerConsentStatus marketingConsentStatus,
      CustomerConsentStatus whatsappConsentStatus,
      int schemaVersion,
      DateTime createdAt,
      DateTime? updatedAt,
      DateTime? archivedAt,
      String? archivedByAppUserId,
      bool synced});
}

/// @nodoc
class __$$CustomerImplCopyWithImpl<$Res>
    extends _$CustomerCopyWithImpl<$Res, _$CustomerImpl>
    implements _$$CustomerImplCopyWith<$Res> {
  __$$CustomerImplCopyWithImpl(
      _$CustomerImpl _value, $Res Function(_$CustomerImpl) _then)
      : super(_value, _then);

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? merchantId = freezed,
    Object? canonicalCustomerId = freezed,
    Object? name = null,
    Object? phone = null,
    Object? totalPoints = null,
    Object? confirmedPoints = freezed,
    Object? accountState = null,
    Object? relationshipStatus = null,
    Object? lifecycleStage = null,
    Object? retentionStatus = null,
    Object? firstVisitAt = freezed,
    Object? lastVisitAt = freezed,
    Object? totalVisits = null,
    Object? totalSpent = null,
    Object? averageSpend = null,
    Object? averageVisitIntervalDays = freezed,
    Object? marketingConsentStatus = null,
    Object? whatsappConsentStatus = null,
    Object? schemaVersion = null,
    Object? createdAt = null,
    Object? updatedAt = freezed,
    Object? archivedAt = freezed,
    Object? archivedByAppUserId = freezed,
    Object? synced = null,
  }) {
    return _then(_$CustomerImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      merchantId: freezed == merchantId
          ? _value.merchantId
          : merchantId // ignore: cast_nullable_to_non_nullable
              as String?,
      canonicalCustomerId: freezed == canonicalCustomerId
          ? _value.canonicalCustomerId
          : canonicalCustomerId // ignore: cast_nullable_to_non_nullable
              as String?,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      phone: null == phone
          ? _value.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String,
      totalPoints: null == totalPoints
          ? _value.totalPoints
          : totalPoints // ignore: cast_nullable_to_non_nullable
              as int,
      confirmedPoints: freezed == confirmedPoints
          ? _value.confirmedPoints
          : confirmedPoints // ignore: cast_nullable_to_non_nullable
              as int?,
      accountState: null == accountState
          ? _value.accountState
          : accountState // ignore: cast_nullable_to_non_nullable
              as CustomerAccountState,
      relationshipStatus: null == relationshipStatus
          ? _value.relationshipStatus
          : relationshipStatus // ignore: cast_nullable_to_non_nullable
              as BusinessCustomerStatus,
      lifecycleStage: null == lifecycleStage
          ? _value.lifecycleStage
          : lifecycleStage // ignore: cast_nullable_to_non_nullable
              as CustomerLifecycleStage,
      retentionStatus: null == retentionStatus
          ? _value.retentionStatus
          : retentionStatus // ignore: cast_nullable_to_non_nullable
              as CustomerRetentionStatus,
      firstVisitAt: freezed == firstVisitAt
          ? _value.firstVisitAt
          : firstVisitAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastVisitAt: freezed == lastVisitAt
          ? _value.lastVisitAt
          : lastVisitAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVisits: null == totalVisits
          ? _value.totalVisits
          : totalVisits // ignore: cast_nullable_to_non_nullable
              as int,
      totalSpent: null == totalSpent
          ? _value.totalSpent
          : totalSpent // ignore: cast_nullable_to_non_nullable
              as double,
      averageSpend: null == averageSpend
          ? _value.averageSpend
          : averageSpend // ignore: cast_nullable_to_non_nullable
              as double,
      averageVisitIntervalDays: freezed == averageVisitIntervalDays
          ? _value.averageVisitIntervalDays
          : averageVisitIntervalDays // ignore: cast_nullable_to_non_nullable
              as int?,
      marketingConsentStatus: null == marketingConsentStatus
          ? _value.marketingConsentStatus
          : marketingConsentStatus // ignore: cast_nullable_to_non_nullable
              as CustomerConsentStatus,
      whatsappConsentStatus: null == whatsappConsentStatus
          ? _value.whatsappConsentStatus
          : whatsappConsentStatus // ignore: cast_nullable_to_non_nullable
              as CustomerConsentStatus,
      schemaVersion: null == schemaVersion
          ? _value.schemaVersion
          : schemaVersion // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      archivedAt: freezed == archivedAt
          ? _value.archivedAt
          : archivedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      archivedByAppUserId: freezed == archivedByAppUserId
          ? _value.archivedByAppUserId
          : archivedByAppUserId // ignore: cast_nullable_to_non_nullable
              as String?,
      synced: null == synced
          ? _value.synced
          : synced // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CustomerImpl extends _Customer {
  const _$CustomerImpl(
      {required this.id,
      this.merchantId,
      this.canonicalCustomerId,
      required this.name,
      required this.phone,
      this.totalPoints = 0,
      this.confirmedPoints,
      this.accountState = CustomerAccountState.unclaimed,
      this.relationshipStatus = BusinessCustomerStatus.active,
      this.lifecycleStage = CustomerLifecycleStage.newCustomer,
      this.retentionStatus = CustomerRetentionStatus.healthy,
      this.firstVisitAt,
      this.lastVisitAt,
      this.totalVisits = 0,
      this.totalSpent = 0,
      this.averageSpend = 0,
      this.averageVisitIntervalDays,
      this.marketingConsentStatus = CustomerConsentStatus.unknown,
      this.whatsappConsentStatus = CustomerConsentStatus.unknown,
      this.schemaVersion = 1,
      required this.createdAt,
      this.updatedAt,
      this.archivedAt,
      this.archivedByAppUserId,
      this.synced = false})
      : super._();

  factory _$CustomerImpl.fromJson(Map<String, dynamic> json) =>
      _$$CustomerImplFromJson(json);

  @override
  final String id;
  @override
  final String? merchantId;
  @override
  final String? canonicalCustomerId;
  @override
  final String name;
  @override
  final String phone;
  @override
  @JsonKey()
  final int totalPoints;
  @override
  final int? confirmedPoints;
  @override
  @JsonKey()
  final CustomerAccountState accountState;
  @override
  @JsonKey()
  final BusinessCustomerStatus relationshipStatus;
  @override
  @JsonKey()
  final CustomerLifecycleStage lifecycleStage;
  @override
  @JsonKey()
  final CustomerRetentionStatus retentionStatus;
  @override
  final DateTime? firstVisitAt;
  @override
  final DateTime? lastVisitAt;
  @override
  @JsonKey()
  final int totalVisits;
  @override
  @JsonKey()
  final double totalSpent;
  @override
  @JsonKey()
  final double averageSpend;
  @override
  final int? averageVisitIntervalDays;
  @override
  @JsonKey()
  final CustomerConsentStatus marketingConsentStatus;
  @override
  @JsonKey()
  final CustomerConsentStatus whatsappConsentStatus;
  @override
  @JsonKey()
  final int schemaVersion;
  @override
  final DateTime createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final DateTime? archivedAt;
  @override
  final String? archivedByAppUserId;
  @override
  @JsonKey()
  final bool synced;

  @override
  String toString() {
    return 'Customer(id: $id, merchantId: $merchantId, canonicalCustomerId: $canonicalCustomerId, name: $name, phone: $phone, totalPoints: $totalPoints, confirmedPoints: $confirmedPoints, accountState: $accountState, relationshipStatus: $relationshipStatus, lifecycleStage: $lifecycleStage, retentionStatus: $retentionStatus, firstVisitAt: $firstVisitAt, lastVisitAt: $lastVisitAt, totalVisits: $totalVisits, totalSpent: $totalSpent, averageSpend: $averageSpend, averageVisitIntervalDays: $averageVisitIntervalDays, marketingConsentStatus: $marketingConsentStatus, whatsappConsentStatus: $whatsappConsentStatus, schemaVersion: $schemaVersion, createdAt: $createdAt, updatedAt: $updatedAt, archivedAt: $archivedAt, archivedByAppUserId: $archivedByAppUserId, synced: $synced)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CustomerImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.merchantId, merchantId) ||
                other.merchantId == merchantId) &&
            (identical(other.canonicalCustomerId, canonicalCustomerId) ||
                other.canonicalCustomerId == canonicalCustomerId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.totalPoints, totalPoints) ||
                other.totalPoints == totalPoints) &&
            (identical(other.confirmedPoints, confirmedPoints) ||
                other.confirmedPoints == confirmedPoints) &&
            (identical(other.accountState, accountState) ||
                other.accountState == accountState) &&
            (identical(other.relationshipStatus, relationshipStatus) ||
                other.relationshipStatus == relationshipStatus) &&
            (identical(other.lifecycleStage, lifecycleStage) ||
                other.lifecycleStage == lifecycleStage) &&
            (identical(other.retentionStatus, retentionStatus) ||
                other.retentionStatus == retentionStatus) &&
            (identical(other.firstVisitAt, firstVisitAt) ||
                other.firstVisitAt == firstVisitAt) &&
            (identical(other.lastVisitAt, lastVisitAt) ||
                other.lastVisitAt == lastVisitAt) &&
            (identical(other.totalVisits, totalVisits) ||
                other.totalVisits == totalVisits) &&
            (identical(other.totalSpent, totalSpent) ||
                other.totalSpent == totalSpent) &&
            (identical(other.averageSpend, averageSpend) ||
                other.averageSpend == averageSpend) &&
            (identical(
                    other.averageVisitIntervalDays, averageVisitIntervalDays) ||
                other.averageVisitIntervalDays == averageVisitIntervalDays) &&
            (identical(other.marketingConsentStatus, marketingConsentStatus) ||
                other.marketingConsentStatus == marketingConsentStatus) &&
            (identical(other.whatsappConsentStatus, whatsappConsentStatus) ||
                other.whatsappConsentStatus == whatsappConsentStatus) &&
            (identical(other.schemaVersion, schemaVersion) ||
                other.schemaVersion == schemaVersion) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.archivedAt, archivedAt) ||
                other.archivedAt == archivedAt) &&
            (identical(other.archivedByAppUserId, archivedByAppUserId) ||
                other.archivedByAppUserId == archivedByAppUserId) &&
            (identical(other.synced, synced) || other.synced == synced));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        merchantId,
        canonicalCustomerId,
        name,
        phone,
        totalPoints,
        confirmedPoints,
        accountState,
        relationshipStatus,
        lifecycleStage,
        retentionStatus,
        firstVisitAt,
        lastVisitAt,
        totalVisits,
        totalSpent,
        averageSpend,
        averageVisitIntervalDays,
        marketingConsentStatus,
        whatsappConsentStatus,
        schemaVersion,
        createdAt,
        updatedAt,
        archivedAt,
        archivedByAppUserId,
        synced
      ]);

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CustomerImplCopyWith<_$CustomerImpl> get copyWith =>
      __$$CustomerImplCopyWithImpl<_$CustomerImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CustomerImplToJson(
      this,
    );
  }
}

abstract class _Customer extends Customer {
  const factory _Customer(
      {required final String id,
      final String? merchantId,
      final String? canonicalCustomerId,
      required final String name,
      required final String phone,
      final int totalPoints,
      final int? confirmedPoints,
      final CustomerAccountState accountState,
      final BusinessCustomerStatus relationshipStatus,
      final CustomerLifecycleStage lifecycleStage,
      final CustomerRetentionStatus retentionStatus,
      final DateTime? firstVisitAt,
      final DateTime? lastVisitAt,
      final int totalVisits,
      final double totalSpent,
      final double averageSpend,
      final int? averageVisitIntervalDays,
      final CustomerConsentStatus marketingConsentStatus,
      final CustomerConsentStatus whatsappConsentStatus,
      final int schemaVersion,
      required final DateTime createdAt,
      final DateTime? updatedAt,
      final DateTime? archivedAt,
      final String? archivedByAppUserId,
      final bool synced}) = _$CustomerImpl;
  const _Customer._() : super._();

  factory _Customer.fromJson(Map<String, dynamic> json) =
      _$CustomerImpl.fromJson;

  @override
  String get id;
  @override
  String? get merchantId;
  @override
  String? get canonicalCustomerId;
  @override
  String get name;
  @override
  String get phone;
  @override
  int get totalPoints;
  @override
  int? get confirmedPoints;
  @override
  CustomerAccountState get accountState;
  @override
  BusinessCustomerStatus get relationshipStatus;
  @override
  CustomerLifecycleStage get lifecycleStage;
  @override
  CustomerRetentionStatus get retentionStatus;
  @override
  DateTime? get firstVisitAt;
  @override
  DateTime? get lastVisitAt;
  @override
  int get totalVisits;
  @override
  double get totalSpent;
  @override
  double get averageSpend;
  @override
  int? get averageVisitIntervalDays;
  @override
  CustomerConsentStatus get marketingConsentStatus;
  @override
  CustomerConsentStatus get whatsappConsentStatus;
  @override
  int get schemaVersion;
  @override
  DateTime get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  DateTime? get archivedAt;
  @override
  String? get archivedByAppUserId;
  @override
  bool get synced;

  /// Create a copy of Customer
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CustomerImplCopyWith<_$CustomerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
