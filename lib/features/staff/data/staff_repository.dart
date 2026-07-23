import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../../core/auth/role_catalog.dart';
import '../../../firebase_options.dart';
import '../../audit/data/audit_repository.dart';
import '../domain/staff_member.dart';

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(FirebaseFirestore.instance, FirebaseAuth.instance),
);

/// Список сотрудников: платформенный админ — все клиники, клинический
/// супер-админ — только своя (гейт в firestore.rules и в UI).
final staffListProvider = FutureProvider<List<StaffMember>>(
  (ref) => ref.watch(staffRepositoryProvider).list(),
);

/// Управление персоналом «Цадмир» в **Firestore** (коллекция `staff`).
///
/// Ключевая тонкость — завести НОВЫЙ Auth-аккаунт из клиента, НЕ разлогинив
/// текущего супер-админа. Firebase не даёт создать чужого пользователя обычным
/// SDK (createUser сразу логинит вас ИМ). Обходим это **вторичным
/// Firebase-приложением**: инициализируем отдельный [FirebaseApp], создаём в нём
/// пользователя, забираем uid, выходим и удаляем приложение — основная сессия
/// (супер-админ) остаётся нетронутой. Профиль staff/{uid} пишем уже из основной
/// сессии (firestore.rules разрешают create/update супер-админу).
class StaffRepository {
  StaffRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _db.collection('staff');

  /// Сотрудники, свежие сверху. Платформенный администратор видит ВСЕХ (без
  /// фильтра); клинический супер-админ — только СВОЮ клинику (фильтр по
  /// `clinic_id`; правила Firestore дублируют это на сервере). Сортируем на
  /// КЛИЕНТЕ, а не через `orderBy('created_at')`, — иначе документы без этого
  /// поля (напр. первый супер-админ, заведённый вручную в консоли) выпали бы
  /// из списка.
  Future<List<StaffMember>> list() async {
    Query<Map<String, dynamic>> query = _staff;
    if (!ClinicScope.isPlatformAdmin) {
      query = query.where('clinic_id', isEqualTo: ClinicScope.current);
    }
    final snap = await query.get();
    final items = snap.docs
        .map((d) => StaffMember.fromMap({...d.data(), 'uid': d.id}))
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

  /// Заводит сотрудника В КЛИНИКУ [clinicId]: создаёт Auth-аккаунт во вторичном
  /// приложении и пишет профиль staff/{uid} с полем `clinic_id`. Клинический
  /// супер-админ может передать только свою клинику (правила отвергнут чужую);
  /// платформенный администратор — любую. Если запись профиля не удалась —
  /// ОТКАТывает осиротевший Auth-аккаунт (иначе email навсегда «занят», а
  /// завести его из клиента повторно нельзя — нет Admin SDK). Возвращает
  /// [StaffMember]; бросает [StaffException] с RU-текстом при ошибке.
  Future<StaffMember> createStaff({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String clinicId,
  }) async {
    final normEmail = email.trim();
    final normName = fullName.trim();
    final permissions = permissionsForRole(role);
    final isSuper = isSuperRole(role);
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
          'permissions': permissions,
          'is_superuser': isSuper,
          'disabled': false,
          'clinic_id': clinicId,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': createdBy,
        });
      } catch (_) {
        // Профиль не записался — удаляем осиротевший Auth-аккаунт (сессия
        // вторичного приложения ещё залогинена как этот пользователь).
        try {
          await newUser.delete();
        } catch (_) {}
        throw const StaffException(
          'Не удалось сохранить профиль сотрудника. Аккаунт отменён — '
          'повторите попытку.',
        );
      }
      await secondaryAuth.signOut();
      await logAudit(
        module: 'staff',
        entity: 'staff',
        entityId: uid,
        action: 'create',
        summary:
            'Заведён сотрудник «$normName» ($normEmail), роль: '
            '${role.isEmpty ? 'без роли' : role}',
      );
      return StaffMember(
        uid: uid,
        email: normEmail,
        fullName: normName,
        role: role,
        clinicId: clinicId,
        isSuperuser: isSuper,
      );
    } on FirebaseAuthException catch (e) {
      throw StaffException(_mapAuthError(e));
    } finally {
      // Чистим вторичное приложение, но НЕ маскируем исходную ошибку/результат.
      try {
        await app.delete();
      } catch (_) {}
    }
  }

  /// Меняет роль сотрудника (пересчитывает права и супер-флаг). Только супер-админ.
  Future<void> updateRole(String uid, String role) async {
    await _staff.doc(uid).update(<String, dynamic>{
      'role': role,
      'permissions': permissionsForRole(role),
      'is_superuser': isSuperRole(role),
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'staff',
      entity: 'staff',
      entityId: uid,
      action: 'role_change',
      summary:
          'Изменена роль сотрудника на «${role.isEmpty ? 'без роли' : role}»',
      changes: <String, dynamic>{'role': role},
    );
  }

  /// Точечно переопределяет ГРАНУЛЯРНЫЕ права сотрудника, НЕ трогая его роль
  /// (роль остаётся прежней; смена роли позже пересчитает права заново — см.
  /// [updateRole]). Платформенный владелец использует это, чтобы «донастроить»
  /// доступ поверх шаблона роли. Только супер-админ/владелец (гейт в
  /// firestore.rules).
  Future<void> updatePermissions(String uid, List<String> permissions) async {
    await _staff.doc(uid).update(<String, dynamic>{
      'permissions': permissions,
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'staff',
      entity: 'staff',
      entityId: uid,
      action: 'update',
      summary: 'Изменены права сотрудника (${permissions.length} шт.)',
      changes: <String, dynamic>{'permissions': permissions},
    );
  }

  /// Отзывает/возвращает доступ сотруднику (флаг `disabled`). Auth-аккаунт при
  /// этом не удаляется (для этого нужен Admin SDK); вход блокируется клиентом
  /// (`AuthRepository._userFromUid`) и может блокироваться правилами.
  Future<void> setDisabled(String uid, bool disabled) async {
    await _staff.doc(uid).update(<String, dynamic>{
      'disabled': disabled,
      'updated_by': _auth.currentUser?.uid,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'staff',
      entity: 'staff',
      entityId: uid,
      action: 'disable',
      summary: disabled
          ? 'Доступ сотруднику отозван'
          : 'Доступ сотруднику восстановлен',
      changes: <String, dynamic>{'disabled': disabled},
    );
  }

  /// Инициализирует (или переиспользует) вторичное Firebase-приложение — чтобы
  /// завести чужой Auth-аккаунт без разлогина текущего супер-админа.
  Future<FirebaseApp> _secondaryApp() async {
    try {
      return await Firebase.initializeApp(
        name: 'staffProvisioner',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // Предыдущее приложение не удалилось — переиспользуем его.
      if (e.code == 'duplicate-app') return Firebase.app('staffProvisioner');
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

/// Понятная пользователю ошибка управления персоналом (RU-текст в [message]).
class StaffException implements Exception {
  const StaffException(this.message);
  final String message;
  @override
  String toString() => message;
}
