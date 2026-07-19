import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../analyses/domain/analysis_record.dart' show kAnalysisTypes;
import '../../audit/data/audit_repository.dart';
import '../domain/analysis_type.dart';

final analysisTypesRepositoryProvider = Provider<AnalysisTypesRepository>(
  (ref) => AnalysisTypesRepository(FirebaseFirestore.instance),
);

/// Все виды анализов (для экрана управления справочником).
final analysisTypesProvider = FutureProvider<List<AnalysisType>>(
  (ref) => ref.watch(analysisTypesRepositoryProvider).list(),
);

/// Только активные виды (для выпадашки при вводе результата в модуле «Анализы»).
final activeAnalysisTypesProvider = FutureProvider<List<AnalysisType>>(
  (ref) => ref.watch(analysisTypesRepositoryProvider).list(activeOnly: true),
);

/// Справочник видов анализов «Цадмир» в **Firestore** (коллекция
/// `analysis_types`) — без бэкенда, клиент пишет/читает напрямую. Сортировка по
/// названию (single-field индекс создаётся автоматически). Ключи документов —
/// snake_case, как ждёт [AnalysisType].
///
/// Каждая мутация штампует `created_by`/`created_at` (при создании) либо
/// `updated_by`/`updated_at` (при изменении) и пишет запись в журнал аудита
/// через [logAudit] (best-effort — сбой аудита не ломает основную операцию).
class AnalysisTypesRepository {
  AnalysisTypesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('analysis_types');

  /// uid текущего сотрудника для штампов `created_by` / `updated_by`.
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Список видов анализов (по названию). [activeOnly] отфильтровывает
  /// отключённые записи (фильтр на клиенте — не требует композитного индекса).
  Future<List<AnalysisType>> list({bool activeOnly = false}) async {
    final snap = await _col
        .where('clinic_id', isEqualTo: ClinicScope.current)
        .orderBy('name')
        .get();
    var items = _parseDocs(snap.docs);
    if (activeOnly) items = items.where((t) => t.active).toList();
    return items;
  }

  /// Добавляет вид анализа. Возвращает id созданного документа.
  Future<String> add({
    required String name,
    required String resultType,
    List<String> options = const <String>[],
    String? unit,
    num? refLow,
    num? refHigh,
  }) async {
    final ref = await _col.add(<String, dynamic>{
      'clinic_id': ClinicScope.current,
      ..._fields(
        name: name,
        resultType: resultType,
        options: options,
        unit: unit,
        refLow: refLow,
        refHigh: refHigh,
      ),
      'active': true,
      'created_by': _uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'analysis_types',
      entity: 'analysis_type',
      entityId: ref.id,
      action: 'create',
      summary: 'Добавлен вид анализа «${name.trim()}»',
    );
    return ref.id;
  }

  /// Обновляет вид анализа целиком (диалог отдаёт полное намеренное состояние).
  /// Необязательные поля (`unit`/`ref_low`/`ref_high`), переданные как `null`,
  /// **очищаются** в документе — это позволяет переключить тип с количественного
  /// на качественный, не оставив «висячих» единицы/референса.
  Future<void> update(
    String id, {
    required String name,
    required String resultType,
    List<String> options = const <String>[],
    String? unit,
    num? refLow,
    num? refHigh,
  }) async {
    await _col.doc(id).update(<String, dynamic>{
      ..._fields(
        name: name,
        resultType: resultType,
        options: options,
        unit: unit,
        refLow: refLow,
        refHigh: refHigh,
        clearMissing: true,
      ),
      'updated_by': _uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'analysis_types',
      entity: 'analysis_type',
      entityId: id,
      action: 'update',
      summary: 'Изменён вид анализа «${name.trim()}»',
    );
  }

  /// Включает/отключает вид анализа (отключённые не предлагаются при вводе).
  Future<void> setActive(String id, bool active) async {
    await _col.doc(id).update(<String, dynamic>{
      'active': active,
      'updated_by': _uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'analysis_types',
      entity: 'analysis_type',
      entityId: id,
      action: 'status_change',
      summary: active ? 'Вид анализа включён' : 'Вид анализа отключён',
      changes: <String, dynamic>{'active': active},
    );
  }

  /// Удаляет вид анализа из справочника.
  Future<void> delete(String id) async {
    await _col.doc(id).delete();
    await logAudit(
      module: 'analysis_types',
      entity: 'analysis_type',
      entityId: id,
      action: 'delete',
      summary: 'Удалён вид анализа',
    );
  }

  /// Первичное наполнение справочника из стандартного списка [kAnalysisTypes]
  /// (модуль «Анализы») — как количественные типы с пустыми референсами, чтобы
  /// при переходе на справочник ничего из привычных видов не потерялось. Ссылки
  /// потом дозаполняются вручную. Один batch = одна запись аудита.
  Future<int> seedDefaults() async {
    final batch = _db.batch();
    final uid = _uid;
    for (final name in kAnalysisTypes) {
      batch.set(_col.doc(), <String, dynamic>{
        'clinic_id': ClinicScope.current,
        'name': name,
        'result_type': kResultQuantitative,
        'options': const <String>[],
        'active': true,
        'created_by': uid,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await logAudit(
      module: 'analysis_types',
      entity: 'analysis_type',
      action: 'create',
      summary:
          'Справочник видов анализов заполнен из стандартного списка '
          '(${kAnalysisTypes.length})',
    );
    return kAnalysisTypes.length;
  }

  // ── Внутреннее ──────────────────────────────────────────────────────────────

  /// Собирает общие поля документа из параметров. При [clearMissing] пустые
  /// необязательные поля пишутся как [FieldValue.delete] (очистка при правке);
  /// иначе просто опускаются (создание). `name` нормализуется trim'ом.
  Map<String, dynamic> _fields({
    required String name,
    required String resultType,
    required List<String> options,
    required String? unit,
    required num? refLow,
    required num? refHigh,
    bool clearMissing = false,
  }) {
    final isQuant = resultType == kResultQuantitative;
    final cleanUnit = unit?.trim();
    // Для качественного типа единица/референс неприменимы — очищаем их.
    final keepUnit = isQuant && cleanUnit != null && cleanUnit.isNotEmpty;
    final keepLow = isQuant && refLow != null;
    final keepHigh = isQuant && refHigh != null;

    Object? optional(bool keep, Object? value) =>
        keep ? value : (clearMissing ? FieldValue.delete() : null);

    final map = <String, dynamic>{
      'name': name.trim(),
      'result_type': resultType,
      // Варианты — только для качественного типа (иначе пустой список).
      'options': isQuant ? const <String>[] : options,
    };
    final unitVal = optional(keepUnit, cleanUnit);
    final lowVal = optional(keepLow, refLow);
    final highVal = optional(keepHigh, refHigh);
    if (unitVal != null) map['unit'] = unitVal;
    if (lowVal != null) map['ref_low'] = lowVal;
    if (highVal != null) map['ref_high'] = highVal;
    return map;
  }

  /// Безопасно разбирает документы: повреждённый пропускается (с `debugPrint`),
  /// чтобы одна битая запись не роняла весь справочник.
  List<AnalysisType> _parseDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <AnalysisType>[];
    for (final d in docs) {
      try {
        out.add(AnalysisType.fromMap({...d.data(), 'id': d.id}));
      } catch (e) {
        debugPrint(
          'analysis_types: пропущен повреждённый документ ${d.id}: $e',
        );
      }
    }
    return out;
  }
}
