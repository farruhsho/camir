import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../data/staff_repository.dart';
import '../domain/staff_member.dart';

/// Значение роли в выпадашках → человеко-читаемая подпись. Пустая строка —
/// сотрудник без роли (нет доступа, пока супер-админ не назначит). Общий для
/// экранов «Сотрудники» и «Сотрудники клиники» и диалога заведения.
const Map<String, String> kRoleChoices = <String, String>{
  '': 'Без роли (нет доступа)',
  roleReception: roleReception,
  roleSuperadmin: roleSuperadmin,
};

/// Полный список НАЗНАЧАЕМЫХ (операционных) permission-кодов — берём набор роли
/// «Ресепшен» как мастер-список (см. `kRolePermissions`). Именно эти коды владелец
/// включает/выключает в редакторе «Права».
List<String> get kAssignablePermissions =>
    kRolePermissions[roleReception] ?? const <String>[];

/// Код права → русская подпись для редактора «Права». Покрывает ВСЕ коды из
/// [kAssignablePermissions]; неизвестный код в UI падает обратно на сам код.
const Map<String, String> kPermissionLabels = <String, String>{
  'patients.read': 'Пациенты: просмотр',
  'patients.create': 'Пациенты: создание',
  'patients.update': 'Пациенты: изменение',
  'visits.create': 'Визиты: создание',
  'visits.read': 'Визиты: просмотр',
  'visits.update': 'Визиты: изменение',
  'inventory.read': 'Склад: просмотр',
  'inventory.manage': 'Склад: управление',
  'inventory.write_off': 'Склад: списание',
  'analyses.read': 'Анализы: просмотр',
  'analyses.write': 'Анализы: ввод результатов',
  'fibroscan.read': 'Фиброскан: просмотр',
  'fibroscan.write': 'Фиброскан: ввод результатов',
  'payments.read': 'Касса: просмотр',
  'payments.create': 'Касса: приём оплаты',
  'payments.refund': 'Касса: возвраты',
  'services.read': 'Услуги: просмотр',
  'services.manage': 'Услуги: управление',
  'audit.read': 'Журнал: просмотр',
  'catalog.manage': 'Справочники: правка',
};

/// Плитка сотрудника со всеми действиями владельца («Сменить роль», «Права»,
/// «Отключить/Включить»). Переиспользуется на экране «Сотрудники» (все клиники)
/// и на экране «Сотрудники клиники» (одна клиника). Сама подключена к Riverpod,
/// поэтому обоим экранам достаточно передать [staff]/[isSelf]/[clinicLabel].
///
/// Защита от самоблокировки: у СВОЕГО аккаунта ([isSelf]) меню действий не
/// показывается — владелец не может понизить/отключить/урезать себя.
class StaffTile extends ConsumerWidget {
  const StaffTile({
    super.key,
    required this.staff,
    required this.isSelf,
    this.clinicLabel,
  });

  final StaffMember staff;
  final bool isSelf;

  /// Название клиники сотрудника — показывается там, где список смешанный (экран
  /// «Сотрудники» у платформенного владельца). На экране одной клиники — `null`.
  final String? clinicLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => showStaffDetail(
          context,
          staff,
          isSelf: isSelf,
          clinicLabel: clinicLabel,
        ),
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        staff.displayRole,
                        kind: staff.isSuperuser
                            ? BadgeKind.info
                            : (staff.role.isEmpty
                                  ? BadgeKind.neutral
                                  : BadgeKind.success),
                      ),
                      if (staff.disabled)
                        const StatusBadge('Отключён', kind: BadgeKind.danger),
                      if (clinicLabel != null && clinicLabel!.isNotEmpty)
                        Pill(label: clinicLabel!),
                    ],
                  ),
                ],
              ),
            ),
            // Свой аккаунт нельзя понизить/отключить/урезать — защита от
            // самоблокировки: меню действий скрыто.
            if (!isSelf)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.sub),
                onSelected: (v) {
                  switch (v) {
                    case 'role':
                      changeStaffRole(context, ref, staff);
                    case 'permissions':
                      editStaffPermissions(context, ref, staff);
                    case 'disabled':
                      toggleStaffDisabled(context, ref, staff);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'role',
                    child: Text('Сменить роль'),
                  ),
                  const PopupMenuItem(
                    value: 'permissions',
                    child: Text('Права'),
                  ),
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

/// «Сменить роль» — роль пересчитывает права по шаблону (см. `updateRole`).
Future<void> changeStaffRole(
  BuildContext context,
  WidgetRef ref,
  StaffMember s,
) async {
  var role = kRoleChoices.containsKey(s.role) ? s.role : '';
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
            for (final e in kRoleChoices.entries)
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

/// «Права» — тонкая настройка гранулярных прав поверх роли. Смена роли позже
/// перезапишет их шаблоном роли (сообщаем это в диалоге).
Future<void> editStaffPermissions(
  BuildContext context,
  WidgetRef ref,
  StaffMember s,
) async {
  final saved = await showDialog<List<String>>(
    context: context,
    builder: (_) => _PermissionEditorDialog(staff: s),
  );
  if (saved == null) return; // отмена
  try {
    await ref.read(staffRepositoryProvider).updatePermissions(s.uid, saved);
    if (context.mounted) {
      ref.invalidate(staffListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Права сотрудника обновлены.')),
      );
    }
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

/// «Отключить/Включить» доступ сотруднику (флаг `disabled`).
Future<void> toggleStaffDisabled(
  BuildContext context,
  WidgetRef ref,
  StaffMember s,
) async {
  final disable = !s.disabled;
  final who = s.fullName.isEmpty ? s.email : s.fullName;
  final ok = await confirmDialog(
    context,
    title: disable ? 'Отключить доступ?' : 'Включить доступ?',
    message: disable
        ? 'Сотрудник «$who» больше не сможет войти в приложение.'
        : 'Сотрудник «$who» снова сможет входить в приложение.',
    confirmLabel: disable ? 'Отключить' : 'Включить',
    danger: disable,
  );
  if (!ok) return;
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

/// Единый детальный просмотр «список → деталь» со ВСЕМИ полями сотрудника.
/// Открывается тапом по плитке; трёхточечное меню действий сохранено.
void showStaffDetail(
  BuildContext context,
  StaffMember s, {
  required bool isSelf,
  String? clinicLabel,
}) {
  showDetailSheet(
    context,
    title: s.fullName.isEmpty ? s.email : s.fullName,
    rows: [
      DetailRow('ФИО', s.fullName),
      DetailRow('Email', s.email),
      DetailRow('Роль', s.displayRole, strong: true),
      // Пустое значение скрывается — строка видна только в смешанном списке.
      DetailRow('Клиника', clinicLabel ?? ''),
      DetailRow('Супер-админ', s.isSuperuser ? 'Да' : 'Нет'),
      DetailRow('Доступ', s.disabled ? 'Отключён' : 'Активен'),
      DetailRow('Права', _permissionsSummary(s)),
      if (isSelf) DetailRow('Это вы', 'Да'),
      DetailRow.section('Служебное'),
      DetailRow('Создан', _fmtStaffTs(s.createdAt)),
      DetailRow('UID', s.uid),
    ],
  );
}

/// Сводка прав для детального просмотра: у супера — полный доступ; иначе — число
/// и русские подписи включённых прав (или «нет прав»).
String _permissionsSummary(StaffMember s) {
  if (s.isSuperuser) return 'Полный доступ (супер-админ)';
  final active = kAssignablePermissions.where(s.permissions.contains).toList();
  if (active.isEmpty) return 'Нет прав';
  final labels = active.map((c) => kPermissionLabels[c] ?? c).join(', ');
  return '${active.length}: $labels';
}

/// Форматирует таймстамп как `ДД.ММ.ГГГГ ЧЧ:ММ` (или пустую строку — тогда
/// строка детали скрывается).
String _fmtStaffTs(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year.toString().padLeft(4, '0')} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Редактор гранулярных прав: чек-бокс на каждый назначаемый код
/// ([kAssignablePermissions]) с русской подписью. Предзаполняется из
/// `staff.permissions`. Возвращает выбранный список в каноническом порядке
/// мастер-списка, либо `null` при отмене.
class _PermissionEditorDialog extends StatefulWidget {
  const _PermissionEditorDialog({required this.staff});

  final StaffMember staff;

  @override
  State<_PermissionEditorDialog> createState() =>
      _PermissionEditorDialogState();
}

class _PermissionEditorDialogState extends State<_PermissionEditorDialog> {
  // Предвыбор: только коды из мастер-списка (устаревшие/чужие коды игнорируем).
  late final Set<String> _selected = {
    ...widget.staff.permissions.where(kAssignablePermissions.contains),
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.staff;
    final who = s.fullName.isEmpty ? s.email : s.fullName;
    return AlertDialog(
      title: Text('Права: $who'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.isSuperuser)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Супер-админ имеет полный доступ независимо от этих прав.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.amber),
                  ),
                ),
              const Text(
                'Смена роли позже перезапишет эти права шаблоном роли.',
                style: TextStyle(fontSize: 12, color: AppColors.sub),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => _selected.addAll(kAssignablePermissions),
                    ),
                    child: const Text('Выбрать всё'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Снять всё'),
                  ),
                ],
              ),
              for (final code in kAssignablePermissions)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(kPermissionLabels[code] ?? code),
                  value: _selected.contains(code),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _selected.add(code);
                    } else {
                      _selected.remove(code);
                    }
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            // Канонический порядок мастер-списка (стабильный вид в Firestore).
            kAssignablePermissions.where(_selected.contains).toList(),
          ),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
