# OpenSpec Implementation Review: add-daily-choice-calendar-day-marks

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Независимая оценка решений, проверка соответствия OpenSpec и проверка качества завершены для всех 14 коммитов и задач 1.1–1.14. Все 54 изменённых пути учтены: 53 файла реализации и тестов, один артефакт планирования. Существенных незакрытых замечаний и принятых остаточных рисков нет. Полные проверки, воспроизводимость генерации и свежий profile-замер максимального окна прошли.

## Review target

- **Baseline ref:** 23f189023cfff137651aaed6e2ee97d7ea940553
- **Base commit:** 23f189023cfff137651aaed6e2ee97d7ea940553
- **Reviewed head:** 7e405c861abf1d3eadd945bb6e9d4a0c66d4d450
- **Target commits:** ["a9ccba25288b42dff8cc1ef16cfa87d3c26f4995", "71e090575c6cb79be27f929f136fb648703e65f9", "965dc6c6de51a0ab058aeb10f819bff5172ac75b", "da3b5c15322ac5f26349c8d16cd84af08bf378d1", "aa215181e66a8b4e94e6c84ee949f5a657ece729", "3df70ce199f4dc31c513dc5a208c095f5180c5bd", "5071e0375c57438c2189fb77935bafbe8cdf9173", "c88ac8a1595e936b8b927138c71906c3e6216e69", "bcb3e9ea22c946677e50aef155e244054b1519c7", "2e057bdf947cd3eb6265296718abfdc7a0f8abb1", "68504b2d04c22a285058dc7d822373c21bb9d25f", "57307cdf311a4cf762ae3f92eb6141383aebe2f9", "1e65762d0d881252732140cef0b2ddc2835aa86c", "7e405c861abf1d3eadd945bb6e9d4a0c66d4d450"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/daily_choice/application/daily_choice_day_statuses.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_daily_choice_day_statuses.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "openspec/changes/add-daily-choice-calendar-day-marks/tasks.md", "test/app/bootstrap/app_runtime_test.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/tag_app_lifecycle_test.dart", "test/app/tag_assignment_app_lifecycle_test.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/daily_choice/application/daily_choice_day_statuses_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/graph/application/graph_command_coordinator_relation_creation_test.dart", "test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart", "test/graph/data/drift_daily_choice_day_statuses_read_cost_test.dart", "test/graph/data/drift_daily_choice_day_statuses_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/long_term_relation/presentation/details/relation_details_test_support.dart", "test/long_term_relation/presentation/editor/editor_test_support.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/daily_choice_catalog_controls.dart"]
- **OpenSpec change:** add-daily-choice-calendar-day-marks
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-daily-choice-calendar-day-marks/tasks.md"]

## Reviewed increment

### U1 · Достоверные состояния дней из ограниченного снимка личного графа

- **Work items:** ["1.1", "1.2", "1.3", "1.4", "1.5", "1.14"]
- **Requirements and scenarios:** ["Отметки состояния дней календаря каталога", "Отметки показывают состояние каждого дня", "Фильтр выполнения не меняет отметку", "Обновление и отказ получения отметок календаря", "design: решения 2 и 6; Risks / Trade-offs", "ADR-0009", "ADR-0024"]
- **Affected boundary:** Сохранённые дневные выборы → прикладная граница личного графа → потребители состояний дней.
- **Implementation target:** ["lib/src/daily_choice/application/daily_choice_day_statuses.dart", "lib/src/graph/application/personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_daily_choice_day_statuses.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/app/bootstrap/app_runtime_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/tag_app_lifecycle_test.dart", "test/app/tag_assignment_app_lifecycle_test.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/daily_choice/application/daily_choice_day_statuses_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/graph/application/graph_command_coordinator_relation_creation_test.dart", "test/graph/application/graph_command_coordinator_relation_lifecycle_test.dart", "test/graph/data/drift_daily_choice_day_statuses_read_cost_test.dart", "test/graph/data/drift_daily_choice_day_statuses_test.dart", "test/graph/presentation/graph_reconciliation_checkpoint_test.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/long_term_relation/presentation/details/relation_details_test_support.dart", "test/long_term_relation/presentation/editor/editor_test_support.dart", "test/long_term_relation/presentation/editor/relation_form_test_support.dart", "test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart", "test/long_term_relation/presentation/participant_picker/participant_picker_test_support.dart", "test/shared/diagnostics/diagnostics_sink_test.dart"]
- **Applicable constraints and non-goals:** Включительный диапазон не больше 98 дней, все выборы даты независимо от фильтра и архивирования, одна ревизия транзакционного снимка, отказ целого чтения при обнаруженном повреждении. Не загружать пути ради отметок, не менять схему и данные, не вводить хранимую сводку. Диагностика содержит только исход, длительность и безопасную категорию отказа.

### U2 · Согласование отметок с просмотром и подтверждёнными ревизиями

- **Work items:** ["1.6", "1.7", "1.10", "1.14"]
- **Requirements and scenarios:** ["Отметки состояния дней календаря каталога", "Отметки соседней недели видны во время перелистывания", "Повторное перелистывание опережает получение отметок", "Обновление сохраняет прежние отметки", "Следующее получение убирает строку отказа", "design: решения 1, 3, 4 и 6", "ADR-0024", "ADR-0025"]
- **Affected boundary:** Просмотр календаря и завершения команд личного графа → модель отметок, живущая вместе со страницей.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window_test.dart", "lib/src/daily_choice/application/daily_choice_day_statuses.dart"]
- **Applicable constraints and non-goals:** Окно покрывает текущий и соседние периоды с обрезкой по CalendarDate. Только одно чтение одновременно; прежнее окно и старая ревизия не публикуются. Любая новая подтверждённая ревизия вызывает согласование независимо от вида команды. Прежние отметки сохраняются при ожидании и отказе; подписка и поздний ответ ограничены временем жизни модели. Выбранная дата, фильтр и выдача принадлежат существующей модели каталога.

### U3 · Доступное представление отметок и независимость выдачи каталога

- **Work items:** ["1.4", "1.8", "1.9", "1.10", "1.11", "1.12", "1.13", "1.14"]
- **Requirements and scenarios:** ["Локализация и доступность дневного выбора", "Отметки состояния дней календаря каталога", "Обновление и отказ получения отметок календаря", "Встроенный недельный и месячный календарь каталога", "Начальное состояние и сохранение календаря каталога", "design: решения 1, 5 и 6", "ADR-0017 с уточнением ADR-0025"]
- **Affected boundary:** Страница каталога → компонент календаря → пользователь и вспомогательные технологии; сохранённая страница при переходах приложения.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/support/daily_choice_catalog_controls.dart", "lib/src/daily_choice/application/daily_choice_day_statuses.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart"]
- **Applicable constraints and non-goals:** Галочка для всех выполненных выборов, кружок при наличии невыполненного, отсутствие отметки у пустого дня. Дни соседнего месяца, выбранный и сегодняшний дни, русский и английский языки и увеличенный текст сохраняют доступность. Отказ отметок даёт одну пассивную строку под шапкой без действий и всплывающего сообщения. Просмотр не читает выдачу и не меняет её условия; реальные команды обновляют отметки и скрытого каталога. Счётчики дней, сохранение отметок между запусками и постоянный журнал диагностики исключены.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий агент `/root/independent_decision_review`, fork_turns=none, навык implementation-decision-review. Ему переданы нейтральные намерения U1–U3, точные SHA и только объединённые 53 пути реализации/тестов. Единицы имеют общие изменённые контракты, поэтому проверены одной группой. Артефакты планирования, история, предыдущие замечания и отчёт не передавались. Восстановлен полный diff группы, прочитано производственное ядро и новые тесты; generated l10n проверены структурно и по diff. Результат: No substantive findings, Coverage: Complete. |
| OpenSpec conformance | Complete | Артефакты прочитаны через git show на 7e405c861abf1d3eadd945bb6e9d4a0c66d4d450; все 14 задач и коммитов сопоставлены ниже. В чистой рабочей копии того же head выполнены mise run check: 2399 корневых тестов, 4 Widgetbook-теста, форматирование и анализ без ошибок; mise run codegen-check: exit 0, изменений нет. mise exec --no-deps -- openspec validate add-daily-choice-calendar-day-marks --strict --json: valid=true, issues=[]. Свежий profile-замер описан ниже. |
| Code quality | Complete | Применены пять направлений code-review-and-quality к полному набору 53 путей: корректность, читаемость, архитектура, безопасность и производительность. Проверены вызывающие стороны, очередь/транзакция/ревизия, реальные SQLite-сценарии, жизненный цикл Riverpod, гонки окон и ответов, UI/семантика, локализация, диагностика, делегирование и управляемые тестовые реализации. git diff --check 23f189023cfff137651aaed6e2ee97d7ea940553 7e405c861abf1d3eadd945bb6e9d4a0c66d4d450: exit 0. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверка выполнена в `/home/seniorkonung/.paseo/worktrees/1id27gtb/frosty-deer` на неизменённом `7e405c861abf1d3eadd945bb6e9d4a0c66d4d450`. До аудита рабочая копия была чистой; проверки и генерация её не изменили. Незакоммиченных данных, исключённых из доказательств реализации, нет. Исключённых или несопоставленных путей диапазона нет.

**Планирование и границы.** Discovery зафиксировал точный диапазон и порядок коммитов. Для повторного вызова помощника использован временный executable с `exec mise exec --no-deps -- openspec "$@"`. Первый вызов помощника до обнаружения этого внутреннего вызова использовал его стандартный executable OpenSpec; отклонение ограничено двумя read-only запросами discovery. Последующие OpenSpec-команды выполнялись указанным пользователем способом. Проверены status и read-only instructions apply. На сохранённом head изучены proposal.md, specs/daily-choice-management/spec.md, design.md, adr.md, plan.md, tasks.md, предметный CONTEXT.md, применимые ADR и каноническая спецификация. Неизменённые контекстные файлы не включены в цель ревью. Изменение tasks.md содержит завершение существующих задач и явное исключение живой проверки экранным диктором по указанию пользователя; это не доказательство фактического озвучивания.

**Полный набор доставки.** Implementation target единиц U1–U3 задаёт точный набор 53 файлов доставки и тестов. Общие пути сохранены целиком, без разделения по строкам: это причина единого изолированного прохода. Единственный изменённый путь вне набора доставки — tasks.md, учтённый как planning evidence. Внешне расположенные тестовые дополнения нужны для совместимости PersonalGraphRepository; реальные обёртки делегируют чтение, управляемые реализации удерживают ответ, а неиспользуемые операции явно запрещены. Посторонних изменений нет.

**Задачи и каждый целевой коммит.** Для каждой строки проверен её индивидуальный диапазон от предыдущего коммита (для первой — от Base commit) до указанного коммита включительно, затем итоговое поведение на Reviewed head. Отметки завершения, номера, описания и порядок задач сохранены.

Задача 1.1 (Task ID 1), коммит `a9ccba25288b42dff8cc1ef16cfa87d3c26f4995`. U1: Типизированный диапазон и неизменяемая карта; daily_choice_day_statuses_test.dart проверяет 1/98/99 дней, обратный диапазон и копирование результата.

Задача 1.2 (Task ID 2), коммит `71e090575c6cb79be27f929f136fb648703e65f9`. U1: Событие чтения и точный безопасный набор полей; diagnostics_sink_test.dart проверяет начало, успех и отказ.

Задача 1.3 (Task ID 3), коммит `965dc6c6de51a0ab058aeb10f819bff5172ac75b`. U1: Одна агрегатная выборка, транзакция и ревизия; drift_daily_choice_day_statuses_test.dart и drift_daily_choice_day_statuses_read_cost_test.dart.

Задача 1.4 (Task ID 4), коммит `da3b5c15322ac5f26349c8d16cd84af08bf378d1`. U1, U3: Метод общей границы и все изменённые реализации интерфейса; анализ и полный набор тестов подтверждают совместимость.

Задача 1.5 (Task ID 5), коммит `aa215181e66a8b4e94e6c84ee949f5a657ece729`. U1: Коммит содержит только завершение проверки; её утверждения повторно проверены SQLite-тестами, диагностикой и отсутствием diff схемы/миграций.

Задача 1.6 (Task ID 6), коммит `3df70ce199f4dc31c513dc5a208c095f5180c5bd`. U2: UTC-арифметика окна; daily_choice_calendar_day_marks_window_test.dart проверяет месяцы, високосность, смену года и обе границы CalendarDate.

Задача 1.7 (Task ID 7), коммит `5071e0375c57438c2189fb77935bafbe8cdf9173`. U2: Модель/состояние/generated provider; семь сценариев модели проверяют окно, ревизии, объединение чтений, отказы, повтор и освобождение.

Задача 1.8 (Task ID 8), коммит `c88ac8a1595e936b8b927138c71906c3e6216e69`. U3: Три ключа обеих локалей, generated l10n; семантика на двух языках и повторная генерация.

Задача 1.9 (Task ID 9), коммит `bcb3e9ea22c946677e50aef155e244054b1519c7`. U3: Компонент и ячейка; day_marks/accessibility/layout-тесты проверяют оба представления, состояния дня, пассивный отказ и масштаб текста.

Задача 1.10 (Task ID 10), коммит `2e057bdf947cd3eb6265296718abfdc7a0f8abb1`. U2, U3: Коммит содержит только завершение проверки; совместимость готового состояния модели и входов календаря подтверждена каталогом тестов и анализом.

Задача 1.11 (Task ID 11), коммит `68504b2d04c22a285058dc7d822373c21bb9d25f`. U3: Одна точка изменения просмотра и постоянный ключ модели; страничные тесты проверяют частичный жест, задержку соседних окон и независимость выдачи.

Задача 1.12 (Task ID 12), коммит `57307cdf311a4cf762ae3f92eb6141383aebe2f9`. U3: Реальный SQLite и coordinator: создание, выполнение/снятие, перенос и удаление; скрытый каталог и возврат с другого экрана.

Задача 1.13 (Task ID 13), коммит `1e65762d0d881252732140cef0b2ddc2835aa86c`. U3: Два страничных сценария отказов: первый ответ, сохранённые отметки, фильтр, выбор, перелистывание, команда и восстановление без общего сообщения.

Задача 1.14 (Task ID 14), коммит `7e405c861abf1d3eadd945bb6e9d4a0c66d4d450`. U1, U2, U3: Коммит завершает проверки фазы и уточняет запрет запуска диктора. Полный check, codegen-check, strict validate и profile максимального окна подтверждены в этой сессии.


**Сценарии дельты.** Названия файлов ниже относятся к test/daily_choice/presentation/catalog/, если не указан иной каталог. Каждый сценарий сопоставлен с конкретной поведенческой проверкой; существующие проверки неизменённого поведения используются как контекст, без расширения целевого diff.

Сценарий «Путь читается экранным диктором»: Существующий test/daily_choice/presentation/details/daily_choice_details_page_test.dart: «показывает порядок и типы всего пути с архивными состояниями», включая дерево семантики.

Сценарий «Выбранный день различим для экранного диктора»: daily_choice_calendar_accessibility_test.dart: «различает сегодняшний 2026-10-04 и выбранный 2026-10-05 при последовательном чтении».

Сценарий «Состояние дня читается экранным диктором»: daily_choice_calendar_accessibility_test.dart: «состояние дня дополняет дату и „сегодня“, сохраняя выбранность; строка отказа читается под шапкой без действий», обе локали.

Сценарий «Календарём можно управлять без свайпа»: daily_choice_calendar_accessibility_test.dart: «доступная активация команд и дня без свайпа даёт те же события, что нажатие».

Сценарий «Увеличенный текст сохраняет доступность выбора»: daily_choice_calendar_layout_test.dart: проверки экрана 360×780 и масштаба 2.5; новые проверки размещения отметок и строки отказа.

Сценарий «Отметки показывают состояние каждого дня»: daily_choice_calendar_day_marks_test.dart: «галочка, пустой кружок и день без отметки…», оба представления; реальное агрегирование отдельно проверяет drift_daily_choice_day_statuses_test.dart.

Сценарий «Фильтр выполнения не меняет отметку»: daily_choice_catalog_day_marks_test.dart: «отметки всех выборов не зависят от фильтра выдачи и выбранного дня».

Сценарий «Выполнение последнего невыполненного выбора ставит галочку»: test/app/navigation/app_shell_state_test.dart: возврат со страницы изменения; согласование существующей модели до возврата и значок после него.

Сценарий «Перенос даты меняет отметки обоих дней»: daily_choice_catalog_details_integration_test.dart: «реальный каталог, отметки и подробности согласуют изменения графа», включая перенос единственного выбора пустого дня.

Сценарий «Отметки соседней недели видны во время перелистывания»: daily_choice_catalog_day_marks_test.dart: «соседняя неделя показывает отметки до завершения жеста…» с проверкой видимой отметки до отпускания жеста.

Сценарий «Повторное перелистывание опережает получение отметок»: daily_choice_catalog_day_marks_test.dart: октябрь → ноябрь → декабрь с удержанным ответом; 30 ноября сохраняется, 15 декабря появляется после ответа текущего окна.

Сценарий «Обновление сохраняет прежние отметки»: daily_choice_calendar_day_marks_view_model_test.dart: новая ревизия при прежней отметке, затем результат с новой отметкой; состояние ожидания проверено до завершения ответа.

Сценарий «Отказ получения показывает пассивную строку»: daily_choice_catalog_day_marks_test.dart: «задержка и отказ обновления сохраняют прежние отметки и выдачу…».

Сценарий «Следующее получение убирает строку отказа»: daily_choice_catalog_day_marks_test.dart: «отказ первого чтения отметок не мешает фильтру и выбору дня; перелистывание внутри окна восстанавливает отметки без смены выдачи».


**Корректность и необходимость.** В lib/src/graph/data/drift_personal_graph_repository_daily_choice_day_statuses.dart:13–17 чтение входит в общую очередь и транзакцию; строки 54–79 агрегируют только нужный диапазон и возвращают его ревизию. Проверка допустимой календарной даты нужна: существующий SQL CHECK задаёт форму строки, но допускает несуществующий день; такой случай воспроизведён на SQLite. Недопустимые значения выполнения не объявлены новым достижимым сценарием: схема уже требует NOT NULL и integer 0/1. Отбрасывание старого окна и ревизии проверено по модели и управляемым ответам. Дополнительные чтения после посторонних команд следуют принятому для изменения контракту. Дублирующего источника состояния, новых зависимостей, миграций, утечек пользовательских данных в диагностике и непараметризованного SQL нет. Новые тесты защищают разные границы: SQL, согласование, отображение и подключение страницы; случайные перестановки UI и хранения не выдаются за предметные требования.

**Свежая проверка стоимости.** Выполнено из widgetbook/ через существующий Linux launcher: `mise exec --no-deps -- flutter run --profile --no-pub -d linux -t /tmp/daily-choice-review-profile.dart`, exit 0. Временный проверочный код вне репозитория импортировал реальные репозиторий, диагностику и существующую синтетическую fixture. Все versioned входы соответствовали Reviewed head; рабочая копия оставалась чистой. Устройство: Linux x64, Ubuntu 26.04.1 LTS; SQLite in-memory, 200 000 дневных выборов на 10 000 дат, по 20 выборов на дату, 400 000 шагов пути. Запрашивалось максимальное окно 2026-08-31 — 2026-12-06, 98 дней; каждый ответ содержит 98 состояний. Длительности получены через DailyChoiceDayStatusesReadDiagnosticsEvent, не внешним таймером.

Первое: 1 чтений; минимум 0,948 мс, медиана 0,948 мс, максимум 0,948 мс.

Повторное при просмотре: 10 чтений; минимум 0,488 мс, медиана 1,2065 мс, максимум 1,639 мс.

После подтверждённой команды: 10 чтений; минимум 0,526 мс, медиана 0,9065 мс, максимум 1,302 мс.


После каждой команды дополнительно проверено совпадение ревизии её подтверждения и снимка отметок; отказов событий нет. Пределы вывода: измерение характеризует этот Linux-процесс и in-memory SQLite, не является обещанием задержки мобильного устройства или дискового ввода-вывода. Свежий SQLite-тест стоимости отдельно подтверждает поиск по индексу, единственный SELECT, не более 98 материализованных агрегатов и отсутствие чтения путей на большом наборе. Оснований добавлять покрывающий индекс по проверенному поведению не обнаружено.

**Визуальные и эксплуатационные пределы.** Временные журналы и снимки предыдущего этапа `/tmp/daily-choice-1.14-linux-profile*.log`, month-ru-2x.png и partial-week-ru-2x.png изучены как дополнительные невёрсионированные материалы; их старые измерения не подменяют свежий запуск. Текущие автоматические тесты подтверждают раскладку, частичный свайп и семантику обеих локалей. Экранный диктор не запускался: фактическое озвучивание исключено записанным указанием пользователя, а не объявлено проверенным.

**Передача результата.** Изменение кода, тестов и планирования по результатам аудита не потребовалось. Новые задачи не добавлены; все существующие завершённые задачи сохранены. Незакрытых замечаний для следующих этапов разрешения и решений о принятии риска нет. Этот отчёт фиксирует доказательства ревью; реализация дополнительных возможностей, публикация, слияние и архивирование в этап не входят.
