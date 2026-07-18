/// Чистая арифметика склада — без Firestore и без Flutter, чтобы её можно было
/// покрыть unit-тестами. Используется репозиторием внутри транзакции при записи
/// движения (приход/расход).
library;

/// Ошибка бизнес-правила склада (например, попытка расхода больше остатка).
/// Текст уже человеко-читаемый по-русски, поэтому `friendlyError` отдаёт его как
/// есть (его `toString()` не содержит технического префикса).
class WarehouseException implements Exception {
  const WarehouseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Форматирует остаток без хвостовых нулей: `5.0 → «5»`, `5.5 → «5.5»`.
String formatStock(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// Новый остаток после движения. [isIn] — приход (+qty) либо расход (−qty),
/// [qty] > 0, [current] — текущий остаток.
///
/// Бросает [WarehouseException] с текстом «Недостаточно на складе (доступно N)»,
/// если расход увёл бы остаток в минус (qty больше доступного). Так учёт никогда
/// не уходит в отрицательные значения.
num nextStock({required num current, required bool isIn, required num qty}) {
  if (qty <= 0) {
    throw const WarehouseException('Количество должно быть больше нуля.');
  }
  if (!isIn && qty > current) {
    throw WarehouseException(
      'Недостаточно на складе (доступно ${formatStock(current)})',
    );
  }
  return isIn ? current + qty : current - qty;
}
