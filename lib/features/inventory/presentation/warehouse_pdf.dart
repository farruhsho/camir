import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/stock_math.dart';
import '../domain/warehouse_product.dart';

/// Печать / экспорт складского отчёта (задача 3, инвентарь).
///
/// Строит PDF на кириллическом шрифте (fonts/GolosText.ttf, см. pubspec) и
/// открывает системный диалог печати/сохранения через [Printing.layoutPdf]
/// (превью + печать + сохранение в файл, в т.ч. в вебе). Пишется по образцу
/// analyses/presentation/analysis_pdf.dart.

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

/// Печатает / экспортирует отчёт по складу: перечень товаров с остатком,
/// минимумом, сроком годности и статусом (мало / истекает / истёк).
Future<void> printWarehouseReport(List<ProductStock> items) async {
  final font = await _loadCyrillic();
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  const teal = PdfColor.fromInt(0xFF0B7468);
  const sub = PdfColor.fromInt(0xFF5C6F6A);
  const headerBg = PdfColor.fromInt(0xFFEAF4F2);
  const red = PdfColor.fromInt(0xFFC0392B);
  const amber = PdfColor.fromInt(0xFFB9791F);

  final headers = <String>[
    'Товар',
    'Категория',
    'Ед.',
    'Остаток',
    'Мин.',
    'Срок годности',
    'Статус',
  ];

  final rows = <List<String>>[
    for (final ps in items)
      <String>[
        ps.product.name,
        ps.product.category ?? '—',
        ps.product.unit,
        formatStock(ps.stock),
        ps.product.minStock != null ? formatStock(ps.product.minStock!) : '—',
        _dmy(ps.product.expiry),
        _statusText(ps),
      ],
  ];

  // Счётчики для сводки под таблицей.
  final lowCount = items.where((i) => i.low).length;
  final expiredCount = items.where((i) => i.product.expired).length;
  final soonCount = items.where((i) => i.product.expiringSoon).length;

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
                'Отчёт по складу «Цадмир»',
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
              'Складской отчёт',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Дата: ${_dmy(DateTime.now())}',
              style: pw.TextStyle(fontSize: 11, color: sub),
            ),
          ],
        ),
        pw.SizedBox(height: 12),

        if (rows.isEmpty)
          pw.Text('Товаров нет.', style: pw.TextStyle(fontSize: 12, color: sub))
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
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(3.2),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.1),
              5: const pw.FlexColumnWidth(1.8),
              6: const pw.FlexColumnWidth(2),
            },
          ),

        pw.SizedBox(height: 14),
        pw.Text(
          'Всего товаров: ${items.length}',
          style: pw.TextStyle(fontSize: 10, color: sub),
        ),
        if (lowCount > 0)
          pw.Text(
            'Мало на складе: $lowCount',
            style: pw.TextStyle(fontSize: 10, color: amber),
          ),
        if (soonCount > 0)
          pw.Text(
            'Истекает срок годности (≤ $kExpirySoonDays дн.): $soonCount',
            style: pw.TextStyle(fontSize: 10, color: amber),
          ),
        if (expiredCount > 0)
          pw.Text(
            'Просрочено: $expiredCount',
            style: pw.TextStyle(fontSize: 10, color: red),
          ),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => doc.save(),
    name: 'Склад_отчёт_${_dmy(DateTime.now()).replaceAll('.', '-')}',
  );
}

/// Сводный статус строки: «мало» / «истекает» / «истёк» (через запятую), либо «—».
String _statusText(ProductStock ps) {
  final parts = <String>[];
  if (ps.low) parts.add('мало');
  if (ps.product.expired) {
    parts.add('истёк');
  } else if (ps.product.expiringSoon) {
    parts.add('истекает');
  }
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// [DateTime] → `ДД.ММ.ГГГГ`; null → «—».
String _dmy(DateTime? d) {
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.year.toString().padLeft(4, '0')}';
}
