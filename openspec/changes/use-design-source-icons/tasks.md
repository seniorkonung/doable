## Phase 1: Нижняя навигация и быстрое создание показывают иконки дизайна

- [x] 1.1 Перенести исходную графику 17 используемых вариантов в ресурсы дизайн-системы
  - **Критерии приёмки:**
    - Для каждой строки таблицы решения 1 в `design.md` перенесены все варианты SVG; сохранены геометрия, заливки, `evenodd`, ширина и окончания линий.
    - Короткий файл происхождения связывает каждый ресурс с блоком `Main.dc.html` и версией экспорта; мини-значки и два вида календаря не объединены.
  - **Проверка:** сопоставить каждый извлечённый SVG с соответствующим исходным элементом и проверить `git diff --check`; графика проверяется в задаче 1.2 реальным компонентом отображения.
  - **Зависимости:** нет.
  - **Вероятные файлы:** новые `lib/src/design_system/icons/assets/*.svg` и `lib/src/design_system/icons/README.md`.
  - **Размер:** S — механический перенос одного ограниченного набора графических ресурсов.

- [x] 1.2 Отображать исходные SVG общим типизированным компонентом с проверкой реальных ресурсов
  - **Критерии приёмки:**
    - `DoableIconData` и `DoableIcon` реализуют контракт решения 2: перечисление, обязательные размер и цвет, квадратная область и отсутствие отдельного семантического узла иконки.
    - В `flutter.assets` корневого `pubspec.yaml` все 17 SVG перечислены отдельными пакетными путями к файлам по решению 3, без записи пакетного каталога. Приложение загружает их по единому адресу пакета; `flutter_svg` и разрешённые версии зависимостей зафиксированы, материалы `context` не участвуют в сборке.
    - Проверка общего компонента загружает все ресурсы; визуальная таблица 17 вариантов сверена с исходниками в цветах обеих тем и сохранена как эталон. Она обнаруживает исчезновение ромба или круга и неверные заливки, которые не проверяют тесты взаимодействий.
  - **Проверка:** `flutter pub get`, `flutter pub get --directory widgetbook`, `flutter test test/design_system/doable_icon_test.dart`; визуально сравнить эталон с исходными SVG перед его принятием.
  - **Зависимости:** 1.1; контракты и способ поставки согласованы в решениях 2–3 дизайна.
  - **Вероятные файлы:** новый `lib/src/design_system/doable_icon.dart`, `pubspec.yaml`, оба `pubspec.lock`, новый `test/design_system/doable_icon_test.dart` и его графические эталоны.
  - **Размер:** M.

- [x] 1.3 Подключить те же ресурсы к Widgetbook и подтвердить адресацию пакета
  - **Критерии приёмки:**
    - В `flutter.assets` файла `widgetbook/pubspec.yaml` перечислены те же 17 отдельных пакетных путей к SVG, что и в корневом манифесте, по решению 3; записи пакетного каталога и отдельных копий SVG нет.
    - Локальная композиция `DoableIcon` показывает все 17 вариантов по тому же контракту загрузки, что и приложение; `DoableIconData.fromIntention` сохраняет ромб и стрелку, ошибок загрузки ресурсов нет.
  - **Проверка:** `flutter pub get --directory widgetbook`, `flutter analyze`; сверить полноту и совпадение записей SVG в обоих манифестах, визуально проверить все 17 вариантов локальной композиции при запуске `mise run widgetbook`. Автоматические тесты Widgetbook не добавляются.
  - **Зависимости:** 1.2.
  - **Вероятные файлы:** `widgetbook/pubspec.yaml`; существующая композиция в `widgetbook/lib/navigation/quick_creation_sheets_use_cases.dart` при необходимости проверки, без сохранения временного примера.
  - **Размер:** S.

- [x] 1.4 Освободить общие сценарии переходов от поиска кнопок по Material Icons
  - **Критерии приёмки:**
    - `appNavigationDestination` находит пункт по существующей семантике и локализованному названию, сохраняя поддержку `skipOffstage` и возврат всего элемента управления.
    - Прямые поиски значков для перехода в проверках запуска, вложенных страниц и создания намерения используют общий помощник; проверки результата переходов и состояния страниц сохранены.
  - **Проверка:** `flutter test test/app/bootstrap/app_bootstrap_shell_test.dart test/app/navigation/app_shell_operation_reset_test.dart test/app/intention_creation_sheet_integration_test.dart`.
  - **Зависимости:** нет; подготовка потребителей существующего контракта, без замены графики.
  - **Вероятные файлы:** `test/support/app_root_pages.dart` и три перечисленных файла тестов.
  - **Размер:** M — общий помощник и механическая замена его прямых обходов.

- [x] 1.5 Сохранить проверки переходов и режима быстрого создания при смене представления иконок
  - **Критерии приёмки:**
    - В сценариях переходов, открытия панелей и восстановления режима кнопки находятся по доступным названиям и ролям либо общему помощнику; состояние режима проверяется по его наблюдаемому представлению.
    - Эти поведенческие проверки не зависят от типа иконочного виджета. Проверки самой графики остаются у тестов соответствующих компонентов и адаптируются вместе с ними.
  - **Проверка:** `flutter test test/app/navigation/app_navigation_transition_test.dart test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart test/app/quick_creation/quick_creation_mode_menu_test.dart test/app/quick_creation/quick_creation_navigation_test.dart test/app/quick_creation/quick_creation_runtime_restart_test.dart`.
  - **Зависимости:** 1.4.
  - **Вероятные файлы:** пять перечисленных файлов тестов.
  - **Размер:** M.

- [x] 1.6 Показывать исходные иконки трёх пунктов навигации в обоих состояниях
  - **Критерии приёмки:**
    - `NavBarItem` и `AppDestination` используют `DoableIconData`; выбранное и невыбранное состояния показывают соответствующие исходные варианты дома, календаря с днями и графа.
    - Размеры, цвета, выбранность, доступные названия и обработчики пунктов сохраняются; проверки графики используют `DoableIcon` вместо `IconData`.
    - Существующие примеры навигации Widgetbook используют тот же компонент, включая увеличенный значок в теле примера.
  - **Проверка:** `flutter test test/app/navigation/app_navigation_bar_test.dart test/app/navigation/app_navigation_accessibility_test.dart`; визуально проверить три выбранных пункта в обеих темах через `mise run widgetbook`.
  - **Зависимости:** 1.2, 1.3, 1.5.
  - **Вероятные файлы:** `lib/src/design_system/components/nav_bar.dart`, `lib/src/app/navigation/app_destination.dart`, два перечисленных файла тестов и `widgetbook/lib/navigation/app_navigation_bar_use_cases.dart`.
  - **Размер:** M.

- [ ] 1.7 Показывать исходный плюс и мини-значок каждого режима быстрого создания
  - **Критерии приёмки:**
    - `NavBarCreateButton` принимает `DoableIconData`; плюс и мини-значки рисуются общим компонентом в размерах 24 и 14 с исходной толщиной линий.
    - `QuickCreationModePresentation.miniIcon` задаёт три мини-варианта, а `QuickCreationButton` передаёт текущий. Смена и восстановление режима сохраняют прежнее поведение.
    - Проверки кнопки и режима больше не ищут её значок через `mode.icon`, предназначенный для меню; проверки доступности и размещения сохраняются.
  - **Проверка:** `flutter test test/app/quick_creation/quick_creation_button_test.dart test/app/quick_creation/quick_creation_accessibility_test.dart test/app/quick_creation/quick_creation_runtime_restart_test.dart test/app/quick_creation/quick_creation_navigation_test.dart test/app/navigation/app_navigation_transition_test.dart`.
  - **Зависимости:** 1.6.
  - **Вероятные файлы:** `lib/src/design_system/components/nav_bar.dart`, `lib/src/app/quick_creation/quick_creation_button.dart`, `quick_creation_mode_presentation.dart`, `test/app/quick_creation/quick_creation_button_test.dart`, `quick_creation_accessibility_test.dart`.
  - **Размер:** M — один путь отображения кнопки и адаптация его существующих проверок.

- [ ] 1.8 Перевести обе панели создания на исходные ведущие и служебные значки
  - **Критерии приёмки:**
    - `OptionRow` принимает `DoableIconData`; все ведущие значки меню, галочка текущего режима и шевроны используют исходную графику.
    - Панель начала дневного выбора показывает `fromIntention` и `fromAction` с ромбом и кругом; направления, возвращаемые при выборе, и отмена сохраняются.
    - `QuickCreationModePresentation.icon` и существующие примеры обеих панелей Widgetbook используют общий набор; связанные ожидания тестов переведены на новый компонент и сохранены проверки взаимодействий.
  - **Проверка:** `flutter test test/app/quick_creation/quick_creation_mode_menu_test.dart test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart test/app/quick_creation/quick_creation_accessibility_test.dart test/app/quick_creation/quick_creation_runtime_restart_test.dart`; визуально сверить состояния обеих панелей в обеих темах.
  - **Зависимости:** 1.7; существующие контракты `ActionSheet` и результата `ChoicePathDraftDirection`.
  - **Вероятные файлы:** `lib/src/design_system/components/option_row.dart`, `lib/src/app/quick_creation/quick_creation_mode_presentation.dart`, `quick_creation_daily_choice_start_sheet.dart`, `widgetbook/lib/navigation/quick_creation_sheets_use_cases.dart`; проверки графики в `quick_creation_mode_menu_test.dart`, `quick_creation_daily_choice_start_sheet_test.dart` и `quick_creation_accessibility_test.dart`.
  - **Размер:** M — миграция единственного общего потребителя строк и его двух панелей; адаптации ожиданий механические.

- [ ] 1.9 Подтвердить соответствие графики и готовность всего участка к итоговой проверке
  - **Критерии приёмки:**
    - Все поверхности из границ фазы показывают исходную графику в обеих темах; внутри них не осталось `Icons.*` и `IconData`. Проверены варианты из решения 5 дизайна, включая составные значки и мини-значки.
    - Обязательная полная проверка проекта проходит; приложение и Widgetbook используют ресурсы из репозитория.
    - Дельты спецификаций проходят строгую проверку. Завершение фазы относится к нижней навигации и быстрому созданию.
  - **Проверка:**
    - `mise run check` — обязательная итоговая проверка перед завершением фазы.
    - `mise exec --no-deps -- openspec validate use-design-source-icons --strict`.
    - Визуально сверить приложение и Widgetbook с исходной графикой в обеих темах по решению 5 дизайна.
    - При доступном Dart MCP проверить наличие работающих приложений через `dtd`; если они есть, выполнить hot reload/restart и прочитать `get_runtime_errors`.
    - Результаты сообщить в сессии; отдельный документ результатов не создавать.
  - **Зависимости:** 1.1–1.8.
  - **Вероятные файлы:** нет, только проверка и отметки задач.
  - **Размер:** S.
