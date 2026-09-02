# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

Остаются два low-severity замечания о production test hook и границе
несопоставленного изменения агентской политики.

## Review target

- **Baseline:** recorded `origin/main` @ `186b8815c4d35760da05476914220ff6c09404f1`
- **Reviewed head:** `9eb803822545536e937bae8c160afbbf2724a95d`
- **Target commits:** 7
- **Reviewable paths:** 14; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Recorded local tracking state; no fetch performed

## Reviewed increment

### U1 · Атомарное первичное создание локальной схемы

- **Work items:** 5.1
- **Requirements and scenarios:** `Создание и версионирование локального хранилища` · `Прерывание создания нового локального хранилища`
- **Affected boundary:** bootstrap и первичное создание постоянного локального хранилища
- **Implementation target:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/bootstrap/local_data_bootstrap.dart`, `lib/src/data/local/migrations/migration_strategy.dart`, `test/data/local/migrations/file_backed_migration_test.dart`, `test/support/local_database_harness.dart`
- **Applicable constraints and non-goals:** подтверждение структуры, проверок целостности и marker версии должно быть атомарным; автоматическое удаление или пересоздание данных запрещено; repository, UI и синхронизация не входят в инкремент
- **Excluded change scope:** задачи 5.4 и последующие фазы не входят в этот инкремент

### U2 · Разделение corruption и временной недоступности

- **Work items:** 5.2
- **Requirements and scenarios:** `Безопасный bootstrap локального хранилища` · `Устранимая ошибка bootstrap`, `Повреждённый SQLite-файл при bootstrap`
- **Affected boundary:** результат bootstrap, владение неготовым executor и безопасная диагностика
- **Implementation target:** `lib/src/data/local/bootstrap/local_data_bootstrap.dart`, `pubspec.yaml`, `pubspec.lock`, `test/data/local/bootstrap/local_data_bootstrap_test.dart`
- **Applicable constraints and non-goals:** классификация опирается на машинный код, а не текст; диагностика не раскрывает пользовательские данные или полный exception; автоматическое destructive recovery запрещено

### U3 · Ограниченная стоимость обычного bootstrap

- **Work items:** 5.3
- **Requirements and scenarios:** `Безопасный bootstrap локального хранилища` · `Обычное открытие текущей схемы не выполняет полный аудит данных`
- **Affected boundary:** готовность текущей схемы и целостность поискового индекса
- **Implementation target:** `lib/src/data/local/migrations/migration_strategy.dart`, `test/data/local/file_backed_database_test.dart`
- **Applicable constraints and non-goals:** обычное открытие не сканирует все записи или индекс; полный audit остаётся обязательным до commit первичного создания и затрагивающих FTS миграций; search semantics и repository не входят в инкремент

### U4 · Буквальная граница FTS5 phrase для фильтра названия

- **Work items:** 5.4; `openspec/changes/manage-intentions/tasks.md` отмечает задачу выполненной
- **Requirements and scenarios:** `Фильтрация каталога по названию`; буквальная регистронезависимая подстрока, сохранение внутренних пробелов и различие Unicode-букв и диакритики
- **Affected boundary:** внутренний ввод фильтра названия из будущего локального repository adapter в SQLite search
- **Implementation target:** `lib/src/data/local/fts_query.dart`, `test/data/local/fts_consistency_test.dart`
- **Applicable constraints and non-goals:** пользовательский фильтр не изменяет SQL или FTS-грамматику; ключи короче трёх Unicode-кодовых точек используют параметризованный `instr`; production repository, каталог и UI не входят в инкремент
- **Excluded change scope:** задачи 5.5–5.7 и последующие repository/UI-фазы не проверялись

## Unmapped range

- **Unmatched target paths:** `.apm/instructions/dart-mcp.instructions.md` и `AGENTS.md` изменяют инструкции агентам и не относятся к результатам U1–U4

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежие изолированные reviewers проверили девять delivery paths U1–U3 и два delivery paths U4 на соответствующих неизменяемых границах |
| OpenSpec conformance | Complete | полный граф артефактов и задачи 5.1–5.4 сопоставлены с обоими инкрементами в обе стороны; строгая валидация вершины U1–U3 и JSON-валидация вершины U4 успешны |
| Code quality | Complete | одиннадцать delivery paths и затронутые runtime, dependency, schema и caller boundaries проверены по correctness, readability, architecture, security и performance; verification evidence для обоих инкрементов раскрыт в Review coverage |

## Findings

### F3 · Low — Тестовая точка отказа стала частью production API и транзакции

- **Evidence:** `InitialSchemaObjectCreated` проведён через конструкторы `LocalDataBootstrap` (`local_data_bootstrap.dart:11`–`30`) и `AppDatabase` (`app_database.dart:10`–`28`), а `migration_strategy.dart:40`–`43` вызывает произвольный async callback после каждого schema object внутри атомарной транзакции. В исходящем диапазоне callback используется только для `_InjectedInitialCreationFailure` в `test/data/local/migrations/file_backed_migration_test.dart:13`–`25`.
- **Impact:** production boundary зависит от внутренней гранулярности Drift-схемы и допускает callback, способный задержать или сорвать инициализацию и выполнить внешние побочные эффекты, которые SQLite rollback не отменяет и следующая попытка повторит. Это расширение не нужно результату bootstrap и усложняет его контракт ради одного теста.
- **Required outcome:** fault injection должна доказывать атомарность, не расширяя production bootstrap contract тестовой детализированной точкой и не допуская внешних побочных эффектов внутри migration transaction.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задача 5.1; `app_database.dart`; `local_data_bootstrap.dart`; `migration_strategy.dart`; migration tests
- **Disposition:** Open

### F4 · Low — В диапазон включено несопоставленное изменение агентской политики

- **Evidence:** `.apm/instructions/dart-mcp.instructions.md` меняет обязательный порядок инициализации Dart MCP roots, а сгенерированный `AGENTS.md` распространяет эту политику на весь репозиторий. Эти пути не реализуют и не проверяют результаты U1–U3 и не имеют соответствующего work item или requirement в `manage-intentions`.
- **Impact:** одно исходящее изменение связывает storage remediation с независимой политикой инженерной автоматизации. Её корректность и откат нельзя обосновать артефактами выбранного OpenSpec change, а повторное ревью storage-range вынуждено нести несвязанную governance-конфигурацию.
- **Required outcome:** изменение агентской политики должно получить отдельную прослеживаемую границу ревью либо явный отдельный источник намерения, не смешанный с implementation increment `manage-intentions`.
- **Earliest source of truth:** separate change
- **Affected artifacts:** `.apm/instructions/dart-mcp.instructions.md`; `AGENTS.md`
- **Disposition:** Open

## Review coverage

Проверены все 14 reviewable paths объединённого диапазона: одиннадцать delivery
paths входят в U1–U4, `tasks.md` служит planning evidence, а два agent-policy
path раскрыты как unmatched. Покрыты production paths bootstrap/migration,
file-backed и in-memory evidence, атомарность DDL, SQLite primary/extended
codes, Android background-isolate executor, lifecycle ресурсов, безопасная
диагностика, FTS5 phrase escaping, SQL parameterization, trigram substring
semantics, короткий fallback и граница будущего repository caller.

На вершине U1–U3 `flutter test` прошёл 79 тестов; `flutter analyze`, строгая
OpenSpec-валидация и `git diff --check` также были успешны. На вершине U4
целевой Flutter-тест прошёл 5 сценариев; `flutter analyze`, целевой Dart-анализ,
`git diff --check` и OpenSpec JSON-валидация завершились без замечаний. Активного
Flutter/DTD-приложения не обнаружено, поэтому hot reload не выполнялся. Полный
test suite и build после U4 не запускались, поскольку они относятся к отдельной
задаче 5.7 и выходят за запрошенный review.
