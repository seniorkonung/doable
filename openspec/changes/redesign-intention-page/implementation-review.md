# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все три целевых коммита и задачи 3.14–3.16. Ожидание свежего снимка перед входом в правку (3.14) и ввод названия без переносов строк (3.15) соответствуют требованиям. Прокрутка к отказу сохранения (3.16) соответствует требованию, кроме случая возвращения клавиатуры после отказа. Его исправление тем, что экран снимает фокус с полей при новом отказе, закреплено в решении 5 design и в незавершённой задаче 3.17. Сохранены принятые риски AR1, AR2 и AR3.

## Review target

- **Baseline ref:** 5be66fb509d64b71a6a0ad4d287d7543a427b8aa
- **Base commit:** 5be66fb509d64b71a6a0ad4d287d7543a427b8aa
- **Reviewed head:** 185ed6942eadc6275a0f2a423ad622ec460bb149
- **Target commits:** ["40942abc4f94e5295c7d6bf075b9856a3da43656", "984e7a461b508acf0e3988f82914406141c83dc8", "185ed6942eadc6275a0f2a423ad622ec460bb149"]
- **Reviewable paths:** ["lib/src/design_system/components/text_field.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "lib/src/intention/presentation/edit/intention_edit_page.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "openspec/changes/redesign-intention-page/tasks.md", "test/design_system/text_field_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/edit/intention_edit_page_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Вход в правку ждёт снимка с подтверждённым текстом

- **Work items:** ["3.14"]
- **Requirements and scenarios:** ["intention-management: Экран изменения намерения", "design: решение 3"]
- **Affected boundary:** Пользователь страницы намерения; модель подробных данных между каналом завершений координатора и наблюдением хранилища
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "test/intention/presentation/details/intention_details_page_test.dart"]
- **Applicable constraints and non-goals:** Контракт координатора не меняется: он снимает занятость до перечитывания. Проверки обходятся без задержек и измерения времени.
- **Excluded change scope:** Входы в правку из описания и параметров относятся к фазе 4, и plan.md уже требует от них той же доступности.

### U2 · Название намерения без переносов строк

- **Work items:** ["3.15"]
- **Requirements and scenarios:** ["intention-management: Ввод названия намерения без переносов строк"]
- **Affected boundary:** Пользователь, который вводит или вставляет название на экране изменения и в панели создания; общее поле `TextField` дизайн-системы
- **Implementation target:** ["lib/src/design_system/components/text_field.dart", "lib/src/intention/presentation/edit/intention_edit_page.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "test/design_system/text_field_test.dart", "test/intention/presentation/edit/intention_edit_page_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart"]
- **Applicable constraints and non-goals:** Нормализация и проверка названия в домене, импорт и сохранённые данные не меняются. Поле описания принимает переносы строк.

### U3 · Отказ сохранения виден на прокрученном экране изменения

- **Work items:** ["3.16"]
- **Requirements and scenarios:** ["intention-management: Экран изменения намерения", "intention-management: Экран изменения намерения / Отказ сохранения виден на прокрученном экране", "design: решение 5, «Как показываются отказы»"]
- **Affected boundary:** Пользователь экрана изменения и экранный диктор; протокол предъявления отказа между экраном и оболочкой по ADR-0012
- **Implementation target:** ["lib/src/intention/presentation/edit/intention_edit_page.dart", "test/intention/presentation/edit/intention_edit_page_test.dart"]
- **Applicable constraints and non-goals:** Предъявление подтверждается свидетельством кадра `OperationFailurePresentation`. Тексты и места отказов не меняются. Введённый текст и позиция курсора сохраняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных рецензента работали по `implementation-decision-review` с нейтральными брифами, без артефактов планирования, истории коммитов и прежнего отчёта. Первый проверил U1: 4 пути. Второй проверил U2 и U3 вместе по общей границе из 6 путей, потому что у них общие `intention_edit_page.dart` и его проверки. Оба сообщили полное покрытие. Код они не запускали. |
| OpenSpec conformance | Complete | Задачи 3.14–3.16 сверены с требованиями «Экран изменения намерения» и «Ввод названия намерения без переносов строк», а также с решениями 3 и 5 design. `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json` дал valid. Рабочая копия совпадает с 185ed6942eadc6275a0f2a423ad622ec460bb149 и чиста. Целевой прогон `flutter test test/design_system/text_field_test.dart test/intention/presentation/edit test/intention/presentation/editor test/intention/presentation/details test/app/intention_app_lifecycle_test.dart` прошёл: 249 тестов. Полный `mise run check` на той же ревизии прошёл: format, проверки скриптов, `flutter analyze` без замечаний, 3546 обычных тестов и 18 процессных. Ручная проверка на устройстве не выполнялась. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены в контексте координатора ко всем путям доставки. Проверены установка и снятие признака ожидания снимка, ревизионный барьер, повторная проверка перед открытием маршрута и единственность общего `GlobalKey` отказа. Также проверены правило замены переносов, его единственный источник и потребители `TextField.multiline` вида `name`. Возвращение клавиатуры после отказа воспроизведено временным виджет-тестом; тест удалён, рабочая копия чистая. |

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

Признак ожидания снимка. Признак ставится только при завершении, которое затрагивает это намерение и проходит ревизионный барьер, уже после запуска нового поколения наблюдения. Снимается он только новым `IntentionDetailsLoaded`, который строится из снимка не старше подтверждённой ревизии. Устаревший снимок отвергается, и признак остаётся. `copyWith` в обновлении занятости и переходах состояния его сохраняет. Отказ перечитывания переводит страницу в прежние состояния отказа, а модель экрана изменения требует `IntentionDetailsLoaded`. Шапка в это время показывает прежнее название. `_openEdit` перед открытием маршрута заново читает состояние и занятость. Канал завершений синхронный, поэтому признак ставится раньше, чем до страницы может дойти нажатие. Рецензент отметил, что выключенное название визуально не отличается от включённого. Это нынешний контракт `PageHead`, им же пользуется занятость из 3.8, а окно длится одно локальное чтение. Критерий 3.14 выполнен через выключенное состояние кнопки, поэтому находкой это не записано.

Ввод названия. Правило замены `\r\n|[\r\n]` на пробел задано одним `lineBreakToSpaceFormatter` и используется растущим полем вида `name` и полем названия панели создания. Единственный потребитель `TextField.multiline` вида `name` — экран изменения. Клавиатура текстовая, действие клавиши ввода — «далее», и проверка экрана закрепляет переход фокуса в описание. Рецензент отметил, что формат применяется ко всему значению поля. Поэтому при первой правке названия, полученного другим путём с переносами, переносы этого названия тоже станут пробелами. Требование запрещает полю принимать перенос строки и сохраняет такое название без изменений, только пока его не правят. Поэтому находкой это не записано.

Прокрутка к отказу. Три места отказа взаимоисключающие, поэтому общий `GlobalKey` не встречается дважды. Ближайшая прокручиваемая область для сообщения — прокрутка экрана. Проверка тождества операции не повторяет прокрутку при правке текста во время показанного отказа. Будущие фазы 4–6 не считались обязательствами диапазона. Безопасности, данных и миграций диапазон не касается.

Не выполнено: сборка APK и ручные проверки на устройстве. Остаются за пользователем: клавиша ввода в названии на экранной клавиатуре, вставка многострочного текста в название, прокрутка к отказу при настоящей клавиатуре.
