# OpenSpec Implementation Review: introduce-actions-and-intention-kinds

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.20–2.30 в целом реализованы, как требуют их критерии, и `mise run check` на `b8c45c8b` проходит. Неустранённых находок нет. Перегенерацию `.g.dart` провайдеров экрана пути и поиска участника, без которой `mise run codegen-check` падает, теперь ведёт задача 2.31 фазы 2. Сохранение подтверждённых чисел половин при повторе после отказа чтения пути и структурную гарантию данных переключателя черновика в загрузке и после отказа ведёт задача 2.32 фазы 2. Удаление полезной нагрузки `RelationBatchAdded.relations` без потребителя и единый разбор исхода добавления связей в модели поиска участника ведёт задача 2.33 фазы 2. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** c0a5b10d13286e72f9849647160ba9ba22031b1c
- **Base commit:** c0a5b10d13286e72f9849647160ba9ba22031b1c
- **Reviewed head:** b8c45c8b16c52494e1ebf9e447c6bae70bfac98a
- **Target commits:** ["393b0b5b99e23d81db575e8e0407fa2e980b9ebc", "dcf46b20d38549649f33f41eb6eaa35bd4891af9", "e7fc870a8df42ccd07a03531e34be0a325ce3784", "990010aa59a9d7315601eecd806e5f221befea56", "f349a2aabc42adfa77ee0a87a9e137080edd3c4c", "2cb511e0cd7a6ebfac31dab66004eafe3ae0ff64", "b8bc7f68ae98d55a1e972889a3a1f43a139aa7bb", "d3a82d8e0cf0505071e99b7e2927484e3bc4b0b4", "a0b9160f23987cce5f1b5fb70af13c7b1e86a3a1", "c16e32b1cd17e4f1886f88d2bfa059b7fce232aa", "196a3e388620cb9ce04fed6cb5a3c9a8d9fbe8f4", "b8c45c8b16c52494e1ebf9e447c6bae70bfac98a"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/action/presentation/editor/action_editor_state.dart", "lib/src/action/presentation/editor/action_priority_sheet.dart", "lib/src/action/presentation/path/path_page.dart", "lib/src/action/presentation/path/path_view_model.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/design_system/components/badge.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/options_menu.dart", "lib/src/design_system/components/path_builder.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_action_reads.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_purpose.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/picker/intention_picker_row.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "lib/src/intention/presentation/search/intention_row_content.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_purpose.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "lib/src/statistics/presentation/statistics_view_sheet.dart", "openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md", "test/action/presentation/editor/action_editor_state_test.dart", "test/action/presentation/path/path_page_test.dart", "test/action/presentation/path/path_view_model_test.dart", "test/action/presentation/path_start/path_start_picker_page_test.dart", "test/app/action_path_app_flow_test.dart", "test/app/creation_flows_integration_test.dart", "test/app/home_statistics_app_flow_test.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/quick_creation/quick_creation_accessibility_test.dart", "test/design_system/badge_test.dart", "test/design_system/option_row_test.dart", "test/design_system/options_menu_test.dart", "test/design_system/path_builder_test.dart", "test/graph/data/drift_action_path_state_read_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart", "test/intention/presentation/picker/intention_picker_row_test.dart", "test/support/path_candidates_controlled_repository.dart"]
- **OpenSpec change:** introduce-actions-and-intention-kinds
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]

## Reviewed increment

### U1 · Полные проверки проходят после расширения команд действия и меню режима

- **Work items:** ["2.20"]
- **Requirements and scenarios:** ["plan.md Phase 2 Ready to advance: полные проверки проекта"]
- **Affected boundary:** Набор автоматических тестов проекта
- **Implementation target:** ["test/app/home_statistics_app_flow_test.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/quick_creation/quick_creation_accessibility_test.dart"]
- **Applicable constraints and non-goals:** Код `lib/` и поведение приложения не меняются, ожидания тестов не ослабляются.

### U2 · Экран пути: поздний успех замены, доступные имена, переключатель половин и связи из поиска участника

- **Work items:** ["2.21", "2.24", "2.25", "2.26"]
- **Requirements and scenarios:** ["action-paths: Изменение пути существующего действия", "action-paths: Кандидаты следующего намерения", "action-paths: Половины «Нужно» и «Можно» на экране пути", "action-paths: Добавление связей на экране пути", "action-paths: Выход с экрана пути без сохранения"]
- **Affected boundary:** Пользователь экрана пути и экрана «Изменить путь»; общий поиск участника связи
- **Implementation target:** ["lib/src/action/presentation/path/path_page.dart", "lib/src/action/presentation/path/path_view_model.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_purpose.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "lib/l10n/app_en.arb", "lib/l10n/app_ru.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "test/action/presentation/path/path_page_test.dart", "test/action/presentation/path/path_view_model_test.dart", "test/app/action_path_app_flow_test.dart", "test/support/path_candidates_controlled_repository.dart"]
- **Applicable constraints and non-goals:** Принятая операция с графом не зависит от экрана. Поиск участника остаётся общим модулем (ADR-0049): правило `canPop` и поведение для других якорей не меняются. Строки на русском и английском с совпадающими ключами. Файлы локализации и `path_page.dart` общие с U3 и U4.

### U3 · Дизайн-система: области нажатия `PathBuilder`, типы `OptionRow` и шага пути, без `showEndSlot`

- **Work items:** ["2.22", "2.28", "2.29"]
- **Requirements and scenarios:** ["action-paths: Экран пути", "README PathBuilder: раздел Flutter"]
- **Affected boundary:** Компоненты дизайн-системы и их вызывающий код
- **Implementation target:** ["lib/src/design_system/components/path_builder.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/options_menu.dart", "lib/src/action/presentation/editor/action_priority_sheet.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/statistics/presentation/statistics_view_sheet.dart", "lib/src/action/presentation/path/path_page.dart", "test/design_system/path_builder_test.dart", "test/design_system/option_row_test.dart", "test/design_system/options_menu_test.dart"]
- **Applicable constraints and non-goals:** Поведение, доступные имена и внешний вид не меняются. Недопустимые состояния непредставимы (type-safe design).

### U4 · Поиск начала пути предлагает текущий корень с отметкой

- **Work items:** ["2.23"]
- **Requirements and scenarios:** ["action-paths: Поиск начала пути", "action-paths: Сокращение пути и смена корня", "intention-management: Карточка намерения в каталоге и поисках"]
- **Affected boundary:** Пользователь поиска начала пути; запрос каталога намерений и хранилище
- **Implementation target:** ["lib/src/design_system/components/badge.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_purpose.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/picker/intention_picker_row.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "lib/src/intention/presentation/search/intention_row_content.dart", "lib/l10n/app_en.arb", "lib/l10n/app_ru.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "test/action/presentation/path_start/path_start_picker_page_test.dart", "test/action/presentation/path/path_page_test.dart", "test/design_system/badge_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_tag_filter_view_model_test.dart", "test/intention/presentation/picker/intention_picker_row_test.dart"]
- **Applicable constraints and non-goals:** Текущий корень подчиняется тем же правилам охвата и фильтров. Исключение в вычислении вклада (`contribution_reachability.dart`) не меняется. Строки на русском и английском.

### U5 · Диагностика чтения пути черновика различается видом операции

- **Work items:** ["2.27"]
- **Requirements and scenarios:** ["action-management: Диагностика действий без пользовательского содержимого"]
- **Affected boundary:** Диагностика слоя данных для разработчика
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository_action_reads.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/graph/data/drift_action_path_state_read_test.dart"]
- **Applicable constraints and non-goals:** События не содержат идентификаторов, путей, названий, параметров запросов и исходных исключений. Чтение панели остаётся `actionRead`.

### U6 · Лист нового действия снова создаёт действие после восстановления пути

- **Work items:** ["2.30"]
- **Requirements and scenarios:** ["action-management: Подтверждённые результаты и безопасные ошибки действия", "action-paths: Допустимый путь действия"]
- **Affected boundary:** Пользователь листа нового действия; наблюдение состояния пути черновика
- **Implementation target:** ["lib/src/action/presentation/editor/action_editor_state.dart", "test/action/presentation/editor/action_editor_state_test.dart", "test/app/creation_flows_integration_test.dart"]
- **Applicable constraints and non-goals:** Подтверждённый конфликт снимается актуализацией, а не повтором неизменённого черновика. Экран пути, `path_state.dart` и спеки не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Каждому блоку или группе пересечения дан свежий изолированный рецензент `implementation-decision-review` с нейтральным описанием намерения, точными `c0a5b10d…b8c45c8b` и полным списком путей без `openspec/`. U1 — sonnet, U5 — sonnet, U6 — opus. U2, U3 и U4 делят `path_page.dart`, `path_page_test.dart` и файлы локализации, поэтому образуют одну группу с общей целью из 38 путей и одним совмещённым описанием. Её покрыли два рецензента opus с разными основными областями: U2 и U3+U4. Каждый подтвердил полное покрытие своей области, вместе области покрывают все 38 путей. |
| OpenSpec conformance | Complete | Координатор сверил критерии и проверки задач 2.20–2.30 с диффом каждого коммита и с добавленными тестами. Команды запущены в этом рабочем дереве (`HEAD` = `b8c45c8b`, дерево чистое, кроме отчёта): `mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --no-interactive` — valid. `mise run check` — EXIT 0: формат, `flutter analyze` без замечаний, 4063 обычных теста и 18 процессных тестов прошли. `mise run codegen-check` — EXIT 1 (несогласованные хэши `.g.dart`, работу ведёт задача 2.31); запущен при отложенном отчёте и восстановленном отчёте после, перегенерированные файлы возвращены к `b8c45c8b`. APK не собирался: это вывод готовности фазы, а не ревью. |
| Code quality | Complete | Координатор применил линзы корректности, читаемости, архитектуры, безопасности и производительности ко всем путям поставки. Навык `code-review-and-quality` не загружался, линзы применены напрямую. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Целевой диапазон — 12 коммитов и 50 путей. Два пути — свидетельства планирования: `task-profiles.md` (профили задач 2.20–2.30, коммит `393b0b5b`) и `tasks.md` (отметки выполнения). Остальные 48 распределены по блокам U1–U6. Каждая задача 2.20–2.30 сопоставлена со своим коммитом из данных процесса и с блоком. Кода вне задач не найдено. Прежний отчёт (`cf5ec2b0…aad60bed`) не содержал неустранённых находок и принятых рисков, поэтому переносить нечего.

Проверено без находок. Помощники `action` двух app-тестов исчерпывающе перечисляют варианты `ActionCommand` без ветви `_`, а строки меню режима ищутся внутри `BottomSheet`. `_save` закрывает экран пути только при `ModalRoute.of(context)?.isCurrent` и берёт черновик сопоставлением с `LoadedPathDraft`. App-тест отпускает замену во время анимации ухода, и панель после этого остаётся на месте. Нажимаемые области корня, промежуточного намерения и «Выберите причину» занимают всю строку, тест компонента измеряет их границы. Текущий корень предлагается в поиске начала пути с отметкой первой в линии меток и в доступном имени. `excludedIntentionId` удалён из запроса, хранилища и тестов, исключение в `contribution_reachability.dart` не тронуто. Доступные имена кандидата и «Добавить» называют последнее намерение и половину на ru и en с совпадающими ключами. Переключатель половин показан во время загрузки и после отказа, без чисел до первого подтверждённого результата; сохранение чисел при повторе после отказа чтения пути ведёт задача 2.32. Исход добавления связей приходит якорю пути из future принятой команды и не теряется при уходе из поиска. Половина при этом не переключается, а `mounted` экрана пути проверяется. Чтение пути черновика пишет отдельное событие `actionPathStateRead` с прежними этапом, исходами и категориями без пользовательских данных. Конфликт создания снимает только подтверждённое целое состояние пути. Целостность считается тем же правилом `firstWholeSegment`, что и проверка команды создания. `OptionRow` и `PathBuilder` больше не содержат `icon!` и `relation!`, а `showEndSlot` удалён.

Отклонено: обёртки `OptionRowIcon` и `OptionRowMark` в вызывающем коде нужны. Константный конструктор не может сам построить вариант из параметра, а сохранять `const OptionRow(...)` у вызывающих нужно.
