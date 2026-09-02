# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

Bootstrap не сохраняет надёжную типизированную причину отказа сквозь реальные executor paths и допускает хранилище по совпадению одних имён schema objects, поэтому recovery policy и готовность данных могут быть ошибочными.

## Review target

- **Upstream:** `origin/main` @ `186b8815c4d35760da05476914220ff6c09404f1`
- **Reviewed head:** `1e3a9d563b6bb900996360cf8627067f74e5a2db`
- **Outgoing commits:** 5
- **Reviewable paths:** 12; `implementation-review.md` исключён
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Upstream freshness:** локальное tracking-состояние; `fetch` не выполнялся
- **Excluded worktree state:** незакоммиченные изменения `openspec/changes/manage-intentions/tasks.md`, `test/data/local/fts_consistency_test.dart` и `lib/src/data/local/fts_query.dart` исключены

## Reviewed increment

### U1 · Атомарное первичное создание локальной схемы

- **Work items:** 5.1
- **Requirements and scenarios:** `Создание и версионирование локального хранилища` · `Прерывание создания нового локального хранилища`
- **Affected boundary:** bootstrap и первичное создание постоянного локального хранилища
- **Implementation target:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/bootstrap/local_data_bootstrap.dart`, `lib/src/data/local/migrations/migration_strategy.dart`, `test/data/local/migrations/file_backed_migration_test.dart`, `test/support/local_database_harness.dart`
- **Applicable constraints and non-goals:** подтверждение структуры, проверок целостности и marker версии должно быть атомарным; автоматическое удаление или пересоздание данных запрещено; repository, UI и синхронизация не входят в инкремент
- **Excluded change scope:** задачи 5.4 и последующие фазы не входят в исходящий диапазон

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

## Unmapped range

- **Planning evidence:** `openspec/changes/manage-intentions/tasks.md` отмечает выполненными 5.1–5.3
- **Unmatched outgoing paths:** `.apm/instructions/dart-mcp.instructions.md` и `AGENTS.md` изменяют инструкции агентам и не относятся к результатам U1–U3

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий изолированный reviewer проверил общий девятипутевой target U1–U3 без planning context |
| OpenSpec conformance | Complete | полный граф артефактов сопоставлен с 5.1–5.3 в обе стороны; текущая JSON-валидация и строгая валидация immutable head успешны; обнаруженные проблемы отражены в F1–F2 |
| Code quality | Complete | девять delivery paths и затронутые runtime/dependency boundaries проверены по correctness, readability, architecture, security и performance; `flutter test` (79 tests) и `flutter analyze` на immutable head успешны |

## Findings

### F1 · High — Классификация SQLite-ошибок не работает сквозь реальные bootstrap paths

- **Evidence:** в immutable head `lib/src/data/local/migrations/migration_strategy.dart:134`–`159` `_verifyStoredSchema` выполняет `PRAGMA user_version` и чтение `sqlite_schema`, после чего преобразует любой `Object`, кроме уже типизированного corruption, в `CorruptLocalDataSchemaException`. `lib/src/data/local/bootstrap/local_data_bootstrap.dart:92`–`103` перехватывает этот тип раньше общего классификатора строк `125`–`131`, поэтому исходный `SqliteException` с `BUSY`, `LOCKED` или `IOERR` до классификатора не доходит. В обратном направлении неизменённый production context `lib/src/data/local/database_connection.dart:23`–`24` использует `driftDatabase`; зафиксированный `drift_flutter` 0.3.1 создаёт background `DatabaseConnection`, а Drift 2.34.3 возвращает ошибку удалённого executor как `DriftRemoteException` с `remoteCause`. Классификатор строк `125`–`131` проверяет только непосредственный `SqliteException` и не распознаёт этот production wrapper. Тесты строк `176`–`296` используют in-process `NativeDatabase`, а retryable matrix выбрасывает исключение из `setup` до `_verifyStoredSchema`, поэтому ни verification-query path, ни production background-isolate path не покрыты.
- **Impact:** временная блокировка или ошибка ввода-вывода при чтении marker/структуры может быть показана как повреждение без повторной попытки, а реальный `CORRUPT`/`NOTADB` из Android production executor — как временная недоступность с ложным retry. В обоих случаях caller получает противоположную recovery policy и не может надёжно защитить доступ к сохранённым данным.
- **Required outcome:** типизированная причина должна сохраняться и единообразно классифицироваться на всём in-process и production background-isolate bootstrap path: `CORRUPT`/`NOTADB` дают corruption, доказанно временные opening/verification failures остаются retryable, а неизвестная причина получает явно определённую безопасную policy. Проверки должны воспроизводить ошибки непосредственно во время bounded schema verification и через executor того же isolate-типа, который использует production connection.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задача 5.2; requirement `Безопасный bootstrap локального хранилища`; `local_data_bootstrap.dart`; `migration_strategy.dart`; bootstrap tests
- **Decision needed:** определить caller-visible policy для неизвестного детерминированного отказа: отдельный non-retryable/unexpected outcome либо осознанно сохранённый catch-all retry с явным обоснованием остаточного риска
- **Disposition:** Open

### F2 · High — Проверка совместимости подтверждает имена, но не структуру схемы

- **Evidence:** `lib/src/data/local/migrations/migration_strategy.dart:134`–`154` сравнивает `user_version`, затем выбирает из `sqlite_schema` только `name` для строк с типом `table`, `index` или `trigger` и применяет `containsAll`. Тип конкретного имени, SQL-определение, обязательные колонки и constraints таблицы, FTS5-конфигурация, тела triggers и поля/предикаты indexes не проверяются. Поэтому файл с marker версии 1 и теми же именами, но несовместимыми определениями проходит `beforeOpen`; `AppDatabase.open` строк `30`–`35` проверяет после этого только `foreign_keys`.
- **Impact:** bootstrap может вернуть ready для структурно несовместимого хранилища. Последующие feature queries способны завершаться ошибками или работать против неверных constraints/triggers/indexes; в частности, повреждённая FTS-конфигурация может молча перестать поддерживать согласованность поискового индекса.
- **Required outcome:** обычное открытие должно за время, ограниченное размером схемы, подтверждать все compatibility-critical свойства таблиц, virtual tables, triggers и indexes, не просматривая пользовательские строки и полный поисковый индекс.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** задача 5.3; requirement `Безопасный bootstrap локального хранилища`; `migration_strategy.dart`; file-backed bootstrap tests
- **Disposition:** Open

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

Проверены immutable production paths bootstrap/migration, file-backed и in-memory evidence, атомарность DDL, ограниченный обычный bootstrap, явный FTS audit, SQLite primary/extended codes, Android background-isolate executor, lifecycle ресурсов, безопасная диагностика и direct-dependency boundary. Все 12 исходящих путей классифицированы: девять входят в delivery units, `tasks.md` служит planning evidence, два agent-policy path раскрыты как unmatched. Полный `flutter test`, `flutter analyze`, строгая OpenSpec-валидация и `git diff --check` выполнены на `1e3a9d563b6bb900996360cf8627067f74e5a2db`; Android build относится к не включённой задаче 5.5. Незакоммиченное состояние не входит в выводы.
