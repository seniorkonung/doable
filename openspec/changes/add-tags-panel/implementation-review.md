# OpenSpec Implementation Review: add-tags-panel

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Фаза 2 выполнена по существу. Со страницы намерения открывается панель тегов, где теги отмечаются и снимаются нажатием и создаются в листе «Новый тег». Операции тегов объявляют только отказ, и он виден поверх открытого листа. Полные проверки проекта и валидация OpenSpec проходят. Независимая проверка, сверка с OpenSpec и проверка качества оставили пять активных низких замечаний: о доступности строки тега, недостижимых ветках, пробелах в проверках и типизации листа. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 65594f4ac5709aef752a3bfeb5c797f7655d4f07
- **Base commit:** 65594f4ac5709aef752a3bfeb5c797f7655d4f07
- **Reviewed head:** b342300ac038f007edff58665e3684838b9407a2
- **Target commits:** ["daed15c9ceb350b4dc927f355b8ab01be801dce4","ff762f9c2ebafb8f7c4bf8d250cfbd67af64ce9c","15db179b9ca3e9a515fa6f90a5d0f3c9e907510c","8045ea716a4abd0c3454a085b7faa1d560414ffe","c2bcb774c17615a43d11fe9721f503bfe6bc50eb","95d9726d1a08272984d7467e672b6d602c829a91","86014da79fac70e155352b671e2e27141a950650","67603fc37fa210861ac208f6518108a2cabd2f87","c1c97918598dd99ddf894720f045137d6744902a","e20388df102159a38356f656603fe55bb4943c4a","98c6da9bb260ac1095927f8db29611fb2f275e17","b83ea5da28073f136d172bd7ef33282011c3c538","ff839f0da72ceba1eb0ab79622b1dc7b9eb59642","ac977c4749f46a6b0794529c7ae32a7e8b7e8d78","67bbf49aed01ed51435f5bb2353a11937897cd06","bb83f419f13e12ed67995c81cdeac56bf94709c6","8d33231ea0a72eabd7433131be90526f903f3612","29c2c2001185f177d818fe22a27b9a572911cd5f","6f40845212ca1ba65407beb58c8df316e927ac1c","b342300ac038f007edff58665e3684838b9407a2"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/button.dart","lib/src/design_system/components/empty_state.dart","lib/src/design_system/components/list_state.dart","lib/src/design_system/components/search_field.dart","lib/src/design_system/components/sheet.dart","lib/src/design_system/components/tag_create_row.dart","lib/src/design_system/components/tag_row.dart","lib/src/design_system/components/text_field.dart","lib/src/design_system/doable_icon.dart","lib/src/design_system/icons/README.md","lib/src/design_system/icons/assets/chevron_down.svg","lib/src/design_system/icons/assets/clear.svg","lib/src/design_system/icons/assets/plus_small.svg","lib/src/design_system/icons/assets/search.svg","lib/src/graph/application/graph_command_coordinator.dart","lib/src/graph/application/graph_command_coordinator.g.dart","lib/src/graph/presentation/graph_operation_presenter.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/tag/domain/tag_name.dart","lib/src/tag/presentation/assignments/tag_assignments_section.dart","lib/src/tag/presentation/catalog/tag_catalog_filter.dart","lib/src/tag/presentation/catalog/tag_catalog_view.dart","lib/src/tag/presentation/editor/tag_editor_page.dart","lib/src/tag/presentation/editor/tag_editor_state.dart","lib/src/tag/presentation/editor/tag_editor_view_model.dart","lib/src/tag/presentation/editor/tag_editor_view_model.g.dart","lib/src/tag/presentation/editor/tag_sheet.dart","lib/src/tag/presentation/panel/tags_panel.dart","lib/src/tag/presentation/panel/tags_panel_context.dart","lib/src/tag/presentation/panel/tags_panel_state.dart","lib/src/tag/presentation/panel/tags_panel_view_model.dart","lib/src/tag/presentation/panel/tags_panel_view_model.g.dart","openspec/changes/add-tags-panel/tasks.md","test/app/intention_creation_sheet_failure_integration_test.dart","test/app/intention_creation_sheet_integration_test.dart","test/app/intention_creation_sheet_tags_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/tag_app_flow_test.dart","test/app/tag_app_lifecycle_test.dart","test/app/tag_assignment_app_flow_test.dart","test/app/tag_assignment_app_lifecycle_test.dart","test/app/tag_navigation_app_lifecycle_test.dart","test/design_system/button_test.dart","test/design_system/doable_icon_test.dart","test/design_system/empty_state_test.dart","test/design_system/goldens/doable_icons.png","test/design_system/list_state_test.dart","test/design_system/search_field_test.dart","test/design_system/sheet_test.dart","test/design_system/tag_create_row_test.dart","test/design_system/tag_row_test.dart","test/design_system/text_field_test.dart","test/graph/application/graph_command_coordinator_tag_test.dart","test/graph/presentation/graph_operation_presenter_test.dart","test/graph/presentation/operation_failure_presentation_test.dart","test/intention/presentation/details/intention_details_tags_test.dart","test/support/tag_catalog_test_repository.dart","test/tag/presentation/assignments/tag_assignments_section_test.dart","test/tag/presentation/catalog/tag_catalog_delete_test.dart","test/tag/presentation/catalog/tag_catalog_draft_lifecycle_test.dart","test/tag/presentation/catalog/tag_catalog_draft_search_scenarios.dart","test/tag/presentation/catalog/tag_catalog_filter_test.dart","test/tag/presentation/catalog/tag_catalog_page_test.dart","test/tag/presentation/catalog/tag_catalog_search_page_test.dart","test/tag/presentation/editor/tag_editor_page_test.dart","test/tag/presentation/editor/tag_editor_view_model_test.dart","test/tag/presentation/editor/tag_sheet_test.dart","test/tag/presentation/panel/tags_panel_test.dart","test/tag/presentation/panel/tags_panel_view_model_test.dart","test/tag/presentation/tag_accessibility_test.dart"]
- **OpenSpec change:** add-tags-panel
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-tags-panel/tasks.md"]

## Reviewed increment

### U1 · Раскрываемый лист и сообщения общей поверхности поверх листов с операциями

- **Work items:** ["2.1", "2.2"]
- **Requirements and scenarios:** ["tag-management: Панель тегов", "tag-management: Согласование панели тегов с подтверждёнными изменениями", "design: решения 7 и 9", "ADR-0041", "ADR-0042"]
- **Affected boundary:** Лист модуля основ над корневым навигатором и его потребители — экспорт, резервные копии, быстрое создание и панель тегов; общая поверхность результатов операций
- **Implementation target:** ["lib/src/design_system/components/sheet.dart","lib/src/graph/presentation/graph_operation_presenter.dart","test/design_system/sheet_test.dart","test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Затемнение, «назад» и семантика маршрута остаются за Material. Листы по содержимому ведут себя как прежде. Владелец общей поверхности, очередь, объединение сообщений и подтверждение кадром не меняются. Иконка шеврона отнесена к U3.

### U2 · Операции тегов объявляют только отказ

- **Work items:** ["2.3"]
- **Requirements and scenarios:** ["tag-management: Согласование панели тегов с подтверждёнными изменениями", "tag-management: Успех операции в панели не объявляется сообщением", "design: решение 7"]
- **Affected boundary:** Координатор команд графа, общая поверхность и прежние экраны тегов: редактор, каталог, секция назначений на странице намерения
- **Implementation target:** ["lib/src/graph/application/graph_command_coordinator.dart","lib/src/graph/application/graph_command_coordinator.g.dart","lib/src/tag/presentation/assignments/tag_assignments_section.dart","lib/src/tag/presentation/catalog/tag_catalog_view.dart","test/graph/application/graph_command_coordinator_tag_test.dart","test/graph/presentation/operation_failure_presentation_test.dart","test/tag/presentation/assignments/tag_assignments_section_test.dart","test/tag/presentation/catalog/tag_catalog_delete_test.dart","test/tag/presentation/catalog/tag_catalog_draft_lifecycle_test.dart","test/app/intention_creation_sheet_failure_integration_test.dart","test/app/intention_creation_sheet_integration_test.dart","test/app/intention_creation_sheet_tags_test.dart","test/app/tag_navigation_app_lifecycle_test.dart"]
- **Applicable constraints and non-goals:** Успех публикуется только для согласования данных. Тексты отказов и сообщения об отклонённом старте сохраняются. Удаление строк успеха из локализации учтено в U6, к которому отнесены файлы локализации.

### U3 · Компоненты модуля основ и иконки для панели и листа тега

- **Work items:** ["2.1", "2.5", "2.6", "2.7", "2.12"]
- **Requirements and scenarios:** ["tag-management: Панель тегов", "tag-management: Локализация и доступность управления тегами", "design: решение 10", "ADR-0030"]
- **Affected boundary:** Модуль основ `lib/src/design_system/` и экраны, которые его используют
- **Implementation target:** ["lib/src/design_system/components/button.dart","lib/src/design_system/components/empty_state.dart","lib/src/design_system/components/list_state.dart","lib/src/design_system/components/search_field.dart","lib/src/design_system/components/tag_create_row.dart","lib/src/design_system/components/tag_row.dart","lib/src/design_system/components/text_field.dart","lib/src/design_system/doable_icon.dart","lib/src/design_system/icons/README.md","lib/src/design_system/icons/assets/chevron_down.svg","lib/src/design_system/icons/assets/clear.svg","lib/src/design_system/icons/assets/plus_small.svg","lib/src/design_system/icons/assets/search.svg","test/design_system/button_test.dart","test/design_system/doable_icon_test.dart","test/design_system/empty_state_test.dart","test/design_system/goldens/doable_icons.png","test/design_system/list_state_test.dart","test/design_system/search_field_test.dart","test/design_system/tag_create_row_test.dart","test/design_system/tag_row_test.dart","test/design_system/text_field_test.dart"]
- **Applicable constraints and non-goals:** Компоненты только отображают: тексты, подписи и обработчики приходят от потребителя. Правила берутся из `context/doable-design-system/components/*/README.md`. Варианты для будущих потребителей не добавляются: ручка перестановки, удержание и отметки фильтра у строки, виды кнопки quiet, danger и text, многострочное поле.
- **Excluded change scope:** Меню, диалог подтверждения и иконки правки, копирования, удаления, ручки и исключения появятся с фазами 3 и 4.

### U4 · Поиск тегов без окружающих пробелов запроса

- **Work items:** ["2.4"]
- **Requirements and scenarios:** ["tag-management: Поиск тегов в панели", "tag-management: Запрос из одних пробелов не сужает список", "design: решение 5 — поисковый фильтр"]
- **Affected boundary:** Общий фильтр поиска тегов: панель и прежние каталог и выбор условия до их удаления
- **Implementation target:** ["lib/src/tag/domain/tag_name.dart","lib/src/tag/presentation/catalog/tag_catalog_filter.dart","test/tag/presentation/catalog/tag_catalog_filter_test.dart","test/tag/presentation/catalog/tag_catalog_search_page_test.dart"]
- **Applicable constraints and non-goals:** Поле хранит исходный ввод. Внутренние пробелы значимы. Поле `query` и метод `matchesWhole`, добавленные задачей 2.13, служат строке создания в U6.

### U5 · Лист «Новый тег»: проверка названия при вводе и передача принятого создания

- **Work items:** ["2.11", "2.14"]
- **Requirements and scenarios:** ["tag-management: Допустимое название тега", "tag-management: Уникальность названия тега", "tag-management: Создание и редактирование тега с выбором цвета", "tag-management: Повторная отправка создания", "tag-management: Пустое после нормализации название", "tag-management: Регистр и окружающие пробелы не создают новый тег", "tag-management: Создание тега без выбора цвета", "design: решение 6"]
- **Affected boundary:** Человек, создающий тег в листе поверх панели, и прежняя страница редактора, которая работает до фазы 4
- **Implementation target:** ["lib/src/tag/presentation/editor/tag_editor_state.dart","lib/src/tag/presentation/editor/tag_editor_view_model.dart","lib/src/tag/presentation/editor/tag_editor_view_model.g.dart","lib/src/tag/presentation/editor/tag_editor_page.dart","lib/src/tag/presentation/editor/tag_sheet.dart","test/tag/presentation/editor/tag_editor_view_model_test.dart","test/tag/presentation/editor/tag_editor_page_test.dart","test/tag/presentation/editor/tag_sheet_test.dart","test/tag/presentation/catalog/tag_catalog_page_test.dart","test/tag/presentation/catalog/tag_catalog_draft_search_scenarios.dart","test/app/tag_app_lifecycle_test.dart"]
- **Applicable constraints and non-goals:** Ответвление «Использовать существующий тег» и чтения после записи удалены по решению 6. Ограничение `UNIQUE` остаётся атомарной защитой. Правила листа изменения относятся к фазе 3.

### U6 · Панель тегов для существующего намерения: выбор, поиск, состояния и создание

- **Work items:** ["2.8", "2.9", "2.10", "2.13", "2.14"]
- **Requirements and scenarios:** ["tag-management: Панель тегов", "tag-management: Выбор тегов намерения в панели", "tag-management: Создание тега из панели", "tag-management: Полное получение тегов одним снимком", "tag-management: Получение каталога тегов и безопасные ошибки", "tag-management: Согласование панели тегов с подтверждёнными изменениями", "tag-management: Время жизни поискового запроса в панели тегов", "tag-management: Обработка некорректного поискового запроса", "tag-management: Очистка поиска и отсутствие совпадений тегов", "tag-management: Поиск сохраняет существующие назначения тегов", "tag-management: Локализация и доступность управления тегами", "design: решения 5–7", "ADR-0040"]
- **Affected boundary:** Человек, ведущий теги намерения в панели; координатор и общая поверхность; протокол ревизий подтверждённых пакетов
- **Implementation target:** ["lib/src/tag/presentation/panel/tags_panel.dart","lib/src/tag/presentation/panel/tags_panel_context.dart","lib/src/tag/presentation/panel/tags_panel_state.dart","lib/src/tag/presentation/panel/tags_panel_view_model.dart","lib/src/tag/presentation/panel/tags_panel_view_model.g.dart","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","test/tag/presentation/panel/tags_panel_test.dart","test/tag/presentation/panel/tags_panel_view_model_test.dart","test/support/tag_catalog_test_repository.dart"]
- **Applicable constraints and non-goals:** Нажатие — само действие, без подтверждения. Одна изменяющая операция на намерение, без очереди. Каталог читается полным снимком в ручном порядке. Файлы локализации общие для U2, U5 и U6.
- **Excluded change scope:** Меню тега, изменение, дублирование, удаление и перестановка — фаза 3. Контексты черновика и фильтра — фаза 4.

### U7 · Вход в панель со страницы намерения и готовность фазы 2

- **Work items:** ["2.15", "2.16"]
- **Requirements and scenarios:** ["intention-management: Управление тегами намерения", "intention-management: Теги архивированного действия", "intention-management: Назначение конкретному одноимённому намерению", "tag-management: Панель со страницы намерения показывает назначенные теги", "tag-management: Закрытие панели сохраняет применённые изменения", "tag-management: Закрытие панели во время назначения", "tag-management: Созданный тег сразу назначен", "app-navigation: Панель на обычных страницах", "app-navigation: Действие «назад» на корневых страницах"]
- **Affected boundary:** Страница активного и архивированного намерения, панель навигации и корневой стек маршрутов
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/tag_app_flow_test.dart","test/app/tag_assignment_app_flow_test.dart","test/app/tag_assignment_app_lifecycle_test.dart","test/intention/presentation/details/intention_details_tags_test.dart","test/tag/presentation/tag_accessibility_test.dart"]
- **Applicable constraints and non-goals:** Прежний каталог в контексте назначения остаётся в коде до фазы 4, но ни один вход его больше не открывает. Переход к странице тега из секции назначений удаляется в фазе 4. Задача 2.16 — проверка готовности фазы без рабочего кода.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных ревьюера по `implementation-decision-review` получили нейтральные брифы без артефактов планирования, истории коммитов и прежних замечаний. Первый проверил 22 пути U3. Второй получил общий бриф U1, U2, U4–U7 и объединение их 53 путей: эти единицы делят файлы локализации, редактора и презентера. Наборы путей не пересекаются. Первый прогон второго ревьюера прервался лимитом API; его возобновили в том же изолированном контексте, и он дочитал все назначенные тесты. Оба сообщили о полном покрытии своих путей. Влияние замечания первого ревьюера на панель проверено в контексте оркестратора по `tags_panel.dart`. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии: она чистая, HEAD = b342300ac038f007edff58665e3684838b9407a2. `mise run check`: код 0. В нём `flutter analyze` без замечаний, 3476 тестов прошли, `check:process-tests` — 18 прошли. `mise run codegen-check`: код 0, копия осталась чистой. `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive --json`: valid. Критерии задач 2.1–2.16 и сценарии из их проверок сопоставлены с тестами диапазона. Оркестратор и два помощника прочитали код; помощники дополнительно запустили наборы тестов своих областей, все прошли. Сборка APK и ручные проверки на устройстве не выполнялись. |
| Code quality | Complete | Оркестратор по линзам `code-review-and-quality` прочитал модель, состояние, контекст и вид панели, лист тега, модель и состояние редактора, разделение завершений в координаторе, презентер, фильтр и вход со страницы намерения. Два помощника применили те же пять линз ко всем путям поставки. Проверены: протокол ревизий и локальное применение пакетов, время жизни модели панели и ожидающего создания, классификация отказов чтения, политика предъявления для пяти видов операций, раскладка листа с собственным `Scaffold`, отступы клавиатуры, жест шапки и уменьшенная анимация. |

## Findings

### F3 · Low — Отметка строки тега объявляется экранному диктору дважды

- **Evidence:** `lib/src/design_system/components/tag_row.dart:30-32` требует, чтобы доступное название строки передавало и отметку словами. При этом `tag_row.dart:44-47` объявляет ту же отметку флагом `checked`. Панель передаёт подписи «‹тег›, отмечен» и «‹тег›, не отмечен» (`lib/src/tag/presentation/panel/tags_panel.dart:257-259`, `lib/l10n/app_ru.arb:508-511`). Тесты закрепляют обе формы одновременно (`test/design_system/tag_row_test.dart:125-164`). В исходнике дизайна (`context/doable-design/design/TagsPanel.dc.html`) в режиме выбора строка называется именем тега, а состояние передаётся отдельно.
- **Evidence revisions:** ["b342300ac038f007edff58665e3684838b9407a2"]
- **Impact:** TalkBack на каждой строке произносит состояние два раза, например «Работа, отмечен, отмечено». Это лишняя речь во всём списке и два источника одного состояния, которые могут разойтись.
- **Required outcome:** Отметка строки в текущем режиме объявляется один раз, из одного источника, определяемого отметкой. Требование «Локализация и доступность управления тегами» при этом остаётся выполненным: отметка различима без опоры на цвет и форму.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/tag_row.dart", "lib/src/tag/presentation/panel/tags_panel.dart", "lib/l10n", "test/design_system/tag_row_test.dart", "test/tag/presentation/panel/tags_panel_test.dart", "test/tag/presentation/tag_accessibility_test.dart"]

### F4 · Low — Модель панели обрабатывает недостижимые состояния, а неизвестный отказ проверен через одно из них

- **Evidence:** `lib/src/tag/presentation/panel/tags_panel_view_model.dart:208-212` перехватывает исключение чтения. Однако `DriftPersonalGraphRepository` сам перехватывает `on Object` и возвращает `TagCatalogError` (`lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart:165-173`). Сценарий «Неизвестный отказ получения каталога» (`test/tag/presentation/panel/tags_panel_view_model_test.dart:100-112`) доказан выброшенным `StateError`, то есть через этот недостижимый путь. Достижимый путь — возвращённый `TagCatalogUnexpectedFailure` — на уровне панели не проверен. Ветка `_precedesShown` (:173, :327-328) не срабатывает: показанная ревизия берётся из пакета или из чтения не старше требуемой, а чтения идут по одному. `TagsPanelLoadFailure.failure` и `TagsPanelLoaded.refreshFailure` имеют тип `TagCatalogReadFailure` (`tags_panel_state.dart:49-70`), хотя `TagCatalogIntentionNotFound` модель всегда переводит в `TagsPanelIntentionMissing`. Поэтому в `tags_panel.dart:275-277` и `:286` есть ветки, которые никогда не выполняются.
- **Evidence revisions:** ["b342300ac038f007edff58665e3684838b9407a2"]
- **Impact:** Проверка обязательного сценария не охраняет путь, который реально встречается. Читатель видит обработку состояний, которых архитектура не допускает. Это противоречит правилам проекта о доказанной необходимости и о типобезопасности.
- **Required outcome:** Сценарий неизвестного отказа показан на отказе, который репозиторий действительно возвращает. Модель и состояние панели не содержат обработки и вариантов, которые текущая система не может произвести.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/tag/presentation/panel/tags_panel_view_model.dart", "lib/src/tag/presentation/panel/tags_panel_state.dart", "lib/src/tag/presentation/panel/tags_panel.dart", "test/tag/presentation/panel/tags_panel_view_model_test.dart"]

### F5 · Low — Причина недопустимого названия в листе «Новый тег» ничем не проверена

- **Evidence:** `lib/src/tag/presentation/editor/tag_sheet.dart:71-75` переводит `TagEditorNameInvalid` в строку ошибки поля. Тесты листа (`test/tag/presentation/editor/tag_sheet_test.dart:55-169`) проверяют только занятое название, создание, выбор цвета, отказ записи и клавиатуру. Модель различает причину (`test/tag/presentation/editor/tag_editor_view_model_test.dart:94`), но ни один тест не показывает, что лист её рисует и делает «Создать тег» недоступной. Например, для названия из 256 графемных кластеров.
- **Evidence revisions:** ["b342300ac038f007edff58665e3684838b9407a2"]
- **Impact:** Требование «Допустимое название тега» обязывает показать в листе различимую причину для непустого недопустимого названия. Её легко получить обычным вводом. Регрессия, при которой причина не рисуется или кнопка остаётся доступной, пройдёт все проверки.
- **Required outcome:** Проверка листа «Новый тег» подтверждает, что для непустого недопустимого названия видна локализованная причина, а создание недоступно.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/tag/presentation/editor/tag_sheet_test.dart"]

### F6 · Low — Два достижимых поведения листа не охранены проверками

- **Evidence:** У раскрываемого листа есть защита: если система отменила касание шапки, жест не применяется (`lib/src/design_system/components/sheet.dart:441`, :472-474, :550-552). Без неё отменённое касание со сдвигом на 48 и больше закрыло бы половинный лист. Flutter вызывает `onEnd` и при `PointerCancelEvent`. В `test/design_system/sheet_test.dart` проверки с отменой касания нет. Отдельно: лист по содержимому с `hostsMessages` раскладывается собственным `_ScaffoldFrame` (`sheet.dart:340-403`), который обещает, что изменение содержимого снова доходит до раскладки листа. Это обещание проверено только на первой раскладке (`sheet_test.dart:138-152`). Достижимый триггер — появление и исчезновение строки ошибки в листе «Новый тег». Помощник временным тестом вне репозитория подтвердил, что сейчас поведение верно; это пробел в проверках, а не дефект.
- **Evidence revisions:** ["b342300ac038f007edff58665e3684838b9407a2"]
- **Impact:** Правка, которая сломает защиту от отмены касания, заставит панель тегов закрываться саму от системных жестов. Правка `_ScaffoldFrame`, которая перестанет пропускать рост содержимого, скроет строку ошибки под подвалом листа. В обоих случаях проверки пройдут.
- **Required outcome:** Проверки модуля основ подтверждают, что отменённое касание шапки не меняет размер листа и не закрывает его. Они же подтверждают, что лист по содержимому с размещением сообщений следует за ростом и уменьшением содержимого после открытия.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/design_system/sheet_test.dart"]

### F7 · Low — Размер листа и вариант его содержимого не связаны типом

- **Evidence:** `showDoableSheet` получает `DoableSheetSize` (`lib/src/design_system/components/sheet.dart:15-22`, :41) независимо от того, что вернёт `builder`: `Sheet` или `Sheet.expandable`. От размера зависит `enableDrag` (:62-65). Несогласованная пара компилируется: раскрываемый размер с обычным листом теряет закрытие свайпом, а размер по содержимому с раскрываемым листом сталкивает перетаскивание Material с жестом шапки. Описание класса «Компонент только оформляет содержимое, показом управляет [showDoableSheet]» (:90) устарело: раскрываемый вариант сам закрывает маршрут через `Navigator.pop`.
- **Evidence revisions:** ["b342300ac038f007edff58665e3684838b9407a2"]
- **Impact:** Каждый следующий потребитель раскрываемого листа должен вручную согласовать два параметра. Ошибка проявится только поведением на устройстве. Устаревшее описание вводит в заблуждение о том, кто управляет закрытием.
- **Required outcome:** Несогласованная пара «размер показа — вариант содержимого» непредставима или отвергается компилятором. Описание `Sheet` верно называет владельца закрытия раскрываемого листа.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/sheet.dart", "lib/src/tag/presentation/panel/tags_panel.dart", "lib/src/tag/presentation/editor/tag_sheet.dart"]

## Review coverage

Просмотрены все 20 целевых коммитов. Задачи 2.1 и 2.2 сопоставлены с U1, а иконка шеврона из задачи 2.1 — с U3. Задача 2.3 сопоставлена с U2, задачи 2.5, 2.6, 2.7 и 2.12 — с U3, задача 2.4 — с U4. Задача 2.11 и лист из задачи 2.14 относятся к U5, задачи 2.8, 2.9, 2.10, 2.13 и панель из задачи 2.14 — к U6, задачи 2.15 и 2.16 — к U7. `tasks.md` служит свидетельством планирования с отметками выполнения. Несопоставленных путей нет. Кода будущих фаз — меню, изменения, дублирования, удаления, перестановки, контекстов черновика и фильтра — в диапазоне нет.

Подтверждено следующее. Успех операций тегов отделён от отказа типом завершения: успех не образует записи для предъявления, отказ принадлежит общей поверхности без права инициатора, а строки успеха удалены. Лист с размещением сообщений показывает отказ над своим подвалом и подтверждает его кадром на верхнем маршруте, а листы без признака оставляют сообщение на странице. Модель панели применяет объяснимые пакеты локально в ручном порядке и отбрасывает запоздалые чтения. Отказ обновления держит строки неактуальными и недоступными, а повтор предлагается только для доказанно устранимого отказа. Строка создания предлагается по применённому запросу с правилом уникальности, ключ создания один на открытие панели. Созданный тег отмечается одной командой назначения, а её отказ оставляет тег неотмеченным. Страница намерения открывает только панель, и панель перекрывает страницу и панель навигации.

Часть кандидатов отклонена. Закрытый тип контекста панели с одним вариантом не считается преждевременным обобщением: два режима панели задают требование «Панель тегов» и ADR-0040, а остальные варианты добавит фаза 4 этого же изменения. Отсутствие места под ручку в `TagRow` и удаление «Использовать существующий тег» прямо предусмотрены задачами 2.6 и 2.11 и решением 6. Перехват исключений в секции назначений существовал до диапазона и в нём не появился.

Исправлений кода и артефактов в этой стадии не было, поэтому `mise run check` на проверяемой голове — итоговая полная проверка фазы 2. Сборка APK и проверки на устройстве не выполнялись, и это не блокирует фазу. Ручные проверки остаются за пользователем: открытие панели на половину высоты, раскрытие и сворачивание шапкой и ручкой, поиск при открытой клавиатуре, назначение, снятие и создание тега, отказ над «Готово» и над «Создать тег», озвучивание TalkBack и сверка вида с макетами задачи 2.16.
