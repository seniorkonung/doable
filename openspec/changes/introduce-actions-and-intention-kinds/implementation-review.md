# OpenSpec Implementation Review: introduce-actions-and-intention-kinds

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 3.17 и 3.18 выполнены. Три теста потоков связей теперь явно выбирают группу «Нужно», а `mise run check` на проверяемой голове проходит целиком. Вид, выбранный при создании намерения в поиске участника, сохраняется после снятия и повторной отметки, и это закреплено тестом через экран и хранилище. Нерешённых находок нет: устранение двойного хранения вида созданного намерения в модели поиска передано задаче 3.19. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** efb39c009dfee2f06ab58725287f8008a832c689
- **Base commit:** efb39c009dfee2f06ab58725287f8008a832c689
- **Reviewed head:** 81ae44ea26af29e63004d70695fb3e6a47b0c8bb
- **Target commits:** ["5c8e38baa2391bba42cb86e6e39f3363f7a0f37c", "6c838b226cf14ee58877c5fee7a37d3eff1308ef", "81ae44ea26af29e63004d70695fb3e6a47b0c8bb"]
- **Reviewable paths:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md", "test/app/long_term_relation_app_flow_test.dart", "test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **OpenSpec change:** introduce-actions-and-intention-kinds
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]

## Reviewed increment

### U1 · Тесты потоков связей не зависят от начальной группы вкладки «Связи»

- **Work items:** ["3.17"]
- **Requirements and scenarios:** ["long-term-relation-management: Порционное получение группы связей намерения"]
- **Affected boundary:** Автоматические проверки проекта: тесты потоков приложения через реальный интерфейс.
- **Implementation target:** ["test/app/long_term_relation_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Поведение продукта и правило начальной группы из 3.13 не меняются, код в `lib/` не затрагивается. Утверждения тестов не ослабляются.

### U2 · Вид созданного в поиске участника намерения сохраняется на всю сессию поиска

- **Work items:** ["3.18"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника", "Scenario: Вспомогательным намерение становится вместе со связью", "Scenario: Без связи созданное намерение остаётся главным"]
- **Affected boundary:** Пользователь поиска участника и сохранённый граф: вид намерения и связи.
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **Applicable constraints and non-goals:** Намерение создаётся главным. Вспомогательным оно становится только вместе с подтверждённой связью в группах «Нужно» и «Можно использовать», в той же атомарной операции. Требование не меняется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два отдельных рецензента без истории работали по нейтральным описаниям намерения. U1: `efb39c00..6c838b22`, путь `test/app/long_term_relation_app_flow_test.dart`, существенных находок нет. U2: `6c838b22..81ae44ea`, пути view model и page test, одна находка низкой важности, она вошла в F1. |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --json` проходит. Состояние OpenSpec: все артефакты планирования готовы. Критерии 3.17 и 3.18 сверены с диффом и требованием «Создание намерения из поиска участника». `mise run check` в этом рабочем дереве на `81ae44ea` (HEAD совпадает с проверяемой головой, дерево чистое) завершился с кодом 0: формат, проверки CI-скриптов, `flutter analyze` без замечаний, 4110 обычных тестов и 18 процессных тестов. |
| Code quality | Complete | Изменения view model поиска участника проверены на корректность, читаемость, архитектуру, безопасность и производительность: `toggle`, `acceptCreated`, `remove`, `submit`, `_onPackage`, `_BatchMark`. Также проверены добавленные тесты и ключ `intention-relations-group-needs` в `intention_relations_sliver.dart`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

В U1 проверены пять вставок явного выбора группы «Нужно» в трёх тестах, которые назвала задача 3.17. Утверждения не ослаблены. Ключ группы взят из `intention_relations_sliver.dart`. Из `lib/` в диапазоне меняется только view model из U2.

В U2 проверено правило запоминания вида в `relation_batch_view_model.dart`. Рассмотрены снятие отметки через `toggle` и `remove` с повторной отметкой, снятие отметки при архивировании и занятой паре в `_onPackage` и входящие группы, где команда не несёт флага вида. Область жизни `_createdKinds` совпадает с экземпляром поиска, поэтому закрытие или сброс поиска её сбрасывает. Новый тест «повторная отметка сохраняет выбранный при создании вид» проверяет сохранённый вид через хранилище. Существующий тест «снятая отметка оставляет созданное намерение главным» сохранён. Комментарий `acceptCreated` описывает новое правило, как требует 3.18.

Файлы `task-profiles.md` и `tasks.md` — свидетельства планирования: профили 3.17–3.18 и отметки выполнения. Отметки подтверждены кодом и проверками. Бенчмарки индекса удержания не перезапускались: диапазон не затрагивает индекс удержания и каталог, а их бюджеты подтверждены предыдущим ревью фазы 3.
