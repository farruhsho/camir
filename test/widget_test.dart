// Smoke + unit tests for pure app logic and the shared theme/widget kit.
// Deliberately plugin-free (no Firebase / network): everything here builds
// offline so `flutter test` stays green in CI without emulators.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadmir/app/theme.dart';
import 'package:cadmir/core/utils/formatters.dart';
import 'package:cadmir/core/widgets/koz_widgets.dart';
import 'package:cadmir/features/auth/domain/auth_user.dart';

void main() {
  group('formatMoney', () {
    test('formats a decimal string with grouping and the som currency', () {
      expect(formatMoney('150000.00'), contains('150'));
      // Kyrgyzstan uses the som («сом») — not the Uzbek sum («сум»).
      expect(formatMoney('150000.00'), endsWith('сом'));
    });

    test('falls back to zero for null/garbage', () {
      expect(formatMoney(null), startsWith('0'));
      expect(formatMoney('abc'), startsWith('0'));
    });
  });

  group('AuthUser.can', () {
    const base = AuthUser(id: '1', email: 'a@b.c', fullName: 'A');

    test('grants only listed permissions', () {
      final u = base.copyWith(permissions: ['patients.read']);
      expect(u.can('patients.read'), isTrue);
      expect(u.can('patients.create'), isFalse);
    });

    test('superuser can do anything', () {
      final u = base.copyWith(isSuperuser: true);
      expect(u.can('anything.at.all'), isTrue);
    });
  });

  group('app theme', () {
    // Guards against the previous state where dark() == light(): the dark
    // variant must actually carry a dark brightness and its own surfaces.
    test('light() and dark() are genuinely different brightnesses', () {
      expect(KozTheme.light().brightness, Brightness.light);
      expect(KozTheme.dark().brightness, Brightness.dark);
      expect(
        KozTheme.dark().scaffoldBackgroundColor,
        isNot(KozTheme.light().scaffoldBackgroundColor),
      );
    });

    testWidgets('shared widget kit builds under both themes without throwing', (
      tester,
    ) async {
      Widget app(ThemeMode mode) => MaterialApp(
        theme: KozTheme.light(),
        darkTheme: KozTheme.dark(),
        themeMode: mode,
        home: const Scaffold(
          body: Center(child: AppCard(child: Text('Цадмир'))),
        ),
      );

      await tester.pumpWidget(app(ThemeMode.light));
      expect(tester.takeException(), isNull);
      expect(find.text('Цадмир'), findsOneWidget);

      await tester.pumpWidget(app(ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Цадмир'), findsOneWidget);
    });
  });
}
