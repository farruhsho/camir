import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Фирменный знак «Цадмир» — стилизованная капля (гематология) с линией
/// электрофореза/пульса поверх неё. Полноцветный inline-SVG: рисуется строкой
/// через [SvgPicture.string] БЕЗ colorFilter (в отличие от монохромного
/// [KozIcon]), поэтому сохраняет собственные цвета — тил #0F9D8F + белую линию.
/// Масштаб задаётся через [size]; asset в pubspec не добавляется.
class CadmirLogo extends StatelessWidget {
  const CadmirLogo({super.key, this.size = 40});

  final double size;

  static const String _svg =
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M24 6 C34 14 34 25 24 32 C14 25 14 14 24 6 Z" fill="#0F9D8F"/>'
      '<path d="M15 22 L21 22 L23.5 15 L27 30 L29.5 21 L33 21" fill="none" '
      'stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round" '
      'stroke-linejoin="round"/></svg>';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg, width: size, height: size);
  }
}
