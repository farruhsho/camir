import 'package:cloud_firestore/cloud_firestore.dart';

/// Клиника-арендатор (tenant) мульти-клиничной системы «Цадмир» — документ
/// коллекции Firestore `clinics/{id}`.
///
/// Простой immutable-класс с [fromMap] (по образцу `StaffMember`/`Patient`).
/// Ключи документа — snake_case. Реестром клиник управляет ТОЛЬКО платформенный
/// администратор; операционные данные каждой клиники изолируются полем
/// `clinic_id` во всех прочих коллекциях (см. `core/auth/clinic_scope.dart`).
/// Id документа `clinics/{id}` — это и есть значение `clinic_id` данных клиники.
class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    this.active = true,
    this.createdAt,
  });

  /// Id документа `clinics/{id}` — он же `clinic_id` в данных этой клиники.
  final String id;
  final String name;

  /// Активна ли клиника. Неактивную можно временно «заморозить» без удаления
  /// (данные сохраняются, но работа в ней приостановлена).
  final bool active;

  final DateTime? createdAt;

  factory Clinic.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return Clinic(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      // Отсутствие поля трактуем как «активна» (клиника по умолчанию, заведённая
      // при миграции, могла не получить явный флаг).
      active: map['active'] != false,
      createdAt: readTs(map['created_at']),
    );
  }
}
