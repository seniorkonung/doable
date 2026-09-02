# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

Bootstrap не сохраняет надёжную типизированную причину отказа сквозь реальные
executor paths и допускает хранилище по совпадению одних имён schema objects.
Кроме того, публичная граница FTS-helper допускает короткий валидный фильтр, для
которого trigram `MATCH` молча возвращает пустой результат вместо выбора
параметризованного `instr`-пути.

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
- **Excluded change scope:** задача 5.5 и последующие repository/UI-фазы не проверялись

## Unmapped range

- **Unmatched target paths:** `.apm/instructions/dart-mcp.instructions.md` и `AGENTS.md` изменяют инструкции агентам и не относятся к результатам U1–U4

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежие изолированные reviewers проверили девять delivery paths U1–U3 и два delivery paths U4 на соответствующих неизменяемых границах; для U4 установлен F5 |
| OpenSpec conformance | Complete | полный граф артефактов и задачи 5.1–5.4 сопоставлены с обоими инкрементами в обе стороны; строгая валидация вершины U1–U3 и JSON-валидация вершины U4 успешны; проблемы отражены в F1–F2 |
| Code quality | Complete | одиннадцать delivery paths и затронутые runtime, dependency, schema и caller boundaries проверены по correctness, readability, architecture, security и performance; verification evidence для обоих инкрементов раскрыт в Review coverage |

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

### F5 · Medium — Применимость trigram FTS не закреплена в публичной границе

- **Evidence:** `lib/src/data/local/fts_query.dart:4` принимает любой `String` и только экранирует кавычки перед созданием `Variable<String>`. Trigram FTS5 не возвращает совпадений для полнотекстового запроса короче трёх Unicode-кодовых точек, что прямо оговорено в [официальной документации SQLite](https://www.sqlite.org/fts5.html#the_trigram_tokenizer). `test/data/local/fts_consistency_test.dart:57`–`59` проверяет `к` и `ко` через отдельный приватный `_findByShortSearchKey`, а не через общую границу, выбирающую его вместо FTS-helper; все новые FTS-fixtures имеют не меньше трёх кодовых точек.
- **Impact:** будущий repository caller может передать в экспортируемый helper валидный короткий фильтр. SQL останется безопасным, но `MATCH` молча вернёт пустую выдачу вместо буквального подстрочного совпадения; компилятор и API не обнаружат неверный выбор пути.
- **Required outcome:** локальная поисковая граница или её типы должны гарантировать буквальную подстрочную семантику для каждого валидного фильтра, включая значения короче трёх Unicode-кодовых точек, и не позволять направить их в trigram `MATCH` только по дисциплине caller.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задача 5.4; раздел design о буквальной FTS phrase и коротком `instr`-пути; `fts_query.dart`; `fts_consistency_test.dart`
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
задаче 5.5 и выходят за запрошенный review.
