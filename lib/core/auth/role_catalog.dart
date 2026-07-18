/// Каталог ролей персонала «Цадмир» → наборы permission-кодов.
///
/// Единственный источник правды для прав доступа. При входе/регистрации в роль
/// сотрудника (поле `role` в staff/{uid}) раскрывается через [permissionsForRole]
/// в список кодов, которые попадают в `AuthUser.permissions` и проверяются через
/// `AuthUser.can(...)`. Супер-админ прав не перечисляет — ему выдаётся
/// `isSuperuser` (см. [isSuperRole]), что открывает всё.
///
/// Для этапа тестирования оставлены ДВЕ роли: Ресепшен (совмещённый фронт-офис с
/// доступом ко всем модулям) и Супер-админ.
library;

/// Роли-константы (они же значения поля `role` в Firestore staff/{uid}).
const String roleSuperadmin = 'Супер-админ';
const String roleReception = 'Ресепшен';

/// Порядок ролей для выпадающего списка и кнопок быстрого входа.
const List<String> kCadmirRoles = <String>[
  roleReception,
  roleSuperadmin,
];

/// Карта роль → permission-коды. У супер-админа список пуст: полный доступ
/// даётся флагом `isSuperuser`. Ресепшен — совмещённый фронт-офис с доступом
/// ко всем модулям (регистратура, пациенты, склад, анализы, фиброскан).
///
/// ВАЖНО: право `staff.manage` НЕ должно входить ни в одну роль — экран
/// «Сотрудники» намеренно доступен только супер-админу (через `isSuperuser`).
const Map<String, List<String>> kRolePermissions = <String, List<String>>{
  roleSuperadmin: <String>[],
  roleReception: <String>[
    'patients.read',
    'patients.create',
    'patients.update',
    'visits.create',
    'visits.read',
    'visits.update',
    'dashboard.view',
    'inventory.read',
    'inventory.manage',
    'inventory.write_off',
    'analyses.read',
    'analyses.write',
    'fibroscan.read',
    'fibroscan.write',
    'audit.read',
  ],
};

/// Permission-коды для роли. Неизвестная роль → пустой список (нет прав).
List<String> permissionsForRole(String role) =>
    kRolePermissions[role] ?? const <String>[];

/// Является ли роль супер-админской (полный доступ через `isSuperuser`).
bool isSuperRole(String role) => role == roleSuperadmin;
