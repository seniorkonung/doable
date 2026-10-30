# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Фаза 3 достигла цели: сценарии проходят каталог через `test/support/intention_catalog_controls.dart`, а `lib/` не менялся. Остаётся одна находка низкой важности: проверка доступности берёт ожидаемое название поля из той же проверяемой семантики.

## Review target

- **Baseline ref:** 6a3f6404ca0e4fd5d319bdb9008b7c0e5cf7ee51
- **Base commit:** 6a3f6404ca0e4fd5d319bdb9008b7c0e5cf7ee51
- **Reviewed head:** f30e1fe1d9df7991bcbc29c350340970c8dbeff3
- **Target commits:** ["c9e50eae130d92a53f830304c84b1944c106e086", "a2021f2a97bdc402a29a1b9f2d76148178f18e4d", "191d8481affbef3b54181550b60720ad68368b6d", "db8706747831babf04df5e7e465ea7a3bf954e3a", "344e3825cdfb68b60d86463e442c91e44171a437", "c32d897587d8ae2f191e7b86490021076f99db0b", "e43bc7c0fc9367ce9bae8446f8705219e309ac1c", "f30e1fe1d9df7991bcbc29c350340970c8dbeff3"]
- **Reviewable paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/app/creation_flows_integration_test.dart", "test/app/graph_import_app_flow_test.dart", "test/app/graph_restore_app_flow_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/intention_tag_search_app_flow_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_graph_generation_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/tag_app_flow_test.dart", "test/app/tag_assignment_app_flow_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/support/intention_catalog_controls.dart", "test/tag/presentation/tag_accessibility_test.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Сценарии приложения управляют каталогом через общие шаги

- **Work items:** ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7"]
- **Requirements and scenarios:** ["plan.md: Phase 3 / Ready to advance", "design: решение 10, сценарные шаги каталога"]
- **Affected boundary:** Авторы сценарных тестов и защита от регрессий, которую эти тесты дают приложению. Поведение приложения не меняется.
- **Implementation target:** ["test/app/creation_flows_integration_test.dart", "test/app/graph_import_app_flow_test.dart", "test/app/graph_restore_app_flow_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/intention_tag_search_app_flow_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_graph_generation_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/tag_app_flow_test.dart", "test/app/tag_assignment_app_flow_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/support/intention_catalog_controls.dart", "test/tag/presentation/tag_accessibility_test.dart"]
- **Applicable constraints and non-goals:** `lib/` не меняется. Шаги действуют и наблюдают через интерфейс, а не через модель. Ожидания сценариев прежние, кроме условий по тегам, которые новая страница показывает только числом. Новых сценариев нет, проверки самой прежней страницы и её частей остаются до фазы 4.
- **Excluded change scope:** Переключение шагов на новую страницу, управление типом и направлением сортировки, перестройка проверок прежней страницы — фаза 4.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер (Sonnet, high, `implementation-decision-review`) проверил U1 по 23 путям тестов. Планирующие артефакты, история коммитов и прежний отчёт ему не передавались. Результат: `Changes needed`, покрытие полное. |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве на голове f30e1fe1d9df7991bcbc29c350340970c8dbeff3; незакоммиченным был только этот отчёт. `mise run check` прошёл с первого запуска, код 0: `dart format`, `test/tool`-проверки и `flutter analyze` без замечаний, 3848 обычных тестов, 18 тестов процессов. `mise exec --no-deps -- openspec validate redesign-intention-catalog --strict --json` — valid. Поиск из задачи 3.7 нашёл ключи и строки только в `test/support/intention_catalog_controls.dart` и пяти разрешённых файлах проверок прежней страницы. `git diff --quiet d6de1fac77d46e512fde7ff981ac01e2aa535b6f f30e1fe1d9df7991bcbc29c350340970c8dbeff3 -- lib` — код 0. |
| Code quality | Complete | Навык `code-review-and-quality` применён ко всем 23 путям: полный дифф каждого сценария сверен с базой, общий файл шагов прочитан целиком на голове. |

## Findings

### F2 · Low — Проверка доступности берёт ожидаемое название поля из проверяемой семантики

- **Evidence:** `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart:517-535`: `titleFieldName` читается из семантики `EditableText` поля и затем ищется в обходе той же семантики. На базе ожидалось `l10n.catalogFilterLabel`. Так требует критерий задачи 3.4. При этом шаг `intentionCatalogTitleFieldLabel` уже даёт подпись из локализации и используется в `intention_editor_page_test.dart`.
- **Evidence revisions:** ["f30e1fe1d9df7991bcbc29c350340970c8dbeff3"]
- **Impact:** Здесь проходит любая непустая подпись поля, и проверка стала длиннее на чтение семантики через `EditableText`. Неверную подпись сейчас ловит `test/intention/presentation/intention_tag_search_accessibility_test.dart:92`, но это проверка прежней страницы, которая перестраивается в фазе 4.
- **Required outcome:** Ожидаемое название поля в сценарии берётся из источника, который не зависит от проверяемой семантики, а смена подписи поля по-прежнему меняет только общий файл шагов.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["tasks.md: 3.4", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart"]

## Review coverage

Проверены все восемь коммитов диапазона и все 25 изменённых путей. Каждая задача 3.1–3.7 привязана к U1: 3.1 — a2021f2a97bdc402a29a1b9f2d76148178f18e4d, 3.2 — 191d8481affbef3b54181550b60720ad68368b6d, 3.3 — db8706747831babf04df5e7e465ea7a3bf954e3a, 3.4 — 344e3825cdfb68b60d86463e442c91e44171a437, 3.5 — c32d897587d8ae2f191e7b86490021076f99db0b, 3.6 — e43bc7c0fc9367ce9bae8446f8705219e309ac1c, 3.7 — f30e1fe1d9df7991bcbc29c350340970c8dbeff3. Коммит c9e50eae130d92a53f830304c84b1944c106e086 меняет только `task-profiles.md`, а отметки `tasks.md` — планирующие свидетельства. Файл `app_shell_unnamed_page_scenarios.dart` не назван в предполагаемых файлах задачи 3.2, но без его правки сценарий сломался бы: `_summary` теперь ищет только строки экранов выбора.

**Общие шаги.** Каждый публичный шаг и параметр имеет вызывающего, все шаги из критериев задач 3.1, 3.2 и 3.4 есть с заданными сигнатурами. Шаги читают значения через интерфейс и к модели не обращаются. Таблица `_orderLabels` не содержит порядка по названию, но прежняя страница его не предлагает, а новую страницу этот файл учитывает в фазе 4.

**Сохранность проверок.** Дифф каждого сценария сверен с базой. Там, где название условия заменено числом, состав выдачи или отметки панели подтверждают тег и надобность либо сценарий проверяет только сброс условия заменой графа. В `tag_app_flow_test.dart` подпись условия по-прежнему читается через `_conditionLabel`. Сравнение строк в `app_shell_back_test.dart` стало строже: теперь оно учитывает подпись тегов и прямоугольник.

**Замечания независимого ревьюера, которые не стали находками.** Фиксированные `pump` в шагах идут по тестовым часам, покрывают анимацию меню и панели, а выдачу не ждут, как и требует задача 3.1. Сценариев, которым нужно промежуточное состояние сразу после выбора, нет. Ожидание `hitTestable` после закрытия панели ни один сценарий не делает зависимым от полного удаления панели. Замена проверок в `app_shell_test.dart` и чтение `row.title` следуют задачам и не теряют проверку: подписи и строки проверяют `intention_catalog_page_test.dart` и `intention_summary_view_test.dart`. Приведение к `TagId` — принятая в тестах запись. Литералы `Теги: …` в `tag_app_flow_test.dart` были на базе, а сценарий идёт только в русской локали.

Безопасность: диапазон меняет только тесты и планирующие файлы, новых входов, данных и зависимостей нет. Задачи фазы 4 обязательствами диапазона не считались. Проверки на устройстве не выполнялись и для этой фазы не нужны: поведение приложения не менялось.
