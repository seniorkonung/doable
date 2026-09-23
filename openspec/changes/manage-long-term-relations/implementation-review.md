# OpenSpec Implementation Review: manage-long-term-relations

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Incomplete
**Coverage limitations:** Независимый просмотр инженерного решения в свежем изолированном контексте не выполнен: условия этапа запрещают запуск агентов. Остальные проходы и проектные проверки завершены.
**Summary:** Установлено замечание F3: committed Riverpod-файл не воспроизводится из исходника и `codegen-check` завершается ошибкой. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** b10a7898ea90c9e731cdbe8f150d1880750b8ee3
- **Base commit:** b10a7898ea90c9e731cdbe8f150d1880750b8ee3
- **Reviewed head:** 687f9c29dae7346a9832d1e1ea1a3bc44cac7c60
- **Target commits:** ["2854bd01df3d98546255f31abf4408ce1deb46d7","e9d10c29e5083d8cceacdd4c7450366faa432cb9","687f9c29dae7346a9832d1e1ea1a3bc44cac7c60"]
- **Reviewable paths:** ["lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/application/selected_relations.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_relation_groups.dart","lib/src/graph/data/drift_personal_graph_repository_selected_relations.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","openspec/changes/manage-long-term-relations/tasks.md","openspec/changes/manage-long-term-relations/verification-6.21.md","test/app/bootstrap/app_runtime_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/long_term_relation_app_flow_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_relation_group_large_fixture_test.dart","test/graph/data/drift_selected_relations_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/intention/application/intention_contract_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart","test/shared/diagnostics/diagnostics_sink_test.dart"]
- **OpenSpec change:** manage-long-term-relations
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-long-term-relations/tasks.md","openspec/changes/manage-long-term-relations/verification-6.21.md"]

## Reviewed increment

### U1 · Новый выбор после частичного удаления

- **Work items:** ["106 / 6.19 / 2854bd01df3d98546255f31abf4408ce1deb46d7"]
- **Requirements and scenarios:** ["intention-management / Requirement: Целевое массовое удаление блокирующих связей","intention-management / Scenario: Новый выбор после частичного удаления на той же странице","intention-management / Scenario: Подтверждённое удаление набора связей"]
- **Affected boundary:** Открытая страница намерения, выбор связей в соседстве и повторное подтверждение.
- **Implementation target:** ["lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart","lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart","test/app/long_term_relation_app_flow_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart"]
- **Applicable constraints and non-goals:** Выбор включает только явно указанные идентификаторы; каждое удаление требует собственного просмотра и подтверждения, намерение сохраняется до отдельной операции. RU/EN, увеличенный текст и семантика экранного диктора применяются к флажкам и подтверждению.

### U2 · Согласованный снимок явно выбранных связей

- **Work items:** ["107 / 6.20 / e9d10c29e5083d8cceacdd4c7450366faa432cb9"]
- **Requirements and scenarios:** ["intention-management / Requirement: Целевое массовое удаление блокирующих связей","intention-management / Scenario: Выбор сохраняется между порциями и группами","intention-management / Scenario: Одна выбранная связь больше не принадлежит намерению","long-term-relation-management / Requirement: Точные счётчики непосредственных связей намерения","long-term-relation-management / Requirement: Диагностика операций без пользовательского текста"]
- **Affected boundary:** Контракт графового репозитория, транзакционное чтение Drift, наблюдение выбранного набора и безопасная диагностика.
- **Implementation target:** ["lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/application/selected_relations.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_relation_groups.dart","lib/src/graph/data/drift_personal_graph_repository_selected_relations.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","test/app/bootstrap/app_runtime_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/long_term_relation_app_flow_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_relation_group_large_fixture_test.dart","test/graph/data/drift_selected_relations_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/intention/application/intention_contract_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart","test/shared/diagnostics/diagnostics_sink_test.dart"]
- **Applicable constraints and non-goals:** Все выбранные идентификаторы имеют результат на одной ревизии; запросы ограничены выбранными связями и уникальными участниками, точные счётчики вычисляются без сохранённых изменяемых копий. Отказ не даёт частичного успеха и диагностические события не содержат пользовательских данных.

### U3 · Пакетная подготовка подтверждения и проверка стоимости

- **Work items:** ["108 / 6.21 / 687f9c29dae7346a9832d1e1ea1a3bc44cac7c60"]
- **Requirements and scenarios:** ["intention-management / Requirement: Целевое массовое удаление блокирующих связей","intention-management / Scenario: Выбор сохраняется между порциями и группами","intention-management / Scenario: Одна выбранная связь больше не принадлежит намерению","plan.md / Phase 6 / Ready to advance"]
- **Affected boundary:** Актуализация выбора, открытый диалог подтверждения, файловая фикстура с 401 выбранной связью.
- **Implementation target:** ["lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart","test/app/intention_app_lifecycle_test.dart","test/graph/data/drift_relation_group_large_fixture_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart"]
- **Applicable constraints and non-goals:** Ошибка и устаревшая ревизия не разрешают отправить частично обновлённый набор; исчезновение связи требует исправления и нового подтверждения. Транзакционная команда повторно проверяет точный набор и не удаляет намерение.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Incomplete | Для U1–U3 не запускался свежий изолированный reviewer: запуск агентов запрещён условиями этапа. Оценка в текущем контексте не считается независимой. |
| OpenSpec conformance | Complete | Сопоставлены задачи 6.19–6.21, обе delta-спецификации, план, дизайн и три коммита. На 687f9c29dae7346a9832d1e1ea1a3bc44cac7c60 прошли `mise exec --no-deps -- openspec validate manage-long-term-relations --json`, `--strict --no-interactive`, форматирование и анализ из `mise run --skip-tools check`, а также последовательный `mise exec --no-deps -- flutter test --no-pub --concurrency=1` (934 теста). Первый полный check тоже прошёл с 934 тестами; повторный параллельный check дал два тайм-аута файловых тестов, которые отдельно и в последовательном полном наборе прошли. |
| Code quality | Complete | Проверены все 32 delivery/test пути, границы выбора, чтения, подписки, ревизий, ошибок, диагностики и тестов. `git diff --check b10a7898ea90c9e731cdbe8f150d1880750b8ee3 687f9c29dae7346a9832d1e1ea1a3bc44cac7c60`, анализ и последовательный полный набор из 934 тестов прошли; `mise run --skip-tools codegen-check` воспроизвёл F3. Два тайм-аута параллельного повторного прогона не воспроизвелись по отдельности и в последовательном полном наборе. |

## Findings

### F3 · Medium — Сгенерированный Riverpod-хеш не совпадает с исходником

- **Evidence:** В 687f9c29dae7346a9832d1e1ea1a3bc44cac7c60 `lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart:74` сохранён хеш `7c36f921a30e976c11e1ec121b2662178bad3442`. Запуск `mise run --skip-tools codegen-check` в чистом дереве на этом коммите регенерировал только этот хеш как `446800601c4d8a56c391e05e71ba7fd2056952af` и завершился с кодом 1 на проверке чистоты. Локальное изменение от проверки восстановлено из reviewed head.
- **Evidence revisions:** ["687f9c29dae7346a9832d1e1ea1a3bc44cac7c60"]
- **Impact:** Воспроизводимость производного кода нарушена, обязательная проектная проверка `codegen-check` не проходит.
- **Required outcome:** Сгенерированный Riverpod-файл должен соответствовать исходнику при закреплённых инструментах, а повторная генерация должна оставлять дерево чистым.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart","lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart"]

## Review coverage

Все три целевых коммита и задачи 106–108 / 6.19–6.21 сопоставлены с U1–U3. Из 34 reviewable paths два пути OpenSpec служат planning evidence; остальные 32 delivery/test путей покрыты объединением implementation target U1–U3, включая перекрывающиеся пути. Проверены набор идентификаторов до и после двух последовательных удалений, границы транзакции и SQL-порций, изменения участников и счётчиков, отказы, старые ревизии, обновление диалога, локализация и измерения файловой фикстуры. При начале проверки рабочее дерево совпадало с reviewed head; единственное изменение от повторной генерации восстановлено до записи отчёта. Исходный полный check прошёл с 934 тестами. Повторный параллельный check завершился двумя тайм-аутами тестов файлового прерывания; оба теста прошли отдельно, затем весь набор из 934 тестов прошёл последовательно на точном снимке кодовых файлов. OpenSpec-валидация прошла в JSON и strict режимах; повторная генерация выявила F3. Независимый проход остаётся непокрытым.
