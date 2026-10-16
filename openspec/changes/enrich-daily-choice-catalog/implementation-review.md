# OpenSpec Implementation Review: enrich-daily-choice-catalog

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Incomplete
**Coverage limitations:** Ожидаются окончание полного mise run check и проверка воспроизводимости generated-файлов через mise run codegen-check.
**Summary:** Проверены все 15 целевых коммитов и все 10 задач фазы 2. Подтверждено одно замечание низкой важности F1: основные секции не сообщают вспомогательным технологиям роль заголовка. Принятых остаточных рисков нет. Вывод относится к каталогу фазы 2; действие флажка и удаление выполнения из редактора относятся к фазе 3.

## Review target

- **Baseline ref:** ae96b8dc60206f7d66bada6329485aaaba35e84e
- **Base commit:** ae96b8dc60206f7d66bada6329485aaaba35e84e
- **Reviewed head:** 6895af1e7c558db1b9f2a574748f7509a2353a41
- **Target commits:** ["df68a74f52234ce8ae584616bfa9cc68e14c053f","515c121ef63f6e168c2e4e9d3aa76bc631c39678","7cc9b437664771ed9693428e6a65c814ac0532a7","3563903d143237da2ff9ec6cd44fec4f5219ac38","44141e3f9eeace2dba77d2c3984b03b3def844d9","0d862d87b8f2fbc646b8e71de377a72a48933bf1","87498698a7a23efdcd934f6cf556fb00f3e8f95a","5588f8f374de55948cf5ceec32fe41dc14aa34b9","e97b31113ad705dc81fe58ad86b559f3941f5611","44d2b1e06a7f0919964b660b1cbb679f91c923b4","dcd5133c8477297e02db24fd58f123e4805d5290","238897562acdfeeb4ae8db7cd814c6aae110e52f","99478c4759a7bf1f4c4d855572f82af5fa9128ac","acefd67c4570270d6cde53be3e05d855bfd84e8d","6895af1e7c558db1b9f2a574748f7509a2353a41"]
- **Reviewable paths:** ["dart_test.yaml","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/application/daily_choice_catalog.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_snapshot_assembly.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart","lib/src/graph/data/drift_personal_graph_repository_daily_choice_catalog.dart","mise.toml","openspec/changes/enrich-daily-choice-catalog/tasks.md","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_flow_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_statistics_app_flow_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/navigation/app_shell_layout_test.dart","test/app/navigation/app_shell_state_test.dart","test/daily_choice/application/daily_choice_catalog_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_card_flow_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_cards_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_snapshot_assembly_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart","test/data/local/migrations/file_backed_migration_test.dart","test/graph/application/selected_relations_test.dart","test/graph/data/drift_daily_choice_catalog_test.dart","test/graph/data/drift_daily_choice_diagnostics_test.dart","test/graph/data/drift_daily_choice_groups_test.dart","test/graph/data/drift_daily_choice_read_cost_test.dart","test/graph/data/drift_selected_relations_test.dart","test/graph/data/file_backed_graph_durability_test.dart","test/graph/data/file_backed_tag_durability_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart","test/support/daily_choice_catalog_controls.dart"]
- **OpenSpec change:** enrich-daily-choice-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/enrich-daily-choice-catalog/tasks.md"]

## Reviewed increment

### U1 · Ограниченные секции читают сохранённые данные в полном порядке

- **Work items:** ["2.1","2.2","2.3","2.6","2.10"]
- **Requirements and scenarios:** ["Краткая карточка дневного выбора / данные проекции и размер пути","Группировка и порядок дневных выборов / Время, приоритет и создание последовательно определяют порядок","Группировка и порядок дневных выборов / Следующая порция учитывается при показе группы на весь день","Каталог дневных выборов по дате и секциям / Совпадающие записи открываются независимо","Подтверждённые результаты и безопасные ошибки дневного выбора"]
- **Affected boundary:** PersonalGraphRepository, SQLite и потребители общей краткой проекции.
- **Implementation target:** ["lib/src/daily_choice/application/daily_choice_catalog.dart","lib/src/graph/data/drift_personal_graph_repository_daily_choice_catalog.dart","test/daily_choice/application/daily_choice_catalog_test.dart","test/graph/application/selected_relations_test.dart","test/graph/data/drift_daily_choice_catalog_test.dart","test/graph/data/drift_daily_choice_diagnostics_test.dart","test/graph/data/drift_daily_choice_groups_test.dart","test/graph/data/drift_daily_choice_read_cost_test.dart","test/graph/data/drift_selected_relations_test.dart","test/intention/presentation/details/intention_details_page_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart","test/long_term_relation/presentation/neighborhood/blocking_relations_selection_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart","test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart"]
- **Applicable constraints and non-goals:** Ровно одна дата и одно выполнение в запросе; весь день предшествует полуночи, затем время, P1–P4 и неизменяемый порядок создания. Количество и наличие времени учитывают всю секцию; материализация ограничена порцией и структурой её путей. Дубликаты самостоятельны; архивированные данные допустимы. ADR-0009, ADR-0006 и контракт ADR-0033.
- **Excluded change scope:** Новая схема и миграция реализованы ранее; полный граф и незагруженные пути не становятся объектом чтения.

### U2 · Обе секции публикуются согласованной парой и отражают подтверждённые изменения

- **Work items:** ["2.4","2.5","2.7","2.10"]
- **Requirements and scenarios:** ["Секции выполнения дневных выборов / Начальное состояние секций","Каталог дневных выборов по дате и секциям / Отказ загрузки не меняет выбранный день","Каталог дневных выборов по дате и секциям / Поздний ответ не возвращает прежнюю дату","Каталог дневных выборов по дате и секциям / Выбор дня без записей","Отметки дней по выполнению всех дневных выборов / Перенос даты меняет отметки обоих дней"]
- **Affected boundary:** Модель экземпляра каталога, ограниченные чтения, завершения координатора, подробности и отдельная модель отметок.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_snapshot_assembly.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_snapshot_assembly_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","lib/src/daily_choice/application/daily_choice_catalog.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart"]
- **Applicable constraints and non-goals:** Одна опубликованная ревизия пары; отдельные продолжения; нет транзакции между пользовательскими действиями. Пересборка сохраняет прежний объём каждой секции и прежние согласованные данные при обновлении или отказе. Смена поколения и закрытие исключают позднюю публикацию. Владельцы команд, диагностики и отметок сохраняются; ADR-0009 и ADR-0033.
- **Excluded change scope:** Изменение выполнения проверяется существующей командой; управление флажком не входит в фазу 2.

### U3 · Карточки, календарь и навигация доступны в независимых экземплярах каталога

- **Work items:** ["2.5","2.8","2.9","2.10"]
- **Requirements and scenarios:** ["Краткая карточка дневного выбора / Краткая карточка сохраняет доступ к полному описанию и пути","Группировка и порядок дневных выборов / Единственная группа на весь день не получает заголовок","Группировка и порядок дневных выборов / Следующая порция учитывается при показе группы на весь день","Каталог дневных выборов по дате и секциям / Выбор дня сразу меняет выдачу","Отметки дней по выполнению всех дневных выборов / Сворачивание невыполненных не меняет отметку","Локализация и доступность дневного выбора","Начальное состояние и сохранение календаря каталога","Каталог дневных выборов на заданную дату / Открытие на дату не меняет корневой каталог","Выбор года и месяца в календаре каталога","Заголовок выбранного дня каталога / Выдача нового дня показывается с начала"]
- **Affected boundary:** Корневой каталог и обычные страницы на дату, ru/en, вспомогательные технологии, переходы к подробностям и редактору.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_flow_test.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_statistics_app_flow_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/navigation/app_shell_layout_test.dart","test/app/navigation/app_shell_state_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_card_flow_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_cards_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart","test/daily_choice/presentation/daily_choice_creation_flow_test.dart","test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart","test/support/daily_choice_catalog_controls.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart"]
- **Applicable constraints and non-goals:** Каноническая формулировка, сохранённые время/P1–P4/размер пути и описание; только описание ограничено двумя строками. Заголовки групп учитывают всю свою секцию и не повторяются на границе порций. Раскрытие независимо и сохраняется при смене даты; новая дата начинает выдачу и прокрутку заново. Просмотр календаря не перечитывает секции. Экземпляры и возврат сохраняют состояние; ADR-0025 и ADR-0028 используются как контекст существующих границ.
- **Excluded change scope:** Флажок выполнения и его жизненный цикл, удаление выполнения из редактора — фаза 3. Неподдерживаемые маленькие окна не добавлены в обязательства.

### U4 · Полная проверка фазы сохраняет миграционные и файловые тесты без конкуренции сборок

- **Work items:** ["2.10"]
- **Requirements and scenarios:** ["Phase 2 / Ready to advance","Локальная долговечность и проверка целостности дневных выборов / существующие проверки миграции и перезапуска"]
- **Affected boundary:** Локальный и CI-запуск проверок, вложенные Flutter-процессы и общие нативные артефакты SQLite.
- **Implementation target:** ["dart_test.yaml","mise.toml","test/data/local/migrations/file_backed_migration_test.dart","test/graph/data/file_backed_graph_durability_test.dart","test/graph/data/file_backed_tag_durability_test.dart"]
- **Applicable constraints and non-goals:** Полный check включает обе взаимодополняющие группы тестов; наборы с вложенным Flutter запускаются последовательно. Содержимое прежних проверок миграции и долговечности сохраняется. Инструменты не устанавливаются и не обновляются.
- **Excluded change scope:** Изменений поведения приложения или хранения эта единица не вводит.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные контексты с fork_turns=none и implementation-decision-review: /root/independent_catalog проверил объединение U1–U3, ровно 50 путей; /root/independent_checks — U4, ровно 5 путей. Общие изменённые контракты и модель объединяют U1–U3. Переданы нейтральное намерение, полные границы и точные commit IDs; planning, описания коммитов и прежний отчёт скрыты. У обоих Coverage: Complete; подтверждён только F1. Generated-файлы и механические фикстуры проверены инструментом целиком, diff и затронутый контекст — вручную. |
| OpenSpec conformance | Incomplete | Артефакты и код прочитаны из сохранённых Git-снимков; все задачи и коммиты сопоставлены ниже. mise exec --no-deps -- openspec validate enrich-daily-choice-catalog --strict --json: exit 0, 1/1 valid, issues: []. Статический анализ выполнен без замечаний; полный mise run check и повторная генерация ещё не завершены. Этот проход остаётся Incomplete до получения результатов. |
| Code quality | Complete | Координатор применил пять осей code-review-and-quality ко всем 55 delivery-путям: корректность данных и границ порций, читаемость и типы, владение ревизией/командами/состоянием, параметризованный SQL и безопасные ошибки, ограниченность материализации и индекс. Проверены реальные потребители проекции, каталог, подробности, отметки, навигация и тестовые конфигурации. git diff --check для точного base..head: exit 0. Замечание доступности объединено в F1; неподтверждённых дефектов и избыточных механизмов не заявлено. |

## Findings

### F1 · Low — Основные секции не представлены заголовками для экранного диктора

- **Evidence:** В lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart:222–240 обе секции строятся с Semantics(expanded: ...) и ListTile с названием и onTap, но без роли заголовка. Временные группы того же экрана на строках 320–323 явно задают header: true. test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart:62–92 проверяет порядок названий и роль заголовка только у даты; daily_choice_catalog_page_test.dart:162–201 проверяет раскрытие, но не роль заголовков секций.
- **Evidence revisions:** ["6895af1e7c558db1b9f2a574748f7509a2353a41"]
- **Impact:** При навигации экранного диктора по заголовкам человек не может перейти к секциям «Не выполненные» и «Выполненные» как к разделам. Ему остаётся последовательная навигация через карточки, что особенно неудобно при нескольких загруженных порциях. Названия, обычная активация и состояние раскрытия доступны; потеря данных не обнаружена.
- **Required outcome:** Обе секции должны передавать вспомогательным технологиям роль заголовка вместе с доступной командой и состоянием раскрытия; проверка доступности должна обнаруживать потерю этой роли.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart","2.5","2.8"]

## Review coverage

Проверка относится только к ae96b8dc60206f7d66bada6329485aaaba35e84e..6895af1e7c558db1b9f2a574748f7509a2353a41. Все 56 путей учтены: tasks.md — planning evidence, остальные 55 — точный delivery-поднабор U1–U4 (код, тесты, локализация, generated-файлы и конфигурация). Несопоставленных и посторонних изменений нет. Границы review units заданы целыми файлами; пересечение U1–U3 проверено одним независимым рецензентом, отдельная U4 — другим. Состояние рабочего дерева при фиксации цели было чистым, HEAD совпадал с Reviewed head; пользовательских незакоммиченных данных не включено.

Контекст соответствия — proposal.md, specs/daily-choice-management/spec.md, design.md, adr.md, plan.md и tasks.md этого изменения, CONTEXT.md и применимые ADR, прочитанные на сохранённом head. CLI status и instructions apply использованы для определения графа и путей артефактов; содержимое доказательств взято из Git. Применённые ограничения единого репозитория, ревизии и причинного порядка согласованы с ADR-0009 и ADR-0006; контракт пары — с ADR-0033. Фаза 1 служит контекстом ранее реализованных полей; её неизменённый код не добавлен в текущую цель. Требования флажка явно отделены от результатов фазы 2.

Каждая задача включена по содержимому реализации и проверки, независимо от наличия записанного taskCommitRange. Четыре сохранённых диапазона задач 14–17 соблюдены; остальные задачи и коммиты вне этих диапазонов сопоставлены по содержимому. ID, номера, описания, порядок и завершённые отметки tasks.md сохранены.

Задача 2.1 (ID 14) → U1. df68a74f52234ce8ae584616bfa9cc68e14c053f: Расширенная проекция, её общий построитель и реальные потребители: время/P2/полное описание/число намерений.

Задача 2.2 (ID 15) → U1. 515c121ef63f6e168c2e4e9d3aa76bc631c39678: Полный SQL-порядок, сводка всей секции, отдельное продолжение и проверка исходного запроса.

Задача 2.3 (ID 16) → U1. 7cc9b437664771ed9693428e6a65c814ac0532a7: Трассировка материализованных строк, выбранные пути и EXPLAIN QUERY PLAN через индекс схемы 2.

Задача 2.4 (ID 17) → U2. 3563903d143237da2ff9ec6cd44fec4f5219ac38: Сборка пары, разные целевые объёмы, восемь попыток, отказ и отмена поколения.

Задача 2.5 (ID 18) → U2, U3. 44141e3f9eeace2dba77d2c3984b03b3def844d9: Подключение state/model/body, независимые секции и продолжения, сохранение прежней пары.

Задача 2.6 (ID 19) → U1, U2. 0d862d87b8f2fbc646b8e71de377a72a48933bf1: Обязательная дата и выполнение; удаление прежнего API и перенос всех производственных вызовов.

Задача 2.7 (ID 20) → U2. 87498698a7a23efdcd934f6cf556fb00f3e8f95a: Интеграция реальных команд, подробностей и отметок; перемещение за границу порции и отказ пересборки.

Задача 2.8 (ID 21) → U3. 5588f8f374de55948cf5ceec32fe41dc14aa34b9: Группы времени, карточки, полное описание и дубликаты; ru/en, семантика и крупный текст.

Задача 2.9 (ID 22) → U3. e97b31113ad705dc81fe58ad86b559f3941f5611: Оба входа сохраняют раскрытие при смене даты; независимые экземпляры, возврат и новый процесс.

Задача 2.10 (ID 23) → U1, U2, U3, U4. 44d2b1e06a7f0919964b660b1cbb679f91c923b4, dcd5133c8477297e02db24fd58f123e4805d5290, 238897562acdfeeb4ae8db7cd814c6aae110e52f, 99478c4759a7bf1f4c4d855572f82af5fa9128ac, acefd67c4570270d6cde53be3e05d855bfd84e8d, 6895af1e7c558db1b9f2a574748f7509a2353a41: Сквозной сценарий, адаптация существующих app-проверок и последовательное выполнение Flutter-process наборов; итоговая отметка checkpoint.


Все 15 Target commits проверены и сопоставлены в порядке workflow. Коммиты df68a74f, 515c121e, 7cc9b437 и 3563903d соответствуют четырём сохранённым taskCommitRanges. 44141e3f, 0d862d87, 87498698, 5588f8f3 и e97b3111 реализуют задачи без recorded ranges. Вне task-сессий: 44d2b1e0 проверяет сохранённый 18:00/P2 от карточки до правки; dcd5133c сохраняет сценарий замены выполненного выбора; 23889756 — открытие выполненного дубликата после перезапуска; 99478c47 — доступность конца выдачи над панелью; acefd67c — изоляцию пересборки native assets; 6895af1e фиксирует завершение 2.10. Эти коммиты включены в U3/U4 и checkpoint, а не исключены из-за отсутствия диапазона задачи.

Сценарии и проверяемые регрессии связаны со следующими доказательствами на Reviewed head:

Сохранённые поля, размер пути 2/4, полный текст и общие потребители: daily_choice_catalog.dart:89–141; drift_personal_graph_repository_daily_choice_catalog.dart:345–373; drift_daily_choice_catalog_test.dart:117; drift_daily_choice_groups_test.dart и drift_selected_relations_test.dart проверяют общий построитель.

Весь день → полночь → время, P1–P4 и создание, сводка остатка, дубликаты: drift_daily_choice_catalog_test.dart:313,357,397,608; путь с архивированными участниками — :690; повреждение следующей порции — :233. drift_daily_choice_read_cost_test.dart:312 проверяет строки/структуру путей и индекс без сортировки в памяти.

Начальная пара, разные ревизии, объём каждой секции, отказы и отмена: daily_choice_catalog_snapshot_assembly_test.dart:15,66,88,108,130,165,177,191,236,243,257,279; модель: daily_choice_catalog_view_model_test.dart:43,64,100,131,172,212,270,288,321. Уровни проверяют разные границы: сборка ограниченных чтений и публикация/завершения/поколения модели.

Подтверждённое изменение, перенос даты/выполнения, создание/удаление, отказ перечитывания: daily_choice_catalog_details_integration_test.dart:46,271,450 использует реальный SQLite и coordinator, сверяет подробности и отметки, сохранённую команду после отказа и перемещение за загруженную границу. Отсутствие будущего флажка не считается пробелом текущей фазы.

Заголовок всего дня по всей секции, одна группа через границу порций, описание в две строки: daily_choice_catalog_cards_test.dart:14,122 выполняется в ru/en; daily_choice_catalog_body.dart:264–375 использует сводку и общий порядок. Полное описание и путь доступны из карточки в daily_choice_catalog_card_flow_test.dart:14; полный дубликат открывается по отдельному ID в daily_choice_creation_flow_test.dart.

Выбор нового дня, отсутствие записей, временный/неповторяемый отказ и поздний ответ: daily_choice_catalog_page_test.dart проверяет каждое наблюдаемое состояние; daily_choice_catalog_view_model_test.dart:288 исключает позднее продолжение. initial/refresh/page failures сохраняют категории и показывают повтор только для временного отказа.

Начальное раскрытие, отсутствие ложной пустоты после сворачивания, доступность и раскладка: daily_choice_catalog_page_test.dart:153; daily_choice_catalog_accessibility_test.dart, daily_choice_catalog_layout_test.dart и daily_choice_catalog_supported_layout_test.dart сохраняют доступность действий и нижнюю границу поддержки. Семантическая роль заголовков секций остаётся недостатком F1.

Оба входа, независимость страниц, возврат, дата/раскрытие/объём/прокрутка и новый процесс: daily_choice_date_catalog_page_test.dart:32,117,215,289,380; app_shell_state_test.dart; intention_statistics_catalog_scenarios.dart; daily_choice_app_lifecycle_test.dart:619. Новый день получает первые порции, прежнее раскрытие и начало прокрутки.

Календарный просмотр, отметки и их отказ не меняют выдачу: daily_choice_catalog_day_marks_test.dart, daily_choice_calendar_period_picker_test.dart, daily_choice_catalog_lifecycle_test.dart; реальный перенос даты согласован интеграционным тестом. Календарь и заголовок дня сохраняют существующие границы.

Полнота файловых проверок без конкурирующих Flutter-сборок: Три библиотеки с вложенными Flutter-процессами помечены flutter_process; mise.toml последовательно выполняет все остальные тесты и затем эти наборы с concurrency=1. Тела прежних проверок не изменены; исключённых из полного gate наборов нет.


SQL остаётся параметризованным; новые пользовательские значения не попадают в диагностику. Новых зависимостей, каналов обновления, долговечных ревизий, полных выборок ради заголовков и самостоятельных механизмов ошибок нет. Проверки ограниченности материализации, SQL-порядка, согласования модели и UI различаются по наблюдаемым регрессиям; неподтверждённые излишества не добавлены как замечания.

Полный gate и воспроизводимость генерации ещё проверяются. Окончательный результат верификации будет внесён до завершения этапа.

DTD listDtdUris не обнаружил запущенного приложения; используется предусмотренная задачей 2.10 альтернатива CLI. Ручная проверка на устройстве и hot reload не выполнялись. Это не скрывает незавершённую обязательную проверку: её состояние отдельно указано в Pass coverage.

Код, тесты и планирующие артефакты в этом review-stage не исправлялись: openspec-review-implementation ограничивает аудит отчётом. F1 остаётся нерешённым и передан последующим этапам разрешения находок; риск не принят и исправление не объявлено выполненным. Новые задачи не добавлены, история всех 23 существующих задач сохранена. Отчёт фиксирует текущий диапазон и не означает завершения фазы 3 или всего изменения, разрешения на push, слияние либо архивацию.
