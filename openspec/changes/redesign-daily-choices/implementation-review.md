# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 3.23 выполнена: прежнее содержимое после подтверждённого удаления связи показывает только панель-инициатор, а другие панели той же связи показывают «Эта связь больше не существует.». Новый тест проверяет оба порядка событий. `mise run check` и `mise run codegen-check` на проверенной голове проходят. Неустранённых находок нет. Остаточный риск AR1 перенесён без изменений.

## Review target

- **Baseline ref:** d7a9bdc212195027f60fcc6ec34a9da87d3cbc31
- **Base commit:** d7a9bdc212195027f60fcc6ec34a9da87d3cbc31
- **Reviewed head:** bedbcd6047cd0f88c51a6fa934cffa78a4cfb162
- **Target commits:** ["294e5cda50c29bbec7280433b8aa8c5ff7242a9a","8eb76dce78fd4d8936381370bc07477bb755e351","bedbcd6047cd0f88c51a6fa934cffa78a4cfb162"]
- **Reviewable paths:** ["lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.g.dart","openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md","test/long_term_relation/presentation/details/relation_details_sheet_test.dart","test/long_term_relation/presentation/details/relation_details_view_model_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md","openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Прежнее содержимое после собственного удаления связи показывает только панель-инициатор

- **Work items:** ["3.23"]
- **Requirements and scenarios:** ["design.md D4: закрытие после собственного удаления и перекрытая панель (для панели связи по задачам 3.19 и 3.23)","tasks.md 3.23: другая открытая панель той же связи показывает «Эта связь больше не существует.»"]
- **Affected boundary:** Пользователь панели связи и все панели одной связи, у которых общая модель `RelationDetailsViewModel`.
- **Implementation target:** ["lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.g.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart","test/long_term_relation/presentation/details/relation_details_view_model_test.dart"]
- **Applicable constraints and non-goals:** Модель остаётся общей для всех панелей связи, с ключом `relationId`. Гарантии задачи 3.19 для инициатора сохраняются: закрытие без кадра «не найден», перекрытая панель сама не закрывается, при отказе панель остаётся открытой, сообщение об успехе показывается один раз. Состояния выражены закрытыми типами без флага рядом с ними. Спецификации и `design.md` не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный проверяющий получил бриф без планирования и границу из всех 6 путей U1. Ревизия `d7a9bdc212195027f60fcc6ec34a9da87d3cbc31..bedbcd6047cd0f88c51a6fa934cffa78a4cfb162`. Существенных замечаний нет, покрытие полное. Проверяющий не читал `openspec/`, историю коммитов и прежний отчёт. |
| OpenSpec conformance | Complete | На проверенной голове прочитаны design D4, plan.md Phase 3, задача 3.23 и её профиль. `mise exec --no-deps -- openspec validate redesign-daily-choices --json` — valid; одно сообщение уровня INFO касается дельты `app-navigation` вне диапазона. `mise run check` — exit 0: формат 879 файлов без изменений, `flutter analyze` — «No issues found!», 4163 обычных и 18 процессных тестов проходят. `mise run codegen-check` — exit 0, дерево после него чистое. Запуск в `/home/seniorkonung/.paseo/worktrees/1id27gtb/purple-scorpion`: `HEAD` совпадает с проверенной головой, дерево чистое. |
| Code quality | Complete | Пять осей `code-review-and-quality` по всем 6 путям доставки и тестов. Контекст: вызовы `retryLifecycleChange`, `releaseDeletedContent`, `RelationDeletionInitiator` и `RelationDetailsOwnDeletionConfirmed` в `lib` и `test`, а также `package_consumers_test_support.dart:272`. |

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

**Цель.** `discover-review-target.mjs` вернул `ready` для изменения `redesign-daily-choices`. Рабочее дерево чистое, исключённых путей нет. Все 3 целевых коммита и 8 путей распределены. `294e5cda` добавляет профиль задачи 3.23 в `task-profiles.md`; это свидетельство планирования. `8eb76dce` содержит реализацию, тесты и отметку задачи 3.23 в `tasks.md` и относится к U1. `bedbcd60` пересоздаёт хеш провайдера в `relation_details_view_model.g.dart` и тоже относится к U1. Неотнесённых путей нет.

**Критерии 3.23.** Модель осталась общей. Панель передаёт в `delete` свой `RelationDeletionInitiator`, и он хранится в `RelationDetailsOwnDeletionConfirmed` (`relation_details_state.dart:166-183`). Через `_Deletion` и `_DeletionRelationMissing` он проходит при любом порядке снимка и исхода (`relation_details_view_model.dart:391-401`, `:494-497`).

Прежнее содержимое показывается только при `identical(initiator, _deletionInitiator)` (`relation_details_sheet.dart:310-312`, `:340-342`). Остальные панели попадают в ветку «не найден» без шапки и меню (`:343-347`).

Флажок `_deletedWhileCovered` заменён вызовом `releaseDeletedContent`. Он переводит общее состояние в `RelationDetailsDeleted` только для своего инициатора (`relation_details_view_model.dart:209-214`).

Ветка `delete` в `retryLifecycleChange` — пустой вариант исчерпывающего `switch`. Единственный вызывающий, `_retryLifecycleChange` панели, направляет повтор удаления через `_delete` (`relation_details_sheet.dart:246-258`), поэтому повтор не теряется.

Новый тест `relation_details_sheet_test.dart:1281` открывает вторую панель той же связи поверх страницы участника и проверяет оба порядка событий. Верхняя панель закрывается с прежним содержимым. Нижняя после возврата показывает «не найден» без `RelationHead` и без кнопки «Параметры связи». Сообщение «Связь удалена.» показано один раз. На базе нижняя панель показала бы прежнее содержимое, потому что флажок ставила только инициатор. Это установлено разбором кода, тест на базе не запускался.

Тесты задачи 3.19 остаются в наборе и проходят в составе `mise run check`. Два порядка вместо шести обоснованы так же, как для 3.19: поток завершений синхронный, а после завершения поздние события отсекает `_isTerminated`. `package_consumers_test_support.dart` не менялся: набор вариантов состояния прежний, изменилось только поле варианта. Тесты не содержат замеров времени.

**Фаза 3.** Все задачи Phase 3 в `tasks.md` отмечены выполненными. Полная проверка фазы `mise run check` пройдена на проверенной голове. Эта стадия не добавляла новых задач и исправлений.

**Перенесённое состояние.** Предыдущий отчёт не содержал активных находок. AR1 сохранён: `list_state.dart`, `day_heading.dart`, типографика и отступы заголовка дня в диапазоне не менялись, и условий повторного открытия нет.

**Устройство.** Устройство и эмулятор не использовались. Ручная проверка остаётся за владельцем продукта: удаление связи из второй панели той же связи и возврат к первой.
