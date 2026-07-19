import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fibroscan_record.freezed.dart';
part 'fibroscan_record.g.dart';

/// Запись исследования на фиброскане (эластография печени). Учётный минимум —
/// дата · ФИО · год рождения · диагноз — дополнен измерениями прибора:
/// LSM (жёсткость печени, кПа) и CAP (контролируемый параметр затухания, дБ/м).
/// По ним экран выводит стадию фиброза (F0..F4) и степень стеатоза (S0..S3)
/// через справочник референсов (`fibroscan_refs`). Денежная логика тут не
/// ведётся — это журнал исследований.
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
    // LSM — жёсткость печени (Liver Stiffness Measurement), кПа. По нему через
    // [stageForLsm] выводится стадия фиброза. Необязателен (старые записи и
    // разовый учёт могут его не содержать).
    num? lsm,
    // CAP — контролируемый параметр затухания (дБ/м). По нему через
    // [gradeForCap] выводится степень стеатоза. Необязателен.
    num? cap,
    // IQR/Med (%) — межквартильный размах, нормированный на медиану LSM; мера
    // надёжности измерения жёсткости. Клинически валидным сканом печени обычно
    // считают IQR/Med ≤ 30%. Необязателен (старые/разовые записи без него).
    num? iqrMed,
    // Число валидных измерений (обычно прибор набирает 10). Косвенно отражает
    // качество серии. Необязателен.
    int? validMeasurements,
    // Когда запись создана (`created_at` из Firestore). Только для отображения в
    // детальном просмотре — на запись не влияет (штампует репозиторий).
    @FibroTimestampConverter() DateTime? createdAt,
  }) = _FibroscanRecord;

  factory FibroscanRecord.fromJson(Map<String, dynamic> json) =>
      _$FibroscanRecordFromJson(json);
}

/// Конвертер Firestore `Timestamp` ⇄ [DateTime] для полей-штампов времени.
///
/// Коллекция пишет `created_at` серверным временем (`Timestamp`), а
/// json_serializable сам его не разберёт — этот конвертер приводит `Timestamp`
/// (а также `DateTime`/ISO-строку/миллисекунды на всякий случай) к [DateTime].
/// `toJson` возвращает ISO-строку, но фактически не используется: репозиторий
/// пишет документы вручную, а не через `toJson`.
class FibroTimestampConverter implements JsonConverter<DateTime?, Object?> {
  const FibroTimestampConverter();

  @override
  DateTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is Timestamp) return json.toDate();
    if (json is DateTime) return json;
    if (json is int) return DateTime.fromMillisecondsSinceEpoch(json);
    if (json is String) return DateTime.tryParse(json);
    return null;
  }

  @override
  Object? toJson(DateTime? object) => object?.toIso8601String();
}

/// Порог надёжности измерения LSM по IQR/Med (%). Валидным сканом печени
/// клинически считают серию с IQR/Med ≤ 30%. Хранится здесь, чтобы экран и
/// PDF-заключение использовали один порог.
const num kFibroIqrMedReliableMax = 30;

/// Признак надёжного измерения LSM по IQR/Med (%): `true` при `iqr <= 30`.
bool isFibroIqrReliable(num iqrMed) => iqrMed <= kFibroIqrMedReliableMax;

/// Текстовая метка надёжности по IQR/Med (%): «надёжно» при ≤ 30 %, иначе
/// «низкая надёжность».
String fibroReliabilityLabel(num iqrMed) =>
    isFibroIqrReliable(iqrMed) ? 'надёжно' : 'низкая надёжность';

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
