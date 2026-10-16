# OpenSpec Implementation Review: polish-calendar-and-navigation

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Все семь целевых коммитов и задачи 3.1–3.7 сопоставлены с четырьмя единицами обзора. Активно F2: обязательный mise run check останавливается на unnecessary_import. Восстановление позиции у конца выдачи обоих каталогов закреплено в delta-спецификации и дизайне; реализация и регрессионные проверки принадлежат новой задаче 3.8 и ещё не выполнены. Независимый проход завершён. Принятых остаточных рисков нет. Release- и profile-APK на Reviewed head собраны; поведение системного окна и плавность на телефоне остаются ручными проверками.

## Review target

- **Baseline ref:** 46353889bd41c426e57057da61ac12bfeb814bba
- **Base commit:** 46353889bd41c426e57057da61ac12bfeb814bba
- **Reviewed head:** 3edfa010c82232519c447e52d9183da8175f880a
- **Target commits:** ["935da6b44fd12a34ffabd830ca35c7e5ee7ad4e5", "241e421f7a8d7251d619b57ae92a9fc29f93f901", "2d9c643e56a103834c35c48ba6086aedc5845013", "de87c9f6baecd54847062f2069291f82aa17c072", "fa737ea497ea5da1ef4c44bbf68c001f00cffc81", "c483f5430caf65526dd322f33b9c59b347bb3779", "3edfa010c82232519c447e52d9183da8175f880a"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_expansion.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/design_system/components/calendar_handle.dart", "openspec/changes/polish-calendar-and-navigation/tasks.md", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/design_system/calendar_handle_test.dart", "widgetbook/lib/calendar/calendar_handle_use_cases.dart"]
- **OpenSpec change:** polish-calendar-and-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/polish-calendar-and-navigation/tasks.md"]

## Reviewed increment

### U1 · Ручка доступна без широкой ряби, отступы не увеличивают блок

- **Work items:** ["3.1"]
- **Requirements and scenarios:** ["daily-choice-management: Встроенный недельный и месячный календарь каталога — активация ручки без широкой ряби", "design: решение 3 — перераспределение 8 + 44 в 16 + 36 dp"]
- **Affected boundary:** Пользователь обоих каталогов; полоса ручки, фокус, экранный диктор и геометрия закреплённого блока.
- **Implementation target:** ["lib/src/design_system/components/calendar_handle.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/design_system/calendar_handle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart"]
- **Applicable constraints and non-goals:** Вся ширина полосы принимает нажатие; сохраняются семантическая и клавиатурная активация. Общий минимальный размер остальных компонентов не меняется.

### U2 · Нажатие и вертикальный жест непрерывно меняют высоту календаря

- **Work items:** ["3.2", "3.3"]
- **Requirements and scenarios:** ["daily-choice-management: Раскрытие сохраняет просмотр соседнего периода", "daily-choice-management: Сворачивание сохраняет дату просмотра", "daily-choice-management: Раскрытие следует за пальцем при смене направления", "daily-choice-management: Отпускание возле полного раскрытия завершает переход к месяцу", "daily-choice-management: Короткое перетягивание возвращает неделю"]
- **Affected boundary:** Полоса ручки, две сетки дней и выдача под календарём; граница временного перехода и подтверждённого просмотра.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_expansion.dart", "lib/src/design_system/components/calendar_handle.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_navigation_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "widgetbook/lib/calendar/calendar_handle_use_cases.dart"]
- **Applicable constraints and non-goals:** Выбранная дата, дата просмотра и фильтр сохраняются. Жест вне ручки не управляет раскрытием; устойчивых положений только два. Компонент ручки сообщает события, календарные решения остаются у приложения. Изменения хранения и маршрутизации исключены.

### U3 · Возврат незавершённого сворачивания сохраняет открытую страницу периода

- **Work items:** ["3.4"]
- **Requirements and scenarios:** ["daily-choice-management: Выбор года и месяца в календаре каталога", "daily-choice-management: Незавершённое сворачивание сохраняет страницу выбора периода", "daily-choice-management: Начальное состояние и сохранение календаря каталога"]
- **Affected boundary:** Живой экземпляр выбора лет/месяцев, его контроллер и внешнее хранилище прокрутки.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart"]
- **Applicable constraints and non-goals:** Возврат сохраняет режим и пролистанную страницу, достижение недели закрывает выбор. Тема, локаль, сегодня и отметки не сбрасывают страницу; промежуточные события не меняют выбранную дату и выдачу.

### U4 · Оба каталога сохраняют состояние и доступность в совместной раскладке

- **Work items:** ["3.5", "3.6", "3.7"]
- **Requirements and scenarios:** ["daily-choice-management: Календарь остаётся на месте при прокрутке выдачи", "daily-choice-management: Раскрытый месяц доступен на нижней границе поддержки при отказе отметок", "daily-choice-management: Каталог дневных выборов на заданную дату", "daily-choice-management: Начальное состояние и сохранение календаря каталога", "app-appearance: Портретная ориентация на телефоне — поддерживаемая область интерфейса", "plan: Phase 3 — автоматически проверяемая часть Ready to advance"]
- **Affected boundary:** Корневой каталог, отдельные экземпляры каталога на дату, выдача, модель отметок, общая нижняя панель и навигация.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/app/navigation/app_shell_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_day_marks_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart"]
- **Applicable constraints and non-goals:** Промежуточное раскрытие не выходит в модели и не читает выдачу. Состояние принадлежит своему экземпляру каталога. Поддерживаются ru/en, граница 360×720 dp и существующая область увеличенного текста компонентов. Проверки устройства выполняет пользователь; они не блокируют этот этап и не подтверждаются сборкой.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий агент `/root/independent_decisions`, fork_turns=none, получил нейтральное описание результатов U1–U4 и точный объединённый набор всех 18 delivery/test-путей. Единицы объединены из-за общих изменённых файлов. Плановые артефакты, история коммитов, прежний отчёт и findings ему не передавались. Полные файлы прочитаны на сохранённом head; неизменённый контекст проверялся закреплённым diff. Итог прохода: Changes needed, Coverage: Complete; потеря позиции у конца выдачи независимо подтверждена координатором. Корректирующая задача 3.8 находится за пределами Reviewed head и этим проходом не проверялась. |
| OpenSpec conformance | Complete | Прочитаны committed proposal, обе delta-specs, design, ADR manifest и применимые ADR, plan/tasks, канонические требования. Все задачи и сценарии сопоставлены с кодом и проверками. Строгая валидация OpenSpec прошла, APK собраны; mise run check выявил F2. Отдельный полный прогон flutter test завершился с exit 0: 2760 тестов прошли. Все проверки выполнялись в данном рабочем каталоге с входами сохранённого head; неуспех обязательного check отражён в F2. |
| Code quality | Complete | По code-review-and-quality рассмотрены все 18 delivery/test-путей: корректность событий и отмены, владение состоянием и контроллерами, раскладка, читаемость, безопасность, производительность и необходимость элементов. Проверены потребители, PageStorage, ru/en, семантика и код закреплённого table_calendar 3.3.0. Подтверждены потеря позиции у конца выдачи, переданная в задачу 3.8, и F2; иных существенных дефектов или избыточных элементов не установлено. |

## Findings

### F2 · Medium — Обязательные проверки фазы останавливаются на лишнем импорте

- **Evidence:** Добавленный `package:flutter/rendering.dart` в `test/design_system/calendar_handle_test.dart:8` уже предоставляет используемые элементы `package:flutter/semantics.dart`, оставленного на строке 9. На сохранённом head команда `mise run check` прошла форматирование, проверки CI scope и разрешение зависимостей Widgetbook, затем flutter analyze выдал `unnecessary_import` на строке 9 и завершил задачу с exit 1 до запуска flutter test. Отдельный `mise exec --no-deps -- dart analyze test/design_system/calendar_handle_test.dart` повторил ту же диагностику. Отметка 3.7 в `openspec/changes/polish-calendar-and-navigation/tasks.md:196–201` требует успешных полных проверок; текущий результат её не подтверждает.
- **Evidence revisions:** ["3edfa010c82232519c447e52d9183da8175f880a"]
- **Impact:** Штатная проверка проекта и контрольная точка фазы не проходят. Это воспроизводимый отказ обязательного процесса проверки, а не предпочтение оформления импорта; отдельный успешный прогон тестов его не устраняет.
- **Required outcome:** Устранить избыточный импорт и подтвердить успешный mise run check после исправления. Существующего анализатора достаточно для защиты от повторения; отдельный тест импорта не нужен.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/design_system/calendar_handle_test.dart", "tasks: 3.7"]

## Review coverage

Обзор выполнен 2026-10-16 в `/home/seniorkonung/.paseo/worktrees/1id27gtb/smelly-bird` для указанного Base..Reviewed head. На старте рабочее дерево чистое, HEAD совпадает с Reviewed head; после проверок изменён только отчёт; входы всех проверок соответствуют этому снимку. Код и версионируемые плановые артефакты прочитаны по полным SHA, незакоммиченные артефакты не использовались. Старый отчёт прочитан координатором после завершения независимого прохода: переносимых findings и accepted risks нет. Локальные SKILL.md служат инструкциями, не доказательствами поведения.

Точный delivery-набор — объединение Implementation target U1–U4: пять production-файлов, двенадцать файлов тестов и один пример Widgetbook. Девятнадцатый reviewable path — tasks.md, плановое свидетельство, где изменены только семь отметок завершения. Несопоставленных путей, посторонней реализации и исключённых изменений рабочего дерева нет. Полнота объединения 18 путей и одного planning-пути, всех семи задач и порядок Target commits дополнительно проверены программно. Неизменённые потребители и планирование рассмотрены как контекст. Android-реализация фазы 1 и горизонтальное перелистывание фазы 2 не добавлены в целевой диапазон; проверяется их совместимость с текущим инкрементом.

Каждый коммит рассмотрен в порядке workflow и в итоговом diff:

Task ID / номер 11 / 3.1, U1: рассмотрен диапазон `46353889bd41c426e57057da61ac12bfeb814bba`..`935da6b44fd12a34ffabd830ca35c7e5ee7ad4e5`. Верхний отступ 16 dp, полоса 36 dp, отсутствие ряби, фокус и активация; сохранена сумма 52 dp.

Task ID / номер 12 / 3.2, U2: рассмотрен диапазон `935da6b44fd12a34ffabd830ca35c7e5ee7ad4e5`..`241e421f7a8d7251d619b57ae92a9fc29f93f901`. Контроллер раскрытия, измеряющий RenderBox, фиксированные сетки, единичное итоговое событие; проверки промежуточных кадров и прерывания.

Task ID / номер 13 / 3.3, U2: рассмотрен диапазон `241e421f7a8d7251d619b57ae92a9fc29f93f901`..`2d9c643e56a103834c35c48ba6086aedc5845013`. Жесты и скорость, глобальные координаты, отмена, обратный ход, представление шеврона и пример Widgetbook.

Task ID / номер 14 / 3.4, U3: рассмотрен диапазон `2d9c643e56a103834c35c48ba6086aedc5845013`..`de87c9f6baecd54847062f2069291f82aa17c072`. Сохранение экземпляра выбора периода, остановка его перелистывания, контроллер до первой раскладки и изоляция PageStorage.

Task ID / номер 15 / 3.5, U4: рассмотрен диапазон `de87c9f6baecd54847062f2069291f82aa17c072`..`fa737ea497ea5da1ef4c44bbf68c001f00cffc81`. Проверки выдачи, отметок, фильтра, независимости экземпляров и навигации. Непокрытый предел прокрутки требует корректирующей реализации и проверки по задаче 3.8.

Task ID / номер 16 / 3.6, U4: рассмотрен диапазон `fa737ea497ea5da1ef4c44bbf68c001f00cffc81`..`c483f5430caf65526dd322f33b9c59b347bb3779`. Семантика перехода и возврата, ru/en, размеры ячеек, ручка и Notice вне обрезки, область выдачи на 360×720 dp.

Task ID / номер 17 / 3.7, U4: рассмотрен диапазон `c483f5430caf65526dd322f33b9c59b347bb3779`..`3edfa010c82232519c447e52d9183da8175f880a`. Только отметка checkpoint; повторены проверки и обе сборки. Отказ mise run check установлен как F2.


Проверка diff --check каждого из семи taskCommitRanges прошла. В целевом диапазоне изменялись только отметки завершения задач. При передаче корректирующей работы в планирование все существующие блоки задач сохранены дословно; после них добавлена незавершённая задача 3.8.

U1: Keyboard Enter/Space и семантическое действие покрывает `calendar_handle_test.dart` вместе с нажатиями у обоих краёв полосы. Проверка пикселей ловит именно широкую заливку и отсутствие видимого фокуса; геометрию 16 + 36 dp проверяют потребители календаря. Эти проверки защищают разные наблюдаемые регрессии.

U2: `daily_choice_calendar_transitions_test.dart` проверяет следование пальцу, обратный ход после границы, отсутствие самостоятельной анимации при удержании, расстояния 0.25/0.5/0.75, скорость по обе стороны 600 dp/с, системную отмену и перехват анимации новым жестом. Нажатия используют тот же переход; проверены пропорциональная длительность до 200 мс, смена цели, внешняя смена просмотра и удаление календаря без позднего события. `daily_choice_calendar_navigation_test.dart` сохраняет проверку вертикального жеста на сетке и выбора дня после завершения перехода. Скрытые сетки измеряются для текущей раскладки, но не создают событий и доступных действий; собственные контроллеры и PageStorage исключают смешивание страниц. Постоянное число сеток и локальное перестроение не вводят неограниченной работы или чтений на кадр.

U3: Сценарий незавершённого сворачивания страницы 2032–2043 покрыт `daily_choice_calendar_transitions_test.dart` для лет и месяцев вместе с полной сменой представления. `daily_choice_calendar_period_picker_test.dart` проверяет остановку горизонтального перехода до и после смены страницы, жест сразу после выбора года и сохранение страницы при смене отметок, сегодня, темы и локали. После возврата выбранный месяц продолжает давать единственное итоговое событие. `daily_choice_calendar_page_storage_test.dart` проверяет внешнее смещение 12 dp после переходов и пересоздания.

Сопоставление относящихся к инкременту сценариев:

Раскрытие сохраняет просмотр соседнего периода: `daily_choice_calendar_transitions_test.dart`: сценарий с выбранной 2026-10-04 и просмотром ноября; `daily_choice_catalog_day_marks_test.dart`: неизменность фильтра и чтений выдачи.

Сворачивание сохраняет дату просмотра; возврат к месяцу выбранной даты: `daily_choice_calendar_navigation_test.dart`: точная неделя даты просмотра; `daily_choice_calendar_transitions_test.dart`: сворачивание при возврате к месяцу выбранного дня.

Следование пальцу, отпускание возле полного раскрытия, короткий возврат: `daily_choice_calendar_transitions_test.dart`: удержание с обратным ходом и параметризованные медленные движения в обе стороны.

Незавершённое сворачивание сохраняет страницу выбора периода: `daily_choice_calendar_transitions_test.dart` и `daily_choice_calendar_period_picker_test.dart`: пролистанные годы/месяцы, отмена, медленный возврат и смена цели.

Выбор дня сохраняет раскрытое представление; просмотр не меняет фильтр: `daily_choice_calendar_navigation_test.dart` и `daily_choice_catalog_day_marks_test.dart`: раздельные события дня/просмотра и счётчики чтений обоих каталогов.

Календарь закреплён, отказ отметок не мешает доступной раскладке: `daily_choice_catalog_layout_test.dart` и `daily_choice_catalog_supported_layout_test.dart`: оба потребителя, промежуточные кадры, ru/en, Notice и прокручиваемая выдача. Сохранение позиции у конца выдачи пока нарушено; реализация и регрессионные проверки запланированы в задаче 3.8.

Сохранение живого экземпляра при навигации: `app_shell_state_test.dart` и `daily_choice_date_catalog_page_test.dart`: возврат ручки, смена пункта, подробности и независимые каталоги одной даты.


Проверки семантики в `daily_choice_calendar_accessibility_test.dart` исключают дни и выбор периода во время перехода, оставляя ручку и live-region сообщения; конечные представления сохраняют соответствующие команды. `daily_choice_calendar_layout_test.dart` проверяет несжатые ячейки лет/месяцев и подписи ru/en при масштабе 1 и 2.5; нижняя граница обоих каталогов проверена при стандартном масштабе по app-appearance. Механизм отказа отметок уже принадлежит модели и Notice, новый обработчик ошибок или отдельное получение данных не добавлены. Новых внешних входов, сетевых интеграций, изменений хранения или зависимостей нет.

Первый запуск discover-review-target ошибочно использовал openspec напрямую вместо предписанной формы запуска. Разрешение границ повторено с временным wrapper, вызывающим `mise exec --no-deps -- openspec`; отчёт использует повторный результат. Ошибка способа запуска не меняла репозиторий или диапазон; последующие команды OpenSpec выполнены через mise.

Свежие проверки на Reviewed head:

Команда `mise run check`: Exit 1: форматирование и CI scope прошли, зависимости Widgetbook разрешены с enforce-lockfile; flutter analyze остановил процесс на F2. Журнал `/tmp/polish-calendar-review-check.log`.

Команда `mise exec --no-deps -- flutter test --concurrency=2`: Exit 0, все 2760 тестов прошли за 12 мин 54 с. Выполнен отдельно, поскольку mise run check остановился до тестов; его отказ остаётся F2. Журнал `/tmp/polish-calendar-review-tests.log`.

Команда `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json`: Exit 0, valid: true, issues: []. Плановые входы совпадают с сохранённым head. Это структурная проверка, не доказательство поведения.

Команда `mise exec --no-deps -- flutter build apk --release`: Exit 0; `build/app/outputs/flutter-apk/app-release.apk`, 67 811 931 байт, SHA-256 `64312c0221609e503e05910d7e637072f3ef6dfa44546869c2825493941c9ae3`. Журнал `/tmp/polish-calendar-review-release.log`.

Команда `mise exec --no-deps -- flutter build apk --profile`: Exit 0; `build/app/outputs/flutter-apk/app-profile.apk`, 88 630 629 байт, SHA-256 `158e319df689ddc5a008963ce20fab4669679d95d6437b0499f49500776adf29`. Журнал `/tmp/polish-calendar-review-profile.log`.

Временные проверки прокрутки: `mise exec --no-deps -- flutter test --reporter expanded /tmp/polish_calendar_scroll_review_test.dart` и аналогично `/tmp/polish_calendar_scroll_release_review_test.dart`: Обе команды exit 1, по два падения ожидаемого сохранения смещения при cancel и медленном отпускании в обоих каталогах. Исправление и постоянные проверки этого поведения принадлежат задаче 3.8. Журналы `/tmp/polish-calendar-review-scroll.log` и `/tmp/polish-calendar-review-scroll-release.log`. Исследовательские файлы находятся вне репозитория и не входят в целевой диапазон или поставку.


По AGENTS.md и указанию пользователя устройства и эмуляторы не запускались. Пользователю остаются: удобство захвата полосы 36 dp, плавность обоих направлений и быстрых жестов в profile-сборке, повторные нажатия, сохранение страницы периода, горизонтальное перелистывание и прокрутка выдачи в обоих каталогах; визуальная сверка ручки и панели обеих тем в Widgetbook. Для Redmi Note 15 Pro+ 5G остаются неизвестными версии Android/HyperOS и фактический результат запуска в обеих темах, жестовой навигации и трёх кнопок, смены темы и возврата после клавиатуры/листа на Главной и в каталоге. Непроверенные границы Android: API 24–25 — тёмная подложка со светлыми кнопками, API 26–28 — цвет и контраст, API 29 — оба режима edge-to-edge, API 35/36 — принудительный edge-to-edge. Нужно подтвердить фон, различимость системных элементов и собственные 6 dp дополнительно к системному отступу. Отсутствие этих ручных проверок не блокирует этап и не доказывает исправление исходной системной полосы.

Согласованное пользователем восстановление позиции закреплено в требовании «Встроенный недельный и месячный календарь каталога» [delta-спецификации](specs/daily-choice-management/spec.md), решениях 4 и 6 [дизайна](design.md) и незавершённой задаче 3.8 в [tasks.md](tasks.md). Это передача исправления в планирование, а не подтверждение исправленного поведения. Код и тесты не изменялись, остаточный риск не принимался. F2 остаётся активным без изменения доказательств и требуемого результата; поэтому общий результат — Changes needed. Фаза 3 не завершена: её завершение определяет последующее ревью реализации после последней задачи.

Проверка обновлённых плановых артефактов: `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json` — exit 0, valid: true, issues: []. Проверки реализации и сборки при передаче в планирование не запускались; приведённые выше результаты относятся только к Reviewed head.
