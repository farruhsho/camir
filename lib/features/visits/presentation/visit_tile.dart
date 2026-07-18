import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../domain/visit.dart';

/// Визуальный стиль кнопки действия над визитом.
enum _ActionStyle { primary, neutral, danger }

/// Одно действие (кнопка) — подпись, иконка, целевой статус, стиль.
class _VisitAction {
  const _VisitAction(this.label, this.icon, this.status, this.style);
  final String label;
  final IconData icon;
  final String status;
  final _ActionStyle style;
}

/// Набор действий очереди для текущего статуса. Строго соответствует
/// [kVisitAllowedTransitions]; `completed` — терминальный (действий нет).
List<_VisitAction> _actionsFor(String status) {
  switch (status) {
    case kVisitWaiting:
      return const [
        _VisitAction(
          'Позвать',
          Icons.campaign_outlined,
          kVisitInProgress,
          _ActionStyle.primary,
        ),
        _VisitAction(
          'Отмена',
          Icons.close,
          kVisitCancelled,
          _ActionStyle.danger,
        ),
      ];
    case kVisitInProgress:
      return const [
        _VisitAction(
          'Завершить',
          Icons.check_circle_outline,
          kVisitCompleted,
          _ActionStyle.primary,
        ),
        _VisitAction(
          'Вернуть в очередь',
          Icons.undo,
          kVisitWaiting,
          _ActionStyle.neutral,
        ),
      ];
    case kVisitCancelled:
      return const [
        _VisitAction(
          'Вернуть в очередь',
          Icons.undo,
          kVisitWaiting,
          _ActionStyle.neutral,
        ),
      ];
    default:
      return const [];
  }
}

/// Плитка визита для доски очереди и живой очереди регистратуры: номер, ФИО,
/// направление, статус и кнопки перехода. [onAction] вызывается с целевым
/// статусом; [busy] блокирует кнопки во время запроса.
class VisitTile extends StatelessWidget {
  const VisitTile({
    super.key,
    required this.visit,
    required this.onAction,
    this.busy = false,
  });

  final Visit visit;
  final void Function(String newStatus) onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final actions = _actionsFor(visit.status);
    final sub = <String>[
      '№ ${visit.mrn}',
      'г.р. ${visit.birthYear}',
      if (visit.phone != null) visit.phone!,
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QueueBadge(visit.queueNumber),
              const SizedBox(width: 12),
              InitialsAvatar(visit.initials, size: 36, fontSize: 12.5),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visit.patientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.sub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(visit.statusLabel, kind: visit.statusKind),
                  if (visit.referralLabel != null) ...[
                    const SizedBox(height: 6),
                    Pill(
                      label: visit.referralLabel!,
                      color: AppColors.tealDark,
                      bg: AppColors.tealBg,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in actions)
                  _ActionButton(
                    action: a,
                    busy: busy,
                    onTap: () => onAction(a.status),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Квадратный бейдж с номером в очереди (#N).
class _QueueBadge extends StatelessWidget {
  const _QueueBadge(this.number);
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.tealBg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: AppColors.tealDark,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// Компактная кнопка действия с семантическим стилем.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.busy,
    required this.onTap,
  });

  final _VisitAction action;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onPressed = busy ? null : onTap;
    final icon = Icon(action.icon, size: 17);
    final label = Text(action.label);

    switch (action.style) {
      case _ActionStyle.primary:
        return FilledButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: label,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        );
      case _ActionStyle.neutral:
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: label,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.tealDark,
            side: const BorderSide(color: AppColors.line),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        );
      case _ActionStyle.danger:
        return TextButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: label,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.red,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        );
    }
  }
}
