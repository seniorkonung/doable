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

- [ ] 1.2 Кнопка быстрого создания выглядит как простой плюс с мини-значком текущего режима, без подложки и стрелок
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

- [ ] 1.3 Проверить готовность фазы 1: панель на всех обычных страницах выглядит по дизайну, а поведение навигации и быстрого создания не изменилось
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
