/// Типы (профили) клиник для мульти-профильной платформы «Цадмир».
///
/// Тип задаёт: русскую подпись, подзаголовок в сайдбаре и ШАБЛОН включённых
/// модулей (функций). Платформенный админ выбирает тип при создании клиники —
/// приложение «подстраивается»: показывает подзаголовок специальности и только
/// включённые модули. Далее модули можно точечно включать/выключать на каждую
/// клинику (экран «Клиники»).
library;

/// Ключи модулей (функций) — совпадают с маршрутами навигации. По ним же
/// строится карта «модуль → пункт меню» в app_shell.
const String kModDashboard = 'dashboard';
const String kModReception = 'reception';
const String kModPatients = 'patients';
const String kModAnalyses = 'analyses';
const String kModFibroscan = 'fibroscan';
const String kModInventory = 'inventory';
const String kModPayments = 'payments';
const String kModAudit = 'audit';
const String kModCatalog = 'catalog';

/// Все модули, которыми можно управлять на уровне клиники (для редактора
/// тумблеров и валидации). Структурные разделы (Сотрудники, Клиники) сюда НЕ
/// входят — они гейтятся правами платформы/супера, а не модулями клиники.
const Map<String, String> kModuleLabels = <String, String>{
  kModDashboard: 'Дашборд',
  kModReception: 'Регистратура',
  kModPatients: 'Пациенты',
  kModAnalyses: 'Анализы',
  kModFibroscan: 'Фиброскан',
  kModInventory: 'Склад',
  kModPayments: 'Касса',
  kModAudit: 'Журнал',
  kModCatalog: 'Справочники',
};

/// Полный набор ключей модулей (порядок = порядок в редакторе).
const List<String> kAllModules = <String>[
  kModDashboard,
  kModReception,
  kModPatients,
  kModAnalyses,
  kModFibroscan,
  kModInventory,
  kModPayments,
  kModAudit,
  kModCatalog,
];

/// Профиль (тип) клиники.
class ClinicType {
  const ClinicType({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.modules,
  });

  /// Значение поля `type` в документе клиники.
  final String key;

  /// Подпись типа в выпадашке при создании.
  final String label;

  /// Подзаголовок под названием клиники в сайдбаре (специальность).
  final String subtitle;

  /// Модули (функции), включённые для этого типа по умолчанию.
  final Set<String> modules;
}

/// Все универсальные модули, кроме фиброскана (он профильный —
/// эластометрия печени, нужен гематологии/гепатологии).
const Set<String> _kUniversalModules = <String>{
  kModDashboard,
  kModReception,
  kModPatients,
  kModAnalyses,
  kModInventory,
  kModPayments,
  kModAudit,
  kModCatalog,
};

/// Каталог типов клиник. Фиброскан включён только там, где он клинически
/// уместен (гематология/общий). Любой модуль можно после создания включить или
/// выключить вручную на конкретную клинику.
const List<ClinicType> kClinicTypes = <ClinicType>[
  ClinicType(
    key: 'hematology',
    label: 'Гематология',
    subtitle: 'Гематологический центр',
    modules: <String>{..._kUniversalModules, kModFibroscan},
  ),
  ClinicType(
    key: 'ophthalmology',
    label: 'Офтальмология (глазная)',
    subtitle: 'Офтальмологический центр',
    modules: _kUniversalModules,
  ),
  ClinicType(
    key: 'ent',
    label: 'ЛОР',
    subtitle: 'ЛОР-центр',
    modules: _kUniversalModules,
  ),
  ClinicType(
    key: 'urology',
    label: 'Урология',
    subtitle: 'Урологический центр',
    modules: _kUniversalModules,
  ),
  ClinicType(
    key: 'gynecology',
    label: 'Гинекология (женская)',
    subtitle: 'Женская консультация',
    modules: _kUniversalModules,
  ),
  ClinicType(
    key: 'pediatric',
    label: 'Педиатрия (детская)',
    subtitle: 'Детская клиника',
    modules: _kUniversalModules,
  ),
  ClinicType(
    key: 'general',
    label: 'Общий профиль',
    subtitle: 'Медицинский центр',
    modules: <String>{..._kUniversalModules, kModFibroscan},
  ),
];

/// Тип по ключу (или гематология по умолчанию — как у клиники `default`,
/// заведённой до появления типов; так старые данные не «теряют» модули).
ClinicType clinicTypeFor(String? key) {
  for (final t in kClinicTypes) {
    if (t.key == key) return t;
  }
  return kClinicTypes.first; // hematology (все модули)
}
