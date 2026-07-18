import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact `[ − ] qty [ + ] unit` stepper — replaces manual numeric typing for
/// quantities. Keyboard-friendly: the middle field stays editable (decimals
/// allowed), while the buttons cover the common ±[step] case.
///
/// Owner rule — *hide redundant units*: the [unit] label is rendered ONLY when
/// it is non-empty AND [value] differs from 1 (the common single-item case),
/// keeping the row clean for the overwhelmingly frequent qty == 1.
///
/// Public API is intentionally stable — other code depends on it. The editable
/// field's transient text state lives in a private child widget so this stays a
/// [StatelessWidget].
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.unit,
    this.step = 1,
    this.min = 1,
    this.max,
    this.enabled = true,
  });

  /// Current numeric value (already clamped to [min]/[max] by the owner).
  final double value;

  /// Emitted with a value clamped to `[min, max]` whenever the user steps or
  /// commits a typed number.
  final ValueChanged<double> onChanged;

  /// Optional unit label (e.g. "шт", "мл"). Hidden when null/empty or value==1.
  final String? unit;

  /// Increment/decrement amount for the − / + buttons.
  final double step;

  /// Lower bound (inclusive). Decrement disabled at/below it.
  final double min;

  /// Upper bound (inclusive). `null` = unbounded; increment disabled at/above it.
  final double? max;

  /// When false, all controls are inert.
  final bool enabled;

  /// "3" for whole numbers, "1.5" for fractional — no trailing ".0".
  static String format(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  double _clamp(double v) {
    var r = v < min ? min : v;
    final hi = max;
    if (hi != null && r > hi) r = hi;
    return r;
  }

  void _emit(double v) {
    final clamped = _clamp(v);
    if (clamped != value) onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final canDec = enabled && value > min;
    final hi = max;
    final canInc = enabled && (hi == null || value < hi);
    final showUnit = unit != null && unit!.isNotEmpty && value != 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          tooltip: 'Меньше',
          visualDensity: VisualDensity.compact,
          onPressed: canDec ? () => _emit(value - step) : null,
        ),
        SizedBox(
          width: 64,
          child: _StepperField(
            value: value,
            enabled: enabled,
            onSubmitted: _emit,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Больше',
          visualDensity: VisualDensity.compact,
          onPressed: canInc ? () => _emit(value + step) : null,
        ),
        if (showUnit) ...[
          const SizedBox(width: 4),
          Text(unit!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// The editable middle field. Holds transient edit text locally and snaps back
/// to the last valid [value] on empty/invalid commit (submit or blur).
class _StepperField extends StatefulWidget {
  const _StepperField({
    required this.value,
    required this.enabled,
    required this.onSubmitted,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  late final TextEditingController _controller =
      TextEditingController(text: QuantityStepper.format(widget.value));
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Commit (or snap back) when focus leaves the field.
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _StepperField old) {
    super.didUpdateWidget(old);
    // Reflect the canonical value whenever the owner changes it (± buttons OR a
    // commit the parent clamped). This never fights active typing: typing only
    // mutates the local controller text, not widget.value, so the guard below is
    // false until an actual commit/step changes the parent's value.
    if (widget.value != old.value) {
      _controller.text = QuantityStepper.format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (parsed != null) {
      widget.onSubmitted(parsed);
    }
    // Always reflect the canonical (clamped/formatted) value after a commit —
    // invalid/empty input snaps back to the last valid value.
    _controller.text = QuantityStepper.format(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
