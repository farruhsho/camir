import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/koz_widgets.dart' show BadgeKind;
import '../../patients/domain/patient.dart' show kReferralLabels;

/// Статусы визита (очередь клиники «Цадмир»).
const String kVisitWaiting = 'waiting';
const String kVisitInProgress = 'in_progress';
const String kVisitCompleted = 'completed';
const String kVisitCancelled = 'cancelled';

/// Статус визита → русская подпись.
const Map<String, String> kVisitStatusLabels = <String, String>{
  kVisitWaiting: 'Ожидает',
  kVisitInProgress: 'На приёме',
  kVisitCompleted: 'Завершён',
  kVisitCancelled: 'Отменён',
};

/// Статус → семантический цвет [StatusBadge] (см. [BadgeKind]).
const Map<String, BadgeKind> kVisitStatusKind = <String, BadgeKind>{
  kVisitWaiting: BadgeKind.warning,
  kVisitInProgress: BadgeKind.info,
  kVisitCompleted: BadgeKind.success,
  kVisitCancelled: BadgeKind.danger,
};

/// Разрешённые переходы статусов очереди. `completed` — терминальный
/// (переходов нет). Проверяется и в репозитории (`setStatus`), и в UI (кнопки
/// действий показываются только для допустимых переходов).
const Map<String, List<String>> kVisitAllowedTransitions =
    <String, List<String>>{
      kVisitWaiting: <String>[kVisitInProgress, kVisitCancelled],
      kVisitInProgress: <String>[kVisitCompleted, kVisitWaiting],
      kVisitCancelled: <String>[kVisitWaiting],
      kVisitCompleted: <String>[],
    };

/// Визит пациента в очереди клиники «Цадмир».
///
/// Простой immutable-класс с [fromMap]/[toMap] под коллекцию Firestore
/// `visits` (по образцу [Patient]). Ключи документа — snake_case. Часть полей
/// пациента денормализована в визит (`patient_name`, `mrn`, `birth_year`,
/// `phone`, `referral`), чтобы доска очереди рисовалась без доп. чтения карты.
class Visit {
  const Visit({
    required this.id,
    this.patientId,
    required this.mrn,
    required this.patientName,
    required this.birthYear,
    this.phone,
    this.referral,
    required this.status,
    required this.queueNumber,
    required this.day,
    this.note,
    this.createdBy,
    this.createdAt,
    this.calledAt,
    this.completedAt,
    this.cancelledAt,
  });

  final String id;

  /// id карты пациента (`patients/{id}`); может быть пустым для карт-заглушек.
  final String? patientId;

  /// № карты пациента (денормализовано из [Patient.mrn]).
  final String mrn;

  /// ФИО пациента одной строкой (денормализовано).
  final String patientName;
  final int birthYear;
  final String? phone;

  /// Направление: [kReferralFibroscan] / [kReferralAnalyses] / [kReferralConsult].
  final String? referral;

  /// Один из [kVisitWaiting] / [kVisitInProgress] / [kVisitCompleted] /
  /// [kVisitCancelled].
  final String status;

  /// Посуточный номер в очереди (счётчик `counters/queue-YYYY-MM-DD`).
  final int queueNumber;

  /// Дата визита в ISO `YYYY-MM-DD`.
  final String day;

  /// Заметка (напр. консультация из регистратуры).
  final String? note;

  final String? createdBy;
  final DateTime? createdAt;

  /// Когда пациента вызвали (`waiting` → `in_progress`).
  final DateTime? calledAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// Русская подпись статуса.
  String get statusLabel => kVisitStatusLabels[status] ?? status;

  /// Семантический цвет статуса для [StatusBadge].
  BadgeKind get statusKind => kVisitStatusKind[status] ?? BadgeKind.neutral;

  /// Русская подпись направления (или `null`).
  String? get referralLabel =>
      referral == null ? null : (kReferralLabels[referral] ?? referral);

  /// Инициалы для аватара (первые буквы двух первых слов ФИО).
  String get initials {
    final parts = patientName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '—';
    final list = parts.toList();
    final a = list[0][0];
    final b = list.length > 1 ? list[1][0] : '';
    return '$a$b'.toUpperCase();
  }

  /// Допустим ли переход текущего статуса в [newStatus].
  bool canTransitionTo(String newStatus) =>
      (kVisitAllowedTransitions[status] ?? const <String>[]).contains(
        newStatus,
      );

  factory Visit.fromMap(Map<String, dynamic> map) {
    DateTime? readTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    int readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Visit(
      id: map['id']?.toString() ?? '',
      patientId: str(map['patient_id']),
      mrn: map['mrn']?.toString() ?? '',
      patientName: map['patient_name']?.toString() ?? '',
      birthYear: readInt(map['birth_year']),
      phone: str(map['phone']),
      referral: str(map['referral']),
      status: str(map['status']) ?? kVisitWaiting,
      queueNumber: readInt(map['queue_number']),
      day: map['day']?.toString() ?? '',
      note: str(map['note']),
      createdBy: str(map['created_by']),
      createdAt: readTs(map['created_at']),
      calledAt: readTs(map['called_at']),
      completedAt: readTs(map['completed_at']),
      cancelledAt: readTs(map['cancelled_at']),
    );
  }

  /// Поля для записи в Firestore (без `id`/серверных таймстампов — их ставит
  /// репозиторий). Пустые необязательные поля опускаются.
  Map<String, dynamic> toMap() => <String, dynamic>{
    if (patientId != null && patientId!.isNotEmpty) 'patient_id': patientId,
    'mrn': mrn,
    'patient_name': patientName,
    'birth_year': birthYear,
    if (phone != null && phone!.isNotEmpty) 'phone': phone,
    if (referral != null && referral!.isNotEmpty) 'referral': referral,
    'status': status,
    'queue_number': queueNumber,
    'day': day,
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}
