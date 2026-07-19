import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

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

/// Поле «Дата рождения» — управляемый (controlled) виджет: тап открывает
/// [showDatePicker], выбранная дата показывается как `ДД.ММ.ГГГГ`, а справа
/// автоматически считается и показывается возраст.
///
/// Диапазон выбора уже гарантирует реалистичность: `firstDate = 120 лет назад`,
/// `lastDate = сегодня` — будущую дату и возраст > 120 просто нельзя выбрать.
/// Значение хранит родитель (передаёт [value] и получает [onChanged]); ошибку
/// «обязательное поле» родитель показывает через [errorText] (мы не тянем сюда
/// `FormField`, чтобы сброс формы регистратуры был предсказуемым).
class BirthDateField extends StatelessWidget {
  const BirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Дата рождения',
    this.isDense = false,
    this.errorText,
  });

  /// Текущая дата рождения (или `null`, если ещё не выбрана).
  final DateTime? value;

  /// Колбэк выбора даты (нормализованной до календарной, без времени).
  final ValueChanged<DateTime?> onChanged;

  final String label;
  final bool isDense;

  /// Текст ошибки под полем (например, «Укажите дату рождения»).
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Диапазон сам обеспечивает реализм: lastDate=сегодня (нельзя в будущее),
    // firstDate=120 лет назад (возраст в пределах 0..120). Так выбранная дата
    // всегда валидна, отдельная проверка «возраста» не нужна.
    final first = DateTime(now.year - 120, now.month, now.day);
    // initialDate обязан лежать в [first, today], иначе showDatePicker падает
    // по ассерту. По умолчанию — ~30 лет назад (типичный взрослый пациент).
    var initial = value ?? DateTime(now.year - 30, now.month, now.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(today)) initial = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: 'Дата рождения',
    );
    if (picked != null) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    final age = v == null ? null : ageFromBirthDate(v);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(AppColors.rField),
      child: InputDecorator(
        // Лейбл всегда «поднят», чтобы плейсхолдер ДД.ММ.ГГГГ не перекрывался.
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          isDense: isDense,
          errorText: errorText,
          prefixIcon: const Icon(Icons.cake_outlined),
          suffixIcon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.calendar_today_outlined, size: 18),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                v == null ? 'ДД.ММ.ГГГГ' : _fmtDmy(v),
                style: TextStyle(
                  color: v == null ? AppColors.muted : AppColors.ink,
                  fontSize: 15,
                ),
              ),
            ),
            if (age != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tealBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$age ${yearsWord(age)}',
                  style: const TextStyle(
                    color: AppColors.tealDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
