import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../audit/data/audit_repository.dart';
import '../domain/service_item.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>(
  (ref) => ServicesRepository(FirebaseFirestore.instance),
);

/// Активные услуги (для выбора в форме оплаты).
final activeServicesProvider = FutureProvider<List<ServiceItem>>(
  (ref) => ref.watch(servicesRepositoryProvider).list(activeOnly: true),
);

/// Все услуги (для экрана управления прайс-листом).
final allServicesProvider = FutureProvider<List<ServiceItem>>(
  (ref) => ref.watch(servicesRepositoryProvider).list(),
);

/// Прайс-лист услуг «Цадмир» в **Firestore** (коллекция `services`). Сортировка
/// по названию (single-field индекс создаётся автоматически). Цена — KGS «сом».
class ServicesRepository {
  ServicesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('services');

  Future<List<ServiceItem>> list({bool activeOnly = false}) async {
    final snap = await _col.orderBy('name').get();
    var items = snap.docs
        .map((d) => ServiceItem.fromMap({...d.data(), 'id': d.id}))
        .toList();
    if (activeOnly) items = items.where((s) => s.active).toList();
    return items;
  }

  Future<void> add({
    required String name,
    required num price,
    String? category,
  }) async {
    final ref = await _col.add(<String, dynamic>{
      'name': name.trim(),
      'price': price,
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      'active': true,
      'created_by': FirebaseAuth.instance.currentUser?.uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'services',
      entity: 'service',
      entityId: ref.id,
      action: 'create',
      summary:
          'Добавлена услуга «${name.trim()}» · ${formatMoney(price.toString())}',
    );
  }

  Future<void> update(
    String id, {
    required String name,
    required num price,
    String? category,
  }) async {
    await _col.doc(id).update(<String, dynamic>{
      'name': name.trim(),
      'price': price,
      'category': (category == null || category.trim().isEmpty)
          ? FieldValue.delete()
          : category.trim(),
      'updated_by': FirebaseAuth.instance.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'services',
      entity: 'service',
      entityId: id,
      action: 'update',
      summary:
          'Изменена услуга «${name.trim()}» · ${formatMoney(price.toString())}',
    );
  }

  Future<void> setActive(String id, bool active) async {
    await _col.doc(id).update(<String, dynamic>{
      'active': active,
      'updated_by': FirebaseAuth.instance.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'services',
      entity: 'service',
      entityId: id,
      action: 'status_change',
      summary: active ? 'Услуга включена' : 'Услуга отключена',
      changes: <String, dynamic>{'active': active},
    );
  }
}
