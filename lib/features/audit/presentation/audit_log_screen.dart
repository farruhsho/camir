import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../data/audit_repository.dart';
import '../domain/audit_entry.dart';

/// Экран «Журнал изменений» — только для чтения (гейт по праву `audit.read`).
///
/// Показывает последние записи аудита (кто/что/когда изменил) списком;
/// тап по строке открывает полную карточку со всеми полями, включая детали
/// изменений. Журнал append-only — правки/удаления тут нет.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final canRead = user?.can('audit.read') ?? false;

    if (!canRead) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Журнал изменений')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Раздел доступен сотрудникам с правом на просмотр журнала '
              'изменений.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.sub),
            ),
          ),
        ),
      );
    }

    final log = ref.watch(auditLogProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Журнал изменений'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(auditLogProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: AsyncValueWidget<List<AuditEntry>>(
          value: log,
          onRetry: () => ref.invalidate(auditLogProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Пока нет записей в журнале.',
                    style: TextStyle(color: AppColors.sub),
                  ),
                ),
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(auditLogProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _AuditRow(entry: items[i]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Семантический цвет бейджа для действия.
BadgeKind _kindFor(String action) => switch (action) {
  'create' => BadgeKind.success,
  'update' || 'status_change' || 'role_change' => BadgeKind.info,
  'delete' || 'void' || 'disable' => BadgeKind.danger,
  'refund' || 'archive' => BadgeKind.warning,
  _ => BadgeKind.neutral,
};

/// Одна строка журнала: бейдж действия + модуль/сущность + описание + кто/когда.
class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.summary ?? _entityLine(entry);
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _showDetail(context, entry),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                      entry.actionLabel,
                      kind: _kindFor(entry.action),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        entry.moduleLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.sub, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${entry.whoDisplay} · ${entry.whenDisplay}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
        ],
      ),
    );
  }
}

/// Строка «сущность №id», когда у записи нет краткого описания.
String _entityLine(AuditEntry e) {
  final parts = <String>[
    if (e.entity.isNotEmpty) e.entity,
    if (e.entityId != null) '№ ${e.entityId}',
  ];
  return parts.join(' ');
}

/// Полная карточка записи журнала: все поля + детали изменений.
Future<void> _showDetail(BuildContext context, AuditEntry e) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Row(
        children: [
          StatusBadge(e.actionLabel, kind: _kindFor(e.action)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.moduleLabel,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Действие', e.actionLabel),
              _DetailRow('Модуль', e.moduleLabel),
              if (e.entity.isNotEmpty) _DetailRow('Сущность', e.entity),
              if (e.entityId != null) _DetailRow('ID записи', e.entityId!),
              if (e.summary != null) _DetailRow('Описание', e.summary!),
              _DetailRow('Кто', e.whoDisplay),
              _DetailRow('Когда', e.whenDisplay),
              if (e.hasChanges) ...[
                const SizedBox(height: 12),
                const Text(
                  'Изменения',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 6),
                _ChangesBlock(changes: e.changes),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// Строка «метка: значение» в карточке детали.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.ink, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Блок деталей изменений: перечисляет пары «поле → значение».
class _ChangesBlock extends StatelessWidget {
  const _ChangesBlock({required this.changes});

  final Map<String, dynamic> changes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.line2,
        borderRadius: BorderRadius.circular(AppColors.rField),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in changes.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: AppColors.ink, fontSize: 13),
                  children: [
                    TextSpan(
                      text: '${entry.key}: ',
                      style: const TextStyle(
                        color: AppColors.sub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: _fmtValue(entry.value)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Аккуратно приводит значение изменения к строке. Пара «до → после»
/// (`{from/before, to/after}` или список `[до, после]`) показывается как «a → b».
String _fmtValue(dynamic value) {
  if (value == null) return '—';
  if (value is Map) {
    final before = value['from'] ?? value['before'] ?? value['old'];
    final after = value['to'] ?? value['after'] ?? value['new'];
    if (before != null || after != null) {
      return '${_scalar(before)} → ${_scalar(after)}';
    }
    return value.entries.map((e) => '${e.key}: ${_scalar(e.value)}').join(', ');
  }
  if (value is List) {
    if (value.length == 2) return '${_scalar(value[0])} → ${_scalar(value[1])}';
    return value.map(_scalar).join(', ');
  }
  return _scalar(value);
}

String _scalar(dynamic v) => v == null ? '—' : v.toString();
