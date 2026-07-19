import 'package:cloud_firestore/cloud_firestore.dart';

/// Статусы кассовой смены (значения поля `status` в Firestore).
const String kShiftOpen = 'open';
const String kShiftClosed = 'closed';

const Map<String, String> kShiftStatusLabels = <String, String>{
  kShiftOpen: 'Открыта',
  kShiftClosed: 'Закрыта',
};

/// Кассовая смена клиники «Цадмир» (коллекция Firestore `cash_shifts`).
///
/// Простой immutable-класс с [fromMap] (по образцу [Payment]/[ServiceItem]).
/// Валюта — KGS «сом». Одна открытая смена на день: открывают с начальным
/// остатком ([openingAmount]) и закрывают с фактически пересчитанной суммой
/// ([countedAmount]). Закрытие — единственная разрешённая правка (см.
/// firestore.rules): смена не удаляется, учёт append-only.
class CashShift {
  const CashShift({
    required this.id,
    required this.day,
    this.openedAt,
    this.openedBy,
    required this.openingAmount,
    this.closedAt,
    this.closedBy,
    this.countedAmount,
    required this.status,
  });

  final String id;

  /// День смены `YYYY-MM-DD` — для дешёвого запроса «смена за сегодня».
  final String day;

  final DateTime? openedAt;
  final String? openedBy;

  /// Остаток в кассе на начало смены (KGS «сом»).
  final num openingAmount;

  final DateTime? closedAt;
  final String? closedBy;

  /// Фактически пересчитанная сумма при закрытии (null, пока смена открыта).
  final num? countedAmount;

  final String status;

  bool get isOpen => status == kShiftOpen;
  bool get isClosed => status == kShiftClosed;
  String get statusLabel => kShiftStatusLabels[status] ?? status;

  factory CashShift.fromMap(Map<String, dynamic> map) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return CashShift(
      id: map['id']?.toString() ?? '',
      day: map['day']?.toString() ?? '',
      openedAt: ts(map['opened_at']),
      openedBy: str(map['opened_by']),
      openingAmount: (map['opening_amount'] as num?) ?? 0,
      closedAt: ts(map['closed_at']),
      closedBy: str(map['closed_by']),
      countedAmount: map['counted_amount'] as num?,
      status: map['status']?.toString() ?? kShiftOpen,
    );
  }
}
