import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../analysis_types/domain/analysis_type.dart';
import '../domain/analysis_record.dart';
import '../domain/analysis_result_view.dart';

/// Печать / экспорт бланка результата анализа (задача 8).
///
/// Строит одностраничный PDF на кириллическом шрифте (fonts/GolosText.ttf,
/// см. pubspec) и открывает системный диалог печати/сохранения через
/// [Printing.layoutPdf] (превью + печать + сохранение в файл, в т.ч. в вебе).

/// Кэш загруженного шрифта — грузим TTF из ассетов один раз на сессию.
pw.Font? _cyrillicFont;

Future<pw.Font> _loadCyrillic() async {
  final cached = _cyrillicFont;
  if (cached != null) return cached;
  final data = await rootBundle.load('fonts/GolosText.ttf');
  final font = pw.Font.ttf(data);
  _cyrillicFont = font;
  return font;
}

/// ISO `YYYY-MM-DD…` → `ДД.ММ.ГГГГ`; иначе как есть.
String _dmy(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  return m == null ? raw : '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// Печатает / экспортирует бланк одного результата. [type] — привязанный вид
/// анализа из справочника (для единицы, референса и заключения); может быть
/// `null` для «свободного»/легаси-типа — тогда единица/референс/заключение
/// опускаются.
Future<void> printAnalysisRecord(
  AnalysisRecord record,
  AnalysisType? type,
) async {
  final font = await _loadCyrillic();
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  final resultText = resultWithUnit(record.result, type);
  final reference = referenceRange(type);
  final flag = resultFlag(record.result, type);
  final hasResult = (record.result ?? '').trim().isNotEmpty;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Шапка клиники.
            pw.Text(
              'Медицинский центр «Цадмир»',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF0B7468),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Гематологический центр',
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromInt(0xFF5C6F6A),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1, color: PdfColor.fromInt(0xFF0B7468)),
            pw.SizedBox(height: 14),
            pw.Center(
              child: pw.Text(
                'Результат лабораторного исследования',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 18),

            // Данные пациента.
            _row('Пациент (ФИО):', record.fullName),
            _row('Год рождения:', record.birthYear.toString()),
            if ((record.phone ?? '').trim().isNotEmpty)
              _row('Телефон:', record.phone!.trim()),
            pw.SizedBox(height: 10),

            // Данные анализа.
            _row('Вид анализа:', record.analysisType),
            _row('Дата анализа:', _dmy(record.date)),
            _row(
              'Результат:',
              hasResult ? resultText : 'ожидается',
              strong: hasResult,
            ),
            if (reference.isNotEmpty) _row('Референс (норма):', reference),
            if (flag.isNotEmpty) _row('Заключение:', flag, strong: true),

            pw.Spacer(),
            pw.Divider(color: PdfColor.fromInt(0xFFE4EAE7)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Подпись специалиста: ____________________',
                  style: pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  'Дата печати: ${_dmy(_todayIso())}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromInt(0xFF8C9C97),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  final safeName = record.fullName.trim().replaceAll(RegExp(r'\s+'), '_');
  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'Анализ_${record.analysisType}_$safeName',
  );
}

pw.Widget _row(String label, String value, {bool strong = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColor.fromInt(0xFF5C6F6A),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}

String _todayIso() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
