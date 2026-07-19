import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/koz_widgets.dart' show BadgeKind;
import '../../patients/domain/patient.dart' show kReferralLabels;

/// Статусы приёма клиники «Цадмир» (регистратура → касса → специалист).
///
/// Поток: регистрация создаёт приём в [kVisitAwaitingPayment]; касса
/// (инлайн в регистратуре) проводит оплату → [kVisitPaid]; после направления к
/// специалисту приём закрывается → [kVisitDone]. Прежняя «доска очереди»
/// (waiting/in_progress) упразднена.
const String kVisitAwaitingPayment = 'awaiting_payment';
const String kVisitPaid = 'paid';
const String kVisitDone = 'done';

/// Статус приёма → русская подпись.
const Map<String, String> kVisitStatusLabels = <String, String>{
  kVisitAwaitingPayment: 'Ожидает оплаты',
  kVisitPaid: 'Оплачено',
  kVisitDone: 'Завершён',
};

/// Статус → семантический цвет [StatusBadge] (см. [BadgeKind]).
const Map<String, BadgeKind> kVisitStatusKind = <String, BadgeKind>{
  kVisitAwaitingPayment: BadgeKind.warning,
  kVisitPaid: BadgeKind.info,
  kVisitDone: BadgeKind.success,
};

/// Приём пациента клиники «Цадмир».
///
/// Простой immutable-класс с [fromMap]/[toMap] под коллекцию Firestore
/// `visits` (по образцу [Patient]). Ключи документа — snake_case. Часть полей
/// пациента денормализована в приём (`patient_name`, `mrn`, `birth_year`,
/// `phone`, `referral`), чтобы список рисовался без доп. чтения карты. Услуга,
/// за которую платит пациент, хранится прямо в приёме (`service_name`,
/// `service_price`). `queue_number` — необязательный посуточный порядковый номер
/// (доска очереди упразднена, но поле оставлено для сортировки/справки).
class Visit {
  const Visit({
    required this.id,
    this.patientId,
    required this.mrn,
    required this.patientName,
    required this.birthYear,
    this.phone,
    this.referral,
    this.serviceName,
    this.servicePrice,
    required this.status,
    this.queueNumber = 0,
    required this.day,
    this.note,
    this.createdBy,
    this.createdAt,
    this.paidAt,
    this.doneAt,
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

  /// Название услуги, за которую платит пациент (из прайса или своя).
  final String? serviceName;

  /// Цена услуги в KGS «сом».
  final num? servicePrice;

  /// Один из [kVisitAwaitingPayment] / [kVisitPaid] / [kVisitDone].
  final String status;

  /// Посуточный номер приёма (счётчик `counters/queue-YYYY-MM-DD`) — справочный.
  final int queueNumber;

  /// Дата приёма в ISO `YYYY-MM-DD`.
  final String day;

  /// Заметка (напр. консультация из регистратуры).
  final String? note;

  final String? createdBy;
  final DateTime? createdAt;

  /// Когда приём оплачен (`awaiting_payment` → `paid`).
  final DateTime? paidAt;

  /// Когда приём завершён (`paid` → `done`).
  final DateTime? doneAt;

  /// Русская подпись статуса.
  String get statusLabel => kVisitStatusLabels[status] ?? status;

  /// Семантический цвет статуса для [StatusBadge].
  BadgeKind get statusKind => kVisitStatusKind[status] ?? BadgeKind.neutral;

  /// Русская подпись направления (или `null`).
  String? get referralLabel =>
      referral == null ? null : (kReferralLabels[referral] ?? referral);

  /// Приём ждёт оплаты.
  bool get isAwaitingPayment => status == kVisitAwaitingPayment;

  /// Приём оплачен (можно направлять к специалисту / завершать).
  bool get isPaid => status == kVisitPaid;

  /// Приём завершён (терминальный статус).
  bool get isDone => status == kVisitDone;

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

    num? readNum(dynamic v) {
      if (v is num) return v;
      return num.tryParse('${v ?? ''}');
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
      serviceName: str(map['service_name']),
      servicePrice: readNum(map['service_price']),
      status: str(map['status']) ?? kVisitAwaitingPayment,
      queueNumber: readInt(map['queue_number']),
      day: map['day']?.toString() ?? '',
      note: str(map['note']),
      createdBy: str(map['created_by']),
      createdAt: readTs(map['created_at']),
      paidAt: readTs(map['paid_at']),
      doneAt: readTs(map['done_at']),
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
    if (serviceName != null && serviceName!.isNotEmpty)
      'service_name': serviceName,
    if (servicePrice != null) 'service_price': servicePrice,
    'status': status,
    'queue_number': queueNumber,
    'day': day,
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}
