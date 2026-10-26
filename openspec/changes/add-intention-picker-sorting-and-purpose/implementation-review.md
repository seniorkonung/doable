# OpenSpec Implementation Review: add-intention-picker-sorting-and-purpose

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Все три прохода завершены для U1–U3 и задач 2.1–2.8; активных замечаний нет. По решению владельца исправление восьми вызовов устаревшего API в тесте OptionGroup передано в незавершённую задачу 2.9. Это передача исправления в план: код ещё не исправлен, успешный `mise run check` и готовность фазы 2 не подтверждены. Сохраняется принятый риск AR1 об индексах архивного охвата; его исходное решение этим диапазоном не пересматривается.

## Review target

- **Baseline ref:** c22842cad85e7d9ce19f9c9dfc1dd9d171123054
- **Base commit:** c22842cad85e7d9ce19f9c9dfc1dd9d171123054
- **Reviewed head:** f4b6d56847b6b24046a3ba3737428c3847ca5754
- **Target commits:** ["f6723f5e3eaacd03da40a67515d7129b9c15ffc8", "9442540e24a40ee67f4387d3fb21ff1b6bb30e59", "88e9fcf7f8c821ed31d3375a2a2583951bae8113", "31d621813da422bb3f9809dc48bb6fe6abba2551", "dee7e025ec63312782dc5c558bec35b5a09ea62c", "e0fee6a332af5e41658f810800a12bad185176a9", "744bf9f397539db7c36a3ff0fc49d0fdd0d508f5", "f4b6d56847b6b24046a3ba3737428c3847ca5754"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/design_system/components/catalog_header.dart", "lib/src/design_system/components/option_group.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/arrow_down.svg", "lib/src/design_system/icons/assets/arrow_up.svg", "lib/src/design_system/icons/assets/sliders.svg", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/picker/intention_picker_kind.dart", "lib/src/intention/presentation/picker/intention_picker_results.dart", "lib/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md", "test/daily_choice/presentation/daily_choice_picker_context_test_support.dart", "test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart", "test/design_system/catalog_header_test.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/option_group_test.dart", "test/design_system/sheet_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart", "test/intention/presentation/picker/intention_picker_results_test.dart", "test/intention/presentation/picker/intention_picker_show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart", "test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart"]
- **OpenSpec change:** add-intention-picker-sorting-and-purpose
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md"]

## Reviewed increment

### U1 · Общие компоненты выбора параметров и графика сортировки

- **Work items:** ["2.1", "2.2", "2.3"]
- **Requirements and scenarios:** ["intention-management: Параметры показа в поиске для выбора", "design: решение 4; Sheet.action; OptionGroup lg"]
- **Affected boundary:** Потребители дизайн-системы, цели касания и семантика экранного диктора.
- **Implementation target:** ["lib/src/design_system/components/option_group.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/arrow_down.svg", "lib/src/design_system/icons/assets/arrow_up.svg", "lib/src/design_system/icons/assets/sliders.svg", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/option_group_test.dart", "test/design_system/sheet_test.dart"]
- **Applicable constraints and non-goals:** Компоненты получают готовые тексты и типизированные значения, без предметных типов; недоступная группа сохраняет выбор и причину. Только нынешние значки и вариант группы lg. Действие листа использует общий механизм заголовка и не закрывает лист.

### U2 · Закреплённый заголовок и немедленная настройка трёх поисков

- **Work items:** ["2.4", "2.5", "2.6", "2.8"]
- **Requirements and scenarios:** ["intention-management: Экран поиска для выбора намерения", "intention-management: Заголовок списка поиска для выбора", "intention-management: Параметры показа в поиске для выбора", "intention-management: Тип намерения в поиске для выбора", "daily-choice-management: Закреплённый тип поиска действия"]
- **Affected boundary:** Общий экран выбора и страницы поиска действия, исходного намерения и участника долговременной связи; модель каталога и подтверждённые порции.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/design_system/components/catalog_header.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/picker/intention_picker_kind.dart", "lib/src/intention/presentation/picker/intention_picker_results.dart", "lib/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart", "lib/src/intention/presentation/picker/intention_picker_view.dart", "test/daily_choice/presentation/daily_choice_picker_context_test_support.dart", "test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart", "test/design_system/catalog_header_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart", "test/intention/presentation/picker/intention_picker_results_test.dart", "test/intention/presentation/picker/intention_picker_show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart", "test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart"]
- **Applicable constraints and non-goals:** Заголовок и лист сразу отражают последний выбор, числа принадлежат только подтверждённым текущим параметрам. Тип и порядок принадлежат экземпляру страницы; сохраняются охват, исключение участника, порционность, выбор по идентификатору и закрытие маршрута. Обе локализации; лист над корневым навигатором.
- **Excluded change scope:** Фазы 3–4: назначение поиска, подзаголовок, лист «Что вы выбираете», графический язык путей и форма связи. Каталог графа не получает новый интерфейс. Уже выполненная фаза 1 рассматривается только как контекст текущих потребителей.

### U3 · Продолжение поиска из пустой выдачи выбранного типа

- **Work items:** ["2.7", "2.8"]
- **Requirements and scenarios:** ["intention-management: Сброс фильтров в пустой выдаче поиска для выбора", "Пустая выдача называет обе причины", "«Сбросить фильтры» снимает название и условия", "Пустой тип предлагает показать оба типа", "Пустой охват без фильтров не предлагает сброс"]
- **Affected boundary:** Сообщения и действия пустой подтверждённой выдачи общего экрана выбора.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/picker/intention_picker_kind.dart", "lib/src/intention/presentation/picker/intention_picker_results.dart", "test/intention/presentation/picker/intention_picker_view_test.dart"]
- **Applicable constraints and non-goals:** Сброс очищает название и условия по тегам, сохраняя тип, порядок и ограничения назначения. Показ обоих типов предлагается только при наличии другого типа без фильтров. Обе локализации. Общие механизмы загрузки и отказов не дублируются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент `/root/independent_decisions`, `gpt-6.1-sol`, high, по `implementation-decision-review`: No substantive findings, Coverage Complete. U1–U3 объединены из-за пересечений целых файлов локализации, результатов и тестов. Передан нейтральный бриф и точные 31 путь поставки; плановые артефакты, описания коммитов, прежний отчёт и находки не передавались. Неизменённый контекст проверен перед чтением. |
| OpenSpec conformance | Complete | Артефакты прочитаны на сохранённой голове; задачи и сценарии сопоставлены с U1–U3. `mise exec --no-deps -- openspec validate add-intention-picker-sorting-and-purpose --strict --no-interactive --json`: exit 0, valid, issues []. `mise run check`: отказ статической части из-за восьми вызовов устаревшего API; исправление отслеживает задача 2.9. `mise run check:tests -- 0 1`: exit 0, все 3387 обычных тестов прошли. `mise run check:process-tests`: exit 0, все 18 процессных тестов прошли. `mise exec --no-deps -- flutter build apk --release`: exit 0, собран `build/app/outputs/flutter-apk/app-release.apk` (71,8 MB). `mise run codegen-check`: exit 0 на чистом дереве коммита `2bb759d2da7ccacc5b33dddcdc639f8496296dd1`; повторная генерация локализации, Riverpod/роутера и снимка Drift не изменила ни одного tracked-файла. Этот коммит отличается от сохранённой головы только отчётом; исходники и прочие входы проверок совпадают. |
| Code quality | Complete | Все 31 путь поставки проверены по корректности, читаемости, архитектуре, безопасности и производительности из `code-review-and-quality`. Проверены изменённые участки и потребители: уведомления модели, устаревшие ответы, числа, порядок переключений, прокрутка, сессии страниц, общая раскладка и семантика листов. Вызванный устаревшим API отказ воспроизведён проектной CLI-проверкой; Dart LSP подтверждает deprecated-статус `SemanticsNode.hasFlag`. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Индексы порядка по названию для архивного охвата не читает ни один запрос до сортировки каталога графа

- **Evidence:** `lib/src/data/local/schema/intention_schema.drift` на исходной голове `38cd39baf4b7979ab433974a66b2cfa02f96fed4` содержит `intentions_archived_title_search_key_asc_id_asc` и `intentions_archived_title_search_key_desc_id_asc` с условием `is_archived = 1`. Архивный охват выбирает только каталог графа намерений, а он через `_OfferedCatalogOrder` в `intention_catalog_page.dart` предлагает только четыре порядка по времени. Поиски читают активный или полный охват.
- **Evidence revisions:** ["38cd39baf4b7979ab433974a66b2cfa02f96fed4"]
- **Potential impact:** Два неиспользуемых индекса в базовом снимке схемы 6 обновляются каждой записью архивного намерения, архивированием и восстановлением и занимают место в файле. Если каталог графа получит порядок по названию в другой форме, индексы останутся мёртвыми, и убрать их можно будет только миграцией.
- **Acceptance rationale:** Владелец решил заложить основу сразу. Сортировка по названию в каталоге графа, где есть архивный охват, — ближайшее следующее изменение, а базовая схема 6 без миграции — последний случай добавить индексы без пути обновления. Цена записи для масштаба личного графа мала.
- **Scope and assumptions:** Только два индекса `(title_search_key ASC|DESC, id ASC)` с условием архивного охвата в схеме 6. Предполагается, что каталог графа получит порядок по названию через тот же ключ сохранённой проекции по ADR-0045 и с тем же курсором `(ключ, id ASC)`.
- **Reopen when:** Сортировку по названию в каталоге графа отменят или отложат на неопределённый срок; её спроектируют на другом ключе, направлении или форме курсора; схема 6 перестанет быть базовой версией без миграции.
- **Acceptance authority:** Явное решение владельца при разборе F4 ревью планирования 25.10.2026: каталог намерений с сортировкой по названию будет сделан вскоре, и основу под него нужно заложить сразу, пока это можно сделать без миграции.
- **Originating finding:** F4
- **Acceptance lifetime:** Durable
- **Decision record:** `docs/adr/0045-order-titles-by-opaque-key-of-stored-search-projection.md` («Последствия»); решение 3 и «Risks / Trade-offs» в `design.md`.
- **Current target relation:** Carried forward; not re-reviewed


## Review coverage

Проверены все восемь целевых коммитов, их изменённые пути и отметки выполнения; каждый относится к единице ниже. Единственный плановый путь в диапазоне — `tasks.md`: восемь отметок меняются на выполненные, описания и порядок задач сохраняются. Несопоставленных путей нет; точное множество поставки — все `Reviewable paths`, кроме `Planning evidence paths`.

Задача 2.1 (ID 12), коммит `f6723f5e3eaacd03da40a67515d7129b9c15ffc8`: U1.

Задача 2.2 (ID 13), коммит `9442540e24a40ee67f4387d3fb21ff1b6bb30e59`: U1.

Задача 2.3 (ID 14), коммит `88e9fcf7f8c821ed31d3375a2a2583951bae8113`: U1.

Задача 2.4 (ID 15), коммит `31d621813da422bb3f9809dc48bb6fe6abba2551`: U2.

Задача 2.5 (ID 16), коммит `dee7e025ec63312782dc5c558bec35b5a09ea62c`: U2.

Задача 2.6 (ID 17), коммит `e0fee6a332af5e41658f810800a12bad185176a9`: U2.

Задача 2.7 (ID 18), коммит `744bf9f397539db7c36a3ff0fc49d0fdd0d508f5`: U3.

Задача 2.8 (ID 19), коммит `f4b6d56847b6b24046a3ba3737428c3847ca5754`: U2, U3; проверочный коммит меняет только отметку задачи.


**U1.** SVG геометрически сверены с `ActionPicker.dc.html`; golden на сохранённой голове просмотрен в обеих темах. `doable_icon_test.dart` проверяет ресурсы, `sheet_test.dart` — общее действие, положение, семантику и прежнюю раскладку без действия; `option_group_test.dart` — выбор, недоступность, числа, равные колонки, темы, масштаб текста 2 и клавиатурный фокус. Эти проверки защищают разные границы общего механизма. Задача 2.9 сохраняет все их утверждения при замене устаревшего API.

**U2.** `IntentionPickerView` отделяет закреплённый `CatalogHeader` от прокрутки результатов. Представления берут текущий выбор из модели; `AsyncData(isLoading: false, IntentionCatalogConfirmedState)` разрешает показ чисел. Дополнительное уведомление модели между состояниями загрузки поддерживает повторный выбор до ответа. Лист применяет переходы к последнему `model.selection.order`, а сброс — только к изменяемым параметрам. Существующая инвалидизация запросов отсекает устаревшие ответы; новый интерфейс не меняет SQL, охватов или способа выбора строки.

Поиск действия с 13 результатами; закреплённый заголовок при прокрутке — `daily_choice_picker_context_test_support.dart`, `intention_picker_view_test.dart`.

Заголовок до первой порции, после отказа, при недопустимом фильтре; доступное название с числом и без — `intention_picker_view_test.dart`: цикл трёх назначений и обеих локализаций.

Последний выбор типа и сортировки без прежних чисел до подтверждения — `intention_picker_view_test.dart`: управляемые ответы настоящей модели для трёх назначений.

Выбор типа с точными числами при поиске — `intention_picker_show_and_sort_sheet_test.dart`: «выбор типа сразу меняет список, а количества учитывают поиск».

Дата ↔ название; дата ↔ дата; повторный выбор до ответа — `intention_picker_show_and_sort_sheet_test.dart`: «поле и направление меняются по последнему выбору до ответа новой порции».

Сброс исходного показа и позиции; закреплённый тип действия — `intention_picker_show_and_sort_sheet_test.dart`: два отдельных сценария сброса и закреплённого типа.

Независимость вложенных поисков и новое открытие — `intention_picker_session_test_support.dart`, используемый тремя наборами страниц.

Доступность целей касания, подписей и контраста — `catalog_header_test.dart`, `option_group_test.dart`, `intention_picker_view_test.dart`, `intention_picker_show_and_sort_sheet_test.dart`.


**U3.** `intention_picker_view_test.dart` на обоих языках покрывает пустоту по названию, тегам и обоим условиям, выбранные действия в поиске исходного намерения, пустой допустимый охват, оба направления пустого свободного типа и возврат ко всем типам. Проверка сброса также сохраняет порядок по названию, охват архивной связи и исключённого участника. Удалённые проверки заголовка из results перенесены на владеющий заголовком экран; устаревшие методы и строки удалены вместе с потребителями.

Плановые источники: `proposal.md`, три дельта-спецификации, `design.md`, `adr.md`, `plan.md` и `tasks.md` прочитаны из `f4b6d56847b6b24046a3ba3737428c3847ca5754`; канонический словарь — `CONTEXT.md`, ограничения порядка — ADR-0045. Локальные дизайн-материалы `context/doable-design-system/components/{CatalogHeader,OptionGroup,Sheet}/README.md` и `context/doable-design/design/ActionPicker.dc.html` не входят в Git-снимок: они использованы только для дополнительной визуальной сверки; нормативное поведение сверено по сохранённым OpenSpec-артефактам. Конфликтов, требующих решения владельца, не установлено.

Проверки реализации, перечисленные выше, выполнялись в рабочей папке `/home/seniorkonung/.paseo/worktrees/1id27gtb/modest-yak` на `f4b6d56847b6b24046a3ba3737428c3847ca5754`, кроме отдельно указанного `codegen-check`. Перед исходным ревью дерево было чистым; отчёт не является входом Flutter-проверок. На этапе передачи исправления в план тесты, сборки и проектные проверки повторно не запускались.

По явному решению владельца от 26.10.2026 оставшуюся работу по API семантики `OptionGroup` принимает [задача 2.9](tasks.md) фазы 2: заменить восемь устаревших вызовов, сохранить все утверждения, не подавлять диагностики и не менять инструменты. Проверка задачи — существующий тест компонента и анализ его файла. Задача добавлена в конец; все прежние задачи и отметки выполнения сохранены. Требования, дизайн и `plan.md` остаются согласованными без изменений. Реализация ещё не исправлена; успешный полный `mise run check` и готовность фазы 2 должно подтвердить следующее ревью реализации после последней задачи. AR1 сохранён без изменений; новый остаточный риск не принимался.

Release APK: `/home/seniorkonung/.paseo/worktrees/1id27gtb/modest-yak/build/app/outputs/flutter-apk/app-release.apk`, собран при исходном ревью из неизменённых исходников сохранённой головы. DTD тогда не обнаружил запущенного приложения; устройство и эмулятор не запускались. Ручные проверки пользователем остаются непроверенными: вид заголовка и листа в трёх поисках и обеих темах относительно макета, прокрутка с открытой клавиатурой, применение/сброс параметров и закреплённый тип, пустые состояния, новое открытие и объявления TalkBack. Это не препятствует завершению этапа ревью и не доказывает исправление особенностей устройства.
