import 'package:freezed_annotation/freezed_annotation.dart';

part 'fibroscan_record.freezed.dart';
part 'fibroscan_record.g.dart';

/// Запись исследования на фиброскане (эластография печени). Минимальный набор
/// полей под учёт: дата · ФИО · год рождения · диагноз. Денежная/клиническая
/// логика тут не ведётся — это простой журнал исследований.
@freezed
abstract class FibroscanRecord with _$FibroscanRecord {
  const factory FibroscanRecord({
    required String id,
    // Пациент из базы (если исследование привязано к карте); журнал допускает и
    // разовые записи без карты — тогда patientId отсутствует, а ФИО вводится вручную.
    String? patientId,
    required String fullName,
    // Год рождения (только год — дата рождения целиком в этом журнале не нужна).
    required int birthYear,
    // Дата исследования. Хранится строкой в ISO-формате `YYYY-MM-DD` (как во
    // всех коллекциях); на экран выводится как ДД.ММ.ГГГГ.
    required String date,
    // Диагноз из справочника [kFibroscanDiagnoses].
    required String diagnosis,
  }) = _FibroscanRecord;

  factory FibroscanRecord.fromJson(Map<String, dynamic> json) =>
      _$FibroscanRecordFromJson(json);
}

/// Справочник диагнозов фиброскана — РОВНО эти шесть кодов (гепатиты и жировая/
/// неалкогольная болезнь печени). Используется выпадающим списком формы.
const List<String> kFibroscanDiagnoses = <String>[
  'ВГВ', // вирусный гепатит B
  'ВГС', // вирусный гепатит C
  'ВГД', // вирусный гепатит D
  'ВГА', // вирусный гепатит A
  'ЖГ', // жировой гепатоз
  'НГ', // неалкогольный гепатоз
];
