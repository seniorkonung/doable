# OpenSpec Implementation Review: manage-tags

## Assessment

**Format version:** 1
**Result:** Incomplete
**Coverage status:** Incomplete
**Coverage limitations:** Штатный mise run --skip-tools check завершился с двумя таймаутами в параллельном тесте файловой долговечности тегов (схемы 0 и 1), поэтому этот обязательный проверочный шаг не подтверждён. Изолированный запуск файла и полный последовательный набор прошли. Причина параллельных таймаутов не установлена; связь с изменениями диапазона не доказана. Сборка APK из прежнего диапазона не повторялась: она не является проверкой задач 2.27–2.29.
**Summary:** Активных замечаний нет; исправление выбора тега вне загруженных порций отслеживается незавершённой задачей 2.30. Обязательный параллельный проверочный шаг остаётся неподтверждённым. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 8ba8d8515d8461130124adbb83fca9fc9e1b4b39
- **Base commit:** 8ba8d8515d8461130124adbb83fca9fc9e1b4b39
- **Reviewed head:** 55396b8317742caec88e680417dd15cbc4348a00
- **Target commits:** ["cd20122435d0b4312a1acf0b704851fb2586e915", "8c5943d3ff772b2823b276df922a926018d199fa", "ef30b07531090c42da2d2254890824e97cc84c3e", "cc88bd2739ff34f22162ea199c2c11bb7574c1aa", "55396b8317742caec88e680417dd15cbc4348a00"]
- **Reviewable paths:** ["drift_schemas/drift_schema_v5.json", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/generated_schema.dart", "lib/src/data/local/migrations/migration_strategy.dart", "lib/src/data/local/schema/tag_schema.drift", "lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "openspec/changes/manage-tags/evidence/assignment-order-read-cost.jsonl", "openspec/changes/manage-tags/evidence/assignment-order-read-cost.md", "openspec/changes/manage-tags/evidence/assignment-reference-check-cost.jsonl", "openspec/changes/manage-tags/evidence/assignment-reference-check-cost.md", "openspec/changes/manage-tags/tasks.md", "test/data/local/migrations/file_backed_migration_test.dart", "test/data/local/migrations/migration_test.dart", "test/data/local/tag_schema_test.dart", "test/graph/data/drift_tag_assignment_read_cost_test.dart", "test/graph/data/drift_tag_assignment_read_test.dart", "test/support/schema_v1_fixture.dart", "test/support/tag_storage_fixture.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **OpenSpec change:** manage-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-tags/evidence/assignment-order-read-cost.jsonl", "openspec/changes/manage-tags/evidence/assignment-order-read-cost.md", "openspec/changes/manage-tags/evidence/assignment-reference-check-cost.jsonl", "openspec/changes/manage-tags/evidence/assignment-reference-check-cost.md", "openspec/changes/manage-tags/tasks.md"]

## Reviewed increment

### U1 · Ограниченное чтение и устойчивый порядок назначений

- **Work items:** ["2.27", "2.28"]
- **Requirements and scenarios:** ["Ограниченное получение и последовательный просмотр тегов", "Локальное сохранение и миграция тегов", "Отказ при повреждённой ссылке за границей порции", "Согласованное продолжение после изменения хранилища"]
- **Affected boundary:** Чтение назначений намерения и долговременной связи, контракт SQLite, файловое обновление схемы и производительность последовательного просмотра.
- **Implementation target:** ["drift_schemas/drift_schema_v5.json", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/generated_schema.dart", "lib/src/data/local/migrations/migration_strategy.dart", "lib/src/data/local/schema/tag_schema.drift", "lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "test/data/local/migrations/file_backed_migration_test.dart", "test/data/local/migrations/migration_test.dart", "test/data/local/tag_schema_test.dart", "test/graph/data/drift_tag_assignment_read_cost_test.dart", "test/graph/data/drift_tag_assignment_read_test.dart", "test/support/schema_v1_fixture.dart", "test/support/tag_storage_fixture.dart"]
- **Applicable constraints and non-goals:** Оба вида получателя, прежний порядок тегов, полное обнаружение отсутствующей ссылки и атомарное обновление существующей базы обязательны. Переход к сущностям по тегу относится к следующей фазе.

### U2 · Достоверное назначение выбранного тега

- **Work items:** ["2.29"]
- **Requirements and scenarios:** ["Каталог тегов и выбор для назначения", "Подтверждённые изменения и согласованные представления тегов", "Ограниченное получение и последовательный просмотр тегов"]
- **Affected boundary:** Выбор тега для намерения или долговременной связи в каталоге, состояние модели и доступность действия назначения.
- **Implementation target:** ["lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Уже назначенный тег не отправляется повторно; свободный тег остаётся доступным для явного назначения без загрузки всего каталога. Создание тега само по себе не назначает его получателю.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два изолированных рецензента проверили точный диапазон и все 14 путей U1 и пять путей U2; по U2 подтверждено F1. Рецензенты не запускали тесты. |
| OpenSpec conformance | Incomplete | На чистом 55396b8317742caec88e680417dd15cbc4348a00 прошли strict OpenSpec validate, 98 целевых тестов чтения, схемы, миграций и каталога, flutter analyze, восемь изолированных тестов файловой долговечности и полный последовательный набор из 1843 тестов. Штатный mise run --skip-tools check: 1841 успешная проверка и два таймаута при параллельном запуске; проверочный шаг остаётся неподтверждённым. Сопоставление задач и сценариев выполнено. |
| Code quality | Complete | Проверены 19 путей реализации и тестов, включая сгенерированную схему, миграцию, курсоры чтения, состояние выбора, прямые SQL-записи и отказ при повреждённых ссылках. Сопоставлены планы и счётчики стоимости; git diff --check и flutter analyze прошли. |

## Findings

No findings confirmed; review incomplete.

## Review coverage

Все пять коммитов и 24 изменённых пути учтены. cd20122435d0b4312a1acf0b704851fb2586e915 и 8c5943d3ff772b2823b276df922a926018d199fa относятся к U1/2.27; ef30b07531090c42da2d2254890824e97cc84c3e и cc88bd2739ff34f22162ea199c2c11bb7574c1aa — к U1/2.28; 55396b8317742caec88e680417dd15cbc4348a00 — к U2/2.29. Четыре файла измерений и tasks.md являются свидетельствами планирования, остальные 19 путей покрыты U1 и U2. Прежний отчёт не содержал активных замечаний или принятых рисков. Рабочее дерево до записи отчёта было чистым. Параллельный и последовательный прогоны использовали записанный head; проверка APK прежнего диапазона здесь не выполнялась.
