// Reusable [TextInputFormatter]s for the clinic's data-entry forms.
//
// SELF IMPROVEMENT MEDICAL MODE: поля вводятся структурировано, не как
// «строка на всё». Маски и лимиты не дают сотруднику ввести мусор и убирают
// ручное проставление разделителей (точки в дате, префикс телефона).
import 'package:flutter/services.dart';

/// Дата в маске `DD.MM.YYYY`: пользователь набирает только цифры, точки
/// проставляются автоматически после дня и месяца. Больше 8 цифр не принимает.
///
/// Пример: ввод `15062026` → отображается `15.06.2026`.
class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Берём только цифры из нового значения и ограничиваем до 8 (DDMMYYYY).
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final capped = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      buffer.write(capped[i]);
      // Точка после позиции 2 (день) и 4 (месяц), но не в самом конце ввода.
      if ((i == 1 || i == 3) && i != capped.length - 1) buffer.write('.');
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Только цифры, не более [maxDigits]. Используется для локальной части
/// телефона (+996 уже в префиксе поля) и числовых документов (ПИН).
List<TextInputFormatter> digitsOnly(int maxDigits) => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxDigits),
    ];

/// Локальная часть кыргызского номера: только цифры, максимум 9
/// (`700 12 34 56`). Префикс `+996 ` показывается через `prefixText`, в
/// контроллере хранятся только эти 9 цифр.
List<TextInputFormatter> get uzPhoneLocal => digitsOnly(9);

/// Длина кыргызской локальной части номера (без `+996`).
const int kUzPhoneLocalLength = 9;

/// Паспорт/ID-карта КР: 2 заглавные латинские буквы + 7 цифр (`AN1234567`);
/// серии AN/ID/AC/AD/AS/PE/PD/PS. Буквы автоматически переводятся в верхний
/// регистр, лишние символы отбрасываются, длина ограничена 9 символами.
class PassportInputFormatter extends TextInputFormatter {
  const PassportInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length && buffer.length < 9; i++) {
      final ch = raw[i];
      if (buffer.length < 2) {
        // Первые две позиции — только латинские буквы.
        if (RegExp(r'[A-Z]').hasMatch(ch)) buffer.write(ch);
      } else {
        // Остальные — только цифры.
        if (RegExp(r'[0-9]').hasMatch(ch)) buffer.write(ch);
      }
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Собирает полный номер из локальной части (`+996 ` + цифры).
/// Пустой/неполный ввод → `null` (поле телефона необязательное).
String? assembleUzPhone(String local) {
  final digits = local.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return '+996$digits';
}

/// Достаёт локальную часть (последние 9 цифр) из произвольного ввода телефона
/// для предзаполнения поля: `+996 700 12 34 56`, `996700123456`,
/// `700123456` → `700123456`.
String extractUzPhoneLocal(String? raw) {
  if (raw == null) return '';
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  // Уберём код страны 996, если он есть в начале.
  if (digits.startsWith('996')) digits = digits.substring(3);
  if (digits.length > kUzPhoneLocalLength) {
    digits = digits.substring(digits.length - kUzPhoneLocalLength);
  }
  return digits;
}
