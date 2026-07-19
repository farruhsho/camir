import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/data/audit_repository.dart';
import '../domain/visit.dart';

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(FirebaseFirestore.instance),
);

/// Приёмы клиники «Цадмир» в **Firestore** (коллекция `visits`) — без бэкенда,
/// клиент пишет/читает напрямую (по образцу `patients_repository`). Ключи
/// документов — snake_case, как ждёт [Visit]. Порядковый номер приёма
/// (`queue_number`) выдаётся последовательно из посуточного счётчика
/// `counters/queue-YYYY-MM-DD` в транзакции.
class VisitRepository {
  VisitRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('visits');

  /// Сегодняшняя дата в ISO `YYYY-MM-DD` (день приёма).
  static String todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Создаёт приём в статусе `awaiting_payment`: атомарно выдаёт `queue_number`
  /// из счётчика `counters/queue-{день}` и пишет документ с денормализованными
  /// полями пациента и выбранной услугой (`service_name`/`service_price`).
  /// Штампует `created_by`/`created_at`.
  Future<Visit> create({
    String? patientId,
    required String mrn,
    required String patientName,
    required int birthYear,
    String? phone,
    String? referral,
    String? serviceName,
    num? servicePrice,
    String? note,
  }) async {
    final day = todayIso();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docRef = _col.doc();
    var queueNumber = 0;
    await _db.runTransaction((tx) async {
      final counterRef = _db.collection('counters').doc('queue-$day');
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['seq'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      queueNumber = next;
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
        if (_clean(serviceName) != null) 'service_name': _clean(serviceName),
        'service_price': ?servicePrice,
        'status': kVisitAwaitingPayment,
        'queue_number': next,
        'day': day,
        if (_clean(note) != null) 'note': _clean(note),
        'created_by': uid,
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    final doc = await docRef.get();
    final visit = Visit.fromMap({...?doc.data(), 'id': doc.id});
    await logAudit(
      module: 'visits',
      entity: 'visit',
      entityId: docRef.id,
      action: 'create',
      summary: 'Регистрация приёма № $queueNumber — $patientName',
    );
    return visit;
  }

  /// Приёмы за сегодня, по возрастанию `queue_number`. [statuses] —
  /// опциональный фильтр по статусам (на клиенте), чтобы не плодить составные
  /// индексы.
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

  /// Переводит приём в статус `paid` (после инкассации в регистратуре).
  /// Штампует `paid_at` + `updated_by`/`updated_at`.
  Future<void> markPaid(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _col.doc(id).update(<String, dynamic>{
      'status': kVisitPaid,
      'paid_at': FieldValue.serverTimestamp(),
      'updated_by': uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'visits',
      entity: 'visit',
      entityId: id,
      action: 'mark_paid',
      summary: 'Приём оплачен',
      changes: <String, dynamic>{'status': kVisitPaid},
    );
  }

  /// Завершает приём (`paid` → `done`) — напр. после направления к специалисту.
  /// Штампует `done_at` + `updated_by`/`updated_at`.
  Future<void> markDone(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _col.doc(id).update(<String, dynamic>{
      'status': kVisitDone,
      'done_at': FieldValue.serverTimestamp(),
      'updated_by': uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'visits',
      entity: 'visit',
      entityId: id,
      action: 'mark_done',
      summary: 'Приём завершён',
      changes: <String, dynamic>{'status': kVisitDone},
    );
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Приёмы на сегодня (все статусы, по возрастанию номера). Обновляется через
/// `invalidate` после регистрации/оплаты/завершения. Экран регистратуры
/// фильтрует статусы на клиенте.
final todayVisitsProvider = FutureProvider<List<Visit>>(
  (ref) => ref.watch(visitRepositoryProvider).listToday(),
);
