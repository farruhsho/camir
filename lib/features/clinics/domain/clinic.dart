import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/auth/clinic_types.dart';

/// Клиника-арендатор (tenant) мульти-клиничной системы «Цадмир» — документ
/// коллекции Firestore `clinics/{id}`.
///
/// Простой immutable-класс с [fromMap] (по образцу `StaffMember`/`Patient`).
/// Ключи документа — snake_case. Реестром клиник управляет ТОЛЬКО платформенный
/// администратор; операционные данные каждой клиники изолируются полем
/// `clinic_id` во всех прочих коллекциях (см. `core/auth/clinic_scope.dart`).
/// Id документа `clinics/{id}` — это и есть значение `clinic_id` данных клиники.
///
/// Мульти-профильность: у клиники есть [type] (профиль — гематология/ЛОР/…),
/// [subtitle] (специальность под названием в сайдбаре) и [modules] — набор
/// включённых модулей (функций), по которому app_shell строит навигацию.
class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.type,
    required this.subtitle,
    required this.modules,
    this.active = true,
    this.createdAt,
  });

  /// Id документа `clinics/{id}` — он же `clinic_id` в данных этой клиники.
  final String id;
  final String name;

  /// Ключ профиля клиники (см. `kClinicTypes`), например `hematology`.
  final String type;

  /// Подзаголовок (специальность) в сайдбаре, например «Гематологический центр».
  final String subtitle;

  /// Включённые модули (ключи `kMod*`). Навигация показывает ТОЛЬКО их.
  final Set<String> modules;

  /// Активна ли клиника. Неактивную можно временно «заморозить» без удаления
  /// (данные сохраняются, но работа в ней приостановлена).
  final bool active;

  final DateTime? createdAt;

  /// Справочный профиль клиники (метка, шаблон модулей и т.п.).
  ClinicType get typeInfo => clinicTypeFor(type);

  factory Clinic.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    // Back-compat: клиники, заведённые ДО появления профилей (`default`,
    // `clinic-b`), не имеют полей type/subtitle/modules — подставляем
    // гематологию (исторический профиль «Цадмир») и её шаблон модулей.
    final typeInfo = clinicTypeFor(map['type']?.toString());
    final rawSubtitle = map['subtitle']?.toString();
    final rawModules = map['modules'];

    return Clinic(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: typeInfo.key,
      subtitle: (rawSubtitle == null || rawSubtitle.trim().isEmpty)
          ? typeInfo.subtitle
          : rawSubtitle,
      modules: rawModules is List
          ? rawModules.map((e) => e.toString()).toSet()
          : typeInfo.modules,
      // Отсутствие поля трактуем как «активна» (клиника по умолчанию, заведённая
      // при миграции, могла не получить явный флаг).
      active: map['active'] != false,
      createdAt: readTs(map['created_at']),
    );
  }
}
