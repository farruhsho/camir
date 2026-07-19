import 'package:cloud_firestore/cloud_firestore.dart';

/// Изъятие (расход) наличных из кассы «Цадмир» (коллекция Firestore
/// `cash_withdrawals`).
///
/// Простой immutable-класс. Валюта — KGS «сом». Запись append-only: изъятие
/// нельзя править/удалять (см. firestore.rules) — дневной отчёт кассы должен
/// сходиться. Уменьшает остаток «В кассе» за день.
class CashWithdrawal {
  const CashWithdrawal({
    required this.id,
    required this.amount,
    this.reason,
    required this.day,
    this.createdBy,
    this.createdAt,
  });

  final String id;

  /// Изъятая сумма (KGS «сом»).
  final num amount;

  /// Причина изъятия (инкассация, размен, хознужды и т.п.).
  final String? reason;

  /// День изъятия `YYYY-MM-DD` — для дешёвого запроса «за сегодня».
  final String day;

  final String? createdBy;
  final DateTime? createdAt;

  factory CashWithdrawal.fromMap(Map<String, dynamic> map) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return CashWithdrawal(
      id: map['id']?.toString() ?? '',
      amount: (map['amount'] as num?) ?? 0,
      reason: str(map['reason']),
      day: map['day']?.toString() ?? '',
      createdBy: str(map['created_by']),
      createdAt: ts(map['created_at']),
    );
  }
}
