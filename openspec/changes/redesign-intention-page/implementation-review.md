# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Проверены все 5 коммитов задач 4.24–4.28 фазы 4. Обрезка плоскостей `TextField.saved` и `OptionTiles`, возврат выбора листа параметров после анимации закрытия, видимая занятость при отклонённом входе в правку, удаление тона у недоступного пункта меню и удаление избыточной проверки страницы соответствуют критериям задач. Полная проверка `mise run check` на проверенной голове прошла. Одно замечание низкой важности (F1): отложенная выдача выбора открывает окно в 180 мс. В это окно страница под закрывающимся листом принимает нажатия, а пришедший позже выбор начинает действие при втором открытом листе, поверх уже открытого экрана изменения или на уходящей странице. Сохранены принятые риски AR1, AR2 и AR3.

## Review target

- **Baseline ref:** 36db1541bd27d2e7c3543d181c3c71269f7de2b0
- **Base commit:** 36db1541bd27d2e7c3543d181c3c71269f7de2b0
- **Reviewed head:** 52b23a9b2ff14eba17103dcc00244de7c8ea858a
- **Target commits:** ["3914e28a138fabe5d869009a5c1aa93d7cf8f812","538504c27076e3276df273cf8a6502b4f3c9a1ee","59a8522df8d47c91a7674bad882abe030c4ebc79","6f285b2b3ae91b5a95c21cfc63eea9e90b4f6d4b","52b23a9b2ff14eba17103dcc00244de7c8ea858a"]
- **Reviewable paths:** ["lib/src/design_system/components/option_tiles.dart","lib/src/design_system/components/options_menu.dart","lib/src/design_system/components/sheet.dart","lib/src/design_system/components/text_field.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/intention/presentation/details/intention_options.dart","openspec/changes/redesign-intention-page/tasks.md","test/app/intention_app_lifecycle_test.dart","test/app/navigation/app_shell_operation_reset_test.dart","test/design_system/option_tiles_test.dart","test/design_system/options_menu_test.dart","test/design_system/text_field_test.dart","test/intention/presentation/details/intention_details_head_test.dart","test/intention/presentation/details/intention_details_options_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/intention/presentation/details/intention_options_test.dart","test/support/intention_options.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Плоскости сохранённого текста и плиток обрезаются областью прокрутки

- **Work items:** ["4.24"]
- **Requirements and scenarios:** ["intention-management: Обзор намерения", "design: решение 11", "README компонентов TextField и OptionTiles"]
- **Affected boundary:** Потребители `TextField.saved` и `OptionTiles` — «Обзор» страницы намерения и листы с прокруткой — и пользователь, видящий прозрачную `TopBar` и полосу состояния
- **Implementation target:** ["lib/src/design_system/components/option_tiles.dart", "lib/src/design_system/components/text_field.dart", "test/design_system/option_tiles_test.dart", "test/design_system/text_field_test.dart"]
- **Applicable constraints and non-goals:** Компоненты остаются представлением без предметных типов (ADR-0030), значения берутся из токенов (ADR-0029). Вид, размеры, семантика, отклик нажатия и кольцо фокуса не меняются.

### U2 · Выбор в листе параметров и недоступный пункт меню

- **Work items:** ["4.25", "4.27"]
- **Requirements and scenarios:** ["intention-management: Параметры намерения на его странице", "intention-management: Параметры намерения на его странице / Архивирование из параметров", "design: меню параметров закрывается до начала операции (ADR-0032, ADR-0042)", "README компонентов OptionsMenu и OptionRow"]
- **Affected boundary:** Показ `OptionsMenu` через `showDoableSheet` и его вызывающий `_openOptions` страницы намерения; остальные потребители `showDoableSheet` как граница совместимости
- **Implementation target:** ["lib/src/design_system/components/options_menu.dart", "lib/src/design_system/components/sheet.dart", "lib/src/intention/presentation/details/intention_options.dart", "test/design_system/options_menu_test.dart", "test/intention/presentation/details/intention_options_test.dart", "test/intention/presentation/details/intention_details_options_test.dart", "test/support/intention_options.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart"]
- **Applicable constraints and non-goals:** Момент выдачи результата у остальных потребителей `showDoableSheet` не меняется, новых общих параметров `showDoableSheet` нет. Закрытие без выбора возвращает отсутствие выбора. Вид и поведение меню и строк не меняются.

### U3 · Видимая занятость при отклонённом входе в правку

- **Work items:** ["4.26"]
- **Requirements and scenarios:** ["intention-management: Экран изменения намерения", "intention-management: Экран изменения намерения / Возвращение во время сохранения не позволяет снова открыть правку"]
- **Affected boundary:** Пользователь страницы намерения; модель подробных данных и общий координатор команд графа
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart", "test/intention/presentation/details/intention_details_head_test.dart"]
- **Applicable constraints and non-goals:** Новых механизмов занятости, подписок на координатор и параметров нет; возврат доступности идёт через существующий путь завершения модели.

### U4 · Удаление избыточной проверки страницы

- **Work items:** ["4.28"]
- **Requirements and scenarios:** ["intention-management: Страница намерения и её вкладки / Шапка архивированного намерения", "intention-management: Обзор намерения / Обзор только что созданного намерения"]
- **Affected boundary:** Набор проверок проекта
- **Implementation target:** ["test/intention/presentation/details/intention_details_page_test.dart"]
- **Applicable constraints and non-goals:** Код приложения и остальные проверки не меняются; каждое ожидание удаляемой проверки остаётся покрытым.
- **Excluded change scope:** Вкладки «Выборы» и «Связи» фаз 5 и 6 не считались обязательствами диапазона.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Четыре свежих изолированных рецензента по `implementation-decision-review` с нейтральными брифами, без артефактов планирования, ADR, истории коммитов и прежнего отчёта. U1 — 4 пути; рецензент прогнал обе проверки компонентов на голове (34 прошли) и во временной копии вне репозитория с компонентами базы: обе новые проверки падают на цвете пикселя `fill`. U2 — 9 путей; по уточнению координатора цель дополнена `intention_details_page.dart` — вызывающим `_openOptions`, общим с U3. После этого покрытие полное, сохранено замечание F1. U3 — 2 пути, покрытие полное. U4 — 1 путь; по уточнению координатора цель дополнена `intention_details_head_test.dart`, на который опирается покрытие метки «Archived». После этого покрытие полное. |
| OpenSpec conformance | Complete | Задачи 4.24–4.28 сверены с критериями приёмки и требованиями «Обзор намерения», «Параметры намерения на его странице», «Экран изменения намерения», «Страница намерения и её вкладки» и с ADR-0042 в обе стороны. Регрессионные проверки 4.24 и 4.25 различают прежнее и новое поведение, проверка шапки 4.26 переписана по критерию. Три ожидания удалённой проверки 4.28 подтверждены проверками шапки и «Обзора». `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json` дал valid. Полный `mise run check` в рабочей копии, совпадавшей с 52b23a9b2ff14eba17103dcc00244de7c8ea858a и чистой, прошёл: format (833 файла, 0 изменено), проверки скриптов, `flutter analyze` без замечаний, 3665 обычных и 18 процессных тестов. Сборка APK и проверки на устройстве не выполнялись: по правилам проекта они за пользователем. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены в контексте координатора ко всем путям доставки на голове. Поведение `TransitionRoute.completed`, `IgnorePointer` барьера закрывающегося маршрута и `Ink._paddingIncludingDecoration` сверено с исходниками Flutter 3.47.1. Отдельно проверено, что `DoableMetrics.space2` = 8 не меньше выступа кольца фокуса 4. |

## Findings

### F1 · Low — Отложенный выбор листа параметров начинает действие после нажатий на странице, сделанных за время закрытия

- **Evidence:** `SheetPresentation.closeWithChoice` закрывает лист сразу (`lib/src/design_system/components/sheet.dart:28-31`). Показ отдаёт выбор только после `route.completed` (`sheet.dart:90-93`), то есть через `_sheetDuration` = 180 мс (`sheet.dart:97`). Пока маршрут листа идёт обратной анимацией, Flutter 3.47.1 пропускает нажатия сквозь его затемнение: в `ModalRoute._buildModalBarrier` (`packages/flutter/lib/src/widgets/routes.dart:2279-2280`) стоит `IgnorePointer(ignoring: !animation.isForwardOrCompleted)`. Страница под листом в это время принимает нажатия: «⋯», название, описание, плитки готовности, системное «назад». Пришедший позже выбор `_openOptions` проверяет только `option == null || !mounted` (`lib/src/intention/presentation/details/intention_details_page.dart:312`). `_openEdit` (`intention_details_page.dart:200-219`) и `_confirmDeletion` не проверяют, что страница остаётся текущим маршрутом и что с неё ничего не открыто. До 4.25 действие начиналось в момент закрытия, и следующие последовательности были недостижимы:
  Последовательности: (1) выбрать пункт и в окне нажать «⋯» — откроется второй лист, и над ним начнётся архивирование или восстановление с перерисовкой его пунктов либо откроется диалог удаления; (2) выбрать «Изменить» и в окне нажать название или описание — первый `_openEdit` откроет экран изменения, а пришедший выбор, пройдя все проверки модели, откроет второй экран изменения поверх первого; (3) выбрать «Архивировать» или «Удалить» и в окне нажать название — архивирование начнётся за экраном изменения либо диалог удаления откроется поверх него; (4) выбрать «Изменить» или «Удалить» и в окне нажать «назад» — страница уходит, но остаётся `mounted`, и экран изменения или диалог открываются над уходящей страницей.
  Изменения данных при этом не теряются: архивирование и восстановление перепроверяются моделью (`intention_details_view_model.dart:225-250`), повтор отклоняет координатор, удаление атомарно проверяет хранилище, а закрытие страницы после удаления защищено `isCurrent` (`intention_details_page.dart:295-300`).
- **Evidence revisions:** ["52b23a9b2ff14eba17103dcc00244de7c8ea858a"]
- **Impact:** Быстрое второе нажатие в течение 180 мс после выбора даёт наложенные экраны и листы: второй экран изменения, диалог поверх постороннего экрана, действие, начатое при открытом листе. Последнее — именно то состояние, которое по ADR-0042 и критерию задачи 4.25 должно быть исключено. Пользователь может выйти из любого такого состояния, данные не портятся. Поэтому важность низкая.
- **Required outcome:** Действие, выбранное в листе параметров, начинается только на странице, которая остаётся текущим, не уходящим маршрутом, и только если с момента выбора с неё не открыт другой лист, диалог или экран изменения. Иначе выбор отбрасывается. Допустимо и другое решение: страница под закрывающимся листом не принимает нажатия, пока выбор не выдан. Проверка воспроизводит хотя бы одну из последовательностей выше.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/design_system/components/sheet.dart", "test/intention/presentation/details/intention_details_options_test.dart", "tasks.md: 4.25"]

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

Обрезка плоскостей. Оба компонента рисуют плоскость, рамку и кольцо фокуса в собственном `DecoratedBox`, а отклик нажатия — на прозрачном `Material` внутри него. Поэтому всё нарисованное идёт в порядке потомков и обрезается областью прокрутки. Отступ содержимого плитки `decoration.padding + space3` повторяет прежний сдвиг на толщину рамки, который давал `Ink`. Прежние проверки компонентов перенаправлены с `Ink` на `DecoratedBox` без изменения ожиданий. Новые проверки задают геометрию: верх компонента на 14, пиксель панели на 30. На базе они падают, на голове проходят. Отдельный помощник `_pixel` в двух файлах проверок следует сложившемуся в проекте способу: свои помощники чтения пикселей есть и в `calendar_handle_test.dart`, `order_button_test.dart` и `sheet_test.dart`. Замечанием он не выделен.

Выбор в листе. Флаг `_resultAfterClosing` ставит только `SheetPresentation.closeWithChoice`, и вызывает его только `OptionsMenu`. Остальные потребители `showDoableSheet` получают результат в момент закрытия: обёртка `then` добавляет лишь микрозадачу. `TransitionRoute.completed` завершается и при `dispose`, поэтому показ не зависает, если маршрут сняли иначе. Закрытие затемнением и «назад» по-прежнему даёт отсутствие выбора. Проверка меню различает моменты: на 90 мс из 180 лист на экране и результата нет, после окончания анимации результат есть. Проверочные помощники приложения получили лишний кадр, потому что выбор приходит после снятия маршрута. Окно 180 мс, в которое страница принимает нажатия, вынесено в F1.

Недоступный пункт. `OptionsMenuItem.unavailable` больше не принимает тон и всегда даёт обычный. Сборщик параметров не передаёт тон выключенному «Удалить», доступное «Удалить» сохраняет опасный тон. Проверка меню подтверждает передачу опасного тона строке на доступном пункте.

Занятость при отклонённой правке. Все три входа — название, описание и «Изменить» в параметрах — идут через `_openEdit`. Отказ из-за занятости у координатора вызывает существующий `refreshOperationRunning`. Возврат доступности после завершения идёт через `_handleCompletion` и `_scheduleGateRefresh` модели, в том числе после отказа команды. Проверка шапки подтверждает `onEdit == null` после нажатия и снова доступный `onEdit` после завершения команды.

Удалённая проверка. Метку «Archived» покрывает параметризованная проверка шапки архивированного намерения на `en`. Приглашение «Add a description» покрывает проверка «Обзора» без описания на `ru` и `en`. Выбранную плитку «Намерение» у неготового намерения покрывает проверка «Обзора» только что созданного намерения. Используемые помощники и импорты остались.

Принятые риски. Диапазон не трогает `TopBar` с кнопкой справа, область нажатия названия `PageHead` и delta-спецификации: условия AR1, AR2 и AR3 сохраняются.

Правила проекта. Комментарии и названия проверок написаны на русском. `pump(Duration)` в проверках только продвигает кадры и не измеряет время. Безопасности, данных, схемы хранилища и миграций диапазон не касается.

Не выполнено: сборка APK и ручные проверки на устройстве. За пользователем остаются: отсутствие цветов «Обзора» в панели при прокрутке на устройстве в обеих темах, в том числе в листах; отклик нажатия и кольцо фокуса плиток и сохранённого текста; исчезновение листа параметров до начала действия; занятость страницы при отклонённом входе в правку.
