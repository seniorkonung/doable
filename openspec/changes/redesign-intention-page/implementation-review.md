# OpenSpec Implementation Review: redesign-intention-page

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все девять целевых коммитов и задачи 1.1–1.9 фазы «Основа связей без массового удаления». Существенных неразрешённых находок нет: массовая операция удалена по всей цепочке, одиночное удаление и защита зависимостей сохранены, общая механика порций обслуживает долговременные связи и дневные выборы. Независимая оценка решений, сверка с OpenSpec и проверка качества завершены. Сохранён применимый планировочный риск AR1 об оформлении замены требований. Полные проверки, повторная генерация и release-сборка прошли. Вывод относится к фазе 1; фазы 2–6 этим диапазоном не реализуются.

## Review target

- **Baseline ref:** bb8d60f5c96b3470d88bafa9c90e38752e85c290
- **Base commit:** bb8d60f5c96b3470d88bafa9c90e38752e85c290
- **Reviewed head:** 6609baa3cc57693c575e9b746435166b1f3ca573
- **Target commits:** ["21d1d3a18345a82787c9fde5ab084dc634786d00", "8f4626a129ce22d1d63cba7436c9c9311dcb8aeb", "12ea1cb6d87843175ebd4389779c6442734628f1", "7063c328de0899096330b27f69d602756c4250aa", "0e96b8a5471c7957d817e6664c5b29b2093a63dc", "427843057232e9d9255129bcf8ef20e90651a604", "c48fb47c5738a73ebd94998d165a2dbb8fd2e1be", "b0024bbef1dc8edad4c595cf120bc09151c761be", "6609baa3cc57693c575e9b746435166b1f3ca573"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/graph/application/blocking_relation_reference.dart", "lib/src/graph/application/delete_blocking_relations.dart", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/application/selected_relations.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_blocking_relations.dart", "lib/src/graph/data/drift_personal_graph_repository_replacement.dart", "lib/src/graph/data/drift_personal_graph_repository_selected_relations.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_confirmation.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart", "lib/src/long_term_relation/presentation/relation_group_paging.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "openspec/changes/redesign-intention-page/tasks.md", "test/app/bootstrap/app_runtime_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/graph/application/delete_blocking_relations_test.dart", "test/graph/application/graph_command_coordinator_blocking_relations_test.dart", "test/graph/application/graph_command_coordinator_relation_creation_test.dart", "test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart", "test/graph/application/graph_command_coordinator_tag_test.dart", "test/graph/application/selected_relations_test.dart", "test/graph/data/drift_blocking_relations_delete_test.dart", "test/graph/data/drift_daily_path_protection_test.dart", "test/graph/data/drift_graph_fact_log_completeness_test.dart", "test/graph/data/drift_graph_fact_log_write_test.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/graph/data/drift_personal_graph_repository_create_relation_test.dart", "test/graph/data/drift_relation_archive_restore_test.dart", "test/graph/data/drift_relation_delete_test.dart", "test/graph/data/drift_relation_group_large_fixture_test.dart", "test/graph/data/drift_relation_update_test.dart", "test/graph/data/drift_relation_watch_test.dart", "test/graph/data/drift_selected_relations_test.dart", "test/graph/data/drift_statistics_relation_snapshot_test.dart", "test/graph/data/file_backed_daily_choice_durability_test.dart", "test/graph/data/file_backed_graph_durability_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/intention/data/drift_intention_relation_counts_test.dart", "test/intention/data/drift_intention_repository_fault_test.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/long_term_relation/presentation/details/relation_details_test_support.dart", "test/long_term_relation/presentation/editor/editor_test_support.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart", "test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart", "test/long_term_relation/presentation/relation_group_paging_test.dart", "test/support/daily_choice_durability_fixture.dart", "test/support/large_blocking_relations_fixture.dart"]
- **OpenSpec change:** redesign-intention-page
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-page/tasks.md"]

## Reviewed increment

### U1 · Удаление массовой операции при сохранении остальных операций графа

- **Work items:** ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.9"]
- **Requirements and scenarios:** ["intention-management: REMOVED Подтверждённое массовое удаление блокирующих связей", "intention-management: Физическое удаление намерения без блокирующих связей — инварианты сохранности и атомарной проверки зависимостей", "intention-management: Получение блокирующих связей намерения — доступность оставшихся групп и прямых дневных ролей", "long-term-relation-management: Согласованность счётчиков с подтверждёнными изменениями графа", "long-term-relation-management: Подтверждённое физическое удаление долговременной связи", "design: решение 13; ADR-0047 — удаление массовой операции и самостоятельной сводки"]
- **Affected boundary:** Пользователь страницы намерения, координатор команд, представление результатов, граница личного графа и адаптер Drift; тестовые потребители этой границы.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/graph/application/blocking_relation_reference.dart", "lib/src/graph/application/delete_blocking_relations.dart", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/application/selected_relations.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_blocking_relations.dart", "lib/src/graph/data/drift_personal_graph_repository_replacement.dart", "lib/src/graph/data/drift_personal_graph_repository_selected_relations.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_confirmation.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_state.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.g.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/app/bootstrap/app_runtime_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/long_term_relation_app_flow_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/graph/application/delete_blocking_relations_test.dart", "test/graph/application/graph_command_coordinator_blocking_relations_test.dart", "test/graph/application/graph_command_coordinator_relation_creation_test.dart", "test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart", "test/graph/application/graph_command_coordinator_tag_test.dart", "test/graph/application/selected_relations_test.dart", "test/graph/data/drift_blocking_relations_delete_test.dart", "test/graph/data/drift_daily_path_protection_test.dart", "test/graph/data/drift_graph_fact_log_completeness_test.dart", "test/graph/data/drift_graph_fact_log_write_test.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/graph/data/drift_personal_graph_repository_create_relation_test.dart", "test/graph/data/drift_relation_archive_restore_test.dart", "test/graph/data/drift_relation_delete_test.dart", "test/graph/data/drift_relation_group_large_fixture_test.dart", "test/graph/data/drift_relation_update_test.dart", "test/graph/data/drift_relation_watch_test.dart", "test/graph/data/drift_selected_relations_test.dart", "test/graph/data/drift_statistics_relation_snapshot_test.dart", "test/graph/data/file_backed_daily_choice_durability_test.dart", "test/graph/data/file_backed_graph_durability_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/graph/presentation/package_consumers_test_support.dart", "test/graph/presentation/tag_package_catalog_consumers_test.dart", "test/intention/data/drift_intention_relation_counts_test.dart", "test/intention/data/drift_intention_repository_fault_test.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/long_term_relation/presentation/details/relation_details_test_support.dart", "test/long_term_relation/presentation/editor/editor_test_support.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart", "test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart", "test/support/daily_choice_durability_fixture.dart", "test/support/large_blocking_relations_fixture.dart"]
- **Applicable constraints and non-goals:** Прежний текст отказа удаления сохраняется без перехода к выбору связей. Проверка фактических зависимостей остаётся атомарной с удалением. Удаление связей по одной, согласованность счётчиков, защита сохранённых путей и долговечность остаются доступными. Схема БД, формат графа, журнал фактов и копии не меняются. Обработчики, диагностика и тесты убираются только вместе с недоступной массовой операцией или её исключительными чтениями.
- **Excluded change scope:** Меню с выключенным удалением, вкладки и новое оформление, отдельный экран правки, новая политика сообщений и новый состав строки относятся к фазам 2–6. Их отсутствие не является пробелом фазы 1.

### U2 · Общая механика порций с сохранением поведения соседства

- **Work items:** ["1.7", "1.8", "1.9"]
- **Requirements and scenarios:** ["long-term-relation-management: Порционное получение выбранной группы связей намерения — ограниченные порции, продолжения и запоздалые ответы", "long-term-relation-management: Согласованность счётчиков с подтверждёнными изменениями графа — пустая и полностью загруженная группы, обновление без смешения ревизий", "design: решение 6 — общее ядро порций", "plan: Phase 1 — сохранение поведения соседства"]
- **Affected boundary:** Соседство долговременных связей и прямых дневных выборов страницы намерения; общая механика загрузки и её потребитель.
- **Implementation target:** ["lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart", "lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.g.dart", "lib/src/long_term_relation/presentation/relation_group_paging.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart", "test/long_term_relation/presentation/relation_group_paging_test.dart"]
- **Applicable constraints and non-goals:** Ядро отвечает за проверку порций и полного количества, совместимость ревизий, поколения запросов, ограниченную пересборку и ближайший сохранившийся якорь. Проверка принадлежности строк, отбор изменений, наблюдение намерения, выбор группы и публикуемые состояния принадлежат потребителю. Оставшаяся часть группы и другие группы автоматически не загружаются. Обе разновидности строк используют одну реализацию алгоритмов.
- **Excluded change scope:** Отдельные модели вкладок и совместная публикация активной и архивной частей группы появятся в последующих фазах. Текущие переключатели и начальная группа соседства сохраняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий рецензент `/root/independent_decisions`, gpt-6.1-sol/high, без истории диалога. Получил только нейтральные цели, ограничения и точные границы. U1 и U2 объединены для независимой проверки из-за общих изменённых файлов; проверено объединение всех 77 путей реализации и тестов на указанном base/head. Планирование, прежние находки и риски ему не передавались. Существенных находок нет. |
| OpenSpec conformance | Complete | Все задачи сопоставлены с диапазонами ниже; использованы артефакты записанного head, а не незакоммиченные версии. Строгая проверка OpenSpec, полный `mise run check`, `mise run codegen-check` и release-сборка завершились с кодом 0 в корне репозитория на записанном head. Подробные свидетельства приведены ниже. |
| Code quality | Complete | По `code-review-and-quality` проверены корректность, читаемость, границы ответственности, безопасность и производительность всех 77 путей реализации/тестов и затронутые неизменённые потребители. Проверены удаления тестов, оба адаптера ядра, обработка отказов, завершение запросов, наблюдения, ревизии, сохранность данных и диагностика. Существенных дефектов и неоправданного расширения не обнаружено. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Оформление замены сохраняемых требований через REMOVED + ADDED

- **Evidence:** `openspec/changes/redesign-intention-page/review.md:17` фиксирует принятый риск замены требований о готовности и согласованности счётчиков. В delta-спецификации связей сохранённые правила счётчиков перенесены в «Согласованность счётчиков с подтверждёнными изменениями графа», а прежний сценарий массового удаления исключён. Причина оформления записана в блоке REMOVED. Проверка этой фазы подтверждает сохранение остальных правил счётчиков.
- **Evidence revisions:** ["6609baa3cc57693c575e9b746435166b1f3ca573"]
- **Potential impact:** Преемственность сохраняемого поведения менее очевидна: его оформление выглядит как удаление и новое добавление требования.
- **Acceptance rationale:** Пользователь ранее принял оформление из-за ограничения OpenSpec на исключение устаревших сценариев через MODIFIED. Возвращение сценария убираемой операции противоречит согласованному изменению.
- **Scope and assumptions:** Только оформление двух замен требований внутри этого изменения; для фазы 1 применима часть о счётчиках. Остальные сохраняемые правила остаются обязательными. Риск не разрешает ослаблять реализацию или тесты.
- **Reopen when:** OpenSpec позволит исключать устаревшие сценарии через MODIFIED либо новые требования перестанут сохранять остальные действующие правила.
- **Acceptance authority:** Ранее зафиксированное решение пользователя в `openspec/changes/redesign-intention-page/review.md:24`: «Принять риск оформления REMOVED + ADDED из-за ограничения инструмента; зафиксировать причину в delta-спецификациях и отчёте».
- **Originating finding:** F4
- **Acceptance lifetime:** Change-scoped

## Review coverage

Проверка выполнена в `/home/seniorkonung/.paseo/worktrees/1id27gtb/real-fireant` на `6609baa3cc57693c575e9b746435166b1f3ca573`. Исходная рабочая копия была чистой; исключённых незакоммиченных изменений не было. Все изменённые пути учтены: 77 путей реализации, локализаций, сгенерированного кода, тестов и фикстур входят в U1/U2; `tasks.md` служит свидетельством планирования. Несопоставленных и посторонних путей нет. Неизменённые файлы изучались как контекст, а не как дополнительная область реализации.

Артефакты proposal, delta-спецификации, design, ADR-манифест, plan и tasks читались из записанного head; статус и `instructions apply` использовались только для определения контекста. Для текущей фазы применены решения 6 и 13 design, ADR-0009, ADR-0011 и уточнения ADR-0047. Историческое описание массового удаления в ADR-0009 не трактовалось как действующая обязанность после его частичного пересмотра. Планировочный AR2 о трёх колонках CountTiles остаётся в `review.md` и ADR-0048: его реализация принадлежит фазе 6 и в текущую область не входит.

Сопоставление каждого коммита и каждой задачи:

taskId 1, задача 1.1, коммит `21d1d3a18345a82787c9fde5ab084dc634786d00`, единица U1. Удалены переход, режим выбора, подтверждение и их исключительные тексты/проверки. `intention_details_delete_test.dart:245` проверяет прежний отказ без перехода и смены группы.

taskId 2, задача 1.2, коммит `8f4626a129ce22d1d63cba7436c9c9311dcb8aeb`, единица U1. Удалены старт, токен, завершение и предъявление массовой операции; оставшиеся проверки занятости и согласования используют одиночные команды.

taskId 3, задача 1.3, коммит `12ea1cb6d87843175ebd4389779c6442734628f1`, единица U1. Удалены команда, её реализация и диагностическое событие. Проверки журнала фактов и статистического снимка используют одиночное удаление; недоступные смешанные массовые транзакции удалены вместе с операцией.

taskId 4, задача 1.4, коммит `7063c328de0899096330b27f69d602756c4250aa`, единица U1. Удалены выбранные ссылки, чтения, наблюдения и уведомления при замене графа. Тестовые адаптеры соответствуют оставшемуся интерфейсу; остальные наблюдатели замены графа сохранены.

taskId 5, задача 1.5, коммит `0e96b8a5471c7957d817e6664c5b29b2093a63dc`, единица U1. Сверки количеств и ревизий переведены на `watchIntention` без ослабления ожиданий. Отсутствующее намерение отличено от подтверждённого нуля.

taskId 6, задача 1.6, коммит `427843057232e9d9255129bcf8ef20e90651a604`, единица U1. Удалены самостоятельное чтение сводки и диагностика; интерфейс, Drift и все тестовые адаптеры согласованы. Проверки, переведённые в 1.5, сохранены.

taskId 7, задача 1.7, коммит `c48fb47c5738a73ebd94998d165a2dbb8fd2e1be`, единица U2. Ядро обобщено по строке и идентификатору, обе разновидности групп подключены к нему. В этом коммите файлы проверок соседства не менялись.

taskId 8, задача 1.8, коммит `b0024bbef1dc8edad4c595cf120bc09151c761be`, единица U2. Проверки механизмов перенесены в `relation_group_paging_test.dart`; у модели сохранены проверки отбора изменений, наблюдений и публикуемых состояний.

taskId 9, задача 1.9, коммит `6609baa3cc57693c575e9b746435166b1f3ca573`, единица U1, U2. Коммит изменяет только отметку задачи; её утверждения независимо подтверждены свежими проверками и сборкой в этой сессии.

Дополнительно сравнены все девять последовательных диапазонов из workflow. На каждом шаге в `tasks.md` меняется только ожидаемая отметка выполнения: идентификаторы, номера, описания и порядок задач остаются прежними. В ходе review задачи и план не редактировались; новые задачи не требуются.

Ключевые сценарии и границы подтверждены следующими свидетельствами записанного head:

Отказ удаления сохраняет намерение и прежнее объяснение, без перехода к связям. `test/intention/presentation/details/intention_details_delete_test.dart:245`; сравнение ARB подтвердило неизменность текста отказа в ru/en.

Архивные и незагруженные зависимости продолжают блокировать удаление, прежний ноль не даёт разрешения. `test/intention/data/drift_intention_relation_counts_test.dart:52` и `:124`; атомарная проверка остаётся в `drift_personal_graph_repository.dart:1052` и `:1066`.

Отсутствующее намерение отличается от существующего без связей; подробности и числа имеют одну ревизию. `test/intention/data/drift_intention_relation_counts_test.dart:37` и `:186`; чтение снимка в `drift_personal_graph_repository.dart:450`.

Создание, изменение типа/участника, каскад, восстановление и удаление сохраняют точные количества. `drift_personal_graph_repository_create_relation_test.dart:55`, `drift_relation_update_test.dart:133`, `drift_intention_relation_counts_test.dart:264`, `drift_relation_archive_restore_test.dart:66` и `:139`, `drift_relation_delete_test.dart:67`.

Пустая и полностью загруженная группы обновляют общую сводку, поздний ответ не возвращает удалённую связь. `relation_neighborhood_view_model_test.dart:889`, `:936`, `:1016`, `:1733` и `:2221`; потребитель отбирает ревизии в `relation_neighborhood_view_model.dart:767`.

Проверка полноты, размера, принадлежности строк, устранение повторов и совместимость продолжения. `test/long_term_relation/presentation/relation_group_paging_test.dart:11`; общие алгоритмы в `relation_group_paging.dart:60` и `:83`.

Поздние ответы прежнего поколения, прерывание сборки, исчерпание повторов и ограничение чтения. Параметризованные проверки в `relation_group_paging_test.dart`; сборка в `relation_group_paging.dart:106` ограничена восемью попытками и загруженным объёмом с запрошенной порцией.

Ближайший сохранившийся якорь и обе разновидности групп. Проверки якорей в `relation_group_paging_test.dart`; `relation_group_paging.dart:271`, адаптеры в `relation_neighborhood_view_model.dart:439` и `:469`; сохранённые проверки дневных ролей и виджетов соседства.

Оставшиеся операции сохраняют путь, журнал фактов, наблюдателей и данные после перезапуска. Наборы `drift_daily_path_protection_test.dart`, `drift_graph_fact_log_write_test.dart`, `drift_graph_fact_log_completeness_test.dart`, `drift_graph_replacement_test.dart`, `file_backed_graph_durability_test.dart` и `file_backed_daily_choice_durability_test.dart`.

Проверены также сохранённые тесты всех восьми агрегатов в неизменённом `test/graph/data/drift_relation_count_aggregates_test.dart`. Удалённые проверки относились к массовой операции, выбранным ссылкам или самостоятельному чтению; проверки оставшихся механизмов сохранены либо перенесены на их владельца. Новая обобщённая механика уже имеет двух текущих потребителей: долговременную и дневную группы. Зависимости, SQL, схема и форматы хранения не расширялись. В диагностике удалены только события убранных операций; новые потоки пользовательских данных не добавлялись.

Свежая автоматическая проверка на записанном head:

Команда `mise run check`. Код 0: форматирование без изменений, обе shell-проверки, `flutter analyze` без замечаний, 3434 обычных теста и 18 тестов `flutter_process` прошли.

Команда `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive --json`. Код 0, `valid: true`, список проблем пуст.

Команда `mise run codegen-check` на чистой рабочей копии. Код 0; повторная генерация локализаций, провайдеров и схемы не изменила tracked-файлы; после проверки рабочая копия осталась чистой.

Команда `mise exec --no-deps -- flutter build apk --release`. Код 0; получен `build/app/outputs/flutter-apk/app-release.apk`, 71.9 MB. SHA-256: `be81a5ad72273c036070fade69326dd5802f368280d2b40c87f04b9efeb4ce6a`.

Поиск удаляемых API в `lib/`, `test/`, `benchmark/` через `git grep` на записанном head. Совпадений нет для выражения из задачи 1.9: массовая команда, её ссылки/чтения, режим выбора и самостоятельная сводка отсутствуют.

Структурное сравнение локализаций base/head. Из каждого языка удалены одинаковые 34 ключа; оставшиеся значения не изменены. Сгенерированные провайдеры меняют только хеш исходника.

Команда `git diff --check` для точного base/head. Код 0.

DTD: поиск запущенного приложения. Запущенных debug-процессов и DTD не обнаружено; использованы CLI-проверки, устройство или эмулятор не запускались.

APK для проверки пользователем: [app-release.apk](../../../build/app/outputs/flutter-apk/app-release.apk). На устройстве остаются неподтверждёнными две ручные проверки из задачи 1.9: прежний текст отказа удаления без кнопки перехода к связям; переключение групп соседства, подгрузка длинной группы и обновление после архивирования и одиночного удаления связи. Их отсутствие не блокирует завершение этой фазы по правилам репозитория.

Код и плановые артефакты в рамках review не исправлялись. Ремедиация и новые задачи не требуются. Отчёт фиксирует результат проверки и применимый принятый риск; решения о последующих фазах и публикации принадлежат оркестратору.
