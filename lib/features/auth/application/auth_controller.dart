import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clinics/data/clinics_repository.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState(this.status, [this.user]);

  final AuthStatus status;
  final AuthUser? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Restore any persisted Firebase session on startup.
    Future.microtask(_restore);
    return const AuthState(AuthStatus.unknown);
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Смена сессии (вход/восстановление/выход) меняет `ClinicScope.current` —
  /// сбрасываем keep-alive-кэш документа активной клиники, чтобы сайдбар и
  /// модульная навигация «перевоплотились» под клинику нового пользователя.
  void _reloadClinicIdentity() => ref.invalidate(currentClinicProvider);

  /// On startup: if Firebase already has a signed-in user (and their staff
  /// profile resolves), go straight to authenticated; otherwise show login.
  Future<void> _restore() async {
    try {
      final user = await _repo.currentUser();
      state = user != null
          ? AuthState(AuthStatus.authenticated, user)
          : const AuthState(AuthStatus.unauthenticated);
    } catch (_) {
      // No session, missing profile, or offline — land on the login screen.
      state = const AuthState(AuthStatus.unauthenticated);
    }
    _reloadClinicIdentity();
  }

  /// Throws [AuthException] on failure (handled by the login screen).
  Future<void> login(String email, String password) async {
    final user = await _repo.login(email, password);
    state = AuthState(AuthStatus.authenticated, user);
    _reloadClinicIdentity();
  }

  /// Registers a new **neutered** staff account (no role, no permissions) and
  /// signs it back out — access is granted later by a superadmin via console.
  /// The login screen shows a confirmation note. Throws [AuthException] on
  /// failure (handled by the login screen).
  Future<void> signUp(String email, String password, String fullName) async {
    await _repo.signUp(email: email, password: password, fullName: fullName);
    // Новый аккаунт создан без прав — сразу выходим, доступ выдаёт админ.
    await _repo.logout();
    state = const AuthState(AuthStatus.unauthenticated);
    _reloadClinicIdentity();
  }

  /// ⚠️ ВРЕМЕННО (убрать вместе с кнопкой): саморегистрация супер-админа —
  /// создаёт учётку с полным доступом и сразу входит. Throws [AuthException].
  Future<void> registerSuperadminTemp(
    String email,
    String password,
    String fullName,
  ) async {
    final user = await _repo.registerSuperadminTemp(
      email: email,
      password: password,
      fullName: fullName,
    );
    state = AuthState(AuthStatus.authenticated, user);
    _reloadClinicIdentity();
  }

  /// Быстрый вход по роли (для тестирования) — анонимный Firebase-вход + роль.
  /// Throws [AuthException] on failure.
  Future<void> loginAsRole(String role) async {
    final user = await _repo.loginAsRole(role);
    state = AuthState(AuthStatus.authenticated, user);
    _reloadClinicIdentity();
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(AuthStatus.unauthenticated);
    _reloadClinicIdentity();
  }
}
