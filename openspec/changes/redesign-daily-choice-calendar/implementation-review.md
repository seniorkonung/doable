# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все девять коммитов и задачи 1.1–1.9 фазы 1. Подтверждённых замечаний, принятых остаточных рисков и нерешённых решений нет. Компоненты подготовлены в модуле основ и Widgetbook; поведение приложения сохранено.

## Review target

- **Baseline ref:** 153bde064e44037e714a227694188779c0bc8323
- **Base commit:** 153bde064e44037e714a227694188779c0bc8323
- **Reviewed head:** d1ec5cb34cf338f229cbf51a43c519a6fd455b4f
- **Target commits:** ["77bc0f7843b02f4f00b2d9543f4249658b7ae0b6","3f984a24318919b6758e13b3aa59311ea59e4e65","704aa5fa50874569488e8386ab9a1bf51cdbcbec","b4ca2aab828c09fbddf463f4847e5da4be18a840","004391e1af84161c0a6dd7a50d82ae5a9b88e74b","30c9a583172fcf3fbca33bfcfcb5809e0453135e","68d6494854a908d63c539ee9dd894afd609b009c","6902880afa349cd5934ee814515f388d1488887c","d1ec5cb34cf338f229cbf51a43c519a6fd455b4f"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart","lib/src/design_system/components/calendar_handle.dart","lib/src/design_system/components/calendar_header.dart","lib/src/design_system/components/day_heading.dart","lib/src/design_system/components/day_mark.dart","lib/src/design_system/components/month_grid_day.dart","lib/src/design_system/components/month_grid_weekday.dart","lib/src/design_system/components/notice.dart","lib/src/design_system/components/week_strip_day.dart","lib/src/design_system/doable_metrics.dart","lib/src/design_system/doable_shadows.dart","lib/src/design_system/doable_theme.dart","lib/src/design_system/text_metrics.dart","openspec/changes/redesign-daily-choice-calendar/tasks.md","test/design_system/calendar_handle_test.dart","test/design_system/calendar_header_test.dart","test/design_system/day_heading_test.dart","test/design_system/month_grid_day_test.dart","test/design_system/notice_test.dart","test/design_system/text_metrics_test.dart","test/design_system/week_strip_day_test.dart","widgetbook/lib/calendar/calendar_handle_use_cases.dart","widgetbook/lib/calendar/calendar_header_use_cases.dart","widgetbook/lib/calendar/day_heading_use_cases.dart","widgetbook/lib/calendar/month_grid_day_use_cases.dart","widgetbook/lib/calendar/week_strip_day_use_cases.dart","widgetbook/lib/catalog.dart","widgetbook/lib/messages/notice_use_cases.dart"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Основы оформления и представления дней календаря

- **Work items:** ["1.1", "1.2", "1.3", "1.4", "1.9"]
- **Requirements and scenarios:** ["Phase 1: компоненты календаря и каталога сверены с макетами", "design.md: решения 1 и 7", "ADR-0029", "ADR-0030", "daily-choice-management: Локализация и доступность дневного выбора — подготовка компонентов"]
- **Affected boundary:** Модуль основ, существующие потребители измерения текста и пользователи примеров дней недели и месяца, включая вспомогательные технологии.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart","lib/src/design_system/components/day_mark.dart","lib/src/design_system/components/month_grid_day.dart","lib/src/design_system/components/month_grid_weekday.dart","lib/src/design_system/components/week_strip_day.dart","lib/src/design_system/doable_metrics.dart","lib/src/design_system/doable_shadows.dart","lib/src/design_system/doable_theme.dart","lib/src/design_system/text_metrics.dart","test/design_system/month_grid_day_test.dart","test/design_system/text_metrics_test.dart","test/design_system/week_strip_day_test.dart","widgetbook/lib/calendar/month_grid_day_use_cases.dart","widgetbook/lib/calendar/week_strip_day_use_cases.dart","widgetbook/lib/catalog.dart"]
- **Applicable constraints and non-goals:** Готовые тексты, признаки, отметка и обработчики поступают от потребителя; предметных типов, провайдеров и локализации приложения в основах нет. Размеры дизайна минимальные, высоты учитывают текущий текст. Перенос измерения сохраняет поведение приложения. Общий каталог Widgetbook пересекается с U2, поэтому независимый обзор выполнен одной группой по объединению полных файлов.
- **Excluded change scope:** Подключение компонентов к приложению, шестинедельные сетки и расширение окна отметок принадлежат фазе 2; выбор года и месяца — фазе 3.

### U2 · Команды календаря, заголовок дня и пассивное сообщение

- **Work items:** ["1.5", "1.6", "1.7", "1.8", "1.9"]
- **Requirements and scenarios:** ["Phase 1: компоненты календаря и каталога сверены с макетами", "design.md: решение 1", "ADR-0030", "daily-choice-management: Заголовок выбранного дня каталога — подготовка компонента", "daily-choice-management: Обновление и отказ получения отметок календаря — подготовка компонента", "daily-choice-management: Локализация и доступность дневного выбора — контракты представлений"]
- **Affected boundary:** Пользователи и вспомогательные технологии на границе представлений шапки, ручки, заголовка дня и сообщения; каталог примеров.
- **Implementation target:** ["lib/src/design_system/components/calendar_handle.dart","lib/src/design_system/components/calendar_header.dart","lib/src/design_system/components/day_heading.dart","lib/src/design_system/components/notice.dart","test/design_system/calendar_handle_test.dart","test/design_system/calendar_header_test.dart","test/design_system/day_heading_test.dart","test/design_system/notice_test.dart","widgetbook/lib/calendar/calendar_handle_use_cases.dart","widgetbook/lib/calendar/calendar_header_use_cases.dart","widgetbook/lib/calendar/day_heading_use_cases.dart","widgetbook/lib/catalog.dart","widgetbook/lib/messages/notice_use_cases.dart"]
- **Applicable constraints and non-goals:** Стрелки получают отдельные названия и nullable-команды, область нажатия не меньше 44 dp; заголовок месяца пока не команда. Ручка объявляет раскрытие; дата — заголовок; Notice объявляет переданное сообщение и не предлагает действий. Примеры доступны в обеих темах. Тесты внешнего вида не требуются: используется ручная сверка.
- **Excluded change scope:** Закрепление календаря, прокрутка выдачи, локализация экранов, отказ чтения отметок, удаление AppBar и портретная ориентация — будущая интеграция фазы 2. Выбор года и месяца и команда заголовка — фаза 3.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий контекст /root/independent_review, fork_turns=none; только нейтральные намерения и точный диапазон. Полностью проверено объединение U1 и U2: 28 путей реализации, тестов и примеров, с прежними сторонами двух переименований. Плановые документы, описания коммитов, обсуждение реализации и прежние замечания независимому рецензенту не передавались. |
| OpenSpec conformance | Complete | Сопоставлены зафиксированные proposal, три delta-spec, design, adr, plan и tasks, релевантные ADR и контекст предметной области. Все задачи и коммиты сопоставлены ниже. OpenSpec validate: valid=true, issues=[]. Проверки выполнены в исходной рабочей директории на d1ec5cb34cf338f229cbf51a43c519a6fd455b4f без изменений входных файлов; результаты приведены ниже. |
| Code quality | Complete | Применены correctness, readability, architecture, security, performance и проверка доказательств из code-review-and-quality ко всем 28 путям. Дополнительный read-only рецензент /root/quality_review проверил тесты, примеры, каталог и семантику. Рассмотрены размеры, переносы, область нажатия, состояния, рисование, темы, измерение текста и существующие потребители. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все 29 reviewable paths учтены: tasks.md — плановое доказательство, остальные 28 — точное подмножество поставки U1 ∪ U2. Несопоставленных и посторонних путей нет. Исходная рабочая директория была чистой и совпадала с reviewed head; staged, unstaged и untracked изменения в обзор не включались. Старые стороны переименований относятся к этим же единицам: daily_choice_calendar_text_metrics.dart → text_metrics.dart и соответствующий тест → test/design_system/text_metrics_test.dart.

Ниже сохранённые ID и номера задач связаны с их коммитами и единицами. Каждый последовательный taskCommitRange проверен; последний коммит меняет только отметку завершения 1.9. История, порядок, описания и завершённость задач сохранены.

Задача ID 1, номер 1.1, коммит `77bc0f7843b02f4f00b2d9543f4249658b7ae0b6`, единицы U1. doable_metrics.dart:20 — tapMin=44; doable_shadows.dart:8–29 — обе палитры shadow-sm совпадают с tokens.json; :36–70 — copyWith/lerp охватывают enum целиком; doable_theme.dart:17–20,95 — расширение в обеих темах. Существующие тесты bootstrap проверяют построение приложения.

Задача ID 2, номер 1.2, коммит `3f984a24318919b6758e13b3aa59311ea59e4e65`, единицы U1. Помощник перенесён с полностью идентичным содержимым. В двух потребителях календаря и перенесённом тесте заменены только импорты. Проверки text_metrics и существующих раскладок/переходов календаря подтверждают прежнее поведение.

Задача ID 3, номер 1.3, коммит `704aa5fa50874569488e8386ab9a1bf51cdbcbec`, единицы U1. WeekStripDay и DayMarkIndicator, week_strip_day_test:9–123: одна кнопка, выбранность, касания по краю, SemanticsAction.tap и рост высоты. Widgetbook показывает четыре сочетания выбранности/сегодня для каждого из трёх состояний отметки и интерактивную неделю.

Задача ID 4, номер 1.4, коммит `b4ca2aab828c09fbddf463f4847e5da4be18a840`, единицы U1. MonthGridDay, MonthGridWeekday и onAccent для отметки; month_grid_day_test:12–144: единая кнопка и рост обеих строк. Примеры включают дни своего/соседнего месяца, выбранность, сегодня и все отметки, а также строку дней с подписями.

Задача ID 5, номер 1.5, коммит `004391e1af84161c0a6dd7a50d82ae5a9b88e74b`, единицы U2. CalendarHeader; calendar_header_test:11–96: отдельные команды, область ≥44×44, активация экранным диктором, обе отключённые границы и отсутствие команды у заголовка. Пример перелистывает сентябрь–ноябрь.

Задача ID 6, номер 1.6, коммит `30c9a583172fcf3fbca33bfcfcb5809e0453135e`, единицы U2. CalendarHandle; calendar_handle_test:11–87: вся полоса 360×44, раскрытие, оба края и SemanticsAction.tap. Примеры обоих начальных состояний.

Задача ID 7, номер 1.7, коммит `68d6494854a908d63c539ee9dd894afd609b009c`, единицы U2. DayHeading; day_heading_test:7–53: дата-заголовок, появление/исчезновение «Сегодня». Примеры показывают оба состояния; ручная проверка масштаба 2,5 подтверждает переносы даты и масштаб отметки без обрезки.

Задача ID 8, номер 1.8, коммит `6902880afa349cd5934ee814515f388d1488887c`, единицы U2. Notice; notice_test:8–25: liveRegion, отсутствие кнопок и tap-действий. Пример содержит короткое и длинное сообщение.

Задача ID 9, номер 1.9, коммит `d1ec5cb34cf338f229cbf51a43c519a6fd455b4f`, единицы U1, U2. Сверены компоненты и примеры, выполнены проверки ниже. В приложении изменены только импорты идентичного измерителя и добавлено неиспользуемое прежними экранами расширение теней; остальная поставка — основы и Widgetbook.

Проверка велась в /home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn на сохранённом reviewed head:

Команда `mise run check` — exit 0, все 2 657 тестов прошли; форматирование 649 файлов без изменений, анализ без замечаний. Включает форматирование, проверку области CI, разрешение зависимостей Widgetbook с enforce-lockfile, анализ Flutter и полный набор тестов с concurrency=2.

Команда `mise exec --no-deps -- flutter test test/design_system test/app/bootstrap test/daily_choice/presentation/catalog --concurrency=2` — exit 0, все 206 тестов прошли. Покрывает изменённые модули и прямых потребителей.

Команда `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --json` — exit 0, valid=true, issues=[].

Команда `git --literal-pathspecs diff --check 153bde064e44037e714a227694188779c0bc8323 d1ec5cb34cf338f229cbf51a43c519a6fd455b4f` — exit 0.

Команда `xvfb-run -a mise run widgetbook` — Linux-сборка успешна. Примеры вручную просмотрены через Flutter Inspector, в светлой и тёмной темах, при стандартном тексте и масштабе 2,5. Сверены состояния дней, отметки, шапка и недоступная стрелка, оба направления ручки, заголовок с отметкой и без неё, короткое/длинное сообщение. После hot reload `get_runtime_errors` вернул `No runtime errors found`.

Эталон визуальной сверки — доступный локальный приватный экспорт: tokens.json, README/preview компонентов WeekStrip, MonthGrid, DayHeading и Notice, а также Parts.dc.html. Значения размеров, цветов, тени и геометрии сопоставлены с кодом; внешний вид — со снимками работающих примеров и отображённой спек-доской. Это ручная сверка; материалы дизайна и снимки в репозиторий не добавлялись.

Первый полный прогон был прерван с сообщением `sh exited with non-zero status: no exit status`; он не засчитан как успешная проверка. Результат выше относится к повторному запуску с отдельно сохранённым кодом возврата. Попытка web-сборки показала, что эта платформа не настроена; проверена штатная Linux-сборка без изменения конфигурации.

Первый read-only вызов discovery-helper использовал его прямой запуск OpenSpec по умолчанию. Обнаружение повторено с `--openspec /tmp/calendar-review-openspec`, оболочкой `mise exec --no-deps -- openspec "$@"`; дальнейшие вызовы OpenSpec выполнялись через mise. Инструменты не устанавливались и не обновлялись.

Исправлений кода или плановых артефактов этот этап не потребовал. Новые задачи и фазы не добавлялись. Требования интеграции фаз 2 и 3 не объявляются выполненными; их дальнейшая детализация остаётся у оркестратора. Отчёт фиксирует результат ограниченного обзора и не разрешает слияние, архивирование или принятие риска.
