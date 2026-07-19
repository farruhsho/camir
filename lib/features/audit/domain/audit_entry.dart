import 'package:cloud_firestore/cloud_firestore.dart';

/// Человеко-читаемые подписи действий аудита (значения поля `action`).
/// Ключи совпадают с контрактом [logAudit]:
/// create|update|delete|void|refund|status_change|role_change|disable|archive.
const Map<String, String> kAuditActionLabels = <String, String>{
  'create': 'Создание',
  'update': 'Изменение',
  'delete': 'Удаление',
  'void': 'Аннулирование',
  'refund': 'Возврат',
  'status_change': 'Смена статуса',
  'role_change': 'Смена роли',
  'disable': 'Отключение',
  'archive': 'Архивирование',
};

/// Человеко-читаемые подписи модулей (значения поля `module`). Список
/// best-effort: если модуль не найден — показываем исходное значение как есть.
const Map<String, String> kAuditModuleLabels = <String, String>{
  'patients': 'Пациенты',
  'visits': 'Регистратура',
  'reception': 'Регистратура',
  'queue': 'Очередь',
  'analyses': 'Анализы',
  'analysis_types': 'Виды анализов',
  'fibroscan': 'Фиброскан',
  'fibroscan_refs': 'Нормы фиброскана',
  'inventory': 'Склад',
  'payments': 'Касса',
  'services': 'Прайс-лист',
  'staff': 'Сотрудники',
  'catalog': 'Справочники',
};

/// Одна запись «Журнала изменений» из коллекции Firestore `audit`.
///
/// Простой immutable-класс с [fromMap] (по образцу [Patient]) — без Dio/бэкенда.
/// Ключи документа хранятся в snake_case; журнал append-only (пишется через
/// top-level [logAudit], правка/удаление запрещены правилами Firestore).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.module,
    required this.entity,
    this.entityId,
    required this.action,
    this.summary,
    this.changes = const <String, dynamic>{},
    this.createdBy,
    this.createdByName,
    this.createdAt,
  });

  final String id;

  /// Модуль-источник события (напр. `patients`, `payments`).
  final String module;

  /// Тип сущности внутри модуля (напр. `patient`, `payment`).
  final String entity;

  /// Идентификатор затронутого документа (может отсутствовать).
  final String? entityId;

  /// Действие: create|update|delete|void|refund|status_change|role_change|
  /// disable|archive (см. [kAuditActionLabels]).
  final String action;

  /// Короткое человеко-читаемое описание события.
  final String? summary;

  /// Что именно поменялось (произвольная карта «поле → значение / до→после»).
  final Map<String, dynamic> changes;

  /// UID автора события (`FirebaseAuth` uid).
  final String? createdBy;

  /// Имя автора на момент события (best-effort из staff/{uid}).
  final String? createdByName;

  /// Когда произошло (`created_at` из Firestore).
  final DateTime? createdAt;

  /// Русская подпись действия (или исходное значение, если код неизвестен).
  String get actionLabel => kAuditActionLabels[action] ?? action;

  /// Русская подпись модуля (или исходное значение, если модуль неизвестен).
  String get moduleLabel => kAuditModuleLabels[module] ?? module;

  /// Кто выполнил действие: имя, иначе uid, иначе «—».
  String get whoDisplay {
    final name = createdByName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final by = createdBy?.trim();
    if (by != null && by.isNotEmpty) return by;
    return '—';
  }

  /// Есть ли детали изменений (для показа блока «Изменения» в карточке).
  bool get hasChanges => changes.isNotEmpty;

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Дата-время в формате `ДД.ММ.ГГГГ ЧЧ:ММ` (или «—», если время неизвестно).
  String get whenDisplay {
    final d = createdAt;
    if (d == null) return '—';
    return '${_two(d.day)}.${_two(d.month)}.${d.year.toString().padLeft(4, '0')} '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    Map<String, dynamic> readChanges(dynamic v) {
      if (v is Map) {
        return v.map((k, value) => MapEntry(k.toString(), value));
      }
      return const <String, dynamic>{};
    }

    return AuditEntry(
      id: map['id']?.toString() ?? '',
      module: map['module']?.toString() ?? '',
      entity: map['entity']?.toString() ?? '',
      entityId: str(map['entity_id']),
      action: map['action']?.toString() ?? '',
      summary: str(map['summary']),
      changes: readChanges(map['changes']),
      createdBy: str(map['created_by']),
      createdByName: str(map['created_by_name']),
      createdAt: readTs(map['created_at']),
    );
  }
}
