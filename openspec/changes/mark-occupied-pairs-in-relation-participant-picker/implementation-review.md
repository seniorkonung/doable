# OpenSpec Implementation Review: mark-occupied-pairs-in-relation-participant-picker

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Исправление 1.15 работает: новая выдача, начатая пока список закрыт страницей, после возврата стоит сверху при любых подтверждённых операциях, а условие «Ready to advance» фазы 1 подтверждено на проверенной ревизии, `mise run check` проходит. Осталась одна находка F1 низкой важности: после исправления проверка запроса в `_restoreVisualAnchor` недостижима. На поведение она не влияет. Принятых рисков нет.

## Review target

- **Baseline ref:** 7f38401de67d1465d090a3e953b2625bc8a72224
- **Base commit:** 7f38401de67d1465d090a3e953b2625bc8a72224
- **Reviewed head:** 3de0dc9df86a4bf90e4228e0e5b25daa4aaada23
- **Target commits:** ["bc4c7b97c31ec7c41060920d69006bb8699499b6","fc6897db9a089dd2ce9d7180d6f6d94061d2815f","3de0dc9df86a4bf90e4228e0e5b25daa4aaada23"]
- **Reviewable paths:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md","test/intention/presentation/search/intention_search_list_test.dart"]
- **OpenSpec change:** mark-occupied-pairs-in-relation-participant-picker
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md"]

## Reviewed increment

### U1 · Новая выдача, начатая под закрытой страницей, стоит сверху

- **Work items:** ["1.15"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога", "intention-management: Сохранение позиции после локального согласования", "long-term-relation-management: Отметка занятой пары в поиске участника", "long-term-relation-management: Восстановленное намерение начинает выдачу поиска заново", "plan.md Phase 1: Подтверждённое изменение на странице, открытой из поиска, не сдвигает первую видимую строку", "plan.md Phase 1: Добавление порции не прерывает идущую прокрутку"]
- **Affected boundary:** Человек, который возвращается к выдаче поиска намерений со страницы поверх неё; виджеты списка и поток состояний модели каталога на всех экранах поиска.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Модель каталога, проекция строки, спецификации, `plan.md` и `design.md` не меняются. Общий каталог и поиски дневного выбора меняются только в удержании места. Реальный сдвиг можно поправить ценой остановки инерции; вмешательство во внутреннее состояние прокрутки Flutter отклонено владельцем продукта. Обычные проверки не замеряют время.

### U2 · Подтверждение готовности фазы 1

- **Work items:** ["1.16"]
- **Requirements and scenarios:** ["plan.md Phase 1: Ready to advance"]
- **Affected boundary:** Решение о завершении фазы 1 и переходе к фазе 2.
- **Implementation target:** ["openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md"]
- **Applicable constraints and non-goals:** Задача содержит только проверки и сборку, код не меняется. Устройство и эмулятор не запускаются, ручные проверки остаются за пользователем.
- **Excluded change scope:** Фаза 2 не начата и не считается недоставленной: требование «Восстановление занимающей связи из создания» и правило открытия восстановленной связи в `app-navigation`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий проверяющий без истории получил нейтральный бриф и два пути точного диапазона U1. U2 не содержит путей доставки. Находок нет. Проверяющий не открывал планирующие материалы; `git diff --name-only` показал ему только имена путей под `openspec/`. Прежний отчёт оркестратор прочитал до его возврата, но проверяющему не передавал, поэтому независимость сохранена. Его довод о приостановке `ref.listen` неверен: в `flutter_riverpod` 3.4.2 приостанавливаются только подписки `ref.watch`, а `ref.listen` закрытого списка получает каждое событие. Оркестратор заново проследил поток с этой поправкой, вывод не изменился. |
| OpenSpec conformance | Complete | В рабочей копии при чистом дереве и HEAD = 3de0dc9df86a4bf90e4228e0e5b25daa4aaada23: `mise run check` — exit 0 (`dart format`, проверки скриптов, `flutter analyze` без замечаний, 3901 тест и 18 процессных тестов прошли); `mise run codegen-check` — exit 0; `openspec validate --strict --no-interactive` — valid с ожидаемым INFO об архивации дельты `intention-management` после `redesign-intention-catalog` (Plan Constraints); `grep` по `excludedIntentionId` из задачи 1.16 — 0 совпадений. APK в этом обзоре не собирался; `build/app/outputs/flutter-apk/app-release.apk` от 18:12:16 новее коммита fc6897db (17:53:42) и старше 3de0dc9d, который меняет только `tasks.md`. |
| Code quality | Complete | В контексте оркестратора пять осей `code-review-and-quality` применены к путям доставки на проверяемой ревизии: корректность хранителя и его обоих потребителей, читаемость, границы модулей, безопасность, производительность. Новых входов с недоверенными данными нет, добавленная проверка постоянна по времени. Проба в одноразовой копии подтвердила чувствительность новой регрессионной проверки и дала F1. |

## Findings

### F1 · Low — После исправления 1.15 проверка запроса при восстановлении якоря недостижима

- **Evidence:** Коммит fc6897db добавил условие `_isShownResultsOf` при запоминании якоря (`results_scroll_keeper.dart:91`). Теперь якорь создаётся только для выдачи, по которой построен `_shown`, а смена запроса и показ состояния вместо строк сбрасывают его через `_jumpToTop` (`:70-82`, `:139-146`). Поэтому в `_restoreVisualAnchor` условие `!identical(state.query, anchor.query)` (`:245`) не может сработать: `_shown` с другим запросом появляется только после публикации этого запроса, а она уже убрала якорь. Поле `_VisualAnchor.query` (`:352`, `:363`, `:375`) нужно только этому условию. До исправления условие было достижимо, когда якорь выдачи запоминался при отставшем `_shown`. Проба в одноразовой копии проверяемой ревизии: без условия `:245`, а заодно и без `:90`, 160 проверок из списка задачи 1.15 прошли. Условие `:90` в находку не входит: оно остаётся локальным предусловием чтения строк из `previousState`.
- **Evidence revisions:** ["3de0dc9df86a4bf90e4228e0e5b25daa4aaada23"]
- **Impact:** Читатель хранителя видит защиту от состояния, которого нет, и считает, что якорь может пережить смену выдачи. Хранитель несёт лишнее поле и лишний инвариант. Поведение не нарушено.
- **Required outcome:** Хранитель не проверяет принадлежность якоря выдаче при восстановлении и не хранит данных только для этой проверки, а удержание места и начало новой выдачи сверху сохраняются.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart"]

## Review coverage

Проверены все 3 целевых коммита. bc4c7b97 вносит только оценки профилей задач 1.15 и 1.16 (планирующее свидетельство). fc6897db — U1 (1.15) и отметка задачи в `tasks.md`. 3de0dc9d — U2 (1.16) и отметка задачи в `tasks.md`. Обе отметки подтверждены диапазоном и проверками выше.

**U1.** Прослежены потоки: одна и несколько операций после начала новой выдачи, операция до и после её начала, новая выдача при видимом списке, операция в том же кадре до перестройки, переход через пустую выдачу и через состояния вместо строк, ранее запомненный якорь. Оба потребителя хранителя не менялись: `IntentionSearchList` читает модель через `ref.watch`, `IntentionSearchResults` получает выдачу от страницы, и у обоих `_shown` отстаёт, пока список закрыт, а события модели приходят. Модель не публикует прежний объект запроса повторно, новые запросы создаются только при чтении первой порции (`intention_catalog_view_model.dart:128`, `:604`). Критерии 1.15 выполнены: якорь запоминается только при идентичных запросах `_shown` и нового состояния, спецификации, `plan.md` и `design.md` не менялись. Без условия `_isShownResultsOf` падает только новая регрессионная проверка, остальные 19 проверок файла проходят, а обратный порядок покрывает соседняя проверка «новая выдача, начатая после изменения строк». Отдельная проверка на несколько операций не нужна: каждое событие проходит одну и ту же ветку. Результаты 1.10–1.12 подтверждены полным прогоном.

**U2.** Подтверждены отсутствие `excludedIntentionId`, полные проверки, кодогенерация и валидность изменения на проверенной ревизии. Прежний опровергающий дефект задачи 1.14 устранён в U1, поэтому условие «Ready to advance» фазы 1 выполнено. Общий каталог и поиски дневного выбора в диапазоне изменились только в удержании места: единственный путь доставки — общий хранитель.

Ручные проверки на устройстве не выполнялись и остаются за пользователем: метки в светлой и тёмной темах, чтение отметки диктором, переход из отмеченной строки и возврат.
