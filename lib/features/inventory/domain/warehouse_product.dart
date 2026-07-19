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
    this.expiry,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Группа/категория (расходники, реактивы, …) — необязательно.
  final String? category;

  /// Единица измерения: `шт` / `уп` / `мл`.
  final String unit;

  /// Порог «мало на складе». null — контроль минимума не ведётся.
  final num? minStock;

  /// Срок годности (Firestore-ключ `expiry`, хранится как ISO `YYYY-MM-DD`).
  /// null — срок годности не контролируется. Сравнения — по датам (без времени),
  /// см. [daysToExpiry] / [expired] / [expiringSoon].
  final DateTime? expiry;

  /// Мягкое удаление: архивные товары скрыты из каталога и остатков
  /// ([WarehouseRepository.products]/[WarehouseRepository.listWithStock]),
  /// но их карточка и история движений остаются в базе (жёсткого удаления нет).
  final bool archived;

  final DateTime? createdAt;

  /// Время последнего изменения карточки (правка/архивация). null — не менялась.
  final DateTime? updatedAt;

  /// Дней до срока годности по датам (без учёта времени). Отрицательное — товар
  /// просрочен, `0` — истекает сегодня. null — срок годности не задан.
  int? get daysToExpiry {
    final e = expiry;
    if (e == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(e.year, e.month, e.day);
    return exp.difference(today).inDays;
  }

  /// Срок годности уже истёк (дата раньше сегодняшней).
  bool get expired {
    final d = daysToExpiry;
    return d != null && d < 0;
  }

  /// Срок годности истекает в ближайшие [kExpirySoonDays] дней (включая сегодня),
  /// но ещё не истёк.
  bool get expiringSoon {
    final d = daysToExpiry;
    return d != null && d >= 0 && d <= kExpirySoonDays;
  }
}

/// Допустимые единицы измерения для выпадашки при добавлении товара.
const List<String> kWarehouseUnits = <String>['шт', 'уп', 'мл'];

/// Порог «скоро истечёт» — сколько дней до срока годности считаем тревожными.
const int kExpirySoonDays = 30;

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
