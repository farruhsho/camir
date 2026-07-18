/// Товар склада (Firestore-коллекция `products`) — простой immutable-класс без
/// codegen (как [StockMovement] в movement.dart). Firestore-маппинг живёт в
/// [WarehouseRepository]; домен остаётся чистым.
///
/// Отдельный класс от старого Dio-[Product] (product.dart): тот всё ещё нужен
/// операциям/лечению, а склад переведён на Firebase без бэкенда.
class WarehouseProduct {
  const WarehouseProduct({
    required this.id,
    required this.name,
    this.category,
    required this.unit,
    this.minStock,
    this.createdAt,
  });

  final String id;
  final String name;

  /// Группа/категория (расходники, реактивы, …) — необязательно.
  final String? category;

  /// Единица измерения: `шт` / `уп` / `мл`.
  final String unit;

  /// Порог «мало на складе». null — контроль минимума не ведётся.
  final num? minStock;

  final DateTime? createdAt;
}

/// Допустимые единицы измерения для выпадашки при добавлении товара.
const List<String> kWarehouseUnits = <String>['шт', 'уп', 'мл'];

/// Товар вместе с текущим остатком (сумма приходов − сумма расходов). Возвращается
/// [WarehouseRepository.listWithStock] для списка на экране.
class ProductStock {
  const ProductStock({required this.product, required this.stock});

  final WarehouseProduct product;

  /// Текущий остаток: Σ(in.qty) − Σ(out.qty). Может быть отрицательным, если
  /// расходов записали больше, чем прихода.
  final num stock;

  /// «Мало»: минимум задан и остаток не выше него.
  bool get low => product.minStock != null && stock <= product.minStock!;
}
