# OpenSpec Implementation Review: redesign-navigation-bar

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Проверены все шесть целевых коммитов и задачи 2.1–2.6 фазы 2. Подтверждён один дефект средней серьёзности: F1 — непрокручиваемая шапка листа полностью скрывает варианты в компактном окне с увеличенным текстом. Остальные потоки, хранение режима, доступность и примеры Widgetbook проверены без дополнительных замечаний. Принятых остаточных рисков нет. Замечание оставлено для последующего этапа разрешения; исправление не выполнено.

## Review target

- **Baseline ref:** c7b0cc7198b30c45faf9d777023e2209e6c62c71
- **Base commit:** c7b0cc7198b30c45faf9d777023e2209e6c62c71
- **Reviewed head:** a9c5750386ebe70cf9b3d0e749cc7de5beecb202
- **Target commits:** ["194df4622131a829e28ac5b47ed2a8a4950f6327", "38c4cf063a71d344feb5abeab0d3e66d8c7fef6f", "649f0fbe39211736508e0412d836be0161e0f02f", "56fbc1e1b93f8272514586007a3cf3a31704d8d8", "6b5322dd077605d47de88d2621501d03809a1504", "a9c5750386ebe70cf9b3d0e749cc7de5beecb202"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart", "lib/src/app/quick_creation/quick_creation_launcher.dart", "lib/src/app/quick_creation/quick_creation_mode.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/app/quick_creation/quick_creation_mode_presentation.dart", "lib/src/design_system/components/action_sheet.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_shadows.dart", "lib/src/design_system/doable_theme.dart", "openspec/changes/redesign-navigation-bar/tasks.md", "test/app/bootstrap/app_runtime_quick_creation_mode_test.dart", "test/app/creation_flows_integration_test.dart", "test/app/creation_flows_test_support.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/navigation/app_navigation_transition_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/quick_creation/file_quick_creation_mode_store_test.dart", "test/app/quick_creation/quick_creation_accessibility_test.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart", "test/app/quick_creation/quick_creation_launcher_test.dart", "test/app/quick_creation/quick_creation_launcher_test_support.dart", "test/app/quick_creation/quick_creation_mode_controller_test.dart", "test/app/quick_creation/quick_creation_mode_menu_test.dart", "test/app/quick_creation/quick_creation_mode_presentation_test.dart", "test/app/quick_creation/quick_creation_mode_process_test.dart", "test/app/quick_creation/quick_creation_navigation_test.dart", "test/app/quick_creation/quick_creation_runtime_restart_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_flow_test.dart", "test/daily_choice/presentation/daily_choice_creation_launcher_test.dart", "test/support/quick_creation.dart", "widgetbook/lib/catalog.dart", "widgetbook/lib/navigation/app_navigation_bar_use_cases.dart", "widgetbook/lib/navigation/quick_creation_sheets_use_cases.dart"]
- **OpenSpec change:** redesign-navigation-bar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-navigation-bar/tasks.md"]

## Reviewed increment

### U1 · Общие листы сохраняют модальность и доступность вариантов

- **Work items:** ["2.1", "2.2", "2.4", "2.6"]
- **Requirements and scenarios:** ["quick-creation / Выбор начала дневного выбора", "quick-creation / Меню режимов", "quick-creation / Локализация и доступность быстрого создания", "design.md / Решения 1, 3, 7 и 11", "ADR-0029", "ADR-0030", "ADR-0032"]
- **Affected boundary:** Человек, выбирающий вариант модального листа касанием, клавиатурой или экранным диктором; общие оформление, системные отступы и изоляция исходной страницы.
- **Implementation target:** ["lib/src/design_system/components/action_sheet.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_shadows.dart", "lib/src/design_system/doable_theme.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart", "test/app/quick_creation/quick_creation_mode_menu_test.dart"]
- **Applicable constraints and non-goals:** Лист перекрывает корневой навигатор и нижнюю панель, возвращает типизированный результат либо отмену; закрытие и барьер принадлежат Material. Компоненты получают готовые тексты и обработчики, без предметных типов и локализации приложения. Две темы, перенос текста и доступные варианты сохраняются. Существующая тема остальных нижних панелей не меняется; новые варианты листов без текущего потребителя не требуются.

### U2 · Три сохраняемых режима продолжают прежние потоки создания

- **Work items:** ["2.2", "2.3", "2.4", "2.6"]
- **Requirements and scenarios:** ["quick-creation / Выбор начала дневного выбора / Нажатие открывает выбор начала", "quick-creation / Режимы быстрого создания", "quick-creation / Запуск режима поверх текущей страницы", "quick-creation / Меню режимов / Смена режима не запускает создание", "quick-creation / Сохранение режима между запусками", "quick-creation / Локализация и доступность быстрого создания", "daily-choice-management / Входы в создание дневного выбора", "app-navigation / Выход из потока создания", "app-navigation / Открытие созданной сущности"]
- **Affected boundary:** Человек, меняющий режим или запускающий создание над обычной страницей; границы между листом, поиском, потоком создания и настройкой установки.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart", "lib/src/app/quick_creation/quick_creation_launcher.dart", "lib/src/app/quick_creation/quick_creation_mode.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/app/quick_creation/quick_creation_mode_presentation.dart", "test/app/bootstrap/app_runtime_quick_creation_mode_test.dart", "test/app/creation_flows_integration_test.dart", "test/app/creation_flows_test_support.dart", "test/app/daily_choice_app_lifecycle_test.dart", "test/app/navigation/app_navigation_transition_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/quick_creation/file_quick_creation_mode_store_test.dart", "test/app/quick_creation/quick_creation_accessibility_test.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart", "test/app/quick_creation/quick_creation_launcher_test.dart", "test/app/quick_creation/quick_creation_launcher_test_support.dart", "test/app/quick_creation/quick_creation_mode_controller_test.dart", "test/app/quick_creation/quick_creation_mode_menu_test.dart", "test/app/quick_creation/quick_creation_mode_presentation_test.dart", "test/app/quick_creation/quick_creation_mode_process_test.dart", "test/app/quick_creation/quick_creation_navigation_test.dart", "test/app/quick_creation/quick_creation_runtime_restart_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_flow_test.dart", "test/daily_choice/presentation/daily_choice_creation_launcher_test.dart", "test/support/quick_creation.dart"]
- **Applicable constraints and non-goals:** Ровно три режима в заданном порядке, выбор направления только при запуске дневного выбора, один поток при повторных нажатиях. Меню меняет режим без запуска и ожидания записи. Исходная история, выбранный пункт и ввод сохраняются; отмена и открытие созданной сущности следуют существующим контрактам. Режим сохраняется вне графа прежним адаптером с последовательной очередью и безопасной диагностикой. Оба устаревших ключа считаются неизвестными; миграции рабочих установок нет. Поиск, построение пути, схема графа и остальные панели не расширяются.
- **Excluded change scope:** Реализация панели фазы 1, не изменённая этим диапазоном, служит контекстом сохранённого поведения. Параллельное изменение календаря не входит в цель ревью.

### U3 · Widgetbook даёт сверить листы, строки и три режима панели

- **Work items:** ["2.5", "2.6"]
- **Requirements and scenarios:** ["plan.md / Phase 2 / Примеры листов и строк в обеих темах", "design.md / Решение 11", "tasks.md / 2.5 / Оба листа, три состояния строк и все режимы панели"]
- **Affected boundary:** Человек, вручную сверяющий оформление в каталоге без маршрутизатора и хранилища приложения.
- **Implementation target:** ["widgetbook/lib/catalog.dart", "widgetbook/lib/navigation/app_navigation_bar_use_cases.dart", "widgetbook/lib/navigation/quick_creation_sheets_use_cases.dart", "lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart", "lib/src/app/quick_creation/quick_creation_mode.dart", "lib/src/app/quick_creation/quick_creation_mode_presentation.dart", "lib/src/design_system/components/action_sheet.dart", "lib/src/design_system/components/option_row.dart"]
- **Applicable constraints and non-goals:** Оба листа и три состояния строки используют production-компоненты и данные представления; панель позволяет выбрать каждый режим при каждом выбранном пункте. Существующая конфигурация предоставляет две темы. Автоматические тесты каталога исключены widgetbook/AGENTS.md; поведение production-компонентов проверяется тестами приложения.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный агент `/root/decision_complete`, `fork_turns=none`, проверил все 42 пути объединения U1/U2/U3 и каждый из трёх исходов. Общие изменённые компоненты и потребительские тесты образуют одну группу; границы заданы целыми файлами. Переданы только нейтральные намерения, репозиторий, точные commit IDs и delivery-пути, без planning artifacts, истории коммитов и прежнего отчёта. Контекстные пути проверены через diff --quiet перед чтением. Результат — Changes needed, полное покрытие; кандидат F1 подтверждён чтением пробы и журнала координатора. |
| OpenSpec conformance | Complete | Proposal, specs, design, ADR manifest, plan и tasks прочитаны из `a9c5750386ebe70cf9b3d0e749cc7de5beecb202`; CLI подтвердил intent-driven и завершённые задачи. Проверены сценарии и критерии именно фазы 2, включая отметки завершения и записанные ручные проверки. `mise run check`: код 0, 2660 тестов. Строгая OpenSpec-валидация: код 0, без issues. Дополнительная проба на том же head выявила F1, поэтому успешный штатный набор не принят за доказательство доступности при любой поддерживаемой высоте. |
| Code quality | Complete | По code-review-and-quality проверены корректность, читаемость, архитектура, безопасность, производительность и доказательства для всех 42 delivery/test-путей. Прослежены неизменённые AppNavigation, контроллер и файловое хранилище режима, bootstrap, DailyChoiceCreationLauncher, маршрутизатор, границы создания, темы и конфигурация Widgetbook. Подтверждён общий корень F1; другие существенные дефекты, неоправданные варианты, дублирующие механизмы или ослабленные утверждения тестов не обнаружены. |

## Findings

### F1 · Medium — Шапка листа полностью скрывает варианты при малой высоте окна

- **Evidence:** В `lib/src/design_system/components/sheet.dart:103` ручка, заголовок и пояснение — непрокручиваемые дети Column; только тело получает остаток высоты через Flexible/SingleChildScrollView в строке 141. Оба потребителя используют эту раскладку через ActionSheet. На reviewed head воспроизведены три отказа с настоящим Inter, русской локалью, масштабом текста 200%, DPR 1 и согласованными padding/viewPadding 24 dp сверху и 34 dp снизу, без клавиатуры: окно 320×240 — меню режимов имеет область вариантов 0 dp и RenderFlex overflow 18 dp; окно 320×220 — область вариантов обоих листов 0 dp, переполнение меню 38 dp и листа начала 2 dp. Прокрутка не возвращает доступ к вариантам при нулевой высоте. Неизменённые `android/app/src/main/AndroidManifest.xml:9` и `lib/main.dart:32` не ограничивают размер окна или масштаб текста; изменение окна в режиме нескольких окон Android — достижимое событие среды. Официальные правила режима и минимальных размеров подтверждены [Android Developers](https://developer.android.com/develop/adaptive-apps/guides/support-multi-window-mode). Текущие проверки увеличенного текста (`test/app/quick_creation/quick_creation_mode_menu_test.dart:127` и `quick_creation_daily_choice_start_sheet_test.dart:139`) используют высоту 568 dp и не выявляют этот отказ.
- **Evidence revisions:** ["a9c5750386ebe70cf9b3d0e749cc7de5beecb202"]
- **Impact:** Пользователь с увеличенным текстом после уменьшения окна не может увидеть и выбрать режим; при меньшей высоте недоступен и выбор начала дневного выбора. Закрытие листа остаётся возможным, но нужное действие создания заблокировано до изменения условий окна или текста.
- **Required outcome:** Оба листа позволяют увидеть и выбрать каждый вариант при поддерживаемой компактной высоте, увеличенном тексте и системных отступах, без переполнения раскладки. Проверка должна ловить подтверждённую потерю всей области вариантов у общего компонента.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/sheet.dart", "test/app/quick_creation/quick_creation_mode_menu_test.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart"]

## Review coverage

Каждый коммит и каждая задача сопоставлены с единицами ревью; приведённые task IDs, номера и описания совпадают с сохранённым workflow и tasks.md.

Задача ID 4 (2.1 Модуль основ предоставляет листы `Sheet`, `ActionSheet` и `OptionRow` с единым показом над корневым навигатором), коммит `194df4622131a829e28ac5b47ed2a8a4950f6327`: U1. Общие компоненты, типизированный конец строки, показ, тень и тема; F1 введён раскладкой Sheet в этом коммите.

Задача ID 5 (2.2 Лист «Новый дневной выбор» возвращает выбранное направление или отмену, сохраняя исходную страницу), коммит `38c4cf063a71d344feb5abeab0d3e66d8c7fef6f`: U1, U2. Два локализованных варианта, результаты/отмена, потребительские проверки модальности и доступности.

Задача ID 6 (2.3 Быстрое создание использует три сохраняемых режима и запускает оба направления дневного выбора через лист выбора начала), коммит `649f0fbe39211736508e0412d836be0161e0f02f`: U2. Три ключа и значка, запуск через лист, оба направления и согласование всех затронутых сценариев хранения, навигации и создания.

Задача ID 7 (2.4 Удержание кнопки открывает меню трёх режимов на `ActionSheet` с пояснениями и отметкой текущего режима), коммит `56fbc1e1b93f8272514586007a3cf3a31704d8d8`: U1, U2. Меню, пояснения и выбранность, начальный фокус, выбор без запуска/ожидания записи, адаптация помощников.

Задача ID 8 (2.5 Widgetbook показывает оба листа, состояния строк и панель с тремя режимами для сверки дизайна), коммит `6b5322dd077605d47de88d2621501d03809a1504`: U3. Регистрация примеров, три состояния OptionRow, режимы панели, записанная ручная сверка.

Задача ID 9 (2.6 Проверить готовность фазы 2: три режима и листы дизайна выполняют спецификации, сохраняя потоки создания), коммит `a9c5750386ebe70cf9b3d0e749cc7de5beecb202`: U1, U2, U3. Контрольная задача без изменения поведения: проверены критерии, запись проверок в коммите и свежие результаты сессии; F1 показывает неполноту прежней проверки компактной высоты.


Проверены совокупный diff и шесть последовательных диапазонов задач, от base до первого target commit и далее между соседними target commits. Промежуточных изменённых путей, отсутствующих в итоговом диапазоне, нет. Все 43 reviewable-пути учтены: tasks.md — планирующее доказательство, оставшиеся 42 — точный delivery/test-набор в объединении Implementation target U1/U2/U3. Несопоставленного или постороннего изменения нет. Неизменённые файлы использованы только как контекст и доказательство сохранённого поведения, а не расширение цели.

Сопоставление требований и сценариев с доказательствами на reviewed head:

Лист выбора начала, порядок вариантов, типизированный результат, отсутствие поиска до выбора. `quick_creation_daily_choice_start_sheet.dart:11`, `:34`; `quick_creation_daily_choice_start_sheet_test.dart:40` проверяет RU/EN, порядок и оба направления.

Закрытие фоном, свайпом и назад; корневая модальность, сохранение страницы, ввода и выбранного пункта. `sheet.dart:26`; `quick_creation_daily_choice_start_sheet_test.dart:77`, `:100`; общие правила проверены на одном потребителе.

«Режим связи открывает пустую форму», «Выбор от намерения начинается с поиска основания» и «Быстрые повторные нажатия открывают один поток». `quick_creation_mode.dart:2`, `quick_creation_launcher.dart:26`, `:41`; `quick_creation_launcher_test.dart:63` проверяет три режима и оба направления над корнем и глубокой историей. Повторный запуск проверяется до выбора направления и после открытия поиска.

Отмена листа не запускает поиск и освобождает запуск. `quick_creation_launcher.dart:51`; `quick_creation_launcher_test.dart:29` сохраняет историю и несохранённое название при двух повторных открытиях.

«Создание не закрывает глубокую историю», «Отмена возвращает на исходную страницу», выбранный пункт сохраняется. `quick_creation_launcher_test.dart:63`, `:153`; `quick_creation_navigation_test.dart:24`; `creation_flows_integration_test.dart:144`, `:203`; проверки сравнивают идентичности маршрутов и черновики, а не только наличие страницы.

«Пустой граф не блокирует режим», оба поисковых входа и вход «Выбрать действие по пути» со страницы намерения. `daily_choice_creation_launcher_test.dart:207`, `:126`; `daily_choice_creation_flow_test.dart:906`; прежние поиски и launcher не изменены, помощники теперь явно выбирают направление в листе.

Выбранное основание передаётся по ID; готовность не ограничивает поиск основания. Неизменённый DailyChoiceCreationLauncher и исходный поиск; `daily_choice_creation_launcher_test.dart:338`, сценарии совместного поиска в `test/daily_choice/presentation/source_picker/`.

«Сохранённый маршрут не предлагается при новом выборе», сохранение прежних путей, отмены и открытия созданного. `daily_choice_creation_flow_test.dart:260`, `:433`, `:906`; `creation_flows_integration_test.dart:144`; исходная история и параметры каталогов проверяются после закрытия созданного представления.

«Назад во время сохранения не разрешает второе подтверждение» и контракт ухода после принятия команды. Неизменённые `test/daily_choice/presentation/daily_choice_creation_exit_test.dart:54` (возврат из принятого подтверждения, отсутствие нового подтверждения и выход с одной записью) и `daily_choice_creation_flow_session_test.dart:122` (повторный обработчик не отправляет вторую команду); общие проверки занятости и выхода сохранены.

Меню показывает три режима, пояснения и галочку; выбранный режим получает фокус; выбор не запускает создание. `quick_creation_mode_menu.dart:30`, `quick_creation_mode_presentation.dart:7`; `quick_creation_mode_menu_test.dart:48` проверяет RU/EN, порядок, выбранность/фокус, немедленный выбор и Enter; `quick_creation_accessibility_test.dart` проверяет удержание и доступное действие.

Три ключа, оба устаревших ключа, первый запуск и восстановление режима. `quick_creation_mode.dart:8`; `file_quick_creation_mode_store_test.dart:49`, `:90`; `quick_creation_mode_controller_test.dart:12`; `quick_creation_runtime_restart_test.dart:51`.

Нечитаемый режим и отказ записи не мешают интерфейсу, диагностика обезличена. `file_quick_creation_mode_store_test.dart:66`, `:109`, `:138`; `app_runtime_quick_creation_mode_test.dart`; `quick_creation_runtime_restart_test.dart:90`, `:117`.

Новый выбор действует до завершения предыдущей записи; отказ не останавливает очередь; последний отказ сохраняет предыдущий успех. Неизменённые QuickCreationModeController и FileQuickCreationModeStore; `file_quick_creation_mode_store_test.dart:138`, `:235`, `:275`, `:315`; `quick_creation_mode_process_test.dart:43`, `:82` проверяет отдельный процесс и остановку во время записи.

Названия и доступные действия RU/EN; варианты объявляются кнопками, режимы — с выбранностью. Оба ARB и generated-файлы согласованы; `quick_creation_mode_menu_test.dart:48`, `quick_creation_daily_choice_start_sheet_test.dart:40`, `quick_creation_accessibility_test.dart`, `quick_creation_mode_presentation_test.dart`.

Панель, сообщения, параметры скрытых корневых страниц и история при переходах. Затронутые проверки `app_navigation_transition_test.dart`, `app_shell_layout_test.dart`, `app_shell_page_matrix.dart`, `ordinary_page_layout_scenarios.dart`, `daily_choice_app_lifecycle_test.dart` сохраняют утверждения и прошли; реализация панели и её высота не меняются этим диапазоном.

Widgetbook: оба листа, состояния строки, все режимы при каждом выбранном пункте, две темы. `widgetbook/lib/catalog.dart:33`, `navigation/quick_creation_sheets_use_cases.dart:13`, `:54`, `app_navigation_bar_use_cases.dart:27`; неизменённая конфигурация Widgetbook предоставляет темы и локализацию.


Проверены границы модуля основ и потребителей по ADR-0020, ADR-0021, ADR-0022, ADR-0029, ADR-0030 и ADR-0032. Функция показа не знает маршрутов auto_route; предметный результат и продолжение принадлежат приложению. Тень добавлена в единственное расширение темы, прежняя bottomSheetTheme не меняется. Удаление старых режимов не ослабило обе ветви выбора пути. Новые варианты компонентов обслуживают текущих потребителей; неоправданных расширений и обработчиков недостижимых состояний не найдено. Новых зависимостей, сетевых операций, разрешений, пользовательских данных в диагностике или изменений схемы хранения нет. Увеличения запросов к графу и неограниченной работы новый код не вводит.

Свежая проверка выполнена в `/home/seniorkonung/.paseo/worktrees/1id27gtb/just-wasp`, исходный HEAD — `a9c5750386ebe70cf9b3d0e749cc7de5beecb202`, рабочее дерево до проверок и после них, до создания отчёта, было чистым:

Команда `mise run check` — код 0; форматирование 636 файлов, 0 изменений; проверка области CI и разрешение зависимостей Widgetbook с сохранённым lockfile успешны; анализ без замечаний; 2660 тестов прошли. Журнал сессии: `/tmp/navigation-review-check.log`.

Команда `mise exec --no-deps -- openspec validate redesign-navigation-bar --strict --json` — код 0; один корректный change, 0 issues. Это структурная проверка совпадающих с head планирующих файлов.

Команда `git --literal-pathspecs diff --check c7b0cc7198b30c45faf9d777023e2209e6c62c71 a9c5750386ebe70cf9b3d0e749cc7de5beecb202` — код 0.

Команда `mise exec --no-deps -- flutter test --no-pub /tmp/navigation_sheet_height_probe_test.dart --reporter expanded` — код 1, три проверки прошли и три завершились подтверждённым F1. Контрольное окно 568×320 при тех же шрифте/масштабе/отступах даёт 142 dp для вариантов обоих листов без исключений. При 320×240 лист начала имеет 18 dp без исключения, меню — нулевую область с переполнением. Повтор с явно согласованными padding/viewPadding дал тот же результат. Проба и журнал `/tmp/navigation-review-height-probe.log` находятся вне репозитория; они воспроизводят дефект и не являются исправлением или добавленными тестами проекта.


Для повторения F1 достаточно минимального MaterialApp с делегатами AppLocalizations, ru, doableTheme и MediaQuery с TextScaler.linear(2); загрузить `lib/src/design_system/fonts/InterVariable.ttf` через FontLoader, задать TestFlutterView physicalSize 320×240, DPR 1, padding и viewPadding (top: 24, bottom: 34), вызвать production `showQuickCreationModeMenu` из контекста страницы с обычным переопределением контроллера/хранилища. После pumpAndSettle высота SingleChildScrollView внутри BottomSheet равна 0, takeException возвращает RenderFlex overflow 18. Для `showQuickCreationDailyChoiceStartSheet` уменьшить высоту до 220 — область также 0, overflow 2. Это проверка реальных компонентов без подмены их раскладки.

Ручная сверка оформления взята из записей целевых коммитов: `6b5322dd077605d47de88d2621501d03809a1504` фиксирует Widgetbook в обеих темах и девять комбинаций панели на тему; `a9c5750386ebe70cf9b3d0e749cc7de5beecb202` — Android API 36, 390×844 dp, оба направления выбора, создание/отмену, возврат к исходной странице и полный перезапуск. В этой сессии устройство Android и работающий DTD отсутствовали; эти ручные проверки не повторялись и не выдаются за свежие. Доступные вневерсионные README Sheet/ActionSheet/OptionRow в приватном context/ сверены как дополнительный контекст, а не основание для изменения согласованных требований. Полный автоматический прогон и воспроизведение F1 выполнены заново.

Код, тесты и планирование на этапе аудита не изменялись. История задач, task IDs, номера, описания, порядок и отметки завершения сохранены; новых задач нет. F1 остаётся открытым для последующего finding-resolution этапа, без принятия риска или передачи в уже согласованный план исправления. Этот отчёт не разрешает слияние, выпуск или архивирование.
