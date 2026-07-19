import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_user.dart';
import '../../features/clinics/data/clinics_repository.dart';
import '../../features/clinics/domain/clinic.dart';
import '../auth/clinic_types.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'cadmir_logo.dart';
import 'koz_icons.dart';
import 'koz_widgets.dart';

/// Maps a shell route to the prototype line-icon key (KozIcons). Unmapped
/// routes fall back to the destination's Material icon.
const Map<String, String> _navIconKey = {
  '/reception': 'reception',
  '/patients': 'patients',
  '/analyses': 'lab',
  '/inventory': 'inventory',
};

class AppDestination {
  const AppDestination(
    this.icon,
    this.selectedIcon,
    this.label,
    this.route, {
    this.permissions = const <String>[],
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  /// Any-of permission codes that reveal this destination (empty = public).
  final List<String> permissions;

  /// Visible when the user holds ANY of [permissions] (or it's public).
  bool allowedFor(AuthUser? user) =>
      permissions.isEmpty || permissions.any((p) => user?.can(p) ?? false);
}

/// Single source of truth for shell navigation AND the router's role-aware
/// landing/guard: the first destination the user is allowed to see is their
/// home screen after login. Order = landing priority per role.
const kAppDestinations = <AppDestination>[
  // Дашборд — аналитика для директора (KPI + выручка). Первым, чтобы
  // супер-админ/директор попадал сюда после входа. Право dashboard.view —
  // у Ресепшена его нет, поэтому он приземляется на Регистратуру.
  AppDestination(
    Icons.dashboard_outlined,
    Icons.dashboard,
    'Дашборд',
    '/dashboard',
    permissions: ['dashboard.view'],
  ),
  AppDestination(
    Icons.point_of_sale_outlined,
    Icons.point_of_sale,
    'Регистратура',
    '/reception',
    // Регистратура заводит приёмы → гейтинг по visits.create.
    permissions: ['visits.create'],
  ),
  // Касса — оплаты/возвраты (KGS «сом»), дневной кассовый отчёт.
  AppDestination(
    Icons.payments_outlined,
    Icons.payments,
    'Касса',
    '/payments',
    permissions: ['payments.read'],
  ),
  AppDestination(
    Icons.people_outline,
    Icons.people,
    'Пациенты',
    '/patients',
    permissions: ['patients.read'],
  ),
  // Фиброскан — эластография печени (гематологический центр «Цадмир»).
  AppDestination(
    Icons.monitor_heart_outlined,
    Icons.monitor_heart,
    'Фиброскан',
    '/fibroscan',
    permissions: ['fibroscan.write'],
  ),
  // Анализы — лабораторные исследования крови.
  AppDestination(
    Icons.bloodtype_outlined,
    Icons.bloodtype,
    'Анализы',
    '/analyses',
    permissions: ['analyses.write'],
  ),
  AppDestination(
    Icons.inventory_2_outlined,
    Icons.inventory_2,
    'Склад',
    '/inventory',
    permissions: ['inventory.read'],
  ),
  // Журнал аудита — история изменений (кто/что/когда). Право audit.read.
  AppDestination(
    Icons.history,
    Icons.history,
    'Журнал',
    '/audit',
    permissions: ['audit.read'],
  ),
  // Справочник анализов — каталог типов лабораторных исследований.
  AppDestination(
    Icons.science_outlined,
    Icons.science,
    'Справочник анализов',
    '/analysis-types',
    permissions: ['catalog.manage'],
  ),
  // Справочник фиброскана — референсные пороги стадий/степеней.
  AppDestination(
    Icons.tune,
    Icons.tune,
    'Справочник фиброскана',
    '/fibroscan-refs',
    permissions: ['catalog.manage'],
  ),
  // Сотрудники — только супер-админ. Право staff.manage нет ни у одной обычной
  // роли (нет в role_catalog), поэтому пункт виден лишь тем, у кого isSuperuser
  // (AuthUser.can(...) для супера истинно всегда).
  AppDestination(
    Icons.badge_outlined,
    Icons.badge,
    'Сотрудники',
    '/staff',
    permissions: ['staff.manage'],
  ),
  // Клиники — только платформенный админ. Право clinics.manage AUTH выдаёт
  // лишь платформенным админам, поэтому пункт скрыт от обычного клинического
  // супер-админа. НЕ спец-casим isSuperuser здесь: видимость держится строго на
  // permissions:["clinics.manage"], иначе клинический супер-админ увидел бы
  // раздел (AuthUser.can(...) для супера истинно для любого права).
  AppDestination(
    Icons.apartment_outlined,
    Icons.apartment,
    'Клиники',
    '/clinics',
    permissions: ['clinics.manage'],
  ),
];

/// Карта «маршрут → ключ модуля клиники» — ЕДИНЫЙ источник и для фильтрации
/// меню (AppShell), и для module-гарда роутера (router.dart). Маршруты БЕЗ
/// записи здесь (/staff, /clinics) — структурные: гейтятся только правами и не
/// отключаются модулями клиники. Оба справочника (/analysis-types и
/// /fibroscan-refs) — один модуль «Справочники» ([kModCatalog]).
const Map<String, String> kRouteModule = <String, String>{
  '/dashboard': kModDashboard,
  '/reception': kModReception,
  '/patients': kModPatients,
  '/analyses': kModAnalyses,
  '/fibroscan': kModFibroscan,
  '/inventory': kModInventory,
  '/payments': kModPayments,
  '/audit': kModAudit,
  '/analysis-types': kModCatalog,
  '/fibroscan-refs': kModCatalog,
};

/// Разрешён ли [route] модулями активной клиники. [modules] == null означает
/// «документ клиники ещё не загружен» — модульный фильтр НЕ применяем (ведём
/// себя как раньше, чтобы навигация не мигала на время загрузки).
bool routeEnabledForModules(String route, Set<String>? modules) {
  final module = kRouteModule[route];
  if (module == null) return true; // структурный раздел — не гейтится модулями
  if (modules == null) return true; // клиника не загружена — без фильтра
  return modules.contains(module);
}

/// Итоговый список пунктов навигации: права пользователя ∧ модули клиники.
/// Используется и сайдбаром/нижней навигацией (AppShell), и homeFor роутера —
/// чтобы «домашний» экран всегда был реально видимым пунктом меню.
List<AppDestination> allowedDestinations(AuthUser? user, Set<String>? modules) {
  return [
    for (final d in kAppDestinations)
      if (d.allowedFor(user) && routeEnabledForModules(d.route, modules)) d,
  ];
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '—';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1);
  }
  return parts[0][0] + parts[1][0];
}

/// Роли «Цадмир» хранятся уже в человеко-читаемом виде (`Супер-админ`,
/// `Ресепшен`), поэтому подпись — это просто первая роль пользователя.
String _roleLabel(List<String> roles) =>
    roles.isEmpty ? 'Сотрудник' : roles.first;

/// Ширина, ниже которой боковое меню (248px) неудобно — переключаемся на нижнюю
/// навигацию ([NavigationBar]).
const double _kNavBreakpoint = 840;

/// App chrome: the dark-teal «Clinic OS» sidebar (wide) or a bottom
/// [NavigationBar] (narrow) + the routed page body. Each routed screen keeps its
/// own Scaffold/AppBar (they inherit the new AppBarTheme); on narrow layouts the
/// body-level Scaffold here only hosts the bottom bar, so there are no nested
/// AppBars.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    // Активная клиника: имя/подзаголовок для шапки сайдбара + набор включённых
    // модулей. Пока документ не загружен (или клиника не назначена) — null:
    // фильтруем только по правам, как раньше (без мигания меню).
    final clinic = ref.watch(currentClinicProvider).valueOrNull;

    final destinations = allowedDestinations(user, clinic?.modules);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _kNavBreakpoint;
        if (narrow) {
          return _MobileScaffold(
            location: location,
            destinations: destinations,
            child: child,
          );
        }
        return Scaffold(
          body: Row(
            children: [
              _Sidebar(
                location: location,
                destinations: destinations,
                user: user,
                clinic: clinic,
              ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

/// Узкий макет: тело экрана + нижняя навигация. [NavigationBar] требует ≥2
/// пунктов — при одном (или отсутствии) доступном разделе показываем только
/// тело без нижнего бара.
class _MobileScaffold extends ConsumerWidget {
  const _MobileScaffold({
    required this.location,
    required this.destinations,
    required this.child,
  });

  final String location;
  final List<AppDestination> destinations;
  final Widget child;

  int _selectedIndex() {
    for (var i = 0; i < destinations.length; i++) {
      final d = destinations[i];
      if (location == d.route || location.startsWith('${d.route}/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void logout() => ref.read(authControllerProvider.notifier).logout();

    // Нет ни одного раздела (аккаунт без прав) — даём хотя бы кнопку выхода,
    // чтобы пользователь не застрял на мобильном макете без сайдбара.
    if (destinations.isEmpty) {
      return Scaffold(
        body: child,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: logout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Выйти'),
              ),
            ),
          ),
        ),
      );
    }

    // Последний пункт — «Выход» (индекс == destinations.length): он не
    // выбирается, а вызывает logout(). Так на мобиле есть выход из аккаунта.
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) {
          if (i < destinations.length) {
            context.go(destinations[i].route);
          } else {
            logout();
          }
        },
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: _navIconKey.containsKey(d.route)
                  ? KozIcon(_navIconKey[d.route]!, size: 22)
                  : Icon(d.icon),
              selectedIcon: _navIconKey.containsKey(d.route)
                  ? KozIcon(_navIconKey[d.route]!, size: 22)
                  : Icon(d.selectedIcon),
              label: d.label,
            ),
          const NavigationDestination(icon: Icon(Icons.logout), label: 'Выход'),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.location,
    required this.destinations,
    required this.user,
    required this.clinic,
  });

  final String location;
  final List<AppDestination> destinations;
  final AuthUser? user;

  /// Активная клиника — её имя и специальность показываются в шапке сайдбара.
  /// null, пока документ клиники загружается (тогда — нейтральный бренд).
  final Clinic? clinic;

  bool _isActive(AppDestination d) =>
      location == d.route || location.startsWith('${d.route}/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Идентичность активной клиники: имя + специальность (subtitle типа).
    // Пока клиника не загружена — нейтральный бренд платформы.
    final clinicName = (clinic?.name ?? '').trim();
    final title = clinicName.isEmpty ? 'Цадмир' : clinicName;
    final clinicSubtitle = (clinic?.subtitle ?? '').trim();
    final subtitle = clinicSubtitle.isEmpty
        ? 'Медицинская платформа'
        : clinicSubtitle;

    return Container(
      width: 248,
      decoration: const BoxDecoration(gradient: AppColors.sidebarGradient),
      child: SafeArea(
        child: Column(
          children: [
            // brand
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  const CadmirLogo(size: 42),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.number(17, color: Colors.white),
                        ),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.sidebarSub,
                            fontSize: 10.5,
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'МЕНЮ',
                  style: TextStyle(
                    color: Color(0xFF4F8278),
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final d in destinations)
                    _NavItem(
                      d: d,
                      active: _isActive(d),
                      onTap: () => context.go(d.route),
                    ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  InitialsAvatar(
                    _initialsOf(user?.fullName ?? '—'),
                    size: 38,
                    fontSize: 14,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user?.fullName ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.onDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          _roleLabel(user?.roles ?? const []),
                          style: const TextStyle(
                            color: AppColors.sidebarSub,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Выйти',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.logout,
                      size: 18,
                      color: AppColors.sidebarSub,
                    ),
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.d, required this.active, required this.onTap});

  final AppDestination d;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.sidebarItemActive : AppColors.sidebarItem;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: active ? AppColors.sidebarActiveBg : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              // reserve the 2px accent always so the row never shifts.
              border: Border(
                left: BorderSide(
                  color: active ? AppColors.sidebarAccent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(11, 11, 13, 11),
            child: Row(
              children: [
                _navIconKey.containsKey(d.route)
                    ? KozIcon(_navIconKey[d.route]!, size: 19, color: color)
                    : Icon(
                        active ? d.selectedIcon : d.icon,
                        size: 19,
                        color: color,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
