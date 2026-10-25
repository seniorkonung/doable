# OpenSpec Implementation Review: add-intention-picker-sorting-and-purpose

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Фаза 1 в целом выполнена. Порядок по названию одинаков в SQL, курсоре и согласовании правок: везде используется сохранённая поисковая проекция и сравнение по кодовым точкам. Условие «только без готовности» и числа обоих типов из одного подсчёта работают в адаптере и в модели каталога. Схема 6 стала базовой. Каталог графа по-прежнему предлагает только четыре порядка по времени. Активных находок нет. Незавершённая задача 1.11 в `tasks.md` переносит производный запрос «без условия готовности» в контракт запроса; её реализация в проверенный диапазон не входит. Остаётся в силе принятый при ревью планирования риск AR1: индексы порядка по названию для архивного охвата пока никто не читает.

## Review target

- **Baseline ref:** 74436d1b99a47b9554b00b95add882eccd794249
- **Base commit:** 74436d1b99a47b9554b00b95add882eccd794249
- **Reviewed head:** 38cd39baf4b7979ab433974a66b2cfa02f96fed4
- **Target commits:** ["25ce67555675a9b4413e2e0a29d1a5749d707ab8", "1f7c8084ce3e195ecf1934c80c8c07b80695bf32", "613ade1b3c5a52daab479bdac0f415f03b9edcf6", "2713091677b9a04da19019fe62af0ef28aef5625", "61f5f7a7f496e67300e20425c116c120feb9d96e", "e2f4db3347a2e4e99b2add76206f5cdabe614e9e", "ce8d808c3ad4484a50a5bb6405b24ffc797e3e87", "2c94ce7a9c48074a59bda3f83e9a25a8a915113a", "d2109de5ea976ceb40d2e82f953148e45cbcd91c", "f26fa9d767572a53233c2760cc38b9eb86cc0d7d", "38cd39baf4b7979ab433974a66b2cfa02f96fed4"]
- **Reviewable paths:** ["README.md", "benchmark/intention/intention_catalog_benchmark.dart", "drift_schemas/drift_schema_v6.json", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/migration_strategy.dart", "lib/src/data/local/schema/intention_schema.drift", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/stored_graph_rows.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md", "test/app/intention_app_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart", "test/data/local/bootstrap/local_data_bootstrap_test.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/data/drift_intention_repository_command_test.dart", "test/intention/data/drift_intention_repository_fault_test.dart", "test/intention/data/drift_intention_repository_large_fixture_test.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/intention/presentation/picker/intention_picker_row_test.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/intention_title_order_key.dart", "test/support/intention_type_counts.dart", "test/support/tag_assignment_changed.dart", "test/tag/application/tag_command_contract_test.dart", "test/tag/presentation/assignments/tag_assignments_view_model_test.dart"]
- **OpenSpec change:** add-intention-picker-sorting-and-purpose
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed

## Reviewed increment

### U1 · Чтение каталога знает тип «без готовности», порядок по названию и числа типов

- **Work items:** ["1.1", "1.2", "1.3", "1.5", "1.9"]
- **Requirements and scenarios:** ["intention-management: Упорядочивание каталогов намерений", "intention-management: Тип намерения в поиске для выбора / Тип «Намерения» исключает действия", "intention-management: точное количество совместного поиска (числа типов)", "design: решения 1, 2, 3 (диагностика)", "ADR-0045"]
- **Affected boundary:** Контракт чтения порций `PersonalGraphRepository` (запрос, сводка, курсор, первая порция) и его адаптер Drift/SQLite, событие диагностики чтения порции, бенчмарк каталога.
- **Implementation target:** ["lib/src/intention/application/intention_catalog.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/stored_graph_rows.dart", "lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "benchmark/intention/intention_catalog_benchmark.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/data/drift_intention_repository_command_test.dart", "test/intention/data/drift_intention_repository_fault_test.dart", "test/intention/data/drift_intention_repository_large_fixture_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/intention_title_order_key.dart", "test/support/tag_assignment_changed.dart", "test/app/intention_app_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/intention/presentation/picker/intention_picker_row_test.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/tag/application/tag_command_contract_test.dart", "test/tag/presentation/assignments/tag_assignments_view_model_test.dart"]
- **Applicable constraints and non-goals:** Поисковые ключи и SQL не выходят за границу модуля графа (ADR-0009). Порции ограничены, количество точное (ADR-0005, ADR-0009). Функция поискового ключа — долговечный контракт с допустимым дрейфом (ADR-0008). Время измеряется только в бенчмарках. Каталог графа не получает порядок по названию и не меняет вид. Языковая сортировка в изменение не входит.

### U2 · Новое хранилище создаётся базовой схемой 6 с индексами порядка по названию

- **Work items:** ["1.4"]
- **Requirements and scenarios:** ["local-data-lifecycle: Создание и версионирование локального хранилища", "local-data-lifecycle: Безопасный bootstrap локального хранилища", "design: решение 3, Migration Plan", "proposal: BREAKING — схема 6 без пути обновления"]
- **Affected boundary:** Bootstrap локального хранилища, снимок схемы Drift и инструкция владельца данных в README.
- **Implementation target:** ["lib/src/data/local/schema/intention_schema.drift", "lib/src/data/local/app_database.dart", "lib/src/data/local/app_database.g.dart", "lib/src/data/local/migrations/migration_strategy.dart", "drift_schemas/drift_schema_v6.json", "README.md", "test/data/local/bootstrap/local_data_bootstrap_test.dart"]
- **Applicable constraints and non-goals:** Владелец решил сделать схему 6 базовой без миграции: production-установок нет, данные переносятся экспортом, очисткой и импортом. Индексы архивного охвата закладываются по решению владельца (AR1). Миграция данных схемы 5 в изменение не входит.

### U3 · Модель каталога ведёт тип намерения, точные числа типов и порядок по названию при правках

- **Work items:** ["1.6", "1.7", "1.8"]
- **Requirements and scenarios:** ["intention-management: Тип намерения в поиске для выбора", "intention-management: Упорядочивание каталогов намерений (согласование правок)", "daily-choice-management: закреплённый тип поиска действия (уровень модели)", "design: решение 2 (модель, правки графа), решение 1 (compare)"]
- **Affected boundary:** `IntentionCatalogViewModel` и его состояние, которыми пользуются три поиска и каталог графа. Тестовые адаптеры, которые отдают первые порции поискам.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/details/details_test_support.dart", "test/support/intention_type_counts.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart"]
- **Applicable constraints and non-goals:** Правки согласуются по снимкам до и после и по ревизии (ADR-0009). Параметры принадлежат экземпляру страницы (ADR-0028). Протокол ревизий и поздних порций не меняется. Вид поисков (заголовок, лист «Показать и упорядочить») относится к фазе 2.
- **Excluded change scope:** Фазы 2–4: заголовок списка, листы, подзаголовок назначения, графический язык путей и связей.

### U4 · Подтверждение готовности фазы 1

- **Work items:** ["1.10"]
- **Requirements and scenarios:** ["plan.md: Phase 1 «Ready to advance»"]
- **Affected boundary:** Готовность фазы 1 к переходу: проверки, сборка, неизменность экранов.
- **Implementation target:** ["openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md"]
- **Applicable constraints and non-goals:** Проверки на эмуляторе и устройстве не требуются (правило testing-scope). Ручные проверки остаются за пользователем.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Одна группа перекрытия U1–U3, потому что у единиц общие пути: тестовая поддержка `catalog_test_support.dart` и `details_test_support.dart`, контракт `intention_catalog.dart`, репозиторий. Ревьюер — свежий изолированный субагент по `implementation-decision-review`. Он получил нейтральный бриф и все пути диапазона, кроме `tasks.md`; планирование, история коммитов и отчёт ему не передавались. Чтение статическое. Его находку о nullable `typeCounts` при открытом типе оркестратор отклонил как несоразмерную (см. Review coverage). |
| OpenSpec conformance | Complete | Задачи 1.1–1.10 сверены с proposal, дельтами, design, ADR-0045 и plan.md в обе стороны. `openspec validate add-intention-picker-sorting-and-purpose --strict --no-interactive --json` — valid, без замечаний. В рабочей копии на `38cd39ba` (HEAD совпадает с проверяемой головой, рабочее дерево чистое) выполнены: `mise run check` — exit 0 (формат: 0 изменённых, `flutter analyze` без замечаний, обычные тесты +3338, процессные тесты +18); `mise run codegen-check` — exit 0; бенчмарк `benchmark/intention/intention_catalog_benchmark.dart` — exit 0, все четыре случая порядка по названию в бюджете 100 мс (режим smoke, одна выборка). Сборку APK этот этап заново не делал. |
| Code quality | Complete | Применён `code-review-and-quality` с пятью линзами: корректность, читаемость, архитектура, безопасность, производительность. Проверены все пути поставки и затронутые соседние места: запрос и `compare`, ключ порядка, курсор и `_keysetCondition`, подсчёт, снимки команд, индексы, модель и состояние, подписи каталога графа, диагностика, бенчмарк, тестовая поддержка. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Индексы порядка по названию для архивного охвата не читает ни один запрос до сортировки каталога графа

- **Evidence:** `lib/src/data/local/schema/intention_schema.drift` на проверяемой голове содержит `intentions_archived_title_search_key_asc_id_asc` и `intentions_archived_title_search_key_desc_id_asc` с условием `is_archived = 1`. Архивный охват выбирает только каталог графа намерений, а он через `_OfferedCatalogOrder` в `intention_catalog_page.dart` предлагает только четыре порядка по времени. Поиски читают активный или полный охват.
- **Evidence revisions:** ["38cd39baf4b7979ab433974a66b2cfa02f96fed4"]
- **Potential impact:** Два неиспользуемых индекса в базовом снимке схемы 6 обновляются каждой записью архивного намерения, архивированием и восстановлением и занимают место в файле. Если каталог графа получит порядок по названию в другой форме, индексы останутся мёртвыми, и убрать их можно будет только миграцией.
- **Acceptance rationale:** Владелец решил заложить основу сразу. Сортировка по названию в каталоге графа, где есть архивный охват, — ближайшее следующее изменение, а базовая схема 6 без миграции — последний случай добавить индексы без пути обновления. Цена записи для масштаба личного графа мала.
- **Scope and assumptions:** Только два индекса `(title_search_key ASC|DESC, id ASC)` с условием архивного охвата в схеме 6. Предполагается, что каталог графа получит порядок по названию через тот же ключ сохранённой проекции по ADR-0045 и с тем же курсором `(ключ, id ASC)`.
- **Reopen when:** Сортировку по названию в каталоге графа отменят или отложат на неопределённый срок; её спроектируют на другом ключе, направлении или форме курсора; схема 6 перестанет быть базовой версией без миграции.
- **Acceptance authority:** Явное решение владельца при разборе F4 ревью планирования 25.10.2026: каталог намерений с сортировкой по названию будет сделан вскоре, и основу под него нужно заложить сразу, пока это можно сделать без миграции.
- **Originating finding:** F4
- **Acceptance lifetime:** Durable
- **Decision record:** `docs/adr/0045-order-titles-by-opaque-key-of-stored-search-projection.md` («Последствия»); решение 3 и «Risks / Trade-offs» в `design.md`.

## Review coverage

Прочитаны proposal, три дельты спецификаций, design, adr.md, plan.md, tasks.md и прежний отчёт ревью планирования. Из канонических спецификаций сверены требования `local-data-lifecycle` о долговечности и восстановлении через импорт.

**U1.** `compare` сравнивает `IntentionTitleOrderKey` по кодовым точкам (`runes`). SQL упорядочивает по колонке `title_search_key` без явной collation, то есть `BINARY` по байтам UTF-8, и это тот же порядок. Ключ строится только в `_rehydrateSummary`: из колонки при чтении порции и из `_StoredIntentionCommandSnapshot.titleSearchKey` в снимке команды. Курсор — sealed-граница (время или ключ) плюс идентификатор. Равные ключи при `id ASC` в обоих направлениях согласованы с убывающим индексом `(title_search_key DESC, id ASC)`. Подсчёт одним запросом `COUNT(*)` и `COUNT(*) FILTER (is_action_ready)` идёт по условию без готовности, общее количество выводится по условию запроса. Первая порция и `IntentionTypeCounts` отклоняют противоречивые числа. Каталог графа перечисляет и подписывает исчерпывающе свой закрытый набор `_OfferedCatalogOrder`. Событие диагностики несёт поле сортировки отдельным перечислением модуля диагностики и не несёт пользовательского текста. Тесты покрывают регистр, «ß», «ё»/«я», латиницу и кириллицу, `U+E000` против `U+1F600`, продолжение через равные ключи, числа при названии, тегах и исключении для трёх условий готовности, а также принадлежность снимков после смены готовности.

**U2.** Версия 6, шесть частичных индексов, снимок `drift_schema_v6.json` вместо v5, комментарий стратегии миграции и тест bootstrap для маркеров 1–5 соответствуют задаче 1.4. README описывает очистку данных схем 1–5 без экспорта и импорта. Это не пробел: по решению владельца установка со старой схемой есть только у него, и данные он сохраняет сам.

**U3.** Доступность типа выражена sealed-значением по назначению. `changeType` применяется только к открытому типу и начинает новую выдачу. Числа запрашиваются только при открытом типе. Пропущенные числа или общее количество, не совпадающее с числом выбранного типа, дают `IntentionCatalogUnexpected`. Поправка «после − до» учитывает принадлежность без условия готовности и готовность снимков. Согласование в порядке по названию проверено сценарием «глобальный порядок и граница» для шести порядков со смешанным регистром у границы. Задача 1.8 не меняла код модели: проверка расхождений не нашла.

**U4.** Отметки в `tasks.md` подтверждены проверками этого этапа (см. Pass coverage). Изменений вида поисков и каталога графа в диапазоне нет.

Отклонённая находка независимого ревьюера. Он предложил связать `typeCounts` в подтверждённом состоянии с вариантом `IntentionTypeOpen`, чтобы пара «открытый тип без чисел» стала непредставимой. Это затронуло бы общий для загрузки и отказов `IntentionCatalogSelection` и около десяти мест пересборки состояния. Nullable-поле повторяет устоявшуюся форму `IntentionCatalogFirstPage.typeCounts`, а инвариант проверяется на единственном входе — `_mapFirstPage`. По правилу type-safe-design такая строгость несоразмерна.

Ручные проверки на устройстве остаются за пользователем и не выполнялись: перенос данных экспортом, очисткой и импортом; каталог и три поиска выглядят и работают как прежде.
