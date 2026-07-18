import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../data/payments_repository.dart';
import '../data/services_repository.dart';
import '../domain/payment.dart';
import '../domain/service_item.dart';
import 'price_list_screen.dart';

String _som(num v) => formatMoney(v.toString());

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
            final refundedSum =
                refundsToday.fold<num>(0, (s, p) => s + p.total);
            final net = gross - refundedSum;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Report(
                          gross: gross,
                          net: net,
                          refundedSum: refundedSum,
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
      await ref
          .read(paymentsRepositoryProvider)
          .refund(p.id, reason: reason);
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
    required this.net,
    required this.refundedSum,
    required this.count,
    required this.payments,
  });

  /// Приход за день (валовый, все созданные сегодня).
  final num gross;

  /// Чистый остаток в кассе за день (приход − возвраты).
  final num net;

  /// Возвраты, оформленные сегодня.
  final num refundedSum;
  final int count;
  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    num byMethod(String m) => payments
        .where((p) => p.method == m)
        .fold<num>(0, (s, p) => s + p.total);

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
                  icon: Icons.account_balance_wallet_outlined,
                  value: _som(net),
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

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
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
                    style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StatusBadge(
                        p.statusLabel,
                        kind: p.isRefunded ? BadgeKind.danger : BadgeKind.success,
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

/// Диалог проведения платежа. Возвращает созданный [Payment] (или null).
class _NewPaymentDialog extends ConsumerStatefulWidget {
  const _NewPaymentDialog();

  @override
  ConsumerState<_NewPaymentDialog> createState() => _NewPaymentDialogState();
}

class _NewPaymentDialogState extends ConsumerState<_NewPaymentDialog> {
  final _name = TextEditingController();
  final List<PaymentItem> _items = <PaymentItem>[];
  String _method = kPayCash;
  final _note = TextEditingController();
  String? _patientId;
  String? _mrn;
  bool _saving = false;

  num get _total => _items.fold<num>(0, (s, i) => s + i.subtotal);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPatient() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (_) => const _PatientPickerDialog(),
    );
    if (!mounted || patient == null) return;
    setState(() {
      _patientId = patient.id;
      _mrn = patient.mrn;
      _name.text = patient.fullName;
    });
  }

  void _clearPatient() => setState(() {
    _patientId = null;
    _mrn = null;
  });

  Future<void> _addFromCatalog() async {
    final chosen = await showDialog<ServiceItem>(
      context: context,
      builder: (_) => const _ServicePickerDialog(),
    );
    if (!mounted || chosen == null) return;
    setState(
      () => _items.add(PaymentItem(service: chosen.name, price: chosen.price)),
    );
  }

  Future<void> _addCustom() async {
    final item = await showDialog<PaymentItem>(
      context: context,
      builder: (_) => const _CustomLineDialog(),
    );
    if (!mounted || item == null) return;
    setState(() => _items.add(item));
  }

  void _setQty(int index, int delta) {
    final it = _items[index];
    final q = (it.qty + delta).clamp(1, 999);
    setState(() => _items[index] = it.copyWith(qty: q));
  }

  Future<void> _save() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);
    try {
      final payment = await ref
          .read(paymentsRepositoryProvider)
          .create(
            patientId: _patientId,
            patientName: _name.text,
            mrn: _mrn,
            items: _items,
            method: _method,
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
              // Пациент (опционально).
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      // Ручная правка ФИО отвязывает карту — иначе платёж ушёл
                      // бы с patient_id одной карты и именем другой.
                      onChanged: (_) {
                        if (_patientId != null) {
                          setState(() {
                            _patientId = null;
                            _mrn = null;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Пациент (ФИО)',
                        isDense: true,
                        helperText: _patientId != null
                            ? 'Карта № $_mrn'
                            : 'Без карты — разовая оплата',
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
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Способ оплаты',
                  isDense: true,
                ),
                items: [
                  for (final m in kPayMethods)
                    DropdownMenuItem(
                      value: m,
                      child: Text(kPayMethodLabels[m]!),
                    ),
                ],
                onChanged: (v) => setState(() => _method = v ?? kPayCash),
              ),
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
          onPressed: (_saving || _items.isEmpty) ? null : _save,
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
          Text('${it.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
            onPressed: () => setState(() => _items.removeAt(i)),
          ),
        ],
      ),
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
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
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
            final price = num.parse(
              _price.text.trim().replaceAll(',', '.'),
            );
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
