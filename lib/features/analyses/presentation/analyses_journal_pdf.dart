import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../analysis_types/domain/analysis_type.dart';
import '../domain/analysis_record.dart';
import '../domain/analysis_result_view.dart';

/// Печать / экспорт ЖУРНАЛА анализов за период (в дополнение к бланку одного
/// результата из [analysis_pdf.dart]).
///
/// Строит табличный PDF на кириллическом шрифте (fonts/GolosText.ttf, см.
/// pubspec) и открывает системный диалог печати/сохранения через
/// [Printing.layoutPdf] (превью + печать + сохранение в файл, в т.ч. в вебе).
/// Используется [pw.MultiPage], поэтому длинный список автоматически разбивается
/// на страницы; шапка с итогом — на первой странице, подпись — в конце.

/// Бренд-цвета (совпадают с бланком одного результата).
const _teal = 0xFF0B7468;
const _tealBg = 0xFFEAF5F3;
const _sub = 0xFF5C6F6A;
const _muted = 0xFF8C9C97;
const _line = 0xFFE4EAE7;

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

String _todayIso() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Печатает / экспортирует журнал анализов за период.
///
/// [records] — уже отфильтрованные и отсортированные записи (свежие сверху);
/// [types] — справочник видов анализов для разрешения единицы и оценки нормы
/// (может быть пустым — тогда единица/флаг опускаются); [periodLabel] —
/// человекочитаемая подпись периода (например «за 19.07.2026» или
/// «за период 12.07.2026 – 19.07.2026»).
Future<void> printAnalysesJournal({
  required List<AnalysisRecord> records,
  required List<AnalysisType> types,
  required String periodLabel,
}) async {
  final font = await _loadCyrillic();
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  const headers = <String>['Дата', 'ФИО', 'Г.р.', 'Вид анализа', 'Результат'];
  final data = <List<String>>[];
  for (final r in records) {
    final type = findAnalysisType(types, r.analysisType);
    final hasResult = (r.result ?? '').trim().isNotEmpty;
    final resultText = hasResult ? resultWithUnit(r.result, type) : 'ожидается';
    final flag = resultFlag(r.result, type);
    data.add(<String>[
      _dmy(r.date),
      r.fullName,
      r.birthYear.toString(),
      r.analysisType,
      flag.isEmpty ? resultText : '$resultText ($flag)',
    ]);
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Стр. ${context.pageNumber} из ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(_muted)),
        ),
      ),
      build: (context) => [
        _header(periodLabel, records.length),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data,
          border: pw.TableBorder.all(color: PdfColor.fromInt(_line), width: .5),
          headerStyle: pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(_teal),
          ),
          headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(_tealBg)),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 5,
          ),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            2: pw.Alignment.center,
          },
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(2.6),
            4: pw.FlexColumnWidth(2.6),
          },
        ),
        pw.SizedBox(height: 28),
        _signature(),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'Журнал_анализов_${_todayIso()}',
  );
}

/// Шапка журнала: клиника, заголовок, период и итоговое количество.
pw.Widget _header(String periodLabel, int total) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Text(
        'Медицинский центр «Цадмир»',
        style: pw.TextStyle(
          fontSize: 18,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromInt(_teal),
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Гематологический центр',
        style: pw.TextStyle(fontSize: 11, color: PdfColor.fromInt(_sub)),
      ),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 1, color: PdfColor.fromInt(_teal)),
      pw.SizedBox(height: 10),
      pw.Center(
        child: pw.Text(
          'Журнал анализов',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Период: $periodLabel',
            style: pw.TextStyle(fontSize: 11, color: PdfColor.fromInt(_sub)),
          ),
          pw.Text(
            'Всего записей: $total',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(_sub),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Подпись специалиста + дата печати (в конце журнала).
pw.Widget _signature() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(color: PdfColor.fromInt(_line)),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Подпись специалиста: ____________________',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text(
            'Дата печати: ${_dmy(_todayIso())}',
            style: pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(_muted)),
          ),
        ],
      ),
    ],
  );
}
