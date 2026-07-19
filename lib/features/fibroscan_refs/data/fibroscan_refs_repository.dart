import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/data/audit_repository.dart';
import '../domain/fibro_ref.dart';

final fibroscanRefsRepositoryProvider = Provider<FibroscanRefsRepository>(
  (ref) => FibroscanRefsRepository(FirebaseFirestore.instance),
);

/// Референсы фиброскана для экранов/консьюмеров (keep-alive — переживает уход с
/// экрана; после правок инвалидируется вручную). Если коллекция пуста —
/// отдаёт стандартные пороги [kDefaultFibroRefs].
final fibroRefsProvider = FutureProvider<List<FibroRef>>(
  (ref) => ref.watch(fibroscanRefsRepositoryProvider).list(),
);

/// Справочник референсных диапазонов фиброскана в **Firestore** (коллекция
/// `fibroscan_refs`) — без бэкенда, клиент пишет/читает напрямую. Ключи
/// документов — snake_case (см. [FibroRef]). Каждая мутация штампует
/// `created_by`/`updated_by` и пишет запись аудита через [logAudit]
/// (best-effort: аудит никогда не роняет саму операцию).
class FibroscanRefsRepository {
  FibroscanRefsRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('fibroscan_refs');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Все бэнды, сгруппированные (фиброз → стеатоз) и отсортированные по нижней
  /// границе. Пустая коллекция → стандартные пороги [kDefaultFibroRefs]
  /// (их можно записать в базу кнопкой «Сбросить к стандартным» → [setDefaults]).
  /// Битый документ пропускается, а не роняет весь список.
  Future<List<FibroRef>> list() async {
    final snap = await _col.get();
    if (snap.docs.isEmpty) {
      return List<FibroRef>.from(kDefaultFibroRefs);
    }
    final refs = <FibroRef>[];
    for (final d in snap.docs) {
      try {
        refs.add(FibroRef.fromMap({...d.data(), 'id': d.id}));
      } catch (_) {
        // Пропускаем несовместимый документ (старая/битая схема).
      }
    }
    refs.sort(_compare);
    return refs;
  }

  /// Создаёт (id пуст) или правит (id задан) бэнд. Пустая заметка при правке
  /// удаляет поле. Штампует автора и пишет аудит.
  Future<void> upsert(FibroRef item) async {
    final data = <String, dynamic>{
      'kind': item.kind,
      'label': item.label.trim(),
      'min': item.min,
      'max': item.max,
    };
    final note = item.note?.trim();
    final changes = <String, dynamic>{
      'kind': item.kind,
      'label': item.label.trim(),
      'min': item.min,
      'max': item.max,
      'note': (note == null || note.isEmpty) ? null : note,
    };

    if (item.id.isEmpty) {
      data['note'] = (note == null || note.isEmpty) ? null : note;
      data['created_by'] = _uid;
      data['created_at'] = FieldValue.serverTimestamp();
      final doc = await _col.add(data);
      await logAudit(
        module: 'fibroscan_refs',
        entity: 'fibro_ref',
        entityId: doc.id,
        action: 'create',
        summary: _summary(item),
        changes: changes,
      );
    } else {
      data['note'] = (note == null || note.isEmpty)
          ? FieldValue.delete()
          : note;
      data['updated_by'] = _uid;
      data['updated_at'] = FieldValue.serverTimestamp();
      await _col.doc(item.id).update(data);
      await logAudit(
        module: 'fibroscan_refs',
        entity: 'fibro_ref',
        entityId: item.id,
        action: 'update',
        summary: _summary(item),
        changes: changes,
      );
    }
  }

  /// Удаляет бэнд. [summary] — человекочитаемое описание для аудита.
  Future<void> delete(String id, {String? summary}) async {
    await _col.doc(id).delete();
    await logAudit(
      module: 'fibroscan_refs',
      entity: 'fibro_ref',
      entityId: id,
      action: 'delete',
      summary: summary ?? 'Удалён референс фиброскана',
    );
  }

  /// Сбрасывает коллекцию к стандартным порогам [kDefaultFibroRefs]:
  /// удаляет текущие документы и записывает набор по умолчанию (одной пачкой).
  Future<void> setDefaults() async {
    final existing = await _col.get();
    final batch = _db.batch();
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (final r in kDefaultFibroRefs) {
      batch.set(_col.doc(), <String, dynamic>{
        'kind': r.kind,
        'label': r.label,
        'min': r.min,
        'max': r.max,
        if (r.note != null && r.note!.isNotEmpty) 'note': r.note,
        'created_by': _uid,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await logAudit(
      module: 'fibroscan_refs',
      entity: 'fibro_ref',
      action: 'update',
      summary:
          'Референсы фиброскана сброшены к стандартным '
          '(${kDefaultFibroRefs.length} диапазонов)',
    );
  }

  /// Краткое описание бэнда для журнала аудита, напр. «Фиброз F2 · 7–9.5 kPa».
  static String _summary(FibroRef r) {
    final group = r.kind == kFibroKindSteatosis ? 'Стеатоз' : 'Фиброз';
    return '$group ${r.label} · ${_rangeText(r)}';
  }

  static String _rangeText(FibroRef r) {
    final lo = r.min, hi = r.max, u = r.unitLabel;
    if (lo == null && hi == null) return '—';
    if (lo == null) return '< ${_num(hi!)} $u';
    if (hi == null) return '≥ ${_num(lo)} $u';
    return '${_num(lo)}–${_num(hi)} $u';
  }

  static String _num(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Фиброз раньше стеатоза, затем по нижней границе (открытый край — «−∞»).
  static int _compare(FibroRef a, FibroRef b) {
    int order(String k) => k == kFibroKindFibrosis ? 0 : 1;
    final ko = order(a.kind).compareTo(order(b.kind));
    if (ko != 0) return ko;
    final am = a.min ?? double.negativeInfinity;
    final bm = b.min ?? double.negativeInfinity;
    return am.compareTo(bm);
  }
}
