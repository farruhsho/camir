import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/warehouse_repository.dart';
import '../domain/warehouse_movement.dart';
import '../domain/warehouse_product.dart';

/// Склад на Firestore (без бэкенда): каталог товаров с текущим остатком,
/// бейдж «мало» при остатке ≤ минимума, добавление товара, приход/расход по
/// товару (кол-во + причина + дата) и журнал движений. Остаток считается из
/// коллекции `stock_movements` на клиенте.
///
/// Действия гейтятся правами: `inventory.manage` — товар/приход,
/// `inventory.write_off` — расход. Просмотр — `inventory.read` (гейт в меню).
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.can('inventory.manage') ?? false;
    final canWriteOff = user?.can('inventory.write_off') ?? false;

    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final products = _ProductsCard(
      canManage: canManage,
      canWriteOff: canWriteOff,
    );
    final log = const _MovementsCard();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Склад'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(warehouseStockProvider);
              ref.invalidate(warehouseMovementsProvider);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: products),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: log),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [products, const SizedBox(height: 16), log],
              ),
      ),
    );
  }
}

// ═══ Карточка: товары с остатком ═════════════════════════════════════════════

class _ProductsCard extends ConsumerWidget {
  const _ProductsCard({required this.canManage, required this.canWriteOff});

  final bool canManage;
  final bool canWriteOff;

  Future<void> _addProduct(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ProductDialog(),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(warehouseStockProvider);
      _snack(context, 'Товар добавлен');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(warehouseStockProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(icon: Icons.inventory_2_outlined, text: 'Товары'),
          if (canManage) ...[
            const SizedBox(height: 14),
            GradientButton(
              label: 'Добавить товар',
              icon: Icons.add,
              onPressed: () => _addProduct(context, ref),
            ),
          ],
          const SizedBox(height: 12),
          AsyncValueWidget<List<ProductStock>>(
            value: stock,
            onRetry: () => ref.invalidate(warehouseStockProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Товаров пока нет',
                      style: TextStyle(color: AppColors.sub),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final ps in items)
                    _ProductTile(
                      data: ps,
                      canManage: canManage,
                      canWriteOff: canWriteOff,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({
    required this.data,
    required this.canManage,
    required this.canWriteOff,
  });

  final ProductStock data;
  final bool canManage;
  final bool canWriteOff;

  Future<void> _move(BuildContext context, WidgetRef ref, String kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MovementDialog(product: data.product, kind: kind),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(warehouseStockProvider);
      ref.invalidate(warehouseMovementsProvider);
      _snack(
        context,
        kind == WarehouseMovement.kIn ? 'Приход оформлен' : 'Расход списан',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = data.product;
    final subtitle = [
      if (p.category != null && p.category!.isNotEmpty) p.category!,
      'ед. ${p.unit}',
      if (p.minStock != null) 'мин. ${_trimNum(p.minStock!)}',
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.sub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_trimNum(data.stock)} ${p.unit}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.ink,
                    ),
                  ),
                  if (data.low) ...[
                    const SizedBox(height: 4),
                    const StatusBadge('мало', kind: BadgeKind.warning),
                  ],
                ],
              ),
            ],
          ),
          if (canManage || canWriteOff) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canManage)
                  TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Приход'),
                    onPressed: () => _move(context, ref, WarehouseMovement.kIn),
                  ),
                if (canWriteOff)
                  TextButton.icon(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Расход'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                    onPressed: () =>
                        _move(context, ref, WarehouseMovement.kOut),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══ Карточка: журнал движений ═══════════════════════════════════════════════

class _MovementsCard extends ConsumerWidget {
  const _MovementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(warehouseMovementsProvider);
    // Имена товаров берём из уже загруженного списка остатков (без доп. запроса).
    final names = <String, String>{
      for (final ps
          in ref.watch(warehouseStockProvider).valueOrNull ?? const [])
        ps.product.id: ps.product.name,
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.swap_vert_outlined,
                  text: 'Движения',
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(warehouseMovementsProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncValueWidget<List<WarehouseMovement>>(
            value: movements,
            onRetry: () => ref.invalidate(warehouseMovementsProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Движений пока нет',
                      style: TextStyle(color: AppColors.sub),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final m in items)
                    _MovementTile(movement: m, name: names[m.productId]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, this.name});

  final WarehouseMovement movement;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final isIn = movement.isIn;
    final sign = isIn ? '+' : '−';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isIn ? Icons.south_west : Icons.north_east,
            size: 18,
            color: isIn ? AppColors.green : AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Товар',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    movement.kindLabel,
                    if (movement.reason != null && movement.reason!.isNotEmpty)
                      movement.reason!,
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${_trimNum(movement.qty)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isIn ? AppColors.green : AppColors.red,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _displayDate(movement.date),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══ Диалог: добавить товар ══════════════════════════════════════════════════

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog();

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _minStock = TextEditingController();
  String _unit = kWarehouseUnits.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final minRaw = _minStock.text.trim().replaceAll(',', '.');
      await ref
          .read(warehouseRepositoryProvider)
          .addProduct(
            name: _name.text.trim(),
            category: _category.text.trim().isEmpty
                ? null
                : _category.text.trim(),
            unit: _unit,
            minStock: minRaw.isEmpty ? null : num.tryParse(minRaw),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый товар'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'Категория (необязательно)',
                  hintText: 'расходники, реактивы…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Единица',
                        isDense: true,
                      ),
                      items: [
                        for (final u in kWarehouseUnits)
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => setState(() => _unit = v ?? _unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStock,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Мин. остаток',
                        hintText: 'необязательно',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Добавить'),
        ),
      ],
    );
  }
}

// ═══ Диалог: приход / расход ═════════════════════════════════════════════════

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog({required this.product, required this.kind});

  final WarehouseProduct product;
  final String kind;

  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  final _date = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isIn => widget.kind == WarehouseMovement.kIn;

  @override
  void initState() {
    super.initState();
    _date.text = _fmtDmy(DateTime.now());
  }

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(2000);
    final last = DateTime(now.year + 1);
    var initial = _parseDmy(_date.text) ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: _isIn ? 'Дата прихода' : 'Дата расхода',
    );
    if (picked != null) setState(() => _date.text = _fmtDmy(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final iso = _isoFromDmy(_date.text);
    if (iso == null) {
      setState(() => _error = 'Укажите корректную дату (ДД.ММ.ГГГГ)');
      return;
    }
    final qty = num.tryParse(_qty.text.trim().replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Количество должно быть больше нуля');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(warehouseRepositoryProvider)
          .addMovement(
            productId: widget.product.id,
            kind: widget.kind,
            qty: qty,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
            date: iso,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      title: Text(_isIn ? 'Приход' : 'Расход'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${p.name} · ед. ${p.unit}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qty,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Количество (${p.unit})',
                  isDense: true,
                ),
                validator: (v) {
                  final q = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (q == null || q <= 0) return 'Больше нуля';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: 'Причина (необязательно)',
                  hintText: _isIn ? 'поставка, возврат…' : 'плановый расход…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _date,
                keyboardType: TextInputType.number,
                inputFormatters: const [DateInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Дата',
                  hintText: 'ДД.ММ.ГГГГ',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Выбрать в календаре',
                    icon: const Icon(Icons.calendar_today, size: 18),
                    onPressed: _pickDate,
                  ),
                ),
                validator: (v) =>
                    _parseDmy(v ?? '') == null ? 'Неверная дата' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isIn ? 'Оприходовать' : 'Списать'),
        ),
      ],
    );
  }
}

// ═══ Общие мелочи ════════════════════════════════════════════════════════════

/// Заголовок секции карточки: иконка бренда + текст.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

/// Число без хвостовых нулей: 5.0 → «5», 5.5 → «5.5».
String _trimNum(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _fmtDmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// Парсит `ДД.ММ.ГГГГ` в [DateTime] (с проверкой на «перетекание»), иначе null.
DateTime? _parseDmy(String raw) {
  final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(raw.trim());
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000) {
    return null;
  }
  final d = DateTime(year, month, day);
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}

/// `ДД.ММ.ГГГГ` → ISO `YYYY-MM-DD` для хранения, либо null.
String? _isoFromDmy(String raw) {
  final d = _parseDmy(raw);
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// ISO `YYYY-MM-DD…` → отображение `ДД.ММ.ГГГГ`; иначе как есть.
String _displayDate(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (m == null) return raw;
  return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}
