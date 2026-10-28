# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Все тринадцать целевых коммитов и задачи 3.1–3.13 проверены. Экран изменения, политика «успех без сообщения», занятость после возвращения и удаление встроенной правки в основном соответствуют фазе 3, полная проверка проекта проходит. Остаются две находки Medium. В поле названия можно ввести перенос строки (F6). Заголовок панели экрана перекрывается кнопкой «Сохранить» (F7). Ещё две находки Low: область нажатия названия в шапке меньше `tap-min` (F8), а отказ сохранения может появиться вне видимой части экрана (F9). Ранее принятый планировочный риск AR1 сохранён.

## Review target

- **Baseline ref:** 9c608971ba1c46949a1c57f40ca8856695585e0e
- **Base commit:** 9c608971ba1c46949a1c57f40ca8856695585e0e
- **Reviewed head:** 5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c
- **Target commits:** ["ab45934a550b21123321ac02d41ca2fe03e21e99", "d28af0af17dd71871845c8a9c95c05403a70641c", "8fd95c31bf1ffc6d50848b48c928fcbb257fcc09", "9d7b39e0b7492d64331bf17065deacc86a5b41fb", "2eea27e6dd34088ec43bdb07b2358bd35737051a", "6901c5c01bbb1859be6dc95f4cc7b64e4aa0c73c", "2bb02491a6c74e5c57252df6c68cdab988325ebc", "1b10ade707bc7050925cfa2d8de6ebd5caa0998b", "a380ac313b93eb9386f2b5b05c81929f7283c3cd", "e8e2119d3c2030e5678a40f18fe4f6b93c3a9ff5", "e9bb34fb6110b4d9454c699b9bd933129470d71a", "dbc2621192471829d5fc2cd70687b4188f115a09", "5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/design_system/components/button.dart", "lib/src/design_system/components/confirm_dialog.dart", "lib/src/design_system/components/page_head.dart", "lib/src/design_system/components/text_field.dart", "lib/src/design_system/components/top_bar.dart", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/intention/domain/intention_text.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "lib/src/intention/presentation/details/intention_details_view_model.g.dart", "lib/src/intention/presentation/edit/intention_edit_failure_message.dart", "lib/src/intention/presentation/edit/intention_edit_page.dart", "lib/src/intention/presentation/edit/intention_edit_state.dart", "lib/src/intention/presentation/edit/intention_edit_view_model.dart", "lib/src/intention/presentation/edit/intention_edit_view_model.g.dart", "lib/src/tag/presentation/editor/tag_sheet.dart", "openspec/changes/redesign-intention-page/tasks.md", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/quick_creation/quick_creation_launcher_test.dart", "test/app/quick_creation/quick_creation_launcher_test_support.dart", "test/design_system/button_test.dart", "test/design_system/confirm_dialog_test.dart", "test/design_system/page_head_test.dart", "test/design_system/text_field_test.dart", "test/design_system/top_bar_test.dart", "test/graph/presentation/graph_operation_message_plan_test.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/intention/presentation/details/intention_details_head_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/details/intention_details_view_model_test.dart", "test/intention/presentation/edit/intention_edit_page_test.dart", "test/intention/presentation/edit/intention_edit_view_model_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/support/intention_creation_origin.dart", "test/support/intention_edit_screen.dart", "test/support/ordinary_page_test_app.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Успех изменения названия и описания без сообщения

- **Work items:** ["3.1"]
- **Requirements and scenarios:** ["intention-management: Независимость принятой изменяющей операции от экрана", "ADR-0046"]
- **Affected boundary:** Координатор команд графа и общая поверхность сообщений результатов
- **Implementation target:** ["lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "test/graph/presentation/graph_operation_message_plan_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart"]
- **Applicable constraints and non-goals:** Протокол ADR-0012 для отказа сохраняется; создание и удаление сохраняют политику по умолчанию; готовность, архивирование и восстановление не меняются до фазы 4.

### U2 · Компоненты дизайн-системы для экрана изменения и шапки

- **Work items:** ["3.2", "3.3", "3.4", "3.8"]
- **Requirements and scenarios:** ["design: решение 11", "intention-management: Экран изменения намерения"]
- **Affected boundary:** Потребители компонентов дизайн-системы и пользователи экранного диктора в обеих темах и при увеличенном тексте
- **Implementation target:** ["lib/src/design_system/components/text_field.dart", "lib/src/design_system/components/button.dart", "lib/src/design_system/components/top_bar.dart", "lib/src/design_system/components/confirm_dialog.dart", "lib/src/design_system/components/page_head.dart", "lib/src/tag/presentation/editor/tag_sheet.dart", "test/design_system/text_field_test.dart", "test/design_system/button_test.dart", "test/design_system/top_bar_test.dart", "test/design_system/confirm_dialog_test.dart", "test/design_system/page_head_test.dart"]
- **Applicable constraints and non-goals:** Компоненты остаются представлением по ADR-0029/0030 и следуют README в `context/doable-design-system/components/`; варианты добавляются только с потребителем. Режим сохранённого текста поля, кнопка-иконка справа в панели и слоты архива в шапке не входят.

### U3 · Экран изменения намерения и вход в него со страницы

- **Work items:** ["3.5", "3.6", "3.7", "3.8", "3.9", "3.12"]
- **Requirements and scenarios:** ["intention-management: Экран изменения намерения", "intention-management: Независимость принятой изменяющей операции от экрана", "app-navigation: Панель на обычных страницах", "app-appearance: Светлое и тёмное оформление по системной настройке", "design: решения 3 и 5"]
- **Affected boundary:** Пользователь страницы намерения и экрана «Изменить намерение»; модель подробных данных и сессия экрана изменения
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/intention/domain/intention_text.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "lib/src/intention/presentation/details/intention_details_view_model.g.dart", "lib/src/intention/presentation/edit/intention_edit_failure_message.dart", "lib/src/intention/presentation/edit/intention_edit_page.dart", "lib/src/intention/presentation/edit/intention_edit_state.dart", "lib/src/intention/presentation/edit/intention_edit_view_model.dart", "lib/src/intention/presentation/edit/intention_edit_view_model.g.dart", "test/intention/presentation/details/intention_details_head_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/details/intention_details_view_model_test.dart", "test/intention/presentation/edit/intention_edit_page_test.dart", "test/intention/presentation/edit/intention_edit_view_model_test.dart", "test/support/ordinary_page_test_app.dart"]
- **Applicable constraints and non-goals:** Экран-задача без нижней панели по ADR-0020; отказ проверки поля у поля, остальные на экране, затем оболочке по ADR-0012; вход недоступен при занятости намерения. Вход из описания и параметров, Обзор и меню относятся к фазе 4.
- **Excluded change scope:** Переходы готовности, архивирования, восстановления и удаления сохраняют прежнее предъявление до фазы 4.

### U4 · Сквозные сценарии и навигация после переноса правки

- **Work items:** ["3.10", "3.11", "3.12", "3.13"]
- **Requirements and scenarios:** ["app-navigation: Панель на обычных страницах", "app-navigation: Сброс истории выбором пункта", "quick-creation: Запуск режима поверх текущей страницы", "intention-management: Экран изменения намерения"]
- **Affected boundary:** Сквозные сценарии приложения, матрица страниц навигации, быстрое создание и пакеты тегов
- **Implementation target:** ["test/app/intention_app_lifecycle_test.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/quick_creation/quick_creation_launcher_test.dart", "test/app/quick_creation/quick_creation_launcher_test_support.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/support/intention_creation_origin.dart", "test/support/intention_edit_screen.dart"]
- **Applicable constraints and non-goals:** Сценарии сохраняют прежние ожидания согласования каталога, соседства и параметров; ручная проверка на устройстве за пользователем.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных рецензента по `implementation-decision-review` с нейтральными брифами, без артефактов планирования и истории. Первый проверил U2: 11 путей компонентов и их проверок, полностью прочитанных на head. Второй проверил U1, U3 и U4 вместе, потому что у них общие файлы локализации и проверок: 43 пути. Оба сообщили полное покрытие своих границ, код они не запускали. |
| OpenSpec conformance | Complete | Сверены задачи 3.1–3.13, решения 3, 4, 5, 10, 11 и 14 design, ADR-0046 и сценарии требований «Экран изменения намерения», «Независимость принятой изменяющей операции от экрана», навигации, быстрого создания и оформления. `rg -nw 'beginEditing&#124;cancelEditing&#124;saveChanges&#124;IntentionDetailsEdit&#124;detailsSaved' lib test` и `rg -n 'intention-details-edit' lib test` ничего не нашли. `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json` дал valid. `mise run check` прошёл в рабочей копии на 5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c, совпадающей с HEAD и чистой: format, проверки скриптов, `flutter analyze` без замечаний, 3540 обычных тестов и 18 процессных. Сборка APK и ручная проверка на устройстве в этом обзоре не выполнялись. |
| Code quality | Complete | В контексте координатора применены пять линз `code-review-and-quality` к модели и странице экрана изменения, сообщениям отказа, модели и странице подробных данных, координатору и презентеру, нормализации названия и компонентам. Перекрытие в `TopBar` измерено временным тестом со шрифтом Inter на 360 и 390 при масштабе 1 и 1,3; тест удалён, рабочая копия чистая. |

## Findings

### F6 · Medium — В поле названия экрана изменения можно ввести перенос строки

- **Evidence:** `TextField.multiline` по умолчанию передаёт `maxLines: null` и не задаёт `keyboardType`, `textInputAction` или фильтр ввода (`lib/src/design_system/components/text_field.dart:35-50, 99-105`). Поэтому Flutter выбирает многострочную клавиатуру с клавишей перевода строки для любого вида, и `kind` меняет только стиль. Экран изменения строит название именно так (`lib/src/intention/presentation/edit/intention_edit_page.dart:143-160`). Нормализация названия обрезает только края (`lib/src/intention/domain/intention_text.dart:42-57`), поэтому внутренний `\n` сохраняется. Прежняя встроенная форма была однострочной. Растущее поле названия в панели создания явно задаёт `TextInputType.text` и `TextInputAction.next` (`lib/src/intention/presentation/editor/intention_editor_page.dart:165-172`).
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Impact:** Ввод на экранной клавиатуре или вставка многострочного текста сохраняет название с переносами. Такое название невозможно получить через панель создания, и оно ломает однострочные строки каталога, поисков и панели. Это регрессия по сравнению со встроенной правкой.
- **Required outcome:** В названии на экране изменения жёсткий перенос нельзя ввести ни набором, ни вставкой. Название при этом переносится визуально и растёт. Описание сохраняет ввод переносов. Проверка закрепляет это для названия.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/text_field.dart", "lib/src/intention/presentation/edit/intention_edit_page.dart", "test/design_system/text_field_test.dart", "test/intention/presentation/edit/intention_edit_page_test.dart"]

### F7 · Medium — Заголовок панели экрана изменения перекрывается кнопкой «Сохранить»

- **Evidence:** `TopBar.withButton` центрирует заголовок с постоянным отступом 64 с каждой стороны (`lib/src/design_system/components/top_bar.dart:49, 276-278`) и рисует поверх него кнопку `sm` справа в `space-3` от края (`top_bar.dart:348-358`). Ширина кнопки зависит от подписи и масштаба. Временный тест со шрифтом Inter для «Изменить намерение» и «Сохранить» показал перекрытие плашки и заголовка. На ширине 360 при масштабе 1: заголовок 90–270, плашка 240–348. На 390 при масштабе 1: заголовок до 284,6, плашка от 270,5. При масштабе 1,3 перекрытие достигает 52–66 px. `test/design_system/top_bar_test.dart:379-401` закрепляет прямоугольник заголовка 64–326 рядом с плашкой, а проверка при масштабе 2 перекрытие не проверяет. Отступ 64 взят из README `TopBar` и критерия задачи 3.3.
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Impact:** На обычных телефонах на русском языке заголовок экрана «Изменить намерение» частично закрыт кнопкой «Сохранить», а при увеличенном тексте закрыт сильнее. Видимый заголовок маршрута теряет читаемость.
- **Required outcome:** Заголовок панели с кнопкой справа не пересекается с ней при любой подписи и масштабе текста и обрезается многоточием до её края. Компонентные проверки закрепляют отсутствие пересечения.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["tasks.md 3.3", "lib/src/design_system/components/top_bar.dart", "test/design_system/top_bar_test.dart"]
- **Decision needed:** Правило README «по центру, не шире панели без 64 с каждой стороны» нельзя выполнить без перекрытия. Нужно выбрать раскладку: симметричный отступ по ширине кнопки, сохраняющий центр, или смещение заголовка от кнопки.

### F8 · Low — Область нажатия названия в шапке ниже `tap-min`

- **Evidence:** `PageHead` оборачивает в `InkWell` только `Text` названия (`lib/src/design_system/components/page_head.dart:26-45`). Поля 2 и 6 стоят снаружи, поэтому однострочное название `page-title` даёт область высотой 30. `test/design_system/page_head_test.dart:41-46` это закрепляет. README основ требует у кнопки область нажатия не меньше `tap-min` при любой видимой высоте (`context/doable-design-system/README.md:76`), а README `PageHead` называет название кнопкой.
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Impact:** Единственный вход в правку в фазе 3 — цель высотой 30 вместо 44. В неё труднее попасть, особенно пользователям с нарушениями моторики.
- **Required outcome:** Область нажатия названия не ниже `tap-min`, при этом видимые поля шапки и перенос названия не меняются. Компонентная проверка это закрепляет.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/page_head.dart", "test/design_system/page_head_test.dart"]

### F9 · Low — Отказ сохранения может появиться вне видимой части экрана изменения

- **Evidence:** Общий отказ вставляется как `Notice` в начало `SingleChildScrollView` (`lib/src/intention/presentation/edit/intention_edit_page.dart:117-142`). Отказ названия рисуется под первым полем. «Сохранить» стоит в неподвижной верхней панели, поэтому её можно нажать из любой позиции прокрутки. Проверка раскладки при масштабе 2 с открытой клавиатурой показывает, что поле описания выше видимой части (`test/intention/presentation/edit/intention_edit_page_test.dart:260-290`). При вводе описания прокрутка уводит начало экрана. Свидетельство кадра подтверждает предъявление только в видимой области, поэтому право остаётся у экрана, пока пользователь не прокрутит вверх.
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Impact:** При увеличенном тексте или длинном описании отказ хранилища или проверки названия не виден и не объявляется. Пользователь видит только снова доступную «Сохранить». Если он затем выберет «Отменить», сообщение придёт уже после ухода.
- **Required outcome:** Отказ, пришедший при открытом экране изменения, становится видимым и доступным диктору без ручной прокрутки. Проверка закрепляет это для прокрученного экрана.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/edit/intention_edit_page.dart", "test/intention/presentation/edit/intention_edit_page_test.dart"]

## Accepted risks

### AR1 · Оформление замены сохраняемых требований через REMOVED + ADDED

- **Evidence:** `openspec/changes/redesign-intention-page/review.md:17` фиксирует принятый риск замены требований о готовности и согласованности счётчиков. В delta-спецификации связей сохранённые правила счётчиков перенесены в «Согласованность счётчиков с подтверждёнными изменениями графа», а прежний сценарий массового удаления исключён. Причина оформления записана в блоке REMOVED. Проверка этой фазы подтверждает сохранение остальных правил счётчиков.
- **Evidence revisions:** ["6609baa3cc57693c575e9b746435166b1f3ca573"]
- **Potential impact:** Преемственность сохраняемого поведения менее очевидна: его оформление выглядит как удаление и новое добавление требования.
- **Acceptance rationale:** Пользователь ранее принял оформление из-за ограничения OpenSpec на исключение устаревших сценариев через MODIFIED. Возвращение сценария убираемой операции противоречит согласованному изменению.
- **Scope and assumptions:** Только оформление двух замен требований внутри этого изменения; для фазы 1 применима часть о счётчиках. Остальные сохраняемые правила остаются обязательными. Риск не разрешает ослаблять реализацию или тесты.
- **Reopen when:** OpenSpec позволит исключать устаревшие сценарии через MODIFIED либо новые требования перестанут сохранять остальные действующие правила.
- **Acceptance authority:** Ранее зафиксированное решение пользователя в `openspec/changes/redesign-intention-page/review.md:24`: «Принять риск оформления REMOVED + ADDED из-за ограничения инструмента; зафиксировать причину в delta-спецификациях и отчёте».
- **Originating finding:** F4
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed


## Review coverage

Независимые проверки решений. Брифы содержали только проблему, результат, границу, обязательные ограничения и пути. Рецензенты проследили приём команд, гейт, порядок публикации и выдачу права в координаторе. Они проверили уход во время сохранения, успех без сообщения и защиту `_closeRoute` от позднего результата. Также проверены геометрия и доступность компонентов, исходы ответов диалога отмены и сохранение вида ошибки в листе тега.

Сверка с OpenSpec. Для каждой задачи 3.1–3.13 найдены реализация и проверки. Экран-задача входит в матрицу навигации с `panel: false`. Сценарии быстрого создания и сброса истории очищены от встроенной правки, тексты добавлены на обоих языках. Строки встроенной правки удалены, `detailsCancelEditAction` и `detailsOperationRunning` остаются у других потребителей. Блок тегов читает занятость у координатора при перестройке, поэтому `tag_assignments_section.dart` не требовал изменений по 3.9. Будущие фазы 4–6 не считались обязательствами диапазона.

Качество. Сила типов: закрытые варианты `IntentionCommandCompletion` разделяют предъявляемое завершение и успех изменения. Ветвь `(update, _)` в `_successFor` презентера недостижима по типу завершения. Выполняющийся токен и опубликованное право освобождаются при уходе. Безопасности, данных и миграций диапазон не касается.

Не выполнено: сборка APK, сравнение с макетом и ручные проверки на устройстве из 3.13: курсор, рост описания, клавиатура, вопрос об отмене и смена темы. Они остаются за пользователем.
