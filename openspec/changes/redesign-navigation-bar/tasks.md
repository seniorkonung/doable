## Phase 1: Панель на всех обычных страницах выглядит по дизайну

- [x] 1.1 Панель приложения построена на `NavBar` дизайн-системы, а кнопка быстрого создания стоит в ней последней
  - **Acceptance criteria:**
    - Модуль основ содержит `NavBar` и токены `navHeight` = 55 и `iconSize` = 24 по решениям 1 и 7 дизайна. Компонент получает пункты (значок, залитый значок, название), индекс выбранного, выбор пункта и виджет действия; предметных типов и строк локализации приложения в нём нет (ADR-0030). Пункты образуют группу вкладок с выбранностью, положением «N из M» и подсказкой по долгому нажатию, а действие стоит вне группы.
    - `AppNavigationBar` с прежним конструктором показывает пункты «Главная», «Дневные выборы» и «Граф намерений», а за ними — кнопку быстрого создания; `AppNavigationBar.height` равна `navHeight`, и вставки оболочки и каркасы страниц опираются на неё (решение 2).
    - Сценарий «Три пункта в заданном порядке» подтверждён тестом. Выбранный пункт отличается залитым значком, подсказки, объявления экранного диктора, выбор пункта и сброс истории работают как прежде.
  - **Verification:**
    - `mise exec -- flutter test test/app/navigation`
    - `mise exec -- flutter analyze`
  - **Dependencies:** None
  - **Files likely touched:** `lib/src/design_system/doable_metrics.dart`, `lib/src/design_system/components/nav_bar.dart` (новый), `lib/src/app/navigation/app_navigation_bar.dart`, `test/app/navigation/app_navigation_bar_test.dart`
  - **Estimated scope:** M

- [x] 1.2 Кнопка быстрого создания выглядит как простой плюс с мини-значком текущего режима, без подложки и стрелок
  - **Acceptance criteria:**
    - Модуль основ содержит кнопку создания `NavBar`: `muted` плюс размера `iconSize` и мини-значок 14 у нижнего правого угла знака, без подложки. Кнопка получает мини-значок, доступное название и подсказку, название действия удержания, нажатие и удержание и никогда не показывается выбранной (решение 1, ADR-0030).
    - `QuickCreationButton` строит её из режима и локализации: плюс — `add_outlined`, мини-значок — прежний значок текущего режима. Стрелки, подложка и `quickCreationChangeModeIcon` удалены, долгое нажатие стандартное для Flutter (решения 2, 8 и 9).
    - Сценарии «Кнопка последней в панели», «Нажатие не меняет выбранный пункт» и «Экранный диктор объявляет кнопку» подтверждены тестами. Нажатие запускает текущий режим, а долгое нажатие и доступное действие «Сменить режим» открывают меню режимов.
  - **Verification:**
    - `mise exec -- flutter test test/app/quick_creation test/app/navigation`
    - `mise exec -- flutter analyze`
  - **Dependencies:** 1.1
  - **Files likely touched:** `lib/src/design_system/components/nav_bar.dart`, `lib/src/app/quick_creation/quick_creation_button.dart`, `lib/src/app/quick_creation/quick_creation_mode_presentation.dart`, `test/app/quick_creation/quick_creation_button_test.dart`, `test/app/quick_creation/quick_creation_accessibility_test.dart`
  - **Estimated scope:** M

- [x] 1.3 Проверить готовность фазы 1: панель на всех обычных страницах выглядит по дизайну, а поведение навигации и быстрого создания не изменилось
  - **Acceptance criteria:**
    - Положение и вид кнопки подтверждены проверками.
    - Прежнее поведение панели сохранилось: выбор пункта, сброс истории, подсказки, объявления экранного диктора, содержимое и сообщения над панелью, все потоки создания.
    - Ручная сверка панели с макетами в обеих темах в Widgetbook и на устройстве не выявила непринятых проблем, проверки репозитория проходят.
  - **Verification:**
    - `mise run check`
    - `openspec validate redesign-navigation-bar --strict`
    - Ручная сверка в `mise run widgetbook` и на устройстве в обеих темах с README `NavBar`, состояниями экрана дня `Main` и разделами «Navigation» и «Create button» спек-доски `Parts` из `context/`.
  - **Dependencies:** 1.1, 1.2
  - **Files likely touched:** None (verification only)
  - **Estimated scope:** XS

## Phase 2: Быстрое создание предлагает три режима с листами дизайна

- [x] 2.1 Модуль основ предоставляет листы `Sheet`, `ActionSheet` и `OptionRow` с единым показом над корневым навигатором
  - **Acceptance criteria:**
    - Компоненты реализуют только варианты, нужные меню режимов и выбору начала, по решениям 1, 3 и 7 дизайна и ADR-0029, ADR-0030, ADR-0032: получают готовые тексты, значки и обработчики; состояние конца строки задаётся типизированными вариантами «выбрана», «ведёт дальше» и «без отметки». Предметных типов и локализации приложения в модуле основ нет.
    - `Sheet` оформляет плоскость, ручку, заголовок, пояснение и нижний системный отступ; `ActionSheet` располагает варианты без промежутков. `shadow-float` обеих тем подключена через единственное расширение `DoableShadows`; если оно уже появилось из изменения календаря, его существующие тени сохраняются.
    - Функция показа возвращает типизированный результат либо `null` при закрытии, использует корневой навигатор, `scrim`, высоту по содержимому и настройки Material из ADR-0032. Закрытие фоном, свайпом и «назад» остаётся за Material; `bottomSheetTheme` прежних панелей не меняется. Размеры компонентов допускают рост текста; строка принимает начальный фокус, необходимый текущему режиму меню.
  - **Verification:**
    - `mise exec --no-deps -- flutter analyze`
    - Сверить компоненты с README `Sheet`, `ActionSheet`, `OptionRow` из приватного `context/`; проверки поведения выполняются на потребителях в задачах 2.2–2.4, без тестов внешнего вида.
  - **Dependencies:** 1.3
  - **Files likely touched:** `lib/src/design_system/components/sheet.dart` (новый, включая функцию показа), `lib/src/design_system/components/action_sheet.dart` (новый), `lib/src/design_system/components/option_row.dart` (новый), `lib/src/design_system/doable_shadows.dart` (новый, если ещё не добавлен), `lib/src/design_system/doable_theme.dart`
  - **Estimated scope:** M

- [x] 2.2 Лист «Новый дневной выбор» возвращает выбранное направление или отмену, сохраняя исходную страницу
  - **Acceptance criteria:**
    - Компонент быстрого создания строит `ActionSheet` с заголовком «Новый дневной выбор», строкой «С чего начать» и двумя вариантами в порядке «От намерения», «От действия». Пояснения, значки направлений и шевроны соответствуют решениям 5, 8 и 10 дизайна; русские и английские строки берутся из локализации.
    - Выбор закрывает лист с `ChoicePathDraftDirection.topDown` либо `bottomUp`, закрытие без выбора — с `null`. Компонент не запускает поиск и не меняет режим: продолжением владеет `QuickCreationLauncher`. Оба варианта доступны без обращения к данным графа.
    - Виджет-проверки листа подтверждают порядок и результаты вариантов, объявления названий и пояснений как кнопок, закрытие фоном, свайпом и «назад», изоляцию исходной страницы и панели корневым барьером и сохранение их состояния после закрытия. Проверяется доступность вариантов при увеличенном тексте и системных отступах без снимков внешнего вида.
  - **Verification:**
    - `mise exec --no-deps -- flutter gen-l10n`
    - `mise exec --no-deps -- flutter test test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 2.1
  - **Files likely touched:** `lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart` (новый), `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, генерируемые `lib/l10n/app_localizations*.dart`, `test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart` (новый)
  - **Estimated scope:** M

- [x] 2.3 Быстрое создание использует три сохраняемых режима и запускает оба направления дневного выбора через лист выбора начала
  - **Acceptance criteria:**
    - `QuickCreationMode` содержит только `intention`, `relation`, `dailyChoice` с ключами `intention`, `relation`, `daily-choice`; названия и мини-значки выводятся исчерпывающе по решениям 4, 8 и 10 дизайна. Прежние ключи дневного выбора проходят существующую обработку неизвестного значения: «Новое намерение» и диагностика повреждения, без миграции. Удалены неиспользуемые прежние названия режимов.
    - `QuickCreationLauncher` ожидает результат листа внутри своей `ExclusiveOperation`: отмена не запускает поиск, направление передаётся прежнему `DailyChoiceCreationLauncher` только после закрытия листа. Проверки реального маршрутизатора подтверждают оба перехода в поиск, возврат и отмену на исходную страницу без листа в истории, пустой граф и единственный поток при повторных нажатиях, включая открытие листа. Вход «Выбрать действие по пути» со страницы намерения и потоки намерения и связи сохраняются.
    - В той же задаче согласованы все зависимые сценарии и помощники тестов: новый режим и направление проверяются отдельно, оба направления сохраняют покрытие; утверждения о глубокой истории, несохранённом вводе, выбранном пункте, отмене и открытии созданной сущности не ослаблены. Проверки хранилища и перезапуска подтверждают три ключа, оба устаревших ключа, немедленное применение режима, порядок записей и продолжение очереди после отказа по `quick-creation`; существующие файловый адаптер и диагностика переиспользуются.
  - **Verification:**
    - `mise exec --no-deps -- flutter gen-l10n`
    - `mise exec --no-deps -- flutter test test/app/quick_creation test/app/navigation test/app/bootstrap/app_runtime_quick_creation_mode_test.dart test/app/creation_flows_integration_test.dart test/app/daily_choice_app_lifecycle_test.dart test/daily_choice/presentation`
    - `mise exec --no-deps -- flutter analyze`
    - `mise exec --no-deps -- openspec validate redesign-navigation-bar --strict`
  - **Dependencies:** 2.2
  - **Files likely touched:** `lib/src/app/quick_creation/quick_creation_mode.dart`, `lib/src/app/quick_creation/quick_creation_mode_presentation.dart`, `lib/src/app/quick_creation/quick_creation_launcher.dart`; `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые локализации; `test/support/quick_creation.dart`, проверки и помощники в `test/app/quick_creation/`, `test/app/navigation/`, `test/app/bootstrap/app_runtime_quick_creation_mode_test.dart`, `test/app/creation_flows_test_support.dart`, `test/app/creation_flows_accessibility_scenarios.dart`, `test/app/daily_choice_app_lifecycle_test.dart`, `test/daily_choice/presentation/daily_choice_creation_launcher_test.dart`, `test/daily_choice/presentation/daily_choice_creation_flow_test.dart`, `test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart`
  - **Estimated scope:** M — один переход поведения; удаление значений перечисления требует одновременного механического согласования перечисленных потребителей.

- [ ] 2.4 Удержание кнопки открывает меню трёх режимов на `ActionSheet` с пояснениями и отметкой текущего режима
  - **Acceptance criteria:**
    - `showQuickCreationModeMenu` использует функцию показа модуля основ, `ActionSheet` и `OptionRow`: заголовок «Что создаёт кнопка», пояснение и три строки из решений 6, 8 и 10 дизайна локализованы на русский и английский. Представление пояснения режима исчерпывающе; текущая строка получает галочку, выбранность и начальный фокус.
    - Выбор вызывает прежний `QuickCreationModeController.select` и закрывает лист без ожидания записи и без запуска создания; выбор текущего режима и закрытие без выбора сохраняют режим. Удержание и доступное действие «Сменить режим» открывают одно и то же меню, а следующий обычный тап запускает выбранный режим.
    - Существующие проверки меню и доступности адаптированы к новому представлению и подтверждают пояснения, выбранность, клавиатурный фокус, отсутствие запуска при выборе, сохранение истории и ввода, недоступность фона и доступность строк на узком экране. Поиск `ListTile` в зависимых помощниках и тестах заменён без ослабления проверяемого поведения; общие правила барьера и закрытия не получают дублирующих наборов тестов.
  - **Verification:**
    - `mise exec --no-deps -- flutter gen-l10n`
    - `mise exec --no-deps -- flutter test test/app/quick_creation test/app/navigation test/app/creation_flows_integration_test.dart test/app/daily_choice_app_lifecycle_test.dart test/daily_choice/presentation`
    - `mise exec --no-deps -- flutter analyze`
    - `mise exec --no-deps -- openspec validate redesign-navigation-bar --strict`
  - **Dependencies:** 2.3
  - **Files likely touched:** `lib/src/app/quick_creation/quick_creation_mode_menu.dart`, `lib/src/app/quick_creation/quick_creation_mode_presentation.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые локализации; `test/support/quick_creation.dart`, `test/app/quick_creation/quick_creation_mode_menu_test.dart`, `test/app/quick_creation/quick_creation_accessibility_test.dart`, `test/app/quick_creation/quick_creation_mode_presentation_test.dart`, `test/app/quick_creation/quick_creation_runtime_restart_test.dart`, `test/app/quick_creation/quick_creation_navigation_test.dart`
  - **Estimated scope:** M

- [ ] 2.5 Widgetbook показывает оба листа, состояния строк и панель с тремя режимами для сверки дизайна
  - **Acceptance criteria:**
    - В каталог добавлены меню режимов, лист выбора начала и нужные состояния `OptionRow`: обычное, выбранное, ведущее дальше; они доступны в обеих темах без маршрутизатора и хранилища приложения. Примеры используют те же компоненты и данные представления, что потребители.
    - Существующие примеры панели позволяют увидеть каждый выбранный пункт с каждым из трёх мини-значков режима. Ручная сверка в Widgetbook с README компонентов и состояниями `ActionMenu`, `ChoiceSheet` и доской `Parts` не выявила непринятых расхождений.
  - **Verification:**
    - `mise exec --no-deps -- flutter analyze`
    - `mise run widgetbook` — проверить обе темы, оба листа, состояния строк и мини-значки панели по решению 11 дизайна; результаты сообщить в сессии.
  - **Dependencies:** 2.4
  - **Files likely touched:** `widgetbook/lib/catalog.dart`, `widgetbook/lib/navigation/app_navigation_bar_use_cases.dart`, `widgetbook/lib/navigation/quick_creation_sheets_use_cases.dart` (новый)
  - **Estimated scope:** M

- [ ] 2.6 Проверить готовность фазы 2: три режима и листы дизайна выполняют спецификации, сохраняя потоки создания
  - **Acceptance criteria:**
    - Сценарии `quick-creation`, `app-navigation` и `daily-choice-management` подтверждены проверками; оба направления дневного выбора доступны через лист, быстрые повторные нажатия при его открытии не создают второй поток.
    - Создание намерения, связи и дневного выбора, отмена, открытие созданной сущности, исходная история и состояние страниц работают по прежним контрактам; режим восстанавливается после полного перезапуска. Ручная сверка листов и меню в обеих темах в Widgetbook и на устройстве не выявила непринятых проблем.
    - Полные проверки репозитория и строгая валидация изменения проходят; результаты проверок и ручной сверки сообщены в сессии.
  - **Verification:**
    - `mise run check`
    - `mise exec --no-deps -- openspec validate redesign-navigation-bar --strict`
    - На устройстве в обеих темах пройти смену режима без запуска, каждый поток создания и его отмену над обычной страницей, оба направления дневного выбора и полный перезапуск; сверить листы с приватными README компонентов, `ActionMenu`, `ChoiceSheet` и разделом «Create button action sheet» доски `Parts`. Учесть результаты Widgetbook из 2.5.
  - **Dependencies:** 2.1, 2.2, 2.3, 2.4, 2.5
  - **Files likely touched:** None (verification only)
  - **Estimated scope:** XS
