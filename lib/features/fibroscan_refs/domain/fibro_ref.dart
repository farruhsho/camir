/// Справочник референсных диапазонов фиброскана (эластографии печени).
///
/// Две группы порогов ([kFibroKindFibrosis] / [kFibroKindSteatosis]):
///  • фиброз — стадия по LSM (жёсткость печени, kPa) → F0..F4;
///  • стеатоз — степень по CAP (контролируемый параметр затухания, dB/m) → S0..S3.
///
/// Простой immutable-класс с [fromMap]/[toMap] под коллекцию Firestore
/// `fibroscan_refs` (ключи документа — snake_case, без бэкенда/Dio).
library;

/// Значения поля `kind` в документе.
const String kFibroKindFibrosis = 'fibrosis';
const String kFibroKindSteatosis = 'steatosis';

/// Один референсный «бэнд» (диапазон) фиброскана.
///
/// Диапазон полуоткрытый — `[min, max)` — совпадает с логикой [stageForLsm] /
/// [gradeForCap]: `min <= v < max`. Открытый край задаётся `null`
/// (`min == null` → «−∞», `max == null` → «+∞»).
class FibroRef {
  const FibroRef({
    required this.id,
    required this.kind,
    required this.label,
    this.min,
    this.max,
    this.note,
  });

  /// Id документа Firestore (пустой у ещё не сохранённого/дефолтного бэнда).
  final String id;

  /// [kFibroKindFibrosis] (LSM, kPa) или [kFibroKindSteatosis] (CAP, dB/m).
  final String kind;

  /// Подпись стадии/степени: `F0-F1`..`F4` для фиброза, `S0`..`S3` для стеатоза.
  final String label;

  /// Нижняя граница диапазона включительно (`null` → открыт слева, «−∞»).
  final num? min;

  /// Верхняя граница диапазона исключительно (`null` → открыт справа, «+∞»).
  final num? max;

  /// Необязательная клиническая заметка к бэнду.
  final String? note;

  /// Единица измерения группы: `kPa` для фиброза, `dB/m` для стеатоза.
  String get unitLabel => kind == kFibroKindSteatosis ? 'dB/m' : 'kPa';

  factory FibroRef.fromMap(Map<String, dynamic> map) {
    num? readNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    String? str(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return FibroRef(
      id: map['id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? kFibroKindFibrosis,
      label: map['label']?.toString() ?? '',
      min: readNum(map['min']),
      max: readNum(map['max']),
      note: str(map['note']),
    );
  }

  /// Поля документа (без `id`/служебных штампов — их ставит репозиторий).
  /// `min`/`max` пишутся как есть, включая `null` для открытых краёв.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'kind': kind,
    'label': label,
    'min': min,
    'max': max,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  FibroRef copyWith({
    String? id,
    String? kind,
    String? label,
    num? min,
    num? max,
    String? note,
  }) => FibroRef(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    min: min ?? this.min,
    max: max ?? this.max,
    note: note ?? this.note,
  );
}

/// Стадия ФИБРОЗА по жёсткости печени [kPa] (LSM). Возвращает подпись
/// подходящего бэнда фиброза (`min <= kPa < max`) или пустую строку, если ни
/// один диапазон не подошёл.
String stageForLsm(num kPa, List<FibroRef> refs) =>
    _matchBand(kPa, refs, kFibroKindFibrosis);

/// Степень СТЕАТОЗА по CAP [dB/m]. Возвращает подпись подходящего бэнда
/// стеатоза (`min <= cap < max`) или пустую строку, если ни один не подошёл.
String gradeForCap(num cap, List<FibroRef> refs) =>
    _matchBand(cap, refs, kFibroKindSteatosis);

/// Ищет бэнд нужной группы, чей полуоткрытый диапазон `[min, max)` накрывает
/// [value]. Если в переданном списке нет бэндов этой группы (пусто/чужой
/// список) — подстраховываемся стандартными порогами [kDefaultFibroRefs].
String _matchBand(num value, List<FibroRef> refs, String kind) {
  final pool = refs.any((r) => r.kind == kind) ? refs : kDefaultFibroRefs;
  for (final r in pool) {
    if (r.kind != kind) continue;
    final lo = r.min;
    final hi = r.max;
    final okLo = lo == null || value >= lo;
    final okHi = hi == null || value < hi;
    if (okLo && okHi) return r.label;
  }
  return '';
}

/// Стандартные (сид) клинические пороги фиброскана.
///
/// ВАЖНО: это ПОРОГИ ПО УМОЛЧАНИЮ и они РЕДАКТИРУЕМЫ под протокол/прибор — их
/// правят на экране «Референсы фиброскана» (см. presentation), а коллекция
/// `fibroscan_refs` при наличии данных перекрывает эти значения. Используются
/// только когда коллекция пуста.
///
/// Диапазоны полуоткрытые `[min, max)` (как в [_matchBand]). Границы подобраны
/// так, чтобы для целочисленных измерений совпадать с клиническими диапазонами:
///  • Фиброз по LSM (kPa), вирусные гепатиты / общая популяция:
///    F0-F1 < 7.0 · F2 7.0–9.5 · F3 9.5–12.5 · F4 > 12.5
///  • Стеатоз по CAP (dB/m):
///    S0 < 238 · S1 238–259 · S2 260–292 · S3 ≥ 293 (> 292)
const List<FibroRef> kDefaultFibroRefs = <FibroRef>[
  // Фиброз (LSM, kPa) — стадии F0..F4.
  FibroRef(
    id: '',
    kind: kFibroKindFibrosis,
    label: 'F0-F1',
    max: 7.0,
    note: 'Норма / минимальный фиброз',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindFibrosis,
    label: 'F2',
    min: 7.0,
    max: 9.5,
    note: 'Умеренный фиброз',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindFibrosis,
    label: 'F3',
    min: 9.5,
    max: 12.5,
    note: 'Выраженный фиброз',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindFibrosis,
    label: 'F4',
    min: 12.5,
    note: 'Цирроз',
  ),
  // Стеатоз (CAP, dB/m) — степени S0..S3. Верхние границы исключительны:
  // S1 [238,260) = 238–259, S2 [260,293) = 260–292, S3 [293,∞) = ≥293 (>292).
  FibroRef(
    id: '',
    kind: kFibroKindSteatosis,
    label: 'S0',
    max: 238,
    note: 'Нет значимого стеатоза',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindSteatosis,
    label: 'S1',
    min: 238,
    max: 260,
    note: 'Лёгкий стеатоз',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindSteatosis,
    label: 'S2',
    min: 260,
    max: 293,
    note: 'Умеренный стеатоз',
  ),
  FibroRef(
    id: '',
    kind: kFibroKindSteatosis,
    label: 'S3',
    min: 293,
    note: 'Выраженный стеатоз',
  ),
];
