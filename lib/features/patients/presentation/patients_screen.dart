import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../analyses/data/analyses_repository.dart';
import '../../analyses/domain/analysis_record.dart';
import '../../auth/application/auth_controller.dart';
import '../../fibroscan/data/fibroscan_repository.dart';
import '../../fibroscan/domain/fibroscan_record.dart';
import '../data/patients_repository.dart';
import '../domain/patient.dart';

/// Текущий поисковый запрос по картотеке (дебаунсится экраном).
final patientsQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Список пациентов под текущий запрос (свежие сверху).
final patientsListProvider = FutureProvider.autoDispose<List<Patient>>((
  ref,
) async {
  final q = ref.watch(patientsQueryProvider);
  final page = await ref
      .watch(patientsRepositoryProvider)
      .list(q: q, limit: 300);
  return page.items;
});

/// Ключ семейства историй пациента: id карты + ФИО (записи Фиброскана/Анализов
/// могут быть привязаны к карте по `patient_id` либо только по совпадению ФИО).
typedef _PatientKey = ({String id, String fullName});

/// Записи фиброскана этого пациента. Запрос делает репозиторий Фиброскана
/// (agent D): точный матч по `patient_id`, плюс — для исторических записей БЕЗ
/// `patient_id` — fallback по точному ФИО. Так мы не тянем и не фильтруем весь
/// журнал на клиенте и не «подхватываем» карточки однофамильцев.
final _fibroscanForPatientProvider = FutureProvider.autoDispose
    .family<List<FibroscanRecord>, _PatientKey>((ref, key) {
      return ref
          .watch(fibroscanRepositoryProvider)
          .listForPatient(key.id, fullName: key.fullName);
    });

/// Записи анализов этого пациента. Запрос делает репозиторий Анализов (agent C):
/// по `patient_id`, с fallback по точному ФИО только для записей без
/// `patient_id` (устраняет утечку записей однофамильца и обрезание по общему
/// «свежие 500»).
final _analysesForPatientProvider = FutureProvider.autoDispose
    .family<List<AnalysisRecord>, _PatientKey>((ref, key) {
      return ref
          .watch(analysesRepositoryProvider)
          .listForPatient(key.id, fullName: key.fullName);
    });

/// ISO-дата (`ГГГГ-ММ-ДД…`) → `ДД.ММ.ГГГГ`; иначе строка как есть.
String _isoToDmy(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  return m == null ? raw : '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// [DateTime] → `ДД.ММ.ГГГГ`.
String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// База пациентов «Цадмир»: поиск + список. Тап по пациенту открывает карту с
/// историей (Фиброскан · Анализы). Данные — из Firestore.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(patientsQueryProvider.notifier).state = value.trim();
    });
  }

  void _openCard(Patient p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _PatientCardPage(patient: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(patientsListProvider);
    // Не мигаем полноэкранным спиннером на каждый символ поиска: пока грузится
    // новый запрос, продолжаем показывать ранее загруженный список. Спиннер —
    // только на самую первую загрузку (когда прошлых данных ещё нет). Ошибки
    // по-прежнему поднимаются наверх и показываются.
    final stable = patients.isLoading && patients.valueOrNull != null
        ? AsyncData<List<Patient>>(patients.valueOrNull!)
        : patients;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Пациенты')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Поиск по ФИО, № карты или телефону',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.card,
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: AsyncValueWidget<List<Patient>>(
                value: stable,
                onRetry: () => ref.invalidate(patientsListProvider),
                builder: (items) {
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Пациенты не найдены',
                        style: TextStyle(color: AppColors.sub),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _patientTile(items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientTile(Patient p) {
    final line = <String>[
      '№ ${p.mrn}',
      'г.р. ${p.birthYear}',
      if (p.phone != null) p.phone!,
    ].join('  ·  ');
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _openCard(p),
      child: Row(
        children: [
          InitialsAvatar(p.initials, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                ),
              ],
            ),
          ),
          if (p.referralLabel != null) ...[
            const SizedBox(width: 8),
            Pill(
              label: p.referralLabel!,
              color: AppColors.tealDark,
              bg: AppColors.tealBg,
            ),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// Карта пациента: шапка + история (Фиброскан · Анализы). Читает Firestore-
/// репозитории соседних модулей по id карты / ФИО.
class _PatientCardPage extends ConsumerStatefulWidget {
  const _PatientCardPage({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_PatientCardPage> createState() => _PatientCardPageState();
}

class _PatientCardPageState extends ConsumerState<_PatientCardPage> {
  late Patient _patient = widget.patient;

  _PatientKey get _key => (id: _patient.id, fullName: _patient.fullName);

  Future<void> _edit() async {
    final updated = await showDialog<Patient>(
      context: context,
      builder: (_) => _PatientEditDialog(patient: _patient),
    );
    if (updated != null && mounted) {
      setState(() => _patient = updated);
      ref.invalidate(patientsListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final canEdit = user?.can('patients.update') ?? false;
    final fibroscan = ref.watch(_fibroscanForPatientProvider(_key));
    final analyses = ref.watch(_analysesForPatientProvider(_key));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Карта пациента'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Редактировать',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(),
            const SizedBox(height: 16),
            _fibroscanSection(fibroscan),
            const SizedBox(height: 16),
            _analysesSection(analyses),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final chips = <Widget>[
      _infoChip(Icons.badge_outlined, '№ карты ${_patient.mrn}'),
      _infoChip(Icons.cake_outlined, 'г.р. ${_patient.birthYear}'),
      if (_patient.phone != null)
        _infoChip(Icons.phone_outlined, _patient.phone!),
      if (_patient.referralLabel != null)
        _infoChip(Icons.alt_route_outlined, _patient.referralLabel!),
      if (_patient.registeredAt != null)
        _infoChip(
          Icons.event_available_outlined,
          'Регистрация: ${_dmy(_patient.registeredAt!)}',
        ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(_patient.initials, size: 52, fontSize: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _patient.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (_patient.disease != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _patient.disease!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
          if (_patient.consultation != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(AppColors.rField),
              ),
              child: Text(
                'Консультация: ${_patient.consultation}',
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.line2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.sub),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
          ),
        ],
      ),
    );
  }

  Widget _fibroscanSection(AsyncValue<List<FibroscanRecord>> value) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.monitor_heart_outlined,
            text: 'Фиброскан',
          ),
          const SizedBox(height: 10),
          AsyncValueWidget<List<FibroscanRecord>>(
            value: value,
            onRetry: () => ref.invalidate(_fibroscanForPatientProvider(_key)),
            builder: (items) {
              if (items.isEmpty) return const _EmptyRow();
              return Column(
                children: [
                  for (final r in items)
                    _historyRow(
                      date: _isoToDmy(r.date),
                      title: r.diagnosis,
                      badgeColor: AppColors.tealDark,
                      badgeBg: AppColors.tealBg,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _analysesSection(AsyncValue<List<AnalysisRecord>> value) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(icon: Icons.bloodtype_outlined, text: 'Анализы'),
          const SizedBox(height: 10),
          AsyncValueWidget<List<AnalysisRecord>>(
            value: value,
            onRetry: () => ref.invalidate(_analysesForPatientProvider(_key)),
            builder: (items) {
              if (items.isEmpty) return const _EmptyRow();
              return Column(
                children: [
                  for (final r in items)
                    _historyRow(
                      date: _isoToDmy(r.date),
                      title: r.analysisType,
                      subtitle: (r.result != null && r.result!.isNotEmpty)
                          ? 'Результат: ${r.result}'
                          : null,
                      badgeColor: AppColors.blue,
                      badgeBg: AppColors.blueBg,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _historyRow({
    required String date,
    required String title,
    String? subtitle,
    required Color badgeColor,
    required Color badgeBg,
  }) {
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
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Pill(label: date, color: badgeColor, bg: badgeBg),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text('Записей нет', style: TextStyle(color: AppColors.muted)),
    );
  }
}

/// Диалог редактирования карты пациента (гейтинг — `patients.update`).
/// Использует [PatientsRepository.update] и возвращает обновлённого [Patient].
class _PatientEditDialog extends ConsumerStatefulWidget {
  const _PatientEditDialog({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_PatientEditDialog> createState() => _PatientEditDialogState();
}

class _PatientEditDialogState extends ConsumerState<_PatientEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _lastName = TextEditingController(text: widget.patient.lastName);
  late final _firstName = TextEditingController(text: widget.patient.firstName);
  late final _middleName = TextEditingController(
    text: widget.patient.middleName ?? '',
  );
  late final _birthYear = TextEditingController(
    text: widget.patient.birthYear.toString(),
  );
  late final _phone = TextEditingController(
    text: extractUzPhoneLocal(widget.patient.phone),
  );
  late final _disease = TextEditingController(
    text: widget.patient.disease ?? '',
  );
  late final _consultation = TextEditingController(
    text: widget.patient.consultation ?? '',
  );
  late String? _referral = widget.patient.referral;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _lastName,
      _firstName,
      _middleName,
      _birthYear,
      _phone,
      _disease,
      _consultation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(patientsRepositoryProvider)
          .update(
            widget.patient.id,
            lastName: _lastName.text.trim(),
            firstName: _firstName.text.trim(),
            middleName: _middleName.text.trim(),
            birthYear: int.parse(_birthYear.text.trim()),
            phone: assembleUzPhone(_phone.text),
            disease: _disease.text.trim(),
            referral: _referral,
            consultation: _consultation.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактирование карты'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Фамилия'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Обязательное поле'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Обязательное поле'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _middleName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Отчество'),
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
                        inputFormatters: uzPhoneLocal,
                        decoration: const InputDecoration(
                          labelText: 'Телефон',
                          prefixText: '+996 ',
                          hintText: '700 12 34 56',
                        ),
                        validator: (v) {
                          final digits = (v ?? '').replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (digits.isEmpty) return null;
                          return digits.length == kUzPhoneLocalLength
                              ? null
                              : 'Введите 9 цифр номера';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _disease,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Вид болезни'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // Защита от краша: если у карты направление вне справочника
                  // (старые/чужие данные), не передаём его как initialValue.
                  initialValue: kReferralLabels.containsKey(_referral)
                      ? _referral
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Направление'),
                  items: [
                    for (final e in kReferralLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _referral = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _consultation,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Консультация (заметка)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.red)),
                ],
              ],
            ),
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
              : const Text('Сохранить'),
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
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
