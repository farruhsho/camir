import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/analysis_record.dart';

final analysesRepositoryProvider = Provider<AnalysesRepository>(
  (ref) => AnalysesRepository(FirebaseFirestore.instance),
);

/// Лабораторные анализы в **Firestore** (коллекция `analyses`) — без бэкенда,
/// клиент пишет/читает напрямую. Записи отдаются свежими сверху (по
/// `created_at`). Ключи документов — snake_case, как ждёт [AnalysisRecord].
///
/// Результат можно дозаполнить позже ([update]) или исправить ошибку — запись
/// больше не «write-once». Каждое изменение штампуется `updated_by` +
/// `updated_at`, создание — `created_by`.
class AnalysesRepository {
  AnalysesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('analyses');

  /// uid текущего сотрудника для штампов `created_by` / `updated_by`.
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Список записей. [q] — опциональный поиск по ФИО/телефону/виду анализа
  /// (фильтруется на клиенте, т.к. Firestore не умеет подстроку).
  Future<List<AnalysisRecord>> list({String? q, int limit = 200}) async {
    final snap = await _col
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    var records = _parseDocs(snap.docs);
    final needle = q?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      records = records
          .where(
            (r) =>
                r.fullName.toLowerCase().contains(needle) ||
                (r.phone ?? '').toLowerCase().contains(needle) ||
                r.analysisType.toLowerCase().contains(needle),
          )
          .toList();
    }
    return records;
  }

  /// Анализы одного пациента (для карточки пациента, агент B).
  ///
  /// Берёт записи, привязанные к карте (`patient_id == id`, свежие сверху по
  /// `created_at` — нужен композитный индекс `patient_id + created_at`). Если
  /// задано [fullName] — дополнительно подтягивает записи с точным совпадением
  /// ФИО, НО только те, что ещё НЕ привязаны к какой-либо карте
  /// (`patient_id` пустой): это анализы, заведённые вручную до того, как
  /// пациента добавили в картотеку. Результаты объединяются и дедуплицируются
  /// по `id`.
  Future<List<AnalysisRecord>> listForPatient(
    String patientId, {
    String? fullName,
  }) async {
    final byIdSnap = await _col
        .where('patient_id', isEqualTo: patientId)
        .orderBy('created_at', descending: true)
        .get();
    final records = _parseDocs(byIdSnap.docs);
    final seen = <String>{for (final r in records) r.id};

    final name = fullName?.trim();
    var mergedUnlinked = false;
    if (name != null && name.isNotEmpty) {
      final byNameSnap = await _col.where('full_name', isEqualTo: name).get();
      for (final d in byNameSnap.docs) {
        if (seen.contains(d.id)) continue;
        final r = _tryParse(d);
        // Только «висячие» записи без привязки к карте — чтобы не притянуть
        // однофамильцев, уже закреплённых за другими пациентами.
        if (r == null || (r.patientId != null && r.patientId!.isNotEmpty)) {
          continue;
        }
        records.add(r);
        seen.add(r.id);
        mergedUnlinked = true;
      }
    }

    // При подмешивании «висячих» записей выстраиваем единую хронологию по дате
    // анализа (ISO `YYYY-MM-DD` сортируется лексикографически = хронологически).
    if (mergedUnlinked) {
      records.sort((a, b) => b.date.compareTo(a.date));
    }
    return records;
  }

  /// Создаёт запись анализа. Пустые необязательные поля не пишутся. Штампует
  /// `created_by`.
  Future<AnalysisRecord> create({
    String? patientId,
    required String fullName,
    required int birthYear,
    String? phone,
    required String analysisType,
    String? result,
    required String date,
  }) async {
    final ref = await _col.add(<String, dynamic>{
      if (patientId != null && patientId.isNotEmpty) 'patient_id': patientId,
      'full_name': fullName,
      'birth_year': birthYear,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'analysis_type': analysisType,
      if (result != null && result.isNotEmpty) 'result': result,
      'date': date,
      'created_by': _uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return AnalysisRecord.fromJson({...?doc.data(), 'id': doc.id});
  }

  /// Дозаполняет/исправляет запись — обновляются ТОЛЬКО переданные поля
  /// (не переданные (`null`) остаются как есть). Позволяет внести результат
  /// позже или поправить опечатку. Штампует `updated_by` + `updated_at`.
  Future<AnalysisRecord> update(
    String id, {
    String? result,
    String? analysisType,
    String? date,
    String? phone,
    String? fullName,
    int? birthYear,
  }) async {
    final data = <String, dynamic>{
      'updated_by': _uid,
      'updated_at': FieldValue.serverTimestamp(),
    };
    // Необязательные текстовые поля: пустая строка очищает поле (пишет null).
    if (result != null) data['result'] = _clean(result);
    if (phone != null) data['phone'] = _clean(phone);
    if (analysisType != null) data['analysis_type'] = analysisType;
    if (date != null) data['date'] = date;
    if (fullName != null) data['full_name'] = fullName.trim();
    if (birthYear != null) data['birth_year'] = birthYear;

    await _col.doc(id).update(data);
    final doc = await _col.doc(id).get();
    return AnalysisRecord.fromJson({...?doc.data(), 'id': doc.id});
  }

  /// Удаляет запись анализа (например заведена по ошибке).
  Future<void> delete(String id) => _col.doc(id).delete();

  // ── Разбор документов ──────────────────────────────────────────────────────

  /// Безопасно разбирает набор документов: повреждённый документ пропускается
  /// (с `debugPrint`), чтобы одна битая запись не роняла весь журнал — жёсткие
  /// касты в `analysis_record.g.dart` иначе бросают исключение на весь список.
  List<AnalysisRecord> _parseDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <AnalysisRecord>[];
    for (final d in docs) {
      final r = _tryParse(d);
      if (r != null) out.add(r);
    }
    return out;
  }

  AnalysisRecord? _tryParse(DocumentSnapshot<Map<String, dynamic>> d) {
    try {
      return AnalysisRecord.fromJson({...?d.data(), 'id': d.id});
    } catch (e) {
      debugPrint('analyses: пропущен повреждённый документ ${d.id}: $e');
      return null;
    }
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Список анализов для экрана (autoDispose — обновляется через invalidate после
/// создания записи).
final analysesListProvider = FutureProvider.autoDispose<List<AnalysisRecord>>(
  (ref) => ref.watch(analysesRepositoryProvider).list(),
);
