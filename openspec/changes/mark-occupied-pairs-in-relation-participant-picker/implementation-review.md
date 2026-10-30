# OpenSpec Implementation Review: mark-occupied-pairs-in-relation-participant-picker

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 1.17 выполнила решение по прежней находке F1: `ResultsScrollKeeper` больше не сверяет якорь с запросом выдачи и не хранит запрос в якоре, а удалённая ветка действительно была недостижима, поэтому поведение не изменилось. Полные проверки фазы 1 проходят на проверенной ревизии, итоговый APK собран. Активных находок нет, принятых рисков нет.

## Review target

- **Baseline ref:** 2dbbb20d17f9416b574948c1600667f649e7a431
- **Base commit:** 2dbbb20d17f9416b574948c1600667f649e7a431
- **Reviewed head:** c373c94de8a782119be1576f29a0b4a7957d86b2
- **Target commits:** ["0b4ca47dc6887a7ed15047389fa9a3f4d83cab03","c373c94de8a782119be1576f29a0b4a7957d86b2"]
- **Reviewable paths:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md"]
- **OpenSpec change:** mark-occupied-pairs-in-relation-participant-picker
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/mark-occupied-pairs-in-relation-participant-picker/task-profiles.md","openspec/changes/mark-occupied-pairs-in-relation-participant-picker/tasks.md"]

## Reviewed increment

### U1 · Хранитель места не несёт недостижимую сверку якоря с выдачей

- **Work items:** ["1.17"]
- **Requirements and scenarios:** ["intention-management: Сохранение состояния загруженного каталога", "intention-management: Сохранение позиции после локального согласования", "plan.md Phase 1: Подтверждённое изменение на странице, открытой из поиска, не сдвигает первую видимую строку", "plan.md Phase 1: Ready to advance"]
- **Affected boundary:** Человек, прокручивающий выдачу поиска намерений в общем каталоге, поисках дневного выбора и поиске участника; поток состояний модели каталога и оба виджета выдачи, которые пользуются общим хранителем.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart"]
- **Applicable constraints and non-goals:** Наблюдаемое поведение не меняется: якорь не применяется к чужой выдаче, место внутри выдачи удерживается, новая выдача начинается сверху. Условие `identical(previousState.query, nextState.query)`, условие `_isShownResultsOf`, поле `_query` и сброс якоря в `_jumpToTop` остаются. Новые проверки не добавляются, существующие, спецификации, `plan.md`, `design.md` и `adr.md` не меняются.
- **Excluded change scope:** Фаза 2 не начата и не считается недоставленной: требование «Восстановление занимающей связи из создания» и правило открытия восстановленной связи в `app-navigation`.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий проверяющий без истории получил нейтральный бриф и единственный путь доставки U1 в точном диапазоне. Находок нет, планирующие материалы он не открывал. Его довод о приостановке подписок неверен: он читал `riverpod` 3.4.3, а в закреплённом `flutter_riverpod` 3.4.2 `_updateTickerMode` приостанавливает только подписки `ref.watch` (`consumer.dart:424`), `ref.listen` же получает каждое событие, в том числе у закрытого списка. Оркестратор заново проследил поток с этой поправкой, вывод не изменился. |
| OpenSpec conformance | Complete | В рабочей копии при чистом дереве и HEAD = c373c94de8a782119be1576f29a0b4a7957d86b2: `mise run check` — exit 0 (`dart format`, проверки скриптов, `flutter analyze` без замечаний, 3901 тест и 18 процессных тестов прошли, в них весь список проверок задачи 1.17); `openspec validate --strict --no-interactive` — valid с ожидаемым INFO об архивации дельты `intention-management` после `redesign-intention-catalog` (Plan Constraints); `grep` по `excludedIntentionId` из задачи 1.16 — 0 совпадений; `flutter build apk --release` — exit 0, артефакт `build/app/outputs/flutter-apk/app-release.apk`. Эмулятор и устройство не запускались. |
| Code quality | Complete | В контексте оркестратора пять осей `code-review-and-quality` применены к `results_scroll_keeper.dart` на проверяемой ревизии и к обоим его потребителям. Удаление убирает из хранителя понятие и поле, ничего не перенося. Импорт `IntentionCatalogQuery` остаётся нужен полю `_query`, устаревших комментариев о запросе якоря нет. Новых входов с недоверенными данными нет, производительность не ухудшилась. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверены оба целевых коммита. 0b4ca47d вносит только оценку профиля задачи 1.17 (планирующее свидетельство). c373c94d — U1 (1.17) и отметка задачи в `tasks.md`; отметка подтверждена диапазоном и проверками выше. Других задач в диапазоне нет.

**Недостижимость удалённой ветки.** Чтобы условие сработало, в `_shown` должна быть выдача с другим запросом при живом якоре. `_shown` меняется только в `onListBuilt`, по уже опубликованному состоянию, а `onCatalogChanged` из `ref.listen` получает каждую публикацию раньше перестройки, и у `IntentionSearchList`, и у `IntentionSearchResults`. Публикация другого запроса при непустом `_query` вызывает `_jumpToTop`, который сбрасывает якорь (`results_scroll_keeper.dart:69-76`, `:139-146`). `_query` не бывает пустым, пока жив якорь: его запоминание идёт после записи запроса. Обратный порядок, когда якорь прежнего запроса запоминается при отставшем `_shown`, закрывает `_isShownResultsOf` (`:88-94`, `:154-158`). Повторно отложенный `afterApproach` якорь сбрасывается тем же путём. `IntentionCatalogInvalidFilter` не несёт запроса, но `_restoreVisualAnchor` снимает якорь для любого состояния кроме `IntentionCatalogLoaded`. Новый объект запроса создаётся при каждом чтении первой порции (`intention_catalog_view_model.dart:128`), поэтому старый запрос не возвращается.

**Критерии 1.17.** Условия `!identical(state.query, anchor.query)` нет, три остальные проверки `_restoreVisualAnchor` сохранены (`:241-243`). У `_VisualAnchor` нет поля `query`, удалены комментарий, параметр конструктора и передача в `_captureVisualAnchor` и `afterApproach`. Перечисленные в задаче условия не менялись. Диапазон меняет только один файл `lib`, а также `tasks.md` и `task-profiles.md`: проверки, спецификации, `plan.md`, `design.md` и `adr.md` не менялись. Отказ от новых проверок обоснован: удалённая ветка недостижима, а поведение покрыто существующими проверками поиска, которые прошли.

**Фаза 1.** Диапазон закрывает последнюю задачу фазы, все 17 задач выполнены, полные проверки на итоговой ревизии проходят.

Ручные проверки на устройстве не выполнялись и остаются за пользователем: метки «Уже связано» и «Связь в архиве» в светлой и тёмной темах, чтение отметки и действия диктором без отдельного узла метки, открытие связи нажатием на текст отмеченной строки и возврат в поиск.
