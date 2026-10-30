# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Фаза 1 переносит экраны выбора на общий модуль поиска в соответствии с задачами 1.1–1.8. Состояния загрузки и отказов экрана выбора теперь «доезжают» пружиной от прежнего смещения (F2). Часть проверок `IntentionSearchKind` повторяет уже существующие (F3).

## Review target

- **Baseline ref:** a1a2f06f86a3633aa9ab0bf43bc996741ce8402b
- **Base commit:** a1a2f06f86a3633aa9ab0bf43bc996741ce8402b
- **Reviewed head:** fdbfd885c4fd62d08e79d00d3b867d80df48c37a
- **Target commits:** ["2896be464ebc7639f525fea1086de72cf1c9499c", "6f5e6fb31c1a3545b9a212fe6b9326a53805e7f1", "77b519f59c6155fbafb0e863b7a543d81240cd1b", "0365c911cc3f93e0bea396906553a53cff0d1d46", "2c6af558e4d74122d4d895f5cef12fe533864dc5", "54a95220606d8a3c67e71c6ed3c4bc7353041512", "31a3a7c31256e375c14f388ca0ef20d658478a55", "5b3064ed169add7daf1bf52d4a14115e86cdb7ce", "fdbfd885c4fd62d08e79d00d3b867d80df48c37a"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/catalog/intention_search_results.dart", "lib/src/intention/presentation/picker/intention_picker_kind.dart", "lib/src/intention/presentation/picker/intention_picker_row.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "lib/src/intention/presentation/search/intention_list_header.dart", "lib/src/intention/presentation/search/intention_row_content.dart", "lib/src/intention/presentation/search/intention_search_bar.dart", "lib/src/intention/presentation/search/intention_search_kind.dart", "lib/src/intention/presentation/search/intention_search_list.dart", "lib/src/intention/presentation/search/results_scroll_keeper.dart", "lib/src/intention/presentation/search/show_and_sort_sheet.dart", "openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/intention/presentation/picker/intention_picker_view_test.dart", "test/intention/presentation/search/intention_search_kind_test.dart", "test/intention/presentation/search/intention_search_list_test.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Разбор назначения и правило содержания строки в модуле поиска

- **Work items:** ["1.1", "1.2"]
- **Requirements and scenarios:** ["intention-management: Строка результата поиска намерений", "intention-management: Экран поиска для выбора намерения", "design: решение 1", "design: решение 6 (IntentionRowContent)"]
- **Affected boundary:** Экраны выбора действия, исходного намерения и участника; модуль `presentation/search/`.
- **Implementation target:** ["lib/src/intention/presentation/search/intention_search_kind.dart", "lib/src/intention/presentation/picker/intention_picker_kind.dart", "lib/src/intention/presentation/search/intention_row_content.dart", "lib/src/intention/presentation/picker/intention_picker_row.dart", "test/intention/presentation/search/intention_search_kind_test.dart"]
- **Applicable constraints and non-goals:** Ключи и тексты экранов выбора не меняются; экран выбора не принимает назначение каталога; один исчерпывающий разбор назначения в модуле поиска.
- **Excluded change scope:** Строка каталога `CatalogRow`/`IntentionCatalogRow` — фаза 4.

### U2 · Общий хранитель места и общая выдача

- **Work items:** ["1.3", "1.4"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога", "intention-management: Пустая выдача поиска намерений", "intention-management: Состояния получения каталогов и подробных данных намерений", "design: решение 5"]
- **Affected boundary:** Выдача экранов выбора и прежняя выдача каталога при согласовании с подтверждёнными операциями и смене параметров.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart", "lib/src/intention/presentation/catalog/intention_search_results.dart", "lib/src/intention/presentation/search/intention_search_list.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "test/intention/presentation/search/intention_search_list_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart"]
- **Applicable constraints and non-goals:** Прежняя страница каталога ведёт себя как раньше; экраны выбора меняют только удержание видимой строки при согласовании; новая выдача начинается сверху.
- **Excluded change scope:** Пустые состояния каталога и снятие `PageStorage` вместе с прежней страницей — фаза 4.

### U3 · Общий лист, строка поиска и заголовок списка

- **Work items:** ["1.5", "1.6"]
- **Requirements and scenarios:** ["intention-management: Параметры показа в поиске намерений", "intention-management: Меню параметров показа в поиске намерений", "intention-management: Заголовок списка поиска намерений", "intention-management: Кнопка фильтра по тегам в поиске намерений"]
- **Affected boundary:** Шапка под заголовком экрана выбора и лист «Показать и упорядочить».
- **Implementation target:** ["lib/src/intention/presentation/search/show_and_sort_sheet.dart", "lib/src/intention/presentation/search/intention_search_bar.dart", "lib/src/intention/presentation/search/intention_list_header.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart"]
- **Applicable constraints and non-goals:** Вид, ключи и поведение экранов выбора не меняются.
- **Excluded change scope:** Строка «Показать», числа по охватам и сброс охвата — фазы 2 и 4.

### U4 · Подпись типа без ограничения

- **Work items:** ["1.7"]
- **Requirements and scenarios:** ["intention-management: Параметры показа в поиске намерений / Крупный текст переносится в строках и меню", "intention-management: Меню параметров показа в поиске намерений / Меню типа показывает количества независимо от выбранного типа"]
- **Affected boundary:** Строка «Тип» и её меню в листе экранов выбора на русском и английском.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_ru.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart"]
- **Applicable constraints and non-goals:** Заголовок списка по-прежнему называет тип «Все» / `All`; наборы ключей ru и en симметричны.

### U5 · Готовность фазы 1

- **Work items:** ["1.8"]
- **Requirements and scenarios:** ["plan.md: Phase 1 / Ready to advance"]
- **Affected boundary:** Вся фаза 1: экраны выбора на общем модуле, прежний каталог без изменений.
- **Implementation target:** ["test/intention/presentation/search/intention_search_list_test.dart", "test/intention/presentation/search/show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart"]
- **Applicable constraints and non-goals:** Без проверок на устройстве; полная проверка проекта `mise run check`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер (Sonnet, `implementation-decision-review`) на объединённую группу U1–U5 со всеми 20 путями поставки и тестов диапазона; планирующие артефакты ему не передавались. |
| OpenSpec conformance | Complete | В рабочем дереве на голове fdbfd885c4fd62d08e79d00d3b867d80df48c37a без незакоммиченных изменений: `mise run check` — `flutter analyze` без замечаний, 3836 обычных и 18 процессных тестов прошли; `mise run codegen-check` — код сгенерирован актуально; `openspec validate redesign-intention-catalog --strict --json` — valid. Задачи 1.1–1.8 сопоставлены с кодом и тестами диапазона. |
| Code quality | Complete | Пять осей по всем путям поставки на голове fdbfd885c4fd62d08e79d00d3b867d80df48c37a с вызывающими `intention_catalog_page.dart` и тестами выдачи каталога. |

## Findings

### F2 · Low — Загрузка и отказы экрана выбора возвращаются к началу пружиной от прежнего смещения

- **Evidence:** В базе `_status` выдачи экрана выбора строил отдельный `ListView`, и состояние загрузки или отказа появлялось сразу сверху. На голове `intention_search_list.dart:103-148` строит пауза ввода, загрузку и отказы как `SliverToBoxAdapter` внутри того же `CustomScrollView` с тем же контроллером хранителя. Хранитель переводит список наверх только при новой подтверждённой выдаче (`results_scroll_keeper.dart:66-71`), а не при замене строк состоянием. Когда содержимое сжимается, смещение оказывается за `maxScrollExtent`; `IdleScrollActivity.applyNewDimensions` вызывает `goBallistic(0)`, и `ClampingScrollPhysics.createBallisticSimulation` (Flutter `scroll_physics.dart`) возвращает пружинную симуляцию к краю.
- **Evidence revisions:** ["fdbfd885c4fd62d08e79d00d3b867d80df48c37a"]
- **Impact:** Пользователь прокрутил выдачу экрана выбора далеко вниз и вводит название: вместо мгновенной замены списка состоянием загрузки текст загрузки несколько кадров въезжает сверху. Так же ведёт себя отказ первой порции. Фаза 1 обещает прежнее поведение экранов выбора, кроме двух названных изменений, а в фазе 4 то же получит каталог.
- **Required outcome:** Пауза ввода, загрузка и отказ первой порции показываются сверху сразу, без анимации прокрутки от смещения прежней выдачи; это подтверждено проверкой из прокрученного состояния.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/search/intention_search_list.dart", "lib/src/intention/presentation/search/results_scroll_keeper.dart", "test/intention/presentation/search/intention_search_list_test.dart"]

### F3 · Low — Проверки `IntentionSearchKind` для экранов выбора повторяют существующие

- **Evidence:** `intention_search_kind_test.dart:35-50` проверяет префикс ключей и `namesKind` для четырёх назначений и отдельно, что префиксы различны. Префиксы трёх экранов выбора уже закреплены тестами, которые находят элементы по ключам `daily-choice-action-…`, `daily-choice-source-…` и `participant-picker-…` (например, `test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart`, `test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart`, `test/intention/presentation/picker/intention_picker_view_test.dart`). Называние типа по назначению закреплено доступными названиями в `test/intention/presentation/picker/intention_picker_row_test.dart:78-125`. Проверка различия префиксов следует из проверок точных значений. Новую регрессию ловят только проверки варианта каталога, у которого в этой фазе нет других проверок.
- **Evidence revisions:** ["fdbfd885c4fd62d08e79d00d3b867d80df48c37a"]
- **Impact:** Повторные проверки удваивают места правки при изменении назначений и не ловят регрессий сверх существующих, вопреки правилу обоснованной необходимости.
- **Required outcome:** В `intention_search_kind_test.dart` остаются только проверки, которые ловят регрессию, не пойманную другими тестами.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/intention/presentation/search/intention_search_kind_test.dart"]

## Review coverage

Проверены все девять коммитов диапазона и все 22 изменённых пути. Пути поставки и тестов прочитаны на голове и сопоставлены с базой: `IntentionSearchKind` и удалённый `IntentionPickerKind`, `IntentionRowContent` и `IntentionPickerRow`, `ResultsScrollKeeper`, прежняя выдача каталога `intention_search_results.dart` с её единственным вызывающим `intention_catalog_page.dart`, `IntentionSearchList` вместо удалённого `IntentionPickerResults`, общий лист «Показать и упорядочить», `IntentionSearchBar`, `IntentionListHeader`, `IntentionPickerView`, изменения ARB и сгенерированной локализации. Проверено, что разбор назначений в представлении остался только в `IntentionSearchKind`, а прежних `IntentionPickerKind` и `intentionPickerKeyPrefix` в `lib/` нет. Удаление обработки смены назначения в прежней выдаче каталога недостижимо и не является находкой: страница передаёт постоянное `BrowseIntentionCatalog()`. Требования delta-спецификации к экранам выбора, строке результата, пустой выдаче, заголовку списка, листу, меню и типу сопоставлены с кодом и тестами. Задачи будущих фаз не считались обязательствами диапазона. `task-profiles.md` и отметки `tasks.md` — планирующие свидетельства. Данных, схемы, безопасности и внешних зависимостей диапазон не касается.
