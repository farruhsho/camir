/// Вид результата анализа.
///
/// `qualitative` — качественный (выбор из [AnalysisType.options], например
/// «положительно / отрицательно / сомнительно»); `quantitative` —
/// количественный (числовое значение с единицей [AnalysisType.unit] и
/// референсными границами [AnalysisType.refLow]/[AnalysisType.refHigh]).
const String kResultQualitative = 'qualitative';
const String kResultQuantitative = 'quantitative';

/// Значение вида результата → русская подпись (для выпадашек и карточек).
const Map<String, String> kResultTypeLabels = <String, String>{
  kResultQualitative: 'Качественный',
  kResultQuantitative: 'Количественный',
};

/// Варианты качественного результата по умолчанию (подставляются при создании
/// нового качественного типа — сотрудник может их отредактировать).
const List<String> kDefaultQualitativeOptions = <String>[
  'положительно',
  'отрицательно',
  'сомнительно',
];

/// Справочная запись «вид анализа» гематологического центра «Цадмир».
///
/// Простой immutable-класс с [fromMap]/[toMap] под коллекцию Firestore
/// `analysis_types` — без Dio/бэкенда. Ключи документа хранятся в snake_case
/// (`result_type`, `ref_low`, `ref_high`). Задаёт, как модуль «Анализы» вводит и
/// интерпретирует результат: качественный (выбор из [options]) или
/// количественный (число + [unit] и референс [refLow]…[refHigh]).
class AnalysisType {
  const AnalysisType({
    required this.id,
    required this.name,
    required this.resultType,
    this.options = const <String>[],
    this.unit,
    this.refLow,
    this.refHigh,
    this.active = true,
  });

  final String id;

  /// Название вида анализа (ОАК, АЛТ, HBSAg маркер …).
  final String name;

  /// [kResultQualitative] или [kResultQuantitative].
  final String resultType;

  /// Варианты ответа для качественного типа (для количественного — пустой).
  final List<String> options;

  /// Единица измерения количественного результата (Ед/л, ммоль/л …). `null`,
  /// если не задана или тип качественный.
  final String? unit;

  /// Нижняя/верхняя граница нормы (референс) для количественного результата.
  /// `null`, если не заданы — тогда [classify] вернёт пустую строку.
  final num? refLow;
  final num? refHigh;

  /// Активен ли вид в справочнике (неактивные не предлагаются при вводе).
  final bool active;

  /// Тип количественный (число + единица + референс).
  bool get isQuantitative => resultType == kResultQuantitative;

  /// Тип качественный (выбор из [options]).
  bool get isQualitative => resultType == kResultQualitative;

  /// Русская подпись вида результата.
  String get resultTypeLabel => kResultTypeLabels[resultType] ?? resultType;

  factory AnalysisType.fromMap(Map<String, dynamic> map) {
    num? readNum(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v.trim().replaceAll(',', '.'));
      return null;
    }

    List<String> readOptions(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      return const <String>[];
    }

    bool readBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true';
      return true; // по умолчанию активен (в т.ч. для старых документов)
    }

    String? str(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    // Нормализуем вид результата: неизвестное значение трактуем как
    // количественный (безопасный дефолт — просто число без вариантов).
    final rawType = map['result_type']?.toString();
    final resultType = (rawType == kResultQualitative)
        ? kResultQualitative
        : kResultQuantitative;

    return AnalysisType(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      resultType: resultType,
      options: readOptions(map['options']),
      unit: str(map['unit']),
      refLow: readNum(map['ref_low']),
      refHigh: readNum(map['ref_high']),
      active: readBool(map['active']),
    );
  }

  /// Поля для записи в Firestore (без `id` и служебных штампов — их ставит
  /// репозиторий). Пустые/`null` необязательные поля опускаются.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'name': name.trim(),
    'result_type': resultType,
    'options': options,
    if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
    if (refLow != null) 'ref_low': refLow,
    if (refHigh != null) 'ref_high': refHigh,
    'active': active,
  };
}

/// Классифицирует количественный результат относительно референсных границ.
///
/// Возвращает «ниже нормы», если [value] < [refLow]; «выше нормы», если
/// [value] > [refHigh]; «норма», если значение в пределах (или задана лишь одна
/// граница и она не нарушена); пустую строку `""`, если границы не заданы вовсе
/// (обе `null`) — тогда классифицировать не по чему.
String classify(num value, num? refLow, num? refHigh) {
  if (refLow == null && refHigh == null) return '';
  if (refLow != null && value < refLow) return 'ниже нормы';
  if (refHigh != null && value > refHigh) return 'выше нормы';
  return 'норма';
}
