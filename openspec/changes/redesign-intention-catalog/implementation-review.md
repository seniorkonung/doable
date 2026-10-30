# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 1.9–1.11 завершают фазу 1. Хранитель места удерживает первую видимую строку, когда верх списка приходится на промежуток между строками. Пауза ввода, загрузка и отказы первой порции сразу встают наверх. Повторяющиеся случаи `IntentionSearchKind` удалены без потери покрытия. Полная проверка проекта проходит.

## Review target

- **Baseline ref:** 4cd590d54d7a120b0b0e2dcf4c15be278cde6a6d
- **Base commit:** 4cd590d54d7a120b0b0e2dcf4c15be278cde6a6d
- **Reviewed head:** 2f87e17b0151558f0336c9aae5390901702ca22b
- **Target commits:** ["3343a0de58f869e053b94e24410d3b80e3f9314a", "d5512a523b621b09ad9f921146c63ca9f76ff29c", "ba20efd907d256f8e713a4b2ac2b7361fab1633c", "2f87e17b0151558f0336c9aae5390901702ca22b"]
- **Reviewable paths:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart", "openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/intention/presentation/search/intention_search_kind_test.dart", "test/intention/presentation/search/intention_search_list_test.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Удержание первой видимой строки, когда верх списка в промежутке между строками

- **Work items:** ["1.9"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога", "design: решение 5"]
- **Affected boundary:** Выдача экранов выбора при согласовании с подтверждёнными операциями без смены запроса; общий `ResultsScrollKeeper`, которым пользуется и прежняя выдача каталога.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart", "test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Соседние строки-кандидаты и остальное поведение хранителя не меняются. Прежняя выдача каталога без промежутков между строками ведёт себя как раньше.

### U2 · Состояния вместо строк сразу сверху

- **Work items:** ["1.10"]
- **Requirements and scenarios:** ["intention-management: Состояния получения каталогов и подробных данных намерений", "design: решение 5 (мгновенный переход наверх)"]
- **Affected boundary:** Выдача экранов выбора при переходе к паузе ввода, загрузке или отказу первой порции во время прокрутки.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart", "test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Прокрутка в `IntentionSearchList` остаётся одной для всех состояний. Удержание строки при согласовании, начало новой выдачи сверху и прежняя выдача каталога не меняются.

### U3 · Удаление повторяющихся проверок `IntentionSearchKind`

- **Work items:** ["1.11"]
- **Requirements and scenarios:** ["tasks.md: 1.11"]
- **Affected boundary:** Набор тестов модуля поиска намерений; код приложения не меняется.
- **Implementation target:** ["test/intention/presentation/search/intention_search_kind_test.dart"]
- **Applicable constraints and non-goals:** Остаются проверки варианта каталога. Префиксы ключей экранов выбора закреплены тестами экранов выбора. Называние типа закреплено доступными названиями в `intention_picker_row_test.dart`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Работали два свежих изолированных ревьюера (Sonnet, `implementation-decision-review`), планирующие артефакты им не передавались. Первый получил группу перекрытия U1+U2 с путями `results_scroll_keeper.dart` и `intention_search_list_test.dart`; в его бриф вошла и цель U3. Второй отдельно проверил U3 с путём `intention_search_kind_test.dart`. Находок нет. |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве на голове 2f87e17b0151558f0336c9aae5390901702ca22b без незакоммиченных изменений. `mise run check`: `dart format` без изменений, `flutter analyze` без замечаний, 3835 обычных и 18 процессных тестов прошли. `openspec validate redesign-intention-catalog --strict --json` — valid. Когда `results_scroll_keeper.dart` временно вернули к базе 4cd590d54d7a120b0b0e2dcf4c15be278cde6a6d, три новых теста `intention_search_list_test.dart` упали; после восстановления файла дерево снова чистое. |
| Code quality | Complete | Пять осей проверены по `results_scroll_keeper.dart` на голове, вместе с вызывающими `intention_search_list.dart` и `intention_search_results.dart` и с построением запроса в `intention_catalog_view_model.dart`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверены все четыре коммита диапазона и все пять изменённых путей.

- **U1.** Условие `extent.end > currentOffset` выбирает первую построенную строку, нижний край которой ниже верха списка. Если верх списка внутри строки, результат тот же, что у прежнего условия, в том числе на точной границе строк. Если верх в промежутке, сдвиг внутри строки отрицателен и проходит через существующие пути `exact.start + offsetWithinItem` и приближения с ограничением `_jumpWithinExtent`.
- **U2.** `_showsStatusInsteadOfRows` повторяет выбор `IntentionSearchList` исчерпывающим `switch` с теми же параметрами `skipLoadingOnReload`/`skipLoadingOnRefresh`. Поэтому новое состояние модели не скомпилируется, пока его не классифицируют.
- **Прежняя страница каталога.** Хранитель там прыгает наверх у ещё не перестроенного `ListView` и может записать 0 в `PageStorage`. Видимого изменения поведения это не даёт: каждая сборка модели создаёт новый `IntentionCatalogQuery` (`intention_catalog_view_model.dart:113`), а состояния вместо строк возникают только в сборке и при первой порции. Значит, любая выдача после такого состояния начинается заново, и хранилище смещения заменяется.
- **U3.** Префиксы `daily-choice-action`, `daily-choice-source` и `participant-picker` используются поиском по ключам в тестах экранов выбора. Называние типа для всех трёх назначений проверяют доступные названия в `intention_picker_row_test.dart`.
- **Планирование.** Отметки 1.9–1.11 в `tasks.md` и `task-profiles.md` — планирующие свидетельства. Задачи будущих фаз не считались обязательствами диапазона.
- **Не затронуто.** Данных, схемы, безопасности и внешних зависимостей диапазон не касается.
