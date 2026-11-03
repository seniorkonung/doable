# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 4.26 подтверждена: новый тест проверяет сохранение экранного положения намерения после появления строки «Создать», завершённой перестройки, прокрутки и следующей вставки перед видимой строкой. Независимый проход, соответствие OpenSpec и проверка качества завершены. Неурегулированных находок и принятых рисков нет.

## Review target

- **Baseline ref:** b8a925592a14fcd7840254dc5ea0e6b19a053877
- **Base commit:** b8a925592a14fcd7840254dc5ea0e6b19a053877
- **Reviewed head:** 9dab8f5d451eab4e6dbb07e7ea952a93065bca1e
- **Target commits:** ["01d205242ecdf6c23c83b0809c4d79f7621727ad","9dab8f5d451eab4e6dbb07e7ea952a93065bca1e"]
- **Reviewable paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/intention/presentation/search/intention_search_list_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Сохранение позиции после появления строки «Создать» проверяется регрессионным тестом

- **Work items:** ["4.26"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога / Сохранение позиции после локального согласования","long-term-relation-management: Создание намерения из поиска участника","long-term-relation-management: Причина занятой пары в поиске участника — исключение со сбросом выдачи"]
- **Affected boundary:** Человек в поиске участника и согласование отображаемой выдачи с подтверждёнными изменениями графа.
- **Implementation target:** ["test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Один тест на русском, небольшая фикстура, без замеров времени и расширенного тайм-аута; проверка без устройства. Рабочий код, продуктовый контракт и существующие тесты сохраняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный агент `decision_review` (GPT-6.1 Sol, medium), навык `implementation-decision-review`, нейтральный бриф и единственный путь U1. Изучен полный файл на точном диапазоне; неизменённый контекст читался после проверки границ. Существенных находок нет. |
| OpenSpec conformance | Complete | Критерии задачи 4.26 (`tasks.md:1376–1387`) сверены с обоими коммитами. На чистом рабочем дереве с `HEAD=9dab8f5d451eab4e6dbb07e7ea952a93065bca1e` команда `mise exec --no-deps -- flutter test test/intention/presentation/search/intention_search_list_test.dart` завершилась кодом 0: 42 теста. Проверка мутацией и повтор после восстановления описаны ниже. `mise run check` — код 0: форматирование без изменений, проверки инструментария, анализ без замечаний, 4019 обычных и 18 процессных тестов прошли. `mise exec --no-deps -- openspec validate add-relations-in-batches --strict --json` — `valid: true`, замечаний нет; это структурное свидетельство. |
| Code quality | Complete | Пять направлений `code-review-and-quality` применены ко всему пути U1: корректность, читаемость, архитектура, безопасность и производительность. Проверены последовательность кадров, принадлежность изменений одному запросу, наблюдаемая экранная координата, отличия от соседних тестов и ограниченный размер фикстуры. Новых зависимостей и границ доверия нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Единица U1 покрывает задачу `taskId=94`, номер `4.26`, с сохранением её описания и завершённого состояния. Все три пути диапазона учтены: два документа служат плановыми свидетельствами, файл тестов — единственный путь проверки поведения. Несопоставленных путей нет.

Коммит `01d205242ecdf6c23c83b0809c4d79f7621727ad` добавляет профиль задачи 4.26 (`task-profiles.md:472–475`), соответствующий ограниченному тестовому изменению; он сопоставлен U1 и задаче 94 / 4.26.

Коммит `9dab8f5d451eab4e6dbb07e7ea952a93065bca1e` добавляет тест `intention_search_list_test.dart:667–710` и отмечает задачу выполненной в `tasks.md:1376`; он сопоставлен U1 и задаче 94 / 4.26. Других изменений рабочего кода или существующих проверок нет.

Тест загружает 15 намерений, переименованием намерения страницы снимает единственное точное совпадение и ждёт три кадра через существующий помощник `_settle`. Затем прокручивает список, запоминает координату «Действие 12» и подтверждает создание «Действие 16» на следующей ревизии. Проверки `:708–709` устанавливают появление новой первой строки и сохранение координаты видимого намерения.

В неизменённом контексте головы изучены `IntentionSearchList`, `ResultsScrollKeeper` и согласование в `IntentionCatalogViewModel`. Создание проходит ветку `IntentionCatalogCreated` (`intention_catalog_view_model.dart:999–1028`), сохраняющую запрос и локально вставляющую намерение; исключение со сбросом поиска не применяется. Тесты появления строки в начале, её появления и ухода на ненулевой позиции и нескольких изменений до перестройки сохранены. Новый тест проверяет следующий переход уже после обслуживания кадра.

Мутация проверена отдельно на временной копии входных файлов головы в `/tmp/review-mutation-inputs-4xu2xqt4`: `flutter test --no-pub test/intention/presentation/search/intention_search_list_test.dart`, Flutter взят из `mise exec --no-deps`. Единственное изменение копии — удаление `_holdsStart = false` из `results_scroll_keeper.dart:252`. Результат: код 1, 41 тест прошёл, только новый тест упал на `:709`: ожидалась координата 44, получена 100. После восстановления исходных байтов та же команда завершилась кодом 0, все 42 теста прошли. Копия удалена; исходники рабочего дерева при проверке не менялись.

Плановые свидетельства прочитаны из записанной головы; незакоммиченных входных изменений при начале ревью и проверок не было. Исправления кода и плановых артефактов, новые задачи и передача работ на устранение находок не потребовались. Полная проверка фазы выполнена в корне репозитория на записанной голове; проверки на устройстве остаются за владельцем продукта.
