# OpenSpec Implementation Review: polish-calendar-and-navigation

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверенный инкремент фазы 1 соответствует задачам 1.1–1.5; существенных замечаний по инженерным решениям, соответствию OpenSpec и качеству кода нет. Все шесть целевых коммитов и 11 изменённых путей учтены. Фактическое отображение системной навигации Android и исходный дефект Redmi остаются непроверенными на устройстве по явному указанию пользователя; это не подтверждение исправления дефекта и не принятие остаточного риска.

## Review target

- **Baseline ref:** 82e5fb84966adb4048d2b2c252cf7173b9275d32
- **Base commit:** 82e5fb84966adb4048d2b2c252cf7173b9275d32
- **Reviewed head:** 77d1ec41b083598f5246a7936cc01c277fe030b2
- **Target commits:** ["6a75bf4e678e2c03117c485e23b3be341d8b838a","1d22fdfc747b604af143de6f4b6d4056df2583f0","25921fb05b48594191a610e79e38aef74360758f","d71244170207e3a4ffe2bedf3cd7c59a552b726f","343ef69c6a7831e2a81792a3bbd0478d0b629454","77d1ec41b083598f5246a7936cc01c277fe030b2"]
- **Reviewable paths:** [".apm/instructions/testing-scope.instructions.md","AGENTS.md","android/app/src/main/res/values-night/styles.xml","android/app/src/main/res/values/styles.xml","lib/main.dart","lib/src/app/navigation/app_navigation_bar.dart","lib/src/design_system/components/nav_bar.dart","lib/src/design_system/doable_metrics.dart","openspec/changes/polish-calendar-and-navigation/design.md","openspec/changes/polish-calendar-and-navigation/tasks.md","test/app/navigation/app_navigation_bar_test.dart"]
- **OpenSpec change:** polish-calendar-and-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** [".apm/instructions/testing-scope.instructions.md","AGENTS.md","openspec/changes/polish-calendar-and-navigation/design.md","openspec/changes/polish-calendar-and-navigation/tasks.md"]

## Reviewed increment

### U1 · Собственный отступ панели и доступность её потребителей

- **Work items:** ["1.1", "1.4", "1.5"]
- **Requirements and scenarios:** ["proposal: симметричные собственные отступы при сохранении размера кнопок", "app-appearance: собственный отступ дополнительно к системному безопасному отступу", "app-appearance: Портретная ориентация на телефоне — поддерживаемая область раскладки", "daily-choice-management: Раскрытый месяц доступен на нижней границе поддержки при отказе отметок"]
- **Affected boundary:** Пользователь корневых и обычных страниц; кнопки общей панели, календарь, выдача и общие сообщения при системных вставках и открытой клавиатуре.
- **Implementation target:** ["lib/src/design_system/components/nav_bar.dart","lib/src/design_system/doable_metrics.dart","test/app/navigation/app_navigation_bar_test.dart"]
- **Applicable constraints and non-goals:** Кнопки остаются высотой 48 dp, собственные отступы — 6 dp сверху и снизу, верхняя линия — отдельный 1 dp; системный отступ добавляется один раз. Сохраняются доступность и область поддержки 360×720 dp. Предметные данные, маршрутизация и владение сообщениями не меняются.
- **Excluded change scope:** Жесты календаря, выбор периода и уменьшение ручки относятся к фазам 2–3 и этим диапазоном не поставляются.

### U2 · Системная навигация следует теме в поддерживаемых версиях Android

- **Work items:** ["1.2", "1.3", "1.5"]
- **Requirements and scenarios:** ["app-appearance: Светлое и тёмное оформление по системной настройке — нижняя системная область", "app-appearance: Смена системной настройки во время работы", "app-appearance: Фон нижней панели под системными кнопками", "app-appearance: Контраст системных кнопок на Android 7 при светлом интерфейсе"]
- **Affected boundary:** Общая панель приложения, запуск Flutter и системное окно Android; смена темы на открытой странице с несохранённым вводом.
- **Implementation target:** ["android/app/src/main/res/values-night/styles.xml","android/app/src/main/res/values/styles.xml","lib/main.dart","lib/src/app/navigation/app_navigation_bar.dart","test/app/navigation/app_navigation_bar_test.dart"]
- **Applicable constraints and non-goals:** Поддержка API 24+ сохраняется. На API 24–25 допустима тёмная подложка со светлыми кнопками; с API 26 фон должен соответствовать панели. Верхняя системная строка остаётся у страницы или AppBar. Ориентация, нативная политика дисплея, хранилище и маршрутизация не меняются; специальная ветка для Redmi не вводится.
- **Excluded change scope:** Наблюдение фактического системного фона, контраста и поведения Redmi выполняет пользователь позднее; эмуляторы и физические устройства на этом этапе не запускаются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий агент `/root/independent_decisions` без истории получил нейтральные цели U1/U2 и объединённые семь delivery-путей, поскольку units разделяют файл тестов. Рассмотрен ровно 82e5fb84966adb4048d2b2c252cf7173b9275d32..77d1ec41b083598f5246a7936cc01c277fe030b2; неизменённый контекст проверялся через закреплённый diff до чтения. Planning artifacts, история коммитов и предыдущие findings не передавались. Результат: No substantive findings. |
| OpenSpec conformance | Complete | Все задачи и целевые коммиты сопоставлены ниже; проверены committed proposal, обе delta-specs, design, ADR manifest, относящиеся к панели ADR, plan и tasks. В рабочем дереве на 77d1ec41b083598f5246a7936cc01c277fe030b2 выполнены `mise run check` (2716 тестов, exit 0), `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json` (valid: true, issues: []) и release-сборка (exit 0). Проверки устройства исключены из обязательного условия этапа указанием пользователя и AGENTS.md. |
| Code quality | Complete | По `code-review-and-quality` проверены все семь delivery-путей: корректность, читаемость, архитектурные границы, безопасность и производительность. Проверены существующие потребители панели, системные вставки, сообщения, смена темы, нативные темы и вызовы закреплённого Flutter 3.47.1. Дополнительных зависимостей, чтений данных, новых внешних входов и несопоставленной реализации нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Ревью выполнено 2026-10-16 в `/home/seniorkonung/.paseo/worktrees/1id27gtb/smelly-bird`. На старте рабочее дерево было чистым, HEAD равнялся Reviewed head. Код, тесты, настройки и плановые артефакты читались через полные SHA; перед завершением проверок отслеживаемые файлы по-прежнему совпадали с этим снимком. Предыдущий implementation-review.md отсутствовал: переносимых findings и принятых рисков нет.

Объединение Implementation target двух units — точный delivery-набор: четыре Dart-файла реализации, две нативные темы и один файл тестов. Остальные четыре пути — design/tasks и два согласованных источника инструкции о проверках; это evidence планирования и условий верификации, а не дополнительное поведение приложения. Несопоставленных путей нет.

Каждый коммит проверен отдельно по patch и в итоговом diff:

Коммит `6a75bf4e678e2c03117c485e23b3be341d8b838a` — задача 1 / 1.1, U1. Нижние 6 dp, общий размер 61 dp и проверки геометрии при inset 0/34 dp.

Коммит `1d22fdfc747b604af143de6f4b6d4056df2583f0` — задача 2 / 1.2, U2. Нижний SystemUiOverlayStyle, сохранение верхнего стиля и ввода при смене темы, явное включение edge-to-edge при запуске Android.

Коммит `25921fb05b48594191a610e79e38aef74360758f` — задача 3 / 1.3; уточнение проверки 1.5, U2. Уточнение design/tasks о недоступных проверках старых API; входит в сохранённый диапазон задачи 1.3 перед её кодовым коммитом.

Коммит `d71244170207e3a4ffe2bedf3cd7c59a552b726f` — задача 3 / 1.3, U2. Чёрная непрозрачная подложка обеих нативных тем в дневных и ночных ресурсах.

Коммит `343ef69c6a7831e2a81792a3bbd0478d0b629454` — задача 4 / 1.4, U1. Отметка проверки существующих потребителей: дополнительных изменений раскладки не требуется, поскольку они используют общую высоту панели.

Коммит `77d1ec41b083598f5246a7936cc01c277fe030b2` — задача 5 / 1.5, U1, U2. Итоговая проверка и сборка; сохранено указание пользователя о последующей самостоятельной проверке устройства.


В U1 `nav_bar.dart:50–69` сохраняет фон снаружи SafeArea и складывает собственный и системный отступы; `doable_metrics.dart:21` задаёт 61 dp. Новые проверки `app_navigation_bar_test.dart:163–187` защищают от уменьшения кнопок и подмены собственного отступа системным. Это два разных режима вставки одного контракта, без дублирования пользовательских сценариев.

Потребители проверены как неизменённый контекст: `app_shell_page.dart:38–44` передаёт общую высоту, `app_shell_tab_insets.dart:31–42` учитывает её при клавиатуре, `ordinary_page_scaffold.dart:18–23` использует штатную нижнюю панель Scaffold. Существующие `app_shell_tab_insets_test.dart`, `app_shell_layout_test.dart` с `ordinary_page_layout_scenarios.dart`, `ordinary_page_scaffold_test.dart` и `daily_choice_catalog_supported_layout_test.dart` включены в свежий полный прогон. Последний проверяет оба каталога на 360×720, весь месяц, отказ отметок, ручку и прокрутку; полезная высота обычного каталога после увеличения панели остаётся 531 dp при требуемых 528 dp.

В U2 `app_navigation_bar.dart:46–66` получает цвет raised из той же темы, что NavBar, и задаёт только нижний стиль. `app_navigation_bar_test.dart:49–123` проверяет итоговый SystemChrome.latestStyle в обоих вариантах владельца верхней строки и сохраняет несохранённый текст при смене темы. Существующий тест каталога также подтверждает смену верхнего стиля без нового чтения выдачи. Общее оформление загрузки не менялось: оба MaterialApp сохраняют системный выбор темы.

Необходимость вызова `lib/main.dart:13–19` сверена с установленным Flutter 3.47.1: `FlutterActivity.configureStatusBarForFullscreenFlutterExperience` и `PlatformPlugin.DEFAULT_SYSTEM_UI` сами не включают нижнее размещение под системной областью на API 29–34. В PlatformPlugin режим edge-to-edge применяется с API 29, цвет и яркость нижних кнопок — с API 26, разделитель — с API 28, отключение контрастной подложки — с API 29; с API 35 цвет нижней панели не назначается этим путём. Официальные контракты [SystemUiMode](https://api.flutter.dev/flutter/services/SystemUiMode.html) и [systemNavigationBarColor](https://api.flutter.dev/flutter/services/SystemUiOverlayStyle/systemNavigationBarColor.html) сверены как дополнительный источник; вывод об используемой версии опирается на локальные исходники SDK. Перенос сохранённого FlutterEngine и восстановление системного стиля также рассмотрены, подтверждённого дефекта в этом переходе не найдено.

Свежая верификация относится к Reviewed head:

Команда `mise run check`: форматирование 663 файлов без изменений, проверки CI scope, разрешение зависимостей Widgetbook с enforce-lockfile, `flutter analyze` без замечаний и 2716 успешных Flutter-тестов. Полный прогон выполнен как проверка завершающего checkpoint фазы 1, включая её непосредственных потребителей.

Команда `mise exec --no-deps -- openspec validate polish-calendar-and-navigation --strict --json`: exit 0, один valid change, issues отсутствуют. Структурная проверка не использовалась как доказательство поведения.

Команда `mise exec --no-deps -- flutter build apk --release --no-pub`: exit 0; `build/app/outputs/flutter-apk/app-release.apk`, 67 779 163 байта, SHA-256 `50f6245a63eb5f7307e09c2e5c9fad002f5735c47377a66ac28575cd79aebf5c`.

Анализ APK: `aapt dump badging` подтвердил minSdk 24 и targetSdk 36; `aapt2 dump resources` подтвердил чёрную navigationBarColor и выключенную windowTranslucentNavigation у LaunchTheme/NormalTheme в обоих ресурсных вариантах. Политика дисплея и минимальная версия не менялись.

Существующие примеры Widgetbook используют общий AppNavigationBar и получают обновлённую геометрию. Их код рассмотрен; интерактивная визуальная проверка Widgetbook в этой сессии не повторялась.


Указание пользователя и AGENTS.md:44–45 имеет приоритет над оставшимися формулировками design/tasks/plan, требующими устройства для завершения фазы. Поэтому завершённые задачи не открывались заново и отсутствие устройства не превращено в finding. Не наблюдались фактический фон, контраст и восстановление после клавиатуры/нижнего листа на API 24, 26, 28, 29, 35/36 и REDMI Note 15 Pro+ 5G в обоих режимах навигации; версии Android/HyperOS Redmi неизвестны. APK подготовлен для этих проверок пользователем. Аннотация Flutter и успешная сборка не доказывают устранение светлой полосы на конкретной прошивке.

Коррекций кода, тестов и плановых артефактов по результатам этого этапа не требуется; новые задачи не добавлены, исходная история задач сохранена. Незавершённых findings для следующих этапов разрешения нет. Результат относится только к сохранённому инкременту фазы 1: фазы 2–3 и изменение в целом этим отчётом завершёнными не объявляются.
