import 'package:cadmir/core/auth/clinic_types.dart';
import 'package:cadmir/core/widgets/app_shell.dart';
import 'package:cadmir/features/auth/domain/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Мульти-профильность: у «глазной» клиники Фиброскан исчезает из навигации,
/// у гематологии — остаётся. Проверяем настоящую логику приложения:
/// шаблоны типов ([clinicTypeFor]) + фильтр меню ([allowedDestinations]) +
/// route-гард ([routeEnabledForModules]) — те же функции, которыми живут
/// AppShell и router.redirect.
void main() {
  // Супер-админ клиники: право есть на всё — значит, видимость пунктов
  // определяется ТОЛЬКО модулями клиники (чистая проверка модульного фильтра).
  const super_ = AuthUser(
    id: 'u1',
    email: 's@c.kg',
    fullName: 'Супер',
    isSuperuser: true,
  );

  group('шаблоны типов клиник', () {
    test('офтальмология — без фиброскана', () {
      final t = clinicTypeFor('ophthalmology');
      expect(t.subtitle, 'Офтальмологический центр');
      expect(t.modules.contains(kModFibroscan), isFalse);
      // Универсальные модули на месте.
      expect(t.modules.contains(kModReception), isTrue);
      expect(t.modules.contains(kModAnalyses), isTrue);
      expect(t.modules.contains(kModPayments), isTrue);
    });

    test('гематология — с фиброскном', () {
      expect(clinicTypeFor('hematology').modules.contains(kModFibroscan),
          isTrue);
    });

    test('неизвестный/старый тип -> гематология (back-compat)', () {
      expect(clinicTypeFor(null).key, 'hematology');
      expect(clinicTypeFor('???').key, 'hematology');
    });
  });

  group('навигация подстраивается под клинику', () {
    test('глазная клиника: /fibroscan исчезает из меню и из route-гарда', () {
      final eye = clinicTypeFor('ophthalmology').modules;

      final routes =
          allowedDestinations(super_, eye).map((d) => d.route).toList();
      expect(routes, isNot(contains('/fibroscan')));
      expect(routes, contains('/reception'));
      expect(routes, contains('/analyses'));
      expect(routes, contains('/payments'));

      // Route-гард (роутер): прямой заход на /fibroscan запрещён.
      expect(routeEnabledForModules('/fibroscan', eye), isFalse);
      // Структурные разделы модулями не гейтятся.
      expect(routeEnabledForModules('/staff', eye), isTrue);
      expect(routeEnabledForModules('/clinics', eye), isTrue);
    });

    test('гематология: /fibroscan на месте', () {
      final hema = clinicTypeFor('hematology').modules;
      final routes =
          allowedDestinations(super_, hema).map((d) => d.route).toList();
      expect(routes, contains('/fibroscan'));
      expect(routeEnabledForModules('/fibroscan', hema), isTrue);
    });

    test('клиника не загружена (null) — модульный фильтр не применяется', () {
      expect(routeEnabledForModules('/fibroscan', null), isTrue);
    });
  });
}
