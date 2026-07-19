import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../audit/data/audit_repository.dart';
import '../domain/stock_math.dart';

/// Стандартный набор категорий товаров склада — используется как «затравка»,
/// пока справочник [product_categories] пуст, чтобы выпадающий список никогда не
/// был пустым. Записывается в базу через [CategoriesRepository.seedDefaults]
/// (в т.ч. автоматически при первом добавлении своей категории).
const List<String> kDefaultProductCategories = [
  'Расходники',
  'Реактивы',
  'Медикаменты',
  'Прочее',
];

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(FirebaseFirestore.instance),
);

/// Названия категорий товаров для выпадающего списка (keep-alive — переживает
/// уход с экрана; обновляется вручную через `ref.invalidate(...)` после
/// добавления новой категории). Если справочник пуст — отдаёт стандартный набор
/// [kDefaultProductCategories], поэтому список никогда не бывает пустым.
final productCategoriesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(categoriesRepositoryProvider).list(),
);

/// Справочник категорий товаров в **Firestore** (коллекция `product_categories`)
/// — без бэкенда, клиент пишет/читает напрямую. Документ: `{name, created_by,
/// created_at}`. Каждое добавление штампует автора/время и пишет запись аудита
/// через [logAudit] (best-effort: аудит никогда не роняет саму операцию).
class CategoriesRepository {
  CategoriesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('product_categories');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Названия категорий по алфавиту (регистронезависимо), без пустых и
  /// дубликатов. Пустой справочник → стандартный набор [kDefaultProductCategories]
  /// (его можно зафиксировать в базе через [seedDefaults]).
  Future<List<String>> list() async {
    final snap = await _col
        .where('clinic_id', isEqualTo: ClinicScope.current)
        .get();
    if (snap.docs.isEmpty) return _sortedDefaults();

    final seen = <String>{};
    final names = <String>[];
    for (final d in snap.docs) {
      final name = (d.data()['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) names.add(name);
    }
    // На случай справочника из одних пустых имён — не оставляем список пустым.
    if (names.isEmpty) return _sortedDefaults();
    names.sort(_compareCi);
    return names;
  }

  /// Добавляет категорию: обрезает пробелы, пропускает регистронезависимый
  /// дубликат (в т.ч. совпадающий со стандартным значением). Штампует
  /// `created_by`/`created_at` и пишет аудит. Возвращает КАНОНИЧЕСКОЕ имя
  /// категории (уже существующее — если это дубликат, иначе — вновь добавленное),
  /// чтобы вызывающий код мог сразу выбрать его в списке.
  Future<String> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const WarehouseException('Введите название категории.');
    }

    // Первое добавление в пустой справочник — заодно фиксируем стандартный набор,
    // чтобы значения по умолчанию не «исчезли» из выпадающего списка.
    final snap = await _col
        .where('clinic_id', isEqualTo: ClinicScope.current)
        .get();
    if (snap.docs.isEmpty) {
      await seedDefaults();
    }

    // Регистронезависимая защита от дубликата (учитываем и стандартные значения).
    final existing = await list();
    for (final c in existing) {
      if (c.toLowerCase() == trimmed.toLowerCase()) return c;
    }

    final ref = await _col.add(<String, dynamic>{
      'clinic_id': ClinicScope.current,
      'name': trimmed,
      'created_by': _uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'inventory',
      entity: 'category',
      entityId: ref.id,
      action: 'create',
      summary: 'Добавлена категория: $trimmed',
    );
    return trimmed;
  }

  /// Записывает стандартный набор [kDefaultProductCategories] в справочник —
  /// только те значения, которых там ещё нет (регистронезависимо), одной пачкой.
  /// Идемпотентна: повторный вызов ничего не дублирует. Пишет аудит.
  Future<void> seedDefaults() async {
    final snap = await _col
        .where('clinic_id', isEqualTo: ClinicScope.current)
        .get();
    final existing = snap.docs
        .map((d) => (d.data()['name'] as String? ?? '').trim().toLowerCase())
        .toSet();
    final missing = kDefaultProductCategories
        .where((c) => !existing.contains(c.toLowerCase()))
        .toList();
    if (missing.isEmpty) return;

    final batch = _db.batch();
    for (final name in missing) {
      batch.set(_col.doc(), <String, dynamic>{
        'clinic_id': ClinicScope.current,
        'name': name,
        'created_by': _uid,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await logAudit(
      module: 'inventory',
      entity: 'category',
      action: 'create',
      summary: 'Добавлены стандартные категории (${missing.length})',
    );
  }

  List<String> _sortedDefaults() {
    final defaults = List<String>.from(kDefaultProductCategories);
    defaults.sort(_compareCi);
    return defaults;
  }

  static int _compareCi(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}
