# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверен коммит задачи 5.11, завершающей фазу 5. Из `AddRow` удалены публичные nullable-геттеры, а проверка `TagsSection` теперь подтверждает передачу заголовка, подписей, ключа и выключенности «Добавить» через видимый текст и семантику. Поведение и потребители не изменились, полный `mise run check` на голове прошёл. Активных находок нет. Сохранены принятые риски AR1, AR2 и AR3.

## Review target

- **Baseline ref:** 2c71e2517b46bbf637f61eb0cb5c8e49e1a1a33d
- **Base commit:** 2c71e2517b46bbf637f61eb0cb5c8e49e1a1a33d
- **Reviewed head:** 5aed6ebef60957adce2f8281d8ba461859e32282
- **Target commits:** ["5aed6ebef60957adce2f8281d8ba461859e32282"]
- **Reviewable paths:** ["lib/src/design_system/components/add_row.dart","openspec/changes/redesign-intention-page/tasks.md","test/design_system/tags_section_test.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Публичная поверхность `AddRow` без геттеров, нужных только проверке

- **Work items:** ["5.11"]
- **Requirements and scenarios:** ["design: решение 11 — компоненты дизайн-системы", "README `AddRow` дизайн-системы"]
- **Affected boundary:** Потребители компонента `AddRow` (`TagsSection`, sliver вкладки «Выборы») и их проверки
- **Implementation target:** ["lib/src/design_system/components/add_row.dart","test/design_system/tags_section_test.dart"]
- **Applicable constraints and non-goals:** Поведение и вид приложения не меняются, производственные потребители не меняются. Закрытая модель вариантов и конструкторы `AddRow` сохраняются. Перестройка вариантов и раскладки строки не входит в задачу.
- **Excluded change scope:** Общий слой согласования списков с графом относится к фазе 6 и не считался обязательством диапазона.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент по `implementation-decision-review` с нейтральным брифом, без артефактов планирования, истории коммитов и прежнего отчёта. Он проверил оба назначенных пути на голове и сообщил полное покрытие. Его прогоны: `tags_section_test.dart` (5 тестов) и `flutter analyze lib/src/design_system test/design_system` — без замечаний. Поиск по `lib` и `test` не нашёл чтений удалённых геттеров. |
| OpenSpec conformance | Complete | Критерии приёмки 5.11 сверены с диффом в обе стороны. `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json` дал valid, все 74 задачи отмечены. `flutter test test/design_system/add_row_test.dart test/design_system/tags_section_test.dart`: 21 тест прошёл. Полный `mise run check` прошёл в рабочей копии на 5aed6ebef60957adce2f8281d8ba461859e32282 без незакоммиченных изменений: format (840 файлов, 0 изменено), проверки скриптов, `flutter analyze` без замечаний, 3689 обычных и 18 процессных тестов. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены в контексте координатора к `add_row.dart` и `tags_section_test.dart` на голове. Закрытые `_Lead` и `_Add` по-прежнему используются в `build`, мёртвого кода не осталось. Проверка `TagsSection` проверяет передачу через наблюдаемый вывод и не дублирует проверки `add_row_test.dart`. |

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

Компонент `AddRow`. Удалены только геттеры `title`, `addText`, `addLabel`, `onAdd` и `addKey`. Конструкторы `AddRow`, `AddRow.hint`, `AddRow.hintOnly`, `AddRow.addOnly`, закрытая модель `_Lead` с `_Title` и `_Hint`, `_Add` и `build` не изменились (`lib/src/design_system/components/add_row.dart:25-132`). Поэтому вид строки и поведение «Добавить» прежние. `tags_section.dart` и `intention_choices_sliver.dart` диапазон не трогает, и удалённые геттеры они не читали.

Проверка `TagsSection`. Тест «блок передаёт строке заголовок, подписи, ключ и выключенность «Добавить»» (`test/design_system/tags_section_test.dart:13-31`) находит «Теги» и «Добавить» внутри `AddRow`. По ключу он берёт семантику кнопки и проверяет подпись «Добавить теги», роль кнопки, наличие состояния доступности и выключенность. Без передачи ключа или обработчика тест падает, так что прежнее сравнение полей заменено эквивалентной проверкой наблюдаемого поведения.

Задачи. Отметка 5.11 в `tasks.md` подтверждена диффом и прогонами. Остальные задачи и их порядок не изменились.

Принятые риски. Диапазон не трогает delta-спецификации, `TopBar` и `PageHead`: условия AR1, AR2 и AR3 сохраняются.

Правила проекта. Название проверки на русском, измерений времени нет. Схемы, данных и миграций диапазон не касается.

Не выполнено: проверки на устройстве. По правилам проекта они за пользователем; для 5.11 вид и поведение приложения не меняются.
