# OpenSpec Implementation Review: add-inline-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Компонент календаря Phase 1 выполняет контракт дат, независимость выбора от просмотра, перелистывание, смену представления, локализацию, доступность и размещение в общей прокрутке на настоящем `table_calendar`. Проверки проекта на рецензируемой ревизии проходят. Изоляция страничной механики библиотеки от `PageStorage` страницы-хоста закреплена в решении 3 design и передана в незавершённые задачи 1.12 и 1.13 `tasks.md`. Автоматическая проверка календарных дат в поясе America/New_York с переходом на летнее время передана в незавершённые задачи 1.14 и 1.15. Основа адаптера — публичный `TableCalendarBase` с ячейками и подписями дней недели, которые строит компонент, — и причина отказа от готовой ячейки `TableCalendar` описаны в решении 3 design. Активных находок и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 63c18a0eae9a3dac0efc227b71097db23b74cfde
- **Base commit:** 63c18a0eae9a3dac0efc227b71097db23b74cfde
- **Reviewed head:** 10fcc63519550f87319fbabe21d5c88b760dad20
- **Target commits:** ["d05c697777cc844df70f259da43d8d1ceb680481", "5d733991a0a83251867fc21c8f14e1f657f52dc8", "704268df1e9f0eeaa7554acfd0c07507c6e7d967", "73ee3952869ba2515b498a1464280b4f417e3b8c", "c07087a3f493b2707c1513233061c8310da6238c", "aa6e29b4294520855e8a2f3abe0ca413efdef279", "5f361e31379f672d37d0867bf78b18920237e99c", "a339361a3e282a2d0f81e6d73e214a27aac75b0a", "591798899135a11f091d7a7e0b2405584c866ef2", "441fb525217167e8c54ba16ffcce1cef90f8749e", "4a816b773f53adc5fca275400c648d97d200d26d", "10fcc63519550f87319fbabe21d5c88b760dad20"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/daily_choice/domain/calendar_date.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_text_metrics.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart", "openspec/changes/add-inline-daily-choice-calendar/tasks.md", "pubspec.lock", "pubspec.yaml", "test/app/localization/locale_resolution_test.dart", "test/daily_choice/domain/calendar_date_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_text_metrics_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart", "widgetbook/pubspec.lock"]
- **OpenSpec change:** add-inline-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-inline-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Воспроизводимая зависимость календаря для приложения и Widgetbook

- **Work items:** ["1.1", "1.11"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога — технологическая основа table_calendar из proposal", "design: решение 3 — версия зависимости и lockfile", "design: решение 5 — прямая зависимость intl при прямом использовании"]
- **Affected boundary:** Разрешение зависимостей приложения и вложенного пакета Widgetbook, проверка lockfile в CI
- **Implementation target:** ["pubspec.yaml", "pubspec.lock", "widgetbook/pubspec.lock"]
- **Applicable constraints and non-goals:** Библиотеку выбрал proposal; инструменты закреплены на Flutter 3.47.1; оба lockfile проверяются через `--enforce-lockfile`; пакеты, импортируемые кодом приложения напрямую, объявляются прямыми зависимостями. Обновлять несвязанные зависимости не требуется.
- **Excluded change scope:** Примеры Widgetbook для календаря в Phase 1 не входят.

### U2 · Управляемый компонент календаря и календарная семантика дат

- **Work items:** ["1.2", "1.3", "1.4", "1.11"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога", "Сценарий: Неделя пересекает границу года", "Сценарий: Високосный день доступен для выбора — контракт компонента"]
- **Affected boundary:** Будущий потребитель компонента (страница каталога и модель представления) и пользователь, выбирающий день
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "lib/src/daily_choice/domain/calendar_date.dart", "test/daily_choice/domain/calendar_date_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart"]
- **Applicable constraints and non-goals:** Выбранная дата и просмотр принадлежат потребителю; компонент не хранит копию фильтра, не обращается к хранилищу и не читает часы. Даты остаются `CalendarDate` без времени и часового пояса во всём диапазоне 0001-01-01 — 9999-12-31. Библиотечные типы не входят во внешний контракт (ADR-0017).
- **Excluded change scope:** Обязательная дата `DailyChoiceCatalogSelection`, источник локального сегодня, подключение к `DailyChoiceCatalogPage` и согласование выдачи относятся к Phase 2.

### U3 · Перелистывание периодов и смена представления без выбора дня

- **Work items:** ["1.6", "1.7", "1.8", "1.11"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога", "Сценарий: Свайп недели сохраняет фильтр — контракт компонента", "Сценарий: Свайп месяца сохраняет фильтр — контракт компонента", "Сценарий: Раскрытие сохраняет просмотр соседнего периода — контракт компонента", "Сценарий: Сворачивание сохраняет дату просмотра — контракт компонента", "Сценарий: Выбор дня сохраняет раскрытое представление — контракт компонента"]
- **Affected boundary:** Будущий потребитель компонента и пользователь, просматривающий соседние недели и месяцы
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart"]
- **Applicable constraints and non-goals:** Перелистывание и смена представления меняют только просмотр и не порождают выбора. Точная дата просмотра сохраняется при раскрытии и сворачивании. Вертикальные жесты не переключают представление. У краёв диапазона нет перехода к несуществующему периоду.
- **Excluded change scope:** Доказательство отсутствия чтений каталога при просмотре относится к Phase 2.

### U4 · Локализованный и доступный календарь

- **Work items:** ["1.5", "1.9", "1.11"]
- **Requirements and scenarios:** ["Локализация и доступность дневного выбора", "Сценарий: Выбранный день различим для экранного диктора", "Сценарий: Календарём можно управлять без свайпа — контракт компонента", "Сценарий: Смена локали сохраняет календарь — контракт компонента"]
- **Affected boundary:** Пользователи экранного диктора и других вспомогательных технологий на русском и английском языках
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_ru.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "test/app/localization/locale_resolution_test.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "pubspec.yaml"]
- **Applicable constraints and non-goals:** Локаль выбирают правила приложения с английским fallback. Названия месяцев и дней недели берутся из средств локализации, без собственных списков. Выбранность и «сегодня» различимы и при совпадении. Команды выполнимы без свайпа. Сгенерированные файлы локализации не редактируются вручную.
- **Excluded change scope:** Ручной проход экранным диктором на реальной странице каталога выполняется в Phase 2.

### U5 · Общая прокрутка и увеличенный текст

- **Work items:** ["1.10", "1.11"]
- **Requirements and scenarios:** ["Встроенный недельный и месячный календарь каталога — общая вертикальная прокрутка", "Сценарий: Увеличенный текст сохраняет доступность выбора — контракт компонента"]
- **Affected boundary:** Пользователь узкого телефона с увеличенным системным размером текста и содержимое страницы под календарём
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_text_metrics.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_text_metrics_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart"]
- **Applicable constraints and non-goals:** Календарь — элемент одной вертикальной прокрутки, без вложенной вертикальной прокрутки, окна или фиксированной высоты. Масштаб текста не уменьшается. Перелистывание не отключается. Окончательное оформление задаётся отдельно и не меняет контракт.
- **Excluded change scope:** Размещение на реальной странице каталога относится к Phase 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер по `implementation-decision-review` для группы перекрытия U1–U5 (общие `pubspec.yaml` и `daily_choice_calendar.dart`). Цель: объединённый набор из 23 путей доставки и тестов на 63c18a0eae9a3dac0efc227b71097db23b74cfde..10fcc63519550f87319fbabe21d5c88b760dad20. Brief без артефактов планирования, сообщений коммитов и прошлых находок. Ревьюер сообщил покрытие Complete. Анализ статический: исходники цели, неизменённого контекста, `table_calendar` 3.3.0 и Flutter 3.47.1; тесты по границам стадии он не запускал. |
| OpenSpec conformance | Complete | Все команды выполнены в рабочей копии с HEAD = 10fcc63519550f87319fbabe21d5c88b760dad20 и чистым деревом. `mise run --skip-tools check`: формат, CI scope, lockfile Widgetbook и `flutter analyze` прошли; `flutter test` — 4106 из 4107. Единственный отказ — тайм-аут подпроцесса в неизменённом `test/graph/data/file_backed_graph_durability_test.dart`; отдельный повторный прогон файла: 26/26. Тесты Widgetbook запущены отдельно: 8/8. Календарные тесты с `TZ=UTC` и `TZ=America/New_York`: по 32/32. `mise run --skip-tools codegen-check`: код 0, дерево чистое. `flutter pub get --enforce-lockfile` для обоих пакетов прошёл. `openspec validate add-inline-daily-choice-calendar --strict --no-interactive` прошёл. `git diff --check` по диапазону: код 0. |
| Code quality | Complete | Линзы `code-review-and-quality` (корректность, читаемость, архитектура, безопасность, производительность) применены ко всем путям доставки на 10fcc63519550f87319fbabe21d5c88b760dad20. Сверка с исходниками `TableCalendarBase`, `CalendarCore` и `PageView`/`PageStorage`. Проверены поток событий выбора и просмотра, остановка перелистывания при смене режима, края диапазона, семантика, измерение высот и обновления lockfile. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Диапазон 63c18a0eae9a3dac0efc227b71097db23b74cfde..10fcc63519550f87319fbabe21d5c88b760dad20 содержит 12 коммитов и 24 пути; отчёт ревью из цели исключён. Все пути сопоставлены: `tasks.md` — свидетельство планирования (отметки 1.1–1.11), остальные 23 пути распределены по U1–U5, несопоставленных путей нет. Каждый целевой коммит отнесён к задаче. Коммит 591798899135a11f091d7a7e0b2405584c866ef2 (прямая зависимость `intl`) не меняет `tasks.md` и отнесён к критерию задачи 1.1 и к U4. Прослежено, что `intl` объявлен до первого импорта в 441fb525217167e8c54ba16ffcce1cef90f8749e. Коммиты 73ee3952869ba2515b498a1464280b4f417e3b8c и 10fcc63519550f87319fbabe21d5c88b760dad20 — проверочные задачи 1.4 и 1.11, только отметки в `tasks.md`; их заявления о проверках подтверждены повторным запуском.

Прочитаны proposal, дельта `daily-choice-management`, design, ADR manifest, plan, tasks, ADR-0017 и предыдущий отчёт ревью планирования; артефакты изменения в рабочей копии совпадают с рецензируемой ревизией. Требования Phase 1 сопоставлены с кодом и тестами: две формы календаря с понедельника, неделя на границе года, февраль 2027 и 2028 годов, 1900 и 2000 годы, оба предела 0001-01-01 и 9999-12-31 с недоступными позициями и нормализацией фокуса, ленивое построение крайних периодов. Также проверены разделение событий выбора и просмотра, повторный выбор, перестроение потребителя, перелистывание кнопками и свайпом у краёв, точная дата просмотра при раскрытии и сворачивании, прерывание анимаций и удаление во время перелистывания. Отдельно проверены локализация ru/en и fallback, полные доступные названия дней, признаки выбранного и сегодняшнего дня, обход в календарном порядке, доступная активация, высоты строк при масштабе 1 и 2,5 на экране 360×780 и достижимость содержимого под календарём. Будущие задачи Phase 2 (обязательная дата выборки, часы, подключение к странице, отсутствие чтений, навигация, ручной проход экранным диктором) не считались обязательствами этого приращения.

Код проверен на соответствие ADR-0017: `table_calendar` импортируется только в `daily_choice_calendar.dart`, а внешний контракт состоит из `CalendarDate`, `DailyChoiceCalendarViewport` и `DailyChoiceCalendarMode`. Компонент не освобождает контроллер библиотеки. Безопасность и производительность: новых входных данных, секретов и сетевых границ нет. Изменения lockfile ограничены `table_calendar` 3.3.0, транзитивным `simple_gesture_detector` 0.2.1 и переводом `intl` в прямые зависимости. Измерение высот выполняется только при перестроении. Отказ полного прогона в неизменённом тесте файлового хранилища графа связан с тайм-аутом подпроцесса под нагрузкой и при отдельном запуске не воспроизводится.
