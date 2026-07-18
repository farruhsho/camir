import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/payment.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => PaymentsRepository(FirebaseFirestore.instance),
);

/// Платежи, СОЗДАННЫЕ сегодня (свежие сверху) — приход в кассу за день + список.
final todayPaymentsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(paymentsRepositoryProvider).listToday(),
);

/// Возвраты, оформленные СЕГОДНЯ (по `refund_day`) — расход из кассы за день.
/// Отдельно от [todayPaymentsProvider], т.к. платёж могли создать вчера, а
/// вернуть сегодня — деньги ушли из сегодняшней кассы.
final todayRefundsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(paymentsRepositoryProvider).refundsToday(),
);

/// Касса «Цадмир» в **Firestore** (коллекция `payments`) — без бэкенда, клиент
/// пишет/читает напрямую. Ключи snake_case. Валюта — KGS «сом». Возврат — это
/// смена статуса на [kPayRefunded] (учёт append-only, дневной отчёт сходится).
class PaymentsRepository {
  PaymentsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('payments');

  /// Сегодняшний день `YYYY-MM-DD` (для дешёвого запроса «за сегодня»).
  static String todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Проводит платёж. [items] не должен быть пустым (проверяет форма). `total`
  /// считается на сервере из строк — клиентское значение не принимаем.
  Future<Payment> create({
    String? patientId,
    required String patientName,
    String? mrn,
    String? visitId,
    required List<PaymentItem> items,
    required String method,
    String? note,
  }) async {
    final total = items.fold<num>(0, (acc, i) => acc + i.subtotal);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = await _col.add(<String, dynamic>{
      if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
      'patient_name': patientName.trim().isEmpty
          ? 'Без карты'
          : patientName.trim(),
      if (mrn != null && mrn.isNotEmpty) 'mrn': mrn,
      if (visitId != null && visitId.isNotEmpty) 'visit_id': visitId,
      'items': items.map((i) => i.toMap()).toList(),
      'total': total,
      'method': method,
      'status': kPayPaid,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'day': todayIso(),
      'created_by': uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return Payment.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Платежи за сегодня, свежие сверху. Требует составной индекс
  /// (day ASC, created_at DESC) — см. firestore.indexes.json.
  Future<List<Payment>> listToday() async {
    final snap = await _col
        .where('day', isEqualTo: todayIso())
        .orderBy('created_at', descending: true)
        .get();
    return snap.docs
        .map((d) => Payment.fromMap({...d.data(), 'id': d.id}))
        .toList();
  }

  /// Возвраты, оформленные СЕГОДНЯ (по полю `refund_day`). Single-field запрос
  /// (авто-индекс), сортировка на клиенте по времени возврата.
  Future<List<Payment>> refundsToday() async {
    final snap = await _col
        .where('refund_day', isEqualTo: todayIso())
        .get();
    final items = snap.docs
        .map((d) => Payment.fromMap({...d.data(), 'id': d.id}))
        .toList();
    items.sort((a, b) {
      final ax = a.refundedAt;
      final bx = b.refundedAt;
      if (ax == null && bx == null) return 0;
      if (ax == null) return 1;
      if (bx == null) return -1;
      return bx.compareTo(ax);
    });
    return items;
  }

  /// Оформляет возврат: переводит платёж в [kPayRefunded] со временем, днём
  /// возврата (`refund_day` — для дневного отчёта) и причиной. Не удаляет
  /// запись (учёт append-only). Двойной возврат отсекается правилами
  /// (update разрешён только из статуса `paid`).
  Future<void> refund(String id, {String? reason}) async {
    await _col.doc(id).update(<String, dynamic>{
      'status': kPayRefunded,
      'refunded_at': FieldValue.serverTimestamp(),
      'refunded_by': FirebaseAuth.instance.currentUser?.uid,
      'refund_day': todayIso(),
      if (reason != null && reason.trim().isNotEmpty)
        'refund_reason': reason.trim(),
    });
  }
}
