import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/xlsx_export.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../fibroscan_refs/data/fibroscan_refs_repository.dart';
import '../../fibroscan_refs/domain/fibro_ref.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../data/fibroscan_repository.dart';
import '../domain/fibroscan_record.dart';
import 'fibroscan_journal_pdf.dart';
import 'fibroscan_pdf.dart';

/// Период журнального отчёта по фиброскану (app-bar «Отчёт / Экспорт»).
/// По умолчанию — [today] (сегодня).
enum _JournalPeriod {
  today('Сегодня', 0),
  week('За 7 дней', 6),
  month('За 30 дней', 29);

  const _JournalPeriod(this.label, this.daysBack);

  /// Человекочитаемая метка для меню и шапки PDF.
  final String label;

  /// На сколько дней назад от сегодня начинается период (включительно):
  /// 0 — только сегодня, 6 — окно из 7 дней, 29 — окно из 30 дней.
  final int daysBack;
}

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
  final _lsm = TextEditingController();
  final _cap = TextEditingController();
  final _iqrMed = TextEditingController();
  final _validMeasurements = TextEditingController();
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
    _lsm.dispose();
    _cap.dispose();
    _iqrMed.dispose();
    _validMeasurements.dispose();
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

  /// [DateTime] → `ДД.ММ.ГГГГ ЧЧ:ММ` (для «Создано» в детальном просмотре).
  static String _displayDateTime(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year} '
      '${_two(d.hour)}:${_two(d.minute)}';

  // ── LSM / CAP ──────────────────────────────────────────────────────────────

  /// Необязательное число из ввода (десятичный разделитель — точка или запятая).
  /// Пустой ввод → `null`; нечисловой ввод → `null` (валидатор в [_submit]
  /// отличает пустое поле от мусора по непустому тексту).
  static num? _parseNum(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  /// Число без лишнего `.0`: `8.0`→`8`, `8.2`→`8.2`.
  static String _numStr(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      _lsm.text = r.lsm != null ? _numStr(r.lsm!) : '';
      _cap.text = r.cap != null ? _numStr(r.cap!) : '';
      _iqrMed.text = r.iqrMed != null ? _numStr(r.iqrMed!) : '';
      _validMeasurements.text = r.validMeasurements != null
          ? r.validMeasurements.toString()
          : '';
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
      _lsm.clear();
      _cap.clear();
      _iqrMed.clear();
      _validMeasurements.clear();
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
      await ref
          .read(fibroscanRepositoryProvider)
          .delete(
            r.id,
            summary: '${r.fullName} · ${_displayDate(r.date)} · ${r.diagnosis}',
          );
      if (!mounted) return;
      // Если удалили запись, которую сейчас редактируем, — выходим из правки.
      if (_editingId == r.id) _cancelEdit();
      _snack('Запись удалена');
      ref.invalidate(fibroscanListProvider);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── Печать заключения ────────────────────────────────────────────────────────

  /// Строит и открывает PDF-заключение по записи (превью/печать/сохранение).
  /// [refs] — справочник для стадии фиброза/степени стеатоза и интерпретации.
  Future<void> _printReport(FibroscanRecord r, List<FibroRef> refs) async {
    try {
      await printFibroscanReport(r, refs);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  // ── Журнальный отчёт за период ───────────────────────────────────────────────

  /// Строит и открывает журнальный PDF (таблица исследований за [period]:
  /// сегодня / 7 дней / 30 дней) с превью/печатью/сохранением. Записи берутся
  /// диапазонным запросом по `date` (без составного индекса). [refs] — для
  /// стадии фиброза / степени стеатоза в колонках таблицы.
  Future<void> _exportJournal(
    _JournalPeriod period,
    List<FibroRef> refs,
  ) async {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: period.daysBack));
    try {
      final records = await ref
          .read(fibroscanRepositoryProvider)
          .listForPeriod(_iso(from), _iso(to));
      if (!mounted) return;
      if (records.isEmpty) {
        _snack(
          'За выбранный период (${period.label.toLowerCase()}) '
          'исследований нет',
        );
        return;
      }
      // Пользователь выбирает: печать (PDF → принтер) или выгрузка в Excel.
      final format = await pickExportFormat(context);
      if (format == null || !mounted) return;
      if (format == ExportFormat.printPdf) {
        await printFibroscanJournal(
          records: records,
          refs: refs,
          periodLabel: period.label,
          from: from,
          to: to,
        );
      } else {
        await _exportJournalXlsx(period, records, refs, from, to);
      }
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    }
  }

  /// Выгрузка журнала фиброскана в .xlsx. Колонки один-в-один с PDF-журналом
  /// (fibroscan_journal_pdf.dart): Дата · ФИО · Г.р. · Диагноз · LSM (кПа) ·
  /// CAP (дБ/м) · IQR/Med — с производной стадией фиброза (F..) и степенью
  /// стеатоза (S..) в ячейках LSM/CAP.
  Future<void> _exportJournalXlsx(
    _JournalPeriod period,
    List<FibroscanRecord> records,
    List<FibroRef> refs,
    DateTime from,
    DateTime to,
  ) async {
    // Ячейка LSM: «8.2 · F2» (значение + стадия) или «—», если не измерялось.
    String lsmCell(FibroscanRecord r) {
      final lsm = r.lsm;
      if (lsm == null) return '—';
      final stage = stageForLsm(lsm, refs);
      return stage.isEmpty ? _numStr(lsm) : '${_numStr(lsm)} · $stage';
    }

    // Ячейка CAP: «250 · S1» (значение + степень) или «—».
    String capCell(FibroscanRecord r) {
      final cap = r.cap;
      if (cap == null) return '—';
      final grade = gradeForCap(cap, refs);
      return grade.isEmpty ? _numStr(cap) : '${_numStr(cap)} · $grade';
    }

    const headers = <String>[
      'Дата',
      'ФИО',
      'Г.р.',
      'Диагноз',
      'LSM (кПа)',
      'CAP (дБ/м)',
      'IQR/Med',
    ];
    final rows = <List<Object?>>[
      for (final r in records)
        <Object?>[
          _displayDate(r.date),
          r.fullName,
          r.birthYear > 0 ? r.birthYear : '—',
          r.diagnosis,
          lsmCell(r),
          capCell(r),
          r.iqrMed != null ? '${_numStr(r.iqrMed!)} %' : '—',
        ],
    ];

    final periodText = from.isAtSameMomentAs(to)
        ? _formatDate(from)
        : '${_formatDate(from)} – ${_formatDate(to)}';

    await exportRowsToXlsx(
      fileName: 'Журнал_фиброскана_${_iso(DateTime.now())}',
      sheetName: 'Фиброскан',
      title: 'Период: ${period.label} · $periodText',
      headers: headers,
      rows: rows,
    );
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
    // LSM/CAP необязательны, но если поле заполнено — оно должно быть
    // положительным числом.
    final lsm = _parseNum(_lsm.text);
    if (_lsm.text.trim().isNotEmpty && (lsm == null || lsm <= 0)) {
      _snack('Некорректный LSM (положительное число, кПа)', error: true);
      return;
    }
    final cap = _parseNum(_cap.text);
    if (_cap.text.trim().isNotEmpty && (cap == null || cap <= 0)) {
      _snack('Некорректный CAP (положительное число, дБ/м)', error: true);
      return;
    }
    // IQR/Med (%) необязателен, но если задан — 0..100 (это относительная мера).
    final iqrMed = _parseNum(_iqrMed.text);
    if (_iqrMed.text.trim().isNotEmpty &&
        (iqrMed == null || iqrMed < 0 || iqrMed > 100)) {
      _snack('Некорректный IQR/Med (0–100 %)', error: true);
      return;
    }
    // Число валидных измерений необязательно; если задано — положительное целое.
    final valid = int.tryParse(_validMeasurements.text.trim());
    if (_validMeasurements.text.trim().isNotEmpty &&
        (valid == null || valid <= 0)) {
      _snack('Некорректное число измерений (целое > 0)', error: true);
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
          lsm: lsm,
          cap: cap,
          iqrMed: iqrMed,
          validMeasurements: valid,
        );
        if (!mounted) return;
        _snack('Запись добавлена');
        // Сброс формы (дату оставляем — обычно за день вносят несколько записей).
        setState(() {
          _patientId = null;
          _fullName.clear();
          _birthYear.clear();
          _lsm.clear();
          _cap.clear();
          _iqrMed.clear();
          _validMeasurements.clear();
          _diagnosis = null;
        });
      } else {
        await repo.update(
          _editingId!,
          fullName: fullName,
          birthYear: year,
          date: iso,
          diagnosis: diagnosis,
          lsm: lsm,
          cap: cap,
          iqrMed: iqrMed,
          validMeasurements: valid,
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
    // Референсы для «на лету» стадии фиброза (F..) и степени стеатоза (S..).
    // Пусто/ещё не загружено — stageForLsm/gradeForCap подстрахуются
    // стандартными порогами (kDefaultFibroRefs).
    final refs = ref.watch(fibroRefsProvider).valueOrNull ?? const <FibroRef>[];
    final list = _listSection(refs);
    final form = _formSection(refs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Фиброскан'),
        actions: [
          PopupMenuButton<_JournalPeriod>(
            tooltip: 'Отчёт / Экспорт',
            icon: const Icon(Icons.summarize_outlined),
            onSelected: (p) => _exportJournal(p, refs),
            itemBuilder: (_) => [
              for (final p in _JournalPeriod.values)
                PopupMenuItem<_JournalPeriod>(
                  value: p,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 20,
                    ),
                    title: Text('Отчёт: ${p.label.toLowerCase()}'),
                  ),
                ),
            ],
          ),
        ],
      ),
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

  Widget _formSection(List<FibroRef> refs) {
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
      // LSM (жёсткость печени) → стадия фиброза F.. показывается прямо в поле.
      _measureField(
        controller: _lsm,
        label: 'LSM (кПа)',
        hint: 'жёсткость печени',
        unit: 'кПа',
        derive: (v) => stageForLsm(v, refs),
      ),
      const SizedBox(height: 12),
      // CAP (затухание УЗ) → степень стеатоза S.. показывается прямо в поле.
      _measureField(
        controller: _cap,
        label: 'CAP (дБ/м)',
        hint: 'стеатоз печени',
        unit: 'дБ/м',
        derive: (v) => gradeForCap(v, refs),
      ),
      const SizedBox(height: 12),
      // IQR/Med (%) — надёжность измерения LSM. Подсказка «надёжно» (≤ 30 %,
      // зелёным) / «низкая надёжность» (> 30 %, янтарным) прямо в поле.
      _iqrMedField(),
      const SizedBox(height: 12),
      TextField(
        controller: _validMeasurements,
        keyboardType: TextInputType.number,
        inputFormatters: digitsOnly(2),
        decoration: const InputDecoration(
          labelText: 'Валидных измерений',
          hintText: 'обычно 10',
          counterText: '',
          isDense: true,
          suffix: Text(
            'изм.',
            style: TextStyle(fontSize: 12.5, color: AppColors.sub),
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

  /// Числовое поле измерения (LSM/CAP) с единицей и производной стадией/степенью
  /// прямо в поле: по мере ввода показывает, напр., «кПа · F2» / «дБ/м · S1».
  /// [derive] превращает введённое число в подпись (`stageForLsm`/`gradeForCap`).
  Widget _measureField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String unit,
    required String Function(num) derive,
  }) {
    final value = _parseNum(controller.text);
    final tag = (value != null && value > 0) ? derive(value) : '';
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: money(),
      // Перерисовываем поле, чтобы стадия/степень пересчитывались на лету.
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        suffix: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: unit,
                style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
              ),
              if (tag.isNotEmpty)
                TextSpan(
                  text: '  ·  $tag',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Поле IQR/Med (%) с подсказкой надёжности измерения LSM прямо в поле:
  /// «надёжно» (≤ 30 %, зелёным) / «низкая надёжность» (> 30 %, янтарным).
  Widget _iqrMedField() {
    final value = _parseNum(_iqrMed.text);
    final show = value != null && value >= 0 && value <= 100;
    final reliable = show && isFibroIqrReliable(value);
    final label = show ? fibroReliabilityLabel(value) : '';
    return TextField(
      controller: _iqrMed,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: money(),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'IQR/Med (%)',
        hintText: 'надёжность LSM',
        isDense: true,
        suffix: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: '%',
                style: TextStyle(fontSize: 12.5, color: AppColors.sub),
              ),
              if (label.isNotEmpty)
                TextSpan(
                  text: '  ·  $label',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: reliable ? AppColors.green : AppColors.amber,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Список исследований ──────────────────────────────────────────────────────

  Widget _listSection(List<FibroRef> refs) {
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
          return Column(
            children: [for (final r in items) _recordTile(r, refs)],
          );
        },
      ),
    ]);
  }

  Widget _recordTile(FibroscanRecord r, List<FibroRef> refs) {
    final highlight = _editingId == r.id;
    // Компактная строка измерений с производной стадией/степенью (если заданы).
    final measures = <String>[
      if (r.lsm != null)
        'LSM ${_measureText(r.lsm!, 'кПа', stageForLsm(r.lsm!, refs))}',
      if (r.cap != null)
        'CAP ${_measureText(r.cap!, 'дБ/м', gradeForCap(r.cap!, refs))}',
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: highlight
          ? BoxDecoration(
              color: AppColors.tealBg,
              borderRadius: BorderRadius.circular(AppColors.rField),
            )
          : null,
      child: InkWell(
        onTap: () => _showDetail(r, refs),
        borderRadius: BorderRadius.circular(AppColors.rField),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              const Icon(
                Icons.waves_outlined,
                size: 20,
                color: AppColors.accent,
              ),
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
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.sub,
                      ),
                    ),
                    if (measures.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        measures.join('     '),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(r.diagnosis, kind: BadgeKind.info),
              PopupMenuButton<String>(
                tooltip: 'Действия',
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: AppColors.sub,
                ),
                onSelected: (v) {
                  if (v == 'print') _printReport(r, refs);
                  if (v == 'edit') _startEdit(r);
                  if (v == 'delete') _confirmDelete(r);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'print',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.print_outlined, size: 20),
                      title: Text('Печать заключения'),
                    ),
                  ),
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
        ),
      ),
    );
  }

  /// «8.2 кПа · F2» — число + единица + производная подпись (пустая подпись
  /// опускается).
  static String _measureText(num v, String unit, String tag) =>
      tag.isEmpty ? '${_numStr(v)} $unit' : '${_numStr(v)} $unit · $tag';

  /// Детальный просмотр записи (единый bottom-sheet «список → деталь»): все поля
  /// записи, LSM/CAP с производной стадией фиброза и степенью стеатоза.
  Future<void> _showDetail(FibroscanRecord r, List<FibroRef> refs) {
    final hasMeasures =
        r.lsm != null ||
        r.cap != null ||
        r.iqrMed != null ||
        r.validMeasurements != null;
    final linked = r.patientId != null && r.patientId!.isNotEmpty;
    return showDetailSheet(
      context,
      title: 'Исследование фиброскана',
      rows: [
        DetailRow('ФИО', r.fullName, strong: true),
        DetailRow('Год рождения', r.birthYear > 0 ? '${r.birthYear} г.р.' : ''),
        DetailRow('Дата исследования', _displayDate(r.date)),
        DetailRow('Диагноз', r.diagnosis),
        if (hasMeasures) ...[
          const DetailRow.section('Измерения'),
          if (r.lsm != null)
            DetailRow(
              'LSM (фиброз)',
              _measureText(r.lsm!, 'кПа', stageForLsm(r.lsm!, refs)),
            ),
          if (r.cap != null)
            DetailRow(
              'CAP (стеатоз)',
              _measureText(r.cap!, 'дБ/м', gradeForCap(r.cap!, refs)),
            ),
          if (r.iqrMed != null)
            DetailRow(
              'IQR/Med',
              '${_numStr(r.iqrMed!)} % · ${fibroReliabilityLabel(r.iqrMed!)}',
            ),
          if (r.validMeasurements != null)
            DetailRow('Валидных измерений', '${r.validMeasurements}'),
        ],
        const DetailRow.section('Учёт'),
        DetailRow(
          'Пациент',
          linked ? 'Из картотеки' : 'Разовая запись (без карты)',
        ),
        DetailRow(
          'Создано',
          r.createdAt != null ? _displayDateTime(r.createdAt!) : '',
        ),
      ],
      extra: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _printReport(r, refs);
          },
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Печать заключения'),
        ),
      ],
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
