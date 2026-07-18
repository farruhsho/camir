import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Exact line-icons from the «Clinic OS» prototype (the HTML `I` map), plus a
/// few matching extras for app-only modules. Rendered via [KozIcon] so the whole
/// app uses the same crisp 24×24 stroke icons as the design.
class KozIcons {
  const KozIcons._();

  static const Map<String, String> paths = {
    // ── from the prototype ─────────────────────────────────────────────
    'eye': '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="3.2" fill="currentColor"/>',
    'dashboard': '<rect x="3" y="3" width="8" height="8" rx="2" stroke="currentColor" stroke-width="1.7"/><rect x="13" y="3" width="8" height="5" rx="2" stroke="currentColor" stroke-width="1.7"/><rect x="13" y="10" width="8" height="11" rx="2" stroke="currentColor" stroke-width="1.7"/><rect x="3" y="13" width="8" height="8" rx="2" stroke="currentColor" stroke-width="1.7"/>',
    'schedule': '<rect x="3" y="4" width="18" height="17" rx="2.5" stroke="currentColor" stroke-width="1.7"/><path d="M3 9h18M8 2v4M16 2v4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    'reception': '<rect x="4" y="3" width="16" height="18" rx="2.5" stroke="currentColor" stroke-width="1.7"/><path d="M8 3v4h8V3M8 12h8M8 16h5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    'patients': '<circle cx="9" cy="8" r="3.4" stroke="currentColor" stroke-width="1.7"/><path d="M3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5" stroke="currentColor" stroke-width="1.7"/><path d="M16 5.2A3.4 3.4 0 0 1 18 11M17 14.7c2.4.5 4 2.5 4 5.3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    'queue': '<path d="M8 6h13M8 12h13M8 18h13" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="3.5" cy="6" r="1.5" fill="currentColor"/><circle cx="3.5" cy="12" r="1.5" fill="currentColor"/><circle cx="3.5" cy="18" r="1.5" fill="currentColor"/>',
    'worklist': '<path d="M6 3v6a4 4 0 0 0 8 0V3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M10 17a4 4 0 0 0 8 0v-2" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="18" cy="13" r="2" stroke="currentColor" stroke-width="1.7"/>',
    'finance': '<rect x="3" y="6" width="18" height="13" rx="2.5" stroke="currentColor" stroke-width="1.7"/><path d="M3 10h18" stroke="currentColor" stroke-width="1.7"/><circle cx="16.5" cy="14.5" r="1.5" fill="currentColor"/>',
    'analytics': '<path d="M3 3v18h18" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M7 14l4-4 3 3 5-6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
    'inventory': '<path d="M3 7l9-4 9 4-9 4-9-4Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M3 7v10l9 4 9-4V7M12 11v10" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
    'lab': '<path d="M9 3v6L4.5 18a2 2 0 0 0 1.8 3h11.4a2 2 0 0 0 1.8-3L15 9V3" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M8 3h8M7.5 14h9" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    'notifications': '<path d="M6 9a6 6 0 0 1 12 0c0 7 3 7 3 9H3c0-2 3-2 3-9Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M10 21a2 2 0 0 0 4 0" stroke="currentColor" stroke-width="1.7"/>',
    'settings': '<circle cx="12" cy="12" r="3" stroke="currentColor" stroke-width="1.7"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6A7 7 0 0 0 5 12c0 .4 0 .8.1 1.2l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>',
    'search': '<circle cx="11" cy="11" r="7" stroke="currentColor" stroke-width="1.8"/><path d="M21 21l-4-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
    'logout': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
    'bell': '<path d="M6 9a6 6 0 0 1 12 0c0 7 3 7 3 9H3c0-2 3-2 3-9Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M10 21a2 2 0 0 0 4 0" stroke="currentColor" stroke-width="1.7"/>',
    // ── matching extras for app-only modules (same stroke style) ────────
    'calls': '<path d="M5.5 4h3l1.4 4-2 1.4a11 11 0 0 0 5 5l1.4-2 4 1.4v3a2 2 0 0 1-2 2A15 15 0 0 1 3.5 6a2 2 0 0 1 2-2Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
    'devices': '<path d="M7 19h10M9.5 19v-3M14.5 19v-3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M6 8a6 6 0 0 0 12 0" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="9.5" y="3" width="5" height="9" rx="2.5" stroke="currentColor" stroke-width="1.7"/>',
    'face': '<rect x="3" y="3" width="18" height="18" rx="5" stroke="currentColor" stroke-width="1.7"/><circle cx="9.5" cy="10.5" r="1.1" fill="currentColor"/><circle cx="14.5" cy="10.5" r="1.1" fill="currentColor"/><path d="M9 15c1.6 1.3 4.4 1.3 6 0" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
    'badge': '<rect x="4" y="4" width="16" height="16" rx="3.5" stroke="currentColor" stroke-width="1.7"/><circle cx="12" cy="10" r="2.4" stroke="currentColor" stroke-width="1.7"/><path d="M8 17c.8-2 2.2-3 4-3s3.2 1 4 3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
  };

  static bool has(String key) => paths.containsKey(key);
}

/// Renders a prototype line-icon, tinted to [color] (or the ambient icon color).
/// Falls back to a neutral material icon for unknown keys.
class KozIcon extends StatelessWidget {
  const KozIcon(this.name, {super.key, this.size = 19, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF12201E);
    final p = KozIcons.paths[name];
    if (p == null) {
      return Icon(Icons.circle_outlined, size: size, color: c);
    }
    // currentColor → a solid colour so something is painted; the colorFilter
    // then recolours every painted pixel to [c] (monochrome icons).
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
        'viewBox="0 0 24 24" fill="none">${p.replaceAll('currentColor', '#000000')}</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
