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
import '../data/analyses_repository.dart';
import '../domain/analysis_record.dart';

/// Модуль «Анализы» (лабораторные исследования — ОАК, биохимия, маркеры
/// вирусных гепатитов, ПЦР …). Запись = пациент (ФИО, год рождения, телефон) +
/// вид анализа + дата (+ опц. результат). Пациента можно выбрать из картотеки
/// (поиск как на ресепшене) либо ввести вручную.
class AnalysesScreen extends ConsumerStatefulWidget {
  const AnalysesScreen({super.key});

  @override
  ConsumerState<AnalysesScreen> createState() => _AnalysesScreenState();
}

class _AnalysesScreenState extends ConsumerState<AnalysesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _birthYear = TextEditingController();
  final _phone = TextEditingController();
  final _result = TextEditingController();
  final _date = TextEditingController();

  // Поиск пациента в картотеке (необязательный — можно ввести данные вручную).
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Patient> _found = const [];
  bool _searching = false;

  // Ссылка на карту пациента, если запись создаётся по выбранному пациенту.
  // При ручном вводе остаётся null.
  String? _patientId;
  String? _analysisType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Дата по умолчанию — сегодня (ДД.ММ.ГГГГ).
    final now = DateTime.now();
    _date.text = _fmtDmy(now);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fullName.dispose();
    _birthYear.dispose();
    _phone.dispose();
    _result.dispose();
    _date.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Дата ─────────────────────────────────────────────────────────────────

  static String _fmtDmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year}';

  /// Парсит дату из поля (маска `ДД.ММ.ГГГГ`) в [DateTime] или null.
  DateTime? _parseDate() {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(_date.text);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (year < 1900) return null;
    final d = DateTime(year, month, day);
    // Отклоняем «перетекание» (например 31.02).
    if (d.year != year || d.month != month || d.day != day) return null;
    return d;
  }

  /// Дата для бэкенда (`YYYY-MM-DD`).
  String? _iso() {
    final d = _parseDate();
    return d == null
        ? null
        : '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';
  }

  /// ISO-дата записи (`YYYY-MM-DD…`) → отображение `ДД.ММ.ГГГГ`; иначе как есть.
  static String _displayDate(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (m == null) return raw;
    return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(1900);
    final last = DateTime(now.year + 1);
    var initial = _parseDate() ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Дата анализа',
    );
    if (picked != null) setState(() => _date.text = _fmtDmy(picked));
  }

  // ── Поиск пациента ───────────────────────────────────────────────────────

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
      _phone.text = p.phone ?? '';
      _found = const [];
      _searchController.clear();
    });
  }

  void _clearPatient() {
    setState(() {
      _patientId = null;
      _fullName.clear();
      _birthYear.clear();
      _phone.clear();
    });
  }

  // ── Сохранение ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_analysisType == null) {
      setState(() => _error = 'Выберите вид анализа');
      return;
    }
    final iso = _iso();
    if (iso == null) {
      setState(() => _error = 'Укажите корректную дату (ДД.ММ.ГГГГ)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(analysesRepositoryProvider)
          .create(
            patientId: _patientId,
            fullName: _fullName.text.trim(),
            birthYear: int.parse(_birthYear.text.trim()),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            analysisType: _analysisType!,
            result: _result.text.trim().isEmpty ? null : _result.text.trim(),
            date: iso,
          );
      ref.invalidate(analysesListProvider);
      if (mounted) {
        _resetForm();
        _snack('Запись анализа сохранена');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    setState(() {
      _patientId = null;
      _analysisType = null;
      _error = null;
      _fullName.clear();
      _birthYear.clear();
      _phone.clear();
      _result.clear();
      _date.text = _fmtDmy(DateTime.now());
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  // ── Редактирование / удаление записи ──────────────────────────────────────

  /// Открывает диалог правки записи (дозаполнить результат / исправить данные).
  /// Диалог сам обновляет запись и инвалидирует список.
  Future<void> _openEdit(AnalysisRecord r) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditAnalysisDialog(r),
    );
    if (saved == true && mounted) _snack('Запись обновлена');
  }

  /// Удаление записи с подтверждением (действие необратимо).
  Future<void> _confirmDelete(AnalysisRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(
          'Анализ «${r.analysisType}» — ${r.fullName}. Действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(analysesRepositoryProvider).delete(r.id);
      ref.invalidate(analysesListProvider);
      if (mounted) _snack('Запись удалена');
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(analysesListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final form = _formCard();
    final list = _listCard(records);

    return Scaffold(
      appBar: AppBar(title: const Text('Анализы')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: form),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: list),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [form, const SizedBox(height: 16), list],
              ),
      ),
    );
  }

  Widget _formCard() {
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              icon: Icons.add_chart_outlined,
              text: 'Новая запись',
            ),
            const SizedBox(height: 14),
            // Поиск пациента в картотеке — по желанию: подставит ФИО, год и
            // телефон. Данные затем можно поправить или ввести вручную.
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
                      onPressed: _clearPatient,
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
            TextFormField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'ФИО пациента',
                isDense: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _birthYear,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly(4),
                    decoration: const InputDecoration(
                      labelText: 'Год рождения',
                      hintText: 'ГГГГ',
                      isDense: true,
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Обязательное поле';
                      final year = int.tryParse(t);
                      final now = DateTime.now().year;
                      if (year == null || t.length != 4) return 'ГГГГ';
                      if (year < 1900 || year > now) return 'Неверный год';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      hintText: 'необязательно',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _analysisType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Вид анализа',
                isDense: true,
              ),
              items: [
                for (final t in kAnalysisTypes)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              validator: (v) => v == null ? 'Выберите вид анализа' : null,
              onChanged: (v) => setState(() => _analysisType = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _date,
              keyboardType: TextInputType.number,
              inputFormatters: const [DateInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Дата анализа',
                hintText: 'ДД.ММ.ГГГГ',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Выбрать в календаре',
                  icon: const Icon(Icons.calendar_today, size: 18),
                  onPressed: _pickDate,
                ),
              ),
              validator: (v) => _parseDate() == null ? 'Неверная дата' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _result,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Результат',
                hintText: 'необязательно',
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: 'Сохранить',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _listCard(AsyncValue<List<AnalysisRecord>> records) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.bloodtype_outlined,
                  text: 'Записи анализов',
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(analysesListProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncValueWidget<List<AnalysisRecord>>(
            value: records,
            onRetry: () => ref.invalidate(analysesListProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Записей пока нет',
                      style: TextStyle(color: AppColors.sub),
                    ),
                  ),
                );
              }
              return Column(children: [for (final r in items) _recordTile(r)]);
            },
          ),
        ],
      ),
    );
  }

  Widget _recordTile(AnalysisRecord r) {
    final pending = r.result == null || r.result!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.rField),
          onTap: () => _openEdit(r),
          child: Container(
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
                  children: [
                    Expanded(
                      child: Text(
                        r.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Pill(
                      label: _displayDate(r.date),
                      color: AppColors.tealDark,
                      bg: AppColors.tealBg,
                    ),
                    const SizedBox(width: 2),
                    _tileMenu(r),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    r.analysisType,
                    'г.р. ${r.birthYear}',
                    if (r.phone != null && r.phone!.isNotEmpty) r.phone!,
                  ].join('  ·  '),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
                const SizedBox(height: 6),
                if (pending)
                  const StatusBadge(
                    'Результат ожидается',
                    kind: BadgeKind.warning,
                  )
                else
                  Text(
                    'Результат: ${r.result}',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Меню действий записи (три точки): «Изменить» / «Удалить».
  Widget _tileMenu(AnalysisRecord r) {
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.sub),
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == 'edit') _openEdit(r);
        if (v == 'delete') _confirmDelete(r);
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
            title: Text('Удалить', style: TextStyle(color: AppColors.red)),
          ),
        ),
      ],
    );
  }
}

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

// ── Хелперы дат (общие для создания и диалога правки) ─────────────────────────

/// Форматирует [DateTime] как `ДД.ММ.ГГГГ` для полей ввода.
String _fmtDmyDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// Парсит `ДД.ММ.ГГГГ` в [DateTime] (с проверкой «перетекания» вроде 31.02)
/// или `null`, если дата некорректна.
DateTime? _parseDmy(String text) {
  final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text.trim());
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (year < 1900) return null;
  final d = DateTime(year, month, day);
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}

/// `ДД.ММ.ГГГГ` → ISO `YYYY-MM-DD` (для записи в Firestore) или `null`.
String? _isoFromDmy(String text) {
  final d = _parseDmy(text);
  return d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
}

/// ISO `YYYY-MM-DD…` → `ДД.ММ.ГГГГ`; если не распознано — как есть.
String _dmyFromIso(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (m == null) return raw;
  return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// Диалог правки записи анализа — переиспользует поля формы создания (ФИО, год,
/// телефон, вид анализа, дата, результат). Главный сценарий: внести результат
/// позже или исправить опечатку. Привязка к карте пациента (`patient_id`) не
/// меняется. По сохранении обновляет запись и инвалидирует список.
class _EditAnalysisDialog extends ConsumerStatefulWidget {
  const _EditAnalysisDialog(this.record);

  final AnalysisRecord record;

  @override
  ConsumerState<_EditAnalysisDialog> createState() =>
      _EditAnalysisDialogState();
}

class _EditAnalysisDialogState extends ConsumerState<_EditAnalysisDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _birthYear;
  late final TextEditingController _phone;
  late final TextEditingController _result;
  late final TextEditingController _date;
  late String? _analysisType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _fullName = TextEditingController(text: r.fullName);
    _birthYear = TextEditingController(text: r.birthYear.toString());
    _phone = TextEditingController(text: r.phone ?? '');
    _result = TextEditingController(text: r.result ?? '');
    _date = TextEditingController(text: _dmyFromIso(r.date));
    _analysisType = r.analysisType;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _birthYear.dispose();
    _phone.dispose();
    _result.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDmy(_date.text) ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1),
      helpText: 'Дата анализа',
    );
    if (picked != null) setState(() => _date.text = _fmtDmyDate(picked));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_analysisType == null) {
      setState(() => _error = 'Выберите вид анализа');
      return;
    }
    final iso = _isoFromDmy(_date.text);
    if (iso == null) {
      setState(() => _error = 'Укажите корректную дату (ДД.ММ.ГГГГ)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(analysesRepositoryProvider)
          .update(
            widget.record.id,
            fullName: _fullName.text.trim(),
            birthYear: int.parse(_birthYear.text.trim()),
            phone: _phone.text.trim(),
            analysisType: _analysisType,
            result: _result.text.trim(),
            date: iso,
          );
      ref.invalidate(analysesListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Вид анализа записи может отсутствовать в справочнике (старые данные) —
    // добавим его в список, чтобы dropdown не упал на неизвестном значении.
    final types = <String>[
      ...kAnalysisTypes,
      if (_analysisType != null && !kAnalysisTypes.contains(_analysisType))
        _analysisType!,
    ];
    return AlertDialog(
      title: const Text('Изменить запись'),
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
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'ФИО пациента',
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Обязательное поле'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _birthYear,
                        keyboardType: TextInputType.number,
                        inputFormatters: digitsOnly(4),
                        decoration: const InputDecoration(
                          labelText: 'Год рождения',
                          hintText: 'ГГГГ',
                          isDense: true,
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Обязательное поле';
                          final year = int.tryParse(t);
                          final now = DateTime.now().year;
                          if (year == null || t.length != 4) return 'ГГГГ';
                          if (year < 1900 || year > now) return 'Неверный год';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Телефон',
                          hintText: 'необязательно',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _analysisType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Вид анализа',
                    isDense: true,
                  ),
                  items: [
                    for (final t in types)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  validator: (v) => v == null ? 'Выберите вид анализа' : null,
                  onChanged: (v) => setState(() => _analysisType = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _date,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [DateInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Дата анализа',
                    hintText: 'ДД.ММ.ГГГГ',
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Выбрать в календаре',
                      icon: const Icon(Icons.calendar_today, size: 18),
                      onPressed: _pickDate,
                    ),
                  ),
                  validator: (v) =>
                      _parseDmy(_date.text) == null ? 'Неверная дата' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _result,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Результат',
                    hintText: 'можно заполнить позже',
                    isDense: true,
                  ),
                ),
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
}
