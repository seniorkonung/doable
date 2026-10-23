# OpenSpec Implementation Review: redesign-intention-pickers

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 2.13 реализована. У заголовка `TopBar` появился флаг `namesRoute`, поэтому экранный диктор называет экран выбора при открытии, как раньше с заголовком `AppBar`. Узел заголовка остался одним узлом-заголовком, не стал кнопкой, а узел крестика не изменился. Проверка семантики заголовка теперь требует `namesRoute`. Задачи фазы 2 (2.1–2.13) выполнены, полные проверки проекта на проверяемой ревизии прошли. Неразрешённых замечаний нет, принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 74e992b56a08a7dc3fdc8efc969ee0d68ff30be7
- **Base commit:** 74e992b56a08a7dc3fdc8efc969ee0d68ff30be7
- **Reviewed head:** 8051c9121ce92699cedc9ceb54800263496756b8
- **Target commits:** ["8051c9121ce92699cedc9ceb54800263496756b8"]
- **Reviewable paths:** ["lib/src/design_system/components/top_bar.dart", "openspec/changes/redesign-intention-pickers/tasks.md", "test/design_system/top_bar_test.dart"]
- **OpenSpec change:** redesign-intention-pickers
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-pickers/tasks.md"]

## Reviewed increment

### U1 · Экранный диктор называет экран выбора заголовком верхней панели

- **Work items:** ["2.13"]
- **Requirements and scenarios:** ["intention-management: Экран поиска для выбора намерения — шапка с крестиком и заголовком, который называет выбираемое", "plan.md: Phase 2 Ready to advance — доступность соответствует спецификации", "design: решение 8 — `TopBar` с семантикой заголовка, который называет маршрут"]
- **Affected boundary:** Пользователи экранного диктора, которые открывают поиск действия или исходного намерения; компонент `TopBar` модуля основ и его потребитель `IntentionPickerView`
- **Implementation target:** ["lib/src/design_system/components/top_bar.dart", "test/design_system/top_bar_test.dart"]
- **Applicable constraints and non-goals:** Компонент остаётся представлением: получает готовые тексты и обработчики, предметных типов не знает (ADR-0030). Заголовок должен вести себя для диктора так же, как заголовки листа и диалога подтверждения дизайн-системы. Вид панели, тексты и обработчики не меняются. Стрелка «назад» и правое действие не добавляются. Проверки обходятся без эмулятора и устройства.
- **Excluded change scope:** Поиск участника переводится на экран выбора только в фазе 3. Объявление TalkBack на устройстве пользователь сверяет вручную.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер по `implementation-decision-review` получил нейтральный бриф, диапазон 74e992b56a08a7dc3fdc8efc969ee0d68ff30be7..8051c9121ce92699cedc9ceb54800263496756b8 и ровно 2 пути U1. Он вернул «No substantive findings» с полным покрытием. Ревьюер сверил решение с исходниками Flutter 3.47.1. Material-страница оборачивает содержимое в `Semantics(scopesRoute: true)`, а `AppBar` на Android ставит на заголовок `namesRoute`. Других узлов с `namesRoute` в маршруте экрана выбора нет. Артефакты планирования, история коммитов и отчёт ревьюеру не передавались. |
| OpenSpec conformance | Complete | Рабочая копия чистая, HEAD = 8051c9121ce92699cedc9ceb54800263496756b8. `mise run check` в рабочей копии на этой ревизии завершился с кодом 0. `dart format` не изменил ни одного из 792 файлов, `flutter analyze` замечаний не нашёл. Прошли 3261 обычный и 18 процессных тестов, в том числе `test/design_system/top_bar_test.dart` и проверки страниц поиска действия, исходного намерения и `IntentionPickerView`. Команда `mise exec --no-deps -- openspec validate redesign-intention-pickers --strict --no-interactive --json` вернула valid, 1 из 1. `openspec instructions apply` показывает 23 из 23 выполненных задач. Критерии задачи 2.13 сверены с диффом в обе стороны: отметка в `tasks.md` подтверждена кодом и проверкой. |
| Code quality | Complete | Линзы `code-review-and-quality` применены к обоим путям поставки на 8051c9121ce92699cedc9ceb54800263496756b8: корректность, читаемость, архитектура, безопасность, производительность. Просмотрены также неизменённые `sheet.dart` и `confirm_dialog.dart`, где `namesRoute` тоже ставится без разбора платформы, единственный потребитель `IntentionPickerView` и состав платформ (в репозитории только `android/`). Поэтому различие с `AppBar`, который на iOS не называет маршрут, на поставляемую сборку не влияет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверен один целевой коммит и 3 пути. Путь планирования один, `tasks.md`: в нём изменилась только отметка задачи 2.13. Остальные два пути относятся к U1, несопоставленного кода нет.

Изменение поставки — одна строка: `namesRoute: true` на существующем узле `Semantics(container: true, header: true)` вокруг текста заголовка. Новых узлов семантики не появилось, ветка крестика с `MergeSemantics` не изменилась. Флаг проверяет уже существующий тест семантики, отдельный тест не добавлен. Тест поймает регрессию, если флаг пропадёт при будущей правке панели. Само объявление при смене маршрута выполняет движок Flutter, поэтому лишних элементов в тестах нет.

Фаза 2. Предыдущее ревью этой фазы на диапазоне 40e69679b54c180cf2d50fc1ab5f328b482ce384..c57cc8222b8d417c8c669707b237558011093dc6 закончилось без неразрешённых замечаний. Единственным открытым условием готовности оставалось название экрана для диктора, и теперь оно выполнено задачей 2.13. Полные проверки проекта прошли на 8051c9121ce92699cedc9ceb54800263496756b8.

Ограничения. Проверки на устройстве по правилу проекта не выполнялись. Пользователь вручную сверяет объявление названия экрана TalkBack при открытии поиска действия и исходного намерения. Остаются и ручные проверки фазы 2 из задачи 2.12: вид обоих поисков против макетов в обеих темах, закреплённая шапка при клавиатуре, линия тегов с «+N», панель фильтра, «Сбросить фильтры», выход крестиком и системным «назад», создание и замена пути дневного выбора. Сборку APK это ревью не повторяло.
