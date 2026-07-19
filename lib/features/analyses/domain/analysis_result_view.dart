import '../../analysis_types/domain/analysis_type.dart';

/// Помощники отображения результата анализа поверх справочника видов
/// ([AnalysisType]). Чистый Dart (без Flutter) — используется и экраном, и
/// построителем PDF.
///
/// Флаг отклонения НЕ хранится в записи ([AnalysisRecord] не имеет поля-флага):
/// он вычисляется на лету из привязанного вида анализа (единица + референс),
/// поэтому смена границ в справочнике сразу отражается на старых записях и не
/// требует миграции данных / регенерации freezed.

/// Находит вид анализа в справочнике по названию (без учёта регистра и крайних
/// пробелов). Возвращает `null`, если вид не найден (запись по «свободному»/
/// легаси-типу вне справочника).
AnalysisType? findAnalysisType(List<AnalysisType> types, String? name) {
  final needle = name?.trim().toLowerCase() ?? '';
  if (needle.isEmpty) return null;
  for (final t in types) {
    if (t.name.trim().toLowerCase() == needle) return t;
  }
  return null;
}

/// Разбирает строковый результат в число (запятая = десятичный разделитель).
/// `null`, если результат пуст или не число.
num? parseResultNum(String? result) {
  final t = result?.trim().replaceAll(',', '.');
  if (t == null || t.isEmpty) return null;
  return num.tryParse(t);
}

/// Флаг отклонения количественного результата: «норма» / «выше нормы» /
/// «ниже нормы». Пусто, если вид не количественный, не найден, результат не
/// число или референс не задан.
String resultFlag(String? result, AnalysisType? type) {
  if (type == null || !type.isQuantitative) return '';
  final value = parseResultNum(result);
  if (value == null) return '';
  return classify(value, type.refLow, type.refHigh);
}

/// Результат вместе с единицей измерения для отображения: «42 Ед/л».
/// Единица добавляется только для количественного вида. Пустой результат → ''.
String resultWithUnit(String? result, AnalysisType? type) {
  final r = result?.trim() ?? '';
  if (r.isEmpty) return '';
  final unit = _unitOf(type);
  return unit.isEmpty ? r : '$r $unit';
}

/// Референсный диапазон для отображения: «10–40 Ед/л», «≥ 10», «≤ 40» или ''.
/// Только для количественного вида с заданными границами.
String referenceRange(AnalysisType? type) {
  if (type == null || !type.isQuantitative) return '';
  final low = type.refLow;
  final high = type.refHigh;
  final unit = _unitOf(type);
  String core;
  if (low != null && high != null) {
    core = '${_fmtNum(low)}–${_fmtNum(high)}';
  } else if (low != null) {
    core = '≥ ${_fmtNum(low)}';
  } else if (high != null) {
    core = '≤ ${_fmtNum(high)}';
  } else {
    return '';
  }
  return unit.isEmpty ? core : '$core $unit';
}

String _unitOf(AnalysisType? type) =>
    (type != null && type.isQuantitative) ? (type.unit ?? '').trim() : '';

/// Число без «.0» у целых значений (40.0 → «40», 3.5 → «3.5»).
String _fmtNum(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();
