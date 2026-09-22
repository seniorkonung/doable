# OpenSpec Implementation Review: manage-long-term-relations

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F1: поздний ответ подгрузки может ошибочно объявить устаревшую сводку актуальной. F2: обновление снимка того же участника ошибочно снимает ошибку занятой или совпадающей пары.

## Review target

- **Baseline ref:** 755b3f97cc5a7377cf4a3b1d81c03d7c36ad429a
- **Base commit:** 755b3f97cc5a7377cf4a3b1d81c03d7c36ad429a
- **Reviewed head:** 6683ec26221d45632656460331ccfae83e73a608
- **Target commits:** ["e6b7ff266ea8f2242f027a3cc4a2fc43ada105f2","f2da4c1aa739300cc2801f13de50c4cd4c5a6937","4f749b0bad3991ad518352e484a2501f8669eb5e","6683ec26221d45632656460331ccfae83e73a608"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/graph/presentation/operation_failure_presentation.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/intention/presentation/details/intention_details_state.dart","lib/src/intention/presentation/details/intention_details_view_model.dart","lib/src/intention/presentation/details/intention_details_view_model.g.dart","lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","lib/src/long_term_relation/presentation/editor/relation_editor_state.dart","lib/src/long_term_relation/presentation/editor/relation_editor_view_model.dart","lib/src/long_term_relation/presentation/editor/relation_editor_view_model.g.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart","lib/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart","openspec/changes/manage-long-term-relations/tasks.md","test/app/intention_app_lifecycle_test.dart","test/app/routing/app_router_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/operation_failure_presentation_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/intention/presentation/details/intention_details_view_model_test.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_editor_page_test.dart","test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart","test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart"]
- **OpenSpec change:** manage-long-term-relations
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-long-term-relations/tasks.md"]

## Reviewed increment

### U1 · Атомарная публикация подробностей намерения после каскада

- **Work items:** ["57 / 3.32 / e6b7ff266ea8f2242f027a3cc4a2fc43ada105f2"]
- **Requirements and scenarios:** ["intention-management / Requirement: Архивирование намерения / Scenario: Архивирование активного намерения","intention-management / Requirement: Целостность при ошибках записи / Scenario: Ошибка в середине каскадного архивирования","intention-management / Requirement: Счётчики групп на странице намерения","long-term-relation-management / Requirement: Согласованность счётчиков с изменениями графа / Scenario: Запоздалое чтение не отменяет подтверждённое число"]
- **Affected boundary:** Представление подробностей намерения, coordinator изменяющих команд и наблюдение ревизий личного графа.
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_state.dart","lib/src/intention/presentation/details/intention_details_view_model.dart","test/app/intention_app_lifecycle_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/intention/presentation/details/intention_details_view_model_test.dart"]
- **Applicable constraints and non-goals:** Подробности публикуются только целостным снимком одной ревизии; завершение команды проходит через ревизионный барьер и повторное наблюдение; прежний целостный снимок сохраняется до согласованной замены; каскад и предъявление результата команды не дублируются. Изменение доменной семантики каскада не входит в инкремент.

### U2 · Доступная индикация актуальности полной сводки связей

- **Work items:** ["58 / 3.33 / f2da4c1aa739300cc2801f13de50c4cd4c5a6937"]
- **Requirements and scenarios:** ["intention-management / Requirement: Счётчики групп на странице намерения / Scenario: Неизвестные количества не выглядят нулевыми","long-term-relation-management / Requirement: Согласованность счётчиков с изменениями графа","long-term-relation-management / Requirement: Состояния получения данных и безопасные ошибки / Scenario: Ошибка обновления сохраняет прежнюю загруженную часть","long-term-relation-management / Requirement: Доступность управления связями"]
- **Affected boundary:** Сводка восьми групп в непосредственном соседстве намерения, её локализованное и семантическое представление.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart"]
- **Applicable constraints and non-goals:** Пользователь различает обновляемую и устаревшую сохранённую сводку рядом с числами, в RU/EN и через semantics; только согласованная замена первой порции подтверждает актуальность. Подгрузка продолжения не должна менять актуальность сводки и не должна материализовать остальные группы.

### U3 · Устойчивая идентичность участников формы связи

- **Work items:** ["59 / 3.34 / 4f749b0bad3991ad518352e484a2501f8669eb5e"]
- **Requirements and scenarios:** ["long-term-relation-management / Requirement: Базовая навигация и выбор участников / Scenario: Выбор среди одноимённых намерений","long-term-relation-management / Requirement: Базовая навигация и выбор участников / Scenario: Ошибка сохраняет проверяемую идентичность выбранных участников","long-term-relation-management / Requirement: Локализация и формулировки связей / Scenario: Смена языка сохраняет пользовательский текст","long-term-relation-management / Requirement: Доступность управления связями / Scenario: Увеличенный текст не скрывает подтверждение"]
- **Affected boundary:** Форма создания связи, выбор и отображение двух участников, маршрутизация к подробностям и формирование команды.
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart","lib/src/intention/presentation/details/intention_details_view_model.g.dart","lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","lib/src/long_term_relation/presentation/editor/relation_editor_state.dart","lib/src/long_term_relation/presentation/editor/relation_editor_view_model.dart","lib/src/long_term_relation/presentation/editor/relation_editor_view_model.g.dart","lib/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart","test/app/routing/app_router_test.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_editor_page_test.dart","test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart"]
- **Applicable constraints and non-goals:** Участник представлен типизированным ID и снимком отображения; роли различаются, команда и навигация используют тот же ID, а ошибка сохраняет проверяемую пару. Переименование, архивирование или удаление после выбора не должно молча подменять участника; редактирование существующей связи не входит в инкремент.

### U4 · Стабильное владение локализованным сообщением результата

- **Work items:** ["60 / 3.35 / 6683ec26221d45632656460331ccfae83e73a608"]
- **Requirements and scenarios:** ["long-term-relation-management / Requirement: Подтверждённые результаты и незавершённые операции","intention-management / Requirement: Независимость принятой изменяющей операции от экрана"]
- **Affected boundary:** Предъявление терминального результата команды формой связи при смене локали и жизненного цикла renderer.
- **Implementation target:** ["lib/src/graph/presentation/operation_failure_presentation.dart","test/graph/presentation/operation_failure_presentation_test.dart","test/long_term_relation/presentation/editor/relation_editor_page_test.dart"]
- **Applicable constraints and non-goals:** Изменение текста при прежних claim, renderer и сессии не меняет владельца; смена владельческой идентичности освобождает claim; результат и согласование предъявляются ровно один раз, а запоздалые callbacks безвредны. Переработка общего протокола команд не входит в инкремент.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Три свежих изолированных reviewer без planning/history/report проверили на `6683ec26221d45632656460331ccfae83e73a608` U1, U2 и overlap-группу U3/U4. Вместе они охватили все delivery/test paths, все четыре task-коммита и границы snapshot/revision, freshness/paging, participant identity/error correction и presentation ownership. U1 и U4 не дали замечаний; U2 и U3 дали F1 и F2. |
| OpenSpec conformance | Complete | Proposal, design, delta-спецификации и задачи 3.32–3.35 сопоставлены с неизменяемым снимком `6683ec26221d45632656460331ccfae83e73a608`. `mise exec --no-deps -- openspec status --change manage-long-term-relations --json`, `mise exec --no-deps -- openspec instructions apply --change manage-long-term-relations --json` и `mise exec --no-deps -- openspec validate manage-long-term-relations --strict --no-interactive --json` подтвердили schema `intent-driven`, 60/60 отмеченных задач и валидный change. Отмеченные F1 и F2 показывают расхождение фактического поведения с критериями уже завершённых задач, поэтому состояние задач не изменялось. |
| Code quality | Complete | Проверены корректность, читаемость, архитектура, безопасность и производительность всех 30 delivery/test paths диапазона: ревизионные барьеры, неизменяемые состояния, paging races, локализация/semantics, типизированные ID, коррекция ошибок и владение claim. Dart MCP analysis не нашёл ошибок; task-focused `flutter test` выполнил 165 тестов; `mise run codegen-check`, `mise run check` (format без изменений, analyze без замечаний, 693 теста) и `git diff --check 755b3f97cc5a7377cf4a3b1d81c03d7c36ad429a 6683ec26221d45632656460331ccfae83e73a608` прошли. Запущенного DTD-сеанса не было, поэтому runtime hot reload не выполнялся. |

## Findings

### F1 · Medium — Поздняя подгрузка ошибочно снимает признак устаревшей сводки

- **Evidence:** В `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart:134-141` актуальность сводки полностью выводится из единственного `RelationGroupProgress`: только `RelationGroupRefreshFailure` означает `stale`, а `Idle`, `LoadingMore` и `LoadMoreFailure` означают `current`. Подгрузка, начатая в `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart:270-310`, остаётся активной, когда ошибка наблюдения переводит текущий подтверждённый state в `RelationGroupRefreshFailure` на строках 546-579. Поздний успех подгрузки создаёт `RelationGroupLoaded` с progress по умолчанию на строках 481-514, а поздний отказ устанавливает `RelationGroupLoadMoreFailure`; оба результата объявляют прежние counts/revision актуальными без успешной согласованной замены первой порции. Изменённые тесты проверяют refresh failure и load-more по отдельности, но не их пересечение.
- **Evidence revisions:** ["6683ec26221d45632656460331ccfae83e73a608"]
- **Impact:** После ошибки обновления пользователь может увидеть сохранённые числа без обязательной пометки об устаревании; это нарушает критерий 3.33, по которому признак снимается только согласованной заменой.
- **Required outcome:** Ответ продолжения, включая запоздалый успех или отказ, не должен снимать или подменять состояние устаревшей сводки; актуальность подтверждает только успешная согласованная замена первой порции.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart"]

### F2 · Medium — Обновление снимка того же участника ошибочно считается исправлением пары

- **Evidence:** `lib/src/long_term_relation/presentation/editor/relation_editor_view_model.dart:44-55` вызывает `withParticipant`, если у прежнего ID изменились title, archive state или count. `lib/src/long_term_relation/presentation/editor/relation_editor_state.dart:278-295` при любом таком повторном выборе применяет коррекцию ошибки, а строки 380-390 снимают `RelationEditorPairOccupied` и `RelationEditorSameParticipants` для любого выбора участника. При этом полнота черновика и команда используют только прежние ID (`relation_editor_state.dart:242-264`, `relation_editor_view_model.dart:110-118`), а picker исключает лишь другого участника и допускает повторный выбор того же ID (`relation_editor_page.dart:179-205`). Поэтому переименование или иной новый снимок того же намерения скрывает конфликт и разрешает повторно отправить неизменённую пару ID. Изменённые тесты не покрывают повторный выбор того же ID после pair-dependent failure.
- **Evidence revisions:** ["6683ec26221d45632656460331ccfae83e73a608"]
- **Impact:** После `PairOccupied` или `SameParticipants` форма может показать конфликт как исправленный и повторно отправить заведомо ту же недопустимую пару; подробности прежней ошибки также исчезают без изменения её причины.
- **Required outcome:** Обновление отображаемого снимка участника с тем же ID не должно считаться исправлением ошибки, зависящей от пары; такая ошибка снимается только при фактическом изменении соответствующего ID либо при подтверждённом исчезновении конфликта.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","lib/src/long_term_relation/presentation/editor/relation_editor_state.dart","lib/src/long_term_relation/presentation/editor/relation_editor_view_model.dart","test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart"]

## Review coverage

Проверен точный диапазон `755b3f97cc5a7377cf4a3b1d81c03d7c36ad429a..6683ec26221d45632656460331ccfae83e73a608`: четыре target-коммита и задачи 3.32–3.35 сопоставлены соответственно с U1–U4. Все 31 reviewable path учтены: `tasks.md` служит planning evidence, остальные 30 входят в implementation target хотя бы одного review unit; unmapped paths нет. Отдельно исследованы гонки команд, наблюдений, первой порции и continuation; сохранение целостных snapshot; RU/EN и semantics при масштабе текста; идентичность одноимённых участников и переходы ошибок; смена локали, renderer и сессии для presentation claim. Существующий отчёт прочитан только после независимых проходов: активных findings и принятых residual risks для переноса в нём не было; прежний review target заменён текущим неизменяемым диапазоном.
