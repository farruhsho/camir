import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../../core/auth/role_catalog.dart';
import '../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance),
);

/// Аутентификация на **Firebase** (email/пароль) + профиль сотрудника в
/// Firestore (коллекция `staff`, документ по uid). Без бэкенда и JWT: клиент
/// логинится напрямую, а роль читает из `staff/{uid}.role` и раскрывает в
/// permission-коды через [permissionsForRole].
class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _db.collection('staff');

  /// Вход по email/паролю. После успешной аутентификации собирает [AuthUser]
  /// из профиля staff/{uid}. Кидает [AuthException] с RU-текстом при ошибке.
  Future<AuthUser> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = await _userFromUid(cred.user!.uid, cred.user!.email);
      // Best-effort: досоздать поля прав в staff/{uid}, чтобы firestore.rules
      // могли гейтить по is_superuser/permissions. Пишется, только если поля
      // отличаются; под прод-правилами разрешено лишь супер-админам (иначе
      // отказ проглатывается, права уже проставлены при повышении через консоль).
      await _ensureStaffFields(cred.user!.uid, user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Самостоятельная регистрация сотрудника: создаёт учётку Firebase и
  /// **обезоруженный** профиль staff/{uid} {full_name, email, role='' ,
  /// permissions=[], is_superuser=false}. Новый аккаунт НЕ получает прав —
  /// роль выдаёт супер-админ через консоль (см. firestore.rules → staff.create
  /// разрешён только «обезоруженным» документам). Роль из UI НЕ принимается,
  /// чтобы закрыть самоэскалацию привилегий.
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final normEmail = email.trim();
    final normName = fullName.trim();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: normEmail,
        password: password,
      );
      final uid = cred.user!.uid;
      await _staff.doc(uid).set(<String, dynamic>{
        'full_name': normName,
        'email': normEmail,
        'role': '',
        'permissions': <String>[],
        'is_superuser': false,
        // Самостоятельная регистрация не даёт клиники: без неё нет доступа к
        // данным, пока клинику не назначит администратор. Платформенный флаг
        // не пишем вовсе (по умолчанию false).
        'clinic_id': '',
        'created_at': FieldValue.serverTimestamp(),
        'created_by': uid,
      });
      return AuthUser(
        id: uid,
        email: normEmail,
        fullName: normName,
        roles: const <String>[],
        permissions: const <String>[],
        isSuperuser: false,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// ⚠️ ВРЕМЕННО (УБРАТЬ вместе с кнопкой на входе и TEMP-строкой в
  /// firestore.rules): саморегистрация СУПЕР-АДМИНА. Создаёт учётку и профиль
  /// staff/{uid} с полным доступом (супер + платформенный) в клинике по
  /// умолчанию, входит сразу. Дыра самоэскалации — только для первичной
  /// настройки/тестов.
  Future<AuthUser> registerSuperadminTemp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final normEmail = email.trim();
    final normName = fullName.trim();
    // Супер получает clinics.manage динамически (как в _userFromUid для
    // платформенных админов) — иначе не увидит раздел «Клиники» в этой сессии.
    final perms = <String>[...permissionsForRole(roleSuperadmin), 'clinics.manage'];
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: normEmail,
        password: password,
      );
      final uid = cred.user!.uid;
      await _staff.doc(uid).set(<String, dynamic>{
        'full_name': normName,
        'email': normEmail,
        'role': roleSuperadmin,
        'permissions': perms,
        'is_superuser': true,
        'is_platform_admin': true,
        'disabled': false,
        'clinic_id': kDefaultClinicId,
        'created_at': FieldValue.serverTimestamp(),
        'created_by': uid,
      });
      ClinicScope.current = kDefaultClinicId;
      ClinicScope.isPlatformAdmin = true;
      return AuthUser(
        id: uid,
        email: normEmail,
        fullName: normName,
        roles: <String>[roleSuperadmin],
        permissions: perms,
        isSuperuser: true,
        clinicId: kDefaultClinicId,
        isPlatformAdmin: true,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Фиксированные ТЕСТОВЫЕ аккаунты (email/пароль) для быстрого входа по роли.
  /// (email, пароль, отображаемое ФИО).
  static const Map<String, (String, String, String)> _testAccounts =
      <String, (String, String, String)>{
        roleReception: (
          'receptsiya@cadmir.local',
          'cadmir123',
          'Ресепшен (тест)',
        ),
        roleSuperadmin: (
          'superadmin@cadmir.local',
          'cadmir123',
          'Супер-админ (тест)',
        ),
      };

  /// Быстрый вход для ТЕСТИРОВАНИЯ через реальный аккаунт Firebase (email/пароль).
  /// При первом клике аккаунт создаётся автоматически (+ профиль staff/{uid}),
  /// при последующих — просто входит. Работает при включённом Email/Password.
  Future<AuthUser> loginAsRole(String role) async {
    final acct = _testAccounts[role];
    final email = acct?.$1 ?? '$role@cadmir.local';
    final password = acct?.$2 ?? 'cadmir123';
    final name = acct?.$3 ?? role;
    try {
      UserCredential cred;
      try {
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // Аккаунта ещё нет — создаём его на лету.
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          cred = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }
      final uid = cred.user!.uid;
      try {
        await _staff.doc(uid).set(<String, dynamic>{
          'full_name': name,
          'email': email,
          'role': role,
          // Права/супер-флаг пишем и здесь, чтобы firestore.rules могли гейтить
          // по ним. Под прод-правилами создание super-тест-аккаунта отклонится
          // (staff.create требует is_superuser==false) — это ожидаемо: быстрый
          // вход работает только под dev-правилами (firestore.rules.dev).
          'permissions': permissionsForRole(role),
          'is_superuser': isSuperRole(role),
          // Отладочный вход всегда попадает в клинику по умолчанию — в неё же
          // мигрированы существующие данные.
          'clinic_id': kDefaultClinicId,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Профиль не записался (напр. правила Firestore ещё закрыты) — для
        // быстрого входа роль берём из клиентского каталога, вход не блокируем.
      }
      // Активная клиника сессии — по умолчанию (даже если запись профиля выше
      // не прошла под закрытыми правилами, отладочный вход работает с ней).
      ClinicScope.current = kDefaultClinicId;
      ClinicScope.isPlatformAdmin = false;
      return AuthUser(
        id: uid,
        email: email,
        fullName: name,
        roles: <String>[role],
        permissions: permissionsForRole(role),
        isSuperuser: isSuperRole(role),
        clinicId: kDefaultClinicId,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Текущий вошедший сотрудник по сохранённой Firebase-сессии, либо `null`,
  /// если никто не залогинен.
  Future<AuthUser?> currentUser() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    return _userFromUid(u.uid, u.email);
  }

  Future<void> logout() async {
    ClinicScope.clear();
    await _auth.signOut();
  }

  /// Собирает [AuthUser] из документа staff/{uid}. Понятная ошибка, если
  /// профиль/роль не заведены. Супер-флаг берётся ИСКЛЮЧИТЕЛЬНО из серверного
  /// поля `is_superuser` (его выставляет супер-админ через консоль) — НЕ из
  /// имени роли: иначе самостоятельно записанная роль `Супер-админ` подняла бы
  /// клиентскую сессию до супера (см. защиту self-create в firestore.rules).
  /// Супер входит даже без заполненного `role` (bootstrap первого админа).
  Future<AuthUser> _userFromUid(String uid, String? email) async {
    final doc = await _staff.doc(uid).get();
    final data = doc.data();
    if (data == null) {
      throw const AuthException(
        'Профиль сотрудника не найден. Обратитесь к администратору для '
        'создания учётной записи и назначения роли.',
      );
    }
    if (data['disabled'] == true) {
      throw const AuthException(
        'Учётная запись отключена. Обратитесь к администратору.',
      );
    }
    final role = (data['role'] as String?)?.trim() ?? '';
    final isSuper = data['is_superuser'] == true;
    // Супер-админ = полный управляющий: автоматически получает права
    // платформенного администратора (управление всеми клиниками и аккаунтами).
    // Изоляция ДАННЫХ пациентов между клиниками при этом сохраняется — она
    // держится на фильтре `clinic_id` в репозиториях и правилах данных, не на
    // этом флаге (он открывает только реестр клиник и кросс-клиничный персонал).
    final isPlatformAdmin = data['is_platform_admin'] == true || isSuper;
    final clinicId = (data['clinic_id'] as String?)?.trim() ?? '';
    // Мульти-клиничность: без назначенной клиники нет доступа к данным. Супер и
    // платформенный админ входят и без клиники (bootstrap / управление
    // клиниками); их операционные запросы всё равно ограничены ClinicScope.
    if (clinicId.isEmpty && !isSuper && !isPlatformAdmin) {
      throw const AuthException(
        'Сотруднику не назначена клиника. Обратитесь к администратору.',
      );
    }
    // Роль обязательна для обычных сотрудников. Супер и платформенный админ
    // входят и без роли (bootstrap первого админа / управление клиниками).
    if (role.isEmpty && !isSuper && !isPlatformAdmin) {
      throw const AuthException(
        'Сотруднику не назначена роль. Обратитесь к администратору.',
      );
    }
    // Платформенному админу динамически выдаём право на управление клиниками —
    // в каталоге ролей оно НЕ прописано (см. role_catalog.dart).
    final basePerms = permissionsForRole(role);
    final permissions = isPlatformAdmin && !basePerms.contains('clinics.manage')
        ? <String>[...basePerms, 'clinics.manage']
        : basePerms;
    // Проставляем активную клинику сессии ПЕРЕД возвратом: репозитории берут её
    // из ClinicScope для фильтрации/штампа clinic_id.
    ClinicScope.current = clinicId.isEmpty ? null : clinicId;
    ClinicScope.isPlatformAdmin = isPlatformAdmin;
    return AuthUser(
      id: uid,
      email: (data['email'] as String?) ?? email ?? '',
      fullName: (data['full_name'] as String?) ?? '',
      roles: role.isEmpty ? const <String>[] : <String>[role],
      permissions: permissions,
      isSuperuser: isSuper,
      clinicId: clinicId.isEmpty ? null : clinicId,
      isPlatformAdmin: isPlatformAdmin,
    );
  }

  /// Best-effort синхронизация полей прав в staff/{uid} (role, permissions,
  /// is_superuser), чтобы firestore.rules могли гейтить по ним. Пишет только при
  /// расхождении и НЕ роняет вход при отказе (под прод-правилами обновлять чужой/
  /// свой staff-док может лишь супер-админ; обычным сотрудникам права уже
  /// проставил супер-админ при повышении через консоль). Штампует
  /// updated_by/updated_at по контракту.
  Future<void> _ensureStaffFields(String uid, AuthUser user) async {
    try {
      final snap = await _staff.doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};
      final storedPerms = (data['permissions'] as List?)?.cast<Object?>();
      final storedSuper = data['is_superuser'] == true;
      final wantPerms = user.permissions;
      final samePerms =
          storedPerms != null &&
          storedPerms.length == wantPerms.length &&
          storedPerms.map((e) => '$e').toSet().containsAll(wantPerms);
      if (samePerms && storedSuper == user.isSuperuser) return; // уже синхронно
      await _staff.doc(uid).set(<String, dynamic>{
        'role': user.roles.isEmpty ? '' : user.roles.first,
        'permissions': wantPerms,
        'is_superuser': user.isSuperuser,
        'updated_by': uid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Отказ правил/офлайн — вход не блокируем.
    }
  }

  /// Оборачивает [FirebaseAuthException] в понятное пользователю RU-сообщение.
  AuthException _mapAuthError(FirebaseAuthException e) {
    final message = switch (e.code) {
      'invalid-email' => 'Некорректный email.',
      'user-disabled' =>
        'Учётная запись отключена. Обратитесь к администратору.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Неверный email или пароль.',
      'email-already-in-use' => 'Этот email уже занят.',
      'weak-password' => 'Слишком простой пароль (минимум 6 символов).',
      'operation-not-allowed' =>
        'Вход по email/паролю отключён в настройках Firebase.',
      'too-many-requests' => 'Слишком много попыток. Повторите позже.',
      'network-request-failed' =>
        'Нет связи с сервером. Проверьте интернет-соединение.',
      _ => e.message ?? 'Ошибка аутентификации (${e.code}).',
    };
    return AuthException(message);
  }
}

/// Понятная пользователю ошибка входа/регистрации (RU-текст в [message]).
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
