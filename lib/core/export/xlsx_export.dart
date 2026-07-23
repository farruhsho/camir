import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

/// Единая точка выгрузки отчётов/журналов: печать в PDF (существующий путь) или
/// экспорт в .xlsx. Экраны сначала спрашивают формат через [pickExportFormat],
/// а для Excel строят те же колонки, что и PDF, и зовут [exportRowsToXlsx].
///
/// Пакеты `excel` и `file_saver` уже в pubspec. На вебе [FileSaver.saveFile]
/// скачивает файл в браузере; печать (PDF) идёт своим путём через `printing`.

/// Формат выгрузки, выбранный пользователем в нижнем листе.
enum ExportFormat {
  /// «Печать» — построить PDF и открыть системный диалог печати (на вебе — диалог
  /// печати браузера → принтер).
  printPdf,

  /// «Экспорт в Excel» — собрать .xlsx и сохранить/скачать файл.
  excel,
}

/// Показывает нижний лист выбора формата выгрузки: «Печать» или
/// «Экспорт в Excel». Возвращает выбор пользователя либо `null` (лист закрыт).
Future<ExportFormat?> pickExportFormat(BuildContext context) {
  return showModalBottomSheet<ExportFormat>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Печать'),
            subtitle: const Text('Открыть диалог печати'),
            onTap: () => Navigator.of(sheetCtx).pop(ExportFormat.printPdf),
          ),
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('Экспорт в Excel'),
            subtitle: const Text('Скачать файл .xlsx'),
            onTap: () => Navigator.of(sheetCtx).pop(ExportFormat.excel),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Строит книгу Excel из табличных данных и сохраняет её как `<fileName>.xlsx`
/// (на вебе — скачивает файл).
///
/// [sheetName] — имя листа; [headers] — строка заголовков; [rows] — строки
/// данных (тип ячейки выбирается по рантайм-типу значения); [title] —
/// необязательная строка-заголовок над заголовками колонок.
Future<void> exportRowsToXlsx({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
  String? title,
}) async {
  final book = xls.Excel.createExcel();
  final sheet = book[sheetName];

  // Необязательная строка-заголовок (период / дата отчёта) над колонками.
  if (title != null && title.trim().isNotEmpty) {
    sheet.appendRow(<xls.CellValue?>[xls.TextCellValue(title)]);
  }

  // Заголовки колонок.
  sheet.appendRow(<xls.CellValue?>[
    for (final h in headers) xls.TextCellValue(h),
  ]);

  // Данные: тип ячейки по рантайм-типу значения.
  for (final row in rows) {
    sheet.appendRow(<xls.CellValue?>[for (final v in row) _cell(v)]);
  }

  // `Excel.createExcel()` создаёт дефолтный лист «Sheet1»; убираем его, если он
  // не совпадает с нашим листом, чтобы в файле не осталось пустой вкладки.
  final def = book.getDefaultSheet();
  if (def != null && def != sheetName) book.delete(def);

  final bytes = book.encode();
  if (bytes == null) {
    throw const _XlsxException('Не удалось сформировать файл Excel.');
  }

  await FileSaver.instance.saveFile(
    name: fileName,
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

/// Ячейка Excel по рантайм-типу значения: `int → IntCellValue`,
/// `double/num → DoubleCellValue`, `null → пустой текст`, иначе — текст.
xls.CellValue _cell(Object? value) {
  if (value == null) return xls.TextCellValue('');
  if (value is int) return xls.IntCellValue(value);
  if (value is double) return xls.DoubleCellValue(value);
  if (value is num) return xls.DoubleCellValue(value.toDouble());
  return xls.TextCellValue(value.toString());
}

/// Ошибка формирования файла с уже человеко-читаемым русским текстом
/// (`toString()` без технического префикса — `friendlyError` отдаёт его как есть).
class _XlsxException implements Exception {
  const _XlsxException(this.message);

  final String message;

  @override
  String toString() => message;
}
