# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

Классификация SQLite делает некоторые постоянные и повреждающие причины
retryable, а typed Drift mapping стирает часть некорректных сохранённых значений
до проверки предметных инвариантов. Задачи 6.1 и 6.2 пока нельзя считать
полностью подтверждёнными текущим инкрементом.

## Review target

- **Baseline:** configured `origin/main` @ `6b0e641c76fe0d4718514dc83b5b1f57f08f0c87`
- **Reviewed head:** `850184990e0864a1ca3ca52554b4e9f08494719b`
- **Target commits:** 3
- **Reviewable paths:** 11; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed

## Reviewed increment

### U1 · Безопасный публичный failure contract и классификация SQLite

- **Work items:** 6.1
- **Requirements and scenarios:** `Безопасное представление неизвестного отказа операции с намерением` · `Неизвестная причина отказа получения данных`, `Неизвестная причина отказа изменения`; `Безопасный bootstrap локального хранилища` · `Устранимая ошибка bootstrap`, `Неизвестная причина отказа bootstrap`, `Повреждённый SQLite-файл при bootstrap`
- **Affected boundary:** публичный результат операций с намерениями и внутренняя классификация причин отказа локального хранилища
- **Implementation target:** `lib/src/intention/application/intention_result.dart`, `lib/src/data/local/sqlite_failure_classifier.dart`, `lib/src/data/local/bootstrap/local_data_bootstrap.dart`, `test/intention/application/intention_contract_test.dart`, `test/data/local/sqlite_failure_classifier_test.dart`
- **Applicable constraints and non-goals:** `unexpected` должен оставаться отдельным non-retryable outcome; retry допустим только для доказанно временных причин; классификация опирается на машинные коды, а diagnostics не содержит текста, UUID, SQL, параметров или полного exception; command-specific conflict, каталог, UI и синхронизация не входят в unit

### U2 · Реактивное подробное чтение намерения из подтверждённого состояния

- **Work items:** 6.2
- **Requirements and scenarios:** `Каталог намерений и его охват` · `Просмотр активного намерения подробно`, `Просмотр архивированного намерения подробно`; `Состояния получения данных` · `Загрузка подробных данных`, `Намерение с корректным идентификатором отсутствует`, `Ошибка получения подробных данных`, `Восстановление подробных данных после повторной попытки`; `Безопасное представление неизвестного отказа операции с намерением` · `Неизвестная причина отказа получения данных`
- **Affected boundary:** `IntentionRepository.watchById` между постоянным состоянием намерения и доверенной предметной моделью
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`, `test/intention/data/drift_intention_repository_watch_test.dart`; совместно проверенные изменённые зависимости — `lib/src/intention/application/intention_result.dart`, `lib/src/data/local/sqlite_failure_classifier.dart`, `test/intention/application/intention_contract_test.dart`, `test/data/local/sqlite_failure_classifier_test.dart`
- **Applicable constraints and non-goals:** stream публикует только подтверждённый snapshot либо успешное отсутствие, после одного typed failure завершается, а retry создаёт новую подписку; storage-типы и пользовательские данные не пересекают публичную seam или diagnostics; каталог, commands, UI, синхронизация и владение заимствованной базой не входят в unit
- **Excluded change scope:** задачи 6.3–6.10 остаются будущей частью Phase 6 и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий изолированный reviewer проверил оба пересекающихся unit одним объединённым target из семи delivery/test paths и неизменяемым диапазоном `6b0e641c…850184990e` |
| OpenSpec conformance | Complete | полный граф артефактов и задачи 6.1–6.2 сопоставлены с кодом и тестами в обе стороны; JSON- и строгая OpenSpec-валидация успешны |
| Code quality | Complete | семь delivery/test paths и неизменённые caller, schema, generated mapping, diagnostics и dependency boundaries проверены по correctness, readability, architecture, security и performance; сфокусированные тесты и анализ успешны |

## Findings

### F1 · High — Широкие primary-коды ошибочно считаются доказанно временными

- **Evidence:** `lib/src/data/local/sqlite_failure_classifier.dart:29-39` классифицирует целые primary-семейства `SQLITE_CANTOPEN` и `SQLITE_IOERR` как `SqliteUnavailableFailure`, не учитывая уже доступный `extendedResultCode`. `test/data/local/sqlite_failure_classifier_test.dart:31-50` явно закрепляет `SQLITE_CANTOPEN_ISDIR` как retryable, хотя этот extended-код означает попытку открыть каталог как файл. В тех же primary-семействах находятся `SQLITE_IOERR_DATA` с неверной checksum страницы и `SQLITE_IOERR_CORRUPTFS` с признаком повреждённой файловой системы; их машинная семантика описана в официальном [справочнике SQLite](https://www.sqlite.org/rescode.html). Bootstrap и detail read затем отображают такой результат в retryable `unavailable` (`lib/src/data/local/bootstrap/local_data_bootstrap.dart:104-108`, `lib/src/intention/data/drift_intention_repository.dart:117-121`).
- **Impact:** постоянная ошибка пути или признак повреждения может получить ложный совет обычного retry и неверный diagnostics outcome; состояние данных представляется менее серьёзным и более устранимым, чем подтверждает машинный код.
- **Required outcome:** `unavailable` должен охватывать только машинные коды с доказанно временной семантикой; постоянные, повреждающие и неизвестные extended-причины должны сохранять корректное отличие от retryable недоступности на bootstrap и repository boundaries.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задачи 6.1 и 6.2; requirements `Безопасный bootstrap локального хранилища` и `Безопасное представление неизвестного отказа операции с намерением`; общий classifier, bootstrap mapping, detail-read mapping и их tests
- **Disposition:** Open

### F2 · Medium — Typed mapping стирает некорректные сохранённые значения до rehydration

- **Evidence:** `watchById` получает уже преобразованный `local.Intention` до вызова `_rehydrate` (`lib/src/intention/data/drift_intention_repository.dart:36-39`). Generated mapper читает readiness/archive как `bool`, а timestamps как `int` (`lib/src/data/local/app_database.g.dart:210-224`). В зафиксированном Drift 2.34.3 boolean mapping превращает любое ненулевое SQLite-значение в `true`, а integer mapping преобразует `double` через `toInt`; после этого `_rehydrate` доверяет boolean-значениям и строит timestamps (`lib/src/intention/data/drift_intention_repository.dart:82-100`). Тесты намеренно отключают `CHECK` для corrupt-row fixtures, но проверяют только нарушения текста и порядка времени, которые переживают typed mapping (`test/intention/data/drift_intention_repository_watch_test.dart:168-220`).
- **Impact:** например, сохранённое boolean-значение `2` может выйти как успешная готовность/архивность, а дробное значение timestamp — как усечённое предметное время вместо terminal `IntentionCorruptionFailure`. Публичная seam тем самым может подтвердить искажённую модель.
- **Required outcome:** граница чтения должна проверять сохранённые представления до потери некорректных состояний при coercion и завершать подписку typed corruption для каждого выявленного нарушения; regression evidence должно покрывать lossy boolean/timestamp cases.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задача 6.2; безопасная rehydration в design; `DriftIntentionRepository.watchById`, persistent row mapping и corrupt-row tests
- **Disposition:** Open

## Review coverage

Проверены все 11 reviewable paths диапазона: семь delivery/test paths входят в
U1–U2, а `design.md`, `plan.md`, `review.md` и `tasks.md` классифицированы как
planning evidence. Материальных несопоставленных путей нет. Дополнительно как
неизменённый контекст проверены публичный `IntentionRepository`, предметные
инварианты текста, identity и timestamps, schema/generated mapping,
`DiagnosticsSink`, primary-key query semantics и зафиксированное поведение
Drift/sqlite3.

Сфокусированный запуск пяти test files прошёл 41 тест; targeted Dart analysis и
полный `flutter analyze` завершились без ошибок. `openspec validate
manage-intentions --json`, строгая OpenSpec-валидация и `git diff --check` также
успешны. Полный test suite и Android build не запускались: критерии задач 6.1 и
6.2 требуют сфокусированные тесты и анализ, а change-wide build gate относится к
будущей задаче 6.10.
