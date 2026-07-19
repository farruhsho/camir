import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/fibroscan_refs_repository.dart';
import '../domain/fibro_ref.dart';

/// Экран «Референсы фиброскана» — правка референсных диапазонов эластографии
/// (стадии фиброза по LSM, kPa и степени стеатоза по CAP, dB/m). Доступ — у кого
/// есть право `catalog.manage` (Ресепшен / супер-админ). Кнопкой «Сбросить к
/// стандартным» коллекция перезаписывается значениями по умолчанию.
class FibroscanRefsScreen extends ConsumerWidget {
  const FibroscanRefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canManage = user?.can('catalog.manage') ?? false;
    if (!canManage) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Референсы фиброскана')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Недостаточно прав для правки справочников.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final refs = ref.watch(fibroRefsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Референсы фиброскана'),
        actions: [
          IconButton(
            tooltip: 'Сбросить к стандартным',
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: () => _resetDefaults(context, ref),
          ),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(fibroRefsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Диапазон'),
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<FibroRef>>(
          value: refs,
          onRetry: () => ref.invalidate(fibroRefsProvider),
          builder: (items) {
            final fibrosis = items
                .where((r) => r.kind == kFibroKindFibrosis)
                .toList();
            final steatosis = items
                .where((r) => r.kind == kFibroKindSteatosis)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section(
                          context,
                          ref,
                          title: 'Фиброз · LSM (kPa)',
                          hint: 'Стадии F0–F4 по жёсткости печени',
                          bands: fibrosis,
                        ),
                        const SizedBox(height: 18),
                        _section(
                          context,
                          ref,
                          title: 'Стеатоз · CAP (dB/m)',
                          hint:
                              'Степени S0–S3 по контролируемому '
                              'параметру затухания',
                          bands: steatosis,
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

  Widget _section(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String hint,
    required List<FibroRef> bands,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
        ),
        const SizedBox(height: 10),
        if (bands.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Диапазонов пока нет.',
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final b in bands)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BandCard(
                band: b,
                onTap: () => _edit(context, ref, b),
                onDelete: () => _delete(context, ref, b),
              ),
            ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    FibroRef? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BandDialog(existing: existing),
    );
    if (saved == true && context.mounted) ref.invalidate(fibroRefsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, FibroRef b) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить диапазон?',
      message: 'Референс «${b.label}» (${_rangeText(b)}) будет удалён.',
    );
    if (!ok) return;
    try {
      await ref
          .read(fibroscanRefsRepositoryProvider)
          .delete(
            b.id,
            summary: 'Удалён референс ${b.label} · ${_rangeText(b)}',
          );
      if (context.mounted) ref.invalidate(fibroRefsProvider);
    } catch (e) {
      if (context.mounted) _snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _resetDefaults(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Сбросить к стандартным?',
      message:
          'Текущие референсы будут заменены стандартными клиническими '
          'порогами. Действие нельзя отменить.',
      confirmLabel: 'Сбросить',
    );
    if (!ok) return;
    try {
      await ref.read(fibroscanRefsRepositoryProvider).setDefaults();
      if (context.mounted) {
        ref.invalidate(fibroRefsProvider);
        _snack(context, 'Референсы сброшены к стандартным');
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

/// Карточка одного диапазона: подпись-чип, границы и заметка + кнопка удаления.
class _BandCard extends StatelessWidget {
  const _BandCard({
    required this.band,
    required this.onTap,
    required this.onDelete,
  });

  final FibroRef band;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Pill(
            label: band.label,
            color: AppColors.tealDark,
            bg: AppColors.tealBg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _rangeText(band),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (band.note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    band.note!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.red,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Диалог добавления/правки диапазона. Возвращает `true`, если сохранено.
class _BandDialog extends ConsumerStatefulWidget {
  const _BandDialog({this.existing});
  final FibroRef? existing;

  @override
  ConsumerState<_BandDialog> createState() => _BandDialogState();
}

class _BandDialogState extends ConsumerState<_BandDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _kind;
  late final TextEditingController _label;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? kFibroKindFibrosis;
    _label = TextEditingController(text: e?.label ?? '');
    _min = TextEditingController(text: _fmt(e?.min));
    _max = TextEditingController(text: _fmt(e?.max));
    _note = TextEditingController(text: e?.note ?? '');
  }

  static String _fmt(num? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    _label.dispose();
    _min.dispose();
    _max.dispose();
    _note.dispose();
    super.dispose();
  }

  num? _parse(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final min = _parse(_min);
    final max = _parse(_max);
    if (min != null && max != null && min >= max) {
      _snack('«От» должно быть меньше «до»');
      return;
    }
    setState(() => _saving = true);
    final item = FibroRef(
      id: widget.existing?.id ?? '',
      kind: _kind,
      label: _label.text.trim(),
      min: min,
      max: max,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    try {
      await ref.read(fibroscanRefsRepositoryProvider).upsert(item);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(friendlyError(e));
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = _kind == kFibroKindSteatosis ? 'dB/m' : 'kPa';
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Новый диапазон' : 'Правка диапазона',
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Группа',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: kFibroKindFibrosis,
                    child: Text('Фиброз · LSM (kPa)'),
                  ),
                  DropdownMenuItem(
                    value: kFibroKindSteatosis,
                    child: Text('Стеатоз · CAP (dB/m)'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _kind = v ?? kFibroKindFibrosis),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Стадия / степень',
                  hintText: 'напр. F2 или S1',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _min,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'От ($unit)',
                        hintText: '— (открыт)',
                        isDense: true,
                      ),
                      validator: (v) => _validNum(v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _max,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'До ($unit)',
                        hintText: '— (открыт)',
                        isDense: true,
                      ),
                      validator: (v) => _validNum(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Диапазон: от ≤ значение < до. Пустое поле — открытый край.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Заметка (необязательно)',
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

  String? _validNum(String? v) {
    final t = (v ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null; // открытый край — допустимо
    final n = num.tryParse(t);
    if (n == null || n < 0) return 'Число';
    return null;
  }
}

/// Текст диапазона для карточки/подтверждений: «< 7 kPa», «7–9.5 kPa», «≥ 12.5 kPa».
String _rangeText(FibroRef r) {
  final lo = r.min, hi = r.max, u = r.unitLabel;
  if (lo == null && hi == null) return '—';
  if (lo == null) return '< ${_num(hi!)} $u';
  if (hi == null) return '≥ ${_num(lo)} $u';
  return '${_num(lo)}–${_num(hi)} $u';
}

String _num(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
