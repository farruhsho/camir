import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fibroscan_record.dart';

final fibroscanRepositoryProvider = Provider<FibroscanRepository>(
  (ref) => FibroscanRepository(FirebaseFirestore.instance),
);

/// Журнал исследований фиброскана в **Firestore** (коллекция `fibroscan`) —
/// без бэкенда, клиент пишет/читает напрямую (по образцу `analyses_repository`).
/// Записи отдаются свежими сверху (по `created_at`). Ключи документов —
/// snake_case, как ждёт [FibroscanRecord]. Дата исследования хранится ISO
/// `YYYY-MM-DD`; на экран выводится как `ДД.ММ.ГГГГ`.
class FibroscanRepository {
  FibroscanRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('fibroscan');

  /// Список исследований, свежие сверху. [q] — необязательный поиск по ФИО /
  /// диагнозу / году рождения (фильтр на клиенте, т.к. Firestore не умеет
  /// подстроку). Парсинг каждого документа обёрнут в try/catch: один битый
  /// документ (например, из старой схемы) не должен ронять весь список.
  Future<List<FibroscanRecord>> list({String? q, int limit = 200}) async {
    final snap = await _col
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    var records = _mapDocs(snap.docs);
    final needle = q?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      records = records
          .where(
            (r) =>
                r.fullName.toLowerCase().contains(needle) ||
                r.diagnosis.toLowerCase().contains(needle) ||
                r.birthYear.toString().contains(needle),
          )
          .toList();
    }
    return records;
  }

  /// Записи фиброскана конкретного пациента (для карточки пациента, агент B).
  /// Основной матч — по `patient_id`. Если передан [fullName], дополнительно
  /// подхватываются записи-«сироты» БЕЗ `patient_id` с точным совпадением ФИО
  /// (разовые записи, внесённые до привязки к карте). Записи с ЧУЖИМ
  /// `patient_id`, но совпавшим ФИО, не подмешиваются — это разные люди с
  /// одинаковыми ФИО. Сортировка по `created_at` — на клиенте, чтобы не
  /// требовать составной индекс Firestore.
  Future<List<FibroscanRecord>> listForPatient(
    String patientId, {
    String? fullName,
  }) async {
    final byId = await _col.where('patient_id', isEqualTo: patientId).get();
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[...byId.docs];

    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      final byName = await _col.where('full_name', isEqualTo: name).get();
      for (final d in byName.docs) {
        final pid = d.data()['patient_id'];
        final orphan = pid == null || (pid is String && pid.isEmpty);
        if (orphan) docs.add(d);
      }
    }

    // Дедуп по id документа (на случай пересечения выборок).
    final seen = <String>{};
    final unique = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      if (seen.add(d.id)) unique.add(d);
    }
    // Свежие сверху (клиентская сортировка — без составного индекса).
    unique.sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
    return _mapDocs(unique);
  }

  /// Создаёт запись исследования. [patientId] опускается для разовой записи без
  /// карты. [date] уже в ISO `YYYY-MM-DD` (конвертирует экран). Штампует
  /// `created_by`.
  Future<FibroscanRecord> create({
    String? patientId,
    required String fullName,
    required int birthYear,
    required String date,
    required String diagnosis,
  }) async {
    final ref = await _col.add(<String, dynamic>{
      if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
      'full_name': fullName,
      'birth_year': birthYear,
      'date': date,
      'diagnosis': diagnosis,
      'created_by': FirebaseAuth.instance.currentUser?.uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return FibroscanRecord.fromJson({...?doc.data(), 'id': doc.id});
  }

  /// Правит запись (ошибочные ФИО / год / дата / диагноз). Передаются только
  /// изменяемые поля; [date] — ISO `YYYY-MM-DD`. Штампует `updated_by` +
  /// `updated_at`.
  Future<FibroscanRecord> update(
    String id, {
    String? fullName,
    int? birthYear,
    String? date,
    String? diagnosis,
  }) async {
    await _col.doc(id).update(<String, dynamic>{
      'full_name': ?fullName,
      'birth_year': ?birthYear,
      'date': ?date,
      'diagnosis': ?diagnosis,
      'updated_by': FirebaseAuth.instance.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    final doc = await _col.doc(id).get();
    return FibroscanRecord.fromJson({...?doc.data(), 'id': doc.id});
  }

  /// Удаляет ошибочно созданную запись исследования.
  Future<void> delete(String id) => _col.doc(id).delete();

  /// Безопасный маппинг документов: битый документ пропускается, а не роняет
  /// весь список.
  List<FibroscanRecord> _mapDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <FibroscanRecord>[];
    for (final d in docs) {
      try {
        out.add(FibroscanRecord.fromJson({...d.data(), 'id': d.id}));
      } catch (_) {
        // Пропускаем несовместимый документ (старая/битая схема).
      }
    }
    return out;
  }

  /// `created_at` документа как [DateTime] для клиентской сортировки
  /// (отсутствует/pending → «нулевая» дата, чтобы такие записи уходили вниз).
  static DateTime _createdAt(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final v = d.data()['created_at'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Список исследований для экрана (autoDispose — обновляется после создания /
/// правки / удаления через invalidate).
final fibroscanListProvider = FutureProvider<List<FibroscanRecord>>(
  (ref) => ref.watch(fibroscanRepositoryProvider).list(),
);
