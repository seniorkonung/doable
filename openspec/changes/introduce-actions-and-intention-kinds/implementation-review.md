# OpenSpec Implementation Review: introduce-actions-and-intention-kinds

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.31–2.33 реализованы, как требуют их критерии. Сгенерированные провайдеры согласованы с исходниками. «Повторить» после отказа чтения пути сохраняет подтверждённые числа половин, а данные переключателя у черновика в загрузке и после отказа гарантирует тип `NonEmptyPathDraft`. Исход добавления связей разбирается в одном месте `_finish`, а `RelationBatchAdded` не несёт данных. `mise run check` и `mise run codegen-check` на `f3686ab1` проходят, поэтому условие готовности фазы 2 «полные проверки проекта» выполнено. Неустранённых находок и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 9f10d9de080105d4dbdb591034d5fcfe86f14d60
- **Base commit:** 9f10d9de080105d4dbdb591034d5fcfe86f14d60
- **Reviewed head:** f3686ab1b0b82e5001d824a82dd61dc3651208f7
- **Target commits:** ["07f058fe20ddc09fdd89af4e3bdd3ea19d924042", "89e9e90be2508c933f564c7a563c98c1ce1a8919", "cc4f801716afb85eda69d8bd53261044c76c6121", "f3686ab1b0b82e5001d824a82dd61dc3651208f7"]
- **Reviewable paths:** ["lib/src/action/presentation/path/path_page.dart", "lib/src/action/presentation/path/path_state.dart", "lib/src/action/presentation/path/path_view_model.dart", "lib/src/action/presentation/path/path_view_model.g.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_state.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.g.dart", "openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md", "test/action/presentation/path/path_view_model_test.dart"]
- **OpenSpec change:** introduce-actions-and-intention-kinds
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]

## Reviewed increment

### U1 · Числа половин экрана пути сохраняются при повторе, а данные переключателя гарантирует тип

- **Work items:** ["2.31", "2.32"]
- **Requirements and scenarios:** ["action-paths: Половины «Нужно» и «Можно» на экране пути", "action-paths: Кандидаты следующего намерения", "plan.md Phase 2 Ready to advance: полные проверки проекта"]
- **Affected boundary:** Пользователь экрана пути; модель, состояние и виджет экрана пути
- **Implementation target:** ["lib/src/action/presentation/path/path_page.dart", "lib/src/action/presentation/path/path_state.dart", "lib/src/action/presentation/path/path_view_model.dart", "lib/src/action/presentation/path/path_view_model.g.dart", "test/action/presentation/path/path_view_model_test.dart"]
- **Applicable constraints and non-goals:** Пока последнее намерение то же, подтверждённые числа остаются до нового подтверждённого чтения. На новое последнее намерение они не переносятся. Остальное видимое поведение экрана, контракт запроса кандидатов и раскладка не меняются. Нужен type-safe design без `!` и проверок во время выполнения, а сгенерированный код должен совпадать с исходниками. Задача 2.31 общая с U2: её часть здесь — `path_view_model.g.dart`.

### U2 · Исход добавления связей разбирается один раз, а маркер успеха без данных

- **Work items:** ["2.31", "2.33"]
- **Requirements and scenarios:** ["action-paths: Добавление связей на экране пути", "long-term-relation-management: поиск участника связи (ADR-0049, общий модуль)", "plan.md Phase 2 Ready to advance: полные проверки проекта"]
- **Affected boundary:** Вызывающие поиск участника (экран пути и другие якоря) и пользователь поиска
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_state.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart", "lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.g.dart"]
- **Applicable constraints and non-goals:** Future `submit()` завершается связями подтверждённого добавления, в том числе после ухода из поиска, и `null` при отказе, непринятой и уже идущей команде. Поведение общего поиска для всех якорей, команда и координатор не меняются. Задача 2.31 общая с U1: её часть здесь — `relation_batch_view_model.g.dart`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | U1 и U2 не делят пути, поэтому каждому дан свой свежий изолированный рецензент `implementation-decision-review` (sonnet). Каждый получил нейтральное описание намерения, точные `9f10d9de…f3686ab1` и полный список своих путей без `openspec/`. U1 — 5 путей, U2 — 3 пути. Оба подтвердили полное покрытие. |
| OpenSpec conformance | Complete | Координатор сверил критерии и проверки задач 2.31–2.33 с диффом каждого коммита из данных процесса: 2.31 — `89e9e90b`, 2.32 — `cc4f8017`, 2.33 — `f3686ab1`. Команды запущены в этом рабочем дереве (`HEAD` = `f3686ab1`, дерево чистое). `mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --no-interactive` — valid. `mise run check` — EXIT 0: формат, анализ, 4064 обычных теста и 18 процессных тестов прошли. `mise run codegen-check` — EXIT 0, рабочее дерево после него чистое. |
| Code quality | Complete | Координатор прочитал `code-review-and-quality` и применил его линзы корректности, читаемости, архитектуры, безопасности и производительности ко всем 8 путям поставки и их непосредственным потребителям (`relation_batch_picker_page.dart`, тесты экрана пути и поиска участника). |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Целевой диапазон — 4 коммита и 10 путей. Два пути — свидетельства планирования: `task-profiles.md` (профили задач 2.31–2.33, коммит `07f058fe`) и `tasks.md` (отметки выполнения). Остальные 8 распределены по U1 и U2, и каждая задача 2.31–2.33 сопоставлена с блоком. Кода вне задач нет. Прежний отчёт (`c0a5b10d…b8c45c8b`) не содержал неустранённых находок и принятых рисков, поэтому переносить нечего.

Проверено без находок по U1. Кандидаты перенесены в `LoadingPathDraft`, `FailedPathDraft` и `LoadedPathDraft` через закрытый `NonEmptyPathDraft`, поэтому `PathState.withDraft` больше не сбрасывает их. `path_page.dart` строит переключатель загрузки и отказа без `!`. `_read` берёт числа из переданного черновика и выбирает вариант исчерпывающим `switch`, без зависимости от порядка присваиваний. `retry`, `selectHalf`, обновление после изменения графа, `selectRoot` с тем же корнем и `loadMore` сохраняют числа. `selectCandidate`, `endAt`, смена корня и укороченный графом путь передают `CandidateState.initial` без чисел. Ветви `_read` эквивалентны прежним: половина по умолчанию, `can` при пустой «Нужно», отказ, пустой участок и неожиданный успех. Запись снимка `loading` в `loadMore` не затирает более новый черновик, потому что любая смена черновика идёт через `_read` и увеличивает `_generation`. Новый тест модели проверяет числа после «Повторить» при задержанном чтении и при повторном отказе. Прежний тест не ослаблен.

Проверено без находок по U2. Метод `_finish` — единственное сопоставление результата. Связи возвращаются независимо от `ref.mounted`, публикация и `claimInitiatorFailure` по-прежнему зависят от `canPublish`, а порядок публикации до продолжения вызывающего сохранён. Потребители `RelationBatchAdded` в `relation_batch_picker_page.dart` проверяют только тип. Возврат связей после ухода из поиска покрывает существующий тест `path_page_test.dart` «связи, добавленные после ухода из поиска во время записи…».

Отклонено замечание рецензента U1 низкой важности: «`_builder` читает nullable `path.candidates`, а `FailedPathDraft` и `LoadingPathDraft` дублируют отказ и загрузку в `CandidateState`». Метод `_builder` обслуживает и `EmptyPathDraft`, у которого кандидатов нет, поэтому ветвь `null` достижима и нужна. Двойное хранение отказа было и до диапазона. Все места создания черновиков в `_read` и `build` согласованы, сценарий расхождения не найден, а критерии 2.32 этого не требуют.
