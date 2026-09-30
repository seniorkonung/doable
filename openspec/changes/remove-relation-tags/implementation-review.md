# OpenSpec Implementation Review: remove-relation-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** В сохранённом диапазоне реализована вторая фаза. Текущая схема хранит назначения только намерениям, хранилище сведено к единственной версии схемы 1 без путей обновления, создание схемы атомарно, а навигация, фикстуры и проверки долговечности работают на этой схеме. Все десять задач 2.1–2.10 сопоставлены с проверенными единицами. Независимая оценка решений, соответствие OpenSpec и проверка качества завершены. Нерешённых замечаний нет. Исправление читаемости тестового литерала с ведущим U+FEFF ведёт незавершённая задача 2.11 в `tasks.md`. Принятых рисков нет.

## Review target

- **Baseline ref:** 786d39a16a613765c8e1983e749420c3032b4b2d
- **Base commit:** 786d39a16a613765c8e1983e749420c3032b4b2d
- **Reviewed head:** f959454e598d88fa60d2ff27869132c9da1bc3ac
- **Target commits:** ["fe4e9f3a05de1e97bfdbe3799d68c71e9f912508", "2c2f1764aa35228d2ff7453f68faea14615a4351", "c8b7ffa2bee9aecae658e0d28d01fb05e9c34a29", "e35df6d97a58bda92a5a8a2fc80425c3c488399e", "e20484a1f1b7b289f609abc26fec347ec456c3c1", "9845b3b853a3cb76b997f1b66d1b73182148fad5", "8011741f5c8c3de51253dd06627a5ae9079aeace", "d59c6525f52bdde39f2e7aa38cc35ad78a44cb87", "c44031cbbec24333cac3a41f109675623a27aeb2", "f959454e598d88fa60d2ff27869132c9da1bc3ac"]
- **Reviewable paths:** ["drift_schemas/drift_schema_v1.json", "drift_schemas/drift_schema_v2.json", "drift_schemas/drift_schema_v3.json", "drift_schemas/drift_schema_v4.json", "drift_schemas/drift_schema_v5.json", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/generated_schema.dart", "lib/src/data/local/migrations/migration_strategy.dart", "lib/src/data/local/schema/tag_schema.drift", "lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart", "lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart", "mise.toml", "openspec/changes/remove-relation-tags/tasks.md", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_graph_lifecycle_scenarios.dart", "test/data/local/app_database_schema_test.dart", "test/data/local/bootstrap/local_data_bootstrap_test.dart", "test/data/local/migrations/fault_injection_test.dart", "test/data/local/migrations/file_backed_migration_test.dart", "test/data/local/migrations/migration_test.dart", "test/data/local/tag_schema_test.dart", "test/graph/data/drift_tag_assignment_read_cost_test.dart", "test/graph/data/drift_tag_assignment_read_test.dart", "test/graph/data/drift_tag_assignment_test.dart", "test/graph/data/drift_tag_delete_test.dart", "test/graph/data/drift_tag_lifecycle_test.dart", "test/graph/data/drift_tagged_entities_read_cost_test.dart", "test/graph/data/drift_tagged_entities_read_test.dart", "test/graph/data/file_backed_graph_durability_test.dart", "test/graph/data/file_backed_tag_durability_test.dart", "test/graph/data/tag_delete_cost.dart", "test/graph/data/tag_lifecycle_integration_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/schema_v1_fixture.dart", "test/support/tag_storage_fixture.dart", "test/tag/presentation/assignments/tag_assignments_read_cost_widget_test.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/navigation/tag_navigation_read_cost_widget_test.dart", "tool/check_generated.sh"]
- **OpenSpec change:** remove-relation-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/remove-relation-tags/tasks.md"]

## Reviewed increment

### U1 · Схема только с назначениями намерениям и единственная версия хранилища

- **Work items:** ["18", "2.1", "19", "2.2", "20", "2.3", "21", "2.4", "25", "2.8", "26", "2.9", "27", "2.10"]
- **Requirements and scenarios:** ["tag-management: Локальное сохранение и миграция тегов", "tag-management: Прерванная миграция", "tag-management: Новая установка хранит назначения только намерениям", "tag-management: Хранилище с более новым маркером версии схемы не обновляется", "tag-management: Обновление графа без тегов", "tag-management: Независимые назначения тегов — Долговременная связь не получает собственный тег"]
- **Affected boundary:** Открытие и создание локального хранилища, текущая схема SQLite, стратегия миграций, диагностика открытия, путь записи назначений Drift-адаптера и цепочка генерации для разработчика.
- **Implementation target:** ["drift_schemas/drift_schema_v1.json", "drift_schemas/drift_schema_v2.json", "drift_schemas/drift_schema_v3.json", "drift_schemas/drift_schema_v4.json", "drift_schemas/drift_schema_v5.json", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/generated_schema.dart", "lib/src/data/local/migrations/migration_strategy.dart", "lib/src/data/local/schema/tag_schema.drift", "lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart", "mise.toml", "tool/check_generated.sh", "test/data/local/app_database_schema_test.dart", "test/data/local/bootstrap/local_data_bootstrap_test.dart", "test/data/local/migrations/fault_injection_test.dart", "test/data/local/migrations/file_backed_migration_test.dart", "test/data/local/migrations/migration_test.dart", "test/data/local/tag_schema_test.dart", "test/graph/data/file_backed_graph_durability_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/schema_v1_fixture.dart"]
- **Applicable constraints and non-goals:** По ADR-0002 изменения транзакционны, у версии схемы есть зафиксированный снимок, включён `PRAGMA foreign_keys = ON`, downgrade не выполняется, база не удаляется и не пересоздаётся автоматически. По ADR-0008 функции схемы остаются долговечным контрактом. `local-data-lifecycle` запрещает полный аудит при каждом открытии. Не входят в объём: перенос или удаление демонстрационных хранилищ версий 1–5, перенос тегов связи на участников и хранение истории назначений.
- **Excluded change scope:** Прикладные контракты, представления и локализации первой фазы уже проверены в предыдущем отчёте и в этом диапазоне не менялись.

### U2 · Навигация, общие фикстуры и долговечность на текущей схеме

- **Work items:** ["21", "2.4", "22", "2.5", "23", "2.6", "24", "2.7", "27", "2.10"]
- **Requirements and scenarios:** ["tag-management: Навигация по тегу между намерениями", "tag-management: Ограниченное получение и последовательный просмотр тегов", "tag-management: Явно подтверждаемое удаление тега", "tag-management: Актуальность идентичностей и атомарность назначений", "tag-management: Теги сохраняются после полного перезапуска", "tag-management: Удалённые данные не возвращаются", "tag-management: Архивированное действие остаётся допустимым получателем"]
- **Affected boundary:** Путь чтения навигации по тегу в Drift-адаптере `PersonalGraphRepository` и тесты, которые доказывают поведение тегов: общие фикстуры, проверки стоимости, долговечности, согласования представлений и потоков приложения.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_graph_lifecycle_scenarios.dart", "test/graph/data/drift_tag_assignment_read_cost_test.dart", "test/graph/data/drift_tag_assignment_read_test.dart", "test/graph/data/drift_tag_assignment_test.dart", "test/graph/data/drift_tag_delete_test.dart", "test/graph/data/drift_tag_lifecycle_test.dart", "test/graph/data/drift_tagged_entities_read_cost_test.dart", "test/graph/data/drift_tagged_entities_read_test.dart", "test/graph/data/file_backed_tag_durability_test.dart", "test/graph/data/tag_delete_cost.dart", "test/graph/data/tag_lifecycle_integration_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/support/tag_storage_fixture.dart", "test/tag/presentation/assignments/tag_assignments_read_cost_widget_test.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/navigation/tag_navigation_read_cost_widget_test.dart"]
- **Applicable constraints and non-goals:** По ADR-0013 каталог и назначения намерения читаются полными снимками, а навигация остаётся ограниченной. По ADR-0009 используются общая граница репозитория и общая ревизия, продолжение привязано к снимку. По ADR-0007 текст проверяется до успешной выдачи. Пределы стоимости сохраняются, а утверждения заменяются, а не удаляются. Не входят в объём: изменение самой схемы, порядка чтения и границ модулей.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Единицы U1 и U2 не пересекаются по путям. Каждую проверял отдельный свежий reviewer по `implementation-decision-review`. Он получал только нейтральный brief, корень репозитория, точные base/head и полный список путей своей единицы: 22 пути для U1 и 19 для U2. Оба сообщили полное покрытие без существенных замечаний. Reviewer U1 прочитал все 22 пути, сверил поведение `onUpgrade` с исходниками drift 2.34.3 и запустил восемь своих тестовых файлов: 108 прошли. Reviewer U2 прочитал все 19 путей, проверил сохранение объёма посторонней нагрузки и формул стоимости и запустил 249 тестов: все прошли. Ни одному reviewer не передавались артефакты планирования, история коммитов или отчёт. |
| OpenSpec conformance | Complete | Proposal, три delta-spec, design, adr, plan и tasks прочитаны в reviewed head; рабочая копия чиста, и её HEAD совпадает с reviewed head. `mise exec --no-deps -- openspec validate remove-relation-tags --type change --strict --json` успешна. `mise run check` в этой рабочей копии: форматирование (414 файлов без изменений), проверка CI scope и `flutter analyze` прошли; `flutter test --concurrency=2` дал 2528 успешных тестов и один отказ. Отказ — порог задержки p95 106 мс при лимите 100 мс в `test/intention/data/drift_intention_repository_large_fixture_test.dart`: этот файл и `lib/src/intention` в диапазоне не менялись, прогон шёл одновременно с тестами reviewer. Два отдельных повторных запуска файла прошли. `mise run codegen-check` успешна, рабочая копия после неё чиста. Поиск в reviewed head не нашёл ссылок на снимки 2–5, `generated_schema`, `schema steps` и фикстуры `createSchemaV` вне архивных изменений и ADR. |
| Code quality | Complete | Проверены все 41 delivery- и test-путь по корректности, читаемости, архитектуре, безопасности и производительности. Отдельно рассмотрены: ограничения `tag_assignments` без получателя-связи; сохранение ссылки шага дневного пути на связь; атомарность `onCreate` и `runAtomicMigration`; классификация маркеров выше и ниже текущего; неизменность файла при несовместимости; диагностика без пользовательских данных; аудит ссылок навигации; планы запросов; объём заменённой посторонней нагрузки; файловые сценарии перезапуска и остановки процесса. Исправление читаемости тестового литерала с ведущим U+FEFF отслеживается задачей 2.11. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Объект ревью — только `786d39a16a613765c8e1983e749420c3032b4b2d..f959454e598d88fa60d2ff27869132c9da1bc3ac` изменения `remove-relation-tags`. Все десять целевых коммитов проверены по смежным task ranges и по итоговому diff. Каждый коммит отмечает выполненной ровно свою задачу в `tasks.md`; идентификаторы, номера, описания и порядок задач 18/2.1 … 27/2.10 сохранены. Предыдущий отчёт покрывал диапазон первой фазы, не содержал нерешённых замечаний и принятых рисков, поэтому переносить нечего.

Инвентаризация: 42 пути. 41 путь продуктового кода, производных, конфигурации генерации и тестов распределён между U1 (22) и U2 (19) без пересечений. `tasks.md` — свидетельство планирования. Несопоставленных путей нет.

Задача 18, номер 2.1 (U1, `786d39a1..fe4e9f3a`). `tag_schema.drift` делает `intention_id` обязательной ссылкой на `intentions` и удаляет `long_term_relation_id`, его внешний ключ, уникальность, оба индекса и ограничение выбора получателя. Триггер неизменяемости идентичности больше не упоминает связь. `currentSchemaVersion` равен 1. `drift_schema_v1.json` перегенерирован, снимки 2–5 удалены, запись в `drift_personal_graph_repository_tag_commands.dart` передаёт обязательный `intentionId`. `tag_schema_test.dart` и `app_database_schema_test.dart` проверяют отсутствие объектов связи, обязательную ссылку, уникальность пары и сохранность ссылки шага дневного пути.

Задача 19, номер 2.2 (U1, `fe4e9f3a..2c2f1764`). Переходы 1→5 и `generated_schema.dart` удалены, команда `schema steps` убрана из `mise.toml` и `tool/check_generated.sh`. `onUpgrade` возвращает несовместимость для маркера выше текущего и повреждение для остальных. Тесты подтверждают это для следующей версии, для маркера -1 и для маркеров 2–5 на файле с побайтовой сверкой без изменений.

Задача 20, номер 2.3 (U1, `2c2f1764..c8b7ffa2`). Внедрённые отказы, остановка отдельного процесса до и после commit и сценарий bootstrap показывают: создание не оставляет частичной схемы и маркера, файл сохраняется, хранилище не предоставляется до commit, следующий запуск создаёт схему заново.

Задача 21, номер 2.4 (U1 и U2, `c8b7ffa2..e35df6d9`). `schema_v1_fixture.dart` и проверки переходов удалены. Проверки долговечности графа и тегов, сверка полного контракта схемы с новой установкой, строк графа, назначений и счётчика последовательности после повторного открытия переведены на текущую схему.

Задача 22, номер 2.5 (U2, `e35df6d9..e20484a1`). Основной запрос и аудит ссылок навигации больше не обращаются к удалённому столбцу. Аудит по-прежнему отклоняет отсутствующее намерение, недопустимый признак архива и недопустимые кодировки. Проверки непредставимых состояний заменены проверкой ограничений схемы. В `lib/` не осталось запросов к `tag_assignments` с `long_term_relation_id`.

Задача 23, номер 2.6 (U2, `e20484a1..9845b3b8`). Фикстуры записывают только назначения намерениям. Посторонняя нагрузка заменена назначениями других тегов и противоположного охвата. Число строк `tag_assignments` не уменьшилось: для удаления широко назначенного тега оно выросло с 2401 до 4801. Пределы и формулы стоимости сохранены.

Задача 24, номер 2.7 (U2, `9845b3b8..8011741f`). В `file_backed_tag_durability_test.dart` добавлена цепочка с перезапусками: пустой каталог, назначение архивированному действию и активному намерению, повтор, чтение, навигация, снятие, сохранение тега без назначений и повторное назначение, с проверками `integrity_check` и `foreign_key_check`.

Задача 25, номер 2.8 (U1, `8011741f..d59c6525`). Комментарии `tag_schema.drift` и `app_database.dart` описывают тег как метку намерения и единственную версию схемы. Действующих описаний прежних версий в репозитории не осталось.

Задача 26, номер 2.9 (U1, `d59c6525..c44031cb`). `fault_injection_test.dart` проверяет версии, длительность и категорию отказа для создания и несовместимого маркера. Проверяется, что события и сообщения не содержат тестовых пользовательских данных, отказ получателя диагностики не меняет исход, а повторное открытие не выполняет аудит тегов и назначений. `diagnostics_sink_test.dart` приведён к переходу 0→1.

Задача 27, номер 2.10 (U1 и U2, `c44031cb..f959454e`). Контрольная точка опирается на повторно выполненные в этой сессии `mise run check`, `mise run codegen-check` и строгую OpenSpec-валидацию; результаты и единственный отказ по времени описаны в таблице проходов. Запущенного приложения для hot reload не было.

Промежуточные коммиты между `fe4e9f3a` и `e20484a1` содержали SQL навигации, ссылавшийся на удалённый столбец. Итоговое состояние это исправляет, поэтому отдельным замечанием это не считается.
