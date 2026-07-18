import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_shell.dart';
import '../features/analyses/presentation/analyses_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/fibroscan/presentation/fibroscan_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/patients/presentation/patients_screen.dart';
import '../features/reception/presentation/reception_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/staff/presentation/staff_screen.dart';
import '../features/visits/presentation/queue_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/reception',
            builder: (_, _) => const ReceptionScreen(),
          ),
          GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
          GoRoute(path: '/patients', builder: (_, _) => const PatientsScreen()),
          // Фиброскан (эластография печени) и Анализы (лаборатория) — профильные
          // экраны «Цадмир». Гейтинг по правам fibroscan.write / analyses.write
          // через kAppDestinations + redirect.
          GoRoute(
            path: '/fibroscan',
            builder: (_, _) => const FibroscanScreen(),
          ),
          GoRoute(path: '/analyses', builder: (_, _) => const AnalysesScreen()),
          GoRoute(
            path: '/inventory',
            builder: (_, _) => const InventoryScreen(),
          ),
          // Управление персоналом — только супер-админ (гейт staff.manage).
          GoRoute(path: '/staff', builder: (_, _) => const StaffScreen()),
        ],
      ),
    ],
  );
});

/// Role-aware home: the first shell destination this user may see
/// (kAppDestinations order = priority). Falls back to /reception so an
/// account with no nav permissions still lands somewhere harmless.
String homeFor(AuthUser? user) {
  for (final d in kAppDestinations) {
    if (d.allowedFor(user)) return d.route;
  }
  return '/reception';
}

/// Bridges Riverpod auth state into GoRouter: re-evaluates redirects whenever
/// the auth status changes.
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authControllerProvider);
    final loc = state.matchedLocation;

    switch (auth.status) {
      case AuthStatus.unknown:
        return loc == '/splash' ? null : '/splash';
      case AuthStatus.unauthenticated:
        return loc == '/login' ? null : '/login';
      case AuthStatus.authenticated:
        final user = auth.user;
        if (loc == '/login' || loc == '/splash') return homeFor(user);
        // Permission guard: navigating to a screen the user may not see
        // (deep link, stale bookmark) sends them home instead of a 403 page.
        for (final d in kAppDestinations) {
          if (loc == d.route || loc.startsWith('${d.route}/')) {
            return d.allowedFor(user) ? null : homeFor(user);
          }
        }
        return null;
    }
  }
}
