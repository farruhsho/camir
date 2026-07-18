import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cadmir/core/widgets/koz_icons.dart';

void main() {
  testWidgets('every KozIcon path renders without throwing', (tester) async {
    for (final key in KozIcons.paths.keys) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: KozIcon(key, size: 24, color: const Color(0xFF12201E))),
        ),
      ));
      // A render error surfaces as a non-null exception on the binding.
      expect(tester.takeException(), isNull, reason: 'KozIcon("$key") threw');
    }
  });

  testWidgets('unknown key falls back to a Material icon, no throw', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: KozIcon('definitely-not-a-key'))),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(Icon), findsOneWidget);
  });
}
