# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Фаза 2 реализована: модель даёт каталогу охват, тип, сортировку и сброс одним действием, а чтение первой порции одним запросом подсчёта даёт матрицу охватов и типов. Числа согласуются при каждой подтверждённой операции, включая переход между охватами, а несогласуемые числа ведут к новому чтению. Прежняя страница каталога новых параметров не показывает. Находок нет. Все части `mise run check` прошли на рассматриваемой голове, но `check:process-tests` прошёл только со второго запуска: в первом запуске неизменённый диапазоном тест упал по таймауту, подробности в разделе покрытия.

## Review target

- **Baseline ref:** 2eb9ffd2e4ef5888482cd2ab980cec9449687ae7
- **Base commit:** 2eb9ffd2e4ef5888482cd2ab980cec9449687ae7
- **Reviewed head:** feb0116dd7bb69866376b4ef3ae7eabde6efafef
- **Target commits:** ["bf68c782d5a09c7d5cadeafdcdcbb120722debe6", "6608076642bdfa922cd4f0df23fe2b11e5bafe00", "fd9046c744d62fcfda51cdf360067b3db9380528", "6fa71744216fdaecb73ed5f36ab5abf9aef23484", "3755cfedc7fc38f5fe9237782050073607ba8ed5", "dfdc85ff66108529b6d1136dd9e11ed12e18fa42", "feb0116dd7bb69866376b4ef3ae7eabde6efafef"]
- **Reviewable paths:** ["benchmark/intention/intention_catalog_benchmark.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/search/intention_list_header.dart", "lib/src/intention/presentation/search/show_and_sort_sheet.dart", "openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart", "test/intention/presentation/picker/intention_picker_purpose_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart", "test/support/intention_type_counts.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Первая порция каталога с видом подсчёта из запроса и замеренной стоимостью

- **Work items:** ["2.1", "2.2"]
- **Requirements and scenarios:** ["intention-management: Точное количество совпадений каталога", "intention-management: Параметры показа в поиске намерений (числа охватов и типов)", "design: решение 4", "ADR-0049: числа"]
- **Affected boundary:** Чтение первой порции в локальном хранилище и контракт порции между хранилищем и моделью каталога.
- **Implementation target:** ["benchmark/intention/intention_catalog_benchmark.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/picker/intention_picker_purpose_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart", "test/support/intention_type_counts.dart"]
- **Applicable constraints and non-goals:** Схема, индексы и формат графа не меняются. Запрос строк порции не меняется, первая порция читается одним запросом подсчёта. Время измеряется только в бенчмарке.

### U2 · Охват и тип как доступность, открытый тип каталога

- **Work items:** ["2.3"]
- **Requirements and scenarios:** ["intention-management: Каталог намерений и его охват", "intention-management: Живое применение параметров каталога / Сохранение фильтра и порядка при смене охвата", "intention-management: Тип намерения в поиске намерений", "design: решение 3"]
- **Affected boundary:** Выбор параметров модели каталога и его потребители: прежняя страница каталога, заголовок списка, лист «Показать и упорядочить», экраны выбора.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/search/intention_list_header.dart", "lib/src/intention/presentation/search/show_and_sort_sheet.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart"]
- **Applicable constraints and non-goals:** Прежняя страница каталога выглядит и ведёт себя как раньше и новых параметров не показывает. Экраны выбора сохраняют закреплённые охват и тип.
- **Excluded change scope:** Показ новых параметров и чисел в интерфейсе каталога, пустые состояния каталога и новая страница относятся к фазе 4, перевод сценарных проверок — к фазе 3.

### U3 · Точные числа подтверждённой выдачи при каждой операции

- **Work items:** ["2.4"]
- **Requirements and scenarios:** ["intention-management: Точное количество совпадений каталога / Количество после подтверждённого изменения", "intention-management: Параметры показа в поиске намерений (количества только для подтверждённой выдачи)", "intention-management: Меню параметров показа в поиске намерений / Меню охвата считает намерения выбранного типа (на уровне модели)", "design: решение 4, согласование и хранение"]
- **Affected boundary:** Подтверждённое состояние модели каталога и его согласование с пакетами подтверждённых изменений графа.
- **Implementation target:** ["lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "test/intention/application/intention_contract_test.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Числа согласуются подтверждёнными снимками на ревизии по ADR-0009. Экраны выбора получают те же числа типов, что раньше. Несогласуемые числа ведут к новому чтению с первой порции.

### U4 · Сброс параметров показа одним действием модели

- **Work items:** ["2.5"]
- **Requirements and scenarios:** ["intention-management: Параметры показа в поиске намерений / «Сбросить» возвращает начальный показ", "intention-management: Параметры показа в поиске намерений / «Сбросить» в каталоге возвращает активный охват и сохраняет поиск (на уровне модели)", "app-navigation: Сохранение состояния корневых страниц / Замена графа сбрасывает корневые страницы (тип и параметры в модели)", "design: решение 3, сброс"]
- **Affected boundary:** Модель каталога и лист «Показать и упорядочить», который предлагает и вызывает сброс.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/search/show_and_sort_sheet.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Сброс сохраняет фильтр названия и условия по тегам и даёт одно новое чтение. Поведение листа экранов выбора не меняется.

### U5 · Готовность фазы 2

- **Work items:** ["2.6"]
- **Requirements and scenarios:** ["plan.md: Phase 2 / Ready to advance"]
- **Affected boundary:** Сгенерированный провайдер модели каталога и автоматические проверки проекта.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart"]
- **Applicable constraints and non-goals:** Задача только проверочная; сгенерированный файл обновлён, чтобы прошёл `codegen-check`. Проверки на устройстве не требуются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер (Sonnet, high, `implementation-decision-review`) проверил группу перекрытия U1–U5: все пять единиц делят `intention_catalog_view_model.dart`, поэтому цель объединена из 23 путей реализации и тестов. Планирующие артефакты, история коммитов и прежний отчёт ему не передавались. Результат: `No substantive findings`, покрытие полное; остальные тестовые файлы он просмотрел только на предмет замеров времени. |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве на голове feb0116dd7bb69866376b4ef3ae7eabde6efafef без незакоммиченных изменений. `dart format`, `test/tool`-проверки и `flutter analyze` прошли без замечаний, 3848 обычных тестов прошли, `mise run codegen-check` прошёл. `mise exec --no-deps -- openspec validate redesign-intention-catalog --strict --json` — valid. `mise run check:process-tests` в составе первого запуска `mise run check` завершился с кодом 1, повторный отдельный запуск прошёл, 18 из 18. |
| Code quality | Complete | Навык `code-review-and-quality` применён ко всем путям реализации: чтение и подсчёт в `drift_personal_graph_repository.dart`, контракт в `intention_catalog.dart`, выбор, состояние и согласование модели, лист, заголовок, прежняя страница, бенчмарк и тестовая поддержка `answerCatalogQuery`. Контекст на голове: `_DriftIntentionCatalogEntrySnapshot.matches`, `IntentionCatalogMutation`, `intention_search_list.dart`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверены все семь коммитов диапазона и все 25 изменённых путей. Каждая задача 2.1–2.6 привязана к единице обзора. Коммит bf68c782d5a09c7d5cadeafdcdcbb120722debe6 меняет только `task-profiles.md`, а отметки `tasks.md` — планирующие свидетельства.

**U1.** `_countTypesByScope` считает четыре агрегата одним запросом с теми же условиями исключения, тегов и названия и без условия охвата. `drift_intention_catalog_test.dart` проверяет числа и общее количество при каждом охвате и готовности, те же строки порции и то же число чтений. Бенчмарк с 40 замерами дал в коммите fd9046c744d62fcfda51cdf360067b3db9380528 p95 от 21 до 22 мс для `totalOnly` и от 9 до 11 мс для `byScopeAndType` при бюджете 100 мс. Бенчмарк диапазона не покрывает фильтр названия, а каталог теперь всегда читает матрицу. Поэтому на одноразовой копии головы случаи `shortFilter` временно запрошены с `byScopeAndType`: p95 от 11 до 25 мс при 20 замерах. Результат только сравнительный (статус `smoke`), но бюджет не под угрозой.

**U2.** `IntentionScopeAvailability` заменяет открытый охват в выборе, `changeScope` не разбирает назначение. `IntentionTypeNotOffered` и `requestsTypeCounts` в `lib`, `test` и `benchmark` не осталось. Прежняя страница не вызывает `changeType` и `resetShowParameters`, значит, остаётся с типом «Все» и прежней готовностью запроса. Комментарий `intention_catalog_page.dart` о том, что каталог не предлагает порядок по названию, остаётся верным до фазы 4.

**U3.** `_mapPage` принимает порцию, только если вид чисел совпадает с запросом, а `totalCount` равен числу текущих охвата и готовности. `totalCount` и ячейки матрицы согласуются по одним снимкам, поэтому после поправки не расходятся. Снимки вне текущих охвата и типа учитываются, перенос между охватами меняет две ячейки, отрицательные числа и действия сверх всех ведут к `_restartFromFirstPage`. Пакеты до первой порции идут тем же `_applyPackage`. Пока выдача получается и после отказа, лист чисел не берёт: `isLoading: false` и подтверждённое состояние. На одноразовой копии проверена чувствительность тестов группы «числа охватов и типов»: снятие условия архивного состояния ячейки уронило 2 из 4 тестов, замена `withAnyScopeAndReadiness()` исходным запросом — 3 из 4.

**U4.** `_restoreInitialShowParameters` — единственное место начальных параметров. Его используют сброс и смена поколения графа, вторая дополнительно очищает фильтры. Тесты проверяют сценарии задачи: один новый запрос, сохранение фильтра и условия, отсутствие действия в начальном состоянии, начальные значения выбора и запроса после замены графа. Ожидания `show_and_sort_sheet_test.dart` не изменились, поменялся только помощник порции.

**U5.** `.g.dart` обновил хэш провайдера. Сообщение коммита feb0116dd7bb69866376b4ef3ae7eabde6efafef перечисляет проверки без `mise run check`, поэтому полную проверку выполнил этот обзор.

**Отказ при первом запуске.** В первом запуске `mise run check` упал `test/graph/data/drift_graph_replacement_process_durability_test.dart`: `TimeoutException: Процесс замены не достиг точки mid_insertion.` Диапазон этот тест и замену графа не меняет. Отдельный запуск файла прошёл за 14 секунд, повторный полный `check:process-tests` на той же голове прошёл 18 из 18. Причину таймаута этот обзор не установил. Единого непрерывного зелёного запуска `mise run check` нет: зелёны все его части по отдельности на одной голове. Проверки на устройстве не выполнялись.

Безопасность: новых внешних входов нет, агрегаты строятся выражениями Drift с параметрами, данные и схема не меняются. Отклонение от правил процесса: тело коммита dfdc85ff66108529b6d1136dd9e11ed12e18fa42 написано по-русски вопреки требованию английских сообщений. История не переписывается, поведения это не меняет, поэтому находкой не записано.

Задачи фаз 3 и 4 обязательствами диапазона не считались.
