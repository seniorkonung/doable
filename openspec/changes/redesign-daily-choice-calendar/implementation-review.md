# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Incomplete
**Coverage limitations:** Все 13 целевых коммитов, 13 задач фазы 2 и 46 изменённых путей сопоставлены и просмотрены. Ручная сверка обоих каталогов с макетами на устройстве в обеих темах, поворот и разделение экрана, включая запуск и отказ подготовки хранилища, в этой сессии не выполнены; DTD не обнаружил работающего приложения. Сохранённый диапазон не содержит проверяемых результатов этих ручных действий. Отметки завершения 2.13 не заменяют такое доказательство.
**Summary:** F1 (Medium): безусловная политика манифеста распространяет телефонные ограничения на большие экраны Android ≤15. Независимые обзоры решений и статический обзор качества завершены; полный `mise run check` прошёл, 2667 тестов успешны. Покрытие необходимых ручных проверок остаётся неполным. Принятых остаточных рисков нет. Замечание оставлено для последующего этапа разрешения findings.

## Review target

- **Baseline ref:** 7389888ec3495126fd617298d8ff743a4c9f4e71
- **Base commit:** 7389888ec3495126fd617298d8ff743a4c9f4e71
- **Reviewed head:** eeef090043567d4f3eea09dfbbf15bcd787e073b
- **Target commits:** ["6362ced9af382521fcd95707b103eec5256dfa92","a42bc4abe50064f8aec1bccb7630ed25ab0581a2","eeec83c3a135116c3861a7d8a22efd9205d3d05a","5ed38e172ac12c53867289cfbcc6fa4716bbadef","322dce71cac40c8bc276be516ab0b4db44f72515","06c8c0014bcef015a803e897712310e6970acfc4","8e09fc0bd0ba1c8abe74dfe9a77b2c7ec35dc0a7","f64b74d282f93128254af7732c8c1dadf34c171b","0b837e9f9183b8e8be814c4917c8ad10f58c6234","5d222d769483ea71cf64b062d3a0856bf2595562","8df05bee379c018fec21a7bc3eb6a09aa110ee89","7d4bbdeacc9450ebe23b66f28b789177bf269236","eeef090043567d4f3eea09dfbbf15bcd787e073b"]
- **Reviewable paths:** ["android/app/src/main/AndroidManifest.xml","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/application/daily_choice_day_statuses.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart","openspec/changes/redesign-daily-choice-calendar/tasks.md","test/android/orientation_policy_test.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/navigation/app_navigation_accessibility_test.dart","test/app/navigation/app_shell_layout_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/quick_creation/quick_creation_launcher_test.dart","test/app/quick_creation/quick_creation_launcher_test_support.dart","test/app/routing/app_router_test.dart","test/daily_choice/application/daily_choice_day_statuses_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart","test/daily_choice/presentation/daily_choice_creation_launcher_test.dart","test/support/daily_choice_catalog_controls.dart"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Подтверждённые отметки трёх шестинедельных сеток

- **Work items:** ["10 / 2.1","14 / 2.5","22 / 2.13"]
- **Requirements and scenarios:** ["daily-choice-management: Отметки состояния дней календаря каталога","Отметки соседней недели видны во время перелистывания","Повторное перелистывание опережает получение отметок","Обновление и отказ получения отметок календаря","design.md: решение 2 — окно шестинедельных сеток"]
- **Affected boundary:** Ограниченный прикладной запрос состояний дней, модель отметок и видимый пользователю первый свайп к соседнему месяцу.
- **Implementation target:** ["lib/src/daily_choice/application/daily_choice_day_statuses.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window.dart","test/daily_choice/application/daily_choice_day_statuses_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_window_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart"]
- **Applicable constraints and non-goals:** Все три сетки покрываются одним согласованным снимком не длиннее 105 дней; UTC сохраняет календарные части, границы обрезаются до запроса. Выдача и фильтр независимы от отметок; подтверждённые отметки переживают отказ, ответы прежнего окна и старой ревизии не подменяют актуальные данные. Миграций и новых источников истины нет. Общие файлы интеграционного теста и его поддержки пересекаются с U3.
- **Excluded change scope:** Завершённый выбор месяца и повтор чтения при равном просмотре через будущий выбор года и месяца относятся к фазе 3.

### U2 · Неделя, шестинедельный месяц и независимый просмотр

- **Work items:** ["11 / 2.2","12 / 2.3","13 / 2.4","15 / 2.6","22 / 2.13"]
- **Requirements and scenarios:** ["daily-choice-management: Встроенный недельный и месячный календарь каталога","Свайп недели сохраняет фильтр","Свайп месяца сохраняет фильтр","Раскрытие сохраняет просмотр соседнего периода","Сворачивание сохраняет дату просмотра","Возврат к месяцу выбранной даты","Выбор дня сохраняет раскрытое представление","Локализация и доступность дневного выбора","Календарём можно управлять без свайпа"]
- **Affected boundary:** Пользователь и вспомогательные технологии на границе календаря, представлений его дней и библиотечного листания.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_boundaries_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart","test/support/daily_choice_catalog_controls.dart"]
- **Applicable constraints and non-goals:** Неделя начинается в понедельник и листается только свайпом; месяц содержит шесть недель и доступные стрелки. Возврат к месяцу выбранного дня восстанавливает его дату просмотра; другие месяцы начинают просмотр с первого числа. Выбор и просмотр раздельны, прерывание анимации сохраняет последний подтверждённый просмотр. Предметные типы и локализация остаются в адаптере, существующие компоненты основ получают готовые данные. Шапка месяца пока не команда. Общий календарь и шаги управления пересекаются с U3.
- **Excluded change scope:** Выбор года и месяца, его состояние и команды — фаза 3; основы и Widgetbook фазы 1 используются как неизменённый контекст.

### U3 · Закреплённый календарь и прокручиваемая выдача обоих каталогов

- **Work items:** ["16 / 2.7","17 / 2.8","18 / 2.9","19 / 2.10","21 / 2.12","22 / 2.13"]
- **Requirements and scenarios:** ["daily-choice-management: Заголовок выбранного дня каталога","Заголовок сегодняшнего дня","Заголовок называет выбранный день вне показанной недели","Выдача нового дня показывается с начала","Календарь остаётся на месте при прокрутке выдачи","Раскрытый месяц доступен на нижней границе поддержки при отказе отметок","Отказ получения показывает пассивную строку","Следующее получение убирает строку отказа","Начальное состояние и сохранение календаря каталога","Каталог дневных выборов на заданную дату","app-navigation: Корневой каталог дневных выборов без заголовка","app-appearance: область поддержки интерфейса телефона"]
- **Affected boundary:** Оба экземпляра каталога, навигация приложения, жизненный цикл локального дня, темы, локализация и прокрутка выдачи.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/navigation/app_navigation_accessibility_test.dart","test/app/navigation/app_shell_layout_test.dart","test/app/navigation/app_shell_state_test.dart","test/app/quick_creation/quick_creation_launcher_test.dart","test/app/quick_creation/quick_creation_launcher_test_support.dart","test/app/routing/app_router_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_accessibility_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart","test/daily_choice/presentation/daily_choice_creation_launcher_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart","test/support/daily_choice_catalog_controls.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart"]
- **Applicable constraints and non-goals:** Календарь и пассивный Notice закреплены, заголовок дня и выдача прокручиваются вместе. Только смена выбранной даты возвращает список к началу; просмотр, отметки и переходы между разделами сохраняют состояние. Корневой Scaffold остаётся без AppBar, стиль строки состояния зависит от темы; каталог на заданную дату сохраняет верхнюю панель. Поддержка: ширина ≥360 dp, полезное тело ≥528 dp при стандартном масштабе, закреплённый блок ≤480 dp и прокрутка ≥48 dp. Удаляются ровно три устаревших ключа локализации. Изменения интеграционных тестов обусловлены новой темой и доступными командами.
- **Excluded change scope:** Новые секции и строки выдачи, верхняя панель каталога на дату, Главная, адаптации окон ниже границы поддержки и гарантия произвольного увеличения текста не входят в фазу 2.

### U4 · Телефонная политика ориентации и окна с запуска процесса

- **Work items:** ["20 / 2.11","22 / 2.13"]
- **Requirements and scenarios:** ["app-appearance: Портретная ориентация на телефоне","Поворот телефона не поворачивает интерфейс","Разделённый экран на телефоне недоступен","ADR-0031"]
- **Affected boundary:** Android Activity, системная ориентация и многооконность, включая подготовку локального хранилища.
- **Implementation target:** ["android/app/src/main/AndroidManifest.xml","test/android/orientation_policy_test.dart"]
- **Applicable constraints and non-goals:** Телефон остаётся в портретной ориентации во весь экран с запуска процесса; поведение больших экранов определяет система. Android targetSdk 36 не отменяет поддержку предыдущих ОС. Отказ от системного поведения Android 16 и альтернативные раскладки не требуются. F1 показывает, что выбранный механизм не соблюдает эту границу на предыдущих ОС.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих контекста с fork_turns=none по implementation-decision-review. /root/calendar_decisions проверил объединение U1–U3: все 43 полных пути; /root/android_decisions — два полных пути U4. Переданы нейтральные исходы, ограничения и сохранённые SHA; плановые документы, история, прошлый отчёт и findings не передавались. Контекст вне назначения проверен на неизменность. Первый обзор не подтвердил существенных замечаний; второй вернул F1, проверенное координатором по снимку и первичной документации. |
| OpenSpec conformance | Incomplete | Прочитаны зафиксированные proposal, три delta-spec, design, adr, plan, tasks, канонические требования и релевантные ADR. Все задачи и пути сопоставлены ниже. `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json`: exit 0, valid=true, issues=[]. `MISE_AUTO_INSTALL=0 mise run check`: exit 0, 2667 тестов прошли, 651 файл отформатирован без изменений, Flutter analyze без замечаний; выполнено в исходной директории на сохранённом head. Не выполнена ручная проверка 2.13 на устройстве. |
| Code quality | Complete | Пять направлений code-review-and-quality применены к полному подмножеству поставки из 45 путей: корректность дат и событий, простота и владение состоянием, границы основ/адаптера/моделей, безопасность чтения и отсутствие нового внешнего ввода, стоимость ограниченного агрегата, качество тестовых наблюдений. Дополнительных подтверждённых дефектов кроме F1 не выявлено. |

## Findings

### F1 · Medium — Телефонные ограничения применяются и к большим экранам Android ≤15

- **Evidence:** На reviewed head `android/app/src/main/AndroidManifest.xml:11` и `:12` безусловно задают portrait и resizeableActivity=false. `android/app/build.gradle.kts:22` и `:23` берут minSdk/targetSdk Flutter; версия 3.47.1 из `mise.toml:2` имеет minSdk=24, targetSdk=36, что также проверено в установленном FlutterExtension.kt:26,34. Следовательно, запуск на планшете ≥600 dp под Android 11 или 15 достижим. До base..head эти атрибуты отсутствовали. Единственная MainActivity и debug/profile manifests не снимают ограничения. По [документации Activity](https://developer.android.com/guide/topics/manifest/activity-element#screen) portrait задаёт портретную Activity; производитель может применить letterbox. На API24–30 false запрещает multiwindow, на API31–35 вводит режим совместимости, когда размеры этого требуют ([поведение multiwindow по версиям](https://developer.android.com/develop/ui/views/layout/support-multi-window-mode#version-specific)). Автоматическое игнорирование этих ограничений для ≥600 dp относится к [Android 16](https://developer.android.com/about/versions/16/behavior-changes-16#ignore-orientation); targetSdk=36 не переносит его на старые ОС. Тест `test/android/orientation_policy_test.dart:27` и `:28` закрепляет литералы без различения размера экрана. Между тем `specs/app-appearance/spec.md:6` ограничивает запрет телефонами, а `docs/adr/0031-restrict-phones-to-portrait-full-screen.md:17` и `:23` оставляет ориентацию и размер больших экранов системе.
- **Evidence revisions:** ["eeef090043567d4f3eea09dfbbf15bcd787e073b","7389888ec3495126fd617298d8ff743a4c9f4e71"]
- **Impact:** На большом экране Android ≤15 приложение вводит новый запрет поворота либо портретный letterbox, а на API24–30 — запрет разделения экрана. Пользователь теряет системные режимы, которые сохранённое требование исключает из телефонного запрета. Проявление зависит от версии ОС и OEM, но область действия атрибутов не ограничена телефонами.
- **Required outcome:** Согласовать техническое решение и его проверки с уже заданной границей: ограничения действуют на телефонных дисплеях с запуска, а большие экраны не получают новых ограничений ориентации и изменения размера на поддерживаемых Android API. Подтвердить различение обеих категорий до Android 16 и сохранить системное поведение Android 16. Новые раскладки больших экранов для этого не требуются.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** ["docs/adr/0031-restrict-phones-to-portrait-full-screen.md","openspec/changes/redesign-daily-choice-calendar/design.md: решение 6","openspec/changes/redesign-daily-choice-calendar/tasks.md: 2.11","android/app/src/main/AndroidManifest.xml","test/android/orientation_policy_test.dart"]

## Review coverage

Все 46 reviewable paths учтены: один tasks.md — плановое доказательство, остальные 45 — точное подмножество поставки U1 ∪ U2 ∪ U3 ∪ U4. Несопоставленных и посторонних путей нет. Пересекающиеся U1–U3 получили одного независимого рецензента с объединением полных файлов; U4 не пересекается с ними и проверена отдельно. Неизменённые модели, компоненты основ, репозиторий, оболочка и ADR использованы только как контекст.

Каждый целевой коммит просмотрен в заданном последовательном taskCommitRange; сопоставление фиксирует связь доказательств, а не выводит выполнение из флажка. ID, номер, описание и порядок задач взяты из сохранённого workflow и tasks.md. Рабочее дерево до аудита было чистым и совпадало с reviewed head; никаких staged, unstaged или untracked изменений как доказательств реализации не использовано.

Задача ID 10, номер 2.1, «Окно отметок покрывает три шестинедельные сетки одним запросом не длиннее 105 дней», коммит `6362ced9af382521fcd95707b103eec5256dfa92`, единицы U1. Расчёт UTC-окна и maxDays=105; проверки границ, високосного февраля, 105/106 дней и модели.

Задача ID 11, номер 2.2, «Свайп и стрелки месяца сохраняют выбранный день при возврате к его месяцу», коммит `a42bc4abe50064f8aec1bccb7630ed25ab0581a2`, единицы U2. Правило даты просмотра; navigation/transitions/boundaries и интеграция catalog_page с сохранением фильтра и выдачи.

Задача ID 12, номер 2.3, «Недельная строка календаря показывает дни компонентом WeekStripDay», коммит `eeec83c3a135116c3861a7d8a22efd9205d3d05a`, единицы U2. Адаптер WeekStripDay, подпись внутри ячейки и независимые доступные состояния; обновлены потребители тестовой темы.

Задача ID 13, номер 2.4, «Месячный календарь показывает шесть недель компонентами MonthGrid», коммит `5ed38e172ac12c53867289cfbcc6fa4716bbadef`, единицы U2. sixWeekMonthsEnforced, MonthGridDay/Weekday; шесть недель февраля и граничные позиции за CalendarDate.

Задача ID 14, номер 2.5, «Подтвердить отметки дополнительной строки соседнего месяца до завершения первого свайпа», коммит `322dce71cac40c8bc276be516ab0b4db44f72515`, единицы U1. Первый незавершённый свайп апреля к маю: 7 июня виден до ответа мая; fake ограничивает данные запрошенным окном.

Задача ID 15, номер 2.6, «Шапка месяца и ручка управляют календарём, а соседние недели открываются только свайпом», коммит `06c8c0014bcef015a803e897712310e6970acfc4`, единицы U2. CalendarHeader/Handle, отсутствие команд недели, семантическая активация и прерывание анимации месяца.

Задача ID 16, номер 2.7, «Оба каталога называют выбранную дату заголовком DayHeading в начале выдачи», коммит `8e09fc0bd0ba1c8abe74dfe9a77b2c7ec35dc0a7`, единицы U3. DayHeading в обоих каталогах; выбранная дата вне просмотра, локаль, полночь и возврат из фона.

Задача ID 17, номер 2.8, «Календарь с Notice закреплён над выдачей, а выбор другого дня возвращает список к началу», коммит `f64b74d282f93128254af7732c8c1dadf34c171b`, единицы U1, U2, U3. Column/Expanded, собственный ScrollController и reset по смене даты; закреплённый Notice, сохранение отметок и смещения.

Задача ID 18, номер 2.9, «Корневой каталог открывается без AppBar и сохраняет стиль строки состояния по теме», коммит `0b837e9f9183b8e8be814c4917c8ad10f58c6234`, единицы U3. Корневой Scaffold без AppBar, AnnotatedRegion по теме; сохранены панель каталога на дату и названия навигации.

Задача ID 19, номер 2.10, «Локализация больше не содержит строк выбранной даты и команд соседней недели», коммит `5d222d769483ea71cf64b062d3a0856bf2595562`, единицы U3. Из ARB и трёх generated-файлов удалены только SelectedDate/PreviousWeek/NextWeek; потребителей ключей нет.

Задача ID 20, номер 2.11, «Манифест ограничивает приложение на телефоне портретной ориентацией во весь экран», коммит `8df05bee379c018fec21a7bc3eb6a09aa110ee89`, единицы U4. Два атрибута MainActivity и тест литералов; телефонный исход статически обеспечен, обнаружено расхождение F1.

Задача ID 21, номер 2.12, «Раскрытый календарь с отказом отметок оставляет доступной выдачу на нижней границе поддержки», коммит `7d4bbdeacc9450ebe23b66f28b789177bf269236`, единицы U3. Новый supported_layout_test: оба каталога, ru/en, 360×720, реальные Inter и системные отступы; дни, Notice, ручка, 48 dp выдачи и действия.

Задача ID 22, номер 2.13, «Проверить готовность фазы 2: оба каталога сохраняют поведение с закреплённым календарём дизайна», коммит `eeef090043567d4f3eea09dfbbf15bcd787e073b`, единицы U1, U2, U3, U4. Обновлены прямые интеграционные потребители команд и темы; полный check прошёл, 2667 тестов. Ручная часть приёмки не подтверждена этой сессией.

Сценарии текущего объёма прослежены до наблюдаемого поведения:

Неделя/месяц листаются без смены выбранной даты, фильтра и выдачи; возврат к выбранному месяцу и сворачивание: daily_choice_calendar_navigation_test, daily_choice_calendar_transitions_test, daily_choice_catalog_page_test; события просмотра и число чтений выдачи.

Выбор дня в раскрытом месяце и граничные даты без смены календарных частей: daily_choice_calendar_test, daily_choice_calendar_boundaries_test, неизменённый daily_choice_calendar_utc_dates_test.

Выбранность, сегодня и состояние дня доступны диктору; месяц управляется без свайпа: daily_choice_calendar_accessibility_test, daily_choice_calendar_day_marks_test; отдельные состояния и SemanticsAction.tap.

Отметки соседей видны уже при первом свайпе, устаревший ответ не заменяет текущий, отказ сохраняет подтверждённое: daily_choice_catalog_day_marks_test и daily_choice_calendar_day_marks_view_model_test; единый снимок и стоимость максимума — неизменённые drift_daily_choice_day_statuses_test/read_cost_test.

Заголовок называет выбранную дату, локальное сегодня обновляется независимо от выборки: daily_choice_catalog_page_test, daily_choice_catalog_lifecycle_test, daily_choice_date_catalog_page_test, app_shell_state_test.

Закрепление, прокрутка и сброс списка по новому дню; пассивное сообщение под ручкой: daily_choice_catalog_layout_test, daily_choice_catalog_day_marks_test; быстрый ответ нового дня не маскирует сброс короткой загрузкой.

Нижняя граница поддержки сохраняет все дни, ручку, сообщение и прокрутку: daily_choice_catalog_supported_layout_test: четыре сценария root/date × ru/en; проверены полезная высота ≥528 dp, бюджет ≤480 dp и список ≥48 dp.

Возврат из раздела, локаль, независимость одинаковых дат и состояние страниц: app_shell_state_test, daily_choice_calendar_page_storage_test, daily_choice_date_catalog_page_test и интеграционные сценарии статистики.

У корневого каталога нет заголовка, навигационное название сохранено, строка состояния следует теме: app_navigation_accessibility_test, daily_choice_catalog_page_test, app_shell_layout_test.

Телефонная политика ориентации/окна: orientation_policy_test подтверждает конфигурацию; ручные сценарии устройства пока не подтверждены, F1 остаётся активным.

Проверки выполнены в /home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn при HEAD=eeef090043567d4f3eea09dfbbf15bcd787e073b. Входные исходники, тесты и планирование совпадают со снимком. OpenSpec status и instructions apply использованы только для чтения графа артефактов и прогресса; Apply и другие workflow не запускались. Discovery выполнен с --openspec /tmp/daily-choice-review-openspec, который вызывает только `mise exec --no-deps -- openspec "$@"`. Инструменты не устанавливались и не обновлялись.

Команда `MISE_AUTO_INSTALL=0 mise run check` завершилась с exit 0: форматирование 651 файла без изменений, проверки области CI успешны, зависимости Widgetbook разрешены с enforce-lockfile, Flutter analyze — No issues found, весь набор — 2667 успешных тестов. Это включает изменённые модули и прямых потребителей, проверки SQLite-агрегата на новом максимуме, локализацию, Android-манифест, навигацию и четыре сценария нижней границы раскладки. Лог текущего прогона — /tmp/daily-choice-review-check.log; тестировался именно reviewed head, а единственная последующая правка — этот отчёт.

Команда `git --literal-pathspecs diff --check 7389888ec3495126fd617298d8ff743a4c9f4e71 eeef090043567d4f3eea09dfbbf15bcd787e073b` завершилась с exit 0. Проверка удалённых ключей через git grep на reviewed head по lib/test вернула exit 1 без совпадений, как ожидается. `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json` завершилась с exit 0, valid=true и issues=[]. Валидатор implementation-review.md подтвердил format v1.

Ручная визуальная сверка обоих работающих каталогов с приватными Main.dc.html и Parts.dc.html в обеих темах, проверка на физическом телефоне, поворот и разделение экрана, включая подготовку хранилища, в эту сессию не вошли. DTD вернул отсутствие работающего debug-приложения. Успех виджет-тестов подтверждает геометрию и поведение в их окружении, но не заменяет эти обязательные действия приёмки 2.13. Старый отчёт фазы 1 не использован как доказательство новой интеграции. Ограничение не требует останавливать этот этап аудита и не объявляется принятием риска.

Существующее состояние отчёта прочитано после завершения изолированных обзоров: активных findings и принятых рисков для переноса не было. F1 относится к текущему диапазону. Исправления кода, тестов и плановых артефактов в этом аудите не выполнялись; новые задачи и фазы не добавлялись, история задач не изменялась. F1 сохраняется для последующих этапов разрешения findings и пока не имеет согласованного планового handoff. Готовность фазы 3 и всего изменения здесь не заявляется.
