import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../data/cash_repository.dart';
import '../data/payments_repository.dart';
import '../data/services_repository.dart';
import '../domain/cash_shift.dart';
import '../domain/cash_withdrawal.dart';
import '../domain/payment.dart';
import '../domain/service_item.dart';
import 'price_list_screen.dart';

String _som(num v) => formatMoney(v.toString());

/// Дата+время для детального просмотра, локальное время `dd.MM.yyyy HH:mm`.
String _fmtDateTime(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Только время `HH:mm` (для строки статуса смены).
String _fmtTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

/// SnackBar-хелпер экрана кассы.
void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: error ? AppColors.red : null),
  );
}

/// Касса «Цадмир»: дневной отчёт (собрано / платежей / возвраты) + список
/// платежей за день + проведение нового платежа и возврат. Валюта — KGS «сом».
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (!(user?.can('payments.read') ?? false)) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Касса')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Недостаточно прав для доступа к кассе.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final canCreate = user?.can('payments.create') ?? false;
    final canManageServices = user?.can('services.manage') ?? false;
    final payments = ref.watch(todayPaymentsProvider);
    final refundsToday =
        ref.watch(todayRefundsProvider).valueOrNull ?? const <Payment>[];
    // Смена и изъятия за день — нужны для строки статуса и расчёта «В кассе».
    final shift = ref.watch(currentShiftProvider).valueOrNull;
    final withdrawals =
        ref.watch(todayWithdrawalsProvider).valueOrNull ??
        const <CashWithdrawal>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Касса'),
        actions: [
          if (canManageServices)
            IconButton(
              tooltip: 'Прайс-лист',
              icon: const Icon(Icons.sell_outlined, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PriceListScreen(),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              ref.invalidate(todayPaymentsProvider);
              ref.invalidate(todayRefundsProvider);
              ref.invalidate(currentShiftProvider);
              ref.invalidate(todayWithdrawalsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _newPayment(context, ref),
              icon: const Icon(Icons.add_card),
              label: const Text('Новый платёж'),
            )
          : null,
      body: SafeArea(
        child: AsyncValueWidget<List<Payment>>(
          value: payments,
          onRetry: () => ref.invalidate(todayPaymentsProvider),
          builder: (items) {
            // Приход в кассу за день = все платежи, СОЗДАННЫЕ сегодня (валовый).
            final gross = items.fold<num>(0, (s, p) => s + p.total);
            // Расход = возвраты, оформленные СЕГОДНЯ (по refund_day) — деньги,
            // ушедшие из сегодняшней кассы, даже если платёж был создан раньше.
            final refundedSum = refundsToday.fold<num>(
              0,
              (s, p) => s + p.total,
            );
            // Изъятия (расход из кассы), оформленные сегодня.
            final withdrawnSum = withdrawals.fold<num>(
              0,
              (s, w) => s + w.amount,
            );
            // Начальный остаток учитываем только при открытой смене.
            final num opening = (shift != null && shift.isOpen)
                ? shift.openingAmount
                : 0;
            // В кассе = остаток на начало + приход − возвраты − изъятия.
            final inDrawer = opening + gross - refundedSum - withdrawnSum;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ShiftBar(
                          shift: shift,
                          canManage: canCreate,
                          onOpen: () => _openShift(context, ref),
                          onWithdraw: () => _withdraw(context, ref),
                          onClose: () =>
                              _closeShift(context, ref, shift!, inDrawer),
                        ),
                        const SizedBox(height: 16),
                        _Report(
                          gross: gross,
                          inDrawer: inDrawer,
                          refundedSum: refundedSum,
                          withdrawnSum: withdrawnSum,
                          count: items.length,
                          payments: items,
                        ),
                        const SizedBox(height: 16),
                        const _SectionTitle('Платежи за сегодня'),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                'Сегодня платежей ещё не было',
                                style: TextStyle(color: AppColors.sub),
                              ),
                            ),
                          )
                        else
                          for (final p in items)
                            _PaymentTile(
                              payment: p,
                              canRefund: user?.can('payments.refund') ?? false,
                              onRefund: () => _refund(context, ref, p),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _newPayment(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<Payment>(
      context: context,
      builder: (_) => const _NewPaymentDialog(),
    );
    if (created != null && context.mounted) {
      ref.invalidate(todayPaymentsProvider);
      await _showReceipt(context, created);
    }
  }

  /// Открыть смену: спросить остаток на начало, создать смену.
  Future<void> _openShift(BuildContext context, WidgetRef ref) async {
    final amount = await showDialog<num>(
      context: context,
      builder: (_) => const _OpenShiftDialog(),
    );
    if (amount == null) return;
    try {
      await ref.read(cashRepositoryProvider).openShift(amount);
      if (context.mounted) {
        ref.invalidate(currentShiftProvider);
        _snack(context, 'Смена открыта');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  /// Закрыть смену: показать ожидаемую сумму, ввести факт, показать разницу.
  Future<void> _closeShift(
    BuildContext context,
    WidgetRef ref,
    CashShift shift,
    num expected,
  ) async {
    final counted = await showDialog<num>(
      context: context,
      builder: (_) => _CloseShiftDialog(expected: expected),
    );
    if (counted == null) return;
    try {
      await ref.read(cashRepositoryProvider).closeShift(shift.id, counted);
      if (context.mounted) {
        ref.invalidate(currentShiftProvider);
        final diff = counted - expected;
        final msg = diff == 0
            ? 'Смена закрыта. Касса сходится.'
            : diff > 0
            ? 'Смена закрыта. Излишек ${_som(diff)}.'
            : 'Смена закрыта. Недостача ${_som(diff.abs())}.';
        _snack(context, msg);
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  /// Изъятие из кассы: сумма + причина.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({num amount, String reason})>(
      context: context,
      builder: (_) => const _WithdrawDialog(),
    );
    if (result == null) return;
    try {
      await ref
          .read(cashRepositoryProvider)
          .withdraw(result.amount, result.reason);
      if (context.mounted) {
        ref.invalidate(todayWithdrawalsProvider);
        _snack(context, 'Изъятие оформлено · ${_som(result.amount)}');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _refund(BuildContext context, WidgetRef ref, Payment p) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Оформить возврат?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.patientName} · ${_som(p.total)} · ${p.methodLabel}',
              style: const TextStyle(color: AppColors.sub),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Причина (необязательно)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Возврат'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (ok != true) return;
    try {
      await ref.read(paymentsRepositoryProvider).refund(p.id, reason: reason);
      if (context.mounted) {
        ref.invalidate(todayPaymentsProvider);
        ref.invalidate(todayRefundsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _showReceipt(BuildContext context, Payment p) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Чек'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.patientName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              for (final it in p.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          it.qty > 1 ? '${it.service} ×${it.qty}' : it.service,
                          style: const TextStyle(color: AppColors.sub),
                        ),
                      ),
                      Text(_som(it.subtotal)),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Итого',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _som(p.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.methodLabel,
                style: const TextStyle(color: AppColors.sub, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({
    required this.gross,
    required this.inDrawer,
    required this.refundedSum,
    required this.withdrawnSum,
    required this.count,
    required this.payments,
  });

  /// Приход за день (валовый, все созданные сегодня).
  final num gross;

  /// Остаток в кассе = остаток на начало + приход − возвраты − изъятия.
  final num inDrawer;

  /// Возвраты, оформленные сегодня.
  final num refundedSum;

  /// Изъятия из кассы, оформленные сегодня.
  final num withdrawnSum;
  final int count;
  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    // Разбивка по способам через methodBreakdown(): смешанный платёж отдаёт
    // наличную часть в «Наличные», карточную — в «Карту» и т.д.
    num byMethod(String m) =>
        payments.fold<num>(0, (s, p) => s + (p.methodBreakdown()[m] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 116,
          child: Row(
            children: [
              Expanded(
                child: KpiCard(
                  icon: Icons.payments_outlined,
                  value: _som(gross),
                  label: 'Собрано сегодня',
                  accent: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  icon: Icons.undo_outlined,
                  value: _som(refundedSum),
                  label: 'Возвраты',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  icon: Icons.north_east,
                  value: _som(withdrawnSum),
                  label: 'Изъято',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KpiCard(
                  icon: Icons.account_balance_wallet_outlined,
                  value: _som(inDrawer),
                  label: 'В кассе',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(label: 'Платежей: $count'),
            for (final m in kPayMethods)
              Pill(
                label: '${kPayMethodLabels[m]}: ${_som(byMethod(m))}',
                color: AppColors.tealDark,
                bg: AppColors.tealBg,
              ),
          ],
        ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.payment,
    required this.canRefund,
    required this.onRefund,
  });

  final Payment payment;
  final bool canRefund;
  final VoidCallback onRefund;

  /// Детальный просмотр платежа со ВСЕМИ полями (список → деталь).
  void _showDetail(BuildContext context) {
    final p = payment;
    showDetailSheet(
      context,
      title: 'Платёж',
      rows: <DetailRow>[
        DetailRow('Пациент', p.patientName, strong: true),
        if (p.mrn != null) DetailRow('Карта №', p.mrn!),
        const DetailRow.section('Услуги'),
        for (final it in p.items)
          DetailRow(
            it.service,
            '${_som(it.price)} × ${it.qty} = ${_som(it.subtotal)}',
          ),
        const DetailRow.section('Оплата'),
        DetailRow('Итого', _som(p.total), strong: true),
        DetailRow('Способ оплаты', p.methodLabel),
        DetailRow('Статус', p.statusLabel),
        if (p.note != null) DetailRow('Комментарий', p.note!),
        DetailRow('День', p.day),
        if (p.isRefunded) ...[
          const DetailRow.section('Возврат'),
          if (p.refundReason != null) DetailRow('Причина', p.refundReason!),
          if (p.refundedAt != null)
            DetailRow('Оформлен', _fmtDateTime(p.refundedAt)),
        ],
        const DetailRow.section('Служебное'),
        if (p.createdBy != null) DetailRow('Кем проведён', p.createdBy!),
        if (p.createdAt != null) DetailRow('Создан', _fmtDateTime(p.createdAt)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _showDetail(context),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (p.mrn != null) ...[
                        const SizedBox(width: 8),
                        Pill(label: '№ ${p.mrn}'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.itemsSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StatusBadge(
                        p.statusLabel,
                        kind: p.isRefunded
                            ? BadgeKind.danger
                            : BadgeKind.success,
                      ),
                      const SizedBox(width: 6),
                      Pill(label: p.methodLabel),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _som(p.total),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: p.isRefunded ? AppColors.muted : AppColors.ink,
                    decoration: p.isRefunded
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (canRefund && !p.isRefunded)
                  TextButton(
                    onPressed: onRefund,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.red,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Возврат'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
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

/// Строка статуса смены + управление кассой (открыть / изъять / закрыть).
/// Действия видны только при праве `payments.create` ([canManage]).
class _ShiftBar extends StatelessWidget {
  const _ShiftBar({
    required this.shift,
    required this.canManage,
    required this.onOpen,
    required this.onWithdraw,
    required this.onClose,
  });

  final CashShift? shift;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onWithdraw;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    if (s == null) {
      // Смена не открыта.
      return AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_outlined, color: AppColors.muted),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Смена не открыта',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Откройте смену, чтобы вести кассу за день.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.sub),
                  ),
                ],
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Открыть смену'),
              ),
            ],
          ],
        ),
      );
    }
    // Смена открыта.
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusBadge('Смена открыта', kind: BadgeKind.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'с ${_fmtTime(s.openedAt)} · старт ${_som(s.openingAmount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onWithdraw,
                    icon: const Icon(Icons.north_east, size: 18),
                    label: const Text('Изъять'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Закрыть смену'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Диалог открытия смены: остаток на начало (KGS «сом»). Возвращает [num].
class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();

  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Открыть смену'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money(),
            decoration: const InputDecoration(
              labelText: 'Сумма на начало, сом',
              isDense: true,
            ),
            validator: (v) {
              final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
              if (n == null || n < 0) return 'Введите сумму';
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final n = num.parse(_amount.text.trim().replaceAll(',', '.'));
            Navigator.pop(context, n);
          },
          child: const Text('Открыть'),
        ),
      ],
    );
  }
}

/// Диалог закрытия смены: показывает ожидаемую сумму, принимает факт и
/// показывает разницу «вживую». Возвращает пересчитанную сумму ([num]).
class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.expected});

  final num expected;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _counted = TextEditingController();
  num? _countedVal;

  @override
  void initState() {
    super.initState();
    _counted.addListener(() {
      setState(() {
        _countedVal = num.tryParse(_counted.text.trim().replaceAll(',', '.'));
      });
    });
  }

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counted = _countedVal;
    final diff = counted == null ? null : counted - widget.expected;
    return AlertDialog(
      title: const Text('Закрыть смену'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ожидается в кассе',
                      style: TextStyle(color: AppColors.sub),
                    ),
                  ),
                  Text(
                    _som(widget.expected),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _counted,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: money(),
                decoration: const InputDecoration(
                  labelText: 'Пересчитано по факту, сом',
                  isDense: true,
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (n == null || n < 0) return 'Введите сумму';
                  return null;
                },
              ),
              if (diff != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Разница',
                        style: TextStyle(color: AppColors.sub),
                      ),
                    ),
                    Text(
                      diff == 0
                          ? _som(0)
                          : diff > 0
                          ? '+${_som(diff)}'
                          : '−${_som(diff.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: diff == 0 ? AppColors.green : AppColors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final n = num.parse(_counted.text.trim().replaceAll(',', '.'));
            Navigator.pop(context, n);
          },
          child: const Text('Закрыть смену'),
        ),
      ],
    );
  }
}

/// Диалог изъятия из кассы: сумма (обязательно) + причина (обязательно).
/// Возвращает запись `(amount, reason)`.
class _WithdrawDialog extends StatefulWidget {
  const _WithdrawDialog();

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Изъятие из кассы'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: money(),
                decoration: const InputDecoration(
                  labelText: 'Сумма, сом',
                  isDense: true,
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Введите сумму';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Причина',
                  isDense: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Укажите причину' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final n = num.parse(_amount.text.trim().replaceAll(',', '.'));
            Navigator.pop(context, (amount: n, reason: _reason.text.trim()));
          },
          child: const Text('Изъять'),
        ),
      ],
    );
  }
}

/// Диалог проведения платежа. Возвращает созданный [Payment] (или null).
class _NewPaymentDialog extends ConsumerStatefulWidget {
  const _NewPaymentDialog();

  @override
  ConsumerState<_NewPaymentDialog> createState() => _NewPaymentDialogState();
}

class _NewPaymentDialogState extends ConsumerState<_NewPaymentDialog> {
  final _name = TextEditingController();
  final List<PaymentItem> _items = <PaymentItem>[];
  final _note = TextEditingController();
  String? _patientId;
  String? _mrn;
  bool _saving = false;

  // ── Инлайн-поиск карты по мере ввода ФИО ──────────────────────────────────
  Timer? _searchDebounce;
  List<Patient> _suggestions = const <Patient>[];
  bool _searching = false;
  bool _showSuggestions = false;

  // ── Разбивка оплаты (наличные / карта / перевод) ──────────────────────────
  final _cash = TextEditingController();
  final _card = TextEditingController();
  final _transfer = TextEditingController();
  // Кассир правил суммы вручную — не переустанавливаем дефолт при смене итога.
  bool _splitTouched = false;

  num get _total => _items.fold<num>(0, (s, i) => s + i.subtotal);

  num _amt(TextEditingController c) =>
      num.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  num get _cashAmt => _amt(_cash);
  num get _cardAmt => _amt(_card);
  num get _transferAmt => _amt(_transfer);
  num get _distributed => _cashAmt + _cardAmt + _transferAmt;

  /// Ненулевые способы оплаты (ключи [kPayCash]/[kPayCard]/[kPayTransfer]).
  Map<String, num> get _splitEntries => <String, num>{
    if (_cashAmt > 0) kPayCash: _cashAmt,
    if (_cardAmt > 0) kPayCard: _cardAmt,
    if (_transferAmt > 0) kPayTransfer: _transferAmt,
  };

  /// Можно проводить: есть услуги и ненулевые способы точно покрывают итог.
  bool get _balanced =>
      _items.isNotEmpty &&
      _total > 0 &&
      _splitEntries.isNotEmpty &&
      sameMoney(_distributed, _total);

  /// Денежное значение для префилла поля (без лишних нулей дробной части).
  String _moneyInput(num v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    _syncDefaultSplit();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _name.dispose();
    _note.dispose();
    _cash.dispose();
    _card.dispose();
    _transfer.dispose();
    super.dispose();
  }

  // ── Пациент ────────────────────────────────────────────────────────────────

  /// Правка ФИО в поле: отвязывает выбранную карту и запускает дебаунс-поиск.
  void _onNameChanged(String v) {
    if (_patientId != null) {
      _patientId = null;
      _mrn = null;
    }
    _showSuggestions = true;
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(v),
    );
  }

  /// Ищет сохранённые карты по ФИО / № карты / телефону (до 8 совпадений).
  Future<void> _runSearch(String q) async {
    final needle = q.trim();
    if (needle.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = const <Patient>[];
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    try {
      final page = await ref
          .read(patientsRepositoryProvider)
          .list(q: needle, limit: 8);
      if (mounted) setState(() => _suggestions = page.items);
    } catch (_) {
      if (mounted) setState(() => _suggestions = const <Patient>[]);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Привязывает выбранную карту: patientId + № карты + подставляет ФИО.
  void _selectPatient(Patient p) {
    _searchDebounce?.cancel();
    setState(() {
      _patientId = p.id;
      _mrn = p.mrn;
      _name.text = p.fullName;
      _suggestions = const <Patient>[];
      _showSuggestions = false;
      _searching = false;
    });
  }

  /// Резервный путь: полноэкранный диалог поиска карты.
  Future<void> _pickPatient() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (_) => const _PatientPickerDialog(),
    );
    if (!mounted || patient == null) return;
    _selectPatient(patient);
  }

  void _clearPatient() => setState(() {
    _patientId = null;
    _mrn = null;
  });

  // ── Услуги ──────────────────────────────────────────────────────────────────

  Future<void> _addFromCatalog() async {
    final chosen = await showDialog<ServiceItem>(
      context: context,
      builder: (_) => const _ServicePickerDialog(),
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _items.add(PaymentItem(service: chosen.name, price: chosen.price));
      _syncDefaultSplit();
    });
  }

  Future<void> _addCustom() async {
    final item = await showDialog<PaymentItem>(
      context: context,
      builder: (_) => const _CustomLineDialog(),
    );
    if (!mounted || item == null) return;
    setState(() {
      _items.add(item);
      _syncDefaultSplit();
    });
  }

  void _setQty(int index, int delta) {
    final it = _items[index];
    final q = (it.qty + delta).clamp(1, 999);
    setState(() {
      _items[index] = it.copyWith(qty: q);
      _syncDefaultSplit();
    });
  }

  void _removeItem(int i) => setState(() {
    _items.removeAt(i);
    _syncDefaultSplit();
  });

  // ── Разбивка оплаты ─────────────────────────────────────────────────────────

  /// Пока кассир не трогал разбивку — держим наличные = итог (карта/перевод
  /// пустые). Единый метод после любых изменений списка услуг.
  void _syncDefaultSplit() {
    if (_splitTouched) return;
    _cash.text = _total > 0 ? _moneyInput(_total) : '';
    _card.text = '';
    _transfer.text = '';
  }

  /// Правка «Наличные»/«Перевод»: остаток от итога автоматически идёт на «Карту».
  void _onCashOrTransferChanged(String _) {
    _splitTouched = true;
    final rest = _total - _cashAmt - _transferAmt;
    // Программная установка .text не вызывает onChanged «Карты» — рекурсии нет.
    _card.text = rest > 0 ? _moneyInput(rest) : '';
    setState(() {});
  }

  /// Правка «Карты» вручную: уважаем ввод, только пересчёт индикаторов.
  void _onCardChanged(String _) {
    _splitTouched = true;
    setState(() {});
  }

  Future<void> _save() async {
    if (_items.isEmpty || !_balanced) return;
    final entries = _splitEntries;
    final String method;
    final Map<String, num>? splits;
    if (entries.length > 1) {
      method = kPayMixed;
      splits = entries;
    } else {
      method = entries.keys.first;
      splits = null;
    }
    setState(() => _saving = true);
    try {
      final payment = await ref
          .read(paymentsRepositoryProvider)
          .create(
            patientId: _patientId,
            patientName: _name.text,
            mrn: _mrn,
            items: _items,
            method: method,
            splits: splits,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, payment);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый платёж'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Пациент (опционально) — инлайн-поиск карты по мере ввода.
              // Ручная правка ФИО отвязывает карту (иначе платёж ушёл бы с
              // patient_id одной карты и именем другой).
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: _onNameChanged,
                      decoration: InputDecoration(
                        labelText: 'Пациент (ФИО / № карты / телефон)',
                        isDense: true,
                        prefixIcon: const Icon(Icons.person_search, size: 20),
                        helperText: _patientId != null
                            ? 'Карта № $_mrn'
                            : 'Начните вводить — найдём карту, либо без карты',
                        suffixIcon: _patientId != null
                            ? IconButton(
                                tooltip: 'Отвязать карту',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearPatient,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Найти карту',
                    icon: const Icon(Icons.person_search),
                    onPressed: _pickPatient,
                  ),
                ],
              ),
              _buildSuggestions(),
              const SizedBox(height: 14),
              // Строки услуг.
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Услуги',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addFromCatalog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Из прайса'),
                  ),
                  TextButton.icon(
                    onPressed: _addCustom,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Своя'),
                  ),
                ],
              ),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Добавьте хотя бы одну услугу.',
                    style: TextStyle(color: AppColors.sub, fontSize: 12.5),
                  ),
                )
              else
                for (var i = 0; i < _items.length; i++) _itemRow(i),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Итого',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    _som(_total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Оплата (сом)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Введите наличные — остаток от итога уйдёт на карту. '
                'Можно смешивать способы.',
                style: TextStyle(color: AppColors.sub, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _amountField(
                      _cash,
                      'Наличные',
                      _onCashOrTransferChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _amountField(_card, 'Карта', _onCardChanged)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountField(
                      _transfer,
                      'Перевод',
                      _onCashOrTransferChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _distributionLine(),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: (_saving || !_balanced) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Провести · ${_som(_total)}'),
        ),
      ],
    );
  }

  Widget _itemRow(int i) {
    final it = _items[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.service, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  _som(it.price),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: () => _setQty(i, -1),
          ),
          Text(
            '${it.qty}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => _setQty(i, 1),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _som(it.subtotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.red,
            onPressed: () => _removeItem(i),
          ),
        ],
      ),
    );
  }

  /// Поле ввода суммы одного способа оплаты (KGS «сом»).
  Widget _amountField(
    TextEditingController c,
    String label,
    ValueChanged<String> onChanged,
  ) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: money(),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  /// Живая строка «Распределено: X / ИТОГО» + остаток/перебор красным.
  Widget _distributionLine() {
    final over = _distributed > _total;
    final balanced = _balanced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Распределено',
                style: TextStyle(color: AppColors.sub),
              ),
            ),
            Text(
              '${_som(_distributed)} / ${_som(_total)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: balanced ? AppColors.green : AppColors.ink,
              ),
            ),
          ],
        ),
        if (!sameMoney(_distributed, _total)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              over ? 'Перебор!' : 'Остаток: ${_som(_total - _distributed)}',
              style: const TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Панель совпадений под полем ФИО: карты из картотеки по мере ввода. Скрыта,
  /// когда карта уже выбрана или строка поиска пуста.
  Widget _buildSuggestions() {
    if (_patientId != null || !_showSuggestions) return const SizedBox.shrink();
    if (_name.text.trim().isEmpty) return const SizedBox.shrink();

    final Widget body;
    if (_searching && _suggestions.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_suggestions.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Карта не найдена — оплата без карты',
          style: TextStyle(color: AppColors.sub, fontSize: 12.5),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 176),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = _suggestions[i];
            final birth = p.birthDisplay;
            return ListTile(
              dense: true,
              leading: InitialsAvatar(p.initials, size: 32),
              title: Text(
                p.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '№ ${p.mrn}'
                '${p.phone != null ? ' · ${p.phone}' : ''}'
                '${birth.isNotEmpty ? ' · $birth' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectPatient(p),
            );
          },
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

/// Диалог выбора услуги из активного прайса.
class _ServicePickerDialog extends ConsumerWidget {
  const _ServicePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(activeServicesProvider);
    return AlertDialog(
      title: const Text('Выберите услугу'),
      content: SizedBox(
        width: 360,
        height: 380,
        child: AsyncValueWidget<List<ServiceItem>>(
          value: services,
          onRetry: () => ref.invalidate(activeServicesProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text(
                  'Прайс-лист пуст. Добавьте услуги в «Прайс-лист».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.sub),
                ),
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = items[i];
                return ListTile(
                  dense: true,
                  title: Text(s.name),
                  subtitle: s.category != null ? Text(s.category!) : null,
                  trailing: Text(
                    _som(s.price),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(context, s),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

/// Диалог ввода произвольной строки (услуга не из прайса).
class _CustomLineDialog extends StatefulWidget {
  const _CustomLineDialog();

  @override
  State<_CustomLineDialog> createState() => _CustomLineDialogState();
}

class _CustomLineDialogState extends State<_CustomLineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Своя услуга'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Цена, сом',
                  isDense: true,
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (n == null || n <= 0) return 'Введите цену';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final price = num.parse(_price.text.trim().replaceAll(',', '.'));
            Navigator.pop(
              context,
              PaymentItem(service: _name.text.trim(), price: price),
            );
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

/// Диалог поиска пациента по картотеке (ФИО / № карты / телефон).
class _PatientPickerDialog extends ConsumerStatefulWidget {
  const _PatientPickerDialog();

  @override
  ConsumerState<_PatientPickerDialog> createState() =>
      _PatientPickerDialogState();
}

class _PatientPickerDialogState extends ConsumerState<_PatientPickerDialog> {
  final _q = TextEditingController();
  List<Patient> _results = const <Patient>[];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  // Дебаунс: поиск бьёт большой запрос по картотеке, поэтому не на каждый
  // символ, а через 350 мс после остановки ввода.
  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = const <Patient>[]);
      return;
    }
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(patientsRepositoryProvider)
          .list(q: q, limit: 8);
      if (mounted) setState(() => _results = page.items);
    } catch (_) {
      if (mounted) setState(() => _results = const <Patient>[]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Найти пациента'),
      content: SizedBox(
        width: 380,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ФИО / № карты / телефон',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        'Введите запрос для поиска',
                        style: TextStyle(color: AppColors.sub),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        return ListTile(
                          dense: true,
                          leading: InitialsAvatar(p.initials, size: 34),
                          title: Text(p.fullName),
                          subtitle: Text(
                            '№ ${p.mrn}'
                            '${p.phone != null ? ' · ${p.phone}' : ''}',
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
