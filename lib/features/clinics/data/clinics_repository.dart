import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../../core/auth/clinic_types.dart';
import '../../../core/auth/role_catalog.dart';
import '../../../firebase_options.dart';
import '../../audit/data/audit_repository.dart';
import '../domain/clinic.dart';

final clinicsRepositoryProvider = Provider<ClinicsRepository>(
  (ref) => ClinicsRepository(FirebaseFirestore.instance, FirebaseAuth.instance),
);

/// Реестр ВСЕХ клиник (виден только платформенному администратору — гейт в
/// firestore.rules и в UI). keep-alive (top-level, НЕ autoDispose): список
/// клиник меняется редко, перечитываем через `ref.invalidate(clinicsProvider)`.
final clinicsProvider = FutureProvider<List<Clinic>>(
  (ref) => ref.watch(clinicsRepositoryProvider).list(),
);

/// Клиника ТЕКУЩЕЙ сессии (`clinics/{ClinicScope.current}`) — по ней app_shell
/// показывает название + специальность в сайдбаре и фильтрует пункты меню по
/// включённым модулям. `null`, пока не выполнен вход / клиника не назначена.
///
/// Точечный doc-get (НЕ query) — правила Firestore разрешают любому вошедшему
/// сотруднику читать документ СВОЕЙ клиники (проверка isActive()), тогда как
/// листинг реестра доступен только платформенному админу.
///
/// keep-alive: перечитывается через `ref.invalidate(currentClinicProvider)` —
/// APP-агент дёргает его в auth-потоках (после входа/выхода), CLINICS-экран —
/// после изменения модулей/типа/названия.
final currentClinicProvider = FutureProvider<Clinic?>((ref) async {
  final id = ClinicScope.current;
  if (id == null) return null;
  final doc = await FirebaseFirestore.instance
      .collection('clinics')
      .doc(id)
      .get();
  final data = doc.data();
  if (!doc.exists || data == null) return null;
  return Clinic.fromMap(<String, dynamic>{...data, 'id': doc.id});
});

/// Управление реестром клиник в **Firestore** (коллекция `clinics`) и
/// провижининг первого администратора каждой клиники.
///
/// ВАЖНО: коллекция `clinics` — это РЕЕСТР арендаторов, а не операционные данные
/// клиники, поэтому она НЕ фильтруется по `clinic_id` (её читает/пишет только
/// платформенный администратор; правила Firestore это гейтят). Изоляция
/// `clinic_id` применяется ко всем ОСТАЛЬНЫМ коллекциям, но не к самому реестру.
///
/// Заведение первого админа клиники повторяет приём из [StaffRepository]: чтобы
/// создать чужой Auth-аккаунт, не разлогинив платформенного администратора,
/// используется ВТОРИЧНОЕ Firebase-приложение (`clinicProvisioner`). Профиль
/// `staff/{uid}` пишется уже из ОСНОВНОЙ сессии.
class ClinicsRepository {
  ClinicsRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _clinics =>
      _db.collection('clinics');

  CollectionReference<Map<String, dynamic>> get _staff =>
      _db.collection('staff');

  /// Все клиники, свежие сверху. Сортируем на КЛИЕНТЕ (а не `orderBy`), т.к.
  /// клиника по умолчанию (`default`, заведённая при миграции) может не иметь
  /// поля `created_at` — иначе она выпала бы из выборки.
  Future<List<Clinic>> list() async {
    final snap = await _clinics.get();
    final items = snap.docs
        .map((d) => Clinic.fromMap({...d.data(), 'id': d.id}))
        .toList();
    items.sort((a, b) {
      final ax = a.createdAt;
      final bx = b.createdAt;
      if (ax == null && bx == null) return 0;
      if (ax == null) return 1; // без даты — в конец
      if (bx == null) return -1;
      return bx.compareTo(ax); // свежие сверху
    });
    return items;
  }

  /// Создаёт клинику (doc auto-id) и возвращает её id (он же будущий
  /// `clinic_id` данных этой клиники). Штампует `created_by`/`created_at`.
  ///
  /// [type] — ключ профиля из `kClinicTypes`; вместе с ним сохраняются
  /// подзаголовок специальности и ШАБЛОН включённых модулей этого профиля
  /// (дальше модули можно точечно менять через [setModules]).
  Future<String> create({required String name, required String type}) async {
    final normName = name.trim();
    final typeInfo = clinicTypeFor(type);
    final ref = await _clinics.add(<String, dynamic>{
      'name': normName,
      'type': typeInfo.key,
      'subtitle': typeInfo.subtitle,
      'modules': _orderedModules(typeInfo.modules),
      'active': true,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': _auth.currentUser?.uid,
    });
    await logAudit(
      module: 'clinics',
      entity: 'clinic',
      entityId: ref.id,
      action: 'create',
      summary: 'Создана клиника «$normName» (${typeInfo.label})',
    );
    return ref.id;
  }

  /// Переименовывает клинику и/или меняет её профиль (тип).
  ///
  /// При СМЕНЕ типа подзаголовок и модули сбрасываются на шаблон нового
  /// профиля (UI предупреждает об этом через confirmDialog). Если переданный
  /// [type] совпадает с текущим — подзаголовок/модули НЕ трогаем (ручные
  /// настройки модулей сохраняются).
  Future<void> updateClinic(String id, {String? name, String? type}) async {
    final data = <String, dynamic>{
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    };
    final changes = <String, dynamic>{};
    final parts = <String>[];

    final normName = name?.trim();
    if (normName != null && normName.isNotEmpty) {
      data['name'] = normName;
      changes['name'] = normName;
      parts.add('название: «$normName»');
    }

    if (type != null) {
      // Читаем текущий тип, чтобы сбрасывать шаблон ТОЛЬКО при реальной смене
      // (иначе повторное сохранение затёрло бы ручную настройку модулей).
      final snap = await _clinics.doc(id).get();
      final oldKey = clinicTypeFor(snap.data()?['type']?.toString()).key;
      final typeInfo = clinicTypeFor(type);
      if (typeInfo.key != oldKey) {
        data['type'] = typeInfo.key;
        data['subtitle'] = typeInfo.subtitle;
        data['modules'] = _orderedModules(typeInfo.modules);
        changes['type'] = typeInfo.key;
        parts.add('тип: ${typeInfo.label} (модули сброшены на шаблон)');
      }
    }

    if (changes.isEmpty) return; // Нечего менять — не пишем пустой update.
    await _clinics.doc(id).update(data);
    await logAudit(
      module: 'clinics',
      entity: 'clinic',
      entityId: id,
      action: 'update',
      summary: 'Изменена клиника — ${parts.join('; ')}',
      changes: changes,
    );
  }

  /// Точечно включает/выключает модули клиники (тумблеры экрана «Клиники»).
  Future<void> setModules(String id, Set<String> modules) async {
    final ordered = _orderedModules(modules);
    await _clinics.doc(id).update(<String, dynamic>{
      'modules': ordered,
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    final labels = ordered.map((m) => kModuleLabels[m] ?? m).join(', ');
    await logAudit(
      module: 'clinics',
      entity: 'clinic',
      entityId: id,
      action: 'update',
      summary: labels.isEmpty
          ? 'Модули клиники: все выключены'
          : 'Модули клиники: $labels',
      changes: <String, dynamic>{'modules': ordered},
    );
  }

  /// Набор модулей → список в каноническом порядке [kAllModules] (стабильный
  /// вид в Firestore/аудите; неизвестные ключи отбрасываются).
  List<String> _orderedModules(Set<String> modules) =>
      kAllModules.where(modules.contains).toList();

  /// Активирует / деактивирует клинику (флаг `active`). Данные сохраняются.
  Future<void> setActive(String id, bool active) async {
    await _clinics.doc(id).update(<String, dynamic>{
      'active': active,
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'clinics',
      entity: 'clinic',
      entityId: id,
      action: 'status_change',
      summary: active ? 'Клиника активирована' : 'Клиника деактивирована',
      changes: <String, dynamic>{'active': active},
    );
  }

  /// Заводит ПЕРВОГО администратора клиники [clinicId] — клинического
  /// супер-админа (`is_superuser: true`, `is_platform_admin: false`), чьи данные
  /// ограничены полем `clinic_id: clinicId`.
  ///
  /// Приём — как в [StaffRepository.createStaff]: создаём Auth-аккаунт во
  /// вторичном приложении (`clinicProvisioner`), пишем профиль `staff/{uid}` из
  /// основной сессии платформенного админа, выходим и удаляем вторичное
  /// приложение. Если запись профиля не удалась — ОТКАТываем осиротевший
  /// Auth-аккаунт (иначе email навсегда «занят»: Admin SDK на клиенте нет).
  Future<void> createClinicAdmin({
    required String clinicId,
    required String email,
    required String password,
    required String fullName,
  }) async {
    final normEmail = email.trim();
    final normName = fullName.trim();
    const role = roleSuperadmin;
    final permissions = permissionsForRole(role);
    final createdBy = _auth.currentUser?.uid;

    final app = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: app);
    try {
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: normEmail,
        password: password,
      );
      final newUser = cred.user!;
      final uid = newUser.uid;
      try {
        await _staff.doc(uid).set(<String, dynamic>{
          'full_name': normName,
          'email': normEmail,
          'role': role,
          'is_superuser': true,
          'disabled': false,
          'clinic_id': clinicId,
          'is_platform_admin': false,
          'permissions': permissions,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': createdBy,
        });
      } catch (_) {
        // Профиль не записался — удаляем осиротевший Auth-аккаунт (сессия
        // вторичного приложения ещё залогинена как этот пользователь).
        try {
          await newUser.delete();
        } catch (_) {}
        throw const ClinicException(
          'Не удалось сохранить профиль администратора клиники. Аккаунт '
          'отменён — повторите попытку.',
        );
      }
      await secondaryAuth.signOut();
      await logAudit(
        module: 'clinics',
        entity: 'staff',
        entityId: uid,
        action: 'create',
        summary: 'Заведён администратор клиники «$normName» ($normEmail)',
      );
    } on FirebaseAuthException catch (e) {
      throw ClinicException(_mapAuthError(e));
    } finally {
      // Чистим вторичное приложение, но НЕ маскируем исходную ошибку/результат.
      try {
        await app.delete();
      } catch (_) {}
    }
  }

  /// Инициализирует (или переиспользует) вторичное Firebase-приложение — чтобы
  /// завести чужой Auth-аккаунт без разлогина текущего платформенного админа.
  Future<FirebaseApp> _secondaryApp() async {
    try {
      return await Firebase.initializeApp(
        name: 'clinicProvisioner',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // Предыдущее приложение не удалилось — переиспользуем его.
      if (e.code == 'duplicate-app') return Firebase.app('clinicProvisioner');
      rethrow;
    }
  }

  String _mapAuthError(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => 'Некорректный email.',
    'email-already-in-use' => 'Этот email уже занят.',
    'weak-password' => 'Слишком простой пароль (минимум 6 символов).',
    'operation-not-allowed' =>
      'Вход по email/паролю отключён в настройках Firebase.',
    'network-request-failed' =>
      'Нет связи с сервером. Проверьте интернет-соединение.',
    _ => e.message ?? 'Не удалось создать аккаунт (${e.code}).',
  };
}

/// Понятная пользователю ошибка управления клиниками (RU-текст в [message]).
class ClinicException implements Exception {
  const ClinicException(this.message);
  final String message;
  @override
  String toString() => message;
}
