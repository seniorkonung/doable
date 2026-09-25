# OpenSpec Implementation Review: manage-daily-choices

## Assessment

**Format version:** 1
**Result:** Incomplete
**Coverage status:** Incomplete
**Coverage limitations:** По просьбе пользователя повторная независимая оценка решений реализации не проводилась; текущий диапазон меняет только тесты и отметку задачи.
**Summary:** Задача 95 / 4.21 удаляет два лишних приведения типов в тестах. Статический анализ, 18 предметных тестов и проверка OpenSpec прошли. Новых подтверждённых замечаний нет; ранее принятые риски AR1 и AR2 сохраняются вне текущего диапазона.

## Review target

- **Baseline ref:** f8c92a13aa1c526bb6db869bf582ebcd574d7ce6
- **Base commit:** f8c92a13aa1c526bb6db869bf582ebcd574d7ce6
- **Reviewed head:** 7979bcb0a4a70abc320997dff8f3458984ff939b
- **Target commits:** ["7979bcb0a4a70abc320997dff8f3458984ff939b"]
- **Reviewable paths:** ["openspec/changes/manage-daily-choices/tasks.md", "test/graph/data/drift_choice_path_suggestions_test.dart", "test/graph/data/drift_daily_choice_read_cost_test.dart"]
- **OpenSpec change:** manage-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Восстановление статического анализа тестов подсказок

- **Work items:** ["95 / 4.21"]
- **Requirements and scenarios:** ["tasks.md: 4.21 / статический анализ и сохранение проверок подсказок"]
- **Affected boundary:** Статический анализ и тесты чтения подсказок и стоимости чтения локального графа.
- **Implementation target:** ["test/graph/data/drift_choice_path_suggestions_test.dart", "test/graph/data/drift_daily_choice_read_cost_test.dart"]
- **Applicable constraints and non-goals:** Удалены только два избыточных приведения к `AvailableChoicePathSuggestion`; проверки подтверждённого пути сохранены, поведение приложения не меняется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Incomplete | Повторная независимая оценка по просьбе пользователя пропущена; целевой коммит не меняет код приложения или решения реализации. |
| OpenSpec conformance | Complete | На чистом рабочем дереве с HEAD 7979bcb0a4a70abc320997dff8f3458984ff939b прошли `mise exec --no-deps -- openspec validate manage-daily-choices --strict --no-interactive`, `mise exec --no-deps -- flutter analyze` и указанный в задаче 4.21 запуск двух тестовых файлов (18 тестов). |
| Code quality | Complete | Разница f8c92a13aa1c526bb6db869bf582ebcd574d7ce6..7979bcb0a4a70abc320997dff8f3458984ff939b содержит только два удаления лишних приведений и отметку задачи. Обращения к `confirmedPath` и проверки ожидаемых значений сохранены. |

## Findings

No findings confirmed; review incomplete.

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
- **Current target relation:** Carried forward; not re-reviewed

### AR2 · Основания с полностью совпадающими видимыми сведениями неразличимы до выбора

- **Evidence:** На 01e4bfa1393c124832523e4dbce2617d4441722a `lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart:177–212` показывает название, готовность, наличие описания и количество связей, возвращая скрытый `IntentionId`; неизменённые `lib/src/intention/presentation/details/intention_details_page.dart:271–296` показывают те же пользовательские поля без гарантированно различающего признака. Тест `test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart:42–77` различает одноимённые записи разной готовностью и наличием описания, но не полные совпадения. Домен допускает отдельные намерения с одинаковыми отображаемыми данными.
- **Evidence revisions:** ["01e4bfa1393c124832523e4dbce2617d4441722a"]
- **Potential impact:** При полностью совпадающих сведениях пользователь может выбрать другое исходное намерение; новый путь привяжется к идентификатору выбранной строки без доступной возможности понять это до выбора.
- **Acceptance rationale:** Пользователь считает полное совпадение видимых сведений исключительным случаем, который не оправдывает дополнительный признак в интерфейсе выбора основания. Постоянный уникальный код добавил бы технические сведения в список и подробности; пользовательская метка потребовала бы изменения модели и хранения данных. Риск сохраняется и не считается исправленным.
- **Scope and assumptions:** Только экран выбора нового активного исходного намерения при замене пути в текущей реализации изменения `manage-daily-choices`, когда все доступные в списке и подробностях сведения двух намерений совпадают. Записи остаются отдельными по `IntentionId`, а выбор конкретной строки возвращает именно её ID. Принятие не распространяется на ошибочную привязку ID или иные проблемы доступности; AR1 отдельно ограничен выбором действия.
- **Reopen when:** Подтверждён ошибочный выбор из таких совпадающих намерений; меняется экран выбора основания или подробности так, что предположение о доступности их текущих сведений перестаёт действовать; либо пользователь запрашивает гарантированное различение оснований до выбора.
- **Acceptance authority:** Явное решение пользователя в текущем диалоге 2026-09-25: «этот случай не стоит рассматривать, потому что пользователь сам не должен себя загонять в такую ситуацию».
- **Originating finding:** F3
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

Единственный целевой коммит 7979bcb0a4a70abc320997dff8f3458984ff939b отнесён к U1 и задаче 95 / 4.21. Оба изменённых тестовых файла входят в U1; `tasks.md` содержит отметку выполнения и служит плановым свидетельством. Других путей в диапазоне нет. Перед проверками рабочее дерево было чистым, а HEAD совпадал с reviewed head. Прежние риски AR1 и AR2 перенесены без переоценки: выбор действия и основания в этом коммите не менялся. Независимая повторная оценка реализации сознательно не проводилась по просьбе пользователя.
