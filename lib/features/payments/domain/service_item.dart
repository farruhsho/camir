/// Услуга прайс-листа клиники «Цадмир» (коллекция Firestore `services`).
///
/// Простой immutable-класс. Цена — в KGS «сом». Неактивные услуги ([active] =
/// false) не предлагаются в форме оплаты, но остаются в справочнике (историю
/// прошлых платежей не ломаем).
class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.price,
    this.category,
    this.active = true,
  });

  final String id;
  final String name;
  final num price;
  final String? category;
  final bool active;

  factory ServiceItem.fromMap(Map<String, dynamic> m) {
    final cat = m['category']?.toString();
    return ServiceItem(
      id: m['id']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      price: (m['price'] as num?) ?? num.tryParse('${m['price']}') ?? 0,
      category: (cat == null || cat.isEmpty) ? null : cat,
      // Старые документы без поля active считаем активными.
      active: m['active'] != false,
    );
  }
}
