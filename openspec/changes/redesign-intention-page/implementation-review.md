# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Проверены все коммиты фазы 5 (задачи 5.1–5.10). Вкладка «Выборы», её модель экземпляра, «Добавить», возврат после создания и удаление дневных групп из соседства соответствуют требованиям и задачам. Нарушений поведения не найдено, полный `mise run check` на голове прошёл. Остаётся одна находка низкой серьёзности. F15: протокол согласования списка с графом скопирован в модель «Выборов», а не получил одного владельца. Сохранены принятые риски AR1, AR2 и AR3.

## Review target

- **Baseline ref:** f3af97106c8fe878eb80af98d28eed44d79e2de4
- **Base commit:** f3af97106c8fe878eb80af98d28eed44d79e2de4
- **Reviewed head:** 5b52b0da6d38673d7b061f3cf3a22672367d6f3a
- **Target commits:** ["874a1d9061364c07c803253121cbfa2046310748","c8f59a23c0696f4aa234ee0a5ac96f50e214c563","d6926b61e19647217f90f53484803ef36f698b90","1ea62240572a19d3da552dc188ea91b50a09d4eb","55e45aa4eca7451854a3dce3ad2ec344ffbe198c","55bf75ef1a4d0886051c0585aaa51624a84d3fe9","81e45c9cb9350841cef3eef63127b144d72f8717","15f032f6321c727be86724f7650ab3e1beee53b9","0721a7504f48f7d215993edd25b6ad96cec6255d","5b52b0da6d38673d7b061f3cf3a22672367d6f3a"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_state.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.g.dart","lib/src/design_system/components/add_row.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/intention/presentation/details/intention_details_tabs.dart","lib/src/intention/presentation/details/intention_page_target.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart","openspec/changes/redesign-intention-page/tasks.md","test/app/daily_choice_app_flow_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/routing/app_router_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart","test/design_system/add_row_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/intention/presentation/details/intention_details_choices_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/intention/presentation/details/intention_details_tabs_test.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart","test/support/intention_choices_tab.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Дневные выборы страницы и их создание идут через вкладку «Выборы» экземпляра страницы

- **Work items:** ["5.1","5.2","5.3","5.5","5.6","5.7","5.10"]
- **Requirements and scenarios:** ["intention-management: Страница намерения и её вкладки / Возвращение к выборам сохраняет роль и начинает список заново", "intention-management: Цель открытия страницы намерения / Две страницы одного намерения не влияют друг на друга", "intention-management: Получение блокирующих связей намерения / Прямые дневные зависимости доступны в обеих ролях", "daily-choice-management: Входы в создание дневного выбора / Вход со страницы намерения не требует поиска, Вход со страницы действия идёт снизу вверх", "daily-choice-management: Открытие созданного дневного выбора / Созданный выбор открывается вместо построения пути", "design: решения 2 и 8"]
- **Affected boundary:** Пользователь страницы намерения; состояние экземпляра страницы и чтения групп дневных выборов из локального графа; вход в существующий поток создания дневного выбора
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_state.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart","lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.g.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/intention/presentation/details/intention_details_tabs.dart","lib/src/intention/presentation/details/intention_page_target.dart","test/app/daily_choice_app_flow_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/routing/app_router_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart","test/intention/presentation/details/intention_details_choices_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/intention/presentation/details/intention_details_tabs_test.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/support/intention_choices_tab.dart"]
- **Applicable constraints and non-goals:** Схема, формат графа, журнал фактов и копии не меняются. Строки и переключатель ролей переносятся без нового оформления. Роли «на пути» и числа на вкладке нет. Роль принадлежит экземпляру страницы; данные намерения общие для его страниц. Маршруты создания сами владеют границей потока (ADR-0022).
- **Excluded change scope:** Вкладка «Связи» по дизайну, удаление прежнего соседства и его политики порций относятся к фазе 6 и не считались обязательствами диапазона.

### U2 · Строка `AddRow` с подсказкой, без «Добавить» или без подсказки

- **Work items:** ["5.4"]
- **Requirements and scenarios:** ["design: решение 11 — компоненты дизайн-системы", "README `AddRow` дизайн-системы"]
- **Affected boundary:** Потребители компонента `AddRow` и пользователь, читающий и нажимающий строку
- **Implementation target:** ["lib/src/design_system/components/add_row.dart","test/design_system/add_row_test.dart"]
- **Applicable constraints and non-goals:** Компонент только презентационный (ADR-0030). Варианты добавляются только для текущего потребителя. Строка с заголовком и `TagsSection` сохраняют поведение; выключенного «Добавить» в строке с подсказкой нет.

### U3 · В соседстве на «Связях» больше нет дневных групп

- **Work items:** ["5.8","5.9"]
- **Requirements and scenarios:** ["plan: фаза 5, результат «Прежнее соседство на вкладке «Связи» больше не содержит дневных групп»", "long-term-relation-management: Согласованность счётчиков с подтверждёнными изменениями графа"]
- **Affected boundary:** Модель и вид соседства на вкладке «Связи»; проверки согласования графа и состояния оболочки
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart","test/app/navigation/app_shell_state_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/intention/presentation/details/intention_details_page_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart"]
- **Applicable constraints and non-goals:** Долговременные группы, их порции и якоря, полная сводка и её согласование, в том числе после изменений дневных выборов, не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных рецензента по `implementation-decision-review` с нейтральными брифами, без артефактов планирования, ADR, истории коммитов и прежнего отчёта. U1 и U3 делят `intention_details_page.dart`, поэтому их проверял один рецензент по объединённому списку из 32 путей. Он прогнал 85 тестов из 6 наборов и `flutter analyze` по затронутым каталогам. U2 проверял второй рецензент по 2 путям: 21 тест `add_row_test.dart` и `tags_section_test.dart`, `flutter analyze`. Оба сообщили полное покрытие назначенных путей. |
| OpenSpec conformance | Complete | Критерии 5.1–5.10 сверены с диффом и проверками в обе стороны. Команды `rg` из 5.7 и 5.9 ничего не находят. `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json` дал valid, все 73 задачи отмечены. Полный `mise run check` прошёл в рабочей копии, совпадавшей с 5b52b0da6d38673d7b061f3cf3a22672367d6f3a и чистой: format (840 файлов, 0 изменено), проверки скриптов, `flutter analyze` без замечаний, 3689 обычных и 18 процессных тестов. APK `build/app/outputs/flutter-apk/app-release.apk` собран реализацией 5.10 вместе с головой. Проверки на устройстве не выполнялись: по правилам проекта они за пользователем. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены в контексте координатора к путям доставки на голове: модель, состояние и sliver «Выборов», удержание модели страницей, цель открытия, `AddRow`, урезанные модель, состояние и вид соседства, строки локализации. |

## Findings

### F15 · Low — Протокол согласования списка с графом скопирован в модель «Выборов»

- **Evidence:** `lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart` почти построчно повторяет слой над общим ядром порций из `relation_neighborhood_view_model.dart`. Повторяются подписка на `watchIntention` и завершения координатора (309–336 против 381–408), разбор наблюдения намерения (338–371 против 410–448), разбор завершений (373–389 против 450–470), сравнение ревизий и запуск пересборки, цикл пересборки, первое чтение и подгрузка (137–249 против 188–281), сопоставление отказов и завершение контекста. Отдельно скопированы статусы сводки и подгрузки в `intention_choices_state.dart:130-182` и виджет статуса с сообщениями отказов в `intention_choices_sliver.dart:430-504`. Копии уже расходятся в устройстве при одинаковом поведении: `_isNewerThanKnown` против ручных сравнений, `_noteUnrelatedRevision` против `_noteUnrelatedTagRevision`. Размер порции «Выборов» берётся из `relationNeighborhoodPagingPolicyProvider` соседства (`intention_choices_view_model.dart:19, 63`). По плану в фазе 6 соседство заменяется новой моделью «Связей», которой нужен тот же протокол.
- **Evidence revisions:** ["5b52b0da6d38673d7b061f3cf3a22672367d6f3a"]
- **Impact:** Самая хрупкая часть списков — поздние ответы, устаревшие продолжения, чужие ревизии и удаление намерения — получает отдельного владельца на каждой вкладке и отдельный набор проверок одних и тех же гонок. Исправление в одной копии не доходит до другой, а модель «Связей» фазы 6 добавит третью копию. Дефект такого рода проявится как устаревший список или пропущенное обновление только на одной вкладке.
- **Required outcome:** У протокола согласования порционного списка страницы с подтверждёнными изменениями графа одно место владения. Вкладка задаёт только своё: запрос порции, принадлежность строки, признак значимого изменения и форму состояния. Параметры порций «Выборов» не принадлежат удаляемой модели соседства.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** ["design.md: решения 6, 8 и 14", "plan.md: фаза 6", "lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart", "lib/src/long_term_relation/presentation/relation_group_paging.dart"]
- **Decision needed:** Выносить ли общий слой согласования сейчас, отдельной задачей фазы 5, или при построении модели «Связей» в фазе 6, либо принять дублирование как остаточный риск. Выбор меняет объём фазы 6 и её проверки.

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

### AR2 · Заголовок панели экрана изменения перекрывается кнопкой «Сохранить»

- **Evidence:** `TopBar.withButton` центрирует заголовок с постоянным отступом 64 с каждой стороны (`lib/src/design_system/components/top_bar.dart:49, 276-278`). Поверх него справа, в `space-3` от края, рисуется кнопка `sm` (`top_bar.dart:348-358`). Временный тест со шрифтом Inter для «Изменить намерение» и «Сохранить» показал перекрытие. На ширине 360 при масштабе 1: заголовок 90–270, плашка 240–348. На 390: заголовок до 284,6, плашка от 270,5. При масштабе 1,3 перекрытие достигает 52–66 px. Отступ 64 взят из README `TopBar` дизайн-системы, которая рассчитана на английские подписи, и из критерия задачи 3.3. `test/design_system/top_bar_test.dart:379-401` закрепляет нынешнее положение.
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Potential impact:** На обычных телефонах на русском языке конец заголовка «Изменить намерение» закрыт кнопкой «Сохранить», а при увеличенном тексте закрыт сильнее. Видимый заголовок маршрута теряет читаемость. Доступное имя маршрута для диктора не меняется.
- **Acceptance rationale:** Пользователь решил пока не менять раскладку и оставить её как есть: исправит позже, когда увидит экран на своём устройстве. Выбор между строгим центром с сильной обрезкой, сдвигом от кнопки и более коротким заголовком требует визуальной оценки.
- **Scope and assumptions:** Только раскладка заголовка `TopBar` с кнопкой справа на экране «Изменить намерение» по задаче 3.3 и правилу 64 px из README. Кнопка остаётся доступной для нажатия и не меняет поведение сохранения. Принятие не распространяется на новых потребителей панели с кнопкой справа.
- **Reopen when:** Пользователь после проверки на устройстве решит исправить раскладку; у панели с кнопкой справа появится другой потребитель; перекрытие начнёт закрывать саму кнопку или мешать нажатию на неё.
- **Acceptance authority:** Явное решение пользователя при разборе F7 (28.10.2026): «Пока что ничего не меняю, ставь так же точно, как сейчас. Это будет принятый риск. Я потом исправлю, когда увижу, как это выглядит».
- **Originating finding:** F7
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

### AR3 · Область нажатия названия в шапке ниже `tap-min`

- **Evidence:** `PageHead` оборачивает в `InkWell` только `Text` названия (`lib/src/design_system/components/page_head.dart:26-45`). Поля 2 и 6 стоят снаружи, поэтому однострочное название `page-title` даёт область нажатия высотой 30. `test/design_system/page_head_test.dart:41-46` закрепляет эти поля. Общее правило дизайн-системы требует у элемента управления область нажатия не меньше `tap-min` = 44 (`context/doable-design-system/tokens.json:483-486`, `context/doable-design-system/README.md:76`). README `PageHead` называет название кнопкой и задаёт шапке поля 2 и 6, за которыми сразу идут вкладки. Поэтому без изменения видимой раскладки однострочное название до 44 не дотягивает.
- **Evidence revisions:** ["5eb233b2cefcafbe15b3a217be50b3a5bdbddc7c"]
- **Potential impact:** В фазе 3 нажатие на название — единственный вход в правку. Цель высотой 30 вместо 44 труднее поймать, особенно при нарушениях моторики. Минимум WCAG 2.2 AA (24×24) выполняется, цель занимает всю ширину содержимого.
- **Acceptance rationale:** Пользователь решил следовать макету `PageHead`: кликабельно только название с видимыми полями из макета, без расширения до `tap-min`. Расширение потребовало бы опустить вкладки на 6 px или вывести область нажатия за пределы шапки — в верхнюю панель или вкладки.
- **Scope and assumptions:** Только область нажатия названия в `PageHead` на странице намерения. Видимая раскладка и поля шапки соответствуют README `PageHead`. Правило `tap-min` для остальных элементов управления остаётся обязательным.
- **Reopen when:** Макет или README `PageHead` изменят поля шапки или явно потребуют `tap-min` для названия; пользователь решит расширить область нажатия после проверки на устройстве; у `PageHead` появится потребитель, для которого название — единственный вход в действие без иных путей после фазы 4.
- **Acceptance authority:** Явное решение пользователя при разборе F8 (28.10.2026): «Делай по дизайну, как сейчас в дизайне. Если в дизайне меньше 44 пикселей, делай меньше».
- **Originating finding:** F8
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

Модель «Выборов». Семейство по `IntentionId` и `IntentionPageInstance`; роль хранится в экземпляре страницы и записывается при смене. Страница удерживает модель через `listenManual`, только пока выбрана вкладка, в том числе под открытыми над ней страницами. Уход на другую вкладку и смена намерения закрывают подписку, а autoDispose освобождает строки, продолжения и подписки. Поколения ядра порций и `ref.mounted` отбрасывают поздние ответы прежней роли и освобождённой модели. Согласование реагирует на `DailyChoiceChange` своей роли и загруженных строк, изменения участников, изменённую сводку, удаление намерения и чужие ревизии тегов; прежняя пара показывается до замены. Проверки модели воспроизводят дневные проверки соседства и добавляют роль по умолчанию, сохранённую роль, независимость экземпляров и молчание после освобождения.

Страница и вход в создание. Порядок вкладок, отсутствие числа и доступное имя «Выборов» на двух языках, отсутствие чтений на «Обзоре», «Связях» и «Статистике», цель `ChoicesTarget`, независимость двух страниц и возвращение с сохранённой ролью и одной первой порцией подтверждены проверками страницы. «Добавить» берёт доступность из принятого снимка: «исходное» у активного намерения, «выбранное» у активного действия, нет у архивированного и у «выбранного» неготового. Подсказка показывается только у непустого подтверждённого списка; строка только с подсказкой у архивированного намерения соответствует README `AddRow` («The row has no Add where nothing can be added»). Сценарий потока создания подтверждает открытие созданного выбора и возвращение на «Выборы» с той же ролью и новой строкой без шагов пути в истории. Дублирующие проверки маршрутизатора удалены, их ожидания покрыты проверками 5.5.

Соседство. Состояние больше не несёт группы: она выводится из долговременного выбора. Ветви дневных групп, `selectDailyGroup` и дневные строки вида удалены, согласование сводки по изменениям дневных выборов сохранено. Все строки `relationNeighborhood*` по-прежнему используются; удалена только `detailsChoosePathAction`.

Находки рецензентов. Обе подтверждены сверкой с кодом. Замечание о публичных nullable-геттерах `AddRow` передано в планирование задачей 5.11 по решению пользователя; протокол согласования записан как F15. Вопрос рецензента U1 о строке с одной подсказкой снят README `AddRow`.

Принятые риски. Диапазон не трогает delta-спецификации, `TopBar` с кнопкой справа и `PageHead`: условия AR1, AR2 и AR3 сохраняются.

Правила проекта. Комментарии и названия проверок на русском. Обычные проверки не измеряют время. Схемы, данных и миграций диапазон не касается.

Не выполнено: ручные проверки на устройстве из 5.10. За пользователем остаются вкладка «Выборы» между «Связями» и «Статистикой» без числа с прежними строками и переключателем ролей; «Добавить» у обеих ролей и его отсутствие у архивированного намерения и у «выбранного» неготового; сохранение роли после ухода на «Обзор» и после создания выбора; обе темы и увеличенный текст.
