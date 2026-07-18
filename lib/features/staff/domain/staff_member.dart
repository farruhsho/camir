import 'package:cloud_firestore/cloud_firestore.dart';

/// Сотрудник клиники «Цадмир» — документ коллекции Firestore `staff/{uid}`.
///
/// Простой immutable-класс с [fromMap] (по образцу [Patient]). Ключи документа —
/// snake_case. Права (`permissions`) и супер-флаг (`is_superuser`) хранятся в
/// документе, чтобы по ним гейтили firestore.rules; в UI роль показывается
/// человеко-читаемо ([displayRole]).
class StaffMember {
  const StaffMember({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    this.isSuperuser = false,
    this.disabled = false,
    this.createdAt,
  });

  /// UID Firebase Auth (он же id документа staff).
  final String uid;
  final String email;
  final String fullName;

  /// Роль (значение из `kCadmirRoles`) либо пустая строка — «без роли».
  final String role;

  /// Полный доступ (проставляется только супер-админом/в консоли).
  final bool isSuperuser;

  /// Доступ отозван: такой сотрудник не пускается в приложение (проверка при
  /// входе в `AuthRepository._userFromUid`).
  final bool disabled;

  final DateTime? createdAt;

  /// Инициалы для аватара.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return email.isNotEmpty ? email[0].toUpperCase() : '—';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// Человеко-читаемая роль для списка.
  String get displayRole {
    if (isSuperuser) return 'Супер-админ';
    if (role.isEmpty) return 'Без роли';
    return role;
  }

  factory StaffMember.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return StaffMember(
      uid: map['uid']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
      isSuperuser: map['is_superuser'] == true,
      disabled: map['disabled'] == true,
      createdAt: readTs(map['created_at']),
    );
  }
}
