# OpenSpec Implementation Review: manage-daily-choices

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Открытых находок нет. AR1: пользователь явно принял остаточный риск неразличимости двух действий с полностью совпадающими видимыми сведениями до выбора; условие не исправлено. Остальные проверенные обязательства фазы 3 имеют реализацию и проверочные свидетельства.

## Review target

- **Baseline ref:** 5b6210ece0dfc2920cdf1ea9109250b5333af71b
- **Base commit:** 5b6210ece0dfc2920cdf1ea9109250b5333af71b
- **Reviewed head:** 6c9cebe5274ba262b6deec6f9cee54e69d42af1a
- **Target commits:** ["21093700810aa7a84a6756b598125d0ef768ed4c", "e82a710a7ac9c5ec847e81a032aca331325c4199", "fca760eaf363733a921f602aeaa668121e95e071", "1d845219888f583e8e93aaebfdb8f5128adf3d95", "efd61f56a5e090fe9e811571981a9d4e693bc73d", "01c2e865feae49963bbfcf34ee3909e5d4ada206", "6214fff7971026ccb643177e9cb8377c136187c9", "f4e7bf8042e2375b7fff99d02f4aba8f0ebbff22", "16d94279409c81abe3f6e7b615fb1a90177ad240", "72398a762f026a951d67c02683f36ed8d523dbe7", "a43b7024178b622fa6d2d8eae862f7d4effe92be", "a393ee3becc43395d5b62adea7fa6740abcdb734", "a1d5e420ac5c0cf1d249662101ca7a4461a87835", "206641f5529fce584d575159e01b98f61deab6a8", "89592c9d8b4fd0f76a424cb3689cc95ebcf43a44", "6c9cebe5274ba262b6deec6f9cee54e69d42af1a"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/daily_choice/application/choice_path_continuations.dart", "lib/src/daily_choice/application/choice_path_draft.dart", "lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/editor/daily_choice_creation_page.dart", "lib/src/daily_choice/presentation/path/choice_path_page.dart", "lib/src/daily_choice/presentation/path/choice_path_state.dart", "lib/src/daily_choice/presentation/path/choice_path_view_model.dart", "lib/src/daily_choice/presentation/path/choice_path_view_model.g.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_choice_path_reads.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_purpose.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "openspec/changes/manage-daily-choices/measurements-3.15.md", "openspec/changes/manage-daily-choices/tasks.md", "openspec/changes/manage-daily-choices/verification-3.16.md", "test/app/daily_choice_app_flow_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/daily_choice/application/choice_path_continuations_test.dart", "test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_flow_test.dart", "test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart", "test/daily_choice/presentation/path/choice_path_page_test.dart", "test/daily_choice/presentation/path/choice_path_view_model_test.dart", "test/graph/data/drift_choice_path_continuations_test.dart", "test/graph/data/drift_daily_choice_concurrency_test.dart", "test/graph/data/drift_daily_choice_diagnostics_test.dart", "test/graph/data/file_backed_daily_choice_durability_test.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_action_selection_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/daily_choice_durability_fixture.dart", "test/support/graph_operation_process_worker.dart"]
- **OpenSpec change:** manage-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-daily-choices/measurements-3.15.md", "openspec/changes/manage-daily-choices/tasks.md", "openspec/changes/manage-daily-choices/verification-3.16.md"]

## Reviewed increment

### U1 · Контракт и чтение входящих продолжений

- **Work items:** ["59 / 3.1", "60 / 3.2", "61 / 3.3"]
- **Requirements and scenarios:** ["daily-choice-management: Допустимость и целостность пути выбора", "daily-choice-management: Пошаговый выбор снизу вверх", "daily-choice-management: Пошаговый выбор сверху вниз — сохранение прежнего контракта"]
- **Affected boundary:** Модель черновика и локальный репозиторий графа; один снимок для проверки суффикса и выдачи порции.
- **Implementation target:** ["lib/src/daily_choice/application/choice_path_continuations.dart", "lib/src/daily_choice/application/choice_path_draft.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_choice_path_reads.dart", "test/daily_choice/application/choice_path_continuations_test.dart", "test/graph/data/drift_choice_path_continuations_test.dart"]
- **Applicable constraints and non-goals:** Фиксированное действие активно и готово; основание может быть неготовым. Непустой простой путь сохраняется от основания к действию; верхний проход остаётся совместимым.

### U2 · Ограниченный выбор действия

- **Work items:** ["62 / 3.4", "63 / 3.5", "64 / 3.6", "65 / 3.7"]
- **Requirements and scenarios:** ["daily-choice-management: Пошаговый выбор снизу вверх / Вход без готовности недоступен", "intention-management: Явная классификация действия"]
- **Affected boundary:** Каталог намерений, SQL-фильтрация, пикер и навигация пользователя.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_purpose.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/presentation/catalog/intention_catalog_action_selection_test.dart", "test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart"]
- **Applicable constraints and non-goals:** Выбираются только активные готовые действия; порция ограничена, фильтр буквальный. Обычный каталог и выбор участника связи сохраняют прежнее поведение; общий поиск графа не входит в фазу.

### U3 · Обход, возврат и подтверждение основания

- **Work items:** ["66 / 3.8", "67 / 3.9", "68 / 3.10"]
- **Requirements and scenarios:** ["daily-choice-management: Пошаговый выбор снизу вверх / Многошаговый обход против направления связей", "daily-choice-management: Пошаговый выбор снизу вверх / Одного основания достаточно", "daily-choice-management: Пошаговый выбор снизу вверх / Возврат меняет основание без смены действия", "daily-choice-management: Локализация и доступность дневного выбора"]
- **Affected boundary:** Состояние экранной сессии и экран пути для обоих направлений.
- **Implementation target:** ["lib/src/daily_choice/presentation/path/choice_path_state.dart", "lib/src/daily_choice/presentation/path/choice_path_view_model.dart", "lib/src/daily_choice/presentation/path/choice_path_view_model.g.dart", "lib/src/daily_choice/presentation/path/choice_path_page.dart", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "test/daily_choice/presentation/path/choice_path_page_test.dart", "test/daily_choice/presentation/path/choice_path_view_model_test.dart"]
- **Applicable constraints and non-goals:** После первого перехода подтверждение основания явно; возврат отбрасывает только более позднюю часть, не меняя действие. Поздние ответы не возвращают старую ветвь.

### U4 · Создание и общий жизненный цикл

- **Work items:** ["69 / 3.11", "70 / 3.12", "71 / 3.13", "72 / 3.14"]
- **Requirements and scenarios:** ["daily-choice-management: Пошаговый выбор снизу вверх / Многошаговый обход против направления связей", "daily-choice-management: Подтверждённые результаты и безопасные ошибки / Конфликт пути сохраняет независимые поля создания", "daily-choice-management: Локальная долговечность и проверка целостности дневных выборов", "daily-choice-management: Календарная дата и независимое выполнение"]
- **Affected boundary:** Дневной каталог, общая форма создания, команда графа и файловое хранилище.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/editor/daily_choice_creation_page.dart", "lib/src/daily_choice/presentation/path/choice_path_page.dart", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_flow_test.dart", "test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart", "test/app/daily_choice_app_flow_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/graph/data/drift_daily_choice_concurrency_test.dart", "test/graph/data/file_backed_daily_choice_durability_test.dart", "test/support/daily_choice_durability_fixture.dart", "test/support/graph_operation_process_worker.dart"]
- **Applicable constraints and non-goals:** Путь подтверждается пользователем и сохраняется атомарно; дата, описание и выполнение независимы от обновления конфликтного пути. Повтор и замена сохранённого пути относятся к фазе 4.

### U5 · Стоимость, диагностика и готовность фазы

- **Work items:** ["73 / 3.15", "74 / 3.16"]
- **Requirements and scenarios:** ["daily-choice-management: Диагностика без пользовательского содержимого", "plan.md: Phase 3 / Ready to advance"]
- **Affected boundary:** Локальная диагностика, измерения запросов и проверка результата фазы.
- **Implementation target:** ["lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/graph/data/drift_daily_choice_diagnostics_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/graph/data/drift_choice_path_continuations_test.dart", "test/intention/data/drift_intention_catalog_test.dart"]
- **Applicable constraints and non-goals:** События не содержат пользовательские тексты, идентификаторы, путь или SQL; сбой диагностики не меняет предметный результат. Порция ограничивает выдачу, но не гарантирует постоянную стоимость поиска.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент проверил все 44 delivery/test paths как одну перекрывающуюся группу на точном диапазоне base..head. Его оценка выявила условие, принятое как AR1; изменения вне списка не включались. |
| OpenSpec conformance | Complete | Задачи 3.1–3.16 сопоставлены с пятью единицами, зафиксированными требованиями и сценариями. На чистом HEAD reviewed head прошли `mise run --skip-tools check` (форматирование без изменений, CI scope, `flutter analyze`, 1393 теста), `mise run --skip-tools codegen-check` (0 outputs, чистое дерево), `mise exec --no-deps -- openspec validate manage-daily-choices --json` и `mise exec --no-deps -- openspec validate manage-daily-choices --strict --no-interactive`. Несоответствие различения одноимённых действий остаётся как явно принятый AR1. |
| Code quality | Complete | Проверены корректность переходов и ревизий, доступность пикера и пути, границы модели/репозитория, SQL-фильтрация и ограничение порций, приватность диагностики, долговечность и регрессии; `git diff --check` прошёл. AR1 относится к пользовательской корректности и доступности. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Действия с полностью совпадающими видимыми сведениями неразличимы до выбора

- **Evidence:** На зафиксированном head `lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart:176–207` строка показывает название, признак наличия описания и число активных связей; ID используется только как ключ и результат выбора. Неизменённые `lib/src/intention/presentation/intention_summary_view.dart:86–105` и `lib/src/intention/presentation/details/intention_details_page.dart:271–296` не предъявляют гарантированно различающий признак. Два активных готовых действия с одинаковым названием, описанием и одинаково подписанным соседством остаются визуально и семантически неразличимыми, хотя имеют разные ID. Тест `test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart:42–58` различает свой дубль только разным `hasDescription`.
- **Evidence revisions:** ["6c9cebe5274ba262b6deec6f9cee54e69d42af1a"]
- **Potential impact:** Пользователь может выбрать не то действие среди одинаково показанных записей; последующий путь и дневной выбор будут привязаны к идентификатору выбранной строки без доступного признака, позволяющего заранее определить нужную запись.
- **Acceptance rationale:** Пользователь после сравнения вариантов явно выбрал сохранить этот крайний случай без исправления. Постоянный различающий признак изменил бы экран и его семантику; отдельное имя потребовало бы расширить модель и хранение данных. Принятие риска не доказывает соответствие интерфейса требованию различения.
- **Scope and assumptions:** Только выбор активного готового действия снизу вверх в текущей реализации изменения `manage-daily-choices`, когда название и все доступные в списке и подробностях сведения двух намерений совпадают. Записи остаются отдельными по `IntentionId`, а выбор конкретной строки сохраняет именно её ID. Принятие не распространяется на ошибочную привязку ID или иные проблемы доступности.
- **Reopen when:** Подтверждён случай ошибочного выбора из таких совпадающих записей; меняется экран выбора или подробности так, что предположение о доступности их текущих сведений перестаёт действовать; либо пользователь запрашивает гарантированное различение таких действий до выбора.
- **Acceptance authority:** Явное решение пользователя в текущем диалоге 2026-09-24: «Принять остаточный риск».
- **Originating finding:** F1
- **Acceptance lifetime:** Change-scoped

## Review coverage

Все 16 целевых коммитов рассмотрены в заданном порядке: U1 — 3.1–3.3 (коммиты 1–3), U2 — 3.4–3.7 (4–7), U3 — 3.8–3.10 (8–10), U4 — 3.11–3.14 (11–14), U5 — 3.15–3.16 (15–16). Каждый из 44 путей реализации и тестов включён хотя бы в одну единицу; общие файлы локализации, экрана пути и измерительных тестов включены в связанные единицы. Три оставшихся reviewable paths — `tasks.md`, `measurements-3.15.md` и `verification-3.16.md` — использованы как плановые и проверочные свидетельства. Непокрытых или посторонних путей нет. Проверки выполнены на чистом рабочем дереве с HEAD 6c9cebe5274ba262b6deec6f9cee54e69d42af1a; после генерации дерево осталось чистым. Предыдущий документ `verification-3.16.md` сообщает также об успешной release-сборке APK; повторная сборка в этом обзоре не выполнялась. Физический экранный диктор не проверялся, доступность оценивалась по коду и автоматическим widget-тестам. Принятый AR1 относится только к указанному сценарию и не означает, что условие устранено.
