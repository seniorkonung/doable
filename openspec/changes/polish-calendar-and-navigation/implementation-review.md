# OpenSpec Implementation Review: polish-calendar-and-navigation

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Инкремент фазы 2 соответствует задачам 2.1–2.5. Независимая оценка инженерных решений, проверка соответствия OpenSpec и проверка качества кода завершены без существенных замечаний. Все пять целевых коммитов, пять задач и 13 изменённых путей учтены. Полные проверки проекта и release-сборка прошли; фактическая плавность на телефоне остаётся пользовательской проверкой.

## Review target

- **Baseline ref:** 5f7ded7ebb7ddf75c2df29e74ace8b0766ea0576
- **Base commit:** 5f7ded7ebb7ddf75c2df29e74ace8b0766ea0576
- **Reviewed head:** 64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94
- **Target commits:** ["4257d6044b3956427010953a8567c6d393dc3f1e", "97331a543cb3224f00b65459157a1c84faf3e2fc", "2349b5db0b5dd38732366a5891c4218aab5f4ecb", "67df827a4054a7e5824e78a38ad86a6cfa970381", "64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_paging.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "lib/src/design_system/components/period_picker.dart", "openspec/changes/polish-calendar-and-navigation/tasks.md", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart", "test/design_system/period_picker_test.dart"]
- **OpenSpec change:** polish-calendar-and-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/polish-calendar-and-navigation/tasks.md"]

## Reviewed increment

### U1 · Подписи выбора периода помещаются при постраничном размещении

- **Work items:** ["2.1"]
- **Requirements and scenarios:** ["daily-choice-management: Выбор года и месяца в календаре каталога — допустимые годы, показанный и текущий периоды", "app-appearance: Портретная ориентация на телефоне — поддерживаемая область раскладки", "design: решение 5 — размеры страниц с учётом ширины, локали и масштаба текста"]
- **Affected boundary:** Пользователь встроенного календаря и потребители представления PeriodPicker; подписи лет и месяцев, пустые позиции крайних блоков.
- **Implementation target:** ["lib/src/design_system/components/period_picker.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "test/design_system/period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_layout_test.dart"]
- **Applicable constraints and non-goals:** Русская и английская локали, системный масштаб текста, сохранение естественной раскладки самостоятельного компонента. Геометрия принадлежит представлению, а календарные правила остаются у приложения; область поддержки маленьких окон не расширяется.

### U2 · Годы и страницы лет переключаются плавно без изменения выбранной даты

- **Work items:** ["2.2", "2.3"]
- **Requirements and scenarios:** ["daily-choice-management: Выбор года и месяца в календаре каталога", "daily-choice-management: Страница лет следует за горизонтальным перетягиванием", "daily-choice-management: Стрелка анимирует смену года", "daily-choice-management: Переход к далёкому месяцу не меняет выбранную дату", "daily-choice-management: Сворачивание после выбора месяца показывает его первую неделю", "daily-choice-management: Возврат к месяцу выбранной даты"]
- **Affected boundary:** Жесты, команды шапки и доступная активация выбора периода; граница между внутренней страницей выбора и подтверждённым просмотром календаря.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_paging.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_calendar_period_picker.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_accessibility_test.dart"]
- **Applicable constraints and non-goals:** Блоки по двенадцать лет привязаны к 2020 году и ограничены CalendarDate. Поздний период появляется справа; месяцы одного года не переключаются свайпом. Промежуточные переходы не выбирают дату и не сообщают новый просмотр. Закрытие и завершённый выбор месяца сохраняют прежний контракт событий.
- **Excluded change scope:** Вертикальное управление раскрытием, изменение отступа над календарём и полосы с ручкой относятся к фазе 3. Сценарий сохранения страницы при незавершённом вертикальном сворачивании не является обязательством этого инкремента.

### U3 · Оба каталога сохраняют состояние, выдачу и доступную раскладку

- **Work items:** ["2.4", "2.5"]
- **Requirements and scenarios:** ["daily-choice-management: Начальное состояние и сохранение календаря каталога", "daily-choice-management: Возврат из другого раздела сохраняет просмотр", "daily-choice-management: Каталог дневных выборов на заданную дату", "daily-choice-management: Выбор года и месяца в календаре каталога — отсутствие чтений выдачи и сохранение состояния", "daily-choice-management: Раскрытый месяц доступен на нижней границе поддержки при отказе отметок", "plan: Phase 2 — Ready to advance"]
- **Affected boundary:** Корневой каталог дневных выборов, отдельные каталоги на заданную дату, модели выдачи и отметок, навигация и внешнее хранилище прокрутки.
- **Implementation target:** ["test/daily_choice/presentation/catalog/daily_choice_calendar_period_picker_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_page_storage_test.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_test_support.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart"]
- **Applicable constraints and non-goals:** Состояние принадлежит живому экземпляру каталога; выбранная дата, фильтр выполнения и выдача независимы от промежуточного выбора периода. На границе 360×720 dp сохраняются команды, подписи, сообщение об отказе отметок и прокрутка выдачи. Проверки без устройства обязательны; плавность на телефоне оценивает пользователь позднее.
- **Excluded change scope:** Поведение системного окна Android из фазы 1 не пересматривается. Проверка исходной светлой полосы Redmi не подменяется успешной сборкой; изменение целиком этим этапом не завершается.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий агент `/root/period_decision_review` с fork_turns=none получил нейтральный brief и точные base/head с объединением всех 12 delivery-путей U1–U3. Группировка обусловлена общими изменёнными файлами. Планирование, история коммитов, прежний отчёт и findings ему не передавались. Исходники прочитаны по записанному head; неизменённые контекстные пути проверялись закреплённым diff. Результат: No substantive findings; Coverage: Complete. |
| OpenSpec conformance | Complete | Прочитаны committed proposal, обе delta-specs, design, ADR manifest, относящиеся к календарю ADR, plan/tasks и канонические требования. Все задачи и сценарии сопоставлены с реализацией и тестами. На 64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94 выполнены `mise run check` (2732 теста, exit 0), `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json` (valid: true, issues: []) и release-сборка (exit 0). |
| Code quality | Complete | По `code-review-and-quality` рассмотрен весь delivery-набор: корректность переходов и событий, читаемость, владение состоянием и геометрией, безопасность, производительность, обоснованность тестов. Проверены потребители календаря, PageStorage, доступность, локализация и соответствующие механизмы закреплённого Flutter 3.47.1. Подтверждённых дефектов и неоправданного расширения объёма нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Обзор выполнен 2026-10-16 в `/home/seniorkonung/.paseo/worktrees/1id27gtb/smelly-bird` для диапазона 5f7ded7ebb7ddf75c2df29e74ace8b0766ea0576..64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94. На старте и после проверок рабочее дерево было чистым, HEAD совпадал с Reviewed head. Все versioned evidence прочитаны по полным SHA; незакоммиченные источники не использовались для обоснования реализации. Независимый reviewer прочитал локальный SKILL.md как инструкции, поскольку файл навыка не входит в Git; это не источник сведений о реализации. Прежний отчёт прочитан координатором после независимого прохода: переносимых незакрытых замечаний и принятых рисков нет.

Точный delivery-набор — объединение Implementation target U1–U3: четыре файла реализации, семь файлов проверок и один вспомогательный файл тестов. Единственный оставшийся путь из Reviewable paths — tasks.md, где отмечено завершение пяти задач. Несопоставленных путей и посторонней реализации нет. Остальные плановые документы и неизменённые потребители рассмотрены как контекст, не как дополнительные цели обзора.

Коммит `4257d6044b3956427010953a8567c6d393dc3f1e`, Task ID 6 / 2.1, U1: проверен вклад диапазона 5f7ded7ebb7ddf75c2df29e74ace8b0766ea0576..4257d6044b3956427010953a8567c6d393dc3f1e. Общая геометрия сетки и проверки подписей при разной ширине, локали и масштабе обосновывают отметку задачи.

Коммит `97331a543cb3224f00b65459157a1c84faf3e2fc`, Task ID 7 / 2.2, U2: проверен вклад диапазона 4257d6044b3956427010953a8567c6d393dc3f1e..97331a543cb3224f00b65459157a1c84faf3e2fc. Добавлены движение страниц лет, команды через тот же контроллер и общие параметры анимации календаря; отменено прежнее ожидание запрета свайпа лет.

Коммит `2349b5db0b5dd38732366a5891c4218aab5f4ecb`, Task ID 8 / 2.3, U2: проверен вклад диапазона 97331a543cb3224f00b65459157a1c84faf3e2fc..2349b5db0b5dd38732366a5891c4218aab5f4ecb. Режим месяцев получает собственные страницы по годам; ключ объекта страницы разделяет режимы. Проверены анимация, запрет свайпа, признаки периода и прерывание перехода.

Коммит `67df827a4054a7e5824e78a38ad86a6cfa970381`, Task ID 9 / 2.4, U3: проверен вклад диапазона 2349b5db0b5dd38732366a5891c4218aab5f4ecb..67df827a4054a7e5824e78a38ad86a6cfa970381. Расширены проверки обоих каталогов, внешнего PageStorage, перестроения при смене входов и границы раскладки; вспомогательный MaterialApp получил тёмную тему для проверки смены темы.

Коммит `64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94`, Task ID 10 / 2.5, U3: проверен диапазон 67df827a4054a7e5824e78a38ad86a6cfa970381..64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94. Семантическая активация тестов использует владельца фактического RenderView; отметка checkpoint подтверждена свежими полными проверками и сборкой в этой сессии. Все пять коммитов учтены также в итоговом diff.

В U1 `lib/src/design_system/components/period_picker.dart:30–98` предоставляет рассчитанную геометрию с закрытым конструктором и сохраняет самостоятельное измерение сетки. Календарь использует её в `daily_choice_calendar_period_picker.dart:89–138`: четыре цифры задают размер лет с равноширинными цифрами, названия двенадцати месяцев — размер месяцев. Общий расчёт нужен текущему потребителю для ограниченной высоты страниц, а не для предполагаемого расширения. `period_picker_test.dart` проверяет совпадение естественной и ограниченной геометрии на ширинах 360/540 dp; `daily_choice_calendar_layout_test.dart` проверяет подписи и пустые позиции при годах 1/9999/2026, ru/en и масштабе 1/2.5. Эти проверки защищают разные границы: контракт размеров компонента и его календарные данные.

В U2 `daily_choice_calendar_period_picker.dart:109–161` связывает жесты, шапку и стрелки с текущей страницей, ограничивает индекс и не передаёт промежуточные страницы наружу. `daily_choice_calendar_paging.dart` используется и днями, и выбором периода: 300 мс, Curves.easeOut. Контроллер принадлежит варианту страницы, освобождается при выборе года и закрытии; `keepPage: false` сохраняет изоляцию. Конечные PageView.builder не строят весь диапазон заранее. Новых хранилищ, внешних входов, зависимостей и путей работы с пользовательскими данными нет.

Сценарий следования лет за пальцем показан тестом «страницы лет следуют за удерживаемым жестом в обе стороны с постоянной высотой и без событий календаря»; он проверяет смещение до отпускания. Сценарий анимации года показан тестом «стрелки плавно перемещают месяцы 2028 → 2029 и обратно без изменения высоты и просмотра». Отдельно проверены промежуточные кадры стрелок лет, повторные команды, смена направления, закрытие заголовком/ручкой, выбор ячейки во время перехода и крайние блоки. Это достижимые действия пользователя во время введённой анимации, а не искусственные состояния.

Сценарии перехода к далёкому месяцу и сворачивания к его первой неделе покрывает существующий тест выбора марта 2028 из октября 2026. Существующие тесты возврата к месяцу выбранной даты и повторного выбора того же месяца проверяют один итоговый callback. В `daily_choice_calendar.dart:289–303` итоговая дата просмотра остаётся выбранной датой внутри месяца, иначе первым числом. Проверки доступности выполняют команды обоих режимов в ru/en, проверяют текущий и показанный периоды и недоступность стрелок на границах.

В U3 тест «каталог … не читает выдачу и отметки при перелистывании выбора периода, а после выбора месяца обновляет только отметки» выполняется для обоих каталогов: число чтений выдачи остаётся 2, отметок — 1 до выбора месяца и 2 после него; выбранная дата, фильтр и строки сохраняются. Неизменённый `daily_choice_catalog_body.dart:118–131,217–231` направляет итоговый просмотр в отдельную модель отметок. `daily_choice_calendar_page_storage_test.dart` проверяет внешнее смещение 12 dp после пересоздания; `daily_choice_date_catalog_page_test.dart` — независимость нескольких каталогов одной даты и возврат из подробностей. Существующие `app_shell_state_test.dart` и `daily_choice_catalog_lifecycle_test.dart` включены в полный прогон и подтверждают сохранение корневого экземпляра при навигации.

Проверки `daily_choice_catalog_supported_layout_test.dart` охватывают оба каталога, ru/en, окно 360×720 dp и отказ отметок: все ячейки, шапка и ручка доступны, подписи не обрезаны, у выдачи остаётся прокручиваемая область. Тест перестроения выбора периода сохраняет пролистанные годы/месяцы при обновлении текущего дня, отметок, темы и локали без событий календаря. Существующие примеры Widgetbook продолжают использовать самостоятельный PeriodPicker; их код рассмотрен и статический анализ прошёл, интерактивная визуальная проверка Widgetbook не выполнялась.

Команда `mise run check` завершилась с exit 0 на Reviewed head: форматирование 664 файлов без изменений, проверка CI scope, разрешение зависимостей Widgetbook с enforce-lockfile, flutter analyze без замечаний и 2732 успешных теста. Полный прогон подтверждает checkpoint 2.5. Локальный журнал запуска: `/tmp/polish-phase2-review-check.log`. Проверка `git diff --check 5f7ded7ebb7ddf75c2df29e74ace8b0766ea0576 64bfc64ad37fd3d1ee26d2ad02e28238c06b2b94` также прошла.

Команда `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json` завершилась с exit 0: один valid change, issues отсутствуют. Проверялись неизменённые относительно Reviewed head плановые артефакты. Это структурное свидетельство, не замена проверкам поведения.

Команда `mise exec --no-deps -- flutter build apk --release --no-pub` завершилась с exit 0. Артефакт: `build/app/outputs/flutter-apk/app-release.apk`, 67 779 163 байта, SHA-256 `b9af78e368135ed6c5ecd33e11e8184e23c0058d1a395eeb1ba342fa04e9020d`. Локальный журнал: `/tmp/polish-phase2-review-build.log`. На телефоне остаются непроверенными фактическая плавность горизонтального жеста лет и стрелок обоих режимов, включая их использование в обоих каталогах. По указанию пользователя и AGENTS.md отсутствие устройства не блокирует этап и не означает принятия остаточного риска.

Коррекций кода, тестов или плановых артефактов не потребовалось. История, номера, описания, порядок и завершённость задач сохранены; новые задачи не добавлены. Findings для последующих этапов разрешения отсутствуют. Результат относится только к сохранённому инкременту фазы 2; вертикальное раскрытие фазы 3 и изменение в целом остаются вне утверждения о завершении.
