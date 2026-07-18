import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/async_value_widget.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../data/visit_repository.dart';
import '../domain/visit.dart';
import 'visit_tile.dart';

/// Доска очереди `/queue`: ожидающие + идущие приёмы за сегодня, с действиями
/// перехода статуса. Данные — [todayVisitsProvider] (фильтр статусов на
/// клиенте). Пустое/загрузка/ошибка — через [AsyncValueWidget] + [friendlyError].
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// id визита, по которому сейчас выполняется действие (блокирует его кнопки).
  String? _busyId;

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
    final visits = ref.watch(todayVisitsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Очередь'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(todayVisitsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AsyncValueWidget<List<Visit>>(
                value: visits,
                onRetry: () => ref.invalidate(todayVisitsProvider),
                builder: (all) {
                  final active = [
                    for (final v in all)
                      if (v.status == kVisitWaiting ||
                          v.status == kVisitInProgress)
                        v,
                  ];
                  final waiting = active
                      .where((v) => v.status == kVisitWaiting)
                      .length;
                  final inProgress = active
                      .where((v) => v.status == kVisitInProgress)
                      .length;
                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: _SectionTitle(
                                icon: Icons.list_alt_outlined,
                                text: 'Очередь на сегодня',
                              ),
                            ),
                            StatusBadge(
                              'Ожидают: $waiting',
                              kind: BadgeKind.warning,
                            ),
                            const SizedBox(width: 8),
                            StatusBadge(
                              'На приёме: $inProgress',
                              kind: BadgeKind.info,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (active.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'Очередь пуста',
                                style: TextStyle(color: AppColors.sub),
                              ),
                            ),
                          )
                        else
                          for (final v in active)
                            VisitTile(
                              visit: v,
                              busy: _busyId == v.id,
                              onAction: (s) => _act(v.id, s),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
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
        Flexible(
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
