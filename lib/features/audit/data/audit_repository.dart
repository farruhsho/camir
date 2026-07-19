import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../domain/audit_entry.dart';

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(FirebaseFirestore.instance),
);

/// Последние записи «Журнала изменений», свежие сверху.
///
/// keep-alive (top-level, НЕ autoDispose) — журнал читают из нескольких мест,
/// незачем перечитывать при каждом входе на экран. Обновление — через
/// `ref.invalidate(auditLogProvider)` (кнопка «Обновить» на экране).
final auditLogProvider = FutureProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).recent(),
);

/// Доступ к журналу аудита в **Firestore** (коллекция `audit`) — только чтение
/// последних записей. Запись выполняется top-level функцией [logAudit] (журнал
/// append-only: правка/удаление запрещены правилами Firestore).
class AuditRepository {
  AuditRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('audit');

  /// Последние [limit] записей журнала, свежие сверху (по `created_at`).
  Future<List<AuditEntry>> recent({int limit = 300}) async {
    final snap = await _col
        .where('clinic_id', isEqualTo: ClinicScope.current)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => AuditEntry.fromMap({...d.data(), 'id': d.id}))
        .toList();
  }
}

/// Пишет запись в журнал аудита (коллекция `audit`).
///
/// **Best-effort по контракту:** обёрнута в try/catch и НИКОГДА не бросает —
/// падение аудита не должно ломать основную мутацию, которую он логирует.
/// Штампует автора (`created_by` = текущий `FirebaseAuth` uid, `created_by_name`
/// — best-effort из staff/{uid}) и `created_at` серверным временем.
///
/// [action]: create|update|delete|void|refund|status_change|role_change|
/// disable|archive.
Future<void> logAudit({
  required String module,
  required String entity,
  String? entityId,
  required String action,
  String? summary,
  Map<String, dynamic>? changes,
}) async {
  try {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final name = await _resolveName(db, uid);
    await db.collection('audit').add(<String, dynamic>{
      'clinic_id': ClinicScope.current,
      'module': module,
      'entity': entity,
      if (entityId != null && entityId.isNotEmpty) 'entity_id': entityId,
      'action': action,
      if (summary != null && summary.isNotEmpty) 'summary': summary,
      if (changes != null && changes.isNotEmpty) 'changes': changes,
      'created_by': uid,
      if (name != null && name.isNotEmpty) 'created_by_name': name,
      'created_at': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Best-effort: аудит НИКОГДА не должен ломать логируемую операцию.
  }
}

/// Имя автора для журнала: `full_name` из staff/{uid}, иначе сам uid.
/// Best-effort — при любой ошибке возвращаем uid (или null, если не залогинен).
/// Сотрудник по правилам Firestore может читать только свой профиль staff/{uid},
/// что и требуется (логируем всегда от имени текущего пользователя).
Future<String?> _resolveName(FirebaseFirestore db, String? uid) async {
  if (uid == null) return null;
  try {
    final doc = await db.collection('staff').doc(uid).get();
    final name = (doc.data()?['full_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {
    // Нет доступа/офлайн — откатываемся на uid.
  }
  return uid;
}
