import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/analysis_types_repository.dart';
import '../domain/analysis_type.dart';

/// Экран «Виды анализов» — управление справочником лабораторных исследований
/// (коллекция `analysis_types`). Определяет, как модуль «Анализы» вводит и
/// трактует результат: качественный (выбор из вариантов) или количественный
/// (число + единица и референсные границы). Доступ — у кого есть право
/// `catalog.manage` (Ресепшен / супер-админ).
class AnalysisTypesScreen extends ConsumerWidget {
  const AnalysisTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.can('catalog.manage') ?? false;
    if (!canManage) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Виды анализов')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Недостаточно прав для управления справочником анализов.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final types = ref.watch(analysisTypesProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Виды анализов'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Вид анализа'),
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<AnalysisType>>(
          value: types,
          onRetry: () => _refresh(ref),
          builder: (items) {
            if (items.isEmpty) {
              return _EmptyState(onSeed: () => _seed(context, ref));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        for (final t in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TypeCard(
                              type: t,
                              onTap: () => _edit(context, ref, t),
                              onActive: (v) => _setActive(context, ref, t, v),
                              onDelete: () => _confirmDelete(context, ref, t),
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

  void _refresh(WidgetRef ref) {
    ref.invalidate(analysisTypesProvider);
    ref.invalidate(activeAnalysisTypesProvider);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AnalysisType? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TypeDialog(existing: existing),
    );
    if (saved == true && context.mounted) {
      _refresh(ref);
      _snack(
        context,
        existing == null ? 'Вид анализа добавлен' : 'Изменения сохранены',
      );
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    AnalysisType t,
    bool active,
  ) async {
    try {
      await ref.read(analysisTypesRepositoryProvider).setActive(t.id, active);
      if (context.mounted) _refresh(ref);
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AnalysisType t,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить вид анализа?',
      message:
          'Вид «${t.name}» будет удалён из справочника. '
          'Уже сохранённые записи анализов не изменятся.',
    );
    if (!ok) return;
    try {
      await ref.read(analysisTypesRepositoryProvider).delete(t.id);
      if (context.mounted) {
        _refresh(ref);
        _snack(context, 'Вид анализа удалён');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _seed(BuildContext context, WidgetRef ref) async {
    try {
      final n = await ref.read(analysisTypesRepositoryProvider).seedDefaults();
      if (context.mounted) {
        _refresh(ref);
        _snack(context, 'Добавлено видов анализов: $n');
      }
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
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

/// Пустое состояние справочника: подсказка + кнопка первичного наполнения из
/// стандартного списка видов анализов.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSeed});

  final VoidCallback onSeed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.science_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Справочник пуст',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Добавьте виды анализов вручную кнопкой «Вид анализа» '
              'или заполните справочник стандартным списком.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.sub),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              child: GradientButton(
                label: 'Заполнить из стандартного списка',
                icon: Icons.playlist_add,
                onPressed: onSeed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка вида анализа в списке: название, вид результата, единица/референс или
/// варианты, переключатель активности и меню удаления.
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.onTap,
    required this.onActive,
    required this.onDelete,
  });

  final AnalysisType type;
  final VoidCallback onTap;
  final ValueChanged<bool> onActive;
  final VoidCallback onDelete;

  /// Вторая строка карточки: вид результата + детали (референс/единица/варианты).
  String get _subtitle {
    final parts = <String>[type.resultTypeLabel];
    if (type.isQuantitative) {
      if (type.unit != null) parts.add('ед.: ${type.unit}');
      if (type.refLow != null || type.refHigh != null) {
        final low = type.refLow == null ? '—' : _num(type.refLow!);
        final high = type.refHigh == null ? '—' : _num(type.refHigh!);
        parts.add('норма: $low…$high');
      }
    } else if (type.options.isNotEmpty) {
      parts.add(type.options.join(' / '));
    }
    return parts.join('  ·  ');
  }

  static String _num(num v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
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
                        type.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (!type.active) ...[
                      const SizedBox(width: 8),
                      const StatusBadge('Отключён', kind: BadgeKind.neutral),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: type.active, onChanged: onActive),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.sub),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'edit') onTap();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Изменить'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: AppColors.red),
                  title: Text(
                    'Удалить',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Диалог добавления/правки вида анализа. Возвращает `true`, если сохранено.
///
/// Поля зависят от выбранного вида результата: для качественного — редактируемый
/// список вариантов; для количественного — единица + референс (нижняя/верхняя
/// граница нормы).
class _TypeDialog extends ConsumerStatefulWidget {
  const _TypeDialog({this.existing});

  final AnalysisType? existing;

  @override
  ConsumerState<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends ConsumerState<_TypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _refLow;
  late final TextEditingController _refHigh;
  late List<TextEditingController> _options;
  late String _resultType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _unit = TextEditingController(text: e?.unit ?? '');
    _refLow = TextEditingController(
      text: e?.refLow == null ? '' : _num(e!.refLow!),
    );
    _refHigh = TextEditingController(
      text: e?.refHigh == null ? '' : _num(e!.refHigh!),
    );
    _resultType = e?.resultType ?? kResultQuantitative;
    // Для качественного типа — существующие варианты, иначе значения по умолчанию.
    final opts = (e != null && e.isQualitative && e.options.isNotEmpty)
        ? e.options
        : kDefaultQualitativeOptions;
    _options = [for (final o in opts) TextEditingController(text: o)];
  }

  static String _num(num v) {
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _refLow.dispose();
    _refHigh.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() => setState(() => _options.add(TextEditingController()));

  void _removeOption(int i) {
    if (_options.length <= 1) return;
    setState(() => _options.removeAt(i).dispose());
  }

  static num? _parseNum(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    return t.isEmpty ? null : num.tryParse(t);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _name.text.trim();
    List<String> options = const <String>[];
    String? unit;
    num? refLow;
    num? refHigh;

    if (_resultType == kResultQualitative) {
      options = _options
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (options.isEmpty) {
        setState(() => _error = 'Добавьте хотя бы один вариант ответа');
        return;
      }
    } else {
      unit = _unit.text.trim().isEmpty ? null : _unit.text.trim();
      refLow = _parseNum(_refLow.text);
      refHigh = _parseNum(_refHigh.text);
      if (refLow != null && refHigh != null && refLow > refHigh) {
        setState(() => _error = 'Нижняя граница не может быть больше верхней');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(analysisTypesRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.add(
          name: name,
          resultType: _resultType,
          options: options,
          unit: unit,
          refLow: refLow,
          refHigh: refHigh,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: name,
          resultType: _resultType,
          options: options,
          unit: unit,
          refLow: refLow,
          refHigh: refHigh,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Новый вид анализа' : 'Правка вида анализа',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                DropdownButtonFormField<String>(
                  initialValue: _resultType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Вид результата',
                    isDense: true,
                  ),
                  items: [
                    for (final entry in kResultTypeLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _resultType = v);
                  },
                ),
                const SizedBox(height: 12),
                if (_resultType == kResultQualitative)
                  _optionsEditor()
                else
                  _quantEditor(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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

  /// Редактор вариантов качественного результата (добавление/удаление строк).
  Widget _optionsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Варианты ответа',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.sub,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _options[i],
                    decoration: InputDecoration(
                      labelText: 'Вариант ${i + 1}',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Убрать',
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: AppColors.red,
                  onPressed: _options.length <= 1
                      ? null
                      : () => _removeOption(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addOption,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Добавить вариант'),
          ),
        ),
      ],
    );
  }

  /// Поля количественного результата: единица + референсные границы.
  Widget _quantEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _unit,
          decoration: const InputDecoration(
            labelText: 'Единица измерения',
            hintText: 'например Ед/л, ммоль/л (необязательно)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _refLow,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Норма от',
                  hintText: 'необязательно',
                  isDense: true,
                ),
                validator: _refValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _refHigh,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Норма до',
                  hintText: 'необязательно',
                  isDense: true,
                ),
                validator: _refValidator,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Границы нормы задаются по протоколу лаборатории. Оставьте пустыми, '
          'если референс не применяется.',
          style: TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
      ],
    );
  }

  /// Валидатор референсной границы: пусто допустимо, иначе — корректное число.
  String? _refValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return _parseNum(t) == null ? 'Число' : null;
  }
}
