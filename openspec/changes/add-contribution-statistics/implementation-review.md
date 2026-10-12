# OpenSpec Implementation Review: add-contribution-statistics

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F1: при сохранённой глубокой прокрутке прежние числа видны без различимого признака обновления или его отказа. Исправление остаётся для последующего этапа разрешения замечаний.

## Review target

- **Baseline ref:** d4be9173ff9c86c5fe2be4fd81786ab4778b51f7
- **Base commit:** d4be9173ff9c86c5fe2be4fd81786ab4778b51f7
- **Reviewed head:** c77a621c68f39a69c52c6b4eca279441aba7c6dc
- **Target commits:** ["49477b9f6ea8dea484ec815db891fdecc2a3895c","e5adb9793eda31f84837bfb57674f416c8264517","c766bd91d46c383b3cb7f8a98f7d5cc9038f7730","e528d68e6be90bc7256091ceaf6686f919c4715e","287d41244c42617e51baefcbdbd47af6bbae03ab","313124be79cbba8aba3a9440967a4cbaef32c7df","1fe7e8d73530e3b5d3e92368689f76c59d931162","36ec2b5081a555b9d2f9c70bd5353c4dc4b86b7f","019804ee9cb234658f4e1791ce57928b28f19445","8e44ae739f16abccd7e6a669c3b30cfa66522bb5","861eb6162e1e086484822e4800899e9ac094c5db","15251c1dfc9cff2264c3c1785c85d0c9b8ac9f37","33e289c265cc5e8cd26ab3493df6efb0b24c4549","c77a621c68f39a69c52c6b4eca279441aba7c6dc"]
- **Reviewable paths:** ["dart_test.yaml","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/app/home/home_page.dart","lib/src/data/local/database_connection.dart","lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_statistics.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","lib/src/statistics/application/contribution_counts.dart","lib/src/statistics/application/statistics_period.dart","lib/src/statistics/application/statistics_read_contract.dart","lib/src/statistics/presentation/home_statistics_content.dart","lib/src/statistics/presentation/home_statistics_period_selector.dart","lib/src/statistics/presentation/home_statistics_state.dart","lib/src/statistics/presentation/home_statistics_view_model.dart","lib/src/statistics/presentation/home_statistics_view_model.g.dart","mise.toml","openspec/changes/add-contribution-statistics/design.md","openspec/changes/add-contribution-statistics/tasks.md","test/app/bootstrap/app_runtime_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/home_statistics_app_flow_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/navigation/app_navigation_accessibility_test.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/navigation/app_start_page_test.dart","test/app/tag_app_lifecycle_test.dart","test/app/tag_assignment_app_lifecycle_test.dart","test/app/tag_navigation_app_lifecycle_test.dart","test/daily_choice/presentation/daily_choice_creation_exit_test.dart","test/data/local/database_transaction_observer_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_statistics_read_cost_test.dart","test/graph/data/drift_statistics_read_failure_test.dart","test/graph/data/drift_statistics_read_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart","test/shared/diagnostics/diagnostics_sink_test.dart","test/statistics/application/statistics_period_test.dart","test/statistics/application/statistics_read_contract_test.dart","test/statistics/presentation/home_statistics_content_test.dart","test/statistics/presentation/home_statistics_period_selector_test.dart","test/statistics/presentation/home_statistics_reconciliation_test.dart","test/statistics/presentation/home_statistics_view_model_test.dart","test/support/contribution_statistics_fixture.dart","test/support/statistics_read_contract_test_fallback.dart"]
- **OpenSpec change:** add-contribution-statistics
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-contribution-statistics/design.md","openspec/changes/add-contribution-statistics/tasks.md"]

## Reviewed increment

### U1 · Точный вклад по сохранённому пути за период

- **Work items:** ["1.1","1.3","1.4","1.12"]
- **Requirements and scenarios:** ["Меры статистики вклада","Засчитывание по сохранённому пути","Каталог элементов Главной","Порционная загрузка с точным числом элементов","Состояния получения статистики"]
- **Affected boundary:** Потребитель статистики → единая граница личного графа → файловый SQLite.
- **Implementation target:** ["lib/src/graph/application/personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository.dart","lib/src/graph/data/drift_personal_graph_repository_statistics.dart","lib/src/statistics/application/contribution_counts.dart","lib/src/statistics/application/statistics_period.dart","lib/src/statistics/application/statistics_read_contract.dart","test/app/bootstrap/app_runtime_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_app_lifecycle_test.dart","test/app/navigation/app_navigation_accessibility_test.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/navigation/app_start_page_test.dart","test/app/tag_app_lifecycle_test.dart","test/app/tag_assignment_app_lifecycle_test.dart","test/app/tag_navigation_app_lifecycle_test.dart","test/daily_choice/presentation/daily_choice_creation_exit_test.dart","test/graph/application/graph_command_coordinator_relation_creation_test.dart","test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart","test/graph/data/drift_statistics_read_failure_test.dart","test/graph/data/drift_statistics_read_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/intention/presentation/catalog/catalog_test_support.dart","test/intention/presentation/details/details_test_support.dart","test/intention/presentation/operation/intention_command_coordinator_test.dart","test/long_term_relation/presentation/details/relation_details_test_support.dart","test/long_term_relation/presentation/editor/editor_test_support.dart","test/long_term_relation/presentation/editor/relation_form_test_support.dart","test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart","test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart","test/statistics/application/statistics_period_test.dart","test/statistics/application/statistics_read_contract_test.dart","test/support/statistics_read_contract_test_fallback.dart"]
- **Applicable constraints and non-goals:** Каждый дневной выбор считается самостоятельно; архивирование не исключает сохранённые основания. Сводка и порции согласованы по ревизии, порядок устойчив, курсор связан с условиями и эпохой. Данные проверяются при необходимом декодировании; повторная проверка целостности сохранённых путей и изменение схемы не требуются.
- **Excluded change scope:** Фазы 2–4: вид «Через связи», статистика отдельного намерения, переходы к ней и каталог дневных выборов на дату.

### U2 · Предсказуемая стоимость чтения и безопасная диагностика

- **Work items:** ["1.2","1.3","1.5","1.12"]
- **Requirements and scenarios:** ["Диагностика статистики без пользовательского содержимого","Отзывчивость на максимальных данных","Решение 10 дизайна: согласованные профили и бюджеты"]
- **Affected boundary:** Чтение статистики → общая очередь графа, диагностический sink и регулярный check.
- **Implementation target:** ["dart_test.yaml","lib/src/data/local/database_connection.dart","lib/src/graph/data/drift_personal_graph_repository_statistics.dart","lib/src/shared/diagnostics/developer_diagnostics_sink.dart","lib/src/shared/diagnostics/diagnostics_sink.dart","mise.toml","test/data/local/database_transaction_observer_test.dart","test/graph/data/drift_statistics_read_cost_test.dart","test/shared/diagnostics/diagnostics_sink_test.dart","test/support/contribution_statistics_fixture.dart"]
- **Applicable constraints and non-goals:** Диагностика содержит только вид, этап, длительность и категорию результата. Проверяются согласованные владельцем профили: 100 выборов ежедневно в 2025–2027 годах, граф 50 000 намерений / 150 000 связей, короткие пути 1–6 шагов и повторяющиеся пути 30 шагов. Бюджеты p95 полного чтения, удержания очереди и задержки команды — 150 мс за месяц / 1 250 мс за год; подготовка курсоров измеряется отдельно. Эти замеры не вводят пользовательских ограничений.
- **Excluded change scope:** Фазы 2–4: вид «Через связи», статистика отдельного намерения, переходы к ней и каталог дневных выборов на дату.

### U3 · Согласованное состояние видимой Главной

- **Work items:** ["1.6","1.7","1.11","1.12"]
- **Requirements and scenarios:** ["Период статистики на Главной","Согласование статистики с изменениями","Состояния получения статистики","ADR-0027: перечитывание только при видимости"]
- **Affected boundary:** Корневая Главная → модель страницы → подтверждения команд графа и местная дата.
- **Implementation target:** ["lib/src/app/home/home_page.dart","lib/src/statistics/application/statistics_read_contract.dart","lib/src/statistics/presentation/home_statistics_state.dart","lib/src/statistics/presentation/home_statistics_view_model.dart","lib/src/statistics/presentation/home_statistics_view_model.g.dart","test/app/home_statistics_app_flow_test.dart","test/statistics/presentation/home_statistics_reconciliation_test.dart","test/statistics/presentation/home_statistics_view_model_test.dart"]
- **Applicable constraints and non-goals:** Месяц и год независимы, вид общий; состояние сохраняется в пределах запуска. Подтверждённое изменение и смена местной даты делают выдачу устаревшей, скрытая Главная не начинает чтения. Видимость означает выбранную корневую вкладку без страницы или диалога поверх. Старые ответы не заменяют новые; загруженная часть каталога обновляется целиком с сохранением прокрутки и различимым состоянием обновления.
- **Excluded change scope:** Фазы 2–4: вид «Через связи», статистика отдельного намерения, переходы к ней и каталог дневных выборов на дату.

### U4 · Доступная статистика Главной и её включение в приложение

- **Work items:** ["1.8","1.9","1.10","1.11","1.12"]
- **Requirements and scenarios:** ["Главная показывает статистику вклада","Период статистики на Главной","Каталог элементов Главной","Состояния получения статистики","Локализация и доступность статистики"]
- **Affected boundary:** Пользователь Главной → выбор периода, сводка, каталог и команды повтора; существующая корневая навигация.
- **Implementation target:** ["dart_test.yaml","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/app/home/home_page.dart","lib/src/statistics/presentation/home_statistics_content.dart","lib/src/statistics/presentation/home_statistics_period_selector.dart","lib/src/statistics/presentation/home_statistics_state.dart","mise.toml","test/app/home_statistics_app_flow_test.dart","test/app/navigation/app_navigation_accessibility_test.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/navigation/app_start_page_test.dart","test/statistics/presentation/home_statistics_content_test.dart","test/statistics/presentation/home_statistics_period_selector_test.dart"]
- **Applicable constraints and non-goals:** Доступны три вида, сводка, точное число элементов, доли, архивные отметки и автоматические порции. RU/EN, клавиатура, семантика и увеличенный текст сохраняют числа и команды. Отказ не превращается в пустую статистику; обычный повтор допустим только при недоступности. Начальный запуск и существующая навигация сохраняют поведение.
- **Excluded change scope:** Фазы 2–4: вид «Через связи», статистика отдельного намерения, переходы к ней и каталог дневных выборов на дату.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный ревьюер /root/isolated_final_review проверил объединение U1–U4: все 58 путей кода, тестов и конфигурации, перечисленных в Implementation target. Ему переданы нейтральное намерение, точный base/head и границы; артефакты планирования, история, прежние замечания и отчёт не передавались. Полнота подтверждена его итоговым перечнем путей. F1 перепроверено координатором по зафиксированной вершине. |
| OpenSpec conformance | Complete | Маппинг всех 12 задач и 14 коммитов завершён; строгая OpenSpec-валидация успешна. На чистом checkout reviewed head прошли полный check: форматирование, анализ, 2 490 основных тестов, два нагрузочных профиля и четыре теста Widgetbook. Codegen-check прошёл на чистом 5030d7f5a835eb4ce4b959649dda2fafe958e3e3; отличие от reviewed head — только этот отчёт, исходный код и тесты идентичны. F1 нарушает явные требования о различимом состоянии прежних данных. |
| Code quality | Complete | Все 58 путей кода, тестов и конфигурации и необходимые неизменённые зависимости проверены на корректность, читаемость, архитектуру, безопасность и производительность. Подтверждён один дефект F1; отдельного подтверждённого избыточного поведения не найдено. Свежие 40 нагрузочных серий прошли согласованные числовые бюджеты. |

## Findings

### F1 · Medium — Признак обновления и его отказа скрыт при глубокой прокрутке

- **Evidence:** В reviewed head `lib/src/statistics/presentation/home_statistics_content.dart:70–73` помещает единственный признак обновления в обычный `SliverToBoxAdapter` перед каталогом; сообщения обновления и отказа выбираются на строках 133–145. Каталог на строках 101–110 не передаёт это состояние своим строкам. Прокрутка сбрасывается только при смене периода или вида (строки 40–51). Модель сохраняет подтверждённую выдачу во время обновления (`home_statistics_view_model.dart:237–248`) и его отказа (строки 322–331). Достижимый сценарий: пользователь загружает каталог, прокручивает его далеко вниз, уходит с Главной, подтверждает изменение дневного выбора и возвращается. Старые строки остаются в видимой области, а сообщение об обновлении, затем о его отказе находится выше экрана. AppBar не показывает это состояние (`lib/src/app/home/home_page.dart:70`). Тест `test/statistics/presentation/home_statistics_content_test.dart:357–379` проверяет сохранение глубокой прокрутки при обновлении, но не видимость признака; возврат с изменением при сохранённой прокрутке покрыт `test/app/home_statistics_app_flow_test.dart:56`. Это противоречит `openspec/changes/add-contribution-statistics/specs/contribution-statistics/spec.md:158–167,179–182`: прежние данные должны оставаться с различимым признаком обновления либо его неудачи. `liveRegion` у сообщения не обеспечивает визуально различимый признак за пределами экрана; общий presenter результатов команд не представляет отказы чтения статистики.
- **Evidence revisions:** ["c77a621c68f39a69c52c6b4eca279441aba7c6dc"]
- **Impact:** Пользователь может принять прежние вклады за актуальные после подтверждённого изменения. При отказе чтения это продолжается до успешного перечитывания или прокрутки вверх; отказ и допустимый повтор остаются незаметными.
- **Required outcome:** При сохранённой глубокой прокрутке пользователь, видящий прежние строки, различает обновление и отказ обновления; допустимый повтор остаётся доступен. Позиция каталога, прежние данные и согласованная замена загруженной части сохраняются. Проверка должна воспроизводить этот достижимый сценарий и проверять воспринимаемое состояние в видимой области.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/statistics/presentation/home_statistics_content.dart","test/statistics/presentation/home_statistics_content_test.dart","test/app/home_statistics_app_flow_test.dart"]

## Review coverage

Инвентаризация и границы.

Проверен сохранённый диапазон `d4be9173ff9c86c5fe2be4fd81786ab4778b51f7..c77a621c68f39a69c52c6b4eca279441aba7c6dc`, а не текущее движение ветки. Все 60 путей из инвентаризации учтены: два изменённых артефакта планирования служат контекстом, остальные 58 входят в объединение U1–U4. Общие файлы связывают единицы в одну общую группу: контракт — U1/U3, чтение SQLite — U1/U2, HomePage и сквозные тесты — U3/U4; файлы не делились на конкурирующие фрагменты diff. Нераспределённых и посторонних изменений нет.

Контекст сопоставлен с committed proposal, четырьмя delta-specs, design, adr, plan, tasks, CONTEXT.md, контрактом локальных данных и применимыми ADR. Фазы 2–4 не выдаются за обязательства Phase 1. Контракт видимости не расширялся на отдельное требование о фоне приложения. Согласованная в design/tasks нагрузка не превращалась в ограничение допустимых путей и числа выборов. Существующего implementation-review.md перед первым сохранением не было.

Покрытие задач.

Каждый ID из workflow связан как минимум с одной единицей. Диапазоны 1.5 и 1.10 включают вспомогательные коммиты; полные SHA находятся в Review target и следующей таблице коммитов.

Задача ID 1, номер 1.1: единицы U1, коммит или диапазон 49477b9. Периоды, ограничения запроса, неизменяемость; test/statistics/application/.

Задача ID 2, номер 1.2: единицы U2, коммит или диапазон e5adb97. Состав события и безопасная запись; diagnostics_sink_test.dart.

Задача ID 3, номер 1.3: единицы U1, U2, коммит или диапазон c766bd9. Настоящий SQLite: read_test, read_failure_test; общая очередь и диагностика.

Задача ID 4, номер 1.4: единицы U1, коммит или диапазон e528d68. Расширение репозитория, делегирование обёрток и явный отказ fallback; анализ и регрессионный набор.

Задача ID 5, номер 1.5: единицы U2, коммит или диапазон e528d68..313124b. Оба коммита диапазона, включая 287d412; профили, независимый эталон, p95 и включение в check.

Задача ID 6, номер 1.6: единицы U3, коммит или диапазон 1fe7e8d. home_statistics_view_model_test.dart: независимые периоды, вид, порции и устаревшие ответы.

Задача ID 7, номер 1.7: единицы U3, коммит или диапазон 36ec2b5. home_statistics_reconciliation_test.dart: подтверждения, скрытие, дата и атомарная замена.

Задача ID 8, номер 1.8: единицы U4, коммит или диапазон 019804e. ARB, generated localizations и проверки RU/EN.

Задача ID 9, номер 1.9: единицы U4, коммит или диапазон 8e44ae7. home_statistics_period_selector_test.dart: доступные состояния, клавиатура и крупный текст.

Задача ID 10, номер 1.10: единицы U4, коммит или диапазон 8e44ae7..15251c1. Оба коммита диапазона, включая 861eb61; content_test.dart, порции и отказы; остаточный дефект F1.

Задача ID 11, номер 1.11: единицы U3, U4, коммит или диапазон 33e289c. home_statistics_app_flow_test.dart: реальный граф, навигация, диалог, часы и повторное открытие файла.

Задача ID 12, номер 1.12: единицы U1–U4, коммит или диапазон c77a621. Свежие CLI-проверки текущей сессии; готовность ограничена F1 и явно указанной проверкой на устройстве.

Покрытие коммитов.

Все целевые коммиты рассмотрены в заданном порядке; назначение изменений сопоставлено с конечным снимком, задачами и тестами. Коммиты с одними изменениями планирования или отметок проверок также учтены.

Коммит 1 — `49477b9f6ea8dea484ec815db891fdecc2a3895c`: задача 1.1, единицы U1. Типизированные периоды, меры и контракт порций.

Коммит 2 — `e5adb9793eda31f84837bfb57674f416c8264517`: задача 1.2, единицы U2. Событие и безопасное кодирование диагностики.

Коммит 3 — `c766bd91d46c383b3cb7f8a98f7d5cc9038f7730`: задача 1.3, единицы U1, U2. Агрегаты SQLite, сводка, курсоры, отказы и диагностика.

Коммит 4 — `e528d68e6be90bc7256091ceaf6686f919c4715e`: задача 1.4, единицы U1. Общий интерфейс и совместимость тестовых реализаций.

Коммит 5 — `287d41244c42617e51baefcbdbd47af6bbae03ab`: задача 1.5, единицы U2. Согласованные бюджеты и границы доказанной нагрузки в design.md; контекст планирования.

Коммит 6 — `313124be79cbba8aba3a9440967a4cbaef32c7df`: задача 1.5, единицы U1, U2. Оптимизация чтения, наблюдатель транзакций, нагрузочные профили и последовательный check.

Коммит 7 — `1fe7e8d73530e3b5d3e92368689f76c59d931162`: задача 1.6, единицы U3. Состояние периода, вида и порций.

Коммит 8 — `36ec2b5081a555b9d2f9c70bd5353c4dc4b86b7f`: задача 1.7, единицы U3. Ревизии, местная дата, видимость и замена загруженной части.

Коммит 9 — `019804ee9cb234658f4e1791ce57928b28f19445`: задача 1.8, единицы U4. RU/EN и сгенерированные локализации.

Коммит 10 — `8e44ae739f16abccd7e6a669c3b30cfa66522bb5`: задача 1.9, единицы U4. Доступный выбор месяца и года.

Коммит 11 — `861eb6162e1e086484822e4800899e9ac094c5db`: задача 1.10, единицы U4. Сводка и строки каталога.

Коммит 12 — `15251c1dfc9cff2264c3c1785c85d0c9b8ac9f37`: задача 1.10, единицы U4. Состояния чтения, порции и widget-проверки.

Коммит 13 — `33e289c265cc5e8cd26ab3493df6efb0b24c4549`: задача 1.11, единицы U3, U4. Подключение корневой Главной и сквозные сценарии.

Коммит 14 — `c77a621c68f39a69c52c6b4eca279441aba7c6dc`: задача 1.12, единицы U1–U4. Отметка готовности; сопоставлена с фактическими проверками и F1, сама по себе не доказывает готовность.

Покрытие поведения.

Меры, месяц/год, границы календаря, местная дата и независимые периоды. Свидетельство: statistics_period_test.dart, statistics_read_contract_test.dart, home_statistics_view_model_test.dart. Проверены инварианты, переходы и неизменяемые результаты.

Три вида по сохранённому пути, самостоятельные дубликаты, архивирование и готовность. Свидетельство: drift_statistics_read_test.dart на настоящем SQLite. Проверены засчитывание, сводка, текущие названия/архив и отсутствие исключения сохранённых оснований.

Порядок, точное число элементов, ключевые порции, ревизия и эпоха. Свидетельство: drift_statistics_read_test.dart, statistics_read_contract_test.dart. Проверены равные ключи на границах, отсутствие повторов/пропусков и отказ устаревшего продолжения.

Каталог, доли, отсутствие доли при нулевом вкладе, пустой вид. Свидетельство: home_statistics_content_test.dart, drift_statistics_read_test.dart. Нули и пустота различаются с загрузкой/отказом; строки содержат числа и архивные отметки.

Скрытая Главная, подтверждения команд, смена даты и устаревшие ответы. Свидетельство: home_statistics_reconciliation_test.dart, home_statistics_app_flow_test.dart. Чтения подавляются при скрытии; показ обновляет данные, загруженная часть заменяется согласованно.

Обновление и отказ при сохранении старых чисел и прокрутки. Свидетельство: home_statistics_reconciliation_test.dart, home_statistics_content_test.dart, home_statistics_app_flow_test.dart. Модель сохраняет данные и позицию; видимость признака при глубокой прокрутке не обеспечена — F1.

Недоступность, повреждение, неизвестный отказ и повтор по категории. Свидетельство: drift_statistics_read_failure_test.dart, home_statistics_content_test.dart. Отказ не маскируется нулями; начальная ошибка, обновление и следующая порция различаются, с оговоркой F1.

RU/EN, семантика, клавиатура и текст 3×. Свидетельство: home_statistics_period_selector_test.dart, home_statistics_content_test.dart, app_navigation_accessibility_test.dart. Проверены локализованные числа/названия, доступные состояния и команды; проверка реальным диктором на устройстве отдельно не заявляется.

Диагностика без содержимого графа. Свидетельство: diagnostics_sink_test.dart и типизированное событие. Поля ограничены видом, этапом, длительностью и категорией; исходные ошибки, даты, идентификаторы, период и числа не передаются.

Стоимость первых/поздних порций и задержка команды. Свидетельство: drift_statistics_read_cost_test.dart, contribution_statistics_fixture.dart, database_transaction_observer_test.dart, mise.toml. Методика и независимый эталон проверены; все 40 серий текущего замера прошли согласованные бюджеты.

Совместимость общей границы и навигации. Свидетельство: Изменённые обёртки/fallback, lifecycle/navigation-тесты, home_statistics_app_flow_test.dart. Реальные обёртки делегируют чтение; неиспользуемое чтение не подменено пустым успехом; состояние корневой страницы сохраняется в пределах запуска.

Качество и необходимость.

Корректность проверялась от сохранённых дневных выборов до строк: параметры SQL передаются как значения, агрегаты ограничивают выдачу, сводка и названия получаются в одной транзакции, продолжение связано с ревизией. Общая очередь, соединение и источник ревизий сохраняются; миграции и хранимые сводки не добавлены. Разделение периодов, результата и статусов выражено типами. Новый fallback нужен существующим тестовым реализациям расширенного интерфейса и возвращает явный отказ; делегирующие обёртки сохраняют настоящее поведение.

Проверены происхождение отказов, безопасное представление и ограничения диагностики, ленивое построение списка, ограниченная материализация и смысл каждого нового набора тестов. SQL-фикстура и наблюдатель транзакций обслуживают согласованный замер, а отдельный шаг check устраняет конкуренцию тестовых процессов в этой методике. Повторные проверки сохранённых цепочек, новые пользовательские настройки и неподтверждённые запасные механизмы не требуются и не добавлены. F1 относится к представлению уже имеющегося состояния, а не требует нового продуктового решения.

Проверки текущей сессии.

Полный check и строгая OpenSpec-валидация запущены в рабочем checkout указанного reviewed head: перед началом HEAD совпадал с ним, дерево было чистым. Codegen-check выполнен на чистом 5030d7f5a835eb4ce4b959649dda2fafe958e3e3, который добавляет только implementation-review.md; это подтверждено сравнением с reviewed head. Отчёт не входит в delivery target; исходный код и тесты в рамках review не менялись.

Команда `git --literal-pathspecs diff --check d4be9173ff9c86c5fe2be4fd81786ab4778b51f7 c77a621c68f39a69c52c6b4eca279441aba7c6dc` — exit 0.
Команда `mise exec --no-deps -- openspec validate add-contribution-statistics --strict --no-interactive --json` — exit 0, valid=true, issues=[].
Команда `TMPDIR="$PWD/.dart_tool/statistics-temp" mise run --skip-tools check` — exit 0: форматирование 574 файлов без изменений, проверка CI scope, анализ без замечаний, 2 490 основных тестов, два нагрузочных теста и четыре теста Widgetbook. Все 40 нагрузочных серий завершены, каждая с тремя прогревами и 40 повторами; p95 удержания очереди / полного чтения / задержки команды максимум 78,930 / 79,098 / 85,198 мс за месяц и 1 065,094 / 1 065,263 / 1 194,518 мс за год. Это ниже бюджетов 150 / 1 250 мс. Подготовка последнего годового курсора измерена отдельно: максимум p95 1 415,002 мс у короткого профиля и 1 054,419 мс у длинного; бюджет относится к одному чтению, а не сумме предварительных порций.
Команда `MISE_AUTO_INSTALL=false mise run --skip-tools codegen-check` — exit 0. Повторены gen-l10n, build_runner и dump схемы Drift; сохранённые артефакты не изменились, дерево осталось чистым. Инструменты не устанавливались и не обновлялись.
Команда `node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/add-contribution-statistics/implementation-review.md` — exit 0: формат v1, одно замечание, принятых рисков нет. Выполняется после каждого изменения отчёта; перед коммитами также проверяется `git diff --cached --check`.

Запущенного приложения/DTD в окружении не обнаружено. По предусмотренному в 1.12 варианту используется CLI-проверка. На устройстве не подтверждены hot reload/restart, runtime errors, ручной проход RU/EN с увеличенным текстом и экранным диктором, а также отзывчивость интерфейса на устройстве средней производительности. Локальные нагрузочные замеры не выдаются за замеры устройства или CI.

Передача результата.

F1 остаётся открытым для последующих этапов разрешения замечаний. Код и тесты не исправлялись; планирование и записанная история задач не менялись, новые задачи не добавлялись. Отметки готовности 1.10–1.12 не отменяют подтверждённый дефект представления F1. Принятия остаточного риска человеком нет.
