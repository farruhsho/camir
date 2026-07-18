import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../data/fibroscan_repository.dart';
import '../domain/fibroscan_record.dart';

/// Журнал исследований на фиброскане: список записей + форма записи
/// (ФИО · год рождения · дата · диагноз из справочника из 6). Пациента можно
/// выбрать из картотеки (поиск как на «Анализах» / ресепшене) — тогда запись
/// привязывается к карте по `patient_id`; либо ввести данные вручную (разовая
/// запись без карты). Существующие записи можно править и удалять.
class FibroscanScreen extends ConsumerStatefulWidget {
  const FibroscanScreen({super.key});

  @override
  ConsumerState<FibroscanScreen> createState() => _FibroscanScreenState();
}

class _FibroscanScreenState extends ConsumerState<FibroscanScreen> {
  final _fullName = TextEditingController();
  final _birthYear = TextEditingController();
  final _date = TextEditingController();
  String? _diagnosis;
  bool _busy = false;

  // Поиск пациента в картотеке (необязательный — можно ввести данные вручную).
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Patient> _found = const [];
  bool _searching = false;

  // Ссылка на карту пациента, если запись создаётся по выбранному пациенту.
  // При ручном вводе остаётся null.
  String? _patientId;

  // id редактируемой записи (null — режим создания новой).
  String? _editingId;

  @override
  void initState() {
    super.initState();
    // Предзаполняем дату сегодняшним числом — обычно запись вносят в день
    // исследования.
    _date.text = _formatDate(DateTime.now());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fullName.dispose();
    _birthYear.dispose();
    _date.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Дата ─────────────────────────────────────────────────────────────────

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _formatDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';

  /// Проверяет формат ДД.ММ.ГГГГ и возвращает дату (или null, если некорректно).
  static DateTime? _parseDate(String raw) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(raw.trim());
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    // Отсекаем «переехавшие» даты (например, 31.02) — DateTime их нормализует.
    if (d.day != day || d.month != month || d.year != year) return null;
    return d;
  }

  /// [DateTime] → ISO `YYYY-MM-DD` (формат хранения во всех коллекциях).
  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// ISO-дата записи (`YYYY-MM-DD…`) → отображение `ДД.ММ.ГГГГ`; иначе как есть
  /// (совместимость со старыми записями, где дата была ДД.ММ.ГГГГ).
  static String _displayDate(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (m == null) return raw;
    return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5);
    final last = DateTime(now.year + 1);
    // Клампим начальную дату в диапазон [first, last]: у старой записи дата
    // может быть раньше first, иначе showDatePicker падает по ассерту.
    var initial = _parseDate(_date.text) ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Дата исследования',
    );
    if (picked != null) setState(() => _date.text = _formatDate(picked));
  }

  // ── Поиск пациента ─────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _found = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final page = await ref
          .read(patientsRepositoryProvider)
          .list(q: q, limit: 8);
      if (mounted) setState(() => _found = page.items);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectPatient(Patient p) {
    setState(() {
      _patientId = p.id;
      _fullName.text = p.fullName;
      _birthYear.text = p.birthYear > 0 ? p.birthYear.toString() : '';
      _found = const [];
      _searchController.clear();
    });
  }

  void _clearPatient() {
    setState(() {
      _patientId = null;
      _fullName.clear();
      _birthYear.clear();
    });
  }

  // ── Редактирование / удаление ────────────────────────────────────────────────

  void _startEdit(FibroscanRecord r) {
    setState(() {
      _editingId = r.id;
      _patientId = r.patientId;
      _fullName.text = r.fullName;
      _birthYear.text = r.birthYear > 0 ? r.birthYear.toString() : '';
      _date.text = _displayDate(r.date);
      // Диагноз ставим только если он есть в справочнике (иначе выпадашка
      // упадёт на неизвестном значении из старой записи).
      _diagnosis = kFibroscanDiagnoses.contains(r.diagnosis)
          ? r.diagnosis
          : null;
      _found = const [];
      _searchController.clear();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _patientId = null;
      _fullName.clear();
      _birthYear.clear();
      _diagnosis = null;
      _date.text = _formatDate(DateTime.now());
    });
  }

  Future<void> _confirmDelete(FibroscanRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(
          '${r.fullName} · ${_displayDate(r.date)} · ${r.diagnosis}\n\n'
          'Действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fibroscanRepositoryProvider).delete(r.id);
      if (!mounted) return;
      // Если удалили запись, которую сейчас редактируем, — выходим из правки.
      if (_editingId == r.id) _cancelEdit();
      _snack('Запись удалена');
      ref.invalidate(fibroscanListProvider);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── Сохранение ───────────────────────────────────────────────────────────────

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _submit() async {
    final fullName = _fullName.text.trim();
    final year = int.tryParse(_birthYear.text.trim());
    final date = _parseDate(_date.text);
    final diagnosis = _diagnosis;
    final currentYear = DateTime.now().year;

    if (fullName.isEmpty) {
      _snack('Укажите ФИО', error: true);
      return;
    }
    if (year == null || year < 1900 || year > currentYear) {
      _snack('Некорректный год рождения (1900–$currentYear)', error: true);
      return;
    }
    if (date == null) {
      _snack('Некорректная дата (формат ДД.ММ.ГГГГ)', error: true);
      return;
    }
    if (diagnosis == null) {
      _snack('Выберите диагноз', error: true);
      return;
    }

    final iso = _iso(date);
    setState(() => _busy = true);
    try {
      final repo = ref.read(fibroscanRepositoryProvider);
      if (_editingId == null) {
        await repo.create(
          patientId: _patientId,
          fullName: fullName,
          birthYear: year,
          date: iso,
          diagnosis: diagnosis,
        );
        if (!mounted) return;
        _snack('Запись добавлена');
        // Сброс формы (дату оставляем — обычно за день вносят несколько записей).
        setState(() {
          _patientId = null;
          _fullName.clear();
          _birthYear.clear();
          _diagnosis = null;
        });
      } else {
        await repo.update(
          _editingId!,
          fullName: fullName,
          birthYear: year,
          date: iso,
          diagnosis: diagnosis,
        );
        if (!mounted) return;
        _snack('Запись обновлена');
        _cancelEdit();
      }
      ref.invalidate(fibroscanListProvider);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final list = _listSection();
    final form = _formSection();

    return Scaffold(
      appBar: AppBar(title: const Text('Фиброскан')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: form),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [form, const SizedBox(height: 16), list],
              ),
      ),
    );
  }

  // ── Форма записи ─────────────────────────────────────────────────────────────

  Widget _formSection() {
    final editing = _editingId != null;
    return _card(editing ? 'Изменить исследование' : 'Новое исследование', [
      // Поиск пациента показываем только при создании — правка существующей
      // записи не меняет привязку к карте.
      if (!editing) ...[
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Найти пациента (необязательно)',
            hintText: 'ФИО, телефон или № карты',
            isDense: true,
            prefixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
        ),
        for (final p in _found)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text(p.initials)),
            title: Text(p.fullName),
            subtitle: Text(
              [p.mrn, if (p.phone != null) p.phone!].join('  ·  '),
            ),
            onTap: () => _selectPatient(p),
          ),
        if (_patientId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Пациент из картотеки',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _clearPatient,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Ввести вручную'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
      if (editing)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(
                Icons.edit_outlined,
                size: 16,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Редактирование записи',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _cancelEdit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      TextField(
        controller: _fullName,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'ФИО',
          hintText: 'Фамилия Имя Отчество',
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _birthYear,
        keyboardType: TextInputType.number,
        inputFormatters: digitsOnly(4),
        decoration: const InputDecoration(
          labelText: 'Год рождения',
          hintText: 'например, 1980',
          counterText: '',
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _date,
        keyboardType: TextInputType.number,
        inputFormatters: const [DateInputFormatter()],
        decoration: InputDecoration(
          labelText: 'Дата исследования',
          hintText: 'ДД.ММ.ГГГГ',
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Выбрать дату',
            icon: const Icon(Icons.calendar_today_outlined, size: 20),
            onPressed: _pickDate,
          ),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('fibro-diag-${_editingId ?? 'new'}'),
        initialValue: _diagnosis,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Диагноз', isDense: true),
        hint: const Text('Выберите диагноз'),
        items: [
          for (final d in kFibroscanDiagnoses)
            DropdownMenuItem(value: d, child: Text(d)),
        ],
        onChanged: _busy ? null : (v) => setState(() => _diagnosis = v),
      ),
      const SizedBox(height: 16),
      GradientButton(
        label: editing ? 'Сохранить изменения' : 'Добавить запись',
        icon: editing ? Icons.save_outlined : Icons.add,
        loading: _busy,
        onPressed: _busy ? null : _submit,
      ),
    ]);
  }

  // ── Список исследований ──────────────────────────────────────────────────────

  Widget _listSection() {
    final async = ref.watch(fibroscanListProvider);
    return _card('Журнал исследований', [
      AsyncValueWidget<List<FibroscanRecord>>(
        value: async,
        onRetry: () => ref.invalidate(fibroscanListProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Пока нет записей. Добавьте первое исследование.',
                  style: TextStyle(color: AppColors.sub),
                ),
              ),
            );
          }
          return Column(children: [for (final r in items) _recordTile(r)]);
        },
      ),
    ]);
  }

  Widget _recordTile(FibroscanRecord r) {
    final highlight = _editingId == r.id;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: highlight
          ? BoxDecoration(
              color: AppColors.tealBg,
              borderRadius: BorderRadius.circular(AppColors.rField),
            )
          : null,
      child: Row(
        children: [
          const Icon(Icons.waves_outlined, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_displayDate(r.date)}  ·  ${r.birthYear} г.р.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(r.diagnosis, kind: BadgeKind.info),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            icon: const Icon(Icons.more_vert, size: 20, color: AppColors.sub),
            onSelected: (v) {
              if (v == 'edit') _startEdit(r);
              if (v == 'delete') _confirmDelete(r);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 20),
                  title: Text('Изменить'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, size: 20),
                  title: Text('Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
