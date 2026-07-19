import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Одна строка детального просмотра: подпись → значение (+опц. «шапка»-строка).
class DetailRow {
  const DetailRow(this.label, this.value, {this.strong = false});

  /// Заголовок-разделитель (без значения) — рисуется как секция.
  const DetailRow.section(this.label) : value = '', strong = true;

  final String label;
  final String value;
  final bool strong;

  bool get isSection => value.isEmpty && strong;
}

/// Единый переиспользуемый read-only детальный просмотр «список → деталь».
///
/// Любой список в системе (история пациента, журнал анализов/фиброскана,
/// движения склада, платежи, визиты, сотрудники) при тапе по строке открывает
/// ЭТО, показывая ВСЕ поля записи. [rows] — плоский список подпись→значение;
/// [extra] — произвольные виджеты (кнопки «Печать», статусы и т.п.) внизу.
Future<void> showDetailSheet(
  BuildContext context, {
  required String title,
  required List<DetailRow> rows,
  List<Widget> extra = const <Widget>[],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppColors.rCard)),
    ),
    builder: (ctx) {
      final visible = rows
          .where((r) => r.isSection || r.value.trim().isNotEmpty)
          .toList();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in visible)
                        if (r.isSection)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                            child: Text(
                              r.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: AppColors.sub,
                                letterSpacing: 0.3,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    r.label,
                                    style: const TextStyle(
                                      color: AppColors.sub,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    r.value,
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 13.5,
                                      fontWeight: r.strong
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (extra.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...extra,
              ],
            ],
          ),
        ),
      );
    },
  );
}
