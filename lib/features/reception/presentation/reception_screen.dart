import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../../core/widgets/patient_search.dart';
import '../../auth/application/auth_controller.dart';
import '../../patients/data/patients_repository.dart';
import '../../patients/domain/patient.dart';
import '../../patients/presentation/birth_date_field.dart';
import '../../payments/data/payments_repository.dart';
import '../../payments/data/services_repository.dart';
import '../../payments/domain/payment.dart';
import '../../payments/domain/service_item.dart';
import '../../visits/data/visit_repository.dart';
import '../../visits/domain/visit.dart';
import '../../visits/presentation/visit_tile.dart';

/// Sentinel-значение выпадашки услуг: «своя услуга» (ввод названия + цены).
const String _kCustomService = '__custom__';

/// Регистратура «Цадмир» — единый гид приёма: **регистрация → оплата →
/// направление**.
///
/// Форма заводит пациента (дедуп по телефону через
/// [PatientsRepository.findByPhone]) и создаёт приём в статусе
/// `awaiting_payment` с выбранной услугой (из прайса [activeServicesProvider]
/// или своей). Список «Сегодня» ([todayVisitsProvider]) показывает приёмы со
/// статусом и действиями по стадии: «Оплатить» (инкассация прямо здесь +
/// [VisitRepository.markPaid]), затем «Направить: …» (переход на профильный
/// экран специалиста) и «Завершить» ([VisitRepository.markDone]).
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
  final _phone = TextEditingController();
  final _note = TextEditingController();

  /// Поля «своей услуги» (когда в выпадашке выбран [_kCustomService]).
  final _customServiceName = TextEditingController();
  final _customServicePrice = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _middleNameFocus = FocusNode();

  /// Полная дата рождения из [BirthDateField] (обязательна при регистрации).
  DateTime? _birthDate;

  /// Текст ошибки под полем даты рождения (показывается при пустом значении).
  String? _birthDateError;

  String? _referral;

  /// id выбранной услуги прайса, либо [_kCustomService] для своей услуги.
  String? _serviceId;

  /// Счётчик сбросов формы: меняет ключ выпадашек (направление, услуга), чтобы
  /// после регистрации они визуально очистились (DropdownButtonFormField хранит
  /// своё значение и не реагирует на обнуление зеркальной переменной без
  /// пересоздания).
  int _formGen = 0;

  bool _saving = false;
  String? _error;

  /// id приёма, по которому сейчас выполняется действие (оплата/завершение).
  String? _busyId;

  /// Выбранный из картотеки пациент — режим «приём для уже зарегистрированного».
  /// `null` — обычный режим регистрации нового пациента (идентичность вводится
  /// вручную). Когда задан, поля ФИО/дата/телефон не монтируются, а идентичность
  /// берётся напрямую из выбранной карты.
  Patient? _existingPatient;

  @override
  void dispose() {
    for (final c in [
      _lastName,
      _firstName,
      _middleName,
      _phone,
      _note,
      _customServiceName,
      _customServicePrice,
    ]) {
      c.dispose();
    }
    _firstNameFocus.dispose();
    _middleNameFocus.dispose();
    super.dispose();
  }

  /// Определяет выбранную услугу (имя + цену) из состояния формы.
  /// Возвращает `(null, null)`, если услуга не выбрана/не валидна.
  (String?, num?) _resolveService(List<ServiceItem> catalog) {
    final id = _serviceId;
    if (id == null) return (null, null);
    if (id == _kCustomService) {
      final name = _customServiceName.text.trim();
      final price = num.tryParse(
        _customServicePrice.text.trim().replaceAll(',', '.'),
      );
      return (
        name.isEmpty ? null : name,
        (price != null && price > 0) ? price : null,
      );
    }
    for (final s in catalog) {
      if (s.id == id) return (s.name, s.price);
    }
    return (null, null);
  }

  Future<void> _save() async {
    final existing = _existingPatient;
    final formOk = _formKey.currentState!.validate();
    // Дата рождения — обязательна ТОЛЬКО при регистрации нового пациента; для
    // существующей карты идентичность (и дата) уже есть. Диапазон пикера
    // гарантирует реализм (не в будущем, возраст ~120), поэтому в новой ветке
    // проверяем лишь «выбрана ли она вообще».
    if (existing == null && _birthDate == null) {
      setState(() => _birthDateError = 'Укажите дату рождения');
    }
    if (!formOk || (existing == null && _birthDate == null)) return;

    final catalog =
        ref.read(activeServicesProvider).valueOrNull ?? const <ServiceItem>[];
    final (serviceName, servicePrice) = _resolveService(catalog);
    if (serviceName == null || servicePrice == null) {
      setState(() => _error = 'Не удалось определить услугу');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Patient patient;
      if (existing != null) {
        // Приём для уже зарегистрированного пациента: создание карты и дедуп по
        // телефону пропускаем — идентичность берём из выбранной картотеки.
        patient = existing;
      } else {
        final phone = assembleUzPhone(_phone.text);
        final patientsRepo = ref.read(patientsRepositoryProvider);

        // Дедуп по телефону: если карта уже есть — предложить переиспользовать.
        Patient? found;
        if (phone != null) {
          final dup = await patientsRepo.findByPhone(phone);
          if (dup != null) {
            if (!mounted) return;
            final choice = await _confirmReuse(dup);
            if (choice == null) return; // отмена — прервать регистрацию
            if (choice) found = dup;
          }
        }

        // Новая карта, если не переиспользуем существующую.
        patient =
            found ??
            await patientsRepo.create(
              lastName: _lastName.text.trim(),
              firstName: _firstName.text.trim(),
              middleName: _middleName.text.trim(),
              birthYear: _birthDate!.year,
              birthDate: _birthDate,
              phone: phone,
              referral: _referral,
              consultation: _note.text.trim(),
            );
      }

      // Приём в статусе awaiting_payment с денормализованными полями пациента
      // и выбранной услугой.
      await ref
          .read(visitRepositoryProvider)
          .create(
            patientId: patient.id,
            mrn: patient.mrn,
            patientName: patient.fullName,
            birthYear: patient.birthYear,
            phone: patient.phone,
            referral: _referral,
            serviceName: serviceName,
            servicePrice: servicePrice,
            note: _note.text.trim(),
          );

      ref.invalidate(todayVisitsProvider);
      if (mounted) {
        final wasExisting = existing != null;
        _resetForm();
        _snack(
          wasExisting
              ? 'Приём создан. Ожидает оплаты.'
              : 'Пациент зарегистрирован. Приём ожидает оплаты.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Открывает поиск по картотеке и переводит форму в режим «приём для уже
  /// зарегистрированного пациента» (идентичность берётся из выбранной карты).
  Future<void> _pickExisting() async {
    final p = await pickPatient(context);
    if (p != null && mounted) {
      setState(() {
        _existingPatient = p;
        _error = null;
        _birthDateError = null;
      });
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

  /// Инкассация приёма: спрашивает способ оплаты, проводит платёж в кассу и
  /// переводит приём в `paid`. Обновляет список приёмов и дневную кассу.
  Future<void> _pay(Visit v) async {
    if (_busyId != null) return;
    final price = v.servicePrice ?? 0;
    if (price <= 0) {
      _snack('У приёма не указана цена услуги', error: true);
      return;
    }
    final method = await _askPaymentMethod(v);
    if (method == null || !mounted) return;

    setState(() => _busyId = v.id);
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .create(
            patientId: v.patientId,
            patientName: v.patientName,
            mrn: v.mrn,
            visitId: v.id,
            items: [
              PaymentItem(service: v.serviceName ?? 'Приём', price: price),
            ],
            method: method,
          );
      await ref.read(visitRepositoryProvider).markPaid(v.id);
      ref.invalidate(todayVisitsProvider);
      ref.invalidate(todayPaymentsProvider);
      if (mounted) _snack('Оплата проведена');
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Небольшой диалог выбора способа оплаты + подтверждения. Возвращает выбранный
  /// метод ([kPayMethods]) или `null` при отмене.
  Future<String?> _askPaymentMethod(Visit v) {
    var method = kPayCash;
    final sum = formatMoney((v.servicePrice ?? 0).toString());
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Оплата приёма'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.patientName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${v.serviceName ?? 'Приём'} · $sum',
                style: const TextStyle(color: AppColors.sub),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: method,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Способ оплаты',
                  isDense: true,
                ),
                items: [
                  for (final m in kPayMethods)
                    DropdownMenuItem(
                      value: m,
                      child: Text(kPayMethodLabels[m]!),
                    ),
                ],
                onChanged: (x) => setLocal(() => method = x ?? kPayCash),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, method),
              child: Text('Оплатить · $sum'),
            ),
          ],
        ),
      ),
    );
  }

  /// Завершает приём (`paid` → `done`).
  Future<void> _markDone(String id) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await ref.read(visitRepositoryProvider).markDone(id);
      ref.invalidate(todayVisitsProvider);
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Профильный экран специалиста по направлению приёма (`null` — нет экрана,
  /// напр. консультация).
  static String? _routeForReferral(String? referral) {
    switch (referral) {
      case kReferralFibroscan:
        return '/fibroscan';
      case kReferralAnalyses:
        return '/analyses';
      default:
        return null;
    }
  }

  void _resetForm() {
    setState(() {
      _referral = null;
      _serviceId = null;
      _error = null;
      _birthDate = null;
      _birthDateError = null;
      _existingPatient = null;
      _formGen++;
    });
    for (final c in [
      _lastName,
      _firstName,
      _middleName,
      _phone,
      _note,
      _customServiceName,
      _customServicePrice,
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
    final canPay = user?.can('payments.create') ?? false;
    final queue = ref.watch(todayVisitsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final form = _formCard(canCreate);
    final list = _queueCard(queue, canCreate: canCreate, canPay: canPay);

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
    final existing = _existingPatient;
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SectionTitle(
                    icon: existing == null
                        ? Icons.person_add_alt_1
                        : Icons.assignment_ind_outlined,
                    text: existing == null
                        ? 'Регистрация приёма'
                        : 'Приём: существующий пациент',
                  ),
                ),
                if (existing == null)
                  TextButton.icon(
                    onPressed: canCreate ? _pickExisting : null,
                    icon: const Icon(Icons.person_search, size: 18),
                    label: const Text('Существующий пациент'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Идентичность: для существующего пациента — read-only баннер карты
            // (без ввода ФИО/даты/телефона); для нового — обычные поля ввода.
            if (existing != null)
              _patientBanner(existing)
            else ...[
              TextFormField(
                controller: _lastName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: nameFormatters,
                onFieldSubmitted: (_) => _firstNameFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Фамилия',
                  isDense: true,
                ),
                validator: validateName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _firstName,
                focusNode: _firstNameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: nameFormatters,
                onFieldSubmitted: (_) => _middleNameFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  isDense: true,
                ),
                validator: validateName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _middleName,
                focusNode: _middleNameFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: nameFormatters,
                decoration: const InputDecoration(
                  labelText: 'Отчество',
                  hintText: 'необязательно',
                  isDense: true,
                ),
                validator: _optionalName,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BirthDateField(
                      value: _birthDate,
                      isDense: true,
                      errorText: _birthDateError,
                      onChanged: (v) => setState(() {
                        _birthDate = v;
                        _birthDateError = null;
                      }),
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
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('referral_$_formGen'),
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
              validator: (v) => v == null ? 'Выберите направление' : null,
            ),
            const SizedBox(height: 12),
            _serviceSelector(),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Заметка (необязательно)',
                hintText: 'напр. жалобы, комментарий',
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
              label: existing == null
                  ? 'Зарегистрировать'
                  : 'Зарегистрировать приём',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: (canCreate && !_saving) ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Read-only баннер выбранной карты в режиме «существующий пациент»:
  /// «{fullName} · №{mrn} · {birthDisplay}{ · phone}» с кнопкой [×], которая
  /// возвращает форму в режим регистрации нового пациента.
  Widget _patientBanner(Patient p) {
    final sub = <String>[
      '№${p.mrn}',
      if (p.birthDisplay.isNotEmpty) p.birthDisplay,
      if (p.phone != null && p.phone!.isNotEmpty) p.phone!,
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        borderRadius: BorderRadius.circular(AppColors.rField),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        children: [
          InitialsAvatar(p.initials, size: 38),
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
                  sub,
                  style: const TextStyle(color: AppColors.sub, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Убрать пациента',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _existingPatient = null),
          ),
        ],
      ),
    );
  }

  /// Выпадашка услуги (прайс + «своя услуга»). Услуга, за которую платит
  /// пациент. При выборе своей услуги показывает поля названия и цены.
  Widget _serviceSelector() {
    final services = ref.watch(activeServicesProvider);
    return AsyncValueWidget<List<ServiceItem>>(
      value: services,
      onRetry: () => ref.invalidate(activeServicesProvider),
      builder: (catalog) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('service_$_formGen'),
              initialValue: _serviceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Услуга (оплата)',
                isDense: true,
              ),
              items: [
                for (final s in catalog)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.name} · ${formatMoney(s.price.toString())}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: _kCustomService,
                  child: Text('+ Своя услуга'),
                ),
              ],
              onChanged: (v) => setState(() => _serviceId = v),
              validator: (v) => v == null ? 'Выберите услугу' : null,
            ),
            if (_serviceId == _kCustomService) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customServiceName,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название услуги',
                  isDense: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Укажите название' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customServicePrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: money(),
                decoration: const InputDecoration(
                  labelText: 'Цена, сом',
                  isDense: true,
                ),
                validator: validatePositiveNum,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _queueCard(
    AsyncValue<List<Visit>> queue, {
    required bool canCreate,
    required bool canPay,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.list_alt_outlined,
                  text: 'Приёмы сегодня',
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
                      onPay: (v.isAwaitingPayment && canPay)
                          ? () => _pay(v)
                          : null,
                      onRoute: _routeCallback(v),
                      onDone: (v.isPaid && canCreate)
                          ? () => _markDone(v.id)
                          : null,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Колбэк «Направить» для оплаченного приёма (или `null`, если нет профильного
  /// экрана по направлению).
  VoidCallback? _routeCallback(Visit v) {
    if (!v.isPaid) return null;
    final route = _routeForReferral(v.referral);
    if (route == null) return null;
    return () => context.go(route);
  }
}

/// Валидатор необязательного ФИО-поля (отчество): пусто — допустимо, цифры —
/// нет. Ввод и так фильтруется [nameFormatters], это защита от вставки.
String? _optionalName(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  return RegExp(r'[0-9]').hasMatch(t) ? 'Без цифр' : null;
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
