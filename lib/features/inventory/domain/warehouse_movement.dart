/// Движение по складу (Firestore-коллекция `stock_movements`) — приход или
/// расход товара. Простой immutable-класс без codegen. Firestore-маппинг —
/// в [WarehouseRepository].
class WarehouseMovement {
  const WarehouseMovement({
    required this.id,
    required this.productId,
    required this.kind,
    required this.qty,
    this.reason,
    required this.date,
    this.createdAt,
  });

  final String id;
  final String productId;

  /// Тип движения: [kIn] (`in`, приход) либо [kOut] (`out`, расход).
  final String kind;

  /// Количество (в единицах товара). Всегда положительное — знак задаёт [kind].
  final num qty;

  /// Причина/комментарий (для расходников — например «плановый расход»).
  final String? reason;

  /// Дата движения в ISO-формате `YYYY-MM-DD` (экран показывает ДД.ММ.ГГГГ).
  final String date;

  final DateTime? createdAt;

  bool get isIn => kind == kIn;

  /// RU-подпись типа движения.
  String get kindLabel => isIn ? 'Приход' : 'Расход';

  /// Приход.
  static const String kIn = 'in';

  /// Расход.
  static const String kOut = 'out';
}
