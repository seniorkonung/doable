# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Однократная обработка наборов условий устранила рост стоимости отсечения кандидата с числом условий. Семантика отбора, отсутствие записей на соединении и типизированные отказы сохранены. Регрессия обхода по индексу порядка при обязательных тегах передана в planning: решение 3 в design уже требует сохранять индексы порядка, а исправление отслеживают новые незавершённые задачи 1.21 и 1.22. Пробел в охране большой фикстуры (снятое утверждение об индексе порядка, нет популярного обязательного тега) также передан в planning: его закрывают новые незавершённые задачи 1.23 и 1.24. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 5b76261ba7e58db98cdb5950b045f4a9761e4f60
- **Base commit:** 5b76261ba7e58db98cdb5950b045f4a9761e4f60
- **Reviewed head:** dca4d0676e27341bebd1569b93ba2f29d522a542
- **Target commits:** ["08bbf3026195d3fee97de114850f7ba5c6d83d91","bba4fa585ad6a6772896d75b42d1696958734518","dca4d0676e27341bebd1569b93ba2f29d522a542"]
- **Reviewable paths:** ["lib/src/graph/data/drift_personal_graph_repository.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","test/graph/data/drift_tagged_entities_read_test.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_catalog_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U6 · Однократная обработка наборов условий по тегам и её доказательство на больших данных

- **Work items:** ["1.18","1.19","1.20"]
- **Requirements and scenarios:** ["intention-management: совместный поиск по названию и тегам","design: решение 3 — каждый набор условий читается один раз на выполнение запроса, существующие индексы порядка сохраняются для сортировки и продолжения","design: риск «Много назначений у одной строки или много условий»"]
- **Affected boundary:** Чтения каталога намерений с условиями по тегам в DriftPersonalGraphRepository: первая порция, точное количество, продолжение и восстановление.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart","test/graph/data/drift_tagged_entities_read_test.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_catalog_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart"]
- **Applicable constraints and non-goals:** Стоимость отсечения кандидата не растёт с числом условий. Семантика и точное количество прежние. Чтения не пишут на соединение и не меняют `total_changes()`. Число условий не ограничено параметрами SQL, материализация ограничена порцией и её назначениями. Курсоры непрозрачны, отказы типизированы, диагностика безопасна. Новых постоянной схемы, индекса, миграции и пути записи нет.
- **Excluded change scope:** Согласование после команд тегов (фаза 2), интерфейс фильтра и предъявление тегов (фаза 3). Их задач в tasks.md пока нет, и их отсутствие находкой не считается.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий субагент с нулевой историей по навыку implementation-decision-review получил нейтральный brief U6 и точный диапазон 5b76261ba7e58db98cdb5950b045f4a9761e4f60..dca4d0676e27341bebd1569b93ba2f29d522a542 со всеми пятью delivery- и тестовыми путями. Planning, история коммитов, отчёт и прежние находки ему не передавались. Coverage Complete. Результат — Changes needed: две находки, обе переданы в planning (задачи 1.21 и 1.23). |
| OpenSpec conformance | Complete | Задачи 1.18–1.20 сопоставлены с U6 и сверены на head с решением 3 и рисками design. Одноразовая копия /tmp/review-sfit-dca4d06 собрана из git archive dca4d0676e27341bebd1569b93ba2f29d522a542. В ней выполнена большая фикстура: exit 0. Красная проверка 1.19: та же фикстура с адаптером из 5b76261ba7e58db98cdb5950b045f4a9761e4f60 падает на утверждении о некоррелированном наборе (`CORRELATED SCALAR SUBQUERY 2`). Там же mise run --skip-tools check — exit 0 (формат, CI scope, flutter analyze без замечаний, 2680 тестов вместе с медленными, All tests passed). codegen-check и codegen-check-test — exit 0, git status пуст. Зелёный прогон не опровергает потерю индекса порядка (задача 1.21), потому что снятая проверка плана больше не охраняет индекс порядка (задача 1.23). mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json — valid, 0 issues. |
| Code quality | Complete | Координатор применил code-review-and-quality к delivery-пути и четырём тестовым путям. Проверены: семантика предикатов относительно базы (уникальность `UNIQUE(tag_id, intention_id)`, `intention_id IS NOT NULL`, NULL-безопасность `NOT IN`); связывание параметров; классификаторы SQL в тестах отказов; отсутствие записей. Планы SQL и стоимость порций сравнены с 5b76261ba7e58db98cdb5950b045f4a9761e4f60 на одноразовом сценарии с популярным обязательным тегом. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверен сохранённый диапазон 5b76261ba7e58db98cdb5950b045f4a9761e4f60..dca4d0676e27341bebd1569b93ba2f29d522a542. Discovery выполнен локальным helper. Три коммита совпадают с workflow, диапазоны задач смежны. До аудита HEAD совпадал с Reviewed head, рабочая копия была чистой. Исключённой пользовательской работы и незакоммиченных planning-различий нет. Классификация путей: файл реализации и четыре тестовых файла входят в U6. tasks.md — planning-артефакт, в нём меняются только отметки выполнения 1.18–1.20. Несопоставленных путей нет.

Planning прочитан из head: design (решение 3, риски) и tasks.md (1.15–1.20). Прежний отчёт не содержал активных находок и принятых рисков. Номера, описания и порядок задач 1.1–1.20 не менялись, прежние отметки выполнения сохранены. Коррекций кода на этом этапе не вносилось. Находка о потере индекса порядка при обязательных тегах разрешена передачей в planning: по решению пользователя в tasks.md добавлены незавершённые задачи 1.21 (обход порции и продолжения по индексу порядка) и 1.22 (контрольная проверка); задачи 1.1–1.20 и их отметки не менялись. Пробел в охране большой фикстуры разрешён передачей в planning: по решению пользователя в tasks.md добавлены незавершённые задачи 1.23 (охрана обхода по индексу порядка и популярный обязательный тег в большой фикстуре) и 1.24 (контрольная проверка); задачи 1.1–1.22 и их отметки не менялись.

Задача ID 18 (1.18), «Предикаты условий по тегам обрабатывают каждый набор один раз на запрос», commit 08bbf3026195d3fee97de114850f7ba5c6d83d91: U6. Оба предиката стали некоррелированными отборами по `(tag_id, intention_id)`. Обязательные отбираются через `HAVING COUNT(*)` по числу различных канонических идентификаторов, для исключённых используется `NOT IN` с отбрасыванием `NULL`. Новый тест в drift_intention_catalog_test.dart охватывает 11 наборов условий × 2 охвата × 2 фильтра названия по всем порциям: пересечение наборов, несуществующие теги, назначения связям. Классификаторы запроса количества в тестах отказов уточнены до `startsWith('SELECT COUNT(')`, потому что в запросе порции теперь есть `COUNT(*)` в `HAVING`. Семантика подтверждена. Нарушение сохранения индексов порядка передано задаче 1.21.

Задача ID 19 (1.19), «Большая фикстура закрепляет независимость стоимости отсечения кандидата от числа условий», commit bba4fa585ad6a6772896d75b42d1696958734518: U6. Фикстура добавляет фоновые назначения и сценарии только с исключениями, только с обязательными и совместные, при 10 и 1201 условии. Она утверждает некоррелированное однократное чтение набора и адресный поиск назначений, сохраняет проверки записей, числа чтений и материализации. Красная проверка на адаптере 1.15 подтверждена. Снятая проверка индекса порядка и отсутствие популярного обязательного тега переданы задаче 1.23.

Задача ID 20 (1.20), «Подтвердить готовность первой фазы после однократной обработки наборов условий», commit dca4d0676e27341bebd1569b93ba2f29d522a542: U6, контрольная; commit меняет только отметку выполнения. Её проверки выполнены в этом ревью на head.

Принятых человеком остаточных рисков нет.
