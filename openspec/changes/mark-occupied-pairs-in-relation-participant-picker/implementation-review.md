# OpenSpec Implementation Review: mark-occupied-pairs-in-relation-participant-picker

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Исправления 1.9–1.13 работают, а `mise run check` на проверенной ревизии проходит, но задача 1.10 внесла регрессию (F1): новая выдача, начатая пока список закрыт страницей, после ещё одной подтверждённой операции открывается не сверху. Это нарушает требование «Отметка занятой пары в поиске участника» и критерий задачи 1.10, поэтому условие готовности фазы 1 о соответствии спецификации не подтверждено. Принятых рисков нет.

## Review target

- **Baseline ref:** e62d4e96c99e81733ce415a8d4558a6a6c5ce19b
- **Base commit:** e62d4e96c99e81733ce415a8d4558a6a6c5ce19b
- **Reviewed head:** 478d8c30464ebb7bd9c1860c8539f40e3aebbbdf
- **Target commits:** ["88d6fcbc5df850fcc93c8e7c67ce6eba6ffe3179","54da4ccdd3a24f71f80370185c2908c34890a850","cb69869f758ff01e17382c7c224c3f886445e1b5","ea6ea82f32c33bec668bbe0b44e6f24b59e47058","56e9e5a1eff7a5d6c49088ea5b91f6eb227cccef","3b576a4af16c5540b93ac190531f73f996f59fc1","478d8c30464ebb7bd9c1860c8539f40e3aebbbdf"]
- **Reviewable paths:** ["lib/src/design_system/components/badge.dart","lib/src/intention/presentation/catalog/intention_search_results.dart","lib/src/intention/presentation/search/intention_search_list.dart","lib/src/intention/presentation/search/results_scroll_keeper.dart","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md","test/app/navigation/app_shell_pages_above_test.dart","test/design_system/badge_test.dart","test/design_system/page_head_test.dart","test/design_system/relation_row_test.dart","test/design_system/tag_line_test.dart","test/intention/presentation/catalog/catalog_reconciliation_test_support.dart","test/intention/presentation/catalog/intention_search_results_test.dart","test/intention/presentation/details/intention_details_head_test.dart","test/intention/presentation/picker/intention_picker_row_test.dart","test/intention/presentation/search/intention_search_list_test.dart"]
- **OpenSpec change:** mark-occupied-pairs-in-relation-participant-picker
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md"]

## Reviewed increment

### U1 · Первая видимая строка выдачи остаётся на месте

- **Work items:** ["1.10", "1.11", "1.12"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога", "intention-management: Сохранение позиции после локального согласования", "long-term-relation-management: Отметка занятой пары в поиске участника", "plan.md Phase 1: Подтверждённое изменение на странице, открытой из поиска, не сдвигает первую видимую строку", "plan.md Phase 1: Добавление порции не прерывает идущую прокрутку"]
- **Affected boundary:** Человек, который прокручивает выдачу поиска намерений на экранах каталога и выбора; виджеты списка и поток состояний модели каталога.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_search_results.dart","lib/src/intention/presentation/search/intention_search_list.dart","lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/catalog/catalog_reconciliation_test_support.dart","test/intention/presentation/catalog/intention_search_results_test.dart","test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Реальный сдвиг можно поправить ценой остановки инерции; вмешательство во внутреннее состояние прокрутки Flutter отклонено владельцем продукта. Модель каталога, проекция строки и линия меток не меняются, место под метку не резервируется. Общий каталог и поиски дневного выбора меняются только в удержании места. Обычные проверки не замеряют время.

### U2 · Метка без значка и слова непредставима

- **Work items:** ["1.13"]
- **Requirements and scenarios:** ["design.md, Decision 5: вариант Badge «слово в строке списка»", "plan.md: компоненты дизайн-системы остаются представлениями без предметной логики"]
- **Affected boundary:** Код приложения, создающий метки, и проверки дизайн-системы, которые их читают.
- **Implementation target:** ["lib/src/design_system/components/badge.dart","test/design_system/badge_test.dart","test/design_system/page_head_test.dart","test/design_system/relation_row_test.dart","test/design_system/tag_line_test.dart","test/intention/presentation/details/intention_details_head_test.dart","test/intention/presentation/picker/intention_picker_row_test.dart"]
- **Applicable constraints and non-goals:** Вызовы `Badge.mark`, `Badge.archived` и `Badge.word` не меняются и остаются const. Вид, цвета, размеры и узлы экранного диктора не меняются. Новых вариантов нет.

### U3 · Сценарий ухода со страницы участника проверяет прежнее поведение

- **Work items:** ["1.9"]
- **Requirements and scenarios:** ["long-term-relation-management: Нажатие на отмеченную строку поиска участника", "сценарий app_shell_pages_above_test: выбор пункта N со страницы участника удаляет незавершённую форму связи без сохранения"]
- **Affected boundary:** Набор проверок навигации приложения.
- **Implementation target:** ["test/app/navigation/app_shell_pages_above_test.dart"]
- **Applicable constraints and non-goals:** Код приложения и спецификации не меняются; прочие шаги сценария не меняются.

### U4 · Подтверждение готовности фазы 1

- **Work items:** ["1.14"]
- **Requirements and scenarios:** ["plan.md Phase 1: Ready to advance"]
- **Affected boundary:** Решение о завершении фазы 1 и переходе к фазе 2.
- **Implementation target:** ["openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md"]
- **Applicable constraints and non-goals:** Задача содержит только проверки и сборку, код не меняется. Устройство и эмулятор не запускаются, ручные проверки остаются за пользователем.
- **Excluded change scope:** Фаза 2 не начата и не считается недоставленной: требование «Восстановление занимающей связи из создания» и правило открытия восстановленной связи в `app-navigation`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Три свежих проверяющих без истории и планирующих материалов получили нейтральные брифы и непересекающиеся наборы путей точного диапазона: U1 — 6 путей, U2 — 7, U3 — 1. U4 не содержит путей доставки. Проверяющий U1 раскрыл два отступления: один `git diff --stat` без списка путей показал только имена других изменённых файлов, а `git grep` по `lib` прошёл и по `badge.dart` вне его цели без совпадений. Содержимое запрещённых материалов не читалось, поэтому независимость сохранена. |
| OpenSpec conformance | Complete | В рабочей копии при чистом дереве и HEAD = 478d8c30464ebb7bd9c1860c8539f40e3aebbbdf: `mise run check` — exit 0 (`dart format`, проверки скриптов, `flutter analyze` без замечаний, 3900 тестов и 18 процессных тестов прошли); `mise run codegen-check` — exit 0; `openspec validate --strict --no-interactive` — valid с ожидаемым INFO об архивации дельты `intention-management` после `redesign-intention-catalog` (Plan Constraints); `git grep excludedIntentionId` по путям задачи 1.14 — 0 совпадений. APK в этом обзоре не собирался; `build/app/outputs/flutter-apk/app-release.apk` от 17:13 старше коммита 478d8c30 (17:18), который меняет только `tasks.md`. Отметка задачи 1.14 о соответствии спецификации опровергается F1. |
| Code quality | Complete | В контексте оркестратора пять осей `code-review-and-quality` применены ко всем путям доставки на проверяемой ревизии: корректность и согласованность хранителя, читаемость, границы модулей, безопасность, производительность. Новых входов с недоверенными данными нет. Новые пробы в одноразовой копии проверяемой ревизии подтвердили F1 и чувствительность регрессионных проверок. |

## Findings

### F1 · Medium — Новая выдача, начатая под закрытой страницей, открывается не сверху после следующей операции

- **Evidence:** `lib/src/intention/presentation/search/results_scroll_keeper.dart:88-93` запоминает якорь, когда у `previous` и `next` один объект запроса, и не проверяет, что построенный список относится к этой же выдаче. `_captureVisualAnchor` (`:174-198`) берёт порядок строк из `previousState`, а геометрию — из построенных строк.
  Под закрытой страницей `ref.listen` продолжает работать, а список не перестраивается, поэтому `onListBuilt` (`:99-105`) не вызывается и `_shown` остаётся прежней выдачей. Новая выдача сбрасывает смещение через `_jumpToTop` (`:70-76`, `:138-145`), а следующая операция снимает якорь со строк старой выдачи уже с новым запросом. Защита `identical(state.query, anchor.query)` (`:232`) его не отсеивает.
  До задачи 1.10 такой якорь отбрасывался: восстановление шло по устаревшей выдаче с другим запросом. Теперь он доживает до перестройки, и `_restoreVisualAnchor` (`:225-254`) уводит новую выдачу от верхней позиции.
  Сценарий достижим двумя путями. В поиске участника запрос начинает заново вход строки по изменению (`intention_catalog_view_model.dart:980-986`). На любом экране поиска — удаление тега из условий (`intention_catalog_view_model.dart:685-696`).
  Воспроизведено в одноразовой копии. Поиск участника с пробой, список прокручен и закрыт страницей; подтверждённое изменение вводит новую строку и начинает выдачу заново; затем подтверждённое создание связи меняет отметку загруженной строки. После возврата на 478d8c30 `pixels = 56` вместо 0, а новая строка скрыта над верхом списка. Тот же сценарий с хранителем и обоими виджетами из e62d4e96 даёт 0. Контроль на 478d8c30: новая выдача по смене условий тегов без второй операции открывается с позиции 0.
  Проверяющий U1 воспроизвёл тот же дефект через условия тегов: `IntentionSearchList` — `pixels = 560`, `IntentionSearchResults` — `pixels = 240`, на base — 0.
  Проверка «новая выдача, начатая после изменения строк, пока список закрыт страницей, стоит сверху» (`test/intention/presentation/search/intention_search_list_test.dart`) покрывает только обратный порядок: сначала операция, затем новая выдача.
- **Evidence revisions:** ["478d8c30464ebb7bd9c1860c8539f40e3aebbbdf","e62d4e96c99e81733ce415a8d4558a6a6c5ce19b"]
- **Impact:** Человек возвращается из страницы, открытой из поиска, и видит список не с начала. В поиске участника вошедшая строка может оказаться выше видимой части. Путь естествен: на странице восстановить намерение, затем восстановить или изменить его связь. Это нарушает требование «Отметка занятой пары в поиске участника» («поиск SHALL начинать выдачу заново… Позиция прокрутки при этом не сохраняется»), критерий задачи 1.10 о новой выдаче и условие плана о неизменности общего каталога и поисков дневного выбора вне удержания места. Дефект задевает все экраны поиска, потому что хранитель общий.
- **Required outcome:** Новая выдача, начатая пока список закрыт страницей, после возврата показана с верхней позиции независимо от числа и порядка подтверждённых операций после её начала. Якорь не строится по строкам другой выдачи. Регрессионная проверка закрепляет порядок «новая выдача, затем операция» и падает без исправления. Результаты задач 1.10–1.12 сохраняются.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/search/intention_search_list_test.dart","tasks.md: 1.10, 1.14"]

## Review coverage

Проверены все 7 целевых коммитов. 88d6fcbc вносит только оценки профилей задач (планирующее свидетельство). 54da4ccd — U3 (1.9); cb69869f, ea6ea82f и 56e9e5a1 — U1 (1.10–1.12); 3b576a4a — U2 (1.13); 478d8c30 — U4 (1.14). Отметки 1.9–1.14 в `tasks.md` сверены с диапазоном; единственная отметка, опровергнутая кодом, описана в F1.

**U1.** Прослежены потоки: несколько операций подряд под закрытой страницей, уход первой видимой строки и её соседей, вставка перед видимой строкой, подгрузка порции одновременно с операцией, разные причины перестройки у `IntentionSearchList` и `IntentionSearchResults`, переход к верху при новой выдаче. Семь регрессионных проверок задач 1.10–1.12 падают с хранителем и виджетами из e62d4e96. Обе проверки задачи 1.12 падают, если убрать сравнение `pairOccupants`, а у `PairOccupant` сравнение по значению. Спецификации и модель каталога в диапазоне не менялись, а `_idsByDistance` и карта индексов оправданы проверкой на уход соседей и линейной стоимостью поиска.

**U2.** `Badge` закрыт, варианты хранят обязательные поля, ветки `StateError` нет. Сравнение прежних приватных методов с новыми `build` не показало отличий размеров, отступов, цветов и `ExcludeSemantics`. Вызовы приложения не менялись, `find.byType(Badge)` в проверках не осталось, утверждения не ослаблены.

**U3.** Пара «Читать» → «Бегать» занята связью фикстуры, «Гулять» свободна. Сценарий по-прежнему проверяет удаление формы без подтверждения, код приложения не менялся.

**U4.** Подтверждены отсутствие `excludedIntentionId`, полные проверки, кодогенерация и валидность изменения на проверенной ревизии. Подтвердить соответствие спецификации нельзя из-за F1.

Ручные проверки на устройстве не выполнялись и остаются за пользователем: метки в светлой и тёмной темах, чтение отметки диктором, переход из отмеченной строки и возврат.
