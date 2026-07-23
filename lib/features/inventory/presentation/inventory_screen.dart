import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/xlsx_export.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/categories_repository.dart';
import '../data/warehouse_repository.dart';
import '../domain/warehouse_movement.dart';
import '../domain/warehouse_product.dart';
import 'warehouse_pdf.dart';

/// Склад на Firestore (без бэкенда): каталог товаров с текущим остатком,
/// бейдж «мало» при остатке ≤ минимума, добавление/правка/мягкое удаление
/// товара, приход/расход по товару (кол-во + причина + дата), сторно движения
/// и журнал движений. Остаток ведётся авторитетным полем `products/{id}.stock`.
///
/// Действия гейтятся правами: `inventory.manage` — товар (создание/правка) и
/// приход, `inventory.write_off` — расход. Удаление товара и сторно движения —
/// только супер-админ (`isSuperuser`). Просмотр — `inventory.read` (гейт в меню).
/// Тап по строке товара/движения открывает детальный просмотр со всеми полями.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.can('inventory.manage') ?? false;
    final canWriteOff = user?.can('inventory.write_off') ?? false;
    final isSuperuser = user?.isSuperuser ?? false;

    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final products = _ProductsCard(
      canManage: canManage,
      canWriteOff: canWriteOff,
      isSuperuser: isSuperuser,
    );
    final log = _MovementsCard(isSuperuser: isSuperuser);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Склад'),
        actions: [
          IconButton(
            tooltip: 'Экспорт / Отчёт',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _exportReport(context, ref),
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _AlertsCard(),
            wide
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
          ],
        ),
      ),
    );
  }

  /// Складской отчёт: пользователь выбирает печать (PDF → принтер) или выгрузку
  /// в Excel. Данные без периода — весь текущий каталог остатков.
  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final items = ref.read(warehouseStockProvider).valueOrNull;
    if (items == null || items.isEmpty) {
      _snack(context, 'Нет данных для отчёта');
      return;
    }
    final format = await pickExportFormat(context);
    if (format == null || !context.mounted) return;
    try {
      if (format == ExportFormat.printPdf) {
        await printWarehouseReport(items);
      } else {
        // Те же колонки, что и в PDF-отчёте (warehouse_pdf.dart):
        // Товар · Категория · Ед. · Остаток · Мин. · Срок годности · Статус.
        const headers = <String>[
          'Товар',
          'Категория',
          'Ед.',
          'Остаток',
          'Мин.',
          'Срок годности',
          'Статус',
        ];
        final rows = <List<Object?>>[
          for (final ps in items)
            <Object?>[
              ps.product.name,
              ps.product.category ?? '—',
              ps.product.unit,
              _trimNum(ps.stock),
              ps.product.minStock != null
                  ? _trimNum(ps.product.minStock!)
                  : '—',
              ps.product.expiry != null ? _fmtDmy(ps.product.expiry!) : '—',
              _warehouseStatusText(ps),
            ],
        ];
        await exportRowsToXlsx(
          fileName: 'Отчёт_склад_${_todayIso()}',
          sheetName: 'Склад',
          headers: headers,
          rows: rows,
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }
}

// ═══ Карточка: внимание (сроки годности + мало на складе) ════════════════════

/// Заметная секция «Внимание» вверху экрана: товары с истёкшим/истекающим сроком
/// годности (≤ [kExpirySoonDays] дней) и товары с остатком ниже минимума. Если
/// таких нет — не рендерится вовсе ([SizedBox.shrink]).
class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(warehouseStockProvider).valueOrNull ?? const [];
    final alerts =
        items
            .where(
              (ps) => ps.product.expired || ps.product.expiringSoon || ps.low,
            )
            .toList()
          ..sort((a, b) => _severity(a).compareTo(_severity(b)));

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  'Внимание — ${alerts.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final ps in alerts) _AlertRow(data: ps),
          ],
        ),
      ),
    );
  }

  /// Ранг срочности для сортировки: просрочен → истекает → мало.
  static int _severity(ProductStock ps) {
    if (ps.product.expired) return 0;
    if (ps.product.expiringSoon) return 1;
    return 2;
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.data});

  final ProductStock data;

  @override
  Widget build(BuildContext context) {
    final p = data.product;
    final badges = <Widget>[
      if (p.expired)
        const StatusBadge('истёк', kind: BadgeKind.danger)
      else if (p.expiringSoon)
        StatusBadge(_daysLabel(p.daysToExpiry!), kind: BadgeKind.warning),
      if (data.low) const StatusBadge('мало', kind: BadgeKind.warning),
    ];

    final info = <String>[
      if (p.expiry != null) 'срок до ${_fmtDmy(p.expiry!)}',
      if (data.low) 'остаток ${_trimNum(data.stock)} ${p.unit}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
                if (info.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    info,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(spacing: 6, runSpacing: 6, children: badges),
        ],
      ),
    );
  }
}

// ═══ Карточка: товары с остатком ═════════════════════════════════════════════

class _ProductsCard extends ConsumerWidget {
  const _ProductsCard({
    required this.canManage,
    required this.canWriteOff,
    required this.isSuperuser,
  });

  final bool canManage;
  final bool canWriteOff;
  final bool isSuperuser;

  Future<void> _addProduct(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ProductDialog(),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(warehouseStockProvider);
      ref.invalidate(warehouseMovementsProvider);
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
                      isSuperuser: isSuperuser,
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
    required this.isSuperuser,
  });

  final ProductStock data;
  final bool canManage;
  final bool canWriteOff;
  final bool isSuperuser;

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

  /// Детальный просмотр товара: все поля + текущий остаток + недавние движения.
  Future<void> _openDetail(BuildContext context, WidgetRef ref) async {
    final p = data.product;
    final recent =
        (ref.read(warehouseMovementsProvider).valueOrNull ??
                const <WarehouseMovement>[])
            .where((m) => m.productId == p.id)
            .take(12)
            .toList();

    final rows = <DetailRow>[
      const DetailRow.section('Товар'),
      DetailRow('Название', p.name, strong: true),
      DetailRow('Категория', p.category ?? ''),
      DetailRow('Единица', p.unit),
      if (p.minStock != null) DetailRow('Мин. остаток', _trimNum(p.minStock!)),
      DetailRow(
        'Текущий остаток',
        '${_trimNum(data.stock)} ${p.unit}',
        strong: true,
      ),
      if (data.low) const DetailRow('Статус', 'Мало на складе'),
      if (p.expiry != null) DetailRow('Срок годности', _fmtDmy(p.expiry!)),
      if (p.expired)
        const DetailRow('Статус срока', 'Истёк', strong: true)
      else if (p.expiringSoon)
        DetailRow(
          'Статус срока',
          'Истекает через ${_daysLabel(p.daysToExpiry!)}',
          strong: true,
        ),
      if (p.createdAt != null)
        DetailRow('Добавлен', _fmtDateTime(p.createdAt!)),
      if (p.updatedAt != null)
        DetailRow('Обновлён', _fmtDateTime(p.updatedAt!)),
      DetailRow('ID', p.id),
      const DetailRow.section('Последние движения'),
      if (recent.isEmpty)
        const DetailRow('Движения', 'нет')
      else
        for (final m in recent)
          DetailRow(
            _displayDate(m.date),
            '${m.kindLabel}  ${m.isIn ? '+' : '−'}${_trimNum(m.qty)}'
            '${m.reason != null && m.reason!.isNotEmpty ? '  ·  ${m.reason}' : ''}',
          ),
    ];

    final extra = <Widget>[];
    if (canManage || isSuperuser) {
      extra.add(
        Row(
          children: [
            if (canManage)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Изменить'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _edit(context, ref);
                  },
                ),
              ),
            if (canManage && isSuperuser) const SizedBox(width: 12),
            if (isSuperuser)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Удалить'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _delete(context, ref);
                  },
                ),
              ),
          ],
        ),
      );
    }

    await showDetailSheet(context, title: p.name, rows: rows, extra: extra);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(product: data.product),
    );
    if (ok == true && context.mounted) {
      ref.invalidate(warehouseStockProvider);
      ref.invalidate(warehouseMovementsProvider);
      _snack(context, 'Товар обновлён');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final p = data.product;
    final ok = await confirmDialog(
      context,
      title: 'Удалить товар?',
      message:
          'Товар «${p.name}» будет скрыт из каталога. '
          'История движений сохранится.',
    );
    if (!ok) return;
    try {
      await ref
          .read(warehouseRepositoryProvider)
          .archiveProduct(p.id, name: p.name);
      if (context.mounted) {
        ref.invalidate(warehouseStockProvider);
        ref.invalidate(warehouseMovementsProvider);
        _snack(context, 'Товар удалён');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = data.product;
    final subtitle = [
      if (p.category != null && p.category!.isNotEmpty) p.category!,
      'ед. ${p.unit}',
      if (p.minStock != null) 'мин. ${_trimNum(p.minStock!)}',
      if (p.expiry != null) 'до ${_fmtDmy(p.expiry!)}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        child: InkWell(
          onTap: () => _openDetail(context, ref),
          borderRadius: BorderRadius.circular(AppColors.rField),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
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
                        if (p.expired) ...[
                          const SizedBox(height: 4),
                          const StatusBadge('истёк', kind: BadgeKind.danger),
                        ] else if (p.expiringSoon) ...[
                          const SizedBox(height: 4),
                          StatusBadge(
                            _daysLabel(p.daysToExpiry!),
                            kind: BadgeKind.warning,
                          ),
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
                          onPressed: () =>
                              _move(context, ref, WarehouseMovement.kIn),
                        ),
                      if (canWriteOff)
                        TextButton.icon(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Расход'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.red,
                          ),
                          onPressed: () =>
                              _move(context, ref, WarehouseMovement.kOut),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ Карточка: журнал движений ═══════════════════════════════════════════════

class _MovementsCard extends ConsumerWidget {
  const _MovementsCard({required this.isSuperuser});

  final bool isSuperuser;

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
                    _MovementTile(
                      movement: m,
                      name: names[m.productId],
                      isSuperuser: isSuperuser,
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

class _MovementTile extends ConsumerWidget {
  const _MovementTile({
    required this.movement,
    this.name,
    required this.isSuperuser,
  });

  final WarehouseMovement movement;
  final String? name;
  final bool isSuperuser;

  /// Детальный просмотр движения: тип, количество, причина, даты, id.
  Future<void> _openDetail(BuildContext context, WidgetRef ref) async {
    final m = movement;
    final rows = <DetailRow>[
      const DetailRow.section('Движение'),
      if (name != null && name!.isNotEmpty)
        DetailRow('Товар', name!, strong: true),
      DetailRow('Тип', m.kindLabel, strong: true),
      DetailRow('Количество', '${m.isIn ? '+' : '−'}${_trimNum(m.qty)}'),
      DetailRow('Причина', m.reason ?? ''),
      DetailRow('Дата', _displayDate(m.date)),
      if (m.createdAt != null) DetailRow('Создано', _fmtDateTime(m.createdAt!)),
      DetailRow('ID', m.id),
    ];

    final extra = <Widget>[];
    if (isSuperuser) {
      extra.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Сторнировать'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _void(context, ref);
            },
          ),
        ),
      );
    }

    await showDetailSheet(
      context,
      title: '${m.kindLabel} · ${name ?? 'Товар'}',
      rows: rows,
      extra: extra,
    );
  }

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Сторнировать движение?',
      message:
          'Будет создано обратное движение '
          '(${movement.isIn ? 'расход' : 'приход'} ${_trimNum(movement.qty)}). '
          'Остаток вернётся к прежнему значению.',
      confirmLabel: 'Сторнировать',
    );
    if (!ok) return;
    try {
      await ref.read(warehouseRepositoryProvider).voidMovement(movement.id);
      if (context.mounted) {
        ref.invalidate(warehouseStockProvider);
        ref.invalidate(warehouseMovementsProvider);
        _snack(context, 'Движение сторнировано');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIn = movement.isIn;
    final sign = isIn ? '+' : '−';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        child: InkWell(
          onTap: () => _openDetail(context, ref),
          borderRadius: BorderRadius.circular(AppColors.rField),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
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
                          if (movement.reason != null &&
                              movement.reason!.isNotEmpty)
                            movement.reason!,
                        ].join('  ·  '),
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
                      '$sign${_trimNum(movement.qty)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isIn ? AppColors.green : AppColors.red,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDate(movement.date),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ Диалог: добавить / редактировать товар ══════════════════════════════════

/// Значение пункта «— без категории —» (при сохранении → null). Пустая строка
/// не может совпасть с реальной категорией (та всегда обрезается и непуста).
const String _kNoCategory = '';

/// Значение пункта-действия «+ Новая категория…» в выпадающем списке. Ведущий
/// пробел гарантирует, что оно не совпадёт с реальным (обрезанным) названием.
const String _kAddNewCategory = ' __add_new_category__';

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({this.product});

  /// null — создание нового товара; иначе — правка существующего.
  final WarehouseProduct? product;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _minStock = TextEditingController();
  final _expiry = TextEditingController();
  String _unit = kWarehouseUnits.first;

  /// Выбранная категория: [_kNoCategory] — «— без категории —» (сохраняется как
  /// null), иначе — само название. [_kAddNewCategory] в состоянии не хранится
  /// (это лишь пункт-действие в списке).
  String _category = _kNoCategory;

  /// Ключ для принудительной пересборки выпадающего списка категорий (нужно,
  /// чтобы сбросить пункт «+ Новая категория…» после инлайн-добавления/отмены).
  int _catFieldRev = 0;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _category = (p.category != null && p.category!.isNotEmpty)
          ? p.category!
          : _kNoCategory;
      _minStock.text = p.minStock != null ? _trimNum(p.minStock!) : '';
      _expiry.text = p.expiry != null ? _fmtDmy(p.expiry!) : '';
      _unit = kWarehouseUnits.contains(p.unit) ? p.unit : kWarehouseUnits.first;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    _expiry.dispose();
    super.dispose();
  }

  /// Открывает маленький диалог ввода названия новой категории, добавляет её в
  /// справочник, обновляет провайдер и выбирает новое значение в списке.
  Future<void> _addCategoryInline() async {
    final name = await _promptCategoryName();
    String? canonical;
    String? err;
    if (name != null && name.trim().isNotEmpty) {
      try {
        canonical = await ref.read(categoriesRepositoryProvider).add(name);
        ref.invalidate(productCategoriesProvider);
        await ref.read(productCategoriesProvider.future);
      } catch (e) {
        err = friendlyError(e);
      }
    }
    if (!mounted) return;
    setState(() {
      final c = canonical;
      if (c != null) _category = c;
      final e = err;
      if (e != null) _error = e;
      // Пересобрать поле, чтобы оно показывало _category, а не «+ Новая…».
      _catFieldRev++;
    });
  }

  /// Небольшой диалог ввода названия категории. Возвращает введённый текст или
  /// null (отмена/закрытие).
  Future<String?> _promptCategoryName() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новая категория'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Название категории',
              hintText: 'Расходники, Реактивы…',
              isDense: true,
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Добавить'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final first = DateTime(2000);
    final last = DateTime(now.year + 20);
    var initial = _parseDmy(_expiry.text) ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Срок годности',
    );
    if (picked != null) setState(() => _expiry.text = _fmtDmy(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Срок годности необязателен; если задан — должен парситься.
    final expiryRaw = _expiry.text.trim();
    final DateTime? expiry = expiryRaw.isEmpty ? null : _parseDmy(expiryRaw);
    if (expiryRaw.isNotEmpty && expiry == null) {
      setState(() => _error = 'Неверный срок годности (ДД.ММ.ГГГГ)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final minRaw = _minStock.text.trim();
      final minStock = minRaw.isEmpty ? null : num.tryParse(minRaw);
      final category =
          (_category == _kNoCategory || _category == _kAddNewCategory)
          ? null
          : _category;
      final repo = ref.read(warehouseRepositoryProvider);
      if (_isEdit) {
        await repo.updateProduct(
          widget.product!.id,
          name: _name.text.trim(),
          category: category,
          unit: _unit,
          minStock: minStock,
          expiry: expiry,
        );
      } else {
        await repo.addProduct(
          name: _name.text.trim(),
          category: category,
          unit: _unit,
          minStock: minStock,
          expiry: expiry,
        );
      }
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

  /// Выпадающий список категорий из [productCategoriesProvider] с пунктами
  /// «— без категории —» и «+ Новая категория…». Категория товара, которой нет
  /// в справочнике (легаси-значение), подставляется в список, чтобы она
  /// отображалась и не роняла ассерт.
  Widget _buildCategoryField() {
    final cats = ref.watch(productCategoriesProvider).valueOrNull ?? const [];
    final values = <String>[_kNoCategory, ...cats];
    // Backward-compat: показать текущую категорию, даже если её нет в справочнике.
    if (_category != _kNoCategory &&
        _category != _kAddNewCategory &&
        !values.contains(_category)) {
      values.add(_category);
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('category_$_catFieldRev'),
      initialValue: _category,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Категория (необязательно)',
        isDense: true,
      ),
      items: [
        for (final v in values)
          DropdownMenuItem<String>(
            value: v,
            child: Text(v == _kNoCategory ? '— без категории —' : v),
          ),
        const DropdownMenuItem<String>(
          value: _kAddNewCategory,
          child: Text('+ Новая категория…'),
        ),
      ],
      onChanged: _saving
          ? null
          : (v) {
              if (v == null) return;
              if (v == _kAddNewCategory) {
                _addCategoryInline();
                return;
              }
              setState(() => _category = v);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Редактировать товар' : 'Новый товар'),
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
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              _buildCategoryField(),
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
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly(6),
                      decoration: const InputDecoration(
                        labelText: 'Мин. остаток',
                        hintText: 'необязательно',
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? null
                          : validatePositiveNum(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _expiry,
                keyboardType: TextInputType.number,
                inputFormatters: const [DateInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Срок годности (необязательно)',
                  hintText: 'ДД.ММ.ГГГГ',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Выбрать в календаре',
                    icon: const Icon(Icons.calendar_today, size: 18),
                    onPressed: _pickExpiry,
                  ),
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null; // необязательно
                  return _parseDmy(s) == null ? 'Неверная дата' : null;
                },
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
              : Text(_isEdit ? 'Сохранить' : 'Добавить'),
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
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly(6),
                decoration: InputDecoration(
                  labelText: 'Количество (${p.unit})',
                  isDense: true,
                ),
                validator: validatePositiveNum,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: 'Причина (необязательно)',
                  hintText: _isIn ? 'поставка, возврат…' : 'плановый расход…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
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

/// Сегодняшняя дата в ISO `YYYY-MM-DD` (для имени файла экспорта).
String _todayIso() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Сводный статус строки склада для отчёта: «мало» / «истекает» / «истёк»
/// (через запятую) либо «—». Повторяет логику warehouse_pdf.dart, чтобы колонка
/// «Статус» в Excel совпадала с PDF один-в-один.
String _warehouseStatusText(ProductStock ps) {
  final parts = <String>[];
  if (ps.low) parts.add('мало');
  if (ps.product.expired) {
    parts.add('истёк');
  } else if (ps.product.expiringSoon) {
    parts.add('истекает');
  }
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// Компактная подпись «дней до срока»: 0 → «сегодня», иначе «N дн.».
String _daysLabel(int days) => days == 0 ? 'сегодня' : '$days дн.';

String _fmtDmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// Дата-время для детального просмотра: `ДД.ММ.ГГГГ ЧЧ:ММ`.
String _fmtDateTime(DateTime d) =>
    '${_fmtDmy(d)} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

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
