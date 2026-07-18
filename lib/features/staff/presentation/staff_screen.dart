import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/staff_repository.dart';
import '../domain/staff_member.dart';

/// Значение роли в выпадашках → человеко-читаемая подпись. Пустая строка —
/// сотрудник без роли (нет доступа, пока супер-админ не назначит).
const Map<String, String> _kRoleChoices = <String, String>{
  '': 'Без роли (нет доступа)',
  roleReception: roleReception,
  roleSuperadmin: roleSuperadmin,
};

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
                          _StaffTile(
                            staff: s,
                            isSelf: s.uid == user.id,
                            onChangeRole: () =>
                                _changeRole(context, ref, s),
                            onToggleDisabled: () =>
                                _toggleDisabled(context, ref, s),
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

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    StaffMember s,
  ) async {
    var role = _kRoleChoices.containsKey(s.role) ? s.role : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Роль: ${s.fullName.isEmpty ? s.email : s.fullName}'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => DropdownButtonFormField<String>(
            initialValue: role,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Роль'),
            items: [
              for (final e in _kRoleChoices.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setLocal(() => role = v ?? ''),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(staffRepositoryProvider).updateRole(s.uid, role);
      if (context.mounted) ref.invalidate(staffListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleDisabled(
    BuildContext context,
    WidgetRef ref,
    StaffMember s,
  ) async {
    final disable = !s.disabled;
    try {
      await ref.read(staffRepositoryProvider).setDisabled(s.uid, disable);
      if (context.mounted) ref.invalidate(staffListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.staff,
    required this.isSelf,
    required this.onChangeRole,
    required this.onToggleDisabled,
  });

  final StaffMember staff;
  final bool isSelf;
  final VoidCallback onChangeRole;
  final VoidCallback onToggleDisabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            InitialsAvatar(staff.initials, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          staff.fullName.isEmpty ? '—' : staff.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 8),
                        const Pill(label: 'вы'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    staff.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StatusBadge(
                        staff.displayRole,
                        kind: staff.isSuperuser
                            ? BadgeKind.info
                            : (staff.role.isEmpty
                                  ? BadgeKind.neutral
                                  : BadgeKind.success),
                      ),
                      if (staff.disabled) ...[
                        const SizedBox(width: 6),
                        const StatusBadge('Отключён', kind: BadgeKind.danger),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Свой аккаунт нельзя понизить/отключить — защита от самоблокировки.
            if (!isSelf)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.sub),
                onSelected: (v) {
                  if (v == 'role') onChangeRole();
                  if (v == 'disabled') onToggleDisabled();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'role', child: Text('Сменить роль')),
                  PopupMenuItem(
                    value: 'disabled',
                    child: Text(staff.disabled ? 'Включить' : 'Отключить'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
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
    setState(() => _saving = true);
    try {
      await ref
          .read(staffRepositoryProvider)
          .createStaff(
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
            role: _role,
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
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Роль',
                  isDense: true,
                ),
                items: [
                  for (final e in _kRoleChoices.entries)
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
