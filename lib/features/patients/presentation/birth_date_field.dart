import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/input_formatters.dart';

/// Полных лет от даты рождения [birth] на дату [ref] (по умолчанию — сегодня).
int ageFromBirthDate(DateTime birth, [DateTime? ref]) {
  final now = ref ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var years = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    years--;
  }
  return years < 0 ? 0 : years;
}

/// Русское склонение слова «год/года/лет» по числу [n].
String yearsWord(int n) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'лет';
  if (mod10 == 1) return 'год';
  if (mod10 >= 2 && mod10 <= 4) return 'года';
  return 'лет';
}

/// `ДД.ММ.ГГГГ` из [d].
String _fmtDmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year.toString().padLeft(4, '0')}';

/// Максимально допустимый возраст пациента (реализм ввода).
const int _kMaxAge = 120;

/// Результат разбора набранной строки `ДД.ММ.ГГГГ`.
class _BirthParse {
  const _BirthParse(this.date, this.error);

  /// Валидная дата рождения либо `null` (неполный/ошибочный ввод).
  final DateTime? date;

  /// Текст ошибки для «завершённого, но неверного» ввода; `null`, пока строка
  /// ещё набирается или уже корректна.
  final String? error;
}

/// Разбирает набранные цифры даты рождения. Пока введено меньше 8 цифр —
/// это «ещё печатают», ошибку не показываем. При 8 цифрах проверяем, что дата
/// реальна (31.02, 29.02 невисокосного — отсекаются), не в будущем и возраст
/// в пределах `0..120`.
_BirthParse _parseBirthText(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 8) return const _BirthParse(null, null);

  final d = int.parse(digits.substring(0, 2));
  final m = int.parse(digits.substring(2, 4));
  final y = int.parse(digits.substring(4, 8));
  if (m < 1 || m > 12 || d < 1 || d > 31) {
    return const _BirthParse(null, 'Неверная дата');
  }
  final dt = DateTime(y, m, d);
  // Round-trip ловит нормализацию: 31.02 → 03.03, 29.02.2005 → 01.03 и т.п.
  if (dt.year != y || dt.month != m || dt.day != d) {
    return const _BirthParse(null, 'Неверная дата');
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (dt.isAfter(today)) return const _BirthParse(null, 'Дата в будущем');
  if (ageFromBirthDate(dt, today) > _kMaxAge) {
    return const _BirthParse(null, 'Проверьте год');
  }
  return _BirthParse(dt, null);
}

/// Поле «Дата рождения» с двойным вводом: сотрудник может набрать цифры
/// (маска [DateInputFormatter] сама расставит точки: `20022005` → `20.02.2005`)
/// **или** открыть календарь по иконке. Набранное значение валидируется на лету
/// (реальность даты, не в будущем, возраст `0..120`); при корректном вводе
/// рядом показывается возраст.
///
/// Виджет остаётся «управляемым» (controlled): актуальную дату хранит родитель
/// ([value] + [onChanged]), обязательность поля родитель сигналит через
/// [errorText]. Свой [FormField] не заводим — чтобы сброс формы регистратуры
/// оставался предсказуемым.
class BirthDateField extends StatefulWidget {
  const BirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Дата рождения',
    this.isDense = false,
    this.errorText,
  });

  /// Текущая дата рождения (или `null`, если ещё не введена).
  final DateTime? value;

  /// Колбэк ввода даты (нормализованной до календарной, без времени). Приходит
  /// `null`, пока ввод неполный или ошибочный.
  final ValueChanged<DateTime?> onChanged;

  final String label;
  final bool isDense;

  /// Текст ошибки под полем от родителя (например, «Укажите дату рождения»).
  /// Внутренняя ошибка разбора имеет приоритет над ним.
  final String? errorText;

  @override
  State<BirthDateField> createState() => _BirthDateFieldState();
}

class _BirthDateFieldState extends State<BirthDateField> {
  late final TextEditingController _controller;

  /// Последнее значение, отданное через [widget.onChanged]. Позволяет отличить
  /// «родитель прислал новое значение извне» (загрузка пациента, сброс формы)
  /// от «родитель просто вернул наш же onChanged» — во втором случае поле
  /// трогать нельзя, иначе затрём набираемый текст.
  DateTime? _lastEmitted;

  /// Текущая валидная дата (для показа возраста); `null` при неполном/неверном.
  DateTime? _parsed;

  /// Внутренняя ошибка разбора (завершённый, но неверный ввод).
  String? _internalError;

  @override
  void initState() {
    super.initState();
    _lastEmitted = widget.value;
    _parsed = widget.value;
    _controller = TextEditingController(
      text: widget.value == null ? '' : _fmtDmy(widget.value!),
    );
  }

  @override
  void didUpdateWidget(covariant BirthDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Синхронизируемся только с внешними изменениями value (не с эхом нашего
    // же onChanged) — так набранный/частичный текст не сбрасывается на лету.
    if (widget.value != _lastEmitted) {
      _lastEmitted = widget.value;
      _parsed = widget.value;
      _internalError = null;
      final text = widget.value == null ? '' : _fmtDmy(widget.value!);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit(DateTime? date) {
    _lastEmitted = date;
    widget.onChanged(date);
  }

  void _onTextChanged(String raw) {
    final result = _parseBirthText(raw);
    setState(() {
      _parsed = result.date;
      _internalError = result.error;
    });
    _emit(result.date);
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Диапазон сам обеспечивает реализм: lastDate=сегодня (нельзя в будущее),
    // firstDate=120 лет назад (возраст в пределах 0..120).
    final first = DateTime(now.year - _kMaxAge, now.month, now.day);
    // initialDate обязан лежать в [first, today], иначе showDatePicker падает
    // по ассерту. По умолчанию — ~30 лет назад (типичный взрослый пациент).
    var initial =
        _parsed ?? widget.value ?? DateTime(now.year - 30, now.month, now.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: 'Дата рождения',
    );
    if (picked == null || !mounted) return;
    final d = DateTime(picked.year, picked.month, picked.day);
    final text = _fmtDmy(d);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _parsed = d;
      _internalError = null;
    });
    _emit(d);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final age = parsed == null ? null : ageFromBirthDate(parsed);
    // Своя ошибка разбора важнее родительской «обязательное поле».
    final error = _internalError ?? widget.errorText;
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      inputFormatters: const [DateInputFormatter()],
      onChanged: _onTextChanged,
      style: const TextStyle(fontSize: 15, color: AppColors.ink),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'ДД.ММ.ГГГГ',
        isDense: widget.isDense,
        errorText: error,
        prefixIcon: const Icon(Icons.cake_outlined),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (age != null) _AgePill(age: age),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                tooltip: 'Выбрать в календаре',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                onPressed: _pick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пилюля с вычисленным возрастом, например «20 лет».
class _AgePill extends StatelessWidget {
  const _AgePill({required this.age});

  final int age;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        borderRadius: BorderRadius.circular(AppColors.rPill),
      ),
      child: Text(
        '$age ${yearsWord(age)}',
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
