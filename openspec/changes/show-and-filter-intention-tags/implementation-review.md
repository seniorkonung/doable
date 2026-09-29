# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Регрессия навигации по тегу устранена: новые регрессионные проверки проходят на записанном head и падают на прежнем коде адаптера, полная проверка репозитория прошла. Хрупкость ручного учёта служебных записей TEMP передана в planning: по решению 3 design наборы передаются параметром `json_each(?)` без записей, реализацию ведут незавершённые задачи 1.15–1.17. Остаётся одна находка. F2 (Low): при отказе поиска путь учёта может заменить исходный типизированный отказ ложным отказом повреждения. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 9747b220051cbadc0c685199d97cf6b299831f66
- **Base commit:** 9747b220051cbadc0c685199d97cf6b299831f66
- **Reviewed head:** 3e7c22938b74caa71e7a5082dadfa5e823600303
- **Target commits:** ["d52581a4093887bd9672cc762adf73530d1b6734","822d98705db1a2db093d030145f8aa17e94ef53c","3e7c22938b74caa71e7a5082dadfa5e823600303"]
- **Reviewable paths:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","test/graph/data/drift_tagged_entities_read_test.dart","test/graph/data/tagged_entities_catalog_storage_scenarios.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_repository_fault_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/tag/presentation/navigation/tag_navigation_catalog_integration_scenarios.dart","test/tag/presentation/navigation/tag_navigation_view_model_test.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U4 · Совместный поиск сохраняет продолжение навигации по тегу

- **Work items:** ["1.12","1.13","1.14"]
- **Requirements and scenarios:** ["intention-management: Совместный поиск сохраняет продолжение навигации по тегу","Успешный совместный поиск не сбрасывает навигацию","Отказ совместного поиска не сбрасывает навигацию","Реальное изменение хранилища сохраняет отклонение старого продолжения","design: решение 3 — служебные записи условий не делают соседние снимки устаревшими"]
- **Affected boundary:** Чтения DriftPersonalGraphRepository (совместный поиск каталога и навигация по тегу) и модель навигации по тегу, использующая их на настоящем адаптере.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","test/graph/data/drift_tagged_entities_read_test.dart","test/graph/data/tagged_entities_catalog_storage_scenarios.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart","test/intention/data/drift_intention_repository_fault_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/tag/presentation/navigation/tag_navigation_catalog_integration_scenarios.dart","test/tag/presentation/navigation/tag_navigation_view_model_test.dart"]
- **Applicable constraints and non-goals:** Реальные изменения через предметную команду и сырые записи на том же или другом физическом соединении по-прежнему лишают курсор действительности, в том числе без продвижения ревизии; ссылочная целостность не ослабляется; курсоры непрозрачны, исходы типизированы; нет новой постоянной схемы, миграции или пути записи; неограниченное число условий, точное количество, ограниченная материализация и безопасная диагностика сохраняются.
- **Excluded change scope:** Согласование после команд тегов (фаза 2), интерфейс фильтра и предъявление тегов (фаза 3); в tasks.md задач этих фаз пока нет, их отсутствие находкой не считается.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий субагент с нулевой историей по навыку implementation-decision-review получил нейтральный brief U4 и точный 9747b220051cbadc0c685199d97cf6b299831f66..3e7c22938b74caa71e7a5082dadfa5e823600303 со всеми девятью delivery- и тестовыми путями. Planning, история, отчёт и прежние находки ему не передавались; контекстные пути он предварительно проверил на неизменность. Coverage Complete; обе находки координатор сверил с кодом. |
| OpenSpec conformance | Complete | Задачи 1.12–1.14 сопоставлены с U4 и сверены с требованием, сценариями и решением 3 design на head. Строгая OpenSpec-валидация: valid, 0 issues. mise run --skip-tools check в рабочей копии на 3e7c22938b74caa71e7a5082dadfa5e823600303: exit 0, All tests passed, 2682 теста, включая медленные. codegen-check и codegen-check-test: exit 0, изменений нет. Красная проверка: тесты head с кодом адаптера из base — 39 падений. |
| Code quality | Complete | Координатор применил code-review-and-quality к двум delivery-путям и семи тестовым путям. Проверены: учёт total_changes()/data_version, маркер соединения, откат, классификация отказов, сборка репозитория в app_runtime, изолятный адаптер соединений, стоимость дополнительных чтений и приватность диагностики. |

## Findings

### F2 · Low — Путь учёта при отказе поиска может заменить исходный типизированный отказ

- **Evidence:** В ветке `on Object` метода `_withCatalogTagFilter` (lib/src/graph/data/drift_personal_graph_repository.dart:895–909) повторно вызывается `_tagReadStorageVersion`, то есть CREATE TEMP TABLE IF NOT EXISTS … randomblob и SELECT. При несовпадении идентификатора соединения выбрасывается `_StoredIntentionCorruption`. Маркер создаётся внутри транзакции поиска, если это первое чтение версии на соединении: например, фильтр по тегам применён до любой навигации после запуска. При ошибках, после которых SQLite сам откатывает всю транзакцию (IOERR, NOMEM и в ряде случаев FULL и BUSY), маркер исчезает, создаётся новый, и поиск возвращает IntentionCorruptionFailure вместо исходной категории. Если сама ветка учёта завершится исключением, оно тоже заменит исходную ошибку. Тесты внедряют отказы из Dart-наблюдателя (test/intention/data/catalog_tag_filter_failure_scenarios.dart:166–211), поэтому автоматический откат SQLite не проверяется.
- **Evidence revisions:** ["3e7c22938b74caa71e7a5082dadfa5e823600303"]
- **Impact:** Редкий кратковременный отказ хранилища предъявляется как повреждение данных или с неверной категорией. Это нарушает требование, чтобы отказ поиска оставался отдельным корректно типизированным исходом. Смена маркера в этой ветке ничего не защищает: курсоров, зависящих от потерянного учёта, на этом соединении ещё нет.
- **Required outcome:** Учёт в пути отказа никогда не меняет и не заменяет категорию исходного отказа поиска. Если учёт выполнить нельзя, допустим только консервативный исход (устаревание курсоров навигации), а не отказ повреждения. Поведение подтверждено проверкой с настоящим откатом транзакции на уровне SQLite либо снимается выполнением задачи 1.15, которая удаляет учёт служебных записей.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/graph/data/drift_personal_graph_repository.dart","test/intention/data/catalog_tag_filter_failure_scenarios.dart"]

## Review coverage

Проверен именно сохранённый диапазон 9747b220051cbadc0c685199d97cf6b299831f66..3e7c22938b74caa71e7a5082dadfa5e823600303. Discovery выполнен локальным helper; список из трёх коммитов совпадает с workflow, диапазоны задач смежны. До аудита HEAD совпадал с Reviewed head, рабочая копия была чистой; исключённой пользовательской работы и незакоммиченных planning-различий нет. Пути классифицированы так: два файла реализации, семь тестовых файлов, один planning-артефакт (tasks.md, где меняются только отметки выполнения 1.12–1.14). Неотображённых путей нет.

Planning прочитан из head: proposal, delta-спецификация intention-management (требование «Совместный поиск сохраняет продолжение навигации по тегу» и три его сценария), design (решения 3 и 6, риски, проверка подхода, план миграции) и tasks.md. Предыдущий отчёт не содержал активных находок и принятых рисков; его передача в планирование прежней находки о регрессии навигации закрыта задачами 1.12–1.14, которые этот диапазон реализует. Номера, описания и порядок задач 1.1–1.14 не менялись, прежние отметки выполнения сохранены.

Задача ID 12 (1.12), «Совместные чтения каталога сохраняют действительный курсор навигации по тегу на неизменных данных», commit d52581a4093887bd9672cc762adf73530d1b6734: U4. В адаптер добавлены маркер физического соединения и учёт служебных записей TEMP. drift_tagged_entities_read_test.dart проверяет цепочку навигация → первая порция, повтор и продолжение каталога → продолжение навигации в обоих охватах для шести сочетаний условий: полный обход без повторов, неизменные предметные данные, схема и ревизия, отсутствие повторной первой порции. Критерий «провал до исправления» подтверждён в этом ревью: тесты head с двумя файлами адаптера из base дали 39 падений из 318 (одноразовая копия /tmp, flutter test --no-pub для drift_tagged_entities_read_test.dart, tag_navigation_view_model_test.dart и drift_intention_repository_fault_test.dart).

Задача ID 13 (1.13), «Отказы совместного поиска сохраняют навигацию без ослабления обнаружения реальных изменений и повреждений», commit 822d98705db1a2db093d030145f8aa17e94ef53c: U4. В пути отказа добавлен учёт total_changes(). catalog_tag_filter_failure_scenarios.dart проверяет четыре точки отказа, три категории, первый и повторный поиск, откат, безопасную диагностику и продолжение навигации. tagged_entities_catalog_storage_scenarios.dart проверяет на файловой базе сырые записи и повреждение ссылок на том же и другом соединении, до и после успешного и отказавшего поиска, изоляцию учёта двух соединений и устаревание после предметной команды. tag_navigation_catalog_integration_scenarios.dart проверяет модель навигации с настоящим репозиторием: сохранение загруженных строк, одно чтение продолжения и восстановление после действительно устаревшего снимка. Отказы в тестах внедряются на уровне Dart; автоматический откат SQLite не покрыт (см. F2).

Задача ID 14 (1.14), «Подтвердить готовность первой фазы после устранения регрессии навигации по тегу», commit 3e7c22938b74caa71e7a5082dadfa5e823600303: U4, контрольная; commit меняет только отметку выполнения. Доказательства получены заново в этом ревью на head: mise run --skip-tools check — exit 0, 2682 теста, All tests passed; codegen-check и codegen-check-test — exit 0, git status после генерации пуст; mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json — valid, 0 issues. drift_intention_repository_large_fixture_test.dart подтверждает ограниченную материализацию с одним дополнительным служебным SELECT.

Качество кода проверено по пяти направлениям. Учёт не может скрыть реальную запись: он растёт только на точное число строк DML или на разность, измеренную внутри транзакции. Идентификатор соединения исключает ложное совпадение счётчиков разных соединений. Проверки ссылок, непрозрачность курсоров и приватность диагностики не изменились. Архитектурная хрупкость учёта и его владение переданы в design (решение 3) и задачи 1.15–1.17; классификация отказа — в F2. Принятых человеком остаточных рисков нет.
