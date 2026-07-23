import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../auth/application/auth_controller.dart';
import '../../clinics/data/clinics_repository.dart';
import '../../clinics/domain/clinic.dart';
import '../data/staff_repository.dart';
import '../domain/staff_member.dart';
import 'staff_tile.dart';

/// Экран «Сотрудники» — только для супер-админа: список персонала, заведение
/// новых учёток (через вторичное Firebase-приложение), смена роли и
/// отключение/включение доступа.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null || !user.isSuperuser) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Сотрудники')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Раздел доступен только супер-администратору.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final staff = ref.watch(staffListProvider);
    // Платформенный админ видит сотрудников ВСЕХ клиник — подписываем каждую
    // плитку названием клиники (clinic_id -> имя из реестра, иначе сырой id).
    final isPlatform = ClinicScope.isPlatformAdmin;
    final clinicNames = <String, String>{
      if (isPlatform)
        for (final c
            in ref.watch(clinicsProvider).valueOrNull ?? const <Clinic>[])
          c.id: c.name,
    };
    String? clinicLabelOf(StaffMember s) {
      if (!isPlatform) return null;
      if (s.clinicId.isEmpty) return 'без клиники';
      return clinicNames[s.clinicId] ?? s.clinicId;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Сотрудники'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStaff(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Добавить'),
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<StaffMember>>(
          value: staff,
          onRetry: () => ref.invalidate(staffListProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Сотрудников пока нет. Нажмите «Добавить».',
                    style: TextStyle(color: AppColors.sub),
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
                          StaffTile(
                            staff: s,
                            isSelf: s.uid == user.id,
                            clinicLabel: clinicLabelOf(s),
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

  Future<void> _addStaff(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (created == true && context.mounted) {
      ref.invalidate(staffListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сотрудник создан. Передайте ему email и пароль для входа.',
          ),
        ),
      );
    }
  }
}

/// Диалог заведения сотрудника. Возвращает `true`, если аккаунт создан.
class _AddStaffDialog extends ConsumerStatefulWidget {
  const _AddStaffDialog();

  @override
  ConsumerState<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  // По умолчанию — «без роли»: доступ к данным сотрудник получает только когда
  // супер-админ осознанно выберет роль (а не проскочит диалог на «Создать»).
  String _role = '';

  // Клиника нового сотрудника. Платформенный админ выбирает её в выпадашке
  // (по умолчанию — своя); клинический супер выпадашки не видит — сотрудник
  // всегда заводится в ЕГО клинику (ClinicScope.current).
  String? _clinicId = ClinicScope.current;

  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final clinicId = ClinicScope.isPlatformAdmin
        ? (_clinicId ?? ClinicScope.current ?? '')
        : (ClinicScope.current ?? '');
    if (clinicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не выбрана клиника для нового сотрудника.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(staffRepositoryProvider)
          .createStaff(
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
            role: _role,
            clinicId: clinicId,
          );
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

  /// Выпадашка «Клиника» (только у платформенного админа): активные клиники из
  /// реестра; по умолчанию — собственная клиника админа, иначе первая активная.
  /// Строится ТОЛЬКО после загрузки списка — так `initialValue` гарантированно
  /// присутствует среди items (иначе Dropdown падает на ассерте).
  Widget _clinicField() {
    final clinicsAsync = ref.watch(clinicsProvider);
    return clinicsAsync.when(
      data: (clinics) {
        final active = clinics.where((c) => c.active).toList();
        if (active.isEmpty) {
          return const Text(
            'Нет активных клиник — сначала создайте клинику.',
            style: TextStyle(fontSize: 12.5, color: AppColors.sub),
          );
        }
        final ids = <String>{for (final c in active) c.id};
        if (_clinicId == null || !ids.contains(_clinicId)) {
          // Прямое присваивание (без setState): значение используется тут же,
          // в этом же build.
          _clinicId = ids.contains(ClinicScope.current)
              ? ClinicScope.current
              : active.first.id;
        }
        return DropdownButtonFormField<String>(
          initialValue: _clinicId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Клиника',
            isDense: true,
          ),
          items: [
            for (final c in active)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _clinicId = v),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => Text(
        friendlyError(e),
        style: const TextStyle(fontSize: 12.5, color: AppColors.red),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый сотрудник'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'ФИО',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  isDense: true,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Обязательное поле';
                  if (!t.contains('@') || !t.contains('.')) {
                    return 'Некорректный email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  isDense: true,
                  helperText: 'Минимум 6 символов',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Минимум 6 символов' : null,
              ),
              if (ClinicScope.isPlatformAdmin) ...[
                const SizedBox(height: 12),
                _clinicField(),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Роль',
                  isDense: true,
                ),
                items: [
                  for (final e in kRoleChoices.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _role = v ?? ''),
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
              : const Text('Создать'),
        ),
      ],
    );
  }
}
