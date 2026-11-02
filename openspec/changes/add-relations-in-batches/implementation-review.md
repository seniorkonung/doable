# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.17–2.21 выполнены и подтверждены тестами на рассмотренной голове. Активных находок и принятых рисков нет. Планирование после обзора изменилось: панель связи стала панелью по содержимому, поэтому раскрытие из U1 снимает открытая задача 2.22, а метки U1 и U2 называют сценарии на рассмотренной голове.

## Review target

- **Baseline ref:** 8f5422aaa8e18fde3c6f520aae01f0b468cef3ca
- **Base commit:** 8f5422aaa8e18fde3c6f520aae01f0b468cef3ca
- **Reviewed head:** dd5343476de3eead050bf7fcd294be2fb935865a
- **Target commits:** ["18357db0cc5cd65ba53f0552754235737e372bb9","8ca3b18f73a3e1c12f7aa20885fafa9ac40aecd6","09e8dbcf33fd16f85e87d9e6356b72b193adf8fe","a391adda9763c23c4fca7a57892caf85f13cf06a","b1568a89d582eb8c2633b7a384f577f36cfa2e65","dd5343476de3eead050bf7fcd294be2fb935865a"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/priority_picker.dart","lib/src/design_system/components/sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","lib/src/long_term_relation/presentation/editor/relation_editor_state.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/design_system/priority_picker_test.dart","test/design_system/sheet_test.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart","test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Панель связи раскрывается и возвращается в прежний размер

- **Work items:** ["2.17","2.18"]
- **Requirements and scenarios:** ["long-term-relation-management: Подробный просмотр связи в нижней панели","long-term-relation-management: Панель раскрывается, даже когда связь помещается","long-term-relation-management: Выход из изменения описания возвращает полный размер","bottom-sheets: Размеры нижней панели","bottom-sheets: Перетаскивание нижней панели","bottom-sheets: Передача жеста между телом и панелью","bottom-sheets: Ручка нижней панели"]
- **Affected boundary:** Человек в панели связи, пользователь экранного диктора и потребители `Sheet` в модуле основ.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","test/design_system/sheet_test.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart"]
- **Applicable constraints and non-goals:** Размер меняет только человек, а лист с полосой неподвижен. Компоненты остаются без предметной логики, строки есть на двух языках. Поведение `Sheet` и `Sheet.expandable` не меняется.

### U2 · Новый отказ операции панели виден без ручной прокрутки

- **Work items:** ["2.19"]
- **Requirements and scenarios:** ["long-term-relation-management: Подробный просмотр связи в нижней панели","long-term-relation-management: Отказ действия из шапки виден без раскрытия","long-term-relation-management: Повторный отказ снова виден в полном размере"]
- **Affected boundary:** Человек, выполняющий операцию в панели связи.
- **Implementation target:** ["lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart"]
- **Applicable constraints and non-goals:** Отказ остаётся внутри панели и не меняет её размер. Показанный ранее отказ не отнимает ручную прокрутку. Тексты и источники отказов не меняются.

### U3 · Состояние формы создания теряет признак без читателя

- **Work items:** ["2.20"]
- **Requirements and scenarios:** []
- **Affected boundary:** Сопровождение формы создания связи; для человека поведение не меняется.
- **Implementation target:** ["lib/src/long_term_relation/presentation/editor/relation_editor_state.dart","test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart"]
- **Applicable constraints and non-goals:** Начальное состояние формы сохраняется. Задача не связана с требованием: это очистка кода, поэтому меток требований нет.

### U4 · Доступное название пилюли приоритета зависит только от приоритета

- **Work items:** ["2.21"]
- **Requirements and scenarios:** ["long-term-relation-management: Подробный просмотр связи в нижней панели"]
- **Affected boundary:** Пользователь экранного диктора и потребитель `PriorityPicker`.
- **Implementation target:** ["lib/src/design_system/components/priority_picker.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","test/design_system/priority_picker_test.dart"]
- **Applicable constraints and non-goals:** Видимый выбор и доступные названия рабочего потребителя прежние.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных ревьюера `implementation-decision-review` проверили диапазон `8f5422aa…..dd534734…`. Первый получил U1, U2 и U4 одной группой, потому что они делят `relation_details_sheet.dart`, а второй — U3. Покрытие обоих полное. Первый вернул две находки, второй — ни одной. Опровергнутое замечание описано в разделе «Review coverage». |
| OpenSpec conformance | Complete | Критерии задач 2.17–2.21 и сценарии «Панель раскрывается, даже когда связь помещается», «Выход из изменения описания возвращает полный размер», «Отказ действия из шапки виден без раскрытия» и «Повторный отказ снова виден в полном размере» сверены с кодом и тестами на `dd534734…`. На дереве с `HEAD` = `dd534734…`: `mise run check` — код 0 (формат без правок, `flutter analyze` без замечаний, 4031 обычный и 18 процессных тестов; во время прогона в дереве менялся только сам отчёт); `mise run codegen-check` — код 0, дерево осталось чистым; `mise exec --no-deps -- openspec validate add-relations-in-batches --strict` — успех, это только структурное свидетельство. Устройство и эмулятор не использовались. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем рабочим путям на `dd534734…`. Вне правок учтены `relation_details_view_model.dart`, `relation_details_state.dart`, `graph_command_coordinator.dart`, `graph_replacement_progress.dart` и `text_field.dart`. Новых зависимостей, границ доверия и неограниченных чтений в диапазоне нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все шесть коммитов диапазона разобраны. `18357db0…` только планирующий и добавляет профили задач. Задача 2.17 — коммит `8ca3b18f…` (U1), 2.18 — `09e8dbcf…` (U1), 2.19 — `a391adda…` (U2), 2.20 — `b1568a89…` (U3), 2.21 — `dd534734…` (U4). В `lib/` и `test/` нет `hasChanges`, а `_UntitledFrame` удалён вместе со своей копией раскладки. Существующие тесты `Sheet`, `Sheet.expandable` и «отказ записи виден над клавиатурой» не менялись: в них изменён только вызов `Sheet.untitled` в общем помощнике.

Мутации в одноразовой копии подтвердили, что тесты ловят откат. Прокрутка только к первому отказу роняет «повторный отказ архивирования». Прокрутка при прежнем отказе роняет «обновление панели с прежним отказом». Удаление слушателя роняет четыре теста. Удаление доводки раскрытия при появлении полосы роняет «снятие полосы, которая оборвала перетаскивание».

Замечание ревьюера о том, что повторный отказ правки в монопольном режиме не прокручивается, отвергнуто. Константа в `relation_details_view_model.dart:236` действительно делает такой повтор тем же объектом, и `_hasNewFailure` в `relation_details_sheet.dart:384` его пропустит. Но замена графа идёт под модальным прогрессом в корневом навигаторе без закрытия (`graph_replacement_progress.dart:77-82`, `:151`), поэтому панель в это время недоступна, а второй путь к этому началу команды — завершение работы приложения.

Доводка раскрытия в `didUpdateWidget` листа находкой не считается, хотя касанием она недостижима. Проба с двумя пальцами показала, что нажатие вторым пальцем во время перетаскивания за ручку или тело не открывает изменение описания: жест забирает активный распознаватель. Но поле описания построено на `InkWell` (`text_field.dart:273`), поэтому его активирует аппаратная клавиатура во время перетаскивания, и лист без этой доводки остался бы между размерами.

Прошлый отчёт не содержал находок и принятых рисков, поэтому переносить нечего. Код и планирующие артефакты в этом этапе не менялись: навык запрещает правки при обзоре. Ручные проверки на устройстве остаются за владельцем продукта, в том числе озвучка ручки диктором и раскрытие жестом.
