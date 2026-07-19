import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../fibroscan_refs/domain/fibro_ref.dart';
import '../domain/fibroscan_record.dart';

/// Журнальный отчёт по фиброскану: таблица исследований за период (в дополнение
/// к per-record заключению из [printFibroscanReport], см. fibroscan_pdf.dart).
///
/// Строит многостраничный PDF на кириллическом шрифте (fonts/GolosText.ttf, см.
/// pubspec) и открывает системный диалог печати/сохранения через
/// [Printing.layoutPdf] (превью + печать + сохранение, в т.ч. в вебе). Пишется
/// по образцу inventory/presentation/warehouse_pdf.dart (шапка «Цадмир»,
/// [pw.TableHelper.fromTextArray], постраничный колонтитул) и разделяет с
/// fibroscan_pdf.dart шрифт и фирменные цвета.

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

/// ISO `YYYY-MM-DD…` → `ДД.ММ.ГГГГ`; иначе строка как есть (совместимость со
/// старыми записями, где дата хранилась уже как ДД.ММ.ГГГГ).
String _dmyIso(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  return m == null ? raw : '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// [DateTime] → `ДД.ММ.ГГГГ`.
String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year.toString().padLeft(4, '0')}';

/// Число без лишнего `.0`: `8.0`→`8`, `8.2`→`8.2`.
String _num(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Ячейка LSM: «8.2 · F2» (значение кПа + стадия фиброза) или «—», если не
/// измерялось. Стадия — через [stageForLsm] по справочнику [refs].
String _lsmCell(FibroscanRecord r, List<FibroRef> refs) {
  final lsm = r.lsm;
  if (lsm == null) return '—';
  final stage = stageForLsm(lsm, refs);
  return stage.isEmpty ? _num(lsm) : '${_num(lsm)} · $stage';
}

/// Ячейка CAP: «250 · S1» (значение дБ/м + степень стеатоза) или «—». Степень —
/// через [gradeForCap] по справочнику [refs].
String _capCell(FibroscanRecord r, List<FibroRef> refs) {
  final cap = r.cap;
  if (cap == null) return '—';
  final grade = gradeForCap(cap, refs);
  return grade.isEmpty ? _num(cap) : '${_num(cap)} · $grade';
}

/// Печатает / экспортирует ЖУРНАЛ исследований фиброскана за период.
///
/// [records] — записи периода (обычно из `listForPeriod`); [refs] — справочник
/// для стадии фиброза (F..) и степени стеатоза (S..). [periodLabel] —
/// человекочитаемая метка («Сегодня» / «За 7 дней» / «За 30 дней»),
/// [from]/[to] — границы периода (ДД.ММ.ГГГГ выводятся в шапке). Колонки:
/// дата · ФИО · г.р. · диагноз · LSM(кПа)+стадия · CAP(дБ/м)+степень · IQR/Med.
Future<void> printFibroscanJournal({
  required List<FibroscanRecord> records,
  required List<FibroRef> refs,
  required String periodLabel,
  required DateTime from,
  required DateTime to,
}) async {
  final font = await _loadCyrillic();
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  const teal = PdfColor.fromInt(0xFF0B7468);
  const sub = PdfColor.fromInt(0xFF5C6F6A);
  const headerBg = PdfColor.fromInt(0xFFEAF4F2);

  final periodText = from.isAtSameMomentAs(to)
      ? _dmy(from)
      : '${_dmy(from)} – ${_dmy(to)}';

  final headers = <String>[
    'Дата',
    'ФИО',
    'Г.р.',
    'Диагноз',
    'LSM (кПа)',
    'CAP (дБ/м)',
    'IQR/Med',
  ];

  final rows = <List<String>>[
    for (final r in records)
      <String>[
        _dmyIso(r.date),
        r.fullName,
        r.birthYear > 0 ? r.birthYear.toString() : '—',
        r.diagnosis,
        _lsmCell(r, refs),
        _capCell(r, refs),
        r.iqrMed != null ? '${_num(r.iqrMed!)} %' : '—',
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      theme: theme,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'Журнал исследований фиброскана «Цадмир» · $periodText',
                style: pw.TextStyle(fontSize: 9, color: sub),
              ),
            ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Стр. ${context.pageNumber} из ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: sub),
        ),
      ),
      build: (context) => [
        // Шапка клиники.
        pw.Text(
          'Медицинский центр «Цадмир»',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: teal,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Гематологический центр',
          style: pw.TextStyle(fontSize: 11, color: sub),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1, color: teal),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Журнал исследований фиброскана',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Период: $periodLabel · $periodText',
              style: pw.TextStyle(fontSize: 11, color: sub),
            ),
          ],
        ),
        pw.SizedBox(height: 12),

        if (rows.isEmpty)
          pw.Text(
            'За выбранный период исследований нет.',
            style: pw.TextStyle(fontSize: 12, color: sub),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            border: pw.TableBorder.all(
              color: const PdfColor.fromInt(0xFFD8E2DF),
              width: 0.5,
            ),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: teal,
            ),
            headerDecoration: const pw.BoxDecoration(color: headerBg),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellHeight: 22,
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.7),
              5: const pw.FlexColumnWidth(1.7),
              6: const pw.FlexColumnWidth(1.2),
            },
          ),

        pw.SizedBox(height: 14),
        pw.Text(
          'Всего исследований: ${records.length}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Стадии фиброза: F0–F1 (норма/мин.) · F2 (умеренный) · '
          'F3 (выраженный) · F4 (цирроз). Степени стеатоза: S0–S3. '
          'IQR/Med ≤ 30 % — измерение LSM надёжно.',
          style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF8C9C97)),
        ),

        pw.SizedBox(height: 18),
        pw.Divider(color: const PdfColor.fromInt(0xFFE4EAE7)),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Подпись врача: ____________________',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Дата печати: ${_dmy(DateTime.now())}',
              style: pw.TextStyle(fontSize: 10, color: sub),
            ),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'Фиброскан_журнал_${_dmy(to).replaceAll('.', '-')}',
  );
}
