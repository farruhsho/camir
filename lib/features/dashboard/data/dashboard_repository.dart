import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/warehouse_repository.dart';
import '../../payments/domain/cash_shift.dart';
import '../../payments/domain/payment.dart';
import '../../visits/domain/visit.dart';

/// Директорский дашборд «Цадмир» — **только чтение**, свой тонкий репозиторий.
///
/// Собирает агрегаты по кассе, картотеке, лаборатории и складу за сегодня в один
/// [DashboardData]. Не пишет ничего и НЕ трогает репозитории других модулей,
/// кроме переиспользования [WarehouseRepository.listWithStock] (тоже чтение) для
/// подсчёта складских алертов.
///
/// Запросы держатся в рамках single-field индексов: по строке `day`
/// (ISO `YYYY-MM-DD` сортируется лексикографически) и по `created_at`
/// (Timestamp) — оба авто-индексируются, композитные индексы не нужны. Разбор
/// каждого документа обёрнут защитно: одна битая запись не роняет весь дашборд, а
/// сбой второстепенной секции (визиты/касса/склад) деградирует до нулей, но не
/// прячет основную выручку.
class DashboardRepository {
  DashboardRepository(this._db, this._warehouse);

  final FirebaseFirestore _db;
  final WarehouseRepository _warehouse;

  /// Сколько дней показывает график выручки (включая сегодня).
  static const int kRevenueWindowDays = 7;

  Future<DashboardData> load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayIso = _iso(todayStart);
    final startTs = Timestamp.fromDate(todayStart);

    // Скелет графика: 7 дней от «сегодня − 6» до сегодня (слева направо).
    final days = <DateTime>[
      for (var i = kRevenueWindowDays - 1; i >= 0; i--)
        todayStart.subtract(Duration(days: i)),
    ];
    final startDayIso = _iso(days.first);
    final revByIso = <String, num>{for (final d in days) _iso(d): 0};

    // ── Платежи за последние 7 дней (один запрос по диапазону строки `day`) ────
    // Отсюда берём: график выручки за 7 дней, выручку/платежи/средний чек за
    // сегодня, валовый приход сегодня (для «в кассе») и разбивку по способам.
    num revenueToday = 0; // Σ оплаченных, созданных сегодня
    num grossToday = 0; // Σ всех (любой статус), созданных сегодня — для кассы
    var paidCountToday = 0;
    final methodTotals = <String, num>{for (final m in kPayMethods) m: 0};

    final rangeSnap = await _db
        .collection('payments')
        .where('day', isGreaterThanOrEqualTo: startDayIso)
        .get();
    for (final doc in rangeSnap.docs) {
      final Payment p;
      try {
        p = Payment.fromMap({...doc.data(), 'id': doc.id});
      } catch (e) {
        debugPrint('dashboard: пропущен платёж ${doc.id}: $e');
        continue;
      }
      final isPaid = p.status == kPayPaid;
      if (p.day == todayIso) {
        grossToday += p.total;
        if (isPaid) {
          revenueToday += p.total;
          paidCountToday++;
          // Разбивка по способам: смешанный платёж засчитывается в каждый способ
          // своей частью (наличные — в «Наличные», карта — в «Карту» и т.д.).
          for (final e in p.methodBreakdown().entries) {
            methodTotals[e.key] = (methodTotals[e.key] ?? 0) + e.value;
          }
        }
      }
      if (isPaid && revByIso.containsKey(p.day)) {
        revByIso[p.day] = (revByIso[p.day] ?? 0) + p.total;
      }
    }

    // ── Возвраты, оформленные сегодня (по `refund_day`) ───────────────────────
    num refundsToday = 0;
    try {
      final refSnap = await _db
          .collection('payments')
          .where('refund_day', isEqualTo: todayIso)
          .get();
      for (final doc in refSnap.docs) {
        refundsToday += (doc.data()['total'] as num?) ?? 0;
      }
    } catch (e) {
      debugPrint('dashboard: возвраты недоступны: $e');
    }

    // ── Касса: открытая смена + изъятия за сегодня ────────────────────────────
    num opening = 0;
    try {
      final shiftSnap = await _db
          .collection('cash_shifts')
          .where('day', isEqualTo: todayIso)
          .get();
      for (final d in shiftSnap.docs) {
        final s = CashShift.fromMap({...d.data(), 'id': d.id});
        if (s.isOpen) {
          opening = s.openingAmount;
          break;
        }
      }
    } catch (e) {
      debugPrint('dashboard: смена недоступна: $e');
    }

    num withdrawalsToday = 0;
    try {
      final wSnap = await _db
          .collection('cash_withdrawals')
          .where('day', isEqualTo: todayIso)
          .get();
      for (final d in wSnap.docs) {
        withdrawalsToday += (d.data()['amount'] as num?) ?? 0;
      }
    } catch (e) {
      debugPrint('dashboard: изъятия недоступны: $e');
    }

    // ── Приёмы за сегодня, по статусам ────────────────────────────────────────
    final visitsByStatus = <String, int>{};
    var visitsCount = 0;
    try {
      final vSnap = await _db
          .collection('visits')
          .where('day', isEqualTo: todayIso)
          .get();
      for (final d in vSnap.docs) {
        final st = d.data()['status']?.toString() ?? kVisitAwaitingPayment;
        visitsByStatus[st] = (visitsByStatus[st] ?? 0) + 1;
        visitsCount++;
      }
    } catch (e) {
      debugPrint('dashboard: приёмы недоступны: $e');
    }

    // ── Счётчики (count() агрегация; фолбэк — ограниченное чтение) ─────────────
    final newPatientsToday = await _safeCount(
      _db
          .collection('patients')
          .where('created_at', isGreaterThanOrEqualTo: startTs),
    );
    final totalPatients = await _safeCount(_db.collection('patients'));
    final analysesToday = await _safeCount(
      _db
          .collection('analyses')
          .where('created_at', isGreaterThanOrEqualTo: startTs),
    );
    final fibroscanToday = await _safeCount(
      _db
          .collection('fibroscan')
          .where('created_at', isGreaterThanOrEqualTo: startTs),
    );

    // ── Склад: «мало» и «истекает/просрочено» ─────────────────────────────────
    var inventoryLow = 0;
    var inventoryExpiry = 0;
    try {
      final stock = await _warehouse.listWithStock();
      for (final s in stock) {
        if (s.low) inventoryLow++;
        if (s.product.expired || s.product.expiringSoon) inventoryExpiry++;
      }
    } catch (e) {
      debugPrint('dashboard: склад недоступен: $e');
    }

    final net = revenueToday - refundsToday;
    final avgCheck = paidCountToday == 0 ? 0 : revenueToday / paidCountToday;
    // В кассе = остаток на начало + валовый приход − возвраты − изъятия
    // (тот же расчёт, что на экране кассы).
    final inDrawer = opening + grossToday - refundsToday - withdrawalsToday;

    return DashboardData(
      revenueToday: revenueToday,
      refundsToday: refundsToday,
      netToday: net,
      inDrawer: inDrawer,
      paymentsCountToday: paidCountToday,
      averageCheck: avgCheck,
      methodTotals: methodTotals,
      last7: [
        for (final d in days)
          DayRevenue(date: d, revenue: revByIso[_iso(d)] ?? 0),
      ],
      newPatientsToday: newPatientsToday,
      totalPatients: totalPatients,
      analysesToday: analysesToday,
      fibroscanToday: fibroscanToday,
      visitsCountToday: visitsCount,
      visitsByStatus: visitsByStatus,
      inventoryLowCount: inventoryLow,
      inventoryExpiryCount: inventoryExpiry,
    );
  }

  /// Дешёвый `count()`; при недоступности агрегации — ограниченное чтение
  /// (потолок 1000), чтобы карточка не падала. [q] — коллекция или запрос.
  Future<int> _safeCount(Query<Map<String, dynamic>> q) async {
    try {
      final agg = await q.count().get();
      return agg.count ?? 0;
    } catch (e) {
      debugPrint('dashboard: count() фолбэк на чтение: $e');
      try {
        final snap = await q.limit(1000).get();
        return snap.docs.length;
      } catch (e2) {
        debugPrint('dashboard: ограниченный подсчёт не удался: $e2');
        return 0;
      }
    }
  }

  /// Дата → ISO `YYYY-MM-DD` (формат хранения `day` по всей кассе/складу).
  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Провайдер тонкого дашборд-репозитория. Переиспользует складской репозиторий
/// (только чтение) для алертов, свою БД — для остальных агрегатов.
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(
    FirebaseFirestore.instance,
    ref.watch(warehouseRepositoryProvider),
  ),
);

/// Агрегаты дашборда (keep-alive: считаются один раз и переиспользуются между
/// заходами на экран; обновляются через `ref.invalidate(dashboardProvider)`).
final dashboardProvider = FutureProvider<DashboardData>(
  (ref) => ref.watch(dashboardRepositoryProvider).load(),
);

/// Выручка за один день графика (оплаченные платежи, созданные в этот день).
class DayRevenue {
  const DayRevenue({required this.date, required this.revenue});

  final DateTime date;
  final num revenue;
}

/// Снимок бизнес-показателей клиники за сегодня для директорского дашборда.
/// Все суммы — в KGS «сом».
class DashboardData {
  const DashboardData({
    required this.revenueToday,
    required this.refundsToday,
    required this.netToday,
    required this.inDrawer,
    required this.paymentsCountToday,
    required this.averageCheck,
    required this.methodTotals,
    required this.last7,
    required this.newPatientsToday,
    required this.totalPatients,
    required this.analysesToday,
    required this.fibroscanToday,
    required this.visitsCountToday,
    required this.visitsByStatus,
    required this.inventoryLowCount,
    required this.inventoryExpiryCount,
  });

  /// Выручка сегодня (Σ оплаченных платежей, созданных сегодня).
  final num revenueToday;

  /// Возвраты, оформленные сегодня (по `refund_day`).
  final num refundsToday;

  /// Чистая выручка = выручка − возвраты.
  final num netToday;

  /// Наличные в кассе сейчас (остаток на начало + приход − возвраты − изъятия).
  final num inDrawer;

  /// Число оплаченных платежей сегодня.
  final int paymentsCountToday;

  /// Средний чек = выручка / число оплаченных платежей (0, если платежей нет).
  final num averageCheck;

  /// Выручка сегодня по способам оплаты (`cash`/`card`/`transfer`).
  final Map<String, num> methodTotals;

  /// Выручка по дням за последние 7 дней (для графика, слева направо).
  final List<DayRevenue> last7;

  final int newPatientsToday;
  final int totalPatients;
  final int analysesToday;
  final int fibroscanToday;

  /// Всего приёмов сегодня.
  final int visitsCountToday;

  /// Приёмы сегодня по статусам (`awaiting_payment`/`paid`/`done`).
  final Map<String, int> visitsByStatus;

  /// Товаров «мало на складе» (остаток ≤ минимума).
  final int inventoryLowCount;

  /// Товаров с истекающим/истёкшим сроком годности.
  final int inventoryExpiryCount;

  /// Есть ли складские алерты (для карточки «Склад»).
  bool get hasInventoryAlerts =>
      inventoryLowCount > 0 || inventoryExpiryCount > 0;
}
