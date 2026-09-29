# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Все три прохода записанного диапазона завершены; неразрешённых находок нет. Согласованное устранение регрессии совместимости чтений закреплено в спецификации и design, оставшаяся реализация принадлежит незавершённым задачам 1.12–1.14. Код ещё не исправлен; это передача в планирование. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 4c129b05e610a1c21da3d68d785b6af917c74ac2
- **Base commit:** 4c129b05e610a1c21da3d68d785b6af917c74ac2
- **Reviewed head:** a143252b6db892ff7f48e35510f20263e544a0f2
- **Target commits:** ["857b3ad65a26a69fd5be5774f3bb2de984f6130f","bf8c5fa7f96bd4e7fe701941b6d22bb237002681","9d67024a39b17fbc1bc2eef79ad08bd80082f737","e283362c77d2abfc09a2cec337d4115db5ae988d","77eb487bb80425d9f6dd90f93f417c350e358818","90b343b1b2a24a436a03ee26e481a823058d9288","4d185e77d4ef37968711ea5cbee7ce21fe83d88d","fa460cc94dc549f6be4feb0cae243995397fc689","aa8ea923fe009cf80b4c76cbfb314fb4b7a773a6","9f50700cd23c89686b839b0636ac436d87dc1940","a143252b6db892ff7f48e35510f20263e544a0f2"]
- **Reviewable paths:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","lib/src/intention/application/intention_catalog.dart","lib/src/intention/presentation/catalog/intention_catalog_state.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","test/intention/application/intention_contract_test.dart","test/intention/data/drift_intention_catalog_test.dart","test/intention/data/drift_intention_repository_command_test.dart","test/intention/data/drift_intention_repository_fault_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U1 · Полные собственные теги кратких данных и снимков команд

- **Work items:** ["1.1","1.2","1.3","1.4","1.11"]
- **Requirements and scenarios:** ["intention-management: Теги в результатах поиска намерений — контракт данных первой фазы","Одноимённые намерения имеют разные теги","Ошибка получения тегов не выглядит отсутствием назначений","ADR-0009: точные каталожные снимки команд","ADR-0013: полные согласованные назначения"]
- **Affected boundary:** Прикладные значения каталога и транзакционные чтения/команды личного графа.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart","lib/src/intention/application/intention_catalog.dart","test/intention/application/intention_contract_test.dart","test/intention/data/drift_intention_catalog_test.dart","test/intention/data/drift_intention_repository_command_test.dart","test/intention/data/drift_intention_repository_fault_test.dart"]
- **Applicable constraints and non-goals:** Устойчивая типизированная идентичность; полные собственные назначения только возвращённых намерений, без предела числа тегов; проверка ссылок и данных до успешной сводки; одна транзакция и ревизия; историческая поисковая проекция снимка; сохранение тегов при копировании счётчика.
- **Excluded change scope:** Обновление после команд тегов относится к фазе 2; предъявление тегов пользователю и представления без поиска не входят в этот инкремент.

### U2 · Совместный отбор, точное количество и устойчивые порции

- **Work items:** ["1.5","1.6","1.7","1.10","1.11"]
- **Requirements and scenarios:** ["intention-management: Совместная фильтрация намерений по названию и тегам","intention-management: Полнота и порционность совместного поиска","intention-management: Сохранение условия после физического удаления тега — семантика чтения","Название, обязательные и исключённые теги действуют одновременно","Совпадение находится за пределами прежней первой порции","Количество совпадений превышает размер порции","Несколько обязательных тегов не повторяют намерение","daily-choice-management: Теги не обходят ограничения действия","daily-choice-management: Готовность не ограничивает найденное основание","long-term-relation-management: Совпадение тегов не разрешает самосвязь"]
- **Affected boundary:** Общий запрос и SQLite-адаптер: допустимость, принадлежность, COUNT, порядок, порции и непрозрачный курсор.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/intention/application/intention_catalog.dart","test/intention/application/intention_contract_test.dart","test/intention/data/drift_intention_catalog_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart"]
- **Applicable constraints and non-goals:** Все условия соединяются через «И» до подсчёта и LIMIT; только собственные TagId; прежние буквальный поиск названия и четыре порядка; исключение второго участника по IntentionId; нет размножения строк, пропусков и повторов; ограниченная материализация, параметризация и безопасная диагностика; чтение сохраняет предметные данные.
- **Excluded change scope:** Автоматическое согласование массовых изменений и открытой выдачи — фаза 2. Совместимость с ещё не включённым параллельным PR проверяется при объединении.

### U3 · Немедленная смена общего поиска и защита от поздних ответов

- **Work items:** ["1.8","1.9","1.11"]
- **Requirements and scenarios:** ["intention-management: Согласованность параметров совместного поиска","Добавление обязательного тега сразу применяет поиск","Удаление исключённого тега сразу применяет поиск","Поздняя порция прежних условий не попадает в новый результат","Смена охвата сохраняет совместный фильтр","Контексты поиска независимы","daily-choice-management: Совместный поиск действия для дневного выбора — общий контракт","daily-choice-management: Совместный поиск исходного намерения для дневного выбора — общий контракт","long-term-relation-management: Совместный поиск участника долговременной связи — общий контракт"]
- **Affected boundary:** Модель поискового состояния, независимые назначения каталога, действия, исходного намерения и участника связи; реальные ответы репозитория.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_state.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart"]
- **Applicable constraints and non-goals:** Изменение тегов сразу начинает первую порцию с текущим текстом и отменяет ожидающий debounce; обычный ввод названия сохраняет debounce; недопустимый ввод, пустой успех и отказ различимы; продолжение и восстановление сохраняют все условия; старое поколение не публикуется; ограничения назначения неизменны, поиск не выполняет команды.
- **Excluded change scope:** Виджеты фильтра, доступность будущего интерфейса и подключение предъявления тегов — фаза 3; обновление после команд тегов — фаза 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Изолированный рецензент independent_decisions с fork_turns=none проверил объединённую область U1–U3: все 15 delivery-путей, нейтральный brief и точный 4c129b05e610a1c21da3d68d785b6af917c74ac2..a143252b6db892ff7f48e35510f20263e544a0f2. Coverage Complete; единственная находка подтверждена координатором реальным API-воспроизведением. |
| OpenSpec conformance | Complete | Все 11 задач и коммитов сопоставлены U1–U3, контракты/сценарии первой фазы сверены с head; OpenSpec strict valid, генерация и её контроль exit 0. В исходном workspace на a143252b6db892ff7f48e35510f20263e544a0f2 выполнен mise run --skip-tools check, exit 0: формат 418 файлов, 0 изменений; CI-scope прошёл; flutter analyze — No issues found; flutter test --concurrency=2 — 2624 теста, All tests passed, включая slow (9 мин 13 с). |
| Code quality | Complete | Координатор применил code-review-and-quality ко всей delivery-области: корректность, читаемость, архитектура, безопасность, производительность и доказательства; test_evidence проверил все девять изменённых тестовых путей. Изучены затронутые вызывающие стороны, хранение, временные таблицы, ошибки и ревизии. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверен именно сохранённый диапазон 4c129b05e610a1c21da3d68d785b6af917c74ac2..a143252b6db892ff7f48e35510f20263e544a0f2. Discovery выполнен через локальный helper с --openspec /tmp/show-intention-tags-review-openspec; обёртка запускает исключительно mise exec --no-deps -- openspec. Список коммитов совпадает с workflow, все 11 диапазонов смежны и имеют указанные границы. Проверены diff каждого коммита, итоговый diff и относящееся окружение из записанного head. Изменённые пути классифицированы: шесть файлов реализации, девять файлов тестов и один артефакт задач. Все 15 путей реализации/тестов составляют точную объединённую delivery-область U1–U3; единственный planning-путь — tasks.md. Неотображённых или посторонних путей нет.

Planning-контекст прочитан из a143252b6db892ff7f48e35510f20263e544a0f2: proposal.md, три delta-spec, design.md, adr.md, plan.md и tasks.md изменения; применимые ADR-0002, ADR-0003, ADR-0009, ADR-0013, CONTEXT.md, openspec/config.yaml и конфигурация проверок. До аудита HEAD совпадал с Reviewed head и рабочая копия была чистой. Незакоммиченных planning-различий или исключённой пользовательской работы нет. Проверки выполняются в исходном workspace на этом head; после генерации tracked/untracked изменений не появилось.

Инкремент охватывает только фазу 1. Выполнение 11 задач не означает завершение всего изменения: согласование подтверждённых изменений тегов и назначений принадлежит фазе 2, интерфейс и пользовательское предъявление — фазе 3. Их отсутствие не использовалось как находка. Совместимость с параллельным PR не утверждается сверх фактически присутствующего кода.

Независимый рецензент independent_decisions получил нулевую историю, нейтральный brief с тремя результатами и полный объединённый список 15 delivery-путей, точные endpoints и target commits. U1–U3 пересекаются по целым файлам, поэтому проверены одной группой. Рецензент не читал planning, историю/сообщения коммитов, прежние находки или отчёт; контекстные пути перед чтением проверял на отсутствие изменений. Его Coverage: Complete и одна находка сверены координатором с кодом и самостоятельным API-воспроизведением. Рецензент test_evidence отдельно проверил все девять тестовых diff и соответствующие блоки head; его статическая оценка не подменяет запуск проверок.

Задача ID 1 (1.1), «Условия наличия и отсутствия тегов представлены одним неизменяемым типизированным значением», commit 857b3ad65a26a69fd5be5774f3bb2de984f6130f: U1; intention_contract_test.dart:109–292 проверяет оба набора, пустоту, пересечение, неизменяемость, равенство/хеш и идентичность.

Задача ID 2 (1.2), «Порция каталога возвращает полный проверенный состав собственных тегов каждого намерения», commit bf8c5fa7f96bd4e7fe701941b6d22bb237002681: U1; drift_intention_catalog_test.dart:852–1169 проверяет пакетность, только возвращённые ID, 1203 назначения при размере порции 1 и снимок до ожидающей команды; drift_intention_repository_fault_test.dart:37–185 проверяет повреждение, continuation и безопасные отказы без частичного успеха.

Задача ID 3 (1.3), «Каталожные снимки обычных команд намерений сохраняют достоверные собственные теги», commit 9d67024a39b17fbc1bc2eef79ad08bd80082f737: U1; drift_intention_repository_command_test.dart:53–365 проверяет 106 собственных тегов, исторический title_search_key, BEFORE/AFTER через SQLite trigger, снимок до каскадного удаления и rollback/revision; intention_contract_test.dart:404–446 — сохранение тегов при замене счётчика.

Задача ID 4 (1.4), «Подтвердить контракт кратких данных перед подключением совместной фильтрации», commit e283362c77d2abfc09a2cec337d4115db5ae988d: U1; commit меняет только отметку выполнения. Доказательства — реализация и проверки задач 1.1–1.3, регрессии каталожных мутаций и свежие проверки анализа/тестов записанного head.

Задача ID 5 (1.5), «Совместный запрос отбирает допустимые намерения по названию и обоим наборам тегов до подсчёта и ограничения порции», commit 77eb487bb80425d9f6dd90f93f417c350e358818: U2; intention_contract_test.dart:296–402 и drift_intention_catalog_test.dart:309–849 проверяют полный предикат, изоляцию/rollback, совпадение за прежними 100 строками, 1203 обязательных и 35000 исключённых условий при 400 параметрах, охват/готовность/исключение участника, удалённый ID и одноимённый новый тег.

Задача ID 6 (1.6), «Продолжение выдачи сохраняет совместный запрос и отклоняет курсор других условий», commit 90b343b1b2a24a436a03ee26e481a823058d9288: U2; drift_intention_catalog_test.dart:57–307 проверяет несовместимость до SQL, равные переставленные наборы, rename, 235 совпадений в порциях 100/100/35, четыре порядка, равные timestamps, один COUNT и отсутствие OFFSET.

Задача ID 7 (1.7), «Подтвердить достоверность совместного чтения перед подключением состояния поиска», commit 4d185e77d4ef37968711ea5cbee7ce21fe83d88d: U2; commit меняет только отметку выполнения. Проверены доказательства 1.4–1.6, регрессии существующего чтения назначений и строгая структурная валидация.

Задача ID 8 (1.8), «Изменение условий по тегам немедленно создаёт новый общий поиск с независимым состоянием каждого назначения», commit fa460cc94dc549f6be4feb0cae243995397fc689: U3; intention_catalog_tag_filter_view_model_test.dart:13–533 проверяет новую первую порцию, debounce/current text/invalid input, scope/order/retry, независимость назначений и полные условия continuation/recovery; generated diff ограничен воспроизводимым hash.

Задача ID 9 (1.9), «Поздние ответы прежних условий не заменяют новую выдачу через реальное соединение модели поиска и репозитория», commit aa8ea923fe009cf80b4c76cbfb314fb4b7a773a6: U3; intention_catalog_tag_filter_revision_protocol_test.dart:35–283 проверяет границу и матрицу двух наборов, четырёх видов чтения и трёх поздних исходов, включая владение новой подгрузкой; intention_catalog_tag_filter_integration_test.dart:63–373 проверяет реальные Drift+VM ответы, все назначения, отложенные first/continuation, scope и empty/invalid/unavailable/retry. catalog_test_support.dart:235–270 передаёт теги в тестовые сводки.

Задача ID 10 (1.10), «Подтвердить ограниченную материализацию и безопасную диагностику совместного поиска на больших данных», commit 9f50700cd23c89686b839b0636ac436d87dc1940: U2; drift_intention_repository_large_fixture_test.dart:59–364 проверяет файловую базу с 50000 намерений, 235 редкими совпадениями, 1201 условием в каждом наборе и 137 дополнительными тегами, четыре SELECT первой порции/три продолжения, LIMIT page+1, только ID возвращённых строк, вставки до 400 параметров и SQL-планы FTS/короткого текста; drift_intention_catalog_test.dart:2722–2954 проверяет категории/длительности и отсутствие личных данных в диагностике, включая отказ sink.

Задача ID 11 (1.11), «Подтвердить готовность общего поиска к реализации согласования изменений во второй фазе», commit a143252b6db892ff7f48e35510f20263e544a0f2: U1, U2 и U3; commit меняет только отметку выполнения. Проверены все предыдущие результаты, реальное соединение модели с адаптером, полная регрессия, формат, анализ, генерация и OpenSpec. Исторические отметки completed сохраняются.

Все перечисленные номера строк относятся к Reviewed head. Тестовые имена выше сокращены до имени файла; полные пути находятся в Implementation target соответствующих единиц. Сверка bytes исходного пакета tasks.md с baseline после нормализации только [ ]/[x] подтверждает неизменность номеров, описаний, порядка, критериев и зависимостей задач 1.1–1.11. При передаче в планирование этот пакет сохранён побайтно, включая отметки выполнения; в конец добавлены только незавершённые задачи 1.12–1.14. Исторические red/green-запуски или проверки промежуточных checkout не заявляются: результаты проверок реализации относятся к записанному head.

Качество проверено по корректности, читаемости, архитектуре, безопасности и производительности: типы и неизменяемость, декодирование ссылок/текста/BOM, транзакции и rollback, контекстная допустимость, историческая проекция, временные условия, курсоры/поколения/retry, согласованность количества и ревизии, пакетность/пределы материализации, параметризованный SQL и безопасная диагностика. Окружение getTaggedEntitiesPage и TagNavigationViewModel исследовано как контекст, не добавлено в target. Принятых человеком остаточных рисков нет.

Свежая проверка mise run --skip-tools codegen-check завершилась exit 0 на чистой копии записанного head; генерация не создала diff. mise run --skip-tools codegen-check-test завершилась exit 0. mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json завершилась exit 0: один valid change, issues=[]; это структурная проверка артефактов.

Согласованное устранение принадлежит требованию «Совместный поиск сохраняет продолжение навигации по тегу» в [спецификации намерений](specs/intention-management/spec.md) и решению 3 [design](design.md). Оставшаяся реализация и регрессионные доказательства отслеживаются в [tasks.md](tasks.md): 1.12 — сохранение курсора после успешных чтений, 1.13 — отказы, реальные изменения, ссылочная целостность и соединение с моделью навигации, 1.14 — контроль готовности первой фазы. Это передача в планирование по явному решению пользователя; код и тесты не изменены, исправление реализации не проверено. Принятие остаточного риска не выполнялось. Строгая OpenSpec-валидация обновлённого планирования прошла: valid=true, issues=[]; исходный tasks.md сохранён побайтно. Диапазон и покрытие ревью не изменены; продолжение фаз 2/3 требует соответствующих будущих пакетов задач.

В исходном workspace на a143252b6db892ff7f48e35510f20263e544a0f2 выполнен mise run --skip-tools check, exit 0: формат 418 файлов, 0 изменений; CI-scope прошёл; flutter analyze — No issues found; flutter test --concurrency=2 — 2624 теста, All tests passed, включая slow (9 мин 13 с).
