import 'package:cadmir/features/payments/domain/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentItem', () {
    test('subtotal = price × qty', () {
      expect(const PaymentItem(service: 'ОАК', price: 350).subtotal, 350);
      expect(
        const PaymentItem(service: 'Фиброскан', price: 1500, qty: 2).subtotal,
        3000,
      );
    });

    test('copyWith меняет только заданное', () {
      const it = PaymentItem(service: 'АЛТ', price: 200);
      expect(it.copyWith(qty: 3).qty, 3);
      expect(it.copyWith(qty: 3).price, 200);
    });
  });

  group('Payment.fromMap', () {
    test('парсит строки, статус, способ и суммарные поля', () {
      final p = Payment.fromMap(<String, dynamic>{
        'id': 'p1',
        'patient_name': 'Иванов И.',
        'mrn': '00042',
        'items': [
          {'service': 'ОАК', 'price': 350, 'qty': 1},
          {'service': 'АЛТ', 'price': 200, 'qty': 2},
        ],
        'total': 750,
        'method': kPayCard,
        'status': kPayPaid,
        'day': '2026-07-18',
      });
      expect(p.items.length, 2);
      expect(p.total, 750);
      expect(p.methodLabel, 'Карта');
      expect(p.statusLabel, 'Оплачен');
      expect(p.isRefunded, isFalse);
      expect(p.itemsSummary, 'ОАК, АЛТ ×2');
    });

    test('refunded статус распознаётся', () {
      final p = Payment.fromMap(<String, dynamic>{
        'id': 'p2',
        'patient_name': 'Без карты',
        'items': const <dynamic>[],
        'total': 0,
        'method': kPayCash,
        'status': kPayRefunded,
        'day': '2026-07-18',
      });
      expect(p.isRefunded, isTrue);
      expect(p.statusLabel, 'Возврат');
      expect(p.patientId, isNull);
    });
  });
}
