# OpenSpec Implementation Review: manage-daily-choices

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задача 94 / 4.20 реализует отбор только допустимых прежних маршрутов в обоих направлениях и при замене; предметные тесты и OpenSpec-валидация прошли. F4: после уточнения типа выдачи `flutter analyze` завершается с двумя предупреждениями в тестах. Сохраняются ранее принятые AR1 и AR2; они не относятся к этому коммиту.

## Review target

- **Baseline ref:** efc654279e5867897ca49b401919c54a3012e8d3
- **Base commit:** efc654279e5867897ca49b401919c54a3012e8d3
- **Reviewed head:** 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8
- **Target commits:** ["0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8"]
- **Reviewable paths:** ["lib/src/daily_choice/application/choice_path_suggestions.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_state.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_view.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart", "lib/src/graph/data/drift_personal_graph_repository_choice_path_suggestions.dart", "openspec/changes/manage-daily-choices/evidence/4.18.md", "openspec/changes/manage-daily-choices/tasks.md", "test/daily_choice/application/choice_path_suggestions_test.dart", "test/daily_choice/presentation/path/choice_path_suggestions_view_model_test.dart", "test/daily_choice/presentation/path/choice_path_suggestions_view_test.dart", "test/graph/data/drift_choice_path_suggestions_test.dart", "test/graph/data/drift_daily_choice_read_cost_test.dart"]
- **OpenSpec change:** manage-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-daily-choices/evidence/4.18.md", "openspec/changes/manage-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Только допустимые прежние маршруты в подсказках

- **Work items:** ["94 / 4.20"]
- **Requirements and scenarios:** ["daily-choice-management: Повтор прежнего маршрута / Недоступные маршруты не вытесняют пригодный; Все прежние маршруты недоступны; Подсказка устарела перед сохранением", "daily-choice-management: Атомарная замена участников и пути", "design.md: раздел 7 / отбор подсказок"]
- **Affected boundary:** Пользователь создания или замены дневного выбора в обоих направлениях; прикладной снимок, чтение локального графа и экран подсказок.
- **Implementation target:** ["lib/src/daily_choice/application/choice_path_suggestions.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_state.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_view.dart", "lib/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart", "lib/src/graph/data/drift_personal_graph_repository_choice_path_suggestions.dart", "test/daily_choice/application/choice_path_suggestions_test.dart", "test/daily_choice/presentation/path/choice_path_suggestions_view_model_test.dart", "test/daily_choice/presentation/path/choice_path_suggestions_view_test.dart", "test/graph/data/drift_choice_path_suggestions_test.dart", "test/graph/data/drift_daily_choice_read_cost_test.dart"]
- **Applicable constraints and non-goals:** Проверяются все последние 20 выборов участника, до пяти различных допустимых путей показываются по новизне; недоступные пути не занимают места, повреждение любого прочитанного кандидата прерывает чтение. Исторический выбор не меняется; 21-й и более старые выборы не читаются для добора, а подтверждение повторно проверяет текущий путь.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент прочитал все десять назначенных путей из 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8 и их diff от efc654279e5867897ca49b401919c54a3012e8d3. Он отметил случай 21-го доступного маршрута; пункт не сохранён как дефект: `design.md:170–172,233` и `tasks.md:931–934` ограничивают подсказки последними 20 выборами, спецификация говорит о рассмотренных выборах, а более старый путь остаётся доступен через каталог и пошаговый обход. |
| OpenSpec conformance | Complete | На чистом checkout с HEAD 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8 прошли `mise exec --no-deps -- openspec validate manage-daily-choices --json`, `mise exec --no-deps -- openspec validate manage-daily-choices --strict --no-interactive`, заданный задачей Flutter-набор подсказок и стоимости (69 тестов), а также сквозные тесты создания и замены (14 тестов). Проверены оба направления, пять недоступных перед допустимым, пустая выдача, предел 20, повтор, повреждение и конфликт подтверждения. |
| Code quality | Complete | Проверены типы снимка, фильтрация и дедупликация после валидации всех кандидатов, наблюдение скрытых путей, состояние экрана, SQL-стоимость, безопасность отказа и тесты. `mise exec --no-deps -- flutter analyze` на 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8 завершился с кодом 1: два `unnecessary_cast`; это F4. |

## Findings

### F4 · Low — анализатор отклоняет два лишних приведения в тестах

- **Evidence:** На 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8 `mise exec --no-deps -- flutter analyze` завершился с кодом 1 и предупредил `unnecessary_cast` в `test/graph/data/drift_choice_path_suggestions_test.dart:310` и `test/graph/data/drift_daily_choice_read_cost_test.dart:587`. Коммит сделал `ChoicePathSuggestionsSnapshot.items` списком `AvailableChoicePathSuggestion` (`lib/src/daily_choice/application/choice_path_suggestions.dart:199`), поэтому прежние приведения в обоих тестах больше не нужны. На базовом коммите элементы имели общий тип `ChoicePathSuggestion`.
- **Evidence revisions:** ["efc654279e5867897ca49b401919c54a3012e8d3", "0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8"]
- **Impact:** Стандартная проверка `flutter analyze` не проходит; статическая проверка ветки остаётся красной, несмотря на успешные поведенческие тесты.
- **Required outcome:** Анализатор должен завершаться с кодом 0 после согласования тестов с точным типом выдачи.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/graph/data/drift_choice_path_suggestions_test.dart", "test/graph/data/drift_daily_choice_read_cost_test.dart"]

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

Единственный целевой коммит 0baf481a8eea8e1f1d04ac7dea899d82cb74cbe8 целиком отнесён к U1 и задаче 94 / 4.20. Все 12 путей диапазона учтены: десять путей реализации и тестов входят в U1, `tasks.md` и `evidence/4.18.md` служат плановым и измерительным свидетельством; непокрытых и посторонних путей нет. Снимок в рабочем дереве был чистым и совпадал с reviewed head. Проверены сценарии требований и граница в 20 кандидатов; позднее изменение проверяется атомарной командой. AR1 и AR2 перенесены из предыдущего отчёта без повторной оценки, поскольку выбор исходного намерения и действия не менялся в этом диапазоне. Повторный экранный диктор и устройство не проверялись; доступность оценена по коду и widget-тестам.
