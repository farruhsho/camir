import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/stock_math.dart';
import '../domain/warehouse_movement.dart';
import '../domain/warehouse_product.dart';

final warehouseRepositoryProvider = Provider<WarehouseRepository>(
  (ref) => WarehouseRepository(FirebaseFirestore.instance),
);

/// Склад на **Firestore** — без бэкенда, клиент пишет/читает напрямую (образец:
/// analyses_repository). Две коллекции:
///  * `products` — карточки товаров (поле `stock` — авторитетный остаток);
///  * `stock_movements` — журнал приходов/расходов (ведётся для аудита).
///
/// Остаток хранится в `products/{id}.stock` и меняется **транзакционно** на
/// каждом движении (+qty на приход, −qty на расход) — поэтому [listWithStock]
/// НЕ сканирует весь журнал, а расход не может увести остаток в минус
/// (см. [addMovement]). Для старых товаров без поля `stock` остаток один раз
/// до-считывается точечным запросом `where('product_id'==id)` (без общего
/// скана). Ключи документов — snake_case (`product_id`, `min_stock`, `stock`).
class WarehouseRepository {
  WarehouseRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  CollectionReference<Map<String, dynamic>> get _movements =>
      _db.collection('stock_movements');

  // ── Товары ────────────────────────────────────────────────────────────────

  /// Каталог товаров (по названию, по возрастанию — так удобнее искать глазами).
  Future<List<WarehouseProduct>> products() async {
    final snap = await _products.orderBy('name').get();
    return snap.docs.map(_product).toList();
  }

  /// Создаёт карточку товара. Пустые необязательные поля не пишутся.
  Future<WarehouseProduct> addProduct({
    required String name,
    String? category,
    required String unit,
    num? minStock,
  }) async {
    final ref = await _products.add(<String, dynamic>{
      'name': name,
      if (category != null && category.isNotEmpty) 'category': category,
      'unit': unit,
      'min_stock': ?minStock,
      'stock': 0, // авторитетный остаток; далее меняется только транзакционно
      'created_by': FirebaseAuth.instance.currentUser?.uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return _product(doc);
  }

  // ── Движения ──────────────────────────────────────────────────────────────

  /// Журнал движений (свежие сверху, по `created_at`). [productId] фильтрует по
  /// товару на клиенте — так не нужен составной индекс Firestore.
  Future<List<WarehouseMovement>> movements({
    String? productId,
    int limit = 300,
  }) async {
    final snap = await _movements
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    var items = snap.docs.map(_movement).toList();
    if (productId != null && productId.isNotEmpty) {
      items = items.where((m) => m.productId == productId).toList();
    }
    return items;
  }

  /// Записывает движение (приход/расход) и **транзакционно** пересчитывает
  /// `products/{id}.stock`. [kind] — `in` или `out`, [qty] > 0.
  ///
  /// Расход, который увёл бы остаток в минус, отклоняется с ошибкой
  /// «Недостаточно на складе (доступно N)» ([WarehouseException]) — журнал и
  /// остаток при этом не меняются. Для старого товара без поля `stock` остаток
  /// один раз до-считывается точечным запросом по товару (транзакция клиента не
  /// умеет запросы, поэтому seed берём до неё).
  Future<WarehouseMovement> addMovement({
    required String productId,
    required String kind,
    required num qty,
    String? reason,
    required String date,
  }) async {
    final isIn = kind == WarehouseMovement.kIn;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final productRef = _products.doc(productId);
    final movementRef = _movements
        .doc(); // id заранее — пишем внутри транзакции

    // Предчтение товара: существует ли и есть ли уже сохранённый остаток. Если
    // остатка нет (легаси), считаем seed точечным запросом ДО транзакции.
    final preSnap = await productRef.get();
    if (!preSnap.exists) {
      throw const WarehouseException('Товар не найден (возможно, удалён).');
    }
    final hasStock = preSnap.data()?['stock'] is num;
    final num? seed = hasStock ? null : await _scopedBalance(productId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(productRef);
      final data = snap.data() ?? const <String, dynamic>{};
      final current = data['stock'] is num ? data['stock'] as num : (seed ?? 0);

      // Чистая проверка/расчёт: бросит WarehouseException при over-withdrawal.
      final next = nextStock(current: current, isIn: isIn, qty: qty);

      txn.set(movementRef, <String, dynamic>{
        'product_id': productId,
        'kind': kind,
        'qty': qty,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'date': date,
        'created_by': uid,
        'created_at': FieldValue.serverTimestamp(),
      });
      txn.update(productRef, <String, dynamic>{
        'stock': next,
        'updated_by': uid,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    final doc = await movementRef.get();
    return _movement(doc);
  }

  // ── Товары + остаток ────────────────────────────────────────────────────────

  /// Товары с текущим остатком. Остаток берём из авторитетного поля
  /// `products/{id}.stock` (его транзакционно ведёт [addMovement]) — БЕЗ скана
  /// всего журнала движений. Для старого товара без этого поля остаток один раз
  /// до-считывается точечным запросом `where('product_id'==id)` (сам себя
  /// «вылечит» на первом же движении). Порядок — как у [products] (по названию).
  Future<List<ProductStock>> listWithStock() async {
    final productsSnap = await _products.orderBy('name').get();

    final result = <ProductStock>[];
    for (final doc in productsSnap.docs) {
      final product = _product(doc);
      final raw = doc.data()['stock'];
      final num stock = raw is num ? raw : await _scopedBalance(product.id);
      result.add(ProductStock(product: product, stock: stock));
    }
    return result;
  }

  /// Точечная сумма движений одного товара (Σ in − Σ out). Запрос ограничен
  /// `where('product_id'==id)` — без общего скана коллекции. Используется как
  /// «seed» остатка для старых товаров без поля `stock`.
  Future<num> _scopedBalance(String productId) async {
    final snap = await _movements
        .where('product_id', isEqualTo: productId)
        .get();
    num balance = 0;
    for (final doc in snap.docs) {
      final m = _movement(doc);
      balance += m.isIn ? m.qty : -m.qty;
    }
    return balance;
  }

  // ── Firestore → домен ───────────────────────────────────────────────────────

  WarehouseProduct _product(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return WarehouseProduct(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      category: data['category'] as String?,
      unit: (data['unit'] as String?) ?? 'шт',
      minStock: data['min_stock'] as num?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  WarehouseMovement _movement(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return WarehouseMovement(
      id: doc.id,
      productId: (data['product_id'] as String?) ?? '',
      kind: (data['kind'] as String?) ?? WarehouseMovement.kIn,
      qty: (data['qty'] as num?) ?? 0,
      reason: data['reason'] as String?,
      date: (data['date'] as String?) ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Товары с остатком для экрана (autoDispose — обновляется через invalidate
/// после добавления товара или движения).
final warehouseStockProvider = FutureProvider<List<ProductStock>>(
  (ref) => ref.watch(warehouseRepositoryProvider).listWithStock(),
);

/// Журнал всех движений склада (свежие сверху).
final warehouseMovementsProvider = FutureProvider<List<WarehouseMovement>>(
  (ref) => ref.watch(warehouseRepositoryProvider).movements(),
);
