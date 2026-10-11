# OpenSpec Implementation Review: remove-previous-route-reuse

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Поддержка повтора прежних маршрутов удалена в согласованной границе. Пошаговое создание, актуализация и замена в обоих направлениях, навигация, завершение принятых команд и сохранность дневных выборов подтверждены. Неразрешённых замечаний и зафиксированных принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 977af8191b3ccb0caee3fcf1b0383f76dce40ff4
- **Base commit:** 977af8191b3ccb0caee3fcf1b0383f76dce40ff4
- **Reviewed head:** 198153503fe375a6e530e1284ccda5c72e2a95ee
- **Target commits:** ["8a88f2ea4a919fea3e5d3b55d202bfb9f58f2c13","efe786bfcfaad92b7b778137c680fd3129e614e1","3450fec11a3ede8956da8e6bbbdddb64fa3b8d1e","36bcbeda7533c68c6934d5836530a7a6ba0a6b05","3d47806a5f009bed6ce6e55763225ebfd43e7051","a9157d37e4d6d96aefc5eda8e3ad6e0bba08e0db","a01ea58468db8dd77ae19ecf457f9bd527febdec","f9715961a0f2d1af68367d51e6fdb98c06803c98","c9b7605f0298fe0b4acfe03c2888aa2fff5aa27d","fbc5b57142d7ef1c036340ced7060dd45ddb72f5","88fe04a0fb98c0dda4f42b21d91105b57ca20f36","39355936a6c62e383ec80026375e1074589e2e8e","198153503fe375a6e530e1284ccda5c72e2a95ee"]
- **Reviewable paths:** ["docs/discussions/action-centered-goal-system.md","drift_schemas/drift_schema_v1.json","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/application/choice_path_suggestions.dart","lib/src/daily_choice/presentation/daily_choice_creation_completion.dart","lib/src/daily_choice/presentation/daily_choice_creation_exit_action.dart","lib/src/daily_choice/presentation/editor/daily_choice_creation_page.dart","lib/src/daily_choice/presentation/path/choice_path_page.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_state.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_view.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart","lib/src/data/local/app_database.g.dart","lib/src/data/local/schema/daily_choice_schema.drift","lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_choice_path_suggestions.dart","lib/src/graph/data/drift_relation_count_aggregates.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","openspec/changes/remove-previous-route-reuse/tasks.md","test/app/bootstrap/app_runtime_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/home_favorites_reorder_app_flow_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/navigation/app_shell_unnamed_page_scenarios.dart","test/daily_choice/application/choice_path_suggestions_test.dart","test/daily_choice/presentation/daily_choice_creation_exit_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart","test/daily_choice/presentation/path/choice_path_suggestions_view_model_test.dart","test/daily_choice/presentation/path/choice_path_suggestions_view_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_choice_path_suggestions_test.dart","test/graph/data/drift_daily_choice_read_cost_test.dart","test/graph/presentation/favorite_mark_package_consumers_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart"]
- **OpenSpec change:** remove-previous-route-reuse
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["docs/discussions/action-centered-goal-system.md","openspec/changes/remove-previous-route-reuse/tasks.md"]

## Reviewed increment

### U1 · Дневной выбор строится пошагово без поддержки повтора прежнего маршрута

- **Work items:** ["1.1","1.2","1.3","1.4","1.5","1.6","1.7","1.8","1.9","1.10","1.11","1.12","1.13"]
- **Requirements and scenarios:** ["daily-choice-management / Календарная дата и независимое выполнение", "daily-choice-management / Атомарная замена участников и пути", "daily-choice-management / Подтверждённые результаты и безопасные ошибки дневного выбора", "daily-choice-management / Входы в создание дневного выбора", "daily-choice-management / Сохранённый маршрут не предлагается при новом выборе", "daily-choice-management / Открытие созданного дневного выбора", "daily-choice-management / REMOVED: Повтор прежнего маршрута", "daily-choice-management / Пошаговый выбор сверху вниз", "daily-choice-management / Пошаговый выбор снизу вверх", "intention-management / Явная классификация действия", "app-navigation / Панель на обычных страницах", "app-navigation / Выход из потока создания", "app-navigation / Открытие созданной сущности"]
- **Affected boundary:** Пользовательские потоки дневного выбора и обслуживающие их представление, личный граф, локальное хранение, диагностика и локализации. Все изменения служат одному сквозному исходу; тестовые реализации общего контракта входят в ту же единицу.
- **Implementation target:** ["drift_schemas/drift_schema_v1.json","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/application/choice_path_suggestions.dart","lib/src/daily_choice/presentation/daily_choice_creation_completion.dart","lib/src/daily_choice/presentation/daily_choice_creation_exit_action.dart","lib/src/daily_choice/presentation/editor/daily_choice_creation_page.dart","lib/src/daily_choice/presentation/path/choice_path_page.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_state.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_view.dart","lib/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart","lib/src/data/local/app_database.g.dart","lib/src/data/local/schema/daily_choice_schema.drift","lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_choice_path_suggestions.dart","lib/src/graph/data/drift_relation_count_aggregates.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","test/app/bootstrap/app_runtime_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/home_favorites_reorder_app_flow_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/navigation/app_shell_unnamed_page_scenarios.dart","test/daily_choice/application/choice_path_suggestions_test.dart","test/daily_choice/presentation/daily_choice_creation_exit_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart","test/daily_choice/presentation/path/choice_path_suggestions_view_model_test.dart","test/daily_choice/presentation/path/choice_path_suggestions_view_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_choice_path_suggestions_test.dart","test/graph/data/drift_daily_choice_read_cost_test.dart","test/graph/presentation/favorite_mark_package_consumers_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart"]
- **Applicable constraints and non-goals:** Сохраняются самостоятельные дневные выборы и их шаги, ссылочная целостность, готовность конечного действия, независимые дата, описание и выполнение, атомарная замена, владение навигацией и жизненный цикл команды. Правка схемы версии 1 на месте допустима по подтверждённому отсутствию установок, требующих перехода со старой физической схемы. Новый способ повтора маршрутов, изменение предметной модели и переустройство общих механизмов не входят в результат.
- **Excluded change scope:** Синхронизация delta-спецификаций с основными спецификациями и архивация относятся к последующим этапам. Архив OpenSpec сохраняет историю решений.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий ревьюер `/root/independent_decision_review` с `fork_turns=none` применил `implementation-decision-review` к точным 50 путям U1 и закреплённым base/head. Получил только нейтральное намерение, обязательные ограничения и границы; planning, история коммитов, прежние оценки и отчёт не передавались. Неизменённый контекст проверялся через `diff --quiet` перед чтением. Итог: `No substantive findings`, полный охват. |
| OpenSpec conformance | Complete | Полный граф proposal → specs → design → adr → plan → tasks прочитан из Reviewed head; CLI status/instructions использованы для его обнаружения. Сопоставлены все задачи и сценарии. В корне репозитория на Reviewed head успешно выполнены `mise run check`, `mise run codegen-check` и `mise exec --no-deps -- openspec validate remove-previous-route-reuse --strict --json`; подробности ниже. |
| Code quality | Complete | По `code-review-and-quality` проверены correctness, readability, architecture, security, performance и свидетельства всех 50 delivery/test-путей; документация сверена отдельно. Дополнительный ревьюер `/root/commit_quality_review` прочитал каждый из 13 целевых коммитов и его diff. Подтверждённых дефектов, избыточных элементов или несопоставленных изменений не выявлено. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

**Границы и источники**

Все 52 пути из discovery учтены: 22 пути реализации, схемы и ресурсов и 28 путей тестов входят в U1; `tasks.md` фиксирует выполненные работы, а `docs/discussions/action-centered-goal-system.md` описывает актуальный продукт и проверен по задаче 1.12. Несопоставленных и посторонних путей нет. Основные спецификации, применимые ADR и неизменённые вызывающие стороны служат контекстом; target не расширялся.

Свидетельства прочитаны через `git show <Reviewed head>:<path>` и diff точных base/head; удалённое содержимое проверено на Base commit. Рабочее дерево перед проверками было чистым, HEAD совпадал с Reviewed head; незакоммиченных исходных или planning-изменений не исключалось. Прежнего `implementation-review.md` нет; переносимых замечаний и принятых рисков нет.

**Покрытие задач и всех целевых коммитов**

Каждый коммит просмотрен отдельно в соответствующем `fromExclusive..throughInclusive`; номера и ID приведены из workflow. Проверочные коммиты 1.4 и 1.13 не содержат отдельной реализации: их отметки подтверждены свежим прогоном. Содержимое, порядок и номера всех 13 задач в диапазоне сохранены; изменены только отметки выполнения.

Задача 1.1 (ID 1, коммит `8a88f2ea4a919fea3e5d3b55d202bfb9f58f2c13`, единица U1): Переведены создание, замена, выход, жизненный цикл приложения и смешанные проверки навигации на шаги пути. Сохранены независимые поля, исходная история, чужой черновик, защита отправки и поздний результат.

Задача 1.2 (ID 2, коммит `efe786bfcfaad92b7b778137c680fd3129e614e1`, единица U1): Из страницы пути удалены предложения, предпросмотр и преобразование шага из подсказки. Регрессия в `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:261` проверяет сохранённый допустимый маршрут, отсутствие его предложения и подстановки, обязательность явного прохода.

Задача 1.3 (ID 3, коммит `3450fec11a3ede8956da8e6bbbdddb64fa3b8d1e`, единица U1): Из обработчика завершения и действия выхода удалены только параметр и ветви `previewRoute`. Сохранились проверки владельца, полной истории и верхней безымянной страницы.

Задача 1.4 (ID 4, коммит `36bcbeda7533c68c6934d5836530a7a6ba0a6b05`, единица U1): Коммит меняет только отметку проверки 1.4. Сохраняемые пользовательские потоки повторно проверены полным `mise run check` в этой сессии.

Задача 1.5 (ID 5, коммит `3d47806a5f009bed6ce6e55763225ebfd43e7051`, единица U1): Из четырёх общих файлов согласования и потребителей пакетов удалены только участники подсказок. Проверки ревизий, каталогов, групп, подробностей, блокирующих ссылок и ограниченности чтений сохранены.

Задача 1.6 (ID 6, коммит `a9157d37e4d6d96aefc5eda8e3ad6e0bba08e0db`, единица U1): Полностью удалены отдельные состояния, модель представления и её тесты. Неизменённая модель пошагового пути сохраняет свою ответственность; новые модели и совместимые заглушки не добавлены.

Задача 1.7 (ID 7, коммит `a01ea58468db8dd77ae19ecf457f9bd527febdec`, единица U1): В `test/graph/data/drift_daily_choice_read_cost_test.dart:203` путь из 150 шагов подготавливается непосредственно: проверяются создание, замена, точная последовательность сохранённых связей и стоимость чтений. Остальные проверки каталога, групп и bootstrap сохранены.

Задача 1.8 (ID 8, коммит `f9715961a0f2d1af68367d51e6fdb98c06803c98`, единица U1): Удалены типы, контракт и Drift-реализация чтения подсказок с отдельными тестами; все тестовые реализации репозитория согласованы. Общие подтверждённый путь, чтение подробностей, продолжения и транзакционная проверка сохранены.

Задача 1.9 (ID 9, коммит `c9b7605f0298fe0b4acfe03c2888aa2fff5aa27d`, единица U1): Удалены ровно два индекса недавних выборов; generated database и snapshot согласованы. `drift_relation_count_aggregates.dart` использует оставшиеся индексы с первым ключом участника; таблицы, ограничения и триггеры не изменены.

Задача 1.10 (ID 10, коммит `fbc5b57142d7ef1c036340ced7060dd45ddb72f5`, единица U1): Удалены только событие, стадия и представление диагностики чтения подсказок. Общая диагностика чтения, проверки и записи пути сохранена.

Задача 1.11 (ID 11, коммит `88fe04a0fb98c0dda4f42b21d91105b57ca20f36`, единица U1): Из двух ARB и трёх generated-классов удалены 19 сообщений `choiceSuggestion*`; общие строки сохранены. Воспроизводимость подтверждена `codegen-check`.

Задача 1.12 (ID 12, коммит `39355936a6c62e383ec80026375e1074589e2e8e`, единица U1): В `docs/discussions/action-centered-goal-system.md` описание создания и замены согласовано с пошаговым выбором. Архивная история, декомпозиция и теги сохранены.

Задача 1.13 (ID 13, коммит `198153503fe375a6e530e1284ccda5c72e2a95ee`, единица U1): Коммит меняет только отметку итоговой проверки 1.13. В этой сессии выполнены полный check с slow, воспроизводимость генерации, строгая валидация, поиск остатков и проверка diff.


**Соответствие сценариям**

Для свидетельств ниже версия — Reviewed head. Неизменённые тесты и вызывающие стороны прочитаны как контекст сохраняемого поведения; в целевой diff они не добавлены. Файлы сценариев с `part of` выполняются через указанный основной набор.

Сценарий Календарная дата: «Запись уже выполненного»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:434` проверяет прошлую дату и независимое выполнение при нижнем создании; `test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart:262` — явную запись показанных полей.

Сценарий Календарная дата: «Смена часового пояса не сдвигает дату»: `test/graph/data/drift_daily_choice_update_test.dart:194`.

Сценарий Календарная дата: «Изменение полей после архивирования пути»: `test/graph/data/drift_daily_choice_update_test.dart:125` и `:218`.

Сценарий Атомарная замена: «Замена действия сохраняет выполнение»: `test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart:341`, оба направления.

Сценарий Атомарная замена: «Недопустимый новый путь не разрушает прежний»: `test/graph/data/drift_daily_choice_replace_test.dart:259`.

Сценарий Атомарная замена: «Замена освобождает последнюю ссылку»: `test/graph/data/drift_daily_choice_replace_test.dart:151`, проверяются новые шаги, отсутствие старых и разрешения освобождённых связей.

Сценарий Безопасные ошибки: «Ошибка проверки пути не выглядит тупиком»: `test/daily_choice/presentation/path/choice_path_page_test.dart:305`.

Сценарий Безопасные ошибки: «Повторное нажатие не создаёт дубликат»: `test/app/daily_choice_app_lifecycle_test.dart:167`, принятие команды удерживается SQL-gate.

Сценарий Безопасные ошибки: «Описание согласовано с повтором после временного отказа»: `test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart:194`.

Сценарий Безопасные ошибки: «Конфликт пути сохраняет независимые поля создания»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:984`; нижнее направление — `:692`.

Сценарий Безопасные ошибки: «Уход с экрана сохраняет результат операции»: `test/daily_choice/presentation/editor/daily_choice_path_replace_view_model_test.dart:169`.

Сценарий Безопасные ошибки: «Неизвестный отказ не маскируется временной ошибкой»: `test/daily_choice/presentation/editor/daily_choice_path_replace_page_test.dart:239` и `test/graph/data/drift_daily_choice_read_test.dart:200`.

Сценарий Входы: «Выбор от намерения через поиск основания»: `test/app/quick_creation/quick_creation_flow_scenarios.dart:5`, вариант `topDown`, основной набор `test/app/creation_flows_integration_test.dart`.

Сценарий Входы: «Вход со страницы намерения не требует поиска»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:261`.

Сценарий Входы: «Отмена поиска основания ничего не создаёт»: `test/app/quick_creation/quick_creation_launcher_test.dart:108` и `test/app/quick_creation/quick_creation_flow_scenarios.dart:170` через `creation_flows_integration_test.dart`.

Сценарий Входы: «Назад во время сохранения не разрешает второе подтверждение»: `test/daily_choice/presentation/daily_choice_creation_exit_test.dart:51`, варианты выхода из пути после принятия команды.

Сценарий Входы: «Сохранённый маршрут не предлагается при новом выборе»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:261`: существующий допустимый путь, отсутствие предложения и подстановки, отдельный пошаговый проход и явное подтверждение.

Сценарий Открытие: «Созданный выбор открывается вместо построения пути»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:907` и `test/daily_choice/presentation/daily_choice_creation_completion_test.dart`.

Сценарий Открытие: «Выбор на другую дату не меняет каталог»: `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:261` сохраняет другой день и проверяет прежний день каталога; `test/app/creation_flows_integration_test.dart:55` проверяет сохранение параметров каталогов.

Сценарий Открытие: «Уход до результата не меняет страницу»: `test/app/daily_choice_app_lifecycle_test.dart:167`.

Сценарий Панель: «Страница намерения показывает панель»: Матрица `test/app/navigation/app_shell_page_matrix.dart` через `test/app/navigation/app_shell_pages_above_test.dart:77`.

Сценарий Панель: «Страница-задача скрывает панель»: Та же матрица страниц, включая форму связи и оба направления пути.

Сценарий Панель: «Обычная страница над задачей показывает панель»: Та же матрица, переходы к подробностям участников из формы связи.

Сценарий Панель: «Правка на странице намерения не скрывает панель»: `test/app/navigation/ordinary_page_layout_scenarios.dart:12` через `test/app/navigation/app_shell_layout_test.dart`.

Сценарий Панель: «Поиск действия не является корневой страницей»: Матрица `app_shell_page_matrix.dart` через `app_shell_pages_above_test.dart:77`.

Сценарий Панель: «Отказ подготовки хранилища показан без панели»: `test/app/bootstrap/app_bootstrap_shell_test.dart:57`.

Сценарий Готовность: «Явное включение готовности к действию»: `test/intention/presentation/details/intention_details_page_test.dart:297`.

Сценарий Готовность: «Подтверждение готовности к действию»: Тот же тест `:297` подтверждает команду и последующее состояние.

Сценарий Готовность: «Отказ от подтверждения готовности»: Тот же тест `:297` проверяет отсутствие команды после отмены.

Сценарий Готовность: «Обратимое выключение готовности»: `test/intention/presentation/details/intention_details_page_test.dart:374`.

Сценарий Готовность: «Утрата готовности сохраняет прежний выбор»: `test/graph/data/drift_daily_path_protection_test.dart:238` и `test/graph/data/drift_daily_choice_update_test.dart:125`.

Сценарий Готовность: «Готовность выбрана до создания»: `test/intention/presentation/editor/intention_editor_page_test.dart:1455`.

Сценарий Готовность: «Отмена начальной готовности»: Тот же тест `:1455` проверяет выключение в черновике без команды.

Сценарий Сохраняемый верхний обход: дальнейшая декомпозиция действия, достижимость без возврата в префикс, смена ветви и отсутствие пути: `test/graph/data/drift_choice_path_continuations_test.dart:497`, `:517`; `test/daily_choice/presentation/path/choice_path_page_test.dart:238`, `:305`; `test/daily_choice/presentation/daily_choice_creation_flow_test.dart:907`.

Сценарий Сохраняемый нижний обход: многошаговый путь, достаточность одного основания, возврат без смены действия и ограничение готовности: `test/daily_choice/presentation/path/choice_path_page_test.dart:378`; `test/daily_choice/presentation/path/choice_path_view_model_test.dart:27`; `test/graph/data/drift_choice_path_continuations_test.dart:183`, `:440`.


Требование «Повтор прежнего маршрута» и его сценарии удаляются delta-спецификацией; их отдельные application, presentation и Drift-тесты закономерно удалены. Проверки самостоятельности записей, полных путей и независимых полей сохранены у действующих потоков. Отсутствие предложений определяется общей страницей для создания, актуализации и замены; дублирующие проверки каждого направления и назначения не добавлены.

**Сохранённые механизмы и инженерное качество**

В `ChoicePathPage` удалены отдельная модель предложений, её подписка, показ и обход пошагового подтверждения. Сохраняемая `ChoicePathViewModel` продолжает проверять префикс, направление, ревизию и возможность подтверждения. Создание, пересчёт и замена используют одну страницу; `DailyChoiceCreationStep.fromSummary` сохраняет показанный смысл пути.

В `lib/src/daily_choice/presentation/daily_choice_creation_completion.dart:12` сохранены принадлежность владельцу, полная исходная история и запрет действия при безымянной странице сверху. Отдельные completion/session-тесты и сквозные exit/lifecycle-наборы подтверждают отмену, обычный возврат, чужую историю, принятую команду и поздний результат.

Изменение `PersonalGraphRepository` сокращает контракт; чтение подробностей, подтверждённый путь и транзакционные изменяющие операции остаются у прежнего владельца. Удаление dedicated-тестов подсказок не затронуло проверки атомарности, rollback, восстановления после открытия базы и ссылочной целостности. Общие проверки согласования продолжают проверять остальных потребителей и ревизии.

В `lib/src/graph/data/drift_relation_count_aggregates.dart:189` запросы используют оставшиеся индексы с первым ключом участника. Read-only сравнение snapshot после нормализации числовых ссылок в имена подтвердило удаление ровно `daily_choices_source_recent` и `daily_choices_selected_recent`; остальные entities, fixed SQL и параметры совпадают с base. Удаление не меняет таблицы, данные, внешние ключи или триггеры и уменьшает обслуживание неиспользуемых индексов. Полные read-cost, aggregate, schema и durability-тесты проверяют действующие чтения и хранение.

Исполняемые ветви, подписки, запросы, локализации и диагностика удалённой возможности устранены без новых абстракций, зависимостей и конфигурации. Границы проверки ввода, безопасного предъявления ошибок и доступа к данным не ослаблены; новых внешних интеграций и границ доверия нет.

**Проверки и завершение этапа**

Место выполнения: `/home/seniorkonung/.paseo/worktrees/1id27gtb/hardy-jaguar`. Версия проверяемых исходных данных: `198153503fe375a6e530e1284ccda5c72e2a95ee`.

Проверка `mise run check` — exit 0: форматирование 581 файла без изменений, проверка CI scope, анализатор без замечаний, 2642 теста основного приложения (включая `slow`) и 8 тестов Widgetbook прошли.

Проверка `mise run codegen-check` — exit 0 на чистом Reviewed head: локализации, build_runner и dump схемы воспроизводимы; tracked diff после повторной генерации отсутствовал.

Проверка `mise exec --no-deps -- openspec validate remove-previous-route-reuse --strict --json` — exit 0, `valid: true`, `issues: []`.

Проверка `git grep -n -E 'ChoicePathSuggestion|choice_path_suggestions|getChoicePathSuggestions|fromSuggestion|choiceSuggestion|previewRoute|daily_choices_(source|selected)_recent' 198153503fe375a6e530e1284ccda5c72e2a95ee -- lib test widgetbook drift_schemas` — ожидаемый exit 1, совпадений нет.

Проверка `git --literal-pathspecs diff --check 977af8191b3ccb0caee3fcf1b0383f76dce40ff4 198153503fe375a6e530e1284ccda5c72e2a95ee` — exit 0.

Проверка формата: `node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/remove-previous-route-reuse/implementation-review.md` — exit 0, формат v1, 0 замечаний, 0 принятых рисков.


По итогам трёх проходов коррекции кода, тестов или planning-артефактов не потребовались. Этап добавляет только этот отчёт; задачи остаются завершёнными в прежнем порядке, новые задачи не добавлены. Неразрешённых решений и работы для передачи на устранение замечаний нет. Результат фиксирует ревью указанного диапазона; публикацией review-коммита управляет оркестратор.
