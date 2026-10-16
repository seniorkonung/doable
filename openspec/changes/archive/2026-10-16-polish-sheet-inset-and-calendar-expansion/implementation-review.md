# OpenSpec Implementation Review: polish-sheet-inset-and-calendar-expansion

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Фаза 1 реализована так, как требуют изменённые спецификации, design.md и задачи 1.1–1.3. Нижний отступ листа исправлен в общем `Sheet`: собственные 16 dp добавляются к системному отступу, а не заменяются им. Поэтому исправление сразу действует для меню режимов быстрого создания и листа «Новый дневной выбор», а функция показа листа не меняется. В `DailyChoiceCalendarExpansion` месяц сдвинут на `(1 − p) · W` и закрывает неделю непрозрачным фоном `bg`, который лежит вне прозрачности. Высота, управление раскрытием, события, семантика и контракт календаря прежние. Независимое ревью решений, проверка соответствия и проверка качества кода завершены, замечаний нет. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 6a9eae993fdabccbbf9e87d55c4ba99fe4cddd25
- **Base commit:** 6a9eae993fdabccbbf9e87d55c4ba99fe4cddd25
- **Reviewed head:** f0e3517d1ef3ac0952557830ae60eb91ad9f0bdb
- **Target commits:** ["0f619d52d26226a58c32f3a8409aee83efd04c82", "484b6769c2694c946bd8d01be59a8fe771b59e5b", "f0e3517d1ef3ac0952557830ae60eb91ad9f0bdb"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar_expansion.dart", "lib/src/design_system/components/sheet.dart", "openspec/changes/polish-sheet-inset-and-calendar-expansion/tasks.md", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart"]
- **OpenSpec change:** polish-sheet-inset-and-calendar-expansion
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/polish-sheet-inset-and-calendar-expansion/tasks.md"]

## Reviewed increment

### U1 · Собственный нижний отступ листа сохраняется сверх системного

- **Work items:** ["1.1", "1.3"]
- **Requirements and scenarios:** ["app-appearance: Светлое и тёмное оформление по системной настройке", "app-appearance: Меню режимов не прижато к системной области"]
- **Affected boundary:** Пользователь Android (API 24+, портрет) и все выезжающие снизу листы на основе общего компонента листа: сейчас это меню режимов быстрого создания и лист «Новый дневной выбор».
- **Implementation target:** ["lib/src/design_system/components/sheet.dart"]
- **Applicable constraints and non-goals:** Собственные 16 dp из шкалы отступов добавляются к системному нижнему отступу как при нулевом, так и при ненулевом системном отступе. Фон листа доходит до нижнего края экрана. Боковые и верхний отступы, ручка, заголовок, прокрутка тела, выбор, закрытие и доступность прежние. Функция показа листа по ADR-0032 не меняется, правки у потребителей не делаются. Нижняя панель и модальная панель создания намерения вне изменения. Автоматический тест отступа по решению 4 дизайна не добавляется.

### U2 · Месяц надвигается на неделю непрозрачным фоном

- **Work items:** ["1.2", "1.3"]
- **Requirements and scenarios:** ["daily-choice-management: Встроенный недельный и месячный календарь каталога", "daily-choice-management: Месяц надвигается на неделю своим фоном"]
- **Affected boundary:** Пользователь календаря в корневом каталоге дневных выборов и в каталоге на заданную дату, в светлой и тёмной теме, включая открытый выбор года и месяца.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar_expansion.dart", "test/daily_choice/presentation/catalog/daily_choice_calendar_transitions_test.dart"]
- **Applicable constraints and non-goals:** Верхний край месяца движется от нижнего края недели к верху календаря. Месяц закрывает неделю сплошным фоном текущей темы, надписи двух представлений нигде не накладываются. Прозрачность месяца равна `p`, недели — `1 − p`. Одинаковое правило действует для нажатия, перетягивания, завершения и возврата. Высота календаря, сдвиг содержимого, управление раскрытием, длительность и кривая, события, семантика и фокус прежние. Внешний контракт календаря по ADR-0017 и токены цвета по ADR-0029 сохраняются. Тени и линии у края месяца нет. Устройство страниц выбора года и месяца и эталонные изображения в изменение не входят.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два новых изолированных ревьюера без истории по `implementation-decision-review`, каждый получил только нейтральный бриф и точную цель `6a9eae99..f0e3517d`. U1 — `lib/src/design_system/components/sheet.dart`. U2 — `daily_choice_calendar_expansion.dart` и `daily_choice_calendar_transitions_test.dart`. Пути единиц не пересекаются. Оба вернули полное покрытие без существенных замечаний. |
| OpenSpec conformance | Complete | Выполнено в рабочей копии; `HEAD` = `f0e3517d1ef3ac0952557830ae60eb91ad9f0bdb`, дерево чистое. `mise exec --no-deps -- openspec validate polish-sheet-inset-and-calendar-expansion --strict --json --no-interactive`: valid, замечаний нет. `mise run check`: exit 0. В его составе: `dart format` — 0 изменённых файлов, тесты CI scope прошли, `flutter analyze` — замечаний нет, `flutter test --exclude-tags=flutter_process` — 2846 тестов прошли, `flutter test --tags=flutter_process` — 14 тестов прошли. Ревьюер U2 на той же ревизии отдельно запустил 24 теста файла переходов и 312 тестов каталога и потребителей календаря: все прошли. Для задачи 1.3: `build/app/outputs/flutter-apk/app-release.apk` собран в 22:34:43, после последнего кодового коммита `484b6769` (22:29:46). |
| Code quality | Complete | Применены пять линз `code-review-and-quality` (корректность, читаемость, архитектура, безопасность, производительность) к обоим изменённым файлам кода и к новому тесту на `f0e3517d`. В контексте изучены: `ActionSheet` и оба его потребителя, Widgetbook-примеры листов, `NavBar`, `showDoableSheet`, `DailyChoiceCalendar` с исключением из взаимодействия во время перехода, `DailyChoiceCatalogBody`, `doableTheme` (`surface = bg`), а также владельцы `Ink` и `InkWell` в шапке месяца, днях сетки и выборе периода. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Целевой диапазон: `6a9eae993fdabccbbf9e87d55c4ba99fe4cddd25..f0e3517d1ef3ac0952557830ae60eb91ad9f0bdb`, три коммита. Каждый из четырёх путей учтён: `sheet.dart` в U1, файл раскладки календаря и его тест в U2, `tasks.md` — как свидетельство планирования. Коммит `0f619d52` (задача 1.1) входит в U1, `484b6769` (задача 1.2) — в U2. Коммит `f0e3517d` отмечает задачу 1.3; её проверки подтверждены для обеих единиц. Неучтённого или постороннего кода в диапазоне нет.

Лист. `SafeArea.minimum` берёт максимум из системного и минимального отступа, а не их сумму. Поэтому нижний минимум обнулён, а 16 dp (`DoableMetrics.space4`) перенесены во внутренний `Padding`, как в `NavBar`. `Material` листа остался снаружи `SafeArea`, поэтому фон доходит до края экрана. `showModalBottomSheet(useSafeArea: true)` не поглощает нижний отступ, и он доходит до `Sheet`. С открытой клавиатурой Flutter обнуляет `padding.bottom`, поэтому над клавиатурой остаётся 16 dp без удвоения. Потребители листа не менялись. Сценарий «Меню режимов не прижато к системной области» не закреплён автоматическим тестом. Это решение человека из базового коммита `6a9eae99` и решения 4 design.md: отступ проверяется на телефоне. Существующие тесты меню режимов и листа «Новый дневной выбор» прошли в `mise run check`.

Календарь. Сдвиг `(1 − p) · W` задаётся в `_RenderExpansionLayout.performLayout` по высоте недели из того же прохода. Отрисовка и проверка попаданий используют тот же offset из parent data. Видимая часть месяца равна `p · M`, формула высоты не изменилась. `ColoredBox` с `DoableColors.bg` лежит вне `Opacity(p)`, поэтому неделя ниже края закрыта при любом `p`. Под фоном видна только полоса недели высотой `(1 − p) · W` с прозрачностью `1 − p`. Выбор года и месяца проходит через тот же дочерний элемент. Оба каталога показывают календарь на фоне `Scaffold` = `colorScheme.surface` = `bg`, поэтому в покое фон незаметен. Каждый `Ink` и `InkWell` в раскрытом месте имеет собственный прозрачный `Material` над новым фоном, так что отклик нажатия не скрыт. Доступ `extension<DoableColors>()!` соответствует соседним компонентам календаря. Новый тест сценария «Месяц надвигается на неделю своим фоном» проверяет положение и цвет фона, его расположение вне прозрачности и обе прозрачности в середине удерживаемого перетягивания. На базовой реализации нет фона с нужным положением, поэтому тест там не проходит. Лишних механизмов, параметров и обработки недостижимых состояний нет.

Безопасность и производительность: недоверенного ввода, хранения данных и внешних границ изменение не затрагивает. В кадре анимации добавляется только заливка прямоугольника без нового слоя прозрачности.

На телефоне остаются ручные проверки пользователя из решения 4 design.md: отступ листов при жестах и трёх системных кнопках, вид перехода в обеих темах и удобство перетягивания. По правилам репозитория они не блокируют завершение фазы, и в этом ревью они не выполнялись.
