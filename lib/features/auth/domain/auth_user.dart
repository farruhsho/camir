import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';
part 'auth_user.g.dart';

/// The authenticated staff member (mirrors `GET /auth/me`).
@freezed
abstract class AuthUser with _$AuthUser {
  const AuthUser._();

  const factory AuthUser({
    required String id,
    required String email,
    required String fullName,
    @Default(false) bool isSuperuser,
    String? branchId,
    String? cabinet,
    @Default(<String>[]) List<String> permissions,
    @Default(<String>[]) List<String> roles,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, dynamic> json) => _$AuthUserFromJson(json);

  bool can(String permission) => isSuperuser || permissions.contains(permission);
}
