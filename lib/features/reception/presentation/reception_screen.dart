import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../../visits/data/visit_repository.dart';
import '../../visits/domain/visit.dart';
import '../../visits/presentation/visit_tile.dart';

/// Регистратура «Цадмир»: форма регистрации + живая очередь на сегодня. При
/// регистрации ищется существующая карта по телефону ([PatientsRepository.findByPhone]):
/// при совпадении предлагается переиспользовать её, иначе заводится новая. Затем
/// создаётся визит в статусе `waiting` через [VisitRepository]. Список
/// «Очередь сегодня» тянется из [todayVisitsProvider] и поддерживает те же
/// действия, что и доска очереди.
class ReceptionScreen extends ConsumerStatefulWidget {
  const ReceptionScreen({super.key});

  @override
  ConsumerState<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends ConsumerState<ReceptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _birthYear = TextEditingController();
  final _phone = TextEditingController();
  final _disease = TextEditingController();
  final _consultation = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _middleNameFocus = FocusNode();

  String? _referral;
  bool _saving = false;
  String? _error;

  /// id визита, по которому сейчас выполняется действие очереди.
  String? _busyId;

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
    _firstNameFocus.dispose();
    _middleNameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = assembleUzPhone(_phone.text);
      final patientsRepo = ref.read(patientsRepositoryProvider);

      // Дедуп по телефону: если карта уже есть — предложить переиспользовать.
      Patient? patient;
      if (phone != null) {
        final existing = await patientsRepo.findByPhone(phone);
        if (existing != null) {
          if (!mounted) return;
          final choice = await _confirmReuse(existing);
          if (choice == null) return; // отмена — прервать регистрацию
          if (choice) patient = existing;
        }
      }

      // Новая карта, если не переиспользуем существующую.
      patient ??= await patientsRepo.create(
        lastName: _lastName.text.trim(),
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        birthYear: int.parse(_birthYear.text.trim()),
        phone: phone,
        disease: _disease.text.trim(),
        referral: _referral,
        consultation: _consultation.text.trim(),
      );

      // Защита от двойной постановки: если пациент уже в живой очереди сегодня
      // (ожидает / на приёме), второй визит не создаём.
      final visitsRepo = ref.read(visitRepositoryProvider);
      final active = await visitsRepo.listToday(
        statuses: <String>{kVisitWaiting, kVisitInProgress},
      );
      Visit? alreadyQueued;
      for (final v in active) {
        if (v.patientId != null && v.patientId == patient.id) {
          alreadyQueued = v;
          break;
        }
      }
      if (alreadyQueued != null) {
        if (mounted) {
          _snack(
            'Пациент уже в очереди (№${alreadyQueued.queueNumber})',
            error: true,
          );
        }
        return;
      }

      // Визит в очередь (статус waiting) с денормализованными полями пациента.
      await visitsRepo.create(
            patientId: patient.id,
            mrn: patient.mrn,
            patientName: patient.fullName,
            birthYear: patient.birthYear,
            phone: patient.phone,
            referral: _referral,
            note: _consultation.text.trim(),
          );

      ref.invalidate(todayVisitsProvider);
      if (mounted) {
        _resetForm();
        _snack('Пациент добавлен в очередь');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Диалог дедупликации. Возвращает: `true` — переиспользовать карту,
  /// `false` — завести новую, `null` — отменить регистрацию.
  Future<bool?> _confirmReuse(Patient existing) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Пациент уже есть'),
        content: Text(
          'Пациент с этим телефоном уже есть: '
          '${existing.fullName} №${existing.mrn}. Использовать карту?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Новая карта'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Использовать'),
          ),
        ],
      ),
    );
  }

  /// Переход статуса визита из живой очереди.
  Future<void> _act(String id, String newStatus) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await ref.read(visitRepositoryProvider).setStatus(id, newStatus);
      ref.invalidate(todayVisitsProvider);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _resetForm() {
    setState(() {
      _referral = null;
      _error = null;
    });
    for (final c in [
      _lastName,
      _firstName,
      _middleName,
      _birthYear,
      _phone,
      _disease,
      _consultation,
    ]) {
      c.clear();
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final canCreate = user?.can('visits.create') ?? false;
    final queue = ref.watch(todayVisitsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final form = _formCard(canCreate);
    final list = _queueCard(queue);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Регистратура')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: form),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: list),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [form, const SizedBox(height: 16), list],
                ),
        ),
      ),
    );
  }

  Widget _formCard(bool canCreate) {
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(
              icon: Icons.person_add_alt_1,
              text: 'Регистрация пациента',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _firstNameFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Фамилия',
                isDense: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstName,
              focusNode: _firstNameFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _middleNameFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Имя',
                isDense: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _middleName,
              focusNode: _middleNameFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Отчество',
                hintText: 'необязательно',
                isDense: true,
              ),
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
                    inputFormatters: uzPhoneLocal,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      prefixText: '+996 ',
                      hintText: '700 12 34 56',
                      isDense: true,
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      if (digits.isEmpty) return null; // необязательное
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
              decoration: const InputDecoration(
                labelText: 'Вид болезни',
                hintText: 'напр. анемия, лейкоз, гепатит…',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _referral,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Направление',
                isDense: true,
              ),
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
                hintText: 'необязательно',
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
            if (!canCreate) ...[
              const SizedBox(height: 12),
              const Text(
                'Недостаточно прав для регистрации пациентов.',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: 'Зарегистрировать',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: (canCreate && !_saving) ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueCard(AsyncValue<List<Visit>> queue) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.list_alt_outlined,
                  text: 'Очередь сегодня',
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(todayVisitsProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AsyncValueWidget<List<Visit>>(
            value: queue,
            onRetry: () => ref.invalidate(todayVisitsProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Сегодня ещё никого не записали',
                      style: TextStyle(color: AppColors.sub),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final v in items)
                    VisitTile(
                      visit: v,
                      busy: _busyId == v.id,
                      onAction: (s) => _act(v.id, s),
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
