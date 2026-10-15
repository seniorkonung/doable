# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все девять целевых коммитов и задачи 29–37 (3.1–3.9): встроенный выбор года и месяца в обоих каталогах, восстановление отметок и сохранение состояния. Независимая оценка решений, сверка с OpenSpec и проверка качества завершены без существенных замечаний. Нерешённых замечаний и принятых остаточных рисков нет. Вывод ограничен указанным диапазоном фазы 3.

## Review target

- **Baseline ref:** 2f08fbf6598d021d7f70646ff7ce27d6032716fa
- **Base commit:** 2f08fbf6598d021d7f70646ff7ce27d6032716fa
- **Reviewed head:** d245a71f08e39020a36e2a4e60a017394ff4b243
- **Target commits:** ["2f0ec79297476c3f50d6ff2b6a7cc8aa9ab35548", "62348e002c01b6c5afeb94da23986c94a27b2cd1", "3a08e9563839f7caff670a9cbdad35ac6f064c1f", "6f3395caa9fdaeaf9d221a844fa421cf7fb0272e", "eed5a9cb2f357efcf970cf02f4d44e795d7e1947", "0f72da3ed3ba29ee03314671bde85387489af44a", "d61cd4f271a26976093b978dc6b8fd90364a5c41", "a2a33a1325bef8c64efc9707f241d0a6b2211aef", "d245a71f08e39020a36e2a4e60a017394ff4b243"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/design_system/components/calendar_header.dart", "lib/src/design_system/components/period_picker.dart", "openspec/changes/redesign-daily-choice-calendar/tasks.md", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/design_system/calendar_header_test.dart", "test/design_system/period_picker_test.dart", "widgetbook/lib/calendar/calendar_header_use_cases.dart", "widgetbook/lib/calendar/period_picker_use_cases.dart", "widgetbook/lib/catalog.dart"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Выбор периода следует дизайну и доступен на русском и английском

- **Work items:** ["29 / 3.1", "30 / 3.2", "32 / 3.4", "36 / 3.8", "37 / 3.9"]
- **Requirements and scenarios:** ["Локализация и доступность дневного выбора", "Календарём можно управлять без свайпа", "design.md: решения 1, 7, 8 и 9", "ADR-0029", "ADR-0030"]
- **Affected boundary:** Пользователь и семантическое управление календарём; потребитель компонентов модуля основ.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/design_system/components/calendar_header.dart", "lib/src/design_system/components/period_picker.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/design_system/calendar_header_test.dart", "test/design_system/period_picker_test.dart", "widgetbook/lib/calendar/calendar_header_use_cases.dart", "widgetbook/lib/calendar/period_picker_use_cases.dart", "widgetbook/lib/catalog.dart"]
- **Applicable constraints and non-goals:** Компоненты получают готовые подписи, признаки и обработчики; управление периодом и локализация принадлежат потребителю. Сетка содержит 12 позиций по три в ряд, недопустимые позиции пусты. Показанный и текущий периоды различимы независимо, включая совпадение. Внешний вид сверяется вручную с макетами в обеих темах.
- **Excluded change scope:** Подключение выбора периода на Главной.

### U2 · Завершённый выбор месяца восстанавливает отметки без лишних чтений

- **Work items:** ["31 / 3.3", "32 / 3.4", "33 / 3.5", "34 / 3.6", "37 / 3.9"]
- **Requirements and scenarios:** ["Обновление и отказ получения отметок календаря", "Повторный выбор показанного месяца восстанавливает отметки", "design.md: решения 2 и 9", "ADR-0024", "ADR-0025"]
- **Affected boundary:** Событие календаря → общий обработчик каталога → модель отметок → существующее чтение окна отметок.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart"]
- **Applicable constraints and non-goals:** Модель различает обычную установку просмотра и завершённый выбор месяца. Повтор после отказа создаёт одно чтение; успешный равный месяц и промежуточные шаги не создают чтений. Выдача, выбранная дата и фильтр независимы от просмотра. Подтверждённые отметки, ревизии и защита от устаревших ответов сохраняются.

### U3 · Оба каталога сохраняют выбор даты и собственное состояние при переходе к периоду

- **Work items:** ["33 / 3.5", "34 / 3.6", "35 / 3.7", "36 / 3.8", "37 / 3.9"]
- **Requirements and scenarios:** ["Выбор года и месяца в календаре каталога", "Переход к далёкому месяцу не меняет выбранную дату", "Сворачивание после выбора месяца показывает его первую неделю", "Возврат к месяцу выбранной даты", "Встроенный недельный и месячный календарь каталога", "design.md: решения 2, 4 и 9", "ADR-0028"]
- **Affected boundary:** Корневой каталог и независимые экземпляры каталога на заданную дату; навигационная история, обновление данных и окружения.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/design_system/components/calendar_header.dart", "lib/src/design_system/components/period_picker.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart"]
- **Applicable constraints and non-goals:** Выбор встроен вместо дней, без маршрута и свайпа; страницы лет привязаны к 2020 году и ограничены CalendarDate. Завершение сообщает одно событие даже при равном просмотре. Заголовок отменяет выбор без события, ручка возвращает неделю прежней даты просмотра. Экземпляры сохраняют собственные состояния в пределах жизненного цикла; новый экземпляр начинает с недели.
- **Excluded change scope:** Нативная оконная политика Android и физическая проверка владельцем продукта из фазы 2.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий reviewer `/root/calendar_decisions` с `fork_turns=none` проверил точный Base..Reviewed head и все девять коммитов. Переданы нейтральное описание ожидаемых результатов, ограничения и 26 файлов поставки; план, задачи, прежний отчёт и чужие замечания не передавались. U1–U3 образуют одну группу пересечения через компоненты, календарь, обработчик и тесты; reviewer проверил объединение полных файлов, равное всем 26 файлам поставки. Существенных замечаний и непокрытых областей не сообщил. |
| OpenSpec conformance | Complete | Сопоставлены артефакты схемы intent-driven, задачи, сценарии, отдельные патчи и итоговый код. На Reviewed head в этом рабочем дереве выполнены полный `mise run check` (2699 тестов, exit 0), строгая валидация OpenSpec (valid=true, issues=[]), свежая Android-сборка и ручная сверка Widgetbook и обоих каталогов в обеих темах. Детали ниже. |
| Code quality | Complete | Проверены все 26 файлов поставки по корректности, читаемости, архитектуре, безопасности и производительности: типизированные переходы, границы дат, семантика, владение состоянием, число чтений, ревизии, сгенерированный код и обоснованность тестов. `flutter analyze` внутри полного прогона завершился без замечаний; `git diff --check` для точного диапазона — exit 0. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Обнаружение диапазона выполнено через `discover-review-target.mjs` с указанными полными SHA; OpenSpec вызывался обёрткой `mise exec --no-deps -- openspec`. На момент проверки HEAD совпадал с Reviewed head, рабочее дерево было чистым. Каждый из 27 путей учтён: 12 файлов реализации и локализации, 11 тестовых файлов и помощников, три файла Widgetbook входят в U1–U3; `tasks.md` служит свидетельством планирования. Непривязанных путей нет.

Прочитаны proposal, три delta-spec, design, adr, plan и tasks этого изменения, конфигурация и схема OpenSpec, применимые положения канонических спецификаций, CONTEXT.md и связанные ADR. Предыдущий implementation-review прочитан только после независимой оценки; действующих F/AR для переноса в нём не было.

Каждый целевой коммит сопоставлен с принадлежащей ему задачей и проверен вместе с итоговым состоянием изменённых файлов. Диапазоны ниже включают правую границу и исключают левую; порядок совпадает с данными workflow.

Задача 29 / 3.1 «Компоненты выбора года и месяца из модуля основ представлены в Widgetbook»: диапазон `2f08fbf6598d021d7f70646ff7ce27d6032716fa..2f0ec79297476c3f50d6ff2b6a7cc8aa9ab35548`; единицы U1. Компоненты, поведенческие проверки и примеры Widgetbook.

Задача 30 / 3.2 «Локализация предоставляет русские и английские названия команд выбора года и месяца»: диапазон `2f0ec79297476c3f50d6ff2b6a7cc8aa9ab35548..62348e002c01b6c5afeb94da23986c94a27b2cd1`; единицы U1. Шесть пар команд RU/EN и соответствующий сгенерированный API.

Задача 31 / 3.3 «Модель отметок повторяет чтение после отказа по завершённому выбору месяца даже при равном просмотре»: диапазон `62348e002c01b6c5afeb94da23986c94a27b2cd1..3a08e9563839f7caff670a9cbdad35ac6f064c1f`; единицы U2. Типизированная причина установки просмотра, повтор чтения и проверки модели.

Задача 32 / 3.4 «Подтвердить готовность компонентов, локализации и контракта отметок к подключению выбора в календарь»: диапазон `3a08e9563839f7caff670a9cbdad35ac6f064c1f..6f3395caa9fdaeaf9d221a844fa421cf7fb0272e`; единицы U1, U2. Только отметка выполнения в tasks.md; готовность компонентов и потребителей проверена на Reviewed head.

Задача 33 / 3.5 «Оба каталога переходят к выбранному году и месяцу через встроенный выбор без изменения выбранной даты и выдачи»: диапазон `6f3395caa9fdaeaf9d221a844fa421cf7fb0272e..eed5a9cb2f357efcf970cf02f4d44e795d7e1947`; единицы U2, U3. Встроенный выбор, подключение общего обработчика обоих каталогов и проверки переходов.

Задача 34 / 3.6 «Проверка календаря с моделью подтверждает восстановление отметок после выбора месяца без лишних чтений»: диапазон `eed5a9cb2f357efcf970cf02f4d44e795d7e1947..0f72da3ed3ba29ee03314671bde85387489af44a`; единицы U2, U3. Интеграционные проверки календаря с моделью и счётчиками чтений.

Задача 35 / 3.7 «Открытый выбор года и месяца сохраняется независимо в каждом экземпляре каталога»: диапазон `0f72da3ed3ba29ee03314671bde85387489af44a..d61cd4f271a26976093b978dc6b8fd90364a5c41`; единицы U3. Проверки сохранения состояния экземпляров, навигации, локали, даты и обновлений.

Задача 36 / 3.8 «Доступные команды выбора года и месяца работают на русском и английском без свайпа»: диапазон `d61cd4f271a26976093b978dc6b8fd90364a5c41..a2a33a1325bef8c64efc9707f241d0a6b2211aef`; единицы U1, U3. Проверки семантического управления RU/EN и крайних позиций.

Задача 37 / 3.9 «Подтвердить готовность фазы 3: выбор года и месяца соответствует спецификации и сохраняет поведение фазы 2»: диапазон `a2a33a1325bef8c64efc9707f241d0a6b2211aef..d245a71f08e39020a36e2a4e60a017394ff4b243`; единицы U1, U2, U3. Только отметка выполнения в tasks.md; полные проверки и ручная сверка повторены в этой сессии.

Изменения `tasks.md` в исходном диапазоне ограничены девятью отметками выполнения. Описания, номера, порядок и зависимости не изменены. Коммиты 3.4 и 3.9 учтены как результаты проверок, а не самостоятельные реализации. Запуск тестов на каждом промежуточном SHA не заявляется: свежие проверки выполнены на Reviewed head, переходы между коммитами изучены по патчам.

Переход из октября 2026 в март 2028, сворачивание к 28 февраля — 5 марта, возврат к месяцу выбранной даты, равный просмотр и оба способа отмены проверены в `test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart:50`. Там же проверяются границы лет 1 и 9999, отсутствие промежуточных событий и независимость выдачи обоих каталогов. Реализация хранит страницы выбора внутри экземпляра календаря и возвращает настоящую сетку дней с согласованной датой просмотра.

Восстановление после отказа и число обращений отдельно доказаны на границе модели в `test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart:169` и на границе настоящего календаря с каталогом в `test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart:18`. Первый уровень защищает политику чтений, второй — передачу причины и отсутствие дублирующих событий либо чтений выдачи. Успешный равный месяц, другой месяц после отказа, отмена заголовком и сворачивание ручкой различаются по наблюдаемому результату.

Проверки `app_shell_state_test.dart`, `daily_choice_date_catalog_page_test.dart` и `daily_choice_catalog_lifecycle_test.dart` покрывают смену пунктов, повторный выбор пункта, возврат по истории, два независимых экземпляра каталога на заданную дату, подтверждённые изменения и начало нового жизненного цикла. Смена локали и текущей локальной даты сохраняет открытую страницу выбора; текущие признаки обновляются независимо от просмотра.

Семантический путь без свайпа проверен в `test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart:192` для RU/EN: открытие, страницы лет, годы, месяц, возврат к дням и сворачивание. Проверены независимые и совпадающие признаки показанного и текущего периода, недоступные стрелки и отсутствие семантических действий у пустых позиций. ARB и три сгенерированных файла согласованы; названия месяцев используют существующее форматирование дат.

Компоненты модуля основ остаются представлением с переданными значениями и обработчиками. Предметное управление ограничено календарём, а решение о повторе и окне чтения принадлежит модели отметок. Enum причины обращения и закрытые варианты страницы выражают различия состояний явно. Проверены сетка, ограниченная 12 позициями, пределы дат, отмена прежнего перелистывания, сброс сохранённой позиции сетки после выбора месяца и защита результатов чтения ревизией.

Проверка безопасности охватила существующие входы пользовательских команд и чтение локальных данных: выбираемые годы ограничены CalendarDate, новый путь не обходит доменные границы и не выполняет команды записи. Зависимости, разрешения и внешние интеграции диапазоном не добавляются. Проверка производительности подтвердила отсутствие загрузки выдачи на промежуточных шагах и повторных чтений успешного окна. Не выявлены недостижимые обработчики отказов, лишние расширения API или тесты, повторяющие одну гарантию на одном уровне.

Команды выполнялись в `/home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn` на `d245a71f08e39020a36e2a4e60a017394ff4b243`; Widgetbook запускался задачей mise из вложенного пакета. Исходники во время проверки не менялись.

Команда `mise run check`: Exit 0: форматирование 656 файлов без изменений; проверки CI scope прошли; зависимости Widgetbook разрешены с `--enforce-lockfile`; анализ — `No issues found`; `flutter test --concurrency=2` — 2699 passed. Включены изменённые модули и непосредственно затронутые потребители, локализация, навигация и регрессии фазы 2.

Команда `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json`: Exit 0, valid=true, issues=[].

Команда `git diff --check 2f08fbf6598d021d7f70646ff7ce27d6032716fa d245a71f08e39020a36e2a4e60a017394ff4b243`: Exit 0.

Команда `mise exec --no-deps -- flutter build apk --debug --no-pub`: Exit 0. Проверенный APK: SHA-256 `8145a28d6fd6e660789e66c75f67de11b19a2646ea9bb21b4e6677088c7dfa30`.

Команда `mise run widgetbook` и запуск свежего APK через `flutter run --use-application-binary`: Сборки запущены; ручная сверка ниже. Dart MCP `get_runtime_errors` не обнаружил ошибок в Widgetbook и приложении после сценариев.

Первый полный прогон не засчитан: управляющая команда завершилась сообщением `no exit status`, хотя дочерний тестовый процесс продолжал вывод. Полный `mise run check` повторён в отдельной сессии до подтверждённого exit 0; вывод второго запуска сохранён локально в `/tmp/calendar-review-check-retry.log`. Причина прерывания первого запуска не приписывается коду приложения.

Использованы доступные в этой рабочей среде приватные источники `context/doable-design-system/components/PeriodPicker/` и `context/doable-design/design/Parts.dc.html`. Они не входят в Git-диапазон. Макеты Parts отрисованы и просмотрены в светлой и тёмной темах; с ними сопоставлены свежие изображения Widgetbook и приложения. Это ручная сверка, без добавления golden-тестов или тестов Widgetbook.

В Widgetbook проверены годы, месяцы, совпадение и различие текущего и показанного периода, крайние пустые позиции, недоступные стрелки и открытая шапка в обеих темах. Сетка, размеры, начертание, заливка, акцент и обводка согласуются с макетами. Непринятых расхождений не выявлено. Локальные снимки: `/tmp/calendar-review-widgetbook-{years,months,lower,upper}-{light,dark}.png` и `/tmp/calendar-review-reference-{light,dark}.png`.

На Android runtime API 36 в эмуляторе `doable-foundation-2-3`, дисплей 390×844 dp, стандартный размер текста, ru-RU, проверены оба каталога в обеих темах. В каждом выполнены открытие выбора, переход к далёкому году и месяцу, отмена заголовком и сворачивание ручкой. Корневой каталог показывал март 2028 в тёмной теме и май 2029 в светлой, сохраняя выбранное 15 октября 2026 и четыре результата. Каталог на заданную дату показывал июнь 2030 в светлой теме и июль 2031 в тёмной, сохраняя выбранное 1 октября 2026 и пустую выдачу. После сворачивания показана неделя соответствующей даты просмотра. Переполнений и расхождений с макетами не наблюдалось; локальные снимки находятся в `/tmp/calendar-review-root-*.png` и `/tmp/calendar-review-date-*.png`. Настройки эмулятора восстановлены, запущенные для проверки процессы остановлены.

Результат относится к выбору года и месяца в указанном диапазоне. Физическая проверка оконной политики владельцем по design.md, решению 6, остаётся отдельным условием готовности фазы 2; её выполнение здесь не заявляется. Этот отчёт не устанавливает готовность всего изменения к архивированию.

Коррекции реализации или планирования по результатам ревью не потребовались. Новые задачи не добавлялись; история и статусы существующих задач сохранены. Единственный изменяемый артефакт этапа — настоящий отчёт.
