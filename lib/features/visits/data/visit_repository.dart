import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/visit.dart';

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(FirebaseFirestore.instance),
);

/// Ошибка недопустимого перехода статуса визита. `toString()` возвращает уже
/// человеко-читаемый русский текст, поэтому `friendlyError` пропускает его как
/// есть.
class VisitTransitionException implements Exception {
  const VisitTransitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Очередь визитов в **Firestore** (коллекция `visits`) — без бэкенда, клиент
/// пишет/читает напрямую (по образцу `patients_repository`). Ключи документов —
/// snake_case, как ждёт [Visit]. Номер в очереди (`queue_number`) выдаётся
/// последовательно из посуточного счётчика `counters/queue-YYYY-MM-DD` в
/// транзакции.
class VisitRepository {
  VisitRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('visits');

  /// Сегодняшняя дата в ISO `YYYY-MM-DD` (день очереди).
  static String todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Создаёт визит в статусе `waiting`: атомарно выдаёт `queue_number` из
  /// счётчика `counters/queue-{день}` и пишет документ визита с
  /// денормализованными полями пациента. Штампует `created_by`/`created_at`.
  Future<Visit> create({
    String? patientId,
    required String mrn,
    required String patientName,
    required int birthYear,
    String? phone,
    String? referral,
    String? note,
  }) async {
    final day = todayIso();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docRef = _col.doc();
    await _db.runTransaction((tx) async {
      final counterRef = _db.collection('counters').doc('queue-$day');
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['seq'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      tx.set(counterRef, <String, dynamic>{
        'seq': next,
      }, SetOptions(merge: true));
      tx.set(docRef, <String, dynamic>{
        if (_clean(patientId) != null) 'patient_id': _clean(patientId),
        'mrn': mrn,
        'patient_name': patientName,
        'birth_year': birthYear,
        if (_clean(phone) != null) 'phone': _clean(phone),
        if (_clean(referral) != null) 'referral': _clean(referral),
        'status': kVisitWaiting,
        'queue_number': next,
        'day': day,
        if (_clean(note) != null) 'note': _clean(note),
        'created_by': uid,
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    final doc = await docRef.get();
    return Visit.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Визиты за сегодня, по возрастанию `queue_number`. [statuses] — опциональный
  /// фильтр по статусам (на клиенте), чтобы не плодить составные индексы.
  Future<List<Visit>> listToday({Set<String>? statuses}) async {
    final day = todayIso();
    final snap = await _col
        .where('day', isEqualTo: day)
        .orderBy('queue_number')
        .get();
    var visits = snap.docs
        .map((d) => Visit.fromMap({...d.data(), 'id': d.id}))
        .toList();
    if (statuses != null && statuses.isNotEmpty) {
      visits = visits.where((v) => statuses.contains(v.status)).toList();
    }
    return visits;
  }

  /// Меняет статус визита с проверкой допустимого перехода
  /// ([kVisitAllowedTransitions]). Штампует соответствующий таймстамп события
  /// (`called_at`/`completed_at`/`cancelled_at`) + `updated_by`/`updated_at`.
  /// Всё в транзакции, чтобы переход считался от актуального статуса.
  Future<void> setStatus(String id, String newStatus) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docRef = _col.doc(id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) {
        throw const VisitTransitionException('Визит не найден.');
      }
      final current = snap.data()?['status']?.toString() ?? kVisitWaiting;
      final allowed = kVisitAllowedTransitions[current] ?? const <String>[];
      if (!allowed.contains(newStatus)) {
        final from = kVisitStatusLabels[current] ?? current;
        final to = kVisitStatusLabels[newStatus] ?? newStatus;
        throw VisitTransitionException('Недопустимый переход: $from → $to.');
      }
      final data = <String, dynamic>{
        'status': newStatus,
        'updated_by': uid,
        'updated_at': FieldValue.serverTimestamp(),
      };
      switch (newStatus) {
        case kVisitInProgress:
          data['called_at'] = FieldValue.serverTimestamp();
        case kVisitCompleted:
          data['completed_at'] = FieldValue.serverTimestamp();
        case kVisitCancelled:
          data['cancelled_at'] = FieldValue.serverTimestamp();
      }
      tx.update(docRef, data);
    });
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Очередь на сегодня (все статусы, по возрастанию номера). autoDispose —
/// обновляется через `invalidate` после регистрации/смены статуса. Экраны
/// доски и регистратуры фильтруют статусы на клиенте.
final todayVisitsProvider = FutureProvider.autoDispose<List<Visit>>(
  (ref) => ref.watch(visitRepositoryProvider).listToday(),
);
