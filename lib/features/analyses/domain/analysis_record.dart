import 'package:freezed_annotation/freezed_annotation.dart';

part 'analysis_record.freezed.dart';
part 'analysis_record.g.dart';

/// Запись лабораторного анализа (mirrors backend `AnalysisOut`).
///
/// Пациент может быть выбран из картотеки ([patientId] заполнен) либо введён
/// вручную (ФИО / год рождения / телефон без ссылки на карту). [result] и
/// [phone] необязательны; [date] хранится строкой в ISO-формате `YYYY-MM-DD`,
/// как её отдаёт бэкенд (экран показывает её как ДД.ММ.ГГГГ).
@freezed
abstract class AnalysisRecord with _$AnalysisRecord {
  const factory AnalysisRecord({
    required String id,
    String? patientId,
    required String fullName,
    required int birthYear,
    String? phone,
    required String analysisType,
    String? result,
    required String date,
  }) = _AnalysisRecord;

  factory AnalysisRecord.fromJson(Map<String, dynamic> json) =>
      _$AnalysisRecordFromJson(json);
}

/// Справочник видов анализов гематологического центра — источник для выпадашки
/// при создании записи. Порядок фиксированный (как задал профиль клиники).
const List<String> kAnalysisTypes = <String>[
  'АЛТ',
  'АСТ',
  'ОАМ',
  'ОАК',
  'Глюкоза крови',
  'HDV маркер',
  'HCV маркер',
  'HBSAg маркер',
  'ПЦР ВГВ количество',
  'ПЦР ВГС количество',
  'ПЦР ВГД количество',
  'Холестерин',
  'Триглицериды',
  'Anti-HBsAg титр',
  'АФП',
  'Альбумин',
  'Креатинин',
  'Мочевина',
  'Азот',
  'Витамин D',
  'Ферритин',
];
