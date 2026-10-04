# OpenSpec Implementation Review: compact-intention-creation

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Incomplete
**Coverage limitations:** Полный `mise run check`, `codegen-check` и сборка APK на проверяемом коммите ещё выполняются; проход соответствия не завершён.
**Summary:** Задача 1.13 усилила сценарии отказа сквозной контрольной точки первой фазы. Свежее публичное чтение графа теперь доказывает неизменность ревизии после каждого отклонённого создания, а управляемый отказ хранилища фиксирует открытую транзакцию, порядок вставок и строки создаваемого намерения. Обе заявленные чувствительности воспроизведены искажениями кода. Остаётся одно замечание низкой важности F1: в точке отказа проверяются только вставки и наличие строк, но не всё заданное командой начальное состояние. Поэтому запись создания, отложенная на момент после места избранного, не обнаруживается, и название сценария «после всех записей» утверждает больше проверенного. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 8b66b4f8b099dae6fb9677f51cc6c922db1fe66a
- **Base commit:** 8b66b4f8b099dae6fb9677f51cc6c922db1fe66a
- **Reviewed head:** d04d534bca6cda49c8166d3e1621528531781dd1
- **Target commits:** ["83df76b0cd7e2bb0546d451f5dcb914fe76cd0eb", "d04d534bca6cda49c8166d3e1621528531781dd1"]
- **Reviewable paths:** ["docs/verification/compact-intention-creation-phase-one-readiness.md", "openspec/changes/compact-intention-creation/tasks.md", "test/app/full_intention_creation_checkpoint_test.dart"]
- **OpenSpec change:** compact-intention-creation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/compact-intention-creation/tasks.md"]

## Reviewed increment

### U1 · Сквозная контрольная точка доказывает неизменность ревизии и место отказа хранилища при отклонённом создании

- **Work items:** ["1.13"]
- **Requirements and scenarios:** ["intention-management: Создание намерения — ошибка во время сохранения исходных данных; выбранный тег удалён перед сохранением", "design: решение 6 — любой отказ до commit откатывает весь набор и не продвигает ревизию", "plan: Phase 1 — Ready to advance"]
- **Affected boundary:** Сквозная проверка приложения `AppRuntime` на файловом хранилище: координатор команд графа, публичное чтение `PersonalGraphRepository`, одновременно загруженные потребители и тестовый наблюдатель соединения, внедряющий отказ.
- **Implementation target:** ["test/app/full_intention_creation_checkpoint_test.dart", "docs/verification/compact-intention-creation-phase-one-readiness.md"]
- **Applicable constraints and non-goals:** Продуктовый код не меняется: инкремент только усиливает доказательство уже реализованного поведения. Ревизия наблюдается через публичный контракт модуля графа (ADR-0009). Тексты тестов и комментарии пишутся на русском. Смысл успешного сценария не меняется. Запись готовности утверждает только фактически проверенное.
- **Excluded change scope:** Черновик и общий выбор тегов (фаза 2), нижняя панель и реальные жесты (фаза 3).

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий субагент без истории по `implementation-decision-review`. Ему передан только нейтральный бриф и точный диапазон `8b66b4f8…d04d534b` с путём `test/app/full_intention_creation_checkpoint_test.dart`. Покрытие полное: прочитаны весь diff и файл на head, а неизменённый контекст (перехватчик соединения, путь создания и ревизия репозитория, схема) — после проверки его неизменности. Ревьюер сообщил одно замечание низкой важности, оно подтверждено и записано как F1. Запись готовности `docs/verification/…` — самоотчёт о проверках. Она исключена из цели ревьюера и проверена в проходе соответствия. |
| OpenSpec conformance | Incomplete | Выполнены на рабочей копии при `HEAD` = `d04d534b…`, без незакоммиченных изменений: `mise exec --no-deps -- flutter test test/app/full_intention_creation_checkpoint_test.dart --reporter expanded` прошёл (6 сценариев); `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive` — код 0; `git diff --check` по диапазону — код 0; diff `lib`, `android`, `pubspec.*`, `drift_schemas`, `widgetbook` между `4a6acea0…` и `d04d534b…` пуст. Полный `mise run check`, `codegen-check` и сборка APK ещё выполняются. |
| Code quality | Complete | Изменённый тестовый файл проверен через `code-review-and-quality` по корректности, читаемости, архитектуре, безопасности и производительности. Проверены: взвод и срабатывание `_CreationFaults`, разбор таблицы вставки по единственному оператору, `!connection.autocommit` на том же соединении `NativeDatabase`, параметризованные запросы `_createdRows`, `_revisions` с явным `fail` для неподтверждённого снимка, `_freshRevision` через `personalGraphRepositoryProvider`. Отдельных замечаний, кроме F1, нет. |

## Findings

### F1 · Low — Точка отказа хранилища не доказывает запись всего начального состояния

- **Evidence:** `test/app/full_intention_creation_checkpoint_test.dart:953-964` записывает в `writes` только операции `LocalDatabaseSqlOperation.insert`; UPDATE, DELETE, `custom` и `batch` не видны. `_createdRows` (`:898-920`) проверяет только наличие строки намерения по названию, набор `tag_id` и место избранного, но не содержимое строки. Проверки `:366-380` поэтому не охватывают готовность к действию, хотя она входит в начальное состояние `CreateIntention.withInitialState` и записывается в той же транзакции. Название сценария (`:89`) и заголовок задачи 1.13 утверждают отказ «после всех записей». Искажение в одноразовой копии `d04d534b…` воспроизводит пробел. В этом искажении строка вставляется с выключенной готовностью, а `UPDATE intentions SET is_action_ready = 1` выполняется после места избранного. Все 6 сценариев контрольной точки проходят, хотя отказ срабатывает до записи готовности. Тот же дефект ловят тесты репозитория `drift_intention_repository_command_test.dart` и `drift_intention_repository_fault_test.dart`.
- **Evidence revisions:** ["d04d534bca6cda49c8166d3e1621528531781dd1"]
- **Impact:** Контрольная точка — доказательство готовности первой фазы, и задача 1.13 создана, чтобы её утверждения совпадали с проверяемым. Запись создания, перенесённая за место избранного, делает отказ «после части записей» незаметным для сквозной проверки, а её название и критерий задачи остаются ложно подтверждёнными. Влияние ограничено: такую регрессию продукта сейчас ловят тесты репозитория уровнем ниже.
- **Required outcome:** В сценарии недоступности хранилища в момент отказа доказано, что неподтверждённая транзакция уже содержит всё заданное командой начальное состояние: название и описание, готовность, активность, назначение каждого выбранного тега и место избранного. Запись создания, ещё не выполненная к моменту отказа, в том числе не вставкой, приводит к падению сценария. Название, комментарии и запись готовности утверждают не больше проверенного.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/app/full_intention_creation_checkpoint_test.dart", "docs/verification/compact-intention-creation-phase-one-readiness.md", "tasks: 1.13"]

## Review coverage

Проверены оба коммита диапазона и все три пути. Тестовый файл прочитан целиком на head. Путь создания `_createIntention` сверен с проверками точки отказа: вставка намерения с готовностью, назначения в порядке набора, `_insertFavoritePlace` как последняя запись, затем только чтения проверки результата. Также проверено, что ревизия — счётчик в памяти `_DriftGraphRevision`, продвигаемый только после commit при `didMutate`, и что `getRelationCounts` возвращает её под последовательным исполнителем.

Заявленная чувствительность воспроизведена искажениями кода в одноразовой копии `d04d534b…` (не в рабочей копии). Продвижение `_mutationSequence` при отказе `CreateIntention` роняет все 4 сценария отказа: ожидалась `GraphRevisionOrder.same`, получена `newer`. Перенос места избранного перед назначениями роняет оба сценария недоступности хранилища: `['intentions', 'favorite_intentions']` вместо полного порядка. Версия теста на `8b66b4f8…` проходит при обоих искажениях, что подтверждает утверждение записи готовности. Третье искажение, перенос записи готовности за место избранного, контрольная точка не обнаруживает (F1).

Утверждения записи готовности сверены с тестом: состав `_storedGraph`, сравнение ревизий всех шести потребителей, порядок записей и обе локали. Схема, миграции, локализации, зависимости и продуктовый код в диапазоне не менялись. Внешних сервисов и новых данных изменение не затрагивает.
