import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'koz_icons.dart';

/// Shared «Clinic OS» building blocks (mirror the prototype). Screens compose
/// these so the visual language stays consistent across the whole app.

/// White rounded card with the brand hairline border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rCard),
        border: Border.all(color: AppColors.line),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.rCard),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Dashboard KPI tile: icon chip, big tabular number, label, optional trend
/// pill. [accent] paints the dark-teal gradient hero variant. [onTap] makes the
/// whole card a navigation target.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    this.icon,
    this.iconKey,
    required this.value,
    required this.label,
    this.accent = false,
    this.trend,
    this.onTap,
  }) : assert(icon != null || iconKey != null, 'provide icon or iconKey');

  /// Material fallback icon. Ignored when [iconKey] is set.
  final IconData? icon;

  /// Prototype line-icon key (see [KozIcons]). Takes precedence over [icon].
  final String? iconKey;
  final String value;
  final String label;
  final bool accent;
  final String? trend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        gradient: accent ? AppColors.sidebarGradient : null,
        color: accent ? null : AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.rCard),
        border: accent ? null : Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent
                      ? Colors.white.withValues(alpha: 0.10)
                      : AppColors.tealBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: iconKey != null
                    ? KozIcon(iconKey!,
                        size: 20,
                        color: accent ? AppColors.mintLight : AppColors.tealDark)
                    : Icon(icon,
                        size: 20,
                        color: accent ? AppColors.mintLight : AppColors.tealDark),
              ),
              const Spacer(),
              if (trend != null)
                Pill(label: trend!, color: AppColors.green, bg: AppColors.greenBg),
            ],
          ),
          // Flexible + scale-down keeps the number/label fitting any cell height
          // (the dashboard grid hands out varied sizes) — never overflows.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      style: AppTypography.number(24,
                          color: accent ? Colors.white : AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 13,
                          color: accent ? const Color(0xFF9FC4BC) : AppColors.sub)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.rCard),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Small rounded pill (trend, count).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color = AppColors.sub, this.bg = AppColors.line2});

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

enum BadgeKind { neutral, info, success, warning, danger }

/// Status chip with a semantic colour pair (Ожидает / Вызван / Оплачено …).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.kind = BadgeKind.neutral});

  final String label;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (kind) {
      BadgeKind.success => (AppColors.green, AppColors.greenBg),
      BadgeKind.warning => (AppColors.amber, AppColors.amberBg),
      BadgeKind.danger => (AppColors.red, AppColors.redBg),
      BadgeKind.info => (AppColors.blue, AppColors.blueBg),
      BadgeKind.neutral => (AppColors.sub, AppColors.line2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Primary call-to-action with the teal gradient + soft glow (matches the
/// prototype's main buttons). Falls back to a disabled look when [onPressed] is
/// null or [loading].
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.height = 48,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppColors.rField),
          boxShadow: [
            BoxShadow(
                color: AppColors.tealDark.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppColors.rField),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: height,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                          ],
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient initials avatar used across patient/staff lists.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.text, {super.key, this.size = 40, this.fontSize = 13.5});

  final String text;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.avatarGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(text.toUpperCase(),
          style: AppTypography.number(fontSize, weight: FontWeight.w700, color: Colors.white)),
    );
  }
}
