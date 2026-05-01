import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_session.freezed.dart';
part 'auth_session.g.dart';

@freezed
class AuthSession with _$AuthSession {
  const AuthSession._();

  const factory AuthSession({
    required String userId,
    required String phone,
    required DateTime expiresAt,
    @Default('') String token,
    String? firebaseUid,
  }) = _AuthSession;

  factory AuthSession.fromJson(Map<String, dynamic> json) =>
      _$AuthSessionFromJson(json);

  bool get isValid => expiresAt.isAfter(DateTime.now());
  bool get isFirebaseSession => firebaseUid != null && firebaseUid!.isNotEmpty;
}
