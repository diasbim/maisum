// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SyncItem _$SyncItemFromJson(Map<String, dynamic> json) {
  return _SyncItem.fromJson(json);
}

/// @nodoc
mixin _$SyncItem {
  String get id => throw _privateConstructorUsedError;
  String get operation => throw _privateConstructorUsedError;
  String get entityType => throw _privateConstructorUsedError;
  String get entityId => throw _privateConstructorUsedError;
  String get payload => throw _privateConstructorUsedError;
  int get retryCount => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this SyncItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyncItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncItemCopyWith<SyncItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncItemCopyWith<$Res> {
  factory $SyncItemCopyWith(SyncItem value, $Res Function(SyncItem) then) =
      _$SyncItemCopyWithImpl<$Res, SyncItem>;
  @useResult
  $Res call(
      {String id,
      String operation,
      String entityType,
      String entityId,
      String payload,
      int retryCount,
      String status,
      DateTime createdAt});
}

/// @nodoc
class _$SyncItemCopyWithImpl<$Res, $Val extends SyncItem>
    implements $SyncItemCopyWith<$Res> {
  _$SyncItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? entityType = null,
    Object? entityId = null,
    Object? payload = null,
    Object? retryCount = null,
    Object? status = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      entityType: null == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String,
      entityId: null == entityId
          ? _value.entityId
          : entityId // ignore: cast_nullable_to_non_nullable
              as String,
      payload: null == payload
          ? _value.payload
          : payload // ignore: cast_nullable_to_non_nullable
              as String,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SyncItemImplCopyWith<$Res>
    implements $SyncItemCopyWith<$Res> {
  factory _$$SyncItemImplCopyWith(
          _$SyncItemImpl value, $Res Function(_$SyncItemImpl) then) =
      __$$SyncItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String operation,
      String entityType,
      String entityId,
      String payload,
      int retryCount,
      String status,
      DateTime createdAt});
}

/// @nodoc
class __$$SyncItemImplCopyWithImpl<$Res>
    extends _$SyncItemCopyWithImpl<$Res, _$SyncItemImpl>
    implements _$$SyncItemImplCopyWith<$Res> {
  __$$SyncItemImplCopyWithImpl(
      _$SyncItemImpl _value, $Res Function(_$SyncItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? entityType = null,
    Object? entityId = null,
    Object? payload = null,
    Object? retryCount = null,
    Object? status = null,
    Object? createdAt = null,
  }) {
    return _then(_$SyncItemImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      entityType: null == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String,
      entityId: null == entityId
          ? _value.entityId
          : entityId // ignore: cast_nullable_to_non_nullable
              as String,
      payload: null == payload
          ? _value.payload
          : payload // ignore: cast_nullable_to_non_nullable
              as String,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SyncItemImpl extends _SyncItem {
  const _$SyncItemImpl(
      {required this.id,
      required this.operation,
      required this.entityType,
      required this.entityId,
      required this.payload,
      this.retryCount = 0,
      this.status = 'pending',
      required this.createdAt})
      : super._();

  factory _$SyncItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyncItemImplFromJson(json);

  @override
  final String id;
  @override
  final String operation;
  @override
  final String entityType;
  @override
  final String entityId;
  @override
  final String payload;
  @override
  @JsonKey()
  final int retryCount;
  @override
  @JsonKey()
  final String status;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'SyncItem(id: $id, operation: $operation, entityType: $entityType, entityId: $entityId, payload: $payload, retryCount: $retryCount, status: $status, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.operation, operation) ||
                other.operation == operation) &&
            (identical(other.entityType, entityType) ||
                other.entityType == entityType) &&
            (identical(other.entityId, entityId) ||
                other.entityId == entityId) &&
            (identical(other.payload, payload) || other.payload == payload) &&
            (identical(other.retryCount, retryCount) ||
                other.retryCount == retryCount) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, operation, entityType,
      entityId, payload, retryCount, status, createdAt);

  /// Create a copy of SyncItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncItemImplCopyWith<_$SyncItemImpl> get copyWith =>
      __$$SyncItemImplCopyWithImpl<_$SyncItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SyncItemImplToJson(
      this,
    );
  }
}

abstract class _SyncItem extends SyncItem {
  const factory _SyncItem(
      {required final String id,
      required final String operation,
      required final String entityType,
      required final String entityId,
      required final String payload,
      final int retryCount,
      final String status,
      required final DateTime createdAt}) = _$SyncItemImpl;
  const _SyncItem._() : super._();

  factory _SyncItem.fromJson(Map<String, dynamic> json) =
      _$SyncItemImpl.fromJson;

  @override
  String get id;
  @override
  String get operation;
  @override
  String get entityType;
  @override
  String get entityId;
  @override
  String get payload;
  @override
  int get retryCount;
  @override
  String get status;
  @override
  DateTime get createdAt;

  /// Create a copy of SyncItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncItemImplCopyWith<_$SyncItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
