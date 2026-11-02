# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Фаза 1 выполнена и соответствует задачам 1.1–1.14, полные проверки на проверенной ревизии проходят. Главная находка F1: устаревшая выдача оставляет в подвале секции вечный индикатор подгрузки, хотя запроса нет и не будет. Остальные находки низкой серьёзности. Принятых рисков нет.

## Review target

- **Baseline ref:** 5f68c63fdb2fa28a40bbd56b506279eed51ad38b
- **Base commit:** 5f68c63fdb2fa28a40bbd56b506279eed51ad38b
- **Reviewed head:** bc3d8b2f03a4d7fe390dab77afc100241965c685
- **Target commits:** ["e3016dfe2104087a44835e3d2259896319c62238", "fe18db7ad08be6928c95e985cb186fcf849c906d", "2ecbdb41d27bbf9841449310127747327e810f35", "20f1fff21e2b2ce35e55907de969a91471491175", "27752d5472e5ea9e00cddd5b863682824099c395", "3927899396029ef9f09f0b217da5f9b5e09d171b", "edd355d6ab241832cceadd2f0384da7c81783576", "f98f03217ca64c0feea00683d64cc5aafbc49121", "268e6f746abe00e173b3a67e91d0c61ac891c1ba", "62b93f636d98417ae817b592787759b10e3866f6", "0002b82ab88212437da9f6d5b2b55c5e39355c9f", "60ff3ae5e1a725e033cccf567e92451b01fa9c31", "99fa1f6a4534b3ac59d5ad406136377ecf8661cf", "7ba5a41501cfd685ea8184ca5331f23d58eb1c35", "c1f8f0746f76e996e9ee6104094efbe5f785ef4f", "b4baa2777499aaeb8d1d3a7155ceec2ccefb209d", "bc3d8b2f03a4d7fe390dab77afc100241965c685"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/navigation/ordinary_page_scaffold.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart", "lib/src/design_system/components/choice_check.dart", "lib/src/design_system/components/choice_row.dart", "lib/src/design_system/components/list_state.dart", "lib/src/design_system/components/reason_chain.dart", "lib/src/design_system/components/relation_row.dart", "lib/src/design_system/components/scroll_top_button.dart", "lib/src/design_system/components/section_header.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/doable_metrics.dart", "lib/src/design_system/doable_priority.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/to_top.svg", "lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart", "openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md", "test/app/creation_flows_test_support.dart", "test/app/daily_choice_app_flow_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/daily_choice_completion_lifecycle_scenarios.dart", "test/app/graph_export_app_flow_test.dart", "test/app/intention_statistics_catalog_scenarios.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_card_flow_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_cards_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/design_system/choice_check_test.dart", "test/design_system/choice_row_test.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/list_state_test.dart", "test/design_system/reason_chain_test.dart", "test/design_system/relation_row_test.dart", "test/design_system/scroll_top_button_test.dart", "test/design_system/section_header_test.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/long_term_relation/presentation/intention_relations/intention_relations_sliver_test.dart", "test/support/daily_choice_catalog_controls.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Экран дня показывает выборы по дизайну на обоих каталогах

- **Work items:** ["1.1", "1.2", "1.6", "1.7", "1.8", "1.9", "1.10", "1.11", "1.13", "1.14"]
- **Requirements and scenarios:** ["Краткая карточка дневного выбора", "Секции выполнения дневных выборов", "Группировка и порядок дневных выборов", "Каталог дневных выборов по дате и секциям", "Подтверждённые результаты и безопасные ошибки дневного выбора: флажок карточки", "Начальное состояние и сохранение календаря каталога", "Возврат к началу выдачи каталога"]
- **Affected boundary:** Человек в корневом каталоге и каталоге на дату, в том числе с экранным диктором, крупным шрифтом и уменьшением движения
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/navigation/ordinary_page_scaffold.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart", "test/app/creation_flows_test_support.dart", "test/app/daily_choice_app_flow_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/daily_choice_completion_lifecycle_scenarios.dart", "test/app/graph_export_app_flow_test.dart", "test/app/intention_statistics_catalog_scenarios.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_card_flow_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_cards_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/support/daily_choice_catalog_controls.dart"]
- **Applicable constraints and non-goals:** Схема, формат данных, чтение, команды, календарь и его отметки не меняются. Запись идёт через координатор, отказ предъявляется через `OperationFailurePresentation`, повтор только при доказанно временном отказе. Сохранение состояния каталога в процессе прежнее, строки есть на обоих языках. Успех флажка в этой фазе объявляется как раньше, карточка открывает прежний подробный просмотр.
- **Excluded change scope:** Фазы 2–4: замена пути, завершение создания, нижняя панель, изменение на месте, сценарий «Успех флажка карточки не объявляется сообщением» и сверка с `add-relations-in-batches`.

### U2 · Модуль основ даёт компоненты дня и одно перечисление приоритета

- **Work items:** ["1.3", "1.4", "1.5", "1.7", "1.9", "1.12"]
- **Requirements and scenarios:** ["Краткая карточка дневного выбора", "Секции выполнения дневных выборов", "Возврат к началу выдачи каталога"]
- **Affected boundary:** Экранный код, потребляющий модуль основ, и доступность его элементов
- **Implementation target:** ["lib/src/design_system/components/choice_check.dart", "lib/src/design_system/components/choice_row.dart", "lib/src/design_system/components/list_state.dart", "lib/src/design_system/components/reason_chain.dart", "lib/src/design_system/components/relation_row.dart", "lib/src/design_system/components/scroll_top_button.dart", "lib/src/design_system/components/section_header.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/doable_metrics.dart", "lib/src/design_system/doable_priority.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/to_top.svg", "lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart", "test/design_system/choice_check_test.dart", "test/design_system/choice_row_test.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/list_state_test.dart", "test/design_system/reason_chain_test.dart", "test/design_system/relation_row_test.dart", "test/design_system/scroll_top_button_test.dart", "test/design_system/section_header_test.dart", "test/long_term_relation/presentation/intention_relations/intention_relations_sliver_test.dart"]
- **Applicable constraints and non-goals:** Компоненты остаются представлениями без предметных типов по ADR-0030 и появляются вместе с потребителем. Значки следуют `lib/src/design_system/icons/README.md`. Параметров множественного выделения нет.
- **Excluded change scope:** `ChoiceHead`, `ChoicePath`, `DetailRow`, `DateGrid`, `TimeDial`: они относятся к следующим фазам.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Единицы U1 и U2 делят потребление компонентов, поэтому у них одно задание на точные 59 путей поставки и тестов без артефактов планирования. Три свежих изолированных проверяющих разделили его: `lib/src`; локализация и тесты каталога и приложения; `test/design_system`, тест среза связей и эталон значков |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate redesign-daily-choices --strict` проходит. `mise run check`, `mise run codegen-check` и `flutter build apk --debug` завершились с кодом 0 в этом worktree на чистом `bc3d8b2f03a4d7fe390dab77afc100241965c685`. Задачи 1.1–1.14 и выбранные сценарии сопоставлены с кодом и тестами |
| Code quality | Complete | Линзы `code-review-and-quality` применены ко всем путям поставки на проверенной ревизии: корректность, читаемость, архитектура, безопасность, производительность. Новых зависимостей, секретов и внешних границ в диапазоне нет |

## Findings

### F1 · Medium — Устаревшая выдача показывает вечную подгрузку в подвале секции

- **Evidence:** После отказа обновления `_assemble` публикует выдачу с `freshness: stale` и `DailyChoiceCatalogPageIdle` (`lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart:368-380`). `loadMore` при такой свежести ничего не запрашивает (`daily_choice_catalog_view_model.dart:280-288`), а подвал секции при `Idle` всегда показывает `ListState.more` (`lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart:505-507`, `724-725`). До диапазона эта же ветка выключала кнопку подгрузки при неактуальной выдаче. Тест `daily_choice_catalog_page_test.dart:670` проверяет только отсутствие запроса, но не вид подвала.
- **Evidence revisions:** ["bc3d8b2f03a4d7fe390dab77afc100241965c685"]
- **Impact:** Человек внизу выдачи видит крутящееся кольцо, а диктор слышит «Загружаем ещё…», хотя запроса нет. `Notice` с отказом стоит в начале прокрутки и может быть за пределами экрана. При неповторяемом отказе кольцо крутится, пока новая ревизия не обновит выдачу. Это нарушает требование различать загрузку и ошибку.
- **Required outcome:** Подвал показывает подгрузку только во время запроса порции или когда запрос гарантированно начнётся. В устаревшей выдаче ложного признака хода работы и его объявления нет, а тест закрепляет это состояние.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart"]

### F2 · Low — Строка обновления накладывается на строку дня при крупном шрифте

- **Evidence:** `ListState.refreshing` стоит поверх `DayHeading` через `PositionedDirectional(top: 3, start: 0, end: 0)` в `Stack`, высоту и ширину которого занимает только заголовок (`lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart:215-249`). Строка дня ничего не резервирует у конца (`lib/src/design_system/components/day_heading.dart`). Проба при ширине 360 и масштабе 2 с тестовым шрифтом показала пересечение: строка обновления занимает x 58–340 и y 19–55, текст дня x 20–340 и y 18–99. Тестовый шрифт шире настоящего, поэтому порог в реальном шрифте не измерен; по оценке ширин наложение наступает примерно от масштаба 1,5 в день с отметкой «Сегодня». Тестов на такое сочетание нет.
- **Evidence revisions:** ["bc3d8b2f03a4d7fe390dab77afc100241965c685"]
- **Impact:** На время обновления текст «Обновляем…» ложится на день недели или отметку «Сегодня». Обновление локальное и короткое, поэтому дефект мигающий, но он возникает при каждой пересборке выдачи у людей с крупным шрифтом.
- **Required outcome:** Строка обновления не пересекает текст заголовка дня при поддерживаемых масштабах шрифта, а высота заголовка и позиции строк выдачи не меняются при её появлении и исчезновении.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart"]

### F3 · Low — Проверка перезапуска больше не связывает строку с выбранным днём

- **Evidence:** В `test/app/daily_choice_app_lifecycle_test.dart:765-768` и `788-791` проверка `_rowLabel` с датой заменена на наличие ключа `daily-choice-row-1`. Этот ключ порядковый и есть у любой непустой выдачи. Цикл по прошлому и будущему дню сверяет идентификатор только в ответе `_catalogResult` (`daily_choice_app_lifecycle_test.dart:777-783`), а не на экране. Задача 1.14 требует сохранить прежние гарантии без ослабления ожиданий.
- **Evidence revisions:** ["bc3d8b2f03a4d7fe390dab77afc100241965c685"]
- **Impact:** Если экран после перезапуска оставит строки другого дня, тест пройдёт, хотя именно эту гарантию он и защищал.
- **Required outcome:** Для каждого выбранного дня тест через интерфейс подтверждает, что показана строка сохранённого выбора этого дня.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/app/daily_choice_app_lifecycle_test.dart"]

### F4 · Low — Два теста компонентов не ловят отдельной регрессии

- **Evidence:** `test/design_system/scroll_top_button_test.dart:103` проверяет, что новое значение обязательного `label` попадает в семантику; это уже утверждает тест в строке 69. `test/design_system/choice_check_test.dart:81` проверяет отсутствие галочки у невыполненного выбора, а тест в строке 18 уже требует в центре кольца цвет тона без значка.
- **Evidence revisions:** ["bc3d8b2f03a4d7fe390dab77afc100241965c685"]
- **Impact:** Лишние тесты удорожают изменение компонентов и не защищают от новой ошибки, что противоречит правилу доказанной необходимости.
- **Required outcome:** В наборе остаётся только тест, называющий отдельную вероятную регрессию.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/design_system/scroll_top_button_test.dart", "test/design_system/choice_check_test.dart"]

## Review coverage

Прочитаны артефакты графа `intent-driven`: proposal, дельта `daily-choice-management`, design, adr, plan, tasks, а также ADR-манифест. Правила компонентов сверены с README `ChoiceRow`, `ChoiceCheck`, `ReasonChain`, `SectionHeader`, `TimeGroup`, `ScrollTopButton`, `ListState`, `EmptyState` из `context/` основного checkout: эта папка не хранится в git, поэтому ревизия её текста неизвестна.

Покрыты все 17 целевых коммитов. Коммит `e3016dfe2104087a44835e3d2259896319c62238` относится только к планированию, `c1f8f0746f76e996e9ee6104094efbe5f785ef4f` обновляет хеш провайдера, `b4baa2777499aaeb8d1d3a7155ceec2ccefb209d` убирает лишний импорт в тесте, `bc3d8b2f03a4d7fe390dab77afc100241965c685` отмечает задачу 1.14, остальные соответствуют задачам 1.1–1.13 один к одному. Изменения `tasks.md` в диапазоне — только отметки выполнения. Посторонних изменений в диапазоне нет.

Проверены подгрузка из построения подвала с защитой от автоповтора отказа, порог и размещение кнопки над панелью и сообщением, восстановление прокрутки, поверхность отказа выполнения, семантика строки и заголовка, полнота ключей локализации и удаление всех имён из задачи 1.14 (`git grep` пуст). Тело каталога одно на обе страницы и не ветвится по странице, поэтому сценарии групп и подгрузки, доказанные на корневом каталоге, распространяются и на каталог на дату; поведение, зависящее от каркаса, тесты проверяют на обоих.

Ручные проверки на устройстве остаются за владельцем продукта.
