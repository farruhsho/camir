import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../fibroscan_refs/domain/fibro_ref.dart';
import '../domain/fibroscan_record.dart';

/// Печать / экспорт заключения фиброскана (эластографии печени) — задача (3).
///
/// Строит одностраничный PDF на кириллическом шрифте (fonts/GolosText.ttf,
/// см. pubspec) и открывает системный диалог печати/сохранения через
/// [Printing.layoutPdf] (превью + печать + сохранение в файл, в т.ч. в вебе).
/// Мирроринг бланка анализов (analysis_pdf.dart): та же шапка «Цадмир», тот же
/// шрифт и та же схема строк «label → value».

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

/// Число без лишнего `.0`: `8.0`→`8`, `8.2`→`8.2`.
String _num(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Клиническая расшифровка стадии фиброза (метка бэнда `note`, если есть).
String? _bandNote(num value, List<FibroRef> refs, String kind) {
  final pool = refs.any((r) => r.kind == kind) ? refs : kDefaultFibroRefs;
  for (final r in pool) {
    if (r.kind != kind) continue;
    final lo = r.min;
    final hi = r.max;
    final okLo = lo == null || value >= lo;
    final okHi = hi == null || value < hi;
    if (okLo && okHi) return (r.note ?? '').trim().isEmpty ? null : r.note;
  }
  return null;
}

/// Печатает / экспортирует заключение одного исследования фиброскана.
/// [refs] — справочник референсов (стадия фиброза F0–F4 по LSM, степень
/// стеатоза S0–S3 по CAP + клинические заметки для интерпретации).
Future<void> printFibroscanReport(
  FibroscanRecord record,
  List<FibroRef> refs,
) async {
  final font = await _loadCyrillic();
  final doc = pw.Document();
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  final lsm = record.lsm;
  final cap = record.cap;
  final iqr = record.iqrMed;
  final valid = record.validMeasurements;

  final stage = lsm != null ? stageForLsm(lsm, refs) : '';
  final grade = cap != null ? gradeForCap(cap, refs) : '';
  final stageNote = lsm != null
      ? _bandNote(lsm, refs, kFibroKindFibrosis)
      : null;
  final gradeNote = cap != null
      ? _bandNote(cap, refs, kFibroKindSteatosis)
      : null;

  // Текстовая интерпретация: стадия фиброза + степень стеатоза + надёжность.
  final interpretation = _buildInterpretation(
    stage: stage,
    stageNote: stageNote,
    grade: grade,
    gradeNote: gradeNote,
    iqr: iqr,
  );

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
                'Заключение эластографии печени (фиброскан)',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 18),

            // Данные пациента.
            _row('Пациент (ФИО):', record.fullName),
            if (record.birthYear > 0)
              _row('Год рождения:', record.birthYear.toString()),
            _row('Дата исследования:', _dmy(record.date)),
            _row('Диагноз:', record.diagnosis),
            pw.SizedBox(height: 12),

            // Результаты измерений.
            pw.Text(
              'Результаты измерений',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF0B7468),
              ),
            ),
            pw.SizedBox(height: 6),
            _row(
              'LSM (жёсткость):',
              lsm != null
                  ? '${_num(lsm)} кПа'
                        '${stage.isNotEmpty ? '   ·   стадия фиброза $stage' : ''}'
                  : 'не измерялось',
              strong: lsm != null,
            ),
            _row(
              'CAP (стеатоз):',
              cap != null
                  ? '${_num(cap)} дБ/м'
                        '${grade.isNotEmpty ? '   ·   степень стеатоза $grade' : ''}'
                  : 'не измерялось',
              strong: cap != null,
            ),
            if (iqr != null)
              _row(
                'IQR/Med:',
                '${_num(iqr)} %   ·   ${fibroReliabilityLabel(iqr)}',
              ),
            if (valid != null) _row('Валидных измерений:', valid.toString()),

            pw.SizedBox(height: 14),
            // Интерпретация текстом.
            pw.Text(
              'Интерпретация',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF0B7468),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF2F7F6),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                interpretation,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Стадии фиброза: F0–F1 (норма/мин.) · F2 (умеренный) · '
              'F3 (выраженный) · F4 (цирроз). Степени стеатоза: '
              'S0–S3. Заключение носит справочный характер и '
              'интерпретируется лечащим врачом.',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromInt(0xFF8C9C97),
              ),
            ),

            pw.Spacer(),
            pw.Divider(color: PdfColor.fromInt(0xFFE4EAE7)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Подпись врача: ____________________',
                  style: const pw.TextStyle(fontSize: 11),
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
    name: 'Фиброскан_заключение_$safeName',
  );
}

/// Собирает связный текст интерпретации из стадии/степени, их клинических
/// заметок и надёжности измерения. Пустые части опускаются; если измерений
/// нет вовсе — возвращает нейтральную заглушку.
String _buildInterpretation({
  required String stage,
  required String? stageNote,
  required String grade,
  required String? gradeNote,
  required num? iqr,
}) {
  final lines = <String>[];
  if (stage.isNotEmpty) {
    final note = (stageNote ?? '').trim();
    lines.add(
      'Фиброз печени: стадия $stage${note.isNotEmpty ? ' — $note' : ''}.',
    );
  }
  if (grade.isNotEmpty) {
    final note = (gradeNote ?? '').trim();
    lines.add(
      'Стеатоз печени: степень $grade${note.isNotEmpty ? ' — $note' : ''}.',
    );
  }
  if (iqr != null) {
    lines.add(
      isFibroIqrReliable(iqr)
          ? 'Надёжность измерения: IQR/Med ${_num(iqr)} % — измерение '
                'надёжно (не более 30 %).'
          : 'Надёжность измерения: IQR/Med ${_num(iqr)} % — низкая '
                'надёжность (более 30 %); рекомендуется повторить '
                'исследование.',
    );
  }
  if (lines.isEmpty) {
    return 'Количественные измерения не вносились. '
        'Заключение формируется лечащим врачом.';
  }
  return lines.join('\n');
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
