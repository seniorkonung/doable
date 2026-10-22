# OpenSpec Implementation Review: add-tags-panel

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 2.24 выполнена по существу. Сквозная проверка «серия назначений и снятий сохраняется без сообщений об успехе» теперь ждёт строку тега «Работа», у которой доступное название — только название тега, а отметку передаёт отмеченное состояние. Неотмеченная строка ожидание не завершает. Остальные шаги и утверждения проверки не изменились. Полная проверка фазы `mise run check` на проверяемой голове проходит, так что фаза 2 готова к завершению. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** a9cd702a91c8f50542c98f0b1ef3f83d3a8a7c84
- **Base commit:** a9cd702a91c8f50542c98f0b1ef3f83d3a8a7c84
- **Reviewed head:** bf7624bb30f60feb8612fd8965ad83d0f504a64c
- **Target commits:** ["bf7624bb30f60feb8612fd8965ad83d0f504a64c"]
- **Reviewable paths:** ["openspec/changes/add-tags-panel/tasks.md","test/app/tag_app_flow_test.dart"]
- **OpenSpec change:** add-tags-panel
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-tags-panel/tasks.md"]

## Reviewed increment

### U1 · Сквозная проверка назначения ждёт отмеченную строку по семантике строки

- **Work items:** ["2.24"]
- **Requirements and scenarios:** ["tag-management: Выбор тегов намерения в панели", "tag-management: Отметка тега объявляется один раз", "tag-management: Локализация и доступность управления тегами"]
- **Affected boundary:** Сквозная проверка панели тегов в запущенном приложении: страница намерения, панель тегов и хранилище назначений
- **Implementation target:** ["test/app/tag_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Меняется только проверка. Поведение приложения и семантика строки тега остаются прежними. Остальные шаги и утверждения проверки не меняются. Обычные тесты обходятся без замеров времени и расширенных тайм-аутов.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный ревьюер работал по `implementation-decision-review`. Он получил нейтральный бриф без артефактов планирования, истории коммитов и прежнего отчёта. Его цель — единственный путь поставки `test/app/tag_app_flow_test.dart` на голове bf7624bb30f60feb8612fd8965ad83d0f504a64c. Ревьюер сообщил о полном покрытии и замечаний не нашёл. Он прогнал `mise exec --no-deps -- flutter test test/app/tag_app_flow_test.dart`: прошли все 3 проверки. Ограничение, которое ревьюер раскрыл сам: отрицательный прогон с неотмеченной строкой не выполнялся. То, что ожидание падает на неотмеченной строке, установлено разбором кода `TagRow` и данных фикстуры. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии: она чистая, HEAD = bf7624bb30f60feb8612fd8965ad83d0f504a64c. `mise run check`: код 0. Внутри него `dart format` и `flutter analyze` прошли без замечаний, все 3480 обычных тестов прошли, а `check:process-tests` прошёл 18 из 18. `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive --json`: valid. Все критерии 2.24 сопоставлены с диффом. В `tasks.md` диапазон только отметил 2.24 выполненной, и это подтверждено. Сборка APK и проверки на устройстве не выполнялись. |
| Code quality | Complete | Оркестратор применил линзы `code-review-and-quality` к `test/app/tag_app_flow_test.dart` на проверяемой голове. Сверено несколько вещей. Во-первых, искатель `_checkedRow` против `MergeSemantics`/`Semantics(label, checked)` в `lib/src/design_system/components/tag_row.dart:43-47`. Во-вторых, название «Работа» тега `lastTagNumber` в `test/support/tag_storage_fixture.dart`. В-третьих, использование существующего опроса `_until` без новых тайм-аутов. Наконец, сверена идиома проверок отмеченного состояния `flagsCollection.isChecked` / `CheckedState` с другими сквозными проверками, например `test/app/long_term_relation_app_flow_test.dart:128`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Просмотрен единственный целевой коммит bf7624bb30f60feb8612fd8965ad83d0f504a64c. Задача 2.24 сопоставлена с U1, а `tasks.md` служит свидетельством планирования с отметкой выполнения. Несопоставленных путей нет. Кода приложения в диапазоне нет.

Подтверждено следующее. `_checkedRow` ищет внутри нажатой строки узел семантики, у которого название ровно «Работа» и `isChecked == CheckedState.isTrue`. Строка объединяет семантику: название приходит из `Semantics.label` (в панели это название тега), видимый текст исключён, а `checked` выставлен только при отметке. Поэтому прежнее название «Работа, отмечен» больше не ищется, а неотмеченная строка ожидание не завершает: через 100 попыток `_until` проверка падает. Раньше времени ожидание тоже не завершится. По фикстуре «Работа» не назначен намерению 1, а единственное назначение «Дом» снимается ещё до шага с панелью. Если бы семантика была выключена, `debugSemantics` вернул бы null, и проверка упала бы, а не прошла. Утверждения об отсутствии `SnackBar`, о строках `tag_assignments`, о трёх завершениях операций и о согласованности после повторного открытия не изменились.

Сборка APK и проверки на устройстве не выполнялись. Ручные проверки предыдущих задач фазы 2 остаются за пользователем: объявление отметки строки TalkBack один раз, закрытие панели свайпом шапки во время создания тега, отменённое системой касание шапки и вид всех листов после перехода на новые функции показа.
