// Unit-тесты чистой арифметики склада (lib/features/inventory/domain/stock_math):
// приход прибавляет, расход вычитает, расход до нуля разрешён, а over-withdrawal
// отклоняется ИМЕННО сообщением «Недостаточно на складе (доступно N)» —
// контракт, который диалог склада показывает через friendlyError.
import 'package:flutter_test/flutter_test.dart';
import 'package:cadmir/features/inventory/domain/stock_math.dart';

void main() {
  group('nextStock', () {
    test('приход прибавляет к остатку', () {
      expect(nextStock(current: 3, isIn: true, qty: 2), 5);
    });

    test('расход вычитает из остатка', () {
      expect(nextStock(current: 5, isIn: false, qty: 2), 3);
    });

    test('расход ровно до нуля разрешён', () {
      expect(nextStock(current: 5, isIn: false, qty: 5), 0);
    });

    test('расход больше остатка отклоняется с точным сообщением', () {
      expect(
        () => nextStock(current: 3, isIn: false, qty: 5),
        throwsA(
          isA<WarehouseException>().having(
            (e) => e.toString(),
            'message',
            'Недостаточно на складе (доступно 3)',
          ),
        ),
      );
    });

    test('дробный остаток в сообщении — без хвостовых нулей', () {
      expect(
        () => nextStock(current: 2.5, isIn: false, qty: 3),
        throwsA(
          isA<WarehouseException>().having(
            (e) => e.toString(),
            'message',
            'Недостаточно на складе (доступно 2.5)',
          ),
        ),
      );
    });

    test('нулевое или отрицательное количество отклоняется', () {
      expect(
        () => nextStock(current: 5, isIn: true, qty: 0),
        throwsA(isA<WarehouseException>()),
      );
      expect(
        () => nextStock(current: 5, isIn: false, qty: -1),
        throwsA(isA<WarehouseException>()),
      );
    });
  });

  group('formatStock', () {
    test('целое — без .0', () => expect(formatStock(5), '5'));
    test('дробное — как есть', () => expect(formatStock(5.5), '5.5'));
  });
}
