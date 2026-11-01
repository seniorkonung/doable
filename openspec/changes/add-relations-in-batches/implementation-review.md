# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 1.19 выполнена: данные разрешений без читателя удалены, поведение подробного просмотра не изменилось, `mise run check` проходит. Сгенерированный файл модели соответствует исходнику с коммита `2cc712c2…` вне проверенного диапазона, `mise run codegen-check` на текущей голове ветки завершается с кодом 0. Активных находок и принятых рисков нет.

## Review target

- **Baseline ref:** 209c51b141e4226dceeb9e72b56fcdb4a8854624
- **Base commit:** 209c51b141e4226dceeb9e72b56fcdb4a8854624
- **Reviewed head:** 718e891ae795c3ee42e58371420b7d7c96e0338c
- **Target commits:** ["bab449fdaf1f1028a990d31df4bf3332c762eb02","718e891ae795c3ee42e58371420b7d7c96e0338c"]
- **Reviewable paths:** ["lib/src/long_term_relation/application/long_term_relation_projection.dart","lib/src/long_term_relation/presentation/details/relation_details_page.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/long_term_relation/presentation/details/relation_details_widget_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Подробный просмотр связи хранит только то, что читает рабочий код

- **Work items:** ["1.19"]
- **Requirements and scenarios:** ["long-term-relation-management: Результаты операций со связями", "long-term-relation-management: Атомарность и согласованность операций графа", ".claude/rules/proven-necessity.md: каждый элемент доказывает необходимость"]
- **Affected boundary:** Человек в подробном просмотре связи; модель представления и прикладная проекция подробных данных связи; тесты согласования открытого просмотра после изменений графа.
- **Implementation target:** ["lib/src/long_term_relation/application/long_term_relation_projection.dart","lib/src/long_term_relation/presentation/details/relation_details_page.dart","lib/src/long_term_relation/presentation/details/relation_details_state.dart","lib/src/long_term_relation/presentation/details/relation_details_view_model.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/long_term_relation/presentation/details/relation_details_widget_test.dart"]
- **Applicable constraints and non-goals:** Поведение для человека не меняется: доступность удаления, объяснение запрета, применимость действий жизненного цикла и открытие формы остаются прежними, в том числе после подтверждённого изменения разрешения без полного чтения. Вычисление и хранение разрешений не меняются.
- **Excluded change scope:** Нижняя панель вместо страницы и формы: фаза 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер `implementation-decision-review` без планирующих артефактов проверил все шесть путей U1 на `209c51b1…..718e891a…`, его покрытие — Complete, находок нет. Он читал рабочее дерево, а не `git show`, и `relation_details_state.dart` оценил по диффу и поиску. Вывод это не ограничивает: дерево было чистым, а `HEAD` равен проверенной голове. |
| OpenSpec conformance | Complete | Критерии 1.19 сверены с диффом в обе стороны. На чистом рабочем дереве с `HEAD` = `718e891a…`: `mise run check` — код 0 (формат, `flutter analyze` без замечаний, 3950 обычных и 18 процессных тестов); эти прогоны включают тесты из проверки задачи. `mise run codegen-check` запущен на чистом рабочем дереве с `HEAD` = `1a93c7fb…`, где исправление `2cc712c2…` уже есть: код 0, рабочее дерево осталось чистым. `mise exec --no-deps -- openspec validate add-relations-in-batches --strict` — код 0, это только структурное свидетельство. Бенчмарки не запускались: диапазон их не затрагивает. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем шести путям на `718e891a…`, вне правок учтены форма изменения связи, `_isLifecycleChangeApplicable`, чтения `permissions` на странице и сгенерированный файл модели. Безопасность и производительность диапазон не затрагивает: он только удаляет неиспользуемые данные. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все критерии 1.19 подтверждены на `718e891a…`, а соответствие сгенерированного файла — на `1a93c7fb…`. Коммит `2cc712c2…` лежит вне проверенного диапазона и меняет только хеш в `relation_details_view_model.g.dart`; других изменений в `lib/` и `test/` после `718e891a…` нет. `codegen-check` прошёл с инкрементальным кэшем: `build_runner` пропустил все входы и ничего не записал, потому что исходники не менялись с генерации этого файла. Значение `11dbe095db4104e080681cc7168763a8d65eb2fd` в файле совпадает с полученным при генерации на `718e891a…`. В `lib/` и `test/` нет `permissionRevision`, `editingDetails` и `withPermissions`. Страница передаёт форме `loaded.details` (`relation_details_page.dart:109`), а в `presentation/editor` нет ни одного чтения `permissions`, поэтому удаление `withPermissions` форму не меняет. Поле `permissions` и его обновление из подтверждённого изменения сохранены, их читают кнопка удаления, объяснение запрета и `_isLifecycleChangeApplicable`.

Новое ожидание в `graph_reconciliation_checkpoint_test.dart:564-566` не слабее прежнего. Прежнее условие на `permissionRevision` выполнялось и после полного чтения, потому что конструктор брал ревизию снимка, то есть различить источник разрешения оно не могло. Новое ждёт наблюдаемый исход, а до удаления выбора `canDelete` у связей 101 и 102 ложно. Второй снимок в `relation_details_widget_test.dart:86-96` собран с теми же идентификаторами, поэтому сценарий закрытия открытого удаления не изменился.

Коммит `bab449fd…` добавляет только профиль задачи 1.19 в `task-profiles.md`, код он не меняет. Все задачи фазы 1 отмечены выполненными. Условия готовности фазы подтверждены прошлым обзором на `e2f96a7e…`, а этот диапазон их не меняет; поиск в `lib/` и `test/` по-прежнему не находит `canChangeMeaning`, `long_term_relations_protect_daily_choice_path`, `ignoredRelationId` и `RelationChangeChoiceFlow`. Прошлый отчёт не содержал находок и принятых рисков, поэтому переносить нечего. Устройство не использовалось: ручные проверки остаются за владельцем продукта.
