import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }

  /// Throws [AuthException] on failure (handled by the login screen).
  Future<void> login(String email, String password) async {
    final user = await _repo.login(email, password);
    state = AuthState(AuthStatus.authenticated, user);
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
  }

  /// Быстрый вход по роли (для тестирования) — анонимный Firebase-вход + роль.
  /// Throws [AuthException] on failure.
  Future<void> loginAsRole(String role) async {
    final user = await _repo.loginAsRole(role);
    state = AuthState(AuthStatus.authenticated, user);
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}
