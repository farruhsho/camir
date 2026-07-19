import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/services_repository.dart';
import '../domain/service_item.dart';

/// Стандартный набор услуг клиники «Цадмир» для быстрого наполнения прайса.
/// Цены — ориентировочные (KGS «сом»), после вставки редактируются как обычно.
/// Формат записи: (название, цена, категория).
const List<(String, num, String)> _kStandardServices = <(String, num, String)>[
  ('Консультация гематолога', 800, 'Консультации'),
  ('Фиброскан печени (эластометрия)', 2500, 'Диагностика'),
  ('ОАК', 350, 'Лаборатория'),
  ('Биохимия крови', 900, 'Лаборатория'),
  ('ПЦР', 1200, 'Лаборатория'),
];

/// Экран «Прайс-лист» — управление услугами и ценами (KGS «сом»). Доступ —
/// у кого есть право `services.manage` (Ресепшен / супер-админ).
class PriceListScreen extends ConsumerWidget {
  const PriceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.can('services.manage') ?? false;
    if (!canManage) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Прайс-лист')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Недостаточно прав для управления прайс-листом.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final services = ref.watch(allServicesProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Прайс-лист'),
        actions: [
          IconButton(
            tooltip: 'Заполнить стандартными',
            icon: const Icon(Icons.playlist_add, size: 20),
            onPressed: () => _seedStandard(context, ref),
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              ref.invalidate(allServicesProvider);
              ref.invalidate(activeServicesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Услуга'),
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<ServiceItem>>(
          value: services,
          onRetry: () => ref.invalidate(allServicesProvider),
          builder: (items) {
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Услуг пока нет. Добавьте свою или заполните '
                        'стандартными услугами клиники.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.sub),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _seedStandard(context, ref),
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('Заполнить стандартными'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        for (final s in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              onTap: () => _edit(context, ref, s),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        if (s.category != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            s.category!,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppColors.sub,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    formatMoney(s.price.toString()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: s.active,
                                    onChanged: (v) =>
                                        _setActive(context, ref, s, v),
                                  ),
                                ],
                              ),
                            ),
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

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    ServiceItem s,
    bool active,
  ) async {
    try {
      await ref.read(servicesRepositoryProvider).setActive(s.id, active);
      if (context.mounted) {
        ref.invalidate(allServicesProvider);
        ref.invalidate(activeServicesProvider);
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  /// Вставляет недостающие стандартные услуги клиники (существующие по имени
  /// не трогает). Каждая услуга проходит через [ServicesRepository.add] —
  /// с аудитом. Цены — заглушки, редактируются как обычно.
  Future<void> _seedStandard(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Заполнить стандартными?',
      message:
          'Будут добавлены недостающие услуги клиники с ориентировочными '
          'ценами. Существующие услуги не изменятся — цены поправите вручную.',
      confirmLabel: 'Заполнить',
      danger: false,
    );
    if (!ok || !context.mounted) return;
    final repo = ref.read(servicesRepositoryProvider);
    try {
      // Читаем текущий список, чтобы не плодить дубли по названию.
      final existing = await repo.list();
      final names = existing.map((s) => s.name.trim().toLowerCase()).toSet();
      var added = 0;
      for (final (name, price, category) in _kStandardServices) {
        if (names.contains(name.toLowerCase())) continue;
        await repo.add(name: name, price: price, category: category);
        added++;
      }
      if (context.mounted) {
        ref.invalidate(allServicesProvider);
        ref.invalidate(activeServicesProvider);
        _snack(
          context,
          added == 0
              ? 'Все стандартные услуги уже есть в прайсе'
              : 'Добавлено услуг: $added',
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ServiceItem? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ServiceDialog(existing: existing),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(allServicesProvider);
      ref.invalidate(activeServicesProvider);
    }
  }

  void _snack(BuildContext context, String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.red : null,
      ),
    );
  }
}

/// Диалог добавления/правки услуги. Возвращает `true`, если сохранено.
class _ServiceDialog extends ConsumerStatefulWidget {
  const _ServiceDialog({this.existing});
  final ServiceItem? existing;

  @override
  ConsumerState<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends ConsumerState<_ServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: e == null ? '' : _trimZeros(e.price));
    _category = TextEditingController(text: e?.category ?? '');
  }

  static String _trimZeros(num v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(servicesRepositoryProvider);
    final price = num.parse(_price.text.trim().replaceAll(',', '.'));
    try {
      if (widget.existing == null) {
        await repo.add(
          name: _name.text,
          price: price,
          category: _category.text,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: _name.text,
          price: price,
          category: _category.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
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
      title: Text(widget.existing == null ? 'Новая услуга' : 'Правка услуги'),
      content: SizedBox(
        width: 360,
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
                  final t = (v ?? '').trim().replaceAll(',', '.');
                  final n = num.tryParse(t);
                  if (n == null || n <= 0) return 'Введите цену';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Категория (необязательно)',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
