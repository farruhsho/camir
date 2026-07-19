import 'package:cloud_firestore/cloud_firestore.dart';

/// Способы оплаты (значения поля `method` в Firestore).
const String kPayCash = 'cash';
const String kPayCard = 'card';
const String kPayTransfer = 'transfer';

/// Способ оплаты → русская подпись.
const Map<String, String> kPayMethodLabels = <String, String>{
  kPayCash: 'Наличные',
  kPayCard: 'Карта',
  kPayTransfer: 'Перевод',
};

/// Порядок способов для выпадашки.
const List<String> kPayMethods = <String>[kPayCash, kPayCard, kPayTransfer];

/// Статусы платежа.
const String kPayPaid = 'paid';
const String kPayRefunded = 'refunded';

const Map<String, String> kPayStatusLabels = <String, String>{
  kPayPaid: 'Оплачен',
  kPayRefunded: 'Возврат',
};

/// Строка чека: услуга, цена за единицу, количество.
class PaymentItem {
  const PaymentItem({required this.service, required this.price, this.qty = 1});

  final String service;
  final num price;
  final int qty;

  /// Сумма строки (цена × количество).
  num get subtotal => price * qty;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'service': service,
    'price': price,
    'qty': qty,
  };

  PaymentItem copyWith({String? service, num? price, int? qty}) => PaymentItem(
    service: service ?? this.service,
    price: price ?? this.price,
    qty: qty ?? this.qty,
  );

  factory PaymentItem.fromMap(Map<String, dynamic> m) => PaymentItem(
    service: m['service']?.toString() ?? '',
    price: (m['price'] as num?) ?? num.tryParse('${m['price']}') ?? 0,
    qty: (m['qty'] as num?)?.toInt() ?? 1,
  );
}

/// Платёж кассы клиники «Цадмир» (коллекция Firestore `payments`).
///
/// Простой immutable-класс с [fromMap]/[toMap] (по образцу [Patient]/[Visit]).
/// Валюта — KGS «сом». Пациент опционален (разовая оплата без карты). Возврат —
/// это НЕ удаление, а перевод в статус [kPayRefunded] с меткой времени/причиной,
/// чтобы дневной отчёт кассы сходился (append-only учёт).
class Payment {
  const Payment({
    required this.id,
    this.patientId,
    required this.patientName,
    this.mrn,
    this.visitId,
    required this.items,
    required this.total,
    required this.method,
    required this.status,
    this.note,
    required this.day,
    this.createdBy,
    this.createdAt,
    this.refundedAt,
    this.refundReason,
  });

  final String id;
  final String? patientId;

  /// Денормализованное имя (или «Без карты» для разовой оплаты).
  final String patientName;
  final String? mrn;

  /// Необязательная привязка к визиту (приёму) из очереди.
  final String? visitId;

  final List<PaymentItem> items;
  final num total;
  final String method;
  final String status;
  final String? note;

  /// День оплаты `YYYY-MM-DD` — для дешёвого запроса «за сегодня».
  final String day;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? refundedAt;
  final String? refundReason;

  bool get isRefunded => status == kPayRefunded;
  String get methodLabel => kPayMethodLabels[method] ?? method;
  String get statusLabel => kPayStatusLabels[status] ?? status;

  /// Краткое перечисление услуг для строки списка.
  String get itemsSummary => items
      .map((i) => i.qty > 1 ? '${i.service} ×${i.qty}' : i.service)
      .join(', ');

  factory Payment.fromMap(Map<String, dynamic> map) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    final rawItems = (map['items'] as List?) ?? const <dynamic>[];
    return Payment(
      id: map['id']?.toString() ?? '',
      patientId: str(map['patient_id']),
      patientName: map['patient_name']?.toString() ?? '',
      mrn: str(map['mrn']),
      visitId: str(map['visit_id']),
      items: rawItems
          .whereType<Map>()
          .map((e) => PaymentItem.fromMap(e.cast<String, dynamic>()))
          .toList(),
      total: (map['total'] as num?) ?? 0,
      method: map['method']?.toString() ?? kPayCash,
      status: map['status']?.toString() ?? kPayPaid,
      note: str(map['note']),
      day: map['day']?.toString() ?? '',
      createdBy: str(map['created_by']),
      createdAt: ts(map['created_at']),
      refundedAt: ts(map['refunded_at']),
      refundReason: str(map['refund_reason']),
    );
  }
}
