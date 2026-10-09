# Доступность общей панели и меню быстрого создания

Задача 3.27 изменения `add-quick-creation-and-persistent-navigation`, 2026-10-09. Основание проверки — `64e3dff72721c38506636fc23af74bd048a0b7d1` и изменения этой задачи. Документ подтверждает только доступность общего интерфейса; готовность всей Phase 3 здесь не устанавливается.

## Матрица и наблюдаемые результаты

[Матрица](../../test/app/quick_creation/quick_creation_accessibility_test.dart) использует настоящий `MainApp`, `AppRuntime` и `AppRouter` с графом в памяти. Проверены **144 случая**: русский, английский и немецкая системная локаль с английским fallback × текст 1.0 / 2.6 × телефон 400×800 и планшет 800×1280 / 1280×800 × безопасные отступы 0/0 и 24/32 × клавиатура 0/260 × корневой каталог намерений и просмотр каталога тегов над ним. DPR равен 1.

В каждом случае три пункта выбираются настоящими нажатиями и сохраняют роль вкладки, позиции среди трёх и единственный выбор. Кнопка объявляет название, текущий режим, роль и подсказку без позиции и состояния выбора. Меню открывается именно пользовательским семантическим действием «Сменить режим» / «Change mode». Каждый из четырёх режимов выбирается обычным `tester.tap`: всего **576 выборов**. После выбора проверяются исходные `matchId`, отсутствие нового маршрута и закрытие меню без запуска создания.

Полные прямоугольники строки режима, её текста и значка находятся в пересечении области прокрутки, безопасного экрана и области над клавиатурой. Проверены `hitTestable`, отсутствие обрезки текста и исключений. Плюс, малый значок режима 12×12 и стрелки смены 16×16 целиком помещаются в кнопку с областью не меньше 48×48. Раскладка самой панели у нижней границы экрана сохраняется: при клавиатуре проверяется размещение меню и содержимого над ней; физическая видимость закрытой клавиатурой панели не заявляется.

[Проверки переходов](../../test/app/navigation/app_navigation_transition_test.dart) подтверждают один видимый экземпляр панели и одинаковую геометрию в промежуточных кадрах `Hero`, включая смену режима на двух обычных страницах, системное «назад», отменённый и завершённый жест возврата iOS. Страница задачи скрывает панель до возвращения. Скрытая страница исключена из семантики и обхода фокуса и не подтверждает кадр сообщения до возвращения.

Для русского, английского и fallback отдельно проверено меню над обычной страницей с несохранённым вводом: восемь переходов Tab удерживают фокус внутри меню, фон и панель не имеют доступных действий. Касание кнопки под барьером только закрывает меню и сохраняет ввод; после закрытия поле получает фокус по нажатию, а кнопка выполняет действие обычным нажатием.

Проверки [раскладки](../../test/app/navigation/app_shell_layout_test.dart) и подключённых [сценариев обычных страниц](../../test/app/navigation/ordinary_page_layout_scenarios.dart) подтверждают последние строки, подгрузку, загрузку, отказ и повтор, поля правки и поиска и общие сообщения над новой панелью. Новые примеры Widgetbook не добавлялись.

## Воспроизведённый дефект и исправление

До исправления отдельная проверка телефона 400×800 с текстом 2.6, отступами 24/32 и клавиатурой 260 завершилась отказом: нижняя граница строки меню была **800**, при доступной границе **540**. Проверка использовала полный прямоугольник строки после прокрутки, поэтому доступный callback не мог скрыть перекрытие клавиатурой.

Причина — меню учитывало только `SafeArea`. Компонент теперь добавляет нижний отступ `MediaQuery.viewInsetsOf(context).bottom` вокруг безопасной области и прокрутки. Согласно документации Flutter, [viewInsets](https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html) описывает область, закрытую клавиатурой, тогда как [useSafeArea](https://api.flutter.dev/flutter/material/ModalBottomSheetRoute/useSafeArea.html) модальной панели защищает верхнюю и боковые границы. Исходная проверка прошла после исправления; затем прошла вся матрица.

Общий прогон также обнаружил несовместимость прежнего [тестового входа](../../test/support/quick_creation.dart) с очень высокой строкой меню: на телефоне 568×320, с клавиатурой 160 и текстом 300% выравнивание начала строки оставляло её центр вне области прокрутки. Helper теперь использует [Scrollable.ensureVisible](https://api.flutter.dev/flutter/widgets/Scrollable/ensureVisible.html) с `alignment: 0.5`, затем сохраняет проверки `hitTestable` и обычное нажатие. Оба исходных сценария горизонтального телефона, с текстом 200% и 300%, проходят без изменения их утверждений о форме. Полная видимость строк в поддерживаемой матрице 3.27 проверяется отдельно и не ослаблена. Первый общий прогон остановлен после этого отказа и повторён с исправленным helper.

## Свидетельства и ограничения среды

Проверены Flutter 3.47.1 и закреплённые зависимости без установки или обновления инструментов. Git blob проверенных файлов:

| Файл | Blob |
| --- | --- |
| `lib/src/app/quick_creation/quick_creation_mode_menu.dart` | `e4ea226f97574e2d75c2999a5c3cdfad0344cd06` |
| `test/app/quick_creation/quick_creation_accessibility_test.dart` | `4945987682a8132c731c73da1b1a37cd6817d90f` |
| `test/app/navigation/app_navigation_transition_test.dart` | `b809b04dcf2e0a43f859a482faaa0768c8d9b2d9` |
| `test/support/quick_creation.dart` | `12ffb03e87d68117fde2f8521d9b026294fa7999` |

Команды выполнялись с `MISE_AUTO_INSTALL=false`:

| Команда | Результат |
| --- | --- |
| `mise exec --no-deps -- flutter test --no-pub test/app/quick_creation/quick_creation_accessibility_test.dart --reporter expanded` | 144 теста, exit 0 |
| `mise exec --no-deps -- flutter test --no-pub test/app/navigation/app_navigation_transition_test.dart --reporter expanded` | 6 тестов, exit 0 |
| `mise exec --no-deps -- flutter test --no-pub test/app/navigation/app_navigation_accessibility_test.dart test/app/navigation/app_navigation_transition_test.dart test/app/navigation/app_shell_layout_test.dart test/app/quick_creation --reporter expanded` | 411 тестов, exit 0; повтор после коррекции общего helper |
| `mise exec --no-deps -- flutter test --no-pub --concurrency=2 --reporter expanded` | 5592 теста прошли, 1 тайм-аут запуска дочернего процесса графа, exit 1; подробности ниже |
| `mise exec --no-deps -- flutter test --no-pub test/intention/presentation/editor/intention_creation_sheet_layout_test.dart --plain-name 'на узком и низком телефоне в альбомной ориентации' --reporter expanded` | 2 теста после коррекции helper, exit 0 |
| `mise exec --no-deps -- flutter test --no-pub test/graph/data/file_backed_graph_durability_test.dart --plain-name 'прерывание архивирования связи после commit оставляет целое состояние' --reporter expanded` | 1 тест, exit 0; повтор после тайм-аута в общем прогоне |
| Из `widgetbook/`: `mise exec --no-deps -- flutter test --no-pub --reporter expanded` | 8 тестов, exit 0 |
| `mise exec --no-deps -- dart format --output=none --set-exit-if-changed .` | 610 файлов, без изменений, exit 0 |
| `mise exec --no-deps -- flutter analyze --no-pub` | Exit 1: два прежних информационных замечания, перечислены ниже |
| `mise exec --no-deps -- flutter analyze --no-pub --no-fatal-infos` | Exit 0: те же два замечания; ошибок и предупреждений нет |
| `mise exec --no-deps -- openspec validate add-quick-creation-and-persistent-navigation --strict --json` | Изменение валидно, issues пуст, exit 0 |

`analyze_files` Dart MCP не сообщил диагностик для четырёх изменённых Dart-файлов, включая итоговый helper. Общий анализ сохраняет `deprecated_member_use` для `containsSemantics` в `test/app/tag_navigation_primary_navigation_app_scenarios.dart:129` и `test/tag/presentation/navigation/tag_navigation_primary_navigation_scenarios.dart:24`. Эти строки присутствуют в базовой ревизии; оба файла не изменялись в 3.27. Успешный запуск с `--no-fatal-infos` не подменяет результат стандартного анализа.

В общем прогоне тест `прерывание архивирования связи после commit оставляет целое состояние` превысил 45 секунд ожидания дочернего процесса: вывод содержал только загрузку `graph_operation_process_worker.dart`, маркер готовности отсутствовал. Повтор только этого теста завершился за четыре секунды с exit 0. Тест, worker и реализация графа совпадают с базовой ревизией; они не исправлялись в 3.27. Успешный повтор не отменяет отказ общего прогона и не подтверждает готовность всей Phase 3.

Dart MCP после изменений не обнаружил процессов приложения или DTD. `flutter devices` перечислил только Linux и Chrome; `flutter emulators` не нашёл эмуляторов. В репозитории настроена только платформа Android, проектов Linux и Web нет. Попытка `DISPLAY=:93 LANG=ru_RU.UTF-8 MISE_AUTO_INSTALL=false mise run start -- -d linux` в виртуальном дисплее завершилась сообщением `No Linux desktop project configured`. Использован разрешённый задачей путь CLI. Ручные свидетельства читаемости значков в приложении, озвучивания экранным диктором, реальной клавиатуры и обычного/предиктивного жеста Android **отсутствуют**. Геометрия и семантика в widget-тестах не выдаются за такие свидетельства; горячая перезагрузка и `get_runtime_errors` без приложения не выполнялись.
