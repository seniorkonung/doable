# OpenSpec Implementation Review: introduce-actions-and-intention-kinds

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 3.19 выполнена. Вид, выбранный при создании намерения в поиске участника, теперь хранится только в записи сессии поиска `_createdKinds`. Отметка поиска хранит одно актуальное название. Поведение не изменилось, и `mise run check` на проверяемой голове проходит целиком, чем закрывается фаза 3. Нерешённых находок нет, принятых остаточных рисков нет.

## Review target

- **Baseline ref:** d3b228a874a4b63bcf0844bca4b81c68e870573d
- **Base commit:** d3b228a874a4b63bcf0844bca4b81c68e870573d
- **Reviewed head:** bd2249eb06e5408b19f7077a77afc8956e71c1a6
- **Target commits:** ["4c1fe462194ead5ac322677f413e2b4bf19c5e33", "bd2249eb06e5408b19f7077a77afc8956e71c1a6"]
- **Reviewable paths:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]
- **OpenSpec change:** introduce-actions-and-intention-kinds
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]

## Reviewed increment

### U1 · Вид созданного в поиске участника намерения хранится в одном месте сессии поиска

- **Work items:** ["3.19"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника", "Scenario: Вспомогательным намерение становится вместе со связью", "Scenario: Без связи созданное намерение остаётся главным"]
- **Affected boundary:** Пользователь поиска участника и сохранённый граф: вид намерения и связи.
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart"]
- **Applicable constraints and non-goals:** Поведение и требование остаются прежними. Намерение создаётся главным. Вспомогательным оно становится только вместе с подтверждённой связью в той же операции. Входящие группы и контракт команды не меняются. Комментарии пишутся на русском.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Отдельный рецензент без истории работал по нейтральному описанию намерения. Цель: `d3b228a8..bd2249eb`, путь `lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart`. Покрытие полное, существенных находок нет. |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --json` проходит. Состояние OpenSpec: все артефакты планирования готовы. Критерии 3.19 сверены с диффом. `mise run check` запускался в этом рабочем дереве на `bd2249eb`: HEAD совпадает с проверяемой головой, дерево чистое. Код выхода 0: формат, `flutter analyze` без замечаний, 4110 обычных тестов и 18 процессных тестов. |
| Code quality | Complete | Изменённые `toggle`, `acceptCreated`, `submit`, переименование в `_onPackage` и `_BatchMark` проверены на корректность, читаемость, архитектуру, безопасность и производительность. Учтены неизменённые `remove`, снятие отметки при архивировании, удалении и занятой паре, а также входящая ветка `submit`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Решение «становится вспомогательным» вычисляется только в `submit` для исходящих групп: `_createdKinds[id] == IntentionKind.supporting`. Раньше то же значение копировалось в отметку в `toggle` и `acceptCreated`, поэтому результат прежний. Снятая и не возвращённая отметка не попадает в кандидаты. Намерения, созданные не в этом поиске, записи вида не имеют. Входящая команда по-прежнему получает только `candidateIds`. Переименование больше не переносит вид, так что потерять его при обновлении названия невозможно. Утверждения тестов «повторная отметка сохраняет выбранный при создании вид» и «снятая отметка оставляет созданное намерение главным» в `relation_batch_picker_page_test.dart` не менялись, и оба теста проходят в полном прогоне. Новых тестов задача не требует.

Задача разрешала оставить `_BatchMark` классом с одним полем или заменить его на `Map<IntentionId, String>`. Оставленный класс — допустимый вариант: замена на словарь упростила бы код лишь незначительно. Doc-комментарий отметки обновлён и написан на русском.

Файлы `task-profiles.md` и `tasks.md` — свидетельства планирования: профиль 3.19 и отметка о её выполнении. Отметка подтверждена кодом и проверками. Бенчмарки не перезапускались: диапазон не затрагивает ни индекс удержания, ни каталог.
