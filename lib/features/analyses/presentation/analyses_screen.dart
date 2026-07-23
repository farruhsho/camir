import 'dart:async';

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
import '../../analysis_types/data/analysis_types_repository.dart';
import '../../analysis_types/domain/analysis_type.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../data/analyses_repository.dart';
import '../domain/analysis_record.dart';
import '../domain/analysis_result_view.dart';
import 'analyses_journal_pdf.dart';
import 'analysis_pdf.dart';

/// Модуль «Анализы» (лабораторные исследования — ОАК, биохимия, маркеры
/// вирусных гепатитов, ПЦР …). Запись = пациент (ФИО, год рождения, телефон) +
/// вид анализа (из справочника [activeAnalysisTypesProvider]) + дата + результат.
///
/// Ввод результата зависит от вида анализа: количественный — число + единица и
/// «живая» оценка нормы (classify); качественный — выбор из вариантов
/// (положительно / отрицательно / …). Для типов вне справочника остаётся
/// свободный текстовый ввод (легаси/неизвестные виды).
class AnalysesScreen extends ConsumerStatefulWidget {
  const AnalysesScreen({super.key});

  @override
  ConsumerState<AnalysesScreen> createState() => _AnalysesScreenState();
}

class _AnalysesScreenState extends ConsumerState<AnalysesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _birthYear = TextEditingController();
  final _phone = TextEditingController(); // локальная часть (+996 в префиксе)
  final _result = TextEditingController(); // число / свободный текст
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
  String? _resultOption; // выбранный вариант для качественного типа
  bool _saving = false;
  String? _error;

  // Счётчик сбросов формы: меняет ключ выпадашки вида, чтобы после сохранения
  // она визуально очистилась (DropdownButtonFormField хранит своё значение и не
  // реагирует на обнуление зеркальной переменной без пересоздания).
  int _formGen = 0;

  @override
  void initState() {
    super.initState();
    // Дата по умолчанию — сегодня (ДД.ММ.ГГГГ).
    _date.text = _fmtDmy(DateTime.now());
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
  DateTime? _parseDate() => _parseDmy(_date.text);

  /// Дата для бэкенда (`YYYY-MM-DD`).
  String? _iso() => _isoFromDmy(_date.text);

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
      _phone.text = extractUzPhoneLocal(p.phone);
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

  Future<void> _save(AnalysisType? selectedType) async {
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
            phone: assembleUzPhone(_phone.text),
            analysisType: _analysisType!,
            result: _resultFor(selectedType),
            date: iso,
          );
      _invalidateAfterMutation();
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

  /// Итоговая строка результата с учётом вида: для качественного — выбранный
  /// вариант; иначе — текст/число из поля. Пусто → null (результат необязателен,
  /// его можно внести позже).
  String? _resultFor(AnalysisType? type) {
    if (type != null && type.isQualitative) {
      final v = _resultOption?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }
    final t = _result.text.trim();
    return t.isEmpty ? null : t;
  }

  void _resetForm() {
    setState(() {
      _patientId = null;
      _analysisType = null;
      _resultOption = null;
      _error = null;
      _formGen++;
      _fullName.clear();
      _birthYear.clear();
      _phone.clear();
      _result.clear();
      _date.text = _fmtDmy(DateTime.now());
    });
  }

  /// После создания/правки/удаления обновляем список экрана. Карточка пациента
  /// (agent B) читает анализы через autoDispose-family — она перечитает данные
  /// при следующем открытии, поэтому только что внесённый результат там виден.
  void _invalidateAfterMutation() {
    ref.invalidate(analysesListProvider);
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  // ── Детальный просмотр / редактирование / удаление ────────────────────────

  /// Открывает единый детальный просмотр записи (все поля + референс + оценка).
  /// Внизу — действия «Печать/Экспорт», «Изменить», «Удалить».
  Future<void> _openDetail(AnalysisRecord r, AnalysisType? type) async {
    final flag = resultFlag(r.result, type);
    final reference = referenceRange(type);
    final hasResult = (r.result ?? '').trim().isNotEmpty;
    await showDetailSheet(
      context,
      title: r.analysisType,
      rows: [
        const DetailRow.section('Пациент'),
        DetailRow('ФИО', r.fullName, strong: true),
        DetailRow(
          'Источник',
          r.patientId != null ? 'из картотеки' : 'введён вручную',
        ),
        DetailRow('Год рождения', r.birthYear.toString()),
        if ((r.phone ?? '').trim().isNotEmpty) DetailRow('Телефон', r.phone!),
        const DetailRow.section('Анализ'),
        DetailRow('Вид анализа', r.analysisType),
        DetailRow('Дата', _dmyFromIso(r.date)),
        DetailRow(
          'Результат',
          hasResult ? resultWithUnit(r.result, type) : 'ожидается',
          strong: hasResult,
        ),
        if (reference.isNotEmpty) DetailRow('Референс (норма)', reference),
        if (flag.isNotEmpty) DetailRow('Заключение', flag, strong: true),
      ],
      extra: [
        Builder(
          builder: (sheetCtx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientButton(
                label: 'Печать',
                icon: Icons.print_outlined,
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  _print(r, type);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Изменить'),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _openEdit(r);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Удалить'),
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDelete(r);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Печать / экспорт бланка результата в PDF (кириллический шрифт, превью).
  Future<void> _print(AnalysisRecord r, AnalysisType? type) async {
    try {
      await printAnalysisRecord(r, type);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── Журнал анализов (отчёт за период) ─────────────────────────────────────

  /// Открывает небольшой выбор периода (сегодня / 7 дней / 30 дней) и строит
  /// журнал-таблицу PDF за выбранный период поверх текущего списка записей.
  Future<void> _openJournalExport(
    AsyncValue<List<AnalysisRecord>> records,
  ) async {
    final loaded = records.valueOrNull;
    if (loaded == null) {
      _snack('Записи ещё загружаются, попробуйте ещё раз');
      return;
    }
    final choice = await showModalBottomSheet<_JournalPeriod>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Журнал анализов — за период',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            for (final p in _JournalPeriod.values)
              ListTile(
                leading: Icon(p.icon, color: AppColors.accent),
                title: Text(p.title),
                onTap: () => Navigator.of(sheetCtx).pop(p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _generateJournal(choice, loaded);
  }

  /// Фильтрует записи по дате анализа за выбранный период и строит PDF-журнал.
  Future<void> _generateJournal(
    _JournalPeriod period,
    List<AnalysisRecord> all,
  ) async {
    final types =
        ref.read(analysisTypesProvider).valueOrNull ?? const <AnalysisType>[];
    final now = DateTime.now();
    final fromIso = _isoDate(now.subtract(Duration(days: period.days - 1)));
    final toIso = _isoDate(now);

    // Дата анализа хранится строкой ISO `YYYY-MM-DD` (сортируется/сравнивается
    // лексикографически = хронологически). Свежие сверху.
    final filtered =
        all
            .where(
              (r) =>
                  r.date.compareTo(fromIso) >= 0 &&
                  r.date.compareTo(toIso) <= 0,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (filtered.isEmpty) {
      _snack('За выбранный период записей нет');
      return;
    }

    final periodLabel = period == _JournalPeriod.today
        ? 'за ${_dmyFromIso(toIso)}'
        : 'за период ${_dmyFromIso(fromIso)} – ${_dmyFromIso(toIso)}';

    // Пользователь выбирает: печать (PDF → принтер) или выгрузка в Excel.
    final format = await pickExportFormat(context);
    if (format == null || !mounted) return;

    try {
      if (format == ExportFormat.printPdf) {
        await printAnalysesJournal(
          records: filtered,
          types: types,
          periodLabel: periodLabel,
        );
      } else {
        // Те же колонки, что и в PDF-журнале (analyses_journal_pdf.dart):
        // Дата · ФИО · Г.р. · Вид анализа · Результат (+ флаг отклонения).
        const headers = <String>[
          'Дата',
          'ФИО',
          'Г.р.',
          'Вид анализа',
          'Результат',
        ];
        final rows = <List<Object?>>[];
        for (final r in filtered) {
          final type = findAnalysisType(types, r.analysisType);
          final hasResult = (r.result ?? '').trim().isNotEmpty;
          final resultText = hasResult
              ? resultWithUnit(r.result, type)
              : 'ожидается';
          final flag = resultFlag(r.result, type);
          rows.add(<Object?>[
            _dmyFromIso(r.date),
            r.fullName,
            r.birthYear,
            r.analysisType,
            flag.isEmpty ? resultText : '$resultText ($flag)',
          ]);
        }
        await exportRowsToXlsx(
          fileName: 'Журнал_анализов_${_isoDate(DateTime.now())}',
          sheetName: 'Анализы',
          title: periodLabel,
          headers: headers,
          rows: rows,
        );
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  /// Открывает диалог правки записи (дозаполнить результат / исправить данные).
  Future<void> _openEdit(AnalysisRecord r) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditAnalysisDialog(r),
    );
    if (saved == true && mounted) {
      _invalidateAfterMutation();
      _snack('Запись обновлена');
    }
  }

  /// Удаление записи с подтверждением (действие необратимо).
  Future<void> _confirmDelete(AnalysisRecord r) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить запись?',
      message:
          'Анализ «${r.analysisType}» — ${r.fullName}. Действие необратимо.',
    );
    if (!ok) return;
    try {
      await ref.read(analysesRepositoryProvider).delete(r.id);
      _invalidateAfterMutation();
      if (mounted) _snack('Запись удалена');
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(analysesListProvider);
    // Активные виды — для выпадашки ввода; все виды — для сопоставления при
    // отображении (запись может ссылаться на отключённый ныне вид).
    final activeTypes =
        ref.watch(activeAnalysisTypesProvider).valueOrNull ??
        const <AnalysisType>[];
    final allTypes =
        ref.watch(analysisTypesProvider).valueOrNull ?? const <AnalysisType>[];
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final form = _formCard(activeTypes);
    final list = _listCard(records, allTypes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Анализы'),
        actions: [
          TextButton.icon(
            onPressed: () => _openJournalExport(records),
            icon: const Icon(Icons.summarize_outlined, size: 20),
            label: const Text('Отчёт / Экспорт'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
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

  Widget _formCard(List<AnalysisType> activeTypes) {
    // Имена для выпадашки: из справочника, иначе — стандартный список. Текущее
    // выбранное значение всегда включаем, чтобы dropdown не упал.
    final names = activeTypes.isNotEmpty
        ? activeTypes.map((t) => t.name).toList()
        : List<String>.from(kAnalysisTypes);
    if (_analysisType != null && !names.contains(_analysisType)) {
      names.add(_analysisType!);
    }
    final selectedType = findAnalysisType(activeTypes, _analysisType);

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
              inputFormatters: nameFormatters,
              decoration: const InputDecoration(
                labelText: 'ФИО пациента',
                isDense: true,
              ),
              validator: validateName,
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
                    validator: _validateYear,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: uzPhoneLocal,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      hintText: '700 12 34 56',
                      prefixText: '+996 ',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('type_$_formGen'),
              initialValue: _analysisType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Вид анализа',
                isDense: true,
              ),
              items: [
                for (final t in names)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              validator: (v) => v == null ? 'Выберите вид анализа' : null,
              onChanged: (v) => setState(() {
                _analysisType = v;
                // Смена вида сбрасывает несовместимый результат.
                _result.clear();
                _resultOption = null;
              }),
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
            _createResultField(selectedType),
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
              onPressed: _saving ? null : () => _save(selectedType),
            ),
          ],
        ),
      ),
    );
  }

  /// Поле результата, зависящее от вида анализа (задача 3):
  /// количественный → число + единица + «живая» оценка нормы;
  /// качественный → выбор из вариантов; иначе → свободный текст.
  Widget _createResultField(AnalysisType? type) {
    if (type != null && type.isQualitative) {
      final options = type.options.isNotEmpty
          ? type.options
          : kDefaultQualitativeOptions;
      final value = (_resultOption != null && options.contains(_resultOption))
          ? _resultOption
          : null;
      return DropdownButtonFormField<String>(
        key: ValueKey('qual_${type.id}'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Результат',
          hintText: 'можно заполнить позже',
          isDense: true,
        ),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => setState(() => _resultOption = v),
      );
    }

    if (type != null && type.isQuantitative) {
      final flag = resultFlag(_result.text, type);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _result,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Результат',
              hintText: 'число',
              isDense: true,
              suffixText: (type.unit ?? '').trim().isEmpty ? null : type.unit,
            ),
          ),
          if (referenceRange(type).isNotEmpty || flag.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (referenceRange(type).isNotEmpty)
                  Expanded(
                    child: Text(
                      'Норма: ${referenceRange(type)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.sub,
                      ),
                    ),
                  ),
                _flagBadge(flag),
              ],
            ),
          ],
        ],
      );
    }

    // Свободный текст — для типов вне справочника / пустого справочника.
    return TextFormField(
      controller: _result,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Результат',
        hintText: 'необязательно',
        isDense: true,
      ),
    );
  }

  Widget _listCard(
    AsyncValue<List<AnalysisRecord>> records,
    List<AnalysisType> allTypes,
  ) {
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
              return Column(
                children: [
                  for (final r in items)
                    _recordTile(r, findAnalysisType(allTypes, r.analysisType)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _recordTile(AnalysisRecord r, AnalysisType? type) {
    final pending = r.result == null || r.result!.trim().isEmpty;
    final flag = resultFlag(r.result, type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.rField),
          onTap: () => _openDetail(r, type),
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
                      label: _dmyFromIso(r.date),
                      color: AppColors.tealDark,
                      bg: AppColors.tealBg,
                    ),
                    const SizedBox(width: 2),
                    _tileMenu(r, type),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Результат: ${resultWithUnit(r.result, type)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (flag.isNotEmpty) _flagBadge(flag),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Меню действий записи (три точки): «Изменить» / «Печать» / «Удалить».
  Widget _tileMenu(AnalysisRecord r, AnalysisType? type) {
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.sub),
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == 'edit') _openEdit(r);
        if (v == 'print') _print(r, type);
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
          value: 'print',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.print_outlined),
            title: Text('Печать'),
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

/// Бейдж оценки нормы количественного результата.
Widget _flagBadge(String flag) {
  switch (flag) {
    case 'норма':
      return const StatusBadge('норма', kind: BadgeKind.success);
    case 'выше нормы':
      return const StatusBadge('выше нормы', kind: BadgeKind.danger);
    case 'ниже нормы':
      return const StatusBadge('ниже нормы', kind: BadgeKind.warning);
    default:
      return const SizedBox.shrink();
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

// ── Валидаторы / хелперы дат (общие для создания и диалога правки) ────────────

/// Валидатор года рождения (ГГГГ, 1900…текущий).
String? _validateYear(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Обязательное поле';
  final year = int.tryParse(t);
  final now = DateTime.now().year;
  if (year == null || t.length != 4) return 'ГГГГ';
  if (year < 1900 || year > now) return 'Неверный год';
  return null;
}

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

/// [DateTime] → ISO `YYYY-MM-DD` (для сравнения периода с полем `date`).
String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Период журнала анализов для отчёта/экспорта. [days] — сколько последних дней
/// (включительно) попадает в выборку по дате анализа.
enum _JournalPeriod {
  today(1, 'Сегодня', Icons.today_outlined),
  week(7, 'Последние 7 дней', Icons.date_range_outlined),
  month(30, 'Последние 30 дней', Icons.calendar_month_outlined);

  const _JournalPeriod(this.days, this.title, this.icon);

  final int days;
  final String title;
  final IconData icon;
}

/// Диалог правки записи анализа — те же поля, что и при создании, с тем же
/// зависящим от вида вводом результата. Главный сценарий: внести результат
/// позже или исправить опечатку. Привязка к карте пациента (`patient_id`) не
/// меняется. По сохранении обновляет запись; список инвалидирует вызывающий.
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
  String? _resultOption;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _fullName = TextEditingController(text: r.fullName);
    _birthYear = TextEditingController(text: r.birthYear.toString());
    _phone = TextEditingController(text: extractUzPhoneLocal(r.phone));
    _result = TextEditingController(text: r.result ?? '');
    _resultOption = (r.result ?? '').trim().isEmpty ? null : r.result!.trim();
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

  Future<void> _save(AnalysisType? selectedType) async {
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
            // Пустая строка очищает телефон; assembleUzPhone(...) даёт +996….
            phone: assembleUzPhone(_phone.text) ?? '',
            analysisType: _analysisType,
            result: _resultFor(selectedType),
            date: iso,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Итоговая строка результата (пустая = очистить). Для качественного вида —
  /// выбранный вариант; иначе — текст/число из поля.
  String _resultFor(AnalysisType? type) {
    if (type != null && type.isQualitative) return _resultOption?.trim() ?? '';
    return _result.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    // Для правки берём все виды (запись может ссылаться на отключённый вид).
    final allTypes =
        ref.watch(analysisTypesProvider).valueOrNull ?? const <AnalysisType>[];
    final names = allTypes.isNotEmpty
        ? allTypes.map((t) => t.name).toList()
        : List<String>.from(kAnalysisTypes);
    if (_analysisType != null && !names.contains(_analysisType)) {
      names.add(_analysisType!);
    }
    final selectedType = findAnalysisType(allTypes, _analysisType);

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
                  inputFormatters: nameFormatters,
                  decoration: const InputDecoration(
                    labelText: 'ФИО пациента',
                    isDense: true,
                  ),
                  validator: validateName,
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
                        validator: _validateYear,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: uzPhoneLocal,
                        decoration: const InputDecoration(
                          labelText: 'Телефон',
                          hintText: '700 12 34 56',
                          prefixText: '+996 ',
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
                    for (final t in names)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  validator: (v) => v == null ? 'Выберите вид анализа' : null,
                  onChanged: (v) => setState(() {
                    _analysisType = v;
                    _result.clear();
                    _resultOption = null;
                  }),
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
                _resultField(selectedType),
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
          onPressed: _saving ? null : () => _save(selectedType),
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

  /// Ввод результата по виду анализа (как в форме создания).
  Widget _resultField(AnalysisType? type) {
    if (type != null && type.isQualitative) {
      final options = <String>[
        ...(type.options.isNotEmpty
            ? type.options
            : kDefaultQualitativeOptions),
      ];
      // Текущее значение вне списка вариантов (легаси) — добавим, чтобы показать.
      if (_resultOption != null &&
          _resultOption!.isNotEmpty &&
          !options.contains(_resultOption)) {
        options.add(_resultOption!);
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('qual_${type.id}'),
        initialValue: (_resultOption != null && options.contains(_resultOption))
            ? _resultOption
            : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Результат',
          hintText: 'можно заполнить позже',
          isDense: true,
        ),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => setState(() => _resultOption = v),
      );
    }

    if (type != null && type.isQuantitative) {
      final flag = resultFlag(_result.text, type);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _result,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: money(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Результат',
              hintText: 'число',
              isDense: true,
              suffixText: (type.unit ?? '').trim().isEmpty ? null : type.unit,
            ),
          ),
          if (referenceRange(type).isNotEmpty || flag.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (referenceRange(type).isNotEmpty)
                  Expanded(
                    child: Text(
                      'Норма: ${referenceRange(type)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.sub,
                      ),
                    ),
                  ),
                _flagBadge(flag),
              ],
            ),
          ],
        ],
      );
    }

    return TextFormField(
      controller: _result,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Результат',
        hintText: 'можно заполнить позже',
        isDense: true,
      ),
    );
  }
}
