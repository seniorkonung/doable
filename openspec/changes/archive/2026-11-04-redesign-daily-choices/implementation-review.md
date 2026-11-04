# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 4.22 и 4.23 выполнены по критериям. Активных находок нет, `mise run check` на проверенной голове проходит. Phase 4 завершена: все задачи отмечены. Остаточный риск AR1 перенесён без изменений.

## Review target

- **Baseline ref:** 1baab10dfd599d6fef74ffb5138409ae17fc69ad
- **Base commit:** 1baab10dfd599d6fef74ffb5138409ae17fc69ad
- **Reviewed head:** e39c70d576895f3f6fb1a3e5c6e696f00a0d327f
- **Target commits:** ["feea6b0e284239096900c1e01a445cea3657a244","be0adb1c32ce897cdb5aec95e0e677d751e32dd0","e39c70d576895f3f6fb1a3e5c6e696f00a0d327f"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","lib/src/daily_choice/presentation/details/daily_choice_field_labels.dart","openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md","test/daily_choice/presentation/details/daily_choice_details_view_model_test.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Запись, которая ничего не изменила, не оставляет панель ждать снимок

- **Work items:** ["4.22"]
- **Requirements and scenarios:** ["daily-choice-management: Изменение дневного выбора в нижней панели","tasks.md 4.22: запись без изменения значений завершается сразу; при отличии любого значения ожидание из 4.17 сохраняется"]
- **Affected boundary:** Человек в панели дневного выбора; `DailyChoiceDetailsViewModel` и его состояние операции.
- **Implementation target:** ["lib/src/daily_choice/presentation/details/daily_choice_details_view_model.dart","test/daily_choice/presentation/details/daily_choice_details_view_model_test.dart","test/daily_choice/presentation/details/daily_choice_sheet_test.dart"]
- **Applicable constraints and non-goals:** Ревизия графа — единственный сигнал порядка между записью и снимком, снимки разных эпох несравнимы. Контракт прикладного слоя, типы результата, репозиторий и подписка не меняются. Лист панели не меняется, «Сохранить» для пробельного ввода в пустое описание остаётся доступной. Сообщения об успехе нет.

### U2 · Формат часов циферблата и подписей времени решается в одном месте

- **Work items:** ["4.23"]
- **Requirements and scenarios:** ["daily-choice-management: Поля даты, времени и приоритета дневного выбора (время в системном формате)","tasks.md 4.23: видимый вывод ru и en не меняется"]
- **Affected boundary:** Человек, который читает и выбирает время дневного выбора; форматирование времени в представлении дневных выборов.
- **Implementation target:** ["lib/src/daily_choice/presentation/details/daily_choice_field_labels.dart"]
- **Applicable constraints and non-goals:** Формат следует настройке 24-часового времени устройства и шаблону локали. «Весь день», подписи половин суток, `backup_descriptions.dart`, `TimeDial` и лист времени не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | U1 и U2 не делят путей, поэтому их проверяли два свежих изолированных проверяющих. Они получили нейтральные брифы без планирования, истории коммитов и прежнего отчёта. Проверяющий U1 работал по трём путям, U2 — по одному. Оба вернули «No substantive findings» с полным покрытием на `1baab10d..e39c70d5`. Проверяющий U2 читал потребителей из рабочего дерева и не открывал исходники Flutter. Рабочее дерево совпадало с головой и было чистым. Эквивалентность форматов проверена отдельно по исходникам Flutter SDK, см. «Review coverage». |
| OpenSpec conformance | Complete | На голове прочитаны критерии 4.22 и 4.23 `tasks.md` и требования `daily-choice-management` об изменении в панели и поле времени. Отметки 4.22 и 4.23 и профили задач в `task-profiles.md` подтверждены диффом. `mise exec --no-deps -- openspec validate redesign-daily-choices --json`: 1/1 passed. `openspec instructions apply`: 78/78 задач выполнено. `mise run check` в рабочем дереве на `e39c70d5`, дерево чистое, exit 0: формат (881 файл, 0 изменено), `flutter analyze` (No issues found), основной набор (+4219) и процессные тесты (+18). |
| Code quality | Complete | Пять осей `code-review-and-quality` по всем путям U1 и U2. Контекст на голове: доменные типы `CalendarDate`, `DailyChoiceDescription`, `DailyChoiceSchedule`, `DailyChoicePriority` (равенство по значению); `_updateDailyChoiceFields` и `_writeGraph` (ревизия записи без изменений); `_watchDailyChoice`; потребители `dailyChoiceTimeValue` в `daily_choice_time_sheet.dart`, `daily_choice_detail_fields.dart`, `daily_choice_catalog_body.dart`. |

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

**Цель.** `discover-review-target.mjs` вернул `ready` для изменения `redesign-daily-choices`: 3 коммита и 6 путей, список коммитов совпадает с данными процесса. Рабочее дерево чистое, исключённых путей нет. `feea6b0e` меняет только `task-profiles.md` (профили 4.22 и 4.23). Задача 4.22 соответствует коммиту `be0adb1c`, задача 4.23 — коммиту `e39c70d5`. Каждый из них отмечает свою задачу в `tasks.md`.

**Задача 4.22.** В `_operationAfter` ожидание снимка наступает, только если `_awaitsSnapshot(revision)` и показанный загруженный снимок не содержит записанных значений (`_showsWritten`). `_showsWritten` сравнивает по значению дату, описание, выполнение, время и приоритет. У этих типов есть равенство по значению. Остальные поля `DailyChoice` (идентификаторы) патч не меняет. Запись без изменений не продвигает ревизию графа. Но показанный снимок может быть старше ревизии подтверждения из-за записей в другие части графа, и тогда нового снимка не будет. Значит, без этой ветки ожидание действительно не заканчивалось. Сравнение с показанным снимком, а не `before` подтверждения, продолжает ждать в случае, когда хранилище уже изменилось, а снимок ещё не доставлен. Тесты модели проверяют два случая. Запись тех же значений при снимке R1 и подтверждении R2 даёт успех, `Idle` и разрешает следующую операцию. Отличие любого из пяти значений оставляет `AwaitingSnapshot`, пока не придёт снимок.

Подделка репозитория в `daily_choice_sheet_test.dart` теперь применяет патч к показанному выбору. Без этого прежние сценарии ожидания снимка (4.17) завершались бы сразу после подтверждения и перестали бы проверять кадр ожидания. Контракты прикладного слоя, репозиторий, подписка и `daily_choice_sheet.dart` не менялись.

**Задача 4.23.** `dailyChoiceTimeValue` вызывает `MaterialLocalizations.formatTimeOfDay` с `alwaysUse24HourFormat: !dailyChoiceUsesTwelveHourClock(context)`. Поэтому формат подписей и циферблата решает одна функция, и комментарии обеих функций это описывают. Видимый вывод не изменился, это проверено по исходникам Flutter SDK. `TimeOfDay.format` передаёт `MediaQuery.alwaysUse24HourFormatOf`, а `_get24HourVersionOf` в `flutter_localizations` оставляет 24-часовые шаблоны локали без изменений. Поэтому для любой локали, где решение даёт 24 часа при выключенной настройке, вывод совпадает с прежним. Тесты совпадения формата циферблата и подписей в листе времени и панели не менялись и проходят. Прямых вызовов `TimeOfDay.format` и `formatTimeOfDay` в `lib/src/daily_choice` вне этого файла нет.

**Отклонённые наблюдения.** В тестах модели `_withPriority` — однострочная обёртка над `_withFields`, и вызывает её одно место. Отдельной находкой она не стала: вреда для сопровождения нет.

**Перенесённое состояние.** В прежнем отчёте активных находок не было. AR1 сохранён: `list_state.dart`, `day_heading.dart`, порог `_wordMaxScale`, шрифт, типографика и отступы заголовка дня в диапазоне не менялись.

**Исправления этой стадии.** Код, тесты и артефакты планирования не менялись. Новых задач нет.

**Устройство.** Устройство и эмулятор не использовались. Ручная проверка на устройстве остаётся за владельцем продукта. Нужно убедиться, что повторное сохранение того же значения в панели не оставляет её в состоянии записи. Ещё нужно сверить подписи времени и циферблат в ru и en при выключенном и включённом 24-часовом времени.
