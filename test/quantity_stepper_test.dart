// Unit tests for the reusable QuantityStepper ([ − ] qty [ + ] unit):
// the owner's hide-unit-when-1 rule, ± stepping with min clamping, and the
// type-then-commit path (regression: pressing Enter keeps focus, so the field
// must still reflect the committed/clamped value rather than the stale one).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cadmir/core/widgets/quantity_stepper.dart';

class _Host extends StatefulWidget {
  const _Host({this.unit, this.min = 1, this.initial = 1});
  final String? unit;
  final double min;
  final double initial;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late double v = widget.initial;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: QuantityStepper(
            value: v,
            unit: widget.unit,
            min: widget.min,
            onChanged: (x) => setState(() => v = x),
          ),
        ),
      );
}

void main() {
  testWidgets('hides the unit when value == 1', (tester) async {
    await tester.pumpWidget(const _Host(unit: 'шт', initial: 1));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('шт'), findsNothing); // owner rule: hide redundant unit
  });

  testWidgets('shows the unit when value != 1', (tester) async {
    await tester.pumpWidget(const _Host(unit: 'шт', initial: 3));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('шт'), findsOneWidget);
  });

  testWidgets('+ increments; − is clamped at min', (tester) async {
    await tester.pumpWidget(const _Host(unit: 'шт', initial: 1, min: 1));
    await tester.tap(find.byIcon(Icons.remove)); // disabled at min — no-op
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('шт'), findsOneWidget); // unit appears once value != 1
  });

  testWidgets('typing a value + Enter commits and the field reflects it',
      (tester) async {
    await tester.pumpWidget(const _Host(unit: 'шт', initial: 1));
    await tester.enterText(find.byType(TextField), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('typing below min snaps back to the clamped value',
      (tester) async {
    await tester.pumpWidget(const _Host(initial: 2, min: 1));
    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('1'), findsOneWidget); // 0 clamped up to min 1
  });
}
