# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Передача наборов условий через `json_each(?)` устранила служебные записи на соединении. Навигация по тегу больше не сбрасывается, ручного учёта нет, отказ поиска остаётся его типизированным исходом. Защитная проверка падает на прежнем адаптере, полная проверка проходит. Однократная обработка наборов условий на запрос, при которой стоимость отсечения кандидата не растёт с числом условий, закреплена в решении 3 design и в незавершённых задачах 1.18–1.20. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** a089ebdb214f6c5b0355a06859139a71090a5454
- **Base commit:** a089ebdb214f6c5b0355a06859139a71090a5454
- **Reviewed head:** 95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe
- **Target commits:** ["57bdeb903a3db3ceed586140a6869e3bdd4c5bff","81edab459c6e510220181c699dd72db7b631bbd3","3cb688404b658f40381d5e69aa53d828dc6b7ddb","d34d1d39927a76209ffb36c515d053a1a127e057","95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe"]
- **Reviewable paths:** ["AGENTS.md","CLAUDE.md","apm.lock.yaml","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","test/graph/data/drift_tagged_entities_read_test.dart","test/graph/data/tagged_entities_catalog_storage_scenarios.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/tag/presentation/navigation/tag_navigation_catalog_integration_scenarios.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U5 · Совместный поиск без служебных записей на соединении и с подтверждённой стоимостью

- **Work items:** ["1.15","1.16","1.17"]
- **Requirements and scenarios:** ["intention-management: Совместный поиск сохраняет продолжение навигации по тегу","Успешный совместный поиск не сбрасывает навигацию","Отказ совместного поиска не сбрасывает навигацию","Реальное изменение хранилища сохраняет отклонение старого продолжения","design: решение 3 — наборы условий параметром json_each(?), чтения без записей","design: риск «Много назначений у одной строки или много условий»"]
- **Affected boundary:** Чтения каталога и навигации по тегу в DriftPersonalGraphRepository и модель навигации по тегу на настоящем адаптере.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","test/graph/data/drift_tagged_entities_read_test.dart","test/graph/data/tagged_entities_catalog_storage_scenarios.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/tag/presentation/navigation/tag_navigation_catalog_integration_scenarios.dart"]
- **Applicable constraints and non-goals:** Реальные изменения через предметную команду и сырые записи на том же или другом соединении по-прежнему лишают курсор действительности, в том числе без продвижения ревизии. Проверка ссылок не ослабляется. Число условий не ограничено, количество точное, материализация ограничена. Курсоры непрозрачны, исходы типизированы, диагностика безопасна. Новых постоянной схемы, миграции и пути записи нет.
- **Excluded change scope:** Согласование после команд тегов (фаза 2), интерфейс фильтра и предъявление тегов (фаза 3). Их задач в tasks.md пока нет, и их отсутствие находкой не считается.

## Unmapped range

- **Unmatched target paths:** ["AGENTS.md","CLAUDE.md","apm.lock.yaml"]
- **Reason:** Это инструментарий агентов, не связанный с изменением. Коммит 81edab459c6e510220181c699dd72db7b631bbd3 добавляет указатель CLAUDE.md, а 3cb688404b658f40381d5e69aa53d828dc6b7ddb обновляет зависимость APM agent-skills и перекомпилирует AGENTS.md с правилом process-discipline. Поведение приложения не меняется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий субагент с нулевой историей по навыку implementation-decision-review получил нейтральный brief U5 и точный диапазон a089ebdb214f6c5b0355a06859139a71090a5454..95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe со всеми семью delivery- и тестовыми путями. Planning, история коммитов, отчёт и прежние находки ему не передавались. Coverage Complete. |
| OpenSpec conformance | Complete | Задачи 1.15–1.17 сопоставлены с U5 и сверены на head с требованием «Совместный поиск сохраняет продолжение навигации по тегу», его сценариями, решением 3 и рисками design. Одноразовая копия /tmp/review-sfit-95933ca, собранная из git archive 95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe: mise run --skip-tools check — exit 0 (формат, CI scope, flutter analyze без замечаний, 2679 тестов вместе с медленными, All tests passed); codegen-check и codegen-check-test — exit 0, git status пуст. Красная проверка: тесты head с двумя файлами адаптера из a089ebdb214f6c5b0355a06859139a71090a5454 — три защитные проверки total_changes() падают. mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json — valid, 0 issues. |
| Code quality | Complete | Координатор применил code-review-and-quality к двум delivery-путям и пяти тестовым путям. Проверены семантика предикатов относительно базы, связывание параметров и отсутствие SQL-инъекций, классификация отказов, отсутствие записей и служебного SELECT, приватность диагностики и стоимость планов SQL. Стоимость воспроизведена отдельно в SQLite 3.53.1. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверен сохранённый диапазон a089ebdb214f6c5b0355a06859139a71090a5454..95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe. Discovery выполнен локальным helper. Пять коммитов совпадают с workflow, диапазоны задач смежны. До аудита HEAD совпадал с Reviewed head, рабочая копия была чистой. Исключённой пользовательской работы и незакоммиченных planning-различий нет. Классификация путей: два файла реализации и пять тестовых файлов входят в U5; tasks.md — planning-артефакт, в нём меняются только отметки выполнения 1.15–1.17; AGENTS.md, CLAUDE.md и apm.lock.yaml не связаны с изменением.

Planning прочитан из head: proposal, delta-спецификация intention-management, design (решение 3, риски, проверка подхода, план миграции) и tasks.md. Прежний отчёт не содержал активных находок и принятых рисков. Переданные им задачам 1.15–1.17 хрупкость ручного учёта и риск ложного отказа повреждения в пути учёта устранены этим диапазоном: учёт и его путь отказа удалены. Номера, описания и порядок задач 1.1–1.17 не менялись, прежние отметки выполнения сохранены.

Задача ID 15 (1.15), «Совместный поиск передаёт наборы условий параметром без служебных записей на соединении», commit 57bdeb903a3db3ceed586140a6869e3bdd4c5bff: U5. Временные таблицы условий, их подготовка и очистка, а также `_catalogTemporaryChanges` удалены. Версия хранилища строится из маркера соединения, `total_changes()` и `data_version` без вычитаний. Первая порция, количество и продолжение используют один предикат `_catalogCondition`. Защитная проверка в drift_tagged_entities_read_test.dart охватывает обязательные, исключённые и совместные условия: первая, повторная и продолжающая порции и отказы при подсчёте, порции и чтении тегов не меняют `total_changes()`, в TEMP остаётся только маркер соединения. Сценарии отказов, двух соединений и модели навигации переведены на те же наблюдаемые свойства. Отказы классифицируются прежним `_classifyCatalogReadFailure`, пути подмены ложным отказом повреждения больше нет. Ожидаемый файл drift_intention_repository_fault_test.dart не менялся: он подключает изменённые catalog_tag_filter_failure_scenarios.dart.

Задача ID 16 (1.16), «Подтвердить стоимость совместного поиска с наборами в параметре на больших данных», commit d34d1d39927a76209ffb36c515d053a1a127e057: U5. Фикстура проверяет отсутствие записей и служебного SELECT, 4 чтения первой и 3 чтения продолжающей порции, наборы условий в параметрах, адресные планы и полный обход с фильтром названия и без него. Критерии задачи формально выполнены. Но фикстура не обнаруживает рост стоимости с числом условий на каждого кандидата и не измеряет поиск только с исключениями среди многих кандидатов. Однократную обработку наборов и её доказательство на больших данных теперь закрепляют решение 3 design и незавершённые задачи 1.18 и 1.19.

Задача ID 17 (1.17), «Подтвердить готовность первой фазы после перехода на передачу наборов без записей», commit 95933cacf20a2bf2ecc0f4630b9a94d3abe38fbe: U5, контрольная; commit меняет только отметку выполнения. Её проверки заново выполнены в этом ревью на head (см. таблицу проходов). Готовность по стоимости подтверждает незавершённая задача 1.20.

Принятых человеком остаточных рисков нет.
