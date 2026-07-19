import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../payments/domain/payment.dart';
import '../../visits/domain/visit.dart';
import '../data/dashboard_repository.dart';

String _som(num v) => formatMoney(v.toString());

/// Короткая подпись дня недели (Пн…Вс) для оси графика выручки.
String _weekday(DateTime d) =>
    const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][(d.weekday - 1) % 7];

/// Директорский дашборд «Цадмир»: сводка бизнеса за сегодня (выручка, касса,
/// поток пациентов, лаборатория, склад) + график выручки за 7 дней.
/// Доступ по праву `dashboard.view` (директор/супер-админ).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (!(user?.can('dashboard.view') ?? false)) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Дашборд')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Недостаточно прав для доступа к дашборду.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final data = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Дашборд'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: AsyncValueWidget<DashboardData>(
          value: data,
          onRetry: () => ref.invalidate(dashboardProvider),
          builder: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _KpiGrid(data: d),
                      const SizedBox(height: 16),
                      _RevenueChartCard(days: d.last7),
                      const SizedBox(height: 16),
                      _MethodsCard(data: d),
                      const SizedBox(height: 16),
                      _VisitsCard(data: d),
                      const SizedBox(height: 16),
                      _InventoryCard(
                        low: d.inventoryLowCount,
                        expiring: d.inventoryExpiryCount,
                        onTap: () => context.go('/inventory'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Адаптивная сетка KPI-плиток: 4 колонки на широком экране, меньше на узком.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      KpiCard(
        icon: Icons.payments_outlined,
        value: _som(data.revenueToday),
        label: 'Выручка сегодня',
        accent: true,
      ),
      KpiCard(
        icon: Icons.account_balance_wallet_outlined,
        value: _som(data.inDrawer),
        label: 'В кассе',
      ),
      KpiCard(
        icon: Icons.receipt_long_outlined,
        value: formatInt(data.paymentsCountToday),
        label: 'Платежей',
      ),
      KpiCard(
        icon: Icons.calculate_outlined,
        value: _som(data.averageCheck),
        label: 'Средний чек',
      ),
      KpiCard(
        icon: Icons.person_add_alt_1_outlined,
        value: formatInt(data.newPatientsToday),
        label: 'Новых пациентов',
        trend: '∑ ${formatInt(data.totalPatients)}',
      ),
      KpiCard(
        icon: Icons.event_available_outlined,
        value: formatInt(data.visitsCountToday),
        label: 'Приёмов',
      ),
      KpiCard(
        icon: Icons.bloodtype_outlined,
        value: formatInt(data.analysesToday),
        label: 'Анализов',
      ),
      KpiCard(
        icon: Icons.monitor_heart_outlined,
        value: formatInt(data.fibroscanToday),
        label: 'Фибросканов',
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 900
            ? 4
            : w >= 600
            ? 3
            : w >= 380
            ? 2
            : 1;
        const gap = 12.0;
        final cardW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: cardW, height: 118, child: card),
          ],
        );
      },
    );
  }
}

/// Карточка «Выручка за 7 дней» — столбчатый график (fl_chart). Сегодняшний
/// столбец выделен тёмным тоном.
class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.days});

  final List<DayRevenue> days;

  @override
  Widget build(BuildContext context) {
    final maxRev = days.fold<num>(0, (m, d) => d.revenue > m ? d.revenue : m);
    final maxY = maxRev <= 0 ? 1.0 : maxRev.toDouble() * 1.25;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Выручка за 7 дней'),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.tealDark,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      _som(rod.toY),
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= days.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _weekday(days[i].date),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.sub,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: days[i].revenue.toDouble(),
                          width: 18,
                          color: i == days.length - 1
                              ? AppColors.tealDark
                              : AppColors.accent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Способы оплаты сегодня»: Pill на каждый способ + строка возвратов/чистой
/// выручки, если сегодня были возвраты.
class _MethodsCard extends StatelessWidget {
  const _MethodsCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Способы оплаты сегодня'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in kPayMethods)
                Pill(
                  label:
                      '${kPayMethodLabels[m]}: ${_som(data.methodTotals[m] ?? 0)}',
                  color: AppColors.tealDark,
                  bg: AppColors.tealBg,
                ),
            ],
          ),
          if (data.refundsToday > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Возвраты: −${_som(data.refundsToday)}  ·  '
              'Чистая выручка: ${_som(data.netToday)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Приёмы сегодня»: количество по статусам приёма.
class _VisitsCard extends StatelessWidget {
  const _VisitsCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Приёмы сегодня'),
          const SizedBox(height: 12),
          if (data.visitsCountToday == 0)
            const Text(
              'Сегодня приёмов ещё не было',
              style: TextStyle(color: AppColors.sub),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final st in const [
                  kVisitAwaitingPayment,
                  kVisitPaid,
                  kVisitDone,
                ])
                  Pill(
                    label:
                        '${kVisitStatusLabels[st]}: ${data.visitsByStatus[st] ?? 0}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Карточка «Склад» — сводка алертов (мало / истекает). Тап ведёт на /inventory.
class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.low,
    required this.expiring,
    required this.onTap,
  });

  final int low;
  final int expiring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAlerts = low > 0 || expiring > 0;
    final (Color iconColor, Color iconBg) = hasAlerts
        ? (AppColors.amber, AppColors.amberBg)
        : (AppColors.green, AppColors.greenBg);
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.inventory_2_outlined, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Склад',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasAlerts
                      ? '$low мало · $expiring истекает'
                      : 'Всё в норме',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: AppColors.ink,
    ),
  );
}
