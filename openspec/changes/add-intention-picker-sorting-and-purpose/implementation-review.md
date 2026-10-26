# OpenSpec Implementation Review: add-intention-picker-sorting-and-purpose

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Все три прохода завершены для U1 и задачи 2.9 (ID 20); неустранённых замечаний нет. Замена восьми устаревших вызовов API сохраняет проверки семантики OptionGroup. Полный `mise run check`, проверка генерации и release-сборка прошли; автоматические проверки завершения фазы 2 подтверждены. Сохраняется принятый риск AR1 об индексах архивного охвата, перенесённый без повторного рассмотрения вне текущего диапазона.

## Review target

- **Baseline ref:** 3812ff32bc30fb17dfaf530bf864eee88a4bd9de
- **Base commit:** 3812ff32bc30fb17dfaf530bf864eee88a4bd9de
- **Reviewed head:** 3cc1a24d4cfc0330147d64c40d079990c4ef2066
- **Target commits:** ["3cc1a24d4cfc0330147d64c40d079990c4ef2066"]
- **Reviewable paths:** ["openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md", "test/design_system/option_group_test.dart"]
- **OpenSpec change:** add-intention-picker-sorting-and-purpose
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md"]

## Reviewed increment

### U1 · Проверки семантики группы вариантов используют поддерживаемый API Flutter

- **Work items:** ["2.9"]
- **Requirements and scenarios:** ["intention-management: Параметры показа в поиске для выбора — семантика взаимоисключающих вариантов", "daily-choice-management: Закреплённый тип поиска действия — недоступность группы с сохранением выбора и причины"]
- **Affected boundary:** Автоматические проверки OptionGroup: выбранность после нажатия, явная недоступность группы и вариантов, взаимоисключение и сохранение выбранного варианта в обеих темах; статический анализ теста.
- **Implementation target:** ["test/design_system/option_group_test.dart"]
- **Applicable constraints and non-goals:** Сохранить существующие утверждения и защиту от регрессий без подавления диагностик, изменения анализатора, версий инструментов или поведения компонента.
- **Excluded change scope:** Реализация задач 2.1–2.8 и фазы 1 служит контекстом; её повторное ревью не входит в диапазон. Назначение поисков, подзаголовки и лист «Что вы выбираете» относятся к будущим фазам 3–4. Полные проверки выполняются для завершения фазы 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент `/root/option_group_decision_review`, `gpt-6.1-sol`, low, применил `implementation-decision-review` к U1: No substantive findings, Coverage Complete. Переданы нейтральное намерение, сохранённые границы и единственный путь `test/design_system/option_group_test.dart`. Плановые артефакты, сообщения коммитов, прежний отчёт и находки не передавались; неизменённые контекстные пути проверены перед чтением. |
| OpenSpec conformance | Complete | Задача 2.9 и относящиеся к ней требования сопоставлены с U1 на сохранённой голове. Тест компонента: exit 0, 8 проверок. Анализ файла: exit 0, диагностик нет. Полный `mise run check`: exit 0, статические проверки, 3387 обычных и 18 процессных тестов прошли. OpenSpec validate в JSON и строгом режиме: exit 0, valid, issues []. `mise run codegen-check` и release-сборка: exit 0. Все команды и условия выполнения указаны ниже. |
| Code quality | Complete | Полностью проверены единственный путь поставки и его diff по корректности, читаемости, архитектуре, безопасности и производительности с помощью `code-review-and-quality`. Соответствие новых состояний старым флагам сверено с локальными исходниками закреплённого Flutter 3.47.1. Новых зависимостей, путей обработки внешних данных, механизмов или фикстур нет; все прежние утверждения сохранены. |

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

Единственный целевой коммит `3cc1a24d4cfc0330147d64c40d079990c4ef2066` рассмотрен полностью. Задача **2.9 (ID 20)** соответствует **U1**, её собственный диапазон совпадает с сохранённым диапазоном ревью. Точное множество путей поставки — `["test/design_system/option_group_test.dart"]`. Второй изменённый путь, `tasks.md:299`, является плановым свидетельством: меняется только отметка 2.9 на выполненную. Идентификаторы, номера, описания, порядок и прежние отметки задач сохранены. Несопоставленных путей нет, новых задач и исправлений в этом этапе не добавлено.

На сохранённой голове `test/design_system/option_group_test.dart:77` проверяет выбор после нажатия через `CheckedState.isTrue/isFalse`; строки 181–195 проверяют явное состояние недоступности группы и вариантов через `Tristate`, выбранность и взаимоисключение. Сохранены все 62 вызова `expect` и шесть объявлений `testWidgets`, разворачивающихся в восемь проверок с обеими темами. Все восемь вызовов `hasFlag` удалены; проверки роли, причины недоступности, отсутствия действия нажатия, оформления, размеров, масштаба текста и клавиатуры сохранены.

В закреплённом SDK `packages/flutter/lib/src/semantics/semantics.dart:3399` предоставляет `flagsCollection`; `hasFlag` на строках 3403–3408 помечен устаревшим с прямой рекомендацией этого API. Преобразование `_toBitMask` на строках 7150–7177 подтверждает соответствие `hasEnabledState` состоянию, отличному от `Tristate.none`, и прежних флагов выбранности и взаимоисключения новым полям. Проверка `CheckedState.isFalse` также исключает отсутствие состояния и смешанное состояние, поэтому защита от регрессии не ослаблена.

Плановые источники `proposal.md`, три дельта-спецификации, `design.md`, `adr.md`, `plan.md` и `tasks.md` прочитаны из `3cc1a24d4cfc0330147d64c40d079990c4ef2066`; терминология взята из `CONTEXT.md`. Неизменённый компонент `lib/src/design_system/components/option_group.dart` и закрепление SDK в `mise.toml` проверены как контекст. Существующий отчёт прочитан после завершения независимого прохода: активных замечаний в нём не было; применимый AR1 сохранён с исходными свидетельствами и полномочиями принятия риска.

Проверки выполнены в `/home/seniorkonung/.paseo/worktrees/1id27gtb/modest-yak` на `3cc1a24d4cfc0330147d64c40d079990c4ef2066`, до изменения отчёта. Рабочее дерево было чистым до проверок и осталось чистым после генерации и сборки; незакоммиченные входы в проверяемый снимок не включались.


Команда `mise exec --no-deps -- flutter test test/design_system/option_group_test.dart` — exit 0, все 8 тестов прошли.

Команда `mise exec --no-deps -- flutter analyze --no-pub test/design_system/option_group_test.dart` — exit 0, No issues found, включая отсутствие `deprecated_member_use`.

Команда `mise run check` — exit 0; форматирование 798 файлов без изменений, проверки инструментов CI и разбиения тестов, анализ всего проекта без диагностик, 3387 обычных и 18 процессных тестов.

Команда `mise exec --no-deps -- openspec validate add-intention-picker-sorting-and-purpose --json` — exit 0, valid, issues [].

Команда `mise exec --no-deps -- openspec validate add-intention-picker-sorting-and-purpose --strict --no-interactive` — exit 0, change is valid.

Команда `mise run codegen-check` — exit 0 на чистой рабочей копии после коммита реализации; генерация локализации, build_runner и снимка Drift не изменила tracked-файлы.

Команда `mise exec --no-deps -- flutter build apk --release` — exit 0; артефакт `build/app/outputs/flutter-apk/app-release.apk` (71,8 MB).

Release APK: `/home/seniorkonung/.paseo/worktrees/1id27gtb/modest-yak/build/app/outputs/flutter-apk/app-release.apk`. DTD не обнаружил запущенного приложения; устройство и эмулятор не запускались. Ручные проверки остаются за пользователем: вид заголовка и листа в трёх поисках и обеих темах относительно макета, прокрутка с открытой клавиатурой, немедленное применение и сброс параметров, закреплённый тип, пустые состояния, новое открытие поиска и объявления TalkBack. Их отсутствие не блокирует завершение фазы и не доказывает исправление особенностей устройства.

Реализация задачи 2.9 проверена; автоматические условия завершения фазы 2 выполнены. Решений по исправлению или принятию новых рисков не требуется. AR1 остаётся принятым остаточным риском вне текущего диапазона; код, плановые артефакты и история задач в этом этапе не менялись.
