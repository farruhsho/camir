# Цадмир — контракт сборки (Phase 2)

Единый источник правды для параллельных агентов. Каждый агент владеет своим
набором файлов и НЕ трогает чужие. Общие интерфейсы ниже — их сигнатуры менять
нельзя, только добавлять новое по контракту.

## Стек / соглашения
- Flutter + Riverpod + go_router + freezed. Бэкенд — только Firebase (Firestore
  + Auth). Никакого своего сервера.
- Ключи документов Firestore — **snake_case** (`last_name`, `patient_id`,
  `created_at`).
- Дата события хранится как **ISO `YYYY-MM-DD`** во ВСЕХ коллекциях; на экран
  выводится как `ДД.ММ.ГГГГ` (хелперы `_displayDate` уже есть на экранах).
- Каждая запись при создании штампуется `created_by`, при изменении —
  `updated_by` + `updated_at`:
  ```dart
  'created_by': FirebaseAuth.instance.currentUser?.uid,
  // update:
  'updated_by': FirebaseAuth.instance.currentUser?.uid,
  'updated_at': FieldValue.serverTimestamp(),
  ```
- Все catch-блоки экранов и error-ветки прогоняют ошибку через
  `friendlyError(e)` из `lib/core/utils/error_messages.dart` (уже создан).
- Не запускать `build_runner`/`flutter analyze` — оркестратор прогонит один
  общий проход. Если меняли поля freezed-модели — укажите `regenNeeded: true`.
- `dart format` на изменённых файлах — можно и нужно.

## Права (role_catalog.dart — владелец: агент A)
Коды прав: `patients.read/create/update`, `visits.create/read/update`,
`analyses.read/write`, `fibroscan.read/write`, `inventory.read/manage/write_off`,
`audit.read`, `dashboard.view`. Роль **Ресепшен** уже держит их все; **Супер-админ**
— `isSuperuser` (всё). Эти коды используются и в firestore.rules, и в навигации.

## Общие интерфейсы (сигнатуры фиксированы контрактом)

### `friendlyError(Object? e) -> String`  (создан, `lib/core/utils/error_messages.dart`)

### PatientsRepository (владелец: агент B) — добавить/сохранить
```dart
Future<Page<Patient>> list({String? q, int limit = 200});     // сохранить сигнатуру; починить, чтобы поиск НЕ ограничивался только свежими N
Future<Patient?> findByPhone(String phone);                    // НОВОЕ: точный матч по нормализованному +996… (для дедупа)
Future<Patient> create({... как сейчас ...});                  // сохранить сигнатуру; штамповать created_by
Future<Patient> update(String id, {... как сейчас ...});       // штамповать updated_by/updated_at
```

### AnalysesRepository (владелец: агент C) — добавить/сохранить
```dart
Future<List<AnalysisRecord>> list({String? q, int limit = 200});
Future<List<AnalysisRecord>> listForPatient(String patientId, {String? fullName}); // НОВОЕ: where('patient_id'==id); при fullName — ещё и записи БЕЗ patient_id с точным ФИО
Future<AnalysisRecord> create({... как сейчас ...});           // created_by
Future<AnalysisRecord> update(String id, {String? result, String? analysisType, String? date, ...}); // НОВОЕ: дозаполнить результат/исправить
Future<void> delete(String id);                                // НОВОЕ
```

### FibroscanRepository (владелец: агент D) — добавить/сохранить
```dart
Future<List<FibroscanRecord>> list({String? q, int limit = 200});
Future<List<FibroscanRecord>> listForPatient(String patientId, {String? fullName}); // НОВОЕ (как у анализов)
Future<FibroscanRecord> create({String? patientId, required String fullName, required int birthYear, required String date, required String diagnosis}); // patientId ТЕПЕРЬ пишется; date хранить ISO
Future<FibroscanRecord> update(String id, {...}); // НОВОЕ
Future<void> delete(String id);                    // НОВОЕ
```

### Visit (НОВОЕ, владелец: агент G) — коллекция `visits`
Поля: `patient_id, mrn, patient_name, birth_year, phone, referral,
status, queue_number, day (YYYY-MM-DD), note, created_by,
created_at, called_at, completed_at, cancelled_at`.
Статусы: `waiting` → `in_progress` → `completed`; `waiting`→`cancelled`;
`in_progress`→`waiting`; `cancelled`→`waiting`. Терминальный: `completed`.
`queue_number` — посуточный счётчик `counters/queue-YYYY-MM-DD` в транзакции.
Регистратура: `findByPhone` → предложить существующую карту, иначе создать
пациента, затем создать Visit(waiting).

## Владение файлами (диспозиция)
- **A** security/auth/config: `firestore.rules`, `firestore.indexes.json`(new),
  `firebase.json`, `.gitignore`, `lib/core/auth/role_catalog.dart`,
  `lib/features/auth/**`, `lib/main.dart`, `android/app/build.gradle.kts`.
- **B** patients: `lib/features/patients/**`.
- **C** analyses: `lib/features/analyses/**`.
- **D** fibroscan: `lib/features/fibroscan/**`.
- **E** inventory: `lib/features/inventory/**`.
- **F** shared/polish: `lib/core/widgets/async_value_widget.dart`,
  `lib/app/theme.dart`, `lib/core/theme/**`, `README.md`, `test/widget_test.dart`.
- **G** visits/nav: `lib/features/visits/**`(new), `lib/features/reception/**`,
  `lib/app/router.dart`, `lib/core/widgets/app_shell.dart`.
