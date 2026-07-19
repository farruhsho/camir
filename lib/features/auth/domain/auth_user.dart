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
    // Мульти-клиничность: активная клиника сотрудника (`null` — не назначена) и
    // признак платформенного администратора (управление клиниками).
    String? clinicId,
    @Default(false) bool isPlatformAdmin,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      _$AuthUserFromJson(json);

  /// Управление клиниками — ТОЛЬКО у платформенного администратора (право
  /// `clinics.manage` выдаётся динамически лишь ему). Обычный супер-админ
  /// клиники под общий флаг `isSuperuser` его НЕ получает — иначе пункт
  /// «Клиники» был бы виден клиническому суперу как «мёртвый».
  bool can(String permission) => permission == 'clinics.manage'
      ? permissions.contains(permission)
      : (isSuperuser || permissions.contains(permission));
}
