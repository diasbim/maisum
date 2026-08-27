import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_session.freezed.dart';
part 'auth_session.g.dart';

enum AuthActor { merchant, customer }

@freezed
class AuthSession with _$AuthSession {
  const AuthSession._();

  const factory AuthSession({
    required String userId,
    required String phone,
    required DateTime expiresAt,
    @Default('') String token,
    String? appUserId,
    String? merchantId,
    @Default('Minha Loja') String merchantName,
    @Default('TRIAL') String subscriptionStatus,
    String? refreshToken,
    String? deviceId,
    String? firebaseUid,
    @Default(AuthActor.merchant) AuthActor actor,
  }) = _AuthSession;

  factory AuthSession.fromJson(Map<String, dynamic> json) =>
      _$AuthSessionFromJson(json);

  bool get isValid => expiresAt.isAfter(DateTime.now());
  bool get isFirebaseSession => firebaseUid != null && firebaseUid!.isNotEmpty;
  bool get isCustomer => actor == AuthActor.customer;
  String get resolvedAppUserId => appUserId ?? userId;
  String get resolvedMerchantId =>
      isCustomer ? '' : merchantId ?? firebaseUid ?? userId;
}
