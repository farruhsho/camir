import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/clinic_types.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/clinics_repository.dart';
import '../domain/clinic.dart';

/// Экран «Клиники» — ТОЛЬКО для платформенного администратора: реестр клиник,
/// заведение новой клиники с её первым (клиническим) супер-админом и
/// активация/деактивация клиники.
///
/// Гейт — жёсткий по `AuthUser.isPlatformAdmin`. Видимость пункта меню
/// отдельно гейтится правом `clinics.manage` (см. `app_shell.dart`), которое
/// AUTH выдаёт только платформенным админам, — так обычный клинический
/// супер-админ сюда не попадает ни через меню, ни по прямой ссылке.
class ClinicsScreen extends ConsumerWidget {
  const ClinicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null || !user.isPlatformAdmin) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Клиники')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Раздел доступен только платформенному администратору.',
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final clinics = ref.watch(clinicsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Клиники'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(clinicsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addClinic(context, ref),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Клиника'),
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<Clinic>>(
          value: clinics,
          onRetry: () => ref.invalidate(clinicsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Клиник пока нет. Нажмите «+ Клиника».',
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
                        for (final c in items)
                          _ClinicTile(
                            clinic: c,
                            onToggleActive: () =>
                                _toggleActive(context, ref, c),
                            onAddAdmin: () => _addAdmin(context, ref, c),
                            onEditModules: () => _editModules(context, ref, c),
                            onEdit: () => _editClinic(context, ref, c),
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

  /// «+ Клиника» → создаём клинику → сразу заводим её первого администратора.
  Future<void> _addClinic(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<({String id, String name})>(
      context: context,
      builder: (_) => const _NewClinicDialog(),
    );
    if (created == null || !context.mounted) return;
    ref.invalidate(clinicsProvider);
    // Провижиним первого администратора новой клиники.
    final adminCreated = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _NewClinicAdminDialog(clinicId: created.id, clinicName: created.name),
    );
    if (adminCreated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Администратор клиники создан. Передайте ему email и пароль '
            'для входа.',
          ),
        ),
      );
    } else if (context.mounted) {
      // Клиника уже создана — админа можно завести позже из её карточки.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Клиника «${created.name}» создана. Администратора можно '
            'добавить позже из её карточки.',
          ),
        ),
      );
    }
  }

  /// Завести дополнительного/первого администратора существующей клиники.
  Future<void> _addAdmin(BuildContext context, WidgetRef ref, Clinic c) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NewClinicAdminDialog(clinicId: c.id, clinicName: c.name),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Администратор клиники создан. Передайте ему email и пароль '
            'для входа.',
          ),
        ),
      );
    }
  }

  /// «Модули» — тумблеры включённых функций клиники.
  Future<void> _editModules(
    BuildContext context,
    WidgetRef ref,
    Clinic c,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ModulesDialog(clinic: c),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(clinicsProvider);
      // Если правили СВОЮ клинику — сайдбар должен перечитать модули.
      ref.invalidate(currentClinicProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Модули клиники «${c.name}» сохранены.')),
      );
    }
  }

  /// «Переименовать / сменить тип» — правка названия и профиля клиники.
  Future<void> _editClinic(
    BuildContext context,
    WidgetRef ref,
    Clinic c,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditClinicDialog(clinic: c),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(clinicsProvider);
      ref.invalidate(currentClinicProvider);
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Clinic c,
  ) async {
    final deactivate = c.active;
    if (deactivate) {
      final ok = await confirmDialog(
        context,
        title: 'Деактивировать клинику?',
        message:
            'Клиника «${c.name}» будет помечена неактивной. Работу в ней '
            'можно возобновить повторной активацией.',
        confirmLabel: 'Деактивировать',
        danger: true,
      );
      if (!ok) return;
    }
    try {
      await ref.read(clinicsRepositoryProvider).setActive(c.id, !c.active);
      if (context.mounted) ref.invalidate(clinicsProvider);
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

class _ClinicTile extends StatelessWidget {
  const _ClinicTile({
    required this.clinic,
    required this.onToggleActive,
    required this.onAddAdmin,
    required this.onEditModules,
    required this.onEdit,
  });

  final Clinic clinic;
  final VoidCallback onToggleActive;
  final VoidCallback onAddAdmin;
  final VoidCallback onEditModules;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _showClinicDetail(context, clinic),
        child: Row(
          children: [
            InitialsAvatar(_clinicInitials(clinic.name), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clinic.name.isEmpty ? '—' : clinic.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${clinic.typeInfo.label} · ${clinic.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${clinic.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.sub,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(
                    clinic.active ? 'Активна' : 'Неактивна',
                    kind: clinic.active ? BadgeKind.success : BadgeKind.neutral,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.sub),
              onSelected: (v) {
                if (v == 'admin') onAddAdmin();
                if (v == 'modules') onEditModules();
                if (v == 'edit') onEdit();
                if (v == 'active') onToggleActive();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'admin',
                  child: Text('Добавить администратора'),
                ),
                const PopupMenuItem(value: 'modules', child: Text('Модули')),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Переименовать / сменить тип'),
                ),
                PopupMenuItem(
                  value: 'active',
                  child: Text(
                    clinic.active ? 'Деактивировать' : 'Активировать',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Инициалы для аватара клиники (до двух первых букв названия).
String _clinicInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '—';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1);
  }
  return parts[0][0] + parts[1][0];
}

/// Единый детальный просмотр «список → деталь» со всеми полями клиники.
void _showClinicDetail(BuildContext context, Clinic c) {
  showDetailSheet(
    context,
    title: c.name.isEmpty ? c.id : c.name,
    rows: [
      DetailRow('Название', c.name),
      DetailRow('Тип', c.typeInfo.label),
      DetailRow('Специальность', c.subtitle),
      DetailRow('Статус', c.active ? 'Активна' : 'Неактивна', strong: true),
      DetailRow.section('Модули'),
      DetailRow('Включены', _modulesLabel(c.modules)),
      DetailRow.section('Служебное'),
      DetailRow('Создана', _fmtClinicTs(c.createdAt)),
      DetailRow('ID', c.id),
    ],
  );
}

/// Включённые модули в каноническом порядке [kAllModules], русскими подписями.
String _modulesLabel(Set<String> modules) {
  final labels = kAllModules
      .where(modules.contains)
      .map((m) => kModuleLabels[m] ?? m)
      .toList();
  return labels.isEmpty ? 'все выключены' : labels.join(', ');
}

/// Форматирует таймстамп как `ДД.ММ.ГГГГ ЧЧ:ММ` (или пустую строку — тогда
/// строка детали скрывается).
String _fmtClinicTs(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year.toString().padLeft(4, '0')} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Диалог создания клиники. Возвращает `(id, name)` созданной клиники.
class _NewClinicDialog extends ConsumerStatefulWidget {
  const _NewClinicDialog();

  @override
  ConsumerState<_NewClinicDialog> createState() => _NewClinicDialogState();
}

class _NewClinicDialogState extends ConsumerState<_NewClinicDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _type = kClinicTypes.first.key;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(clinicsRepositoryProvider)
          .create(name: _name.text, type: _type);
      if (mounted) {
        Navigator.pop(context, (id: id, name: _name.text.trim()));
      }
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
      title: const Text('Новая клиника'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Название клиники',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Тип клиники',
                  isDense: true,
                ),
                items: [
                  for (final t in kClinicTypes)
                    DropdownMenuItem(value: t.key, child: Text(t.label)),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? kClinicTypes.first.key),
              ),
              const SizedBox(height: 6),
              const Text(
                'Тип задаёт специальность в сайдбаре и набор включённых '
                'модулей (можно поменять позже через «Модули»).',
                style: TextStyle(fontSize: 12, color: AppColors.sub),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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

/// Диалог заведения (клинического) супер-админа для клиники [clinicId].
/// Возвращает `true`, если аккаунт создан.
class _NewClinicAdminDialog extends ConsumerStatefulWidget {
  const _NewClinicAdminDialog({
    required this.clinicId,
    required this.clinicName,
  });

  final String clinicId;
  final String clinicName;

  @override
  ConsumerState<_NewClinicAdminDialog> createState() =>
      _NewClinicAdminDialogState();
}

class _NewClinicAdminDialogState extends ConsumerState<_NewClinicAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
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
          .read(clinicsRepositoryProvider)
          .createClinicAdmin(
            clinicId: widget.clinicId,
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
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
      title: const Text('Администратор клиники'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Клиника: ${widget.clinicName}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
              ),
              const SizedBox(height: 12),
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

/// Диалог «Модули» — тумблер на каждый модуль из [kAllModules]. Сохраняет
/// через `setModules` и возвращает `true` (родитель перечитывает провайдеры).
class _ModulesDialog extends ConsumerStatefulWidget {
  const _ModulesDialog({required this.clinic});

  final Clinic clinic;

  @override
  ConsumerState<_ModulesDialog> createState() => _ModulesDialogState();
}

class _ModulesDialogState extends ConsumerState<_ModulesDialog> {
  late final Set<String> _enabled = {...widget.clinic.modules};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicsRepositoryProvider)
          .setModules(widget.clinic.id, _enabled);
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
      title: const Text('Модули клиники'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.clinic.name,
                style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
              ),
              const SizedBox(height: 8),
              for (final m in kAllModules)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(kModuleLabels[m] ?? m),
                  value: _enabled.contains(m),
                  onChanged: _saving
                      ? null
                      : (on) => setState(() {
                          if (on) {
                            _enabled.add(m);
                          } else {
                            _enabled.remove(m);
                          }
                        }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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

/// Диалог «Переименовать / сменить тип». При смене типа предупреждает (через
/// confirmDialog), что подзаголовок и модули будут сброшены на шаблон нового
/// типа. Возвращает `true`, если изменения сохранены.
class _EditClinicDialog extends ConsumerStatefulWidget {
  const _EditClinicDialog({required this.clinic});

  final Clinic clinic;

  @override
  ConsumerState<_EditClinicDialog> createState() => _EditClinicDialogState();
}

class _EditClinicDialogState extends ConsumerState<_EditClinicDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.clinic.name,
  );
  late String _type = widget.clinic.type;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final typeChanged = _type != widget.clinic.type;
    if (typeChanged) {
      final newType = clinicTypeFor(_type);
      final ok = await confirmDialog(
        context,
        title: 'Сменить тип клиники?',
        message:
            'Тип станет «${newType.label}». Подзаголовок и набор модулей '
            'будут СБРОШЕНЫ на шаблон нового типа (ручную настройку модулей '
            'придётся повторить).',
        confirmLabel: 'Сменить тип',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicsRepositoryProvider)
          .updateClinic(
            widget.clinic.id,
            name: _name.text,
            // Тип передаём только при реальной смене — чтобы не сбрасывать
            // ручную настройку модулей при простом переименовании.
            type: typeChanged ? _type : null,
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
      title: const Text('Клиника — название и тип'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Название клиники',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Обязательное поле'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Тип клиники',
                  isDense: true,
                ),
                items: [
                  for (final t in kClinicTypes)
                    DropdownMenuItem(value: t.key, child: Text(t.label)),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? widget.clinic.type),
              ),
              const SizedBox(height: 6),
              const Text(
                'Смена типа сбросит подзаголовок и модули на шаблон нового '
                'типа.',
                style: TextStyle(fontSize: 12, color: AppColors.sub),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
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
