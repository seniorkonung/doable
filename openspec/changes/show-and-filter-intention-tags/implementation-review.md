# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Однократная обработка наборов условий устранила рост стоимости отсечения кандидата с числом условий. Семантика отбора, отсутствие записей на соединении и типизированные отказы сохранены. Однако предикат обязательных тегов, отобранных в список, управляет выборкой, и SQLite перестаёт использовать индекс порядка: каждая порция и каждое продолжение с обязательными тегами без FTS сортирует все совпадения во временном B-дереве (F2). Для популярного тега у 25 000 кандидатов продолжение замедлилось примерно в 10 раз. Большая фикстура сняла утверждение об индексе порядка и не нагружает популярный обязательный тег, поэтому регрессия проходит зелёной (F3). Принятых остаточных рисков нет.

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
| Independent decision review | Complete | Свежий субагент с нулевой историей по навыку implementation-decision-review получил нейтральный brief U6 и точный диапазон 5b76261ba7e58db98cdb5950b045f4a9761e4f60..dca4d0676e27341bebd1569b93ba2f29d522a542 со всеми пятью delivery- и тестовыми путями. Planning, история коммитов, отчёт и прежние находки ему не передавались. Coverage Complete. Результат — Changes needed: две находки, которые совпадают с F2 и F3. |
| OpenSpec conformance | Complete | Задачи 1.18–1.20 сопоставлены с U6 и сверены на head с решением 3 и рисками design. Одноразовая копия /tmp/review-sfit-dca4d06 собрана из git archive dca4d0676e27341bebd1569b93ba2f29d522a542. В ней выполнена большая фикстура: exit 0. Красная проверка 1.19: та же фикстура с адаптером из 5b76261ba7e58db98cdb5950b045f4a9761e4f60 падает на утверждении о некоррелированном наборе (`CORRELATED SCALAR SUBQUERY 2`). Там же mise run --skip-tools check — exit 0 (формат, CI scope, flutter analyze без замечаний, 2680 тестов вместе с медленными, All tests passed). codegen-check и codegen-check-test — exit 0, git status пуст. Зелёный прогон не опровергает F2 и F3: снятая проверка плана больше не охраняет индекс порядка. mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json — valid, 0 issues. |
| Code quality | Complete | Координатор применил code-review-and-quality к delivery-пути и четырём тестовым путям. Проверены: семантика предикатов относительно базы (уникальность `UNIQUE(tag_id, intention_id)`, `intention_id IS NOT NULL`, NULL-безопасность `NOT IN`); связывание параметров; классификаторы SQL в тестах отказов; отсутствие записей. Планы SQL и стоимость порций сравнены с 5b76261ba7e58db98cdb5950b045f4a9761e4f60 на одноразовом сценарии с популярным обязательным тегом. |

## Findings

### F2 · High — Обязательные теги лишают порцию и продолжение индекса порядка

- **Evidence:** В `lib/src/graph/data/drift_personal_graph_repository.dart:1576-1602` на head предикат обязательных тегов имеет вид `intentions.id IN (SELECT assignment.intention_id … GROUP BY assignment.intention_id HAVING COUNT(*) = ?)`. Его используют `_readFirstCatalogPage` и `_readCatalogContinuationPage` (`:875-943`) с `ORDER BY … LIMIT pageSize + 1`. Для всех запросов с обязательными тегами без FTS SQLite выбирает план `SEARCH intentions USING INDEX sqlite_autoindex_intentions_1 (id=?) | LIST SUBQUERY … | USE TEMP B-TREE FOR GROUP BY | USE TEMP B-TREE FOR ORDER BY`, и индекс `intentions_active_created_at_desc_id_asc` не используется. Это видно в выводе большой фикстуры на head. Запросы только с исключениями сохраняют `SCAN intentions USING INDEX intentions_active_created_at_desc_id_asc`. Одноразовый замер в /tmp/review-sfit-dca4d06: 50 000 намерений, один обязательный тег у всех, 25 000 активных совпадений, трассировка `getCatalogPage`. На head первая порция заняла 236–292 мс, продолжения 106–138 мс. С адаптером 5b76261ba7e58db98cdb5950b045f4a9761e4f60 — 42–94 мс и 8–12 мс, план шёл по индексу порядка. Решение 3 в `design.md:98` требует: «Существующие индексы порядка сохраняются для сортировки и продолжения». Изолированный ревьюер независимо воспроизвёл регрессию в SQLite 3.53.1.
- **Evidence revisions:** ["dca4d0676e27341bebd1569b93ba2f29d522a542","5b76261ba7e58db98cdb5950b045f4a9761e4f60"]
- **Impact:** Популярный обязательный тег — обычный сценарий фильтра. С ним стоимость каждой порции, включая каждое продолжение прокрутки, растёт с числом совпадений, а не с размером порции: все совпавшие строки заново сортируются во временном B-дереве. На 25 000 совпадений продолжение замедлилось примерно в 10 раз, на мобильных устройствах эффект сильнее. Задачи 1.18 и 1.20 отмечены выполненными, хотя требование design о сохранении индексов порядка не выполнено.
- **Required outcome:** С обязательными условиями, в том числе совместными, без фильтра названия или с фильтром без FTS первая порция и продолжение обходят кандидатов по существующему индексу порядка и завершаются после `pageSize + 1` строк без сортировки всего множества совпадений. При этом сохраняются однократная обработка каждого набора на запрос, прежняя семантика и точное количество, отсутствие записей на соединении и независимость стоимости отсечения кандидата от числа условий.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/graph/data/drift_personal_graph_repository.dart: _RequiredCatalogTagsExpression","tasks.md: 1.18","tasks.md: 1.20","design.md: решение 3"]

### F3 · Medium — Фикстура больших данных не охраняет индекс порядка и популярный обязательный тег

- **Evidence:** Коммит bba4fa585ad6a6772896d75b42d1696958734518 удалил из `_expectJointPlans` проверку плана порции. На базе 5b76261ba7e58db98cdb5950b045f4a9761e4f60 это `test/intention/data/drift_intention_repository_large_fixture_test.dart:416-426`, где утверждалось `intentions_active_created_at_desc_id_asc` без FTS. Замены у неё нет. Новая `_expectConditionSetsReadOnce` (`:498-551` на head) проверяет только некоррелированность набора и `LIST SUBQUERY`. Сценарии «только обязательные» (`:158-164`) и совместные используют обязательные теги не более чем у 245 кандидатов. Фоновые теги (`:332`) в условия не входят. Поэтому фикстура проходит зелёной, хотя её собственный вывод показывает `USE TEMP B-TREE FOR ORDER BY` для всех запросов с обязательными тегами. 1.16 требовала, чтобы планы SQL подтверждали «существующие индексы порядка», а 1.19 требовала сохранить прежние доказательства 1.16.
- **Evidence revisions:** ["dca4d0676e27341bebd1569b93ba2f29d522a542","5b76261ba7e58db98cdb5950b045f4a9761e4f60"]
- **Impact:** Регрессия F2 и любые будущие смены плана, которые возвращают сортировку всего множества совпадений, не обнаруживаются проверками. Отметка выполнения 1.19 опирается на доказательство, которое пропускает именно нарушающий случай.
- **Required outcome:** Большая фикстура утверждает, не опираясь на скорость машины, что первая порция и продолжение без FTS идут по индексу порядка без `TEMP B-TREE FOR ORDER BY`. Это проверяется для запросов только с обязательными, только с исключёнными и с совместными условиями. Среди нагружаемых условий есть обязательный тег, назначенный большой доле кандидатов. Проверка падает на реализации dca4d0676e27341bebd1569b93ba2f29d522a542.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/intention/data/drift_intention_repository_large_fixture_test.dart","tasks.md: 1.19"]

## Review coverage

Проверен сохранённый диапазон 5b76261ba7e58db98cdb5950b045f4a9761e4f60..dca4d0676e27341bebd1569b93ba2f29d522a542. Discovery выполнен локальным helper. Три коммита совпадают с workflow, диапазоны задач смежны. До аудита HEAD совпадал с Reviewed head, рабочая копия была чистой. Исключённой пользовательской работы и незакоммиченных planning-различий нет. Классификация путей: файл реализации и четыре тестовых файла входят в U6. tasks.md — planning-артефакт, в нём меняются только отметки выполнения 1.18–1.20. Несопоставленных путей нет.

Planning прочитан из head: design (решение 3, риски) и tasks.md (1.15–1.20). Прежний отчёт не содержал активных находок и принятых рисков. Номера, описания и порядок задач 1.1–1.20 не менялись, прежние отметки выполнения сохранены. Коррекций кода и артефактов на этом этапе не вносилось. Находки F2 и F3 переданы следующим этапам разрешения.

Задача ID 18 (1.18), «Предикаты условий по тегам обрабатывают каждый набор один раз на запрос», commit 08bbf3026195d3fee97de114850f7ba5c6d83d91: U6. Оба предиката стали некоррелированными отборами по `(tag_id, intention_id)`. Обязательные отбираются через `HAVING COUNT(*)` по числу различных канонических идентификаторов, для исключённых используется `NOT IN` с отбрасыванием `NULL`. Новый тест в drift_intention_catalog_test.dart охватывает 11 наборов условий × 2 охвата × 2 фильтра названия по всем порциям: пересечение наборов, несуществующие теги, назначения связям. Классификаторы запроса количества в тестах отказов уточнены до `startsWith('SELECT COUNT(')`, потому что в запросе порции теперь есть `COUNT(*)` в `HAVING`. Семантика подтверждена. Нарушение сохранения индексов порядка — F2.

Задача ID 19 (1.19), «Большая фикстура закрепляет независимость стоимости отсечения кандидата от числа условий», commit bba4fa585ad6a6772896d75b42d1696958734518: U6. Фикстура добавляет фоновые назначения и сценарии только с исключениями, только с обязательными и совместные, при 10 и 1201 условии. Она утверждает некоррелированное однократное чтение набора и адресный поиск назначений, сохраняет проверки записей, числа чтений и материализации. Красная проверка на адаптере 1.15 подтверждена. Снятая проверка индекса порядка и отсутствие популярного обязательного тега — F3.

Задача ID 20 (1.20), «Подтвердить готовность первой фазы после однократной обработки наборов условий», commit dca4d0676e27341bebd1569b93ba2f29d522a542: U6, контрольная; commit меняет только отметку выполнения. Её проверки выполнены в этом ревью на head.

Принятых человеком остаточных рисков нет.
