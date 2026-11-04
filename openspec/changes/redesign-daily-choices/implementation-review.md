# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 3.18–3.22 выполнены и подтверждены тестами, а `mise run check` и `mise run codegen-check` на проверенной голове проходят. Активна одна находка: собственное удаление связи переводит общее для всех панелей этой связи состояние в «собственное удаление», поэтому вторая панель той же связи под страницей намерения после удаления из первой показывает удалённую связь как существующую (F2). Остаточный риск AR1 перенесён без изменений.

## Review target

- **Baseline ref:** 37835b580716c7b4005b21bf827cf12e041d2bf3
- **Base commit:** 37835b580716c7b4005b21bf827cf12e041d2bf3
- **Reviewed head:** 2139ac35881f5bf035902c30eeaba6a16ab4a13f
- **Target commits:** ["224d045158982819e60a1e5cb5f09ff2ed706814","036a28db12db90086f2731a095e4d6caeebb4a94","f886085ca12284e75bd9ef7055d5bd2d54f0fe80","df2da66446cf04279189e92ab2130f1c60441e1c","fbd7137974c7266c32472b18fc4839b506bae778","2139ac35881f5bf035902c30eeaba6a16ab4a13f"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/details/daily_choice_details_state.dart","lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","lib/src/daily_choice/presentation/details/daily_choice_sheet.dart","lib/src/design_system/components/relation_head.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.g.dart","openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md","test/daily_choice/presentation/details/daily_choice_sheet_test.dart","test/design_system/relation_head_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Собственное удаление закрывает панель выбора с прежним содержимым, а меню не проверяет недостижимую запись

- **Work items:** ["3.18","3.22"]
- **Requirements and scenarios:** ["daily-choice-management: Параметры дневного выбора","Scenario: Удаление закрывает панель","design.md D4: закрытие после собственного удаления и перекрытая панель"]
- **Affected boundary:** Пользователь панели дневного выбора и потребители её состояния.
- **Implementation target:** ["lib/src/daily_choice/presentation/details/daily_choice_details_state.dart","lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","lib/src/daily_choice/presentation/details/daily_choice_sheet.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart","test/graph/presentation/package_consumers_test_support.dart"]
- **Applicable constraints and non-goals:** Закрывающаяся панель не показывает и не объявляет «не найден» при любом порядке снимка и исхода команды; чужое удаление, перекрытая панель и отказ показывают «не найден» без самостоятельного закрытия; сообщение об успехе один раз; состояния выражены закрытыми типами; спецификации не меняются.

### U2 · Панель связи не показывает ложное «не найден» при собственном удалении

- **Work items:** ["3.19"]
- **Requirements and scenarios:** ["design.md D4: закрытие после собственного удаления (по задаче 3.19 то же поведение для панели связи)"]
- **Affected boundary:** Пользователь панели связи и все потребители общего состояния просмотра связи.
- **Implementation target:** ["lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.g.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart","test/graph/presentation/package_consumers_test_support.dart"]
- **Applicable constraints and non-goals:** Поведение повторяет U1; удаление, начатое не этой панелью, показывает «не найден»; спецификации не меняются.

### U3 · Переключатель вида связи виден и нажимается при крупном шрифте

- **Work items:** ["3.20"]
- **Requirements and scenarios:** ["tasks.md 3.20: масштаб до 2 на ширине 360 с полями 20 и меню"]
- **Affected boundary:** Пользователь панели связи; потребители компонента `RelationHead`.
- **Implementation target:** ["lib/src/design_system/components/relation_head.dart","test/design_system/relation_head_test.dart"]
- **Applicable constraints and non-goals:** Компонент остаётся представлением без предметных типов по ADR-0030; слова и шрифт не сокращаются; семантика и выбор не меняются.

### U4 · Неиспользуемая строка удаления дневного выбора удалена

- **Work items:** ["3.21"]
- **Requirements and scenarios:** ["proposal.md: строки удалённых потоков уходят"]
- **Affected boundary:** Ресурсы локализации и созданный API локализации.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb"]
- **Applicable constraints and non-goals:** Созданные файлы получены кодогенерацией; видимый текст не меняется; поиск других неиспользуемых строк не входит.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные проверяющие с брифом без планирования: U1+U2 вместе с U3 одной группой по объединённой границе из 12 путей (первый проверяющий U1+U2 без `relation_head.dart` отметил неполное покрытие, поэтому группа проверена заново по полной границе), U3 отдельно, U4 отдельно. Первый проверяющий U4 случайно увидел файлы планирования при поиске по всему репозиторию, его результат не использован, и U4 проверен заново с поиском только по `lib` и `test`. Ревизия `37835b580716c7b4005b21bf827cf12e041d2bf3..2139ac35881f5bf035902c30eeaba6a16ab4a13f`. |
| OpenSpec conformance | Complete | Прочитаны design D4, требование «Параметры дневного выбора», задачи 3.18–3.22 и профили на проверенной голове. `mise exec --no-deps -- openspec validate redesign-daily-choices --json` — valid. `mise run codegen-check` — exit 0, `git grep dailyChoiceDeleteAction 2139ac35… -- lib test` пуст, `_showOptions` вызывается только из `daily_choice_sheet.dart:240`. `mise run check` — exit 0: формат и `flutter analyze` без замечаний, 4161 обычный тест и 18 процессных тестов проходят. Рабочая копия = проверенная голова, дерево чистое; запуск в `/home/seniorkonung/.paseo/worktrees/1id27gtb/purple-scorpion`. |
| Code quality | Complete | Пять осей `code-review-and-quality` по всем 17 путям доставки и тестов, с контекстом `graph_command_coordinator.dart`, `intention_details_page.dart`, `sheet.dart` и `ModalRoute` из Flutter. |

## Findings

### F2 · Medium — Общее состояние просмотра связи объявляет собственное удаление всем панелям этой связи

- **Evidence:** `RelationDetailsViewModel` — семейство `@riverpod` с ключом только `relationId` (`lib/src/long_term_relation/presentation/details/relation_details_view_model.dart:55`), и каждая панель этой связи следит за одним экземпляром (`relation_details_sheet.dart:265`). После подтверждения собственного удаления общее состояние становится `RelationDetailsOwnDeletionConfirmed` (`relation_details_view_model.dart:381`, `:724`), а пакет потока завершений с токеном этой команды больше не даёт `RelationDetailsDeleted` (`:550`). Флажок `_deletedWhileCovered` ставит только панель, начавшая удаление (`relation_details_sheet.dart:240`), поэтому любая другая панель той же связи попадает в ветви `RelationDetailsOwnDeletionConfirmed(:final shown) when !_deletedWhileCovered` (`:310`, `:340`) и показывает прежнюю связь. Две панели одной связи достижимы: панель связи открывает страницу участника (`relation_details_sheet.dart:699-701`), а вкладка «Связи» страницы намерения открывает панель той же связи (`lib/src/intention/presentation/details/intention_details_page.dart:805`). Панель дневного выбора этого дефекта не имеет: каждая создаёт свою модель (`daily_choice_sheet.dart:102`). Тесты U2 открывают одну панель и этот путь не проверяют.
- **Evidence revisions:** ["2139ac35881f5bf035902c30eeaba6a16ab4a13f"]
- **Impact:** Пользователь открывает связь X (панель A), переходит к участнику, на вкладке «Связи» снова открывает X (панель B) и удаляет её из B. B закрывается правильно, а A при возврате бессрочно показывает удалённую связь как существующую: название, шапку, описание и доступную кнопку параметров. До диапазона A показывала «Эта связь больше не существует.». Это нарушает требование задачи 3.19 «Чужое удаление показывает „не найден“» и прежнее правило модели «Общее состояние данных по ID не передаёт право закрытия другим страницам» (`relation_details_view_model.dart:187`).
- **Required outcome:** Прежнее содержимое при закрытии сохраняет только экземпляр панели, начавший удаление; любая другая панель той же связи после подтверждённого удаления показывает «не найден» при любом порядке прихода событий, и это подтверждено тестом с двумя панелями одной связи.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart","tasks.md 3.19"]

## Accepted risks

### AR1 · Граница показа слова обновления не закреплена тестом каталога

- **Evidence:** `lib/src/design_system/components/list_state.dart:86` и `:97-99` оставляют слово до масштаба 1,5 включительно. `test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart:52-81` проверяет день недели только при масштабе 2, где слова уже нет, а `test/design_system/list_state_test.dart:138` и `:146` проверяют голый `ListState` вне `DayHeading`. Ширину слота ограничивает половина заголовка: `lib/src/design_system/components/day_heading.dart:100`. Замер с настоящим Inter в окне 360 на этой ревизии: при 1,5 заголовок шириной 320 вмещает слот 150,0, промежуток 8 и «Понедельник» 149,1, поэтому сейчас свободно 12,9 dp. Слот не шире половины заголовка, значит дню недели остаётся не меньше 152 dp, и реальный запас против изменений шрифта и отступов около 3 dp. Этот расчёт опирается на замеры отчёта и заново не снимался. При слове на масштабе 1,6 «Понедельник» и «Воскресенье» уже разрываются.
- **Evidence revisions:** ["402b9271783e3b2701fc4958aa121bc8e3ab4c79"]
- **Potential impact:** Сейчас день недели цел при всех замеренных масштабах от 1 до 2. Другой шрифт, другая типографика или другие отступы могут вернуть разрыв дня недели внутри слова при масштабе до 1,5, и все тесты останутся зелёными. Длинное слово обновления само по себе день недели не порвёт, потому что слот ограничен половиной заголовка. Вред только внешний: данные и поведение не затрагиваются.
- **Acceptance rationale:** Пользователь явно принял остаточный риск. Вред ограничен видом заголовка дня, запас зависит от редко меняемых шрифта и отступов, а цена устранения — новая задача 1.21 и ещё один цикл реализации и проверки Фазы 1. Условие не устранено и не опровергнуто.
- **Scope and assumptions:** Заголовок дня в корневом каталоге и каталоге на дату, окно шириной 360, масштаб текста до 1,5 включительно, русская и английская локали. Допущения: шрифт Inter, текущая типографика `body` и `caption`, текущая геометрия `DayHeading` и текущие отступы заголовка в каталоге. Подъём порога `_wordMaxScale` в промежуток между 1,5 и 1,75 тестами не ловится и тоже входит в принятый риск как осознанная правка константы. Тесты, код, спецификация, design, plan.md и tasks.md не меняются, корректирующая задача не создаётся.
- **Reopen when:** Смена шрифта, изменение типографики `body` или `caption`, изменение геометрии `DayHeading`, отступов заголовка дня в каталоге или порога `_wordMaxScale`, а также жалоба на разрыв дня недели внутри слова.
- **Acceptance authority:** Явное решение пользователя: запись о находке F1 в `openspec/changes/redesign-daily-choices/implementation-review-decisions.md` на коммите `8caa1f456d7b3dd20df12f86431c5fc0246cc3f1`. Коммит этой резолюции удаляет запись из текущей версии файла.
- **Originating finding:** F1
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

**Цель.** `discover-review-target.mjs` вернул `ready` для изменения `redesign-daily-choices`; рабочее дерево чистое, исключённых путей нет. Все 6 целевых коммитов и 19 путей распределены: `224d0451` — профили задач 3.18–3.22 (`task-profiles.md`), отметки в `tasks.md` — свидетельства планирования; 3.18 — `036a28db` (U1), 3.19 — `f886085c` (U2), 3.20 — `df2da664` (U3), 3.21 — `fbd71379` (U4), 3.22 — `2139ac35` (U1). `package_consumers_test_support.dart` меняют 3.18 и 3.19, поэтому U1 и U2 проверялись одной группой. Неотнесённых путей нет.

**Сценарии и критерии.** 3.18: оба порядка снимка и подтверждения с покадровым закрытием без `pumpAndSettle` и однократным сообщением — `test/daily_choice/presentation/details/daily_choice_sheet_test.dart:113`; перекрытая панель — там же, `:141`; отказ при исчезнувшем выборе — `:174`; выключенные флажок и параметры во время записи и закрытия — `_expectHeadLocked`. Чужое удаление по-прежнему ведёт в `DailyChoiceDetailsNotFound`, потому что у каждой панели своя модель. 3.19: дефект подтверждён кодом прежней головы (общий `RelationDetailsDeleted` показывал «не найден»), тесты обоих порядков, перекрытой панели и отказа — `test/long_term_relation/presentation/details/relation_details_sheet_test.dart:1192`, `:1239`, `:1279`. Порядков два, а не шесть, обоснованно: поток завершений синхронный (`graph_command_coordinator.dart:889`) и выдаёт пакет до завершения команды (`:1292-1293`), а обратный порядок отсекает `_isTerminated`. Требование о чужом удалении нарушено для второй панели той же связи — F2. 3.20: `Wrap` и тесты с настоящим Inter при масштабе 2 на ширине 360 — `test/design_system/relation_head_test.dart`. 3.21 и 3.22 подтверждены поиском и `codegen-check`. Тесты не содержат замеров времени.

**Разбор замечаний, не ставших находками.** «Панель выбора при отказе чтения во время собственного удаления закрывается с отказом „недоступно“ и живым повтором»: при отказе чтения панель уже показывала этот отказ, и закрытие сохраняет показанное, а не подменяет его «не найден»; повтор во время закрытия недоступен, потому что `ModalRoute` игнорирует указатель на обратной анимации, а в перекрытой панели повтор приводит к верному «не найден». Цена отдельного хранения содержимого превышает вред. «Кнопка параметров панели связи не выключена во время записи»: поведение до диапазона, задачей 3.19 не затронуто; при закрытии нажатие невозможно по той же причине.

**Перенесённое состояние.** Предыдущий отчёт не содержал активных находок. AR1 сохранён: `list_state.dart`, `day_heading.dart`, типографика и отступы заголовка дня в диапазоне не менялись, условий повторного открытия нет. F1 занят исходной находкой AR1, поэтому новая находка — F2. Задачи для F2 не добавлены: находка передаётся стадиям разрешения находок.

**Устройство.** Устройство и эмулятор не использовались. Ручные проверки остаются за владельцем продукта: закрытие панелей выбора и связи после удаления, возврат к перекрытой панели и переключатель вида связи при крупном системном шрифте.
