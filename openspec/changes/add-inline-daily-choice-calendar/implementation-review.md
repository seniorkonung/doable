# OpenSpec Implementation Review: add-inline-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Изоляция страничной механики календаря от `PageStorage` страницы-хоста (1.12) работает. Регрессионный тест падает на базовой реализации и проходит на рецензируемой. Автоматическая проверка в America/New_York (1.14) ловит обе предусмотренные задачей регрессии и не проходит без перехода времени. Однако она не охватывает собственный расчёт границ видимого периода, от которого зависит доступность команд соседнего периода. Поэтому заявление 1.15 о том, что любая регрессия, зависящая от часового пояса, ломает обязательную проверку, подтверждено не полностью (F4, Low). Проверки проекта на рецензируемой ревизии проходят, кроме одного несвязанного порога задержки, который при отдельном повторе проходит. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 2d0effd2e3016e3cb01c63600aab0bebf1e676ec
- **Base commit:** 2d0effd2e3016e3cb01c63600aab0bebf1e676ec
- **Reviewed head:** 634b62ced06a0eb0ac3b178cffe2071bda6a7c69
- **Target commits:** ["527bc45d7850a40167dc6c5db4c426615dec9f3f", "b3a2b8f0aa0cbde57f1f829ac135007a69df11cd", "a595180d88fb2b4b9005294788ff98831cc8fa0b", "634b62ced06a0eb0ac3b178cffe2071bda6a7c69"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "openspec/changes/add-inline-daily-choice-calendar/tasks.md", "test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_time_zone_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_time_zone_worker.dart"]
- **OpenSpec change:** add-inline-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-inline-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Календарь показывает период потребителя под прокруткой с сохраняемым состоянием

- **Work items:** ["1.12", "1.13"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога — перелистывание меняет только период просмотра", "Начальное состояние и сохранение календаря каталога — сохранение просматриваемого периода и позиции прокрутки (контракт компонента)", "design: решение 3 — собственная область хранения страниц библиотеки"]
- **Affected boundary:** Будущий потребитель компонента — страница с общей прокруткой под `PageStorageKey` — и пользователь, перелистывающий недели и месяцы
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart"]
- **Applicable constraints and non-goals:** Компонент управляется потребителем: выбранная дата и viewport приходят извне, а наружу уходят только события. `table_calendar` и его хранение страниц не входят во внешний контракт (ADR-0017). После пересоздания период восстанавливается из viewport потребителя, а не из памяти библиотеки. Сохранение между процессами не добавляется.
- **Excluded change scope:** Подключение к `DailyChoiceCatalogPage`, проверки навигации оболочки и возврата из подробностей относятся к Phase 2.

### U2 · Календарная семантика дат автоматически проверяется в поясе с переходом на летнее время

- **Work items:** ["1.14", "1.15"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога — календарь не меняет дату из-за преобразования времени и часового пояса", "Сценарий: Високосный день доступен для выбора — календарная дата без времени и часового пояса", "design: решение 4 — технические даты в UTC без `toLocal`"]
- **Affected boundary:** Обязательный прогон `flutter test` и CI-проверка проекта как защита календарной семантики дат компонента и `CalendarDate`
- **Implementation target:** ["test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_time_zone_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_time_zone_worker.dart"]
- **Applicable constraints and non-goals:** Продуктовый код и поведение приложения не меняются. Дочерний `flutter test` следует образцу подпроцесса с `Pacific/Honolulu`, не запускает сам себя и падает без перехода времени. Прогон укладывается в 45-минутный job CI на ubuntu-24.04.
- **Excluded change scope:** Источник локального сегодня, таймер полуночи и проверки часов в модели каталога относятся к Phase 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер по `implementation-decision-review` для группы перекрытия U1+U2: юниты делят контекст `daily_choice_calendar.dart` и `daily_choice_calendar_test_support.dart`. Цель — объединённый набор из 6 путей доставки и тестов на 2d0effd2e3016e3cb01c63600aab0bebf1e676ec..634b62ced06a0eb0ac3b178cffe2071bda6a7c69. Brief без артефактов планирования, сообщений коммитов и прошлых находок. Ревьюер сообщил покрытие Complete для обоих юнитов и одну находку (F4). |
| OpenSpec conformance | Complete | Команды выполнены в рабочей копии с HEAD = 634b62ced06a0eb0ac3b178cffe2071bda6a7c69 и чистым деревом. `mise run --skip-tools check`: формат (521 файл, 0 изменений), CI scope, lockfile Widgetbook и `flutter analyze` прошли. `flutter test --concurrency=2` — 4116 из 4117 за 17:38, `daily_choice_calendar_time_zone_test.dart` и `daily_choice_calendar_page_storage_test.dart` выполнены и прошли. Единственный отказ — порог p95 ≤ 100 мс (факт 111 мс) в неизменённом `test/intention/data/drift_intention_repository_large_fixture_test.dart`, совпавший с параллельными прогонами ревью. Отдельный повтор файла: 5/5. Тесты Widgetbook после остановки задачи запущены отдельно: 8/8. `mise run --skip-tools codegen-check`: код 0, дерево чистое до и после. `openspec validate add-inline-daily-choice-calendar --strict --no-interactive`: valid. `git diff --check` по диапазону: код 0. В одноразовой копии ревизии повторены красно-зелёные проверки. 1.12: с базовой версией `daily_choice_calendar.dart` падают 5/5 тестов `PageStorage`, с рецензируемой — 5/5 проходят. 1.14: из `TZ=UTC` локальный `DateTime` в `_technicalDate` даёт +28 -8 в дочернем прогоне, `toLocal()` в `_calendarDate` даёт +6 -30, дочерний `Etc/UTC` падает в `setUpAll`. Без подмен проверка проходит. |
| Code quality | Complete | Линзы `code-review-and-quality` (корректность, читаемость, архитектура, безопасность, производительность) применены ко всем 6 путям доставки на 634b62ced06a0eb0ac3b178cffe2071bda6a7c69. Сверено с `TableCalendarBase` и `CalendarCore` из `table_calendar` 3.3.0 и с `PageStorage` из Flutter 3.47.1, а также с образцами подпроцессов `flutter test` в тестах хранилища. `analyze_files` по 6 путям: ошибок нет. |

## Findings

### F4 · Low — Проверка в America/New_York не охватывает расчёт границ видимого периода календаря

- **Evidence:** Компонент сам вычисляет границы видимого периода, отдельно от `table_calendar`. `_visiblePeriodStart` и `_visiblePeriodEnd` (`lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart:324-355`) строят `DateTime.utc(...)` напрямую, минуя `_technicalDate`. `_hasPreviousPeriod` и `_hasNextPeriod` (строки 316-321) сравнивают их с `_firstDay` и `_lastDay`, и от результата зависит доступность команд «Предыдущая/Следующая неделя/месяц» (строки 110-111). Дочерний прогон `daily_choice_calendar_time_zone_worker.dart` запускает только `daily_choice_calendar_boundaries_test.dart` и `calendar_date_test.dart`. Ни один из них не проверяет доступность этих команд. Её проверяют неизменённые `daily_choice_calendar_navigation_test.dart` (группа «края диапазона») и `daily_choice_calendar_accessibility_test.dart`, но они выполняются только в часовом поясе обычного прогона. Проверено в одноразовой копии 634b62ced06a0eb0ac3b178cffe2071bda6a7c69 с временной заменой `DateTime.utc` на `DateTime` в обеих ветках `_visiblePeriodStart`. Из `TZ=UTC` весь `flutter test test/daily_choice/presentation/catalog`, включая `daily_choice_calendar_time_zone_test.dart`, проходит (+170). С `TZ=America/New_York` падают 5 тестов навигации и доступности у первой недели и первого месяца диапазона. Код восстановлен.
- **Evidence revisions:** ["634b62ced06a0eb0ac3b178cffe2071bda6a7c69"]
- **Impact:** Регрессия, переводящая этот расчёт на локальное время процесса, проходит обязательную проверку проекта. Тогда в поясах западнее UTC команда «Предыдущая неделя/месяц» у 0001-01-01 становится доступной и объявляется экранному диктору, хотя перехода нет. Это противоречит заявлению 1.15, что регрессия, зависящая от часового пояса, ломает обязательную проверку. Вред ограничен краями диапазона и доступностью команд; даты не сдвигаются.
- **Required outcome:** Каждый расчёт дат календаря, результат которого может зависеть от часового пояса процесса, включая границы видимого периода и доступность команд соседнего периода у краёв диапазона, проверяется прогоном в America/New_York. Регрессия любого из них на локальное время роняет обязательный `flutter test`.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["openspec/changes/add-inline-daily-choice-calendar/tasks.md: 1.14, 1.15", "test/daily_choice/presentation/catalog/daily_choice_calendar_time_zone_worker.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart: _visiblePeriodStart, _visiblePeriodEnd"]

## Review coverage

Диапазон 2d0effd2e3016e3cb01c63600aab0bebf1e676ec..634b62ced06a0eb0ac3b178cffe2071bda6a7c69 содержит 4 коммита и 7 путей; отчёт ревью из цели исключён. `tasks.md` — свидетельство планирования (отметки 1.12–1.15), остальные 6 путей распределены по U1 и U2, несопоставленных путей нет. Каждый коммит отнесён к задаче: 527bc45d7850a40167dc6c5db4c426615dec9f3f — 1.12, b3a2b8f0aa0cbde57f1f829ac135007a69df11cd — проверочная 1.13, a595180d88fb2b4b9005294788ff98831cc8fa0b — 1.14, 634b62ced06a0eb0ac3b178cffe2071bda6a7c69 — проверочная 1.15. Предыдущий отчёт не содержал активных находок и принятых рисков; переносить нечего. Идентификатор F4 выбран после F1–F3 прежних ревью, на которые ссылаются коммиты планирования.

Прочитаны proposal, дельта `daily-choice-management`, design (решения 3, 4 и 6), ADR manifest, ADR-0017, plan и tasks; артефакты в рабочей копии совпадают с рецензируемой ревизией. Для U1 прослежен механизм: `PageView` библиотеки с контроллером по умолчанию (`keepPage`) записывает номер страницы в ближайший `PageStorage` под ключами `PageStorageKey` предков. Под прокруткой с ключом это была та же запись, что у смещения прокрутки. Собственный `PageStorage` компонента обрывает поиск ключей, поэтому календарь ничего не читает из хранилища предков и не пишет туда. Регрессионные тесты проверяют пересоздание после свайпа, кнопок и смены представления. Они проверяют видимые недели, подпись месяца, события нажатия дня и первого перелистывания, неделю 2026-09-28 — 2026-10-04 у нового экземпляра и восстановление смещения пересозданной прокрутки. Переработка `pumpCalendarConsumer` сохраняет прежнее поведение для существующих тестов: ключ прокрутки необязателен. `table_calendar` по-прежнему импортируется только в `daily_choice_calendar.dart`. Контракт рядом с кодом соответствует решению 3 design и ADR-0017.

Для U2 проверено, что дочерний прогон следует образцу подпроцессов `flutter test` в тестах хранилища. Он не входит в обычный набор (имя без `_test`) и не запускает родителя. Он требует код 0 и «All tests passed!», а при отказе или превышении 5 минут показывает вывод. Новые недели с понедельника по обе стороны переходов ловят подмену `_technicalDate`. Продуктовый код в a595180d88fb2b4b9005294788ff98831cc8fa0b не менялся. Будущие задачи Phase 2 (обязательная дата выборки, часы, подключение к странице, навигация, ручной проход экранным диктором) не считались обязательствами этого приращения.

Безопасность и производительность: новых входных данных, секретов, сетевых границ и зависимостей нет. Дочерний прогон добавляет около 9 секунд отдельно и укладывается в 45-минутный job CI. Как и существующие подпроцессы с `Pacific/Honolulu`, тест не помечен `slow` и выполняется также в `check-fast`.
