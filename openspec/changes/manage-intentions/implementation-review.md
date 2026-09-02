# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

Каталог может молча выдать семантически несогласованный результат из допустимой
для текущей schema строки, а cursor одного экземпляра Drift adapter принимается
другим логическим каталогом с теми же параметрами запроса.

## Review target

- **Baseline:** configured `origin/main` @ `db00120577a2ed96f1adc808cc5964f762cd4141`
- **Reviewed head:** `4853c22347a2476529fd54655aa4f3eb133c7ee8`
- **Target commits:** 2
- **Reviewable paths:** 3; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed

## Reviewed increment

### U1 · Ограниченная первая страница каталога

- **Work items:** 6.3
- **Requirements and scenarios:** `Каталог намерений и его охват` · `Сводные данные намерения в каталоге`; `Фильтрация каталога по названию` · все допустимые варианты фильтра; `Ограниченная выдача и автоматическая подгрузка каталога` · `Ограниченная первая порция`; `Точное количество совпадений каталога` · `Количество больше загруженной порции`, `Количество после изменения фильтра`; `Упорядочивание каталогов намерений` · четыре порядка и детерминированный tie-breaker
- **Affected boundary:** вызывающая сторона каталога и постоянный `IntentionRepository`
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`, `test/intention/data/drift_intention_catalog_test.dart`
- **Applicable constraints and non-goals:** первая порция и точный count должны принадлежать одному SQLite snapshot; чтение ограничено `pageSize + 1`, не использует offset и не материализует полный description; фильтр остаётся буквальным и параметризованным через `LocalIntentionTitleSearch`; UI, command paths, large-fixture performance budget и синхронизация не входят в unit

### U2 · Opaque keyset-продолжения каталога

- **Work items:** 6.4
- **Requirements and scenarios:** `Ограниченная выдача и автоматическая подгрузка каталога` · `Последовательность порций`, `Конец выдачи`; `Упорядочивание каталогов намерений` · `Детерминированный порядок при одинаковом времени между порциями`
- **Affected boundary:** вызывающая сторона каталога, opaque continuation state и постоянный `IntentionRepository`
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`, `test/intention/data/drift_intention_catalog_test.dart`
- **Applicable constraints and non-goals:** cursor связывает один логический каталог, нормализованные scope/filter/order и value boundary из выбранного UTC timestamp и `IntentionId`; continuation не повторяет count, не зависит от существования boundary row и отклоняет чужой или несовместимый cursor до storage query; UI-prefetch, согласование command results, command paths и performance qualification не входят в unit
- **Excluded change scope:** задачи 6.5–6.14 остаются будущей частью Phase 6 и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий изолированный reviewer проверил U1 и U2 одним overlap-target из двух delivery/test paths в точном диапазоне `db001205…4853c223`; planning-артефакты и прежний отчёт ему не раскрывались |
| OpenSpec conformance | Complete | полный граф артефактов и задачи 6.3–6.4 сопоставлены с delivery-кодом и тестами в обе стороны; targeted и полная test suite, Dart analysis и JSON-валидация OpenSpec успешны |
| Code quality | Complete | полный delivery-path subset и неизменённые repository contract, domain identity/order, schema, FTS, diagnostics и SQLite boundaries проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

### F1 · Medium — Каталог доверяет несогласованным производным storage-полям

- **Evidence:** `lib/src/intention/data/drift_intention_repository.dart:123`–`170` и `:173`–`214` вычисляют membership/count через `title_search_key`/FTS и проецируют `hasDescription` как `description IS NOT NULL`, но не читают эти исходные значения для проверки; `_rehydrateSummary` в `:271`–`314` проверяет только название, UUID и timestamps. При этом `lib/src/data/local/schema/intention_schema.drift:1`–`20` требует от `title` и `title_search_key` лишь независимую непустоту и допускает пустое либо полностью пробельное ненулевое description, а подробная rehydration в `drift_intention_repository.dart:330`–`345` уже классифицирует те же расхождения как corruption.
- **Impact:** schema-valid, но семантически повреждённая строка может войти в count/выдачу для фильтра, которого нет в показанном названии, либо исчезнуть из корректного фильтра; пробельное description будет показано как существующее. Вместо typed corruption каталог возвращает внутренне противоречивый успешный snapshot.
- **Required outcome:** membership, точный count и признаки summary должны опираться на storage-представления, согласованность которых с каноническими предметными значениями гарантирована либо проверяется с typed corruption outcome, сохраняя ограниченную materialization без полного description.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** task 6.3; requirements `Фильтрация каталога по названию` и `Каталог намерений и его охват`; catalog rehydration, schema/search-key boundary и repository tests
- **Disposition:** Open

### F2 · Medium — Cursor не связан с выдавшим его логическим каталогом

- **Evidence:** `lib/src/intention/data/drift_intention_repository.dart:38`–`60` принимает любой `_DriftIntentionCatalogCursor`, если `matches` успешен. Cursor в `:316`–`328` и `:377`–`395` хранит scope, filter, order, timestamp и ID, а `matches` сравнивает только первые три параметра; identity repository/database отсутствует. Поэтому cursor, выданный одним публично создаваемым `DriftIntentionRepository`, проходит проверку в другом экземпляре того же класса с иной базой. Тест `test/intention/data/drift_intention_catalog_test.dart:465`–`534` проверяет только другой runtime-тип cursor и несовпадающие параметры, но не тот же adapter type с другим логическим каталогом.
- **Impact:** continuation во второй базе начинает чтение от value boundary первой базы, может пропустить начальную часть второго каталога или вернуть пустую страницу и не выполняет требуемый validation failure до storage access.
- **Required outcome:** до storage query continuation должен подтверждать принадлежность cursor тому же логическому постоянному каталогу и тем же нормализованным параметрам, сохраняя value-boundary semantics независимо от существования граничной строки.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** design cursor semantics; task 6.4; repository cursor ownership/validation и catalog tests
- **Disposition:** Open

## Review coverage

Все три reviewable path классифицированы: два delivery/test path образуют
пересекающиеся U1–U2, а `openspec/changes/manage-intentions/tasks.md` является
planning evidence; материальных несопоставленных путей нет. Проверены первая read
transaction, общий predicate count/rows, три scope, четыре порядка, компактная
summary projection, короткая и FTS-ветви, SQL limits, keyset predicates,
cursor provenance/mismatch, удалённая boundary row, typed failures и безопасные
diagnostics.

`flutter test test/intention/data/drift_intention_catalog_test.dart
test/data/local/fts_consistency_test.dart` прошёл 12 тестов; полный `flutter test`
прошёл 107 тестов. Targeted Dart analysis и полный `flutter analyze` завершились
без ошибок. `openspec validate manage-intentions --json` и `git diff --check`
успешны. Android build не запускался: задачи 6.3–6.4 не меняют platform delivery
и требуют repository/FTS tests, а change-wide build gate относится к будущей
проверочной задаче.
