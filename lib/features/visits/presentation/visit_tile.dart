import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/detail_sheet.dart';
import '../../../core/widgets/koz_widgets.dart';
import '../domain/visit.dart';

/// Плитка приёма для списка «Сегодня» регистратуры: пациент, услуга, статус и
/// действия по стадии приёма.
///
/// Действия зависят от статуса и переданных колбэков:
///  * `awaiting_payment` → «Оплатить» ([onPay]);
///  * `paid` → «Направить: …» ([onRoute], если у направления есть экран) и
///    «Завершить» ([onDone]);
///  * `done` → действий нет.
/// [busy] блокирует кнопки во время запроса. Тап по плитке открывает единый
/// детальный просмотр со ВСЕМИ полями приёма.
class VisitTile extends StatelessWidget {
  const VisitTile({
    super.key,
    required this.visit,
    this.busy = false,
    this.onPay,
    this.onRoute,
    this.onDone,
  });

  final Visit visit;
  final bool busy;

  /// Провести оплату приёма (только для `awaiting_payment`).
  final VoidCallback? onPay;

  /// Направить к специалисту (только для `paid`; `null`, если у направления нет
  /// профильного экрана, напр. консультация).
  final VoidCallback? onRoute;

  /// Завершить приём (только для `paid`).
  final VoidCallback? onDone;

  /// Открывает единый детальный просмотр «список → деталь» со ВСЕМИ полями приёма.
  void _showDetail(BuildContext context) {
    final v = visit;
    showDetailSheet(
      context,
      title: v.patientName.isEmpty ? 'Приём' : v.patientName,
      rows: [
        DetailRow('№ приёма', '${v.queueNumber}', strong: true),
        DetailRow('Статус', v.statusLabel, strong: true),
        DetailRow.section('Пациент'),
        DetailRow('ФИО', v.patientName),
        DetailRow('№ карты', v.mrn),
        DetailRow('Год рождения', '${v.birthYear}'),
        if (v.phone != null) DetailRow('Телефон', v.phone!),
        DetailRow('Направление', v.referralLabel ?? ''),
        DetailRow.section('Услуга'),
        DetailRow('Наименование', v.serviceName ?? ''),
        if (v.servicePrice != null)
          DetailRow('Цена', formatMoney(v.servicePrice.toString())),
        if (v.note != null)
          DetailRow('Заметка (консультация регистратуры)', v.note!),
        DetailRow.section('Время'),
        DetailRow('Зарегистрирован', _fmtTs(v.createdAt)),
        DetailRow('Оплачен', _fmtTs(v.paidAt)),
        DetailRow('Завершён', _fmtTs(v.doneAt)),
        DetailRow.section('Служебное'),
        DetailRow('ID приёма', v.id),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = <String>[
      '№ ${visit.mrn}',
      'г.р. ${visit.birthYear}',
      if (visit.phone != null) visit.phone!,
    ].join('  ·  ');

    final actions = _buildActions();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rField),
        child: InkWell(
          onTap: () => _showDetail(context),
          borderRadius: BorderRadius.circular(AppColors.rField),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
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
                          if (visit.serviceName != null) ...[
                            const SizedBox(height: 6),
                            _ServiceChip(
                              name: visit.serviceName!,
                              price: visit.servicePrice,
                            ),
                          ],
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
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Кнопки действий для текущего статуса приёма (только те, для которых
  /// передан колбэк).
  List<Widget> _buildActions() {
    if (visit.isAwaitingPayment && onPay != null) {
      return [
        _ActionButton(
          label: 'Оплатить',
          icon: Icons.payments_outlined,
          style: _ActionStyle.primary,
          busy: busy,
          onTap: onPay!,
        ),
      ];
    }
    if (visit.isPaid) {
      return [
        if (onRoute != null)
          _ActionButton(
            label: 'Направить: ${visit.referralLabel}',
            icon: Icons.arrow_forward,
            style: _ActionStyle.primary,
            busy: busy,
            onTap: onRoute!,
          ),
        if (onDone != null)
          _ActionButton(
            label: 'Завершить',
            icon: Icons.check_circle_outline,
            style: _ActionStyle.neutral,
            busy: busy,
            onTap: onDone!,
          ),
      ];
    }
    return const [];
  }
}

/// Форматирует таймстамп события приёма как `ДД.ММ.ГГГГ ЧЧ:ММ`
/// (или пустую строку — тогда строка детали скрывается).
String _fmtTs(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year.toString().padLeft(4, '0')} '
      '${two(l.hour)}:${two(l.minute)}';
}

/// Квадратный бейдж с номером приёма (#N).
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

/// Чип услуги приёма: наименование + цена «сом».
class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.name, required this.price});

  final String name;
  final num? price;

  @override
  Widget build(BuildContext context) {
    final label = price != null
        ? '$name · ${formatMoney(price.toString())}'
        : name;
    return Pill(label: label, color: AppColors.sub, bg: AppColors.line2);
  }
}

/// Визуальный стиль кнопки действия.
enum _ActionStyle { primary, neutral }

/// Компактная кнопка действия с семантическим стилем.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.style,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final _ActionStyle style;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onPressed = busy ? null : onTap;
    final iconWidget = Icon(icon, size: 17);
    final labelWidget = Text(label);

    switch (style) {
      case _ActionStyle.primary:
        return FilledButton.icon(
          onPressed: onPressed,
          icon: iconWidget,
          label: labelWidget,
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
          icon: iconWidget,
          label: labelWidget,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.tealDark,
            side: const BorderSide(color: AppColors.line),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        );
    }
  }
}
