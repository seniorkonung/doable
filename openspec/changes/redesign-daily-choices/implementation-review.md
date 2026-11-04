# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 4.17–4.21 выполнены по критериям, `mise run check` на проверенной голове проходит. Активных находок нет: F7 и F8 по решениям пользователя переданы в незавершённые задачи 4.22 и 4.23 Phase 4 `tasks.md`, код по ним ещё не менялся. Остаточный риск AR1 перенесён без изменений.

## Review target

- **Baseline ref:** 70190820a75cdef0d1cca72d3111ca0056b15e1d
- **Base commit:** 70190820a75cdef0d1cca72d3111ca0056b15e1d
- **Reviewed head:** febecc20e9578c10b666cdf0294495039d784d83
- **Target commits:** ["8319463dbebce2d58cc1c21443d2f692d0ea00cd","f6a796eeb307279b631e917940dece8045b43610","70c110e929f170bb3d4a06ed2e861f363c1ad334","09980166c122107946258b10aefe0b97713abfeb","5f97bc68bb05090fdf76079e8a4be49938c3e11d","febecc20e9578c10b666cdf0294495039d784d83"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/details/daily_choice_details_state.dart","lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","lib/src/daily_choice/presentation/details/daily_choice_field_labels.dart","lib/src/daily_choice/presentation/details/daily_choice_sheet.dart","lib/src/daily_choice/presentation/details/daily_choice_time_sheet.dart","lib/src/design_system/components/tabs.dart","lib/src/design_system/components/time_dial.dart","openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md","test/daily_choice/presentation/details/daily_choice_details_view_model_test.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart","test/daily_choice/presentation/details/daily_choice_time_sheet_test.dart","test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart","test/design_system/tabs_test.dart","test/design_system/time_dial_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · После собственной подтверждённой записи панель ждёт снимок с записанным значением

- **Work items:** ["4.17"]
- **Requirements and scenarios:** ["daily-choice-management: Изменение дневного выбора в нижней панели","daily-choice-management: Изменение описания в нижней панели / Описание добавляется под полосой","tasks.md 4.17: ожидание снимка, конец ожидания при любом исходе подписки"]
- **Affected boundary:** Человек в панели дневного выбора; `DailyChoiceDetailsViewModel`, его состояние операции и лист панели.
- **Implementation target:** ["lib/src/daily_choice/presentation/details/daily_choice_details_state.dart","lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","lib/src/daily_choice/presentation/details/daily_choice_sheet.dart","test/daily_choice/presentation/details/daily_choice_details_view_model_test.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart"]
- **Applicable constraints and non-goals:** Ревизия графа — единственный сигнал порядка между записью и снимком, а снимки разных эпох несравнимы. Успех изменения не объявляется. Отказ записи, удаление и закрытие панели до результата ведут себя как раньше.

### U2 · Циферблат следует итоговому формату часов устройства и локали

- **Work items:** ["4.18"]
- **Requirements and scenarios:** ["daily-choice-management: Поля даты, времени и приоритета дневного выбора (время в системном формате)","tasks.md 4.18: ru и en при выключенном 24-часовом времени"]
- **Affected boundary:** Человек, который выбирает время в листе времени панели и подтверждения создания.
- **Implementation target:** ["lib/src/daily_choice/presentation/details/daily_choice_field_labels.dart","lib/src/daily_choice/presentation/details/daily_choice_time_sheet.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart","test/daily_choice/presentation/details/daily_choice_time_sheet_test.dart"]
- **Applicable constraints and non-goals:** Начальная половина суток и подписи половин суток не меняются. Подписи резервных копий не меняются.

### U3 · Контракты `Tabs` и `TimeDial` без лишних параметров

- **Work items:** ["4.19","4.20"]
- **Requirements and scenarios:** ["design.md D4: компоненты дизайн-системы без предметных типов","tasks.md 4.19: Tabs.toggle без параметров полосы","tasks.md 4.20: TimeDial без allDayHint и showsFocus"]
- **Affected boundary:** Потребители модуля `lib/src/design_system/` и люди с экранным диктором.
- **Implementation target:** ["lib/src/design_system/components/tabs.dart","lib/src/design_system/components/time_dial.dart","lib/src/daily_choice/presentation/details/daily_choice_time_sheet.dart","test/design_system/tabs_test.dart","test/design_system/time_dial_test.dart"]
- **Applicable constraints and non-goals:** Вид, раскладка, семантика и поведение полос вкладок и переключателя «AM»/«PM» не меняются. Новых режимов циферблата нет.

### U4 · Тесты подтверждения создания не проверяют недостижимый отказ по дате

- **Work items:** ["4.21"]
- **Requirements and scenarios:** ["tasks.md 4.21: удалён тест отказа по полю даты"]
- **Affected boundary:** Набор тестов страницы подтверждения создания.
- **Implementation target:** ["test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart"]
- **Applicable constraints and non-goals:** Производственный код, `DailyChoiceValidationField.date`, строка `dailyChoiceDateInvalid` и тесты модели создания не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных проверяющих получили нейтральные брифы без планирования, истории коммитов и прежнего отчёта. Группа U1–U3 связана общими путями `daily_choice_sheet_test.dart` и `daily_choice_time_sheet.dart`, поэтому её проверял один проверяющий по объединению из 12 путей. Он нашёл два замечания уровня Medium. После проверки они записаны как F7 и F8. F7 передан в задачу 4.22, F8 — в задачу 4.23. U4 проверял отдельный проверяющий по одному пути: существенных замечаний нет. Оба отчитались о полном покрытии на `70190820..febecc20`. |
| OpenSpec conformance | Complete | На проверенной голове прочитаны критерии 4.17–4.21, plan.md Phase 4 и требования `daily-choice-management` об изменении в панели, описании и полях. Отметки 4.17–4.21 и профили задач подтверждены диффом. `mise exec --no-deps -- openspec validate redesign-daily-choices --json`: 1/1 passed. `mise run check` в рабочем дереве на `febecc20`, дерево чистое: формат, `flutter analyze` (No issues found), основной набор (+4217) и процессные тесты (+18) прошли, exit 0. |
| Code quality | Complete | Пять осей `code-review-and-quality` по всем путям U1–U4. Контекст на голове: `graph_command_coordinator.dart` (`DailyChoiceCommandCompletion.confirmedResult`), `drift_personal_graph_repository.dart` (ревизия подтверждения), `drift_personal_graph_repository_daily_choice_commands.dart` (`didMutate`), `drift_personal_graph_repository_daily_choice_reads.dart` (подписка выбора и её сигналы), `daily_choice_command.dart` и `daily_choice_description.dart` (пробельный ввод). |

## Findings

No unresolved findings remain in the implementation review.

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

**Цель.** `discover-review-target.mjs` вернул `ready` для изменения `redesign-daily-choices`: 6 коммитов и 15 путей, список коммитов совпадает с данными процесса. Рабочее дерево чистое, исключённых путей нет. `8319463d` меняет только `task-profiles.md` (профили 4.17–4.21). Задачи 4.17–4.21 соответствуют коммитам `f6a796ee`, `70c110e9`, `09980166`, `5f97bc68` и `febecc20`, и каждый из них отмечает свою задачу в `tasks.md`.

**Задача 4.17.** `DailyChoiceDetailsOperationAwaitingSnapshot` хранит ревизию из `completion.confirmedResult`. Пока снимок не пришёл, новые операции запрещены (`_canStartOperation`), а панель считает это состояние записью (`daily_choice_sheet.dart:287-292`). Ожидание заканчивают снимок не старше записи, снимок другой эпохи, отсутствие выбора, отказ чтения и `dispose`. Тесты модели проверяют успех только после снимка и исходы «не найден» и «отказ чтения». Тест панели фиксирует кадр между подтверждением и снимком для приоритета и описания. Пробел этого механизма — запись без изменений (бывшая F7). По решению пользователя его устраняет задача 4.22 в `tasks.md`: если показанный снимок уже содержит записанные значения, ожидания нет.

**Задача 4.18.** `dailyChoiceUsesTwelveHourClock` берёт `timeOfDayFormat(alwaysUse24HourFormat:)` и `hourFormat`. Лист времени выбирает по ней `TimeDialClock12` или `TimeDialClock24`. Тесты листа и панели подтверждают ru «18:00» на 24-часовом циферблате, en «6:00 PM» на 12-часовом и en с включённым 24-часовым временем. Расхождение между утверждением о едином месте и кодом (бывшая F8): `dailyChoiceTimeValue` выбирает формат сам, через `TimeOfDay.format`. По решению пользователя его устраняет задача 4.23 в `tasks.md`: подписи времени получают формат из `dailyChoiceUsesTwelveHourClock`, видимый вывод не меняется.

**Задачи 4.19 и 4.20.** У `Tabs.toggle` нет `stuck` и `plane`, `assert` удалён, перечисление смысла закрыто (`_TabsSemantics`). `minWidth` задаёт только переключатель, полоса держит `DoableMetrics.tapMin`. Тест циферблата проверяет переключатель по семантике (кнопка, включена, не вкладка), а не по удалённому полю. У `TimeDial` нет `allDayHint`, доступное название кнопки «Весь день» совпадает с её текстом, `_DialButton` принимает готовый `child`, кольцо фокуса рисует `foregroundPainter`.

**Задача 4.21.** Удалён один тест. Изолированный проверяющий подтвердил, что в `lib/` нет производителя `DailyChoiceValidationField.date`, а уведомление отказа страницы по-прежнему проверяют тесты отказа описания и временного отказа.

**Отклонённые наблюдения.** Отдельного теста для ветки «показанный снимок уже не старше подтверждения, ожидания нет» нет. Регрессия этой ветки оставила бы панель ждать снимок, который уже показан. У неё тот же корень, что у бывшей F7: ожидание рассчитывает на будущий снимок. Тест задачи 4.22 (показанный снимок уже содержит записанные значения, ожидания нет) покрывает и её, поэтому отдельная находка не заводится.

**Перенесённое состояние.** В прежнем отчёте активных находок не было. Новые номера начинаются с F7, потому что F1–F6 уже использованы. AR1 сохранён: `list_state.dart`, `day_heading.dart`, порог `_wordMaxScale`, шрифт, типографика и отступы заголовка дня в диапазоне не менялись.

**Исправления этой стадии.** Код, тесты и артефакты планирования не менялись. Навык проверки реализации запрещает этой стадии править код. Решения по находкам принимают отдельные стадии их разрешения. F7 по решению пользователя передана в новую незавершённую задачу 4.22 в конце Phase 4 `tasks.md`; код по ней ещё не менялся. F8 по решению пользователя передана в новую незавершённую задачу 4.23 в конце Phase 4 `tasks.md`; код по ней ещё не менялся.

**Устройство.** Устройство и эмулятор не использовались. Ручная проверка на устройстве остаётся за владельцем продукта: переход панели через ожидание снимка при изменении описания и формат циферблата в ru и en при выключенном 24-часовом времени.
