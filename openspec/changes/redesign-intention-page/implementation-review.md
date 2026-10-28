# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Все восемь целевых коммитов и задачи 2.1–2.8 проверены: каркас страницы, закреплённые вкладки, типизированная цель открытия и независимое состояние статистики соответствуют границам фазы 2. Независимая оценка решений, сверка с OpenSpec и проверка качества завершены без существенных неразрешённых находок. Сохранён ранее принятый планировочный риск AR1 об оформлении замены требований. Полные проверки проекта, повторная генерация и release-сборка прошли. Фазы 3–6 остаются последующей работой.

## Review target

- **Baseline ref:** a05e50bfb3270aa2c5a3191552a0ed8f579f0ae4
- **Base commit:** a05e50bfb3270aa2c5a3191552a0ed8f579f0ae4
- **Reviewed head:** 2cc7519fceb33cf44c279cb4c59057af398a62d7
- **Target commits:** ["ae685ae21b2469401c4154b0683e9893b695ad11", "03021d0f1b34801b029bf8da3c603a40d6b67d1d", "d0b7d0c940b930050da8da43c44dfc659fd3e033", "5976e9fffe8b906d5951337b18dee78e2d0c5e8a", "0ee783e489e20929f8707184f6bae906c4af9e08", "13db381894c8efbf5ee0fbdacd51c3929421b433", "4288f5d5150ca9e7e2e7f6c9fa053b7635f22344", "2cc7519fceb33cf44c279cb4c59057af398a62d7"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/home/home_page.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/design_system/components/page_head.dart", "lib/src/design_system/components/tabs.dart", "lib/src/design_system/components/top_bar.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/back.svg", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_tabs.dart", "lib/src/intention/presentation/details/intention_page_target.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart", "lib/src/statistics/presentation/intention_statistics_section.dart", "lib/src/statistics/presentation/intention_statistics_view_model.dart", "lib/src/statistics/presentation/intention_statistics_view_model.g.dart", "openspec/changes/redesign-intention-page/tasks.md", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/intention_statistics_catalog_scenarios.dart", "test/app/intention_statistics_navigation_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_navigation_accessibility_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/routing/app_router_test.dart", "test/daily_choice/presentation/daily_choice_creation_completion_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/daily_choice/presentation/daily_choice_creation_route_scenarios.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/page_head_test.dart", "test/design_system/tabs_test.dart", "test/design_system/top_bar_test.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_head_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_statistics_test.dart", "test/intention/presentation/details/intention_details_tabs_test.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/statistics/presentation/intention_statistics_test_support.dart", "test/support/ordinary_page_test_app.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Доступные компоненты панели, шапки и вкладок

- **Work items:** ["2.1", "2.2", "2.8"]
- **Requirements and scenarios:** ["intention-management: Страница намерения и её вкладки — тип, полное название, локализованное имя при отсутствии подробностей и закрепление вкладок", "design: решения 1, 11, 12 и 14 — компоненты и проверки текущего каркаса", "tasks: критерии 2.1 и 2.2 — геометрия, темы, крупный текст, семантика, фокус и каталог иконок"]
- **Affected boundary:** Пользователь страницы, включая пользователя экранного диктора и клавиатуры; потребители представлений дизайн-системы.
- **Implementation target:** ["lib/src/design_system/components/page_head.dart", "lib/src/design_system/components/tabs.dart", "lib/src/design_system/components/top_bar.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/back.svg", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/page_head_test.dart", "test/design_system/tabs_test.dart", "test/design_system/top_bar_test.dart"]
- **Applicable constraints and non-goals:** Существующие варианты панели с крестиком и строкой назначения сохраняются. Компоненты получают готовые строки, доступные названия и обработчики, используют токены обеих тем и не зависят от предметных моделей или маршрутизации. Полное название переносится, заголовок панели ограничен одной строкой, выбранная вкладка доступна при увеличенном тексте. Эталон каталога иконок проверяет рисунок новой стрелки.
- **Excluded change scope:** Действие справа, удержание стрелки, редактирование названия через шапку, метка архива и варианты вкладок без текущего потребителя относятся к последующим частям изменения.

### U2 · Страница с закреплёнными вкладками и сохранением навигации

- **Work items:** ["2.3", "2.4", "2.5", "2.8"]
- **Requirements and scenarios:** ["intention-management: Страница намерения и её вкладки — Страница действия открывается на обзоре; Страница ненайденного намерения сохраняет доступное имя; Длинное название переходит в панель при прокрутке; «Назад» не возвращает к прежней вкладке", "intention-management: Счётчики групп на странице намерения — число активных и отметка архива на вкладке", "app-navigation: Панель на обычных страницах; Сброс истории выбором пункта", "plan: Phase 2 — прежние содержимое и общее состояние соседства", "tasks: 2.5 — положение при смене вкладки и отсутствие повторного применения прежнего якоря"]
- **Affected boundary:** Страница намерения, общая прокрутка, соседство связей, оболочка обычных страниц и существующие потоки создания, изменения и удаления.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_tabs.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_navigation_accessibility_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/routing/app_router_test.dart", "test/daily_choice/presentation/daily_choice_creation_completion_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/daily_choice/presentation/daily_choice_creation_route_scenarios.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_head_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_tabs_test.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/support/ordinary_page_test_app.dart"]
- **Applicable constraints and non-goals:** Обзор содержит прежние данные, действия, встроенную правку и теги; Связи — прежнее соседство. Переключение не создаёт маршрут и сохраняет вкладку при возврате сверху. При скрытой шапке новое тело начинается под закреплёнными вкладками; при видимой сохраняется смещение. До первого показа Связей чтения групп нет, затем соседство удерживается до закрытия страницы. Число на вкладке берётся из сводки подробных данных; дневные роли в него не входят. Схема хранения и правила команд не меняются.
- **Excluded change scope:** Вкладка Выборы, новый вид Обзора и Связей, отдельный экран правки, параметры, новая политика сообщений и состояние связей экземпляра страницы принадлежат фазам 3–6. Освобождение порций соседства при каждом переключении пока не является обязанностью этой фазы.

### U3 · Цель открытия и статистика видимого экземпляра страницы

- **Work items:** ["2.6", "2.7", "2.8"]
- **Requirements and scenarios:** ["intention-management: Цель открытия страницы намерения — выбор доступной вкладки и независимость состояния экземпляров", "intention-management: Раздел статистики на странице намерения — Страница открывается на разделе статистики", "contribution-statistics: Переходы из статистики — Элемент Главной открывает тот же вид; Элемент разбивки открывает соответствующий вид; День открывает каталог на эту дату", "contribution-statistics: Согласование статистики с изменениями; Состояния получения статистики", "design: решения 2 и 9; ADR-0027; ADR-0028"]
- **Affected boundary:** Вызывающие страницу Главная и разбивки статистики, экземпляр страницы, модель статистики и видимость маршрута.
- **Implementation target:** ["lib/src/app/home/home_page.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_page_target.dart", "lib/src/statistics/presentation/intention_statistics_section.dart", "lib/src/statistics/presentation/intention_statistics_view_model.dart", "lib/src/statistics/presentation/intention_statistics_view_model.g.dart", "test/app/intention_statistics_app_flow_test.dart", "test/app/intention_statistics_catalog_scenarios.dart", "test/app/intention_statistics_navigation_test.dart", "test/intention/presentation/details/intention_details_statistics_test.dart", "test/intention/presentation/details/intention_details_tabs_test.dart", "test/statistics/presentation/intention_statistics_test_support.dart"]
- **Applicable constraints and non-goals:** Начальная цель применяется один раз и допускает только доступные вкладки. Период, вид и загруженные порции статистики сохраняются при смене вкладки и независимы у разных страниц одного намерения. Смена идентификатора у виджета создаёт новый экземпляр. Чтения разрешены только текущему маршруту с выбранной Статистикой; накопленные изменения вызывают одно обновление при показе. Уведомление об обновлении остаётся ниже полосы вкладок. Обычные вызовы без цели открывают Обзор.
- **Excluded change scope:** Группа связей в цели появится в фазе 6, цель Выборов — в фазе 5. Формулы статистики и её оформление не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих рецензента без истории диалога, gpt-6.1-sol/high: `/root/decision_components` проверил все 11 путей U1; `/root/decision_page` — объединение всех 43 путей U2/U3. U2 и U3 объединены из-за общих изменённых файлов, U1 не пересекается с ними. Переданы только нейтральные цели, ограничения, точные base/head и границы путей; планирование, отчёты и прежние риски не передавались. Оба результата — No substantive findings, Coverage: Complete. |
| OpenSpec conformance | Complete | Сопоставлены все задачи, коммиты, применимые требования и сценарии. Артефакты прочитаны из записанного head. Строгая проверка OpenSpec, полный `mise run check`, `mise run codegen-check` и release-сборка завершились с кодом 0 в корне репозитория на записанном head; свидетельства ниже. |
| Code quality | Complete | По `code-review-and-quality` проверены все 54 пути реализации, локализаций, сгенерированного кода, ресурсов и тестов: корректность, читаемость, архитектура, безопасность и производительность. Прослежены существующие потребители, наблюдение деталей, видимость статистики, якоря и ограниченные порции соседства. Существенных дефектов и необоснованного расширения текущего этапа не установлено. |

## Findings

No unresolved findings remain in the implementation review.

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

Проверка выполнена в `/home/seniorkonung/.paseo/worktrees/1id27gtb/real-fireant` на `2cc7519fceb33cf44c279cb4c59057af398a62d7`. Исходная рабочая копия чистая, HEAD совпадал с Reviewed head; исключённых незакоммиченных изменений нет. Все 55 путей записанного diff учтены: 54 пути входят в U1–U3, `tasks.md` служит свидетельством планирования. Это также точное подмножество путей реализации для проверки качества. Несопоставленных и посторонних путей нет. Неизменённые зависимости изучались только как контекст.

Proposal, все шесть delta-спецификаций, design, ADR-манифест, plan и tasks прочитаны из записанного head. Дополнительно сверены каноническая спецификация contribution-statistics, ADR-0027, ADR-0028 и термины CONTEXT.md. Статус и `instructions apply` использованы только для определения графа артефактов и прогресса. Внешние README компонентов из `context/doable-design-system/components/` не версионируются этим репозиторием и использованы как вспомогательный контекст; обязательства текущего этапа закреплены в committed tasks и design. Неподтверждённые внешние материалы не использованы для оправдания реализации.

AR1 перенесён из предыдущего отчёта с исходной ревизией свидетельства и явным указанием, что он не переоценивался в текущем диапазоне. Условие его принятия сохраняется в неизменённых delta-спецификациях и `review.md`; его сохранение не означает нового принятия риска. Планировочный AR2 о трёх колонках CountTiles остаётся в `review.md` и ADR-0048, относится к фазе 6 и реализацией этого этапа не затронут.

Каждый целевой коммит сопоставлен со своей задачей:

taskId 10, задача 2.1, коммит `ae685ae21b2469401c4154b0683e9893b695ad11`. U1: варианты TopBar, стрелка, доступное имя без видимого заголовка, ресурс и эталон иконок.

taskId 11, задача 2.2, коммит `03021d0f1b34801b029bf8da3c603a40d6b67d1d`. U1: PageHead и Tabs, семантика, горизонтальная прокрутка, крупный текст и фокус.

taskId 12, задача 2.3, коммит `d0b7d0c940b930050da8da43c44dfc659fd3e033`. U2: панель типа, измеряемая шапка, переход названия при прокрутке; состояния чтения и прежние вызовы возврата.

taskId 13, задача 2.4, коммит `5976e9fffe8b906d5951337b18dee78e2d0c5e8a`. U2: вкладки, перенос прежнего содержимого, отложенный старт и удержание соседства, числа и переход к архиву; адаптация потребителей.

taskId 14, задача 2.5, коммит `0ee783e489e20929f8707184f6bae906c4af9e08`. U2: смещение при смене вкладки, минимальная высота тела, линия закрепления и восстановление только новых якорей.

taskId 15, задача 2.6, коммит `13db381894c8efbf5ee0fbdacd51c3929421b433`. U3: единая синхронизация видимости по маршруту и вкладке, отложенное чтение и сохранение порций.

taskId 16, задача 2.7, коммит `4288f5d5150ca9e7e2e7f6c9fa053b7635f22344`. U3: закрытый тип цели, ключ экземпляра, маршруты, провайдеры и оба вызывающих со статистикой.

taskId 17, задача 2.8, коммит `2cc7519fceb33cf44c279cb4c59057af398a62d7`. U1–U3: корректировка сквозных проверок под вкладки и подтверждение готовности свежими проверками и сборкой этой сессии.

Проверены также все восемь последовательных taskCommitRanges из workflow. В каждом коммите `tasks.md` меняет только ожидаемую отметку своей задачи с незавершённой на завершённую: номера, описания, порядок и остальные отметки сохранены. Все задачи 2.1–2.8 остаются завершёнными; задачи и план в review не редактировались.

Ключевые сценарии проверены по следующим свидетельствам записанного head:

Тип, полное название, стрелка и доступное имя без заголовка во время загрузки, отсутствия намерения или отказа. `intention_details_page.dart:243`, `intention_details_head_test.dart:20` и `:60`; варианты панели проверены на обоих языках, компонент — в обеих темах.

Длинное название заменяет тип и возвращает его; архивное название приглушено, масштаб текста меняет порог. `intention_details_page.dart:165`, `intention_details_head_test.dart:107` и `:146`; геометрия и отсутствие усечения PageHead — `page_head_test.dart:50`.

Выбор вкладок, число активных связей и архив в семантике; прокрутка и фокус без изменения вертикального положения. `intention_details_tabs.dart:29`, `intention_details_tabs_test.dart:199`; `tabs_test.dart:48`, `:196`, `:251` и `:283`.

Первое открытие Обзора без чтения групп, отложенное открытие Связей и переход к архивной группе. `intention_details_page.dart:100`, `intention_details_tabs_test.dart:38`, `:133` и `:199`; архив выбирается по подтверждённой сводке страницы.

Вкладки остаются под панелью; смена вкладки сохраняет видимую шапку или начинает тело под закреплёнными вкладками. `intention_details_page.dart:111`, `intention_details_tabs.dart:101`; `intention_details_tabs_test.dart:60` и `:96`, включая короткое тело и высокий viewport.

Прежний якорь не сдвигает повторно показанные Связи; новое согласование видимого списка сохраняет строку. `relation_neighborhood_sliver.dart:84` и `:310`; новые проверки `relation_neighborhood_widget_test.dart:698` для обоих положений шапки, сохранённая проверка согласования `:612`.

«Назад» закрывает страницу после смены вкладок; возврат сверху сохраняет вкладку, группу и позицию. `intention_details_tabs_test.dart:254`; изменённые app/navigation и routing тесты сохраняют нижнюю панель, сброс истории и отсутствие поздней навигации закрытого маршрута.

Статистика не читается под другим маршрутом и на других вкладках, обновляется один раз при показе, сохраняет условия. `intention_details_page.dart:146`; `intention_details_statistics_test.dart:323` и `:671`, существующие проверки модели в `test/statistics/presentation/`.

Уведомление обновления и повтор остаются под вкладками в обеих ориентациях и локалях. `intention_statistics_section.dart:37`; `intention_details_statistics_test.dart:50` проверяет уведомление над обзором и обеими разбивками.

Начальная цель применяется один раз, смена намерения создаёт новый экземпляр; две страницы одного намерения независимы. `intention_page_target.dart:4` и `:24`, `intention_details_page.dart:90` и `:207`; `intention_details_statistics_test.dart:434` и `:539`.

Главная и все разбивки передают правильные вид и период; возврат сохраняет условия, порции и прокрутку. `home_page.dart:104`, `intention_statistics_section.dart:99`; `intention_statistics_navigation_test.dart:35`, `:75` и `:119`, дополнительно сквозные сценарии статистики.

Прежние правка, теги, создание связей и дневных выборов, архивирование и удаление доступны на своих вкладках. Сохранённые ожидания в details, long_term_relation, daily_choice и app тестах; изменения выбирают нужную вкладку и новый элемент возврата. Проверки данных и результатов операций не заменены ожиданием одного лишь открытия вкладки.

Во всех ссылках без каталога используются файлы из перечисленных Implementation target. Компоненты остаются представлениями; выбранная вкладка и статистика принадлежат экземпляру, данные намерения и временно удерживаемое соседство — идентичности намерения по границам фазы. Поздние ответы защищены существующими поколениями моделей. Новых внешних интеграций, зависимостей, SQL, миграций, диагностических событий или обрабатываемых пользовательских данных нет. Локализации ru/en и сгенерированные маршруты/провайдеры сверены с исходниками и повторной генерацией. Новые проверки охраняют договорённости компонентов, границы видимости и состояния; необоснованных вариантов или сценариев вне текущего этапа не установлено.

Свежая проверка в этой сессии на записанном head, до изменения файла отчёта:

Команда `mise run check`. Код 0: форматирование 808 файлов без изменений, обе shell-проверки, `flutter analyze` без замечаний, 3474 обычных теста и 18 тестов `flutter_process` прошли.

Команда `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json`. Код 0; `valid: true`, список issues пуст.

Команда `mise run codegen-check`. Код 0 на чистой рабочей копии; повторная генерация локализации, провайдеров, маршрутов и схемы не изменила файлы.

Команда `mise exec --no-deps -- flutter build apk --release`. Код 0; `build/app/outputs/flutter-apk/app-release.apk`, 71.9 MB. SHA-256: `fde08cfec6f637bebf4f68e7a9f8dcb35c5f469cdf5dd9ffb750fa55cc412447`.

Команда `git diff --check a05e50bfb3270aa2c5a3191552a0ed8f579f0ae4 2cc7519fceb33cf44c279cb4c59057af398a62d7`. Код 0, ошибок пробелов нет.

Поиск в `lib/` и `test/` на записанном head. `statisticsTarget` отсутствует; в файле страницы нет AppBar, единственное использование `detailsTitle` — `routeName` панели без видимого заголовка, строка 259.

Dart MCP: roots add, затем DTD listDtdUris. Запущенных debug-приложений и DTD нет; hot restart и runtime errors неприменимы. Использованы CLI-проверки; устройство и эмулятор не запускались.

APK для пользователя: [app-release.apk](../../../build/app/outputs/flutter-apk/app-release.apk). На устройстве остаются неподтверждёнными: тип и значок панели, перенос длинного названия в панель и обратно, приглушение архивного названия; закреплённые вкладки с линией и прокруткой при крупном шрифте, число и архив на Связях; открытие Статистики с Главной и из разбивки с нужными видом и периодом; возврат после переключения вкладок. Эти ручные проверки не блокируют завершение фазы по правилам репозитория и не объявлены выполненными.

Код, тесты и плановые артефакты в review не исправлялись; проверка не выявила работы, требующей новых задач или передачи на ремедиацию. Незавершённых решений нет. Сохранённый AR1 остаётся принятым планировочным риском, без нового принятия. Отчёт фиксирует свидетельства проверки; переходом к следующим фазам и публикацией управляет оркестратор.
