import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../audit/data/audit_repository.dart';
import '../domain/cash_shift.dart';
import '../domain/cash_withdrawal.dart';
import 'payments_repository.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => CashRepository(FirebaseFirestore.instance),
);

/// Открытая смена за сегодня (или null, если смена ещё не открыта / уже
/// закрыта). keep-alive: используется на экране кассы для расчёта «В кассе».
final currentShiftProvider = FutureProvider<CashShift?>(
  (ref) => ref.watch(cashRepositoryProvider).currentShift(),
);

/// Изъятия из кассы, оформленные СЕГОДНЯ (по полю `day`), свежие сверху —
/// расход из сегодняшней кассы.
final todayWithdrawalsProvider = FutureProvider<List<CashWithdrawal>>(
  (ref) => ref.watch(cashRepositoryProvider).withdrawalsToday(),
);

/// Смены и изъятия кассы «Цадмир» в **Firestore** (коллекции `cash_shifts`,
/// `cash_withdrawals`). Ключи snake_case. Валюта — KGS «сом». Учёт append-only:
/// смена закрывается (не удаляется), изъятие править нельзя. Дневной день
/// (`day`) берём из [PaymentsRepository.todayIso] — единый формат по всей кассе.
class CashRepository {
  CashRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _shifts =>
      _db.collection('cash_shifts');
  CollectionReference<Map<String, dynamic>> get _withdrawals =>
      _db.collection('cash_withdrawals');

  /// Открытая смена за сегодня или null. Запрос по одному полю `day`
  /// (single-field авто-индекс), выбор открытой — на клиенте (за день их
  /// единицы, обычно одна).
  Future<CashShift?> currentShift() async {
    final snap = await _shifts
        .where('day', isEqualTo: PaymentsRepository.todayIso())
        .get();
    for (final d in snap.docs) {
      final s = CashShift.fromMap({...d.data(), 'id': d.id});
      if (s.isOpen) return s;
    }
    return null;
  }

  /// Открывает смену на сегодня с начальным остатком [openingAmount].
  /// Защита от повторного открытия: если открытая смена уже есть — бросает
  /// (экран этого не допускает, но защищаемся и на уровне репозитория).
  Future<CashShift> openShift(num openingAmount) async {
    final existing = await currentShift();
    if (existing != null) {
      throw StateError('Смена уже открыта');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = await _shifts.add(<String, dynamic>{
      'day': PaymentsRepository.todayIso(),
      'opening_amount': openingAmount,
      'status': kShiftOpen,
      'opened_by': uid,
      'opened_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'payments',
      entity: 'cash_shift',
      entityId: ref.id,
      action: 'create',
      summary:
          'Открыта смена · остаток на начало '
          '${formatMoney(openingAmount.toString())}',
    );
    final doc = await ref.get();
    return CashShift.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Закрывает смену [shiftId], фиксируя фактически пересчитанную сумму
  /// [countedAmount]. Начальный остаток/день/автор открытия не меняются
  /// (гарантируется и правилами Firestore).
  Future<void> closeShift(String shiftId, num countedAmount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _shifts.doc(shiftId).update(<String, dynamic>{
      'status': kShiftClosed,
      'counted_amount': countedAmount,
      'closed_by': uid,
      'closed_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'payments',
      entity: 'cash_shift',
      entityId: shiftId,
      action: 'status_change',
      summary:
          'Закрыта смена · в кассе по факту '
          '${formatMoney(countedAmount.toString())}',
      changes: <String, dynamic>{'counted_amount': countedAmount},
    );
  }

  /// Изъятия из кассы за сегодня (по полю `day`), свежие сверху. Single-field
  /// запрос (авто-индекс), сортировка на клиенте по времени создания.
  Future<List<CashWithdrawal>> withdrawalsToday() async {
    final snap = await _withdrawals
        .where('day', isEqualTo: PaymentsRepository.todayIso())
        .get();
    final items = snap.docs
        .map((d) => CashWithdrawal.fromMap({...d.data(), 'id': d.id}))
        .toList();
    items.sort((a, b) {
      final ax = a.createdAt;
      final bx = b.createdAt;
      if (ax == null && bx == null) return 0;
      if (ax == null) return 1;
      if (bx == null) return -1;
      return bx.compareTo(ax);
    });
    return items;
  }

  /// Оформляет изъятие (расход) наличных из кассы. [reason] обязательна на
  /// уровне экрана; пустую строку не сохраняем.
  Future<void> withdraw(num amount, String reason) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final r = reason.trim();
    final ref = await _withdrawals.add(<String, dynamic>{
      'amount': amount,
      if (r.isNotEmpty) 'reason': r,
      'day': PaymentsRepository.todayIso(),
      'created_by': uid,
      'created_at': FieldValue.serverTimestamp(),
    });
    await logAudit(
      module: 'payments',
      entity: 'cash_withdrawal',
      entityId: ref.id,
      action: 'create',
      summary: r.isEmpty
          ? 'Изъятие из кассы ${formatMoney(amount.toString())}'
          : 'Изъятие из кассы ${formatMoney(amount.toString())} · $r',
    );
  }
}
