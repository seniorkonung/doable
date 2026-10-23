# OpenSpec Implementation Review: add-tags-panel

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 4.14 выполнена без замечаний. Контракт набора тегов черновика сведён к тому, что читает панель тегов. Изменения публикуются только при смене набора, а включение и исключение отвергаются во время отправки и после закрытия сессии. Задача 4.15 убрала два дубля проверок панели фильтра. Оставшиеся дубли проверок создания и удаления тега в фильтре и не зависящие от языка утверждения двуязычного теста по решению пользователя переданы новой незавершённой задаче 4.16 фазы 4. `mise run check` на проверяемой голове проходит. Сохраняется принятый остаточный риск AR1: действие шапки «Сбросить» при крупном системном шрифте вытесняет заголовок и список панели фильтра.

## Review target

- **Baseline ref:** ff30c8cd4bfb21bd767d2b9e247c2e38304f734b
- **Base commit:** ff30c8cd4bfb21bd767d2b9e247c2e38304f734b
- **Reviewed head:** 94da5942dd5b596d31535c9e829035d3f6a5f442
- **Target commits:** ["e5661fd3d3587a834eea921728cbb421e3b26bda", "94da5942dd5b596d31535c9e829035d3f6a5f442"]
- **Reviewable paths:** ["lib/src/intention/presentation/editor/intention_draft_tag_set.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/tag/presentation/panel/tags_panel_view_model.dart", "openspec/changes/add-tags-panel/tasks.md", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/tag/presentation/panel/tags_panel_test.dart", "test/tag/presentation/panel/tags_panel_view_model_test.dart"]
- **OpenSpec change:** add-tags-panel
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-tags-panel/tasks.md"]

## Reviewed increment

### U1 · Контракт набора тегов черновика несёт только то, что читает панель тегов

- **Work items:** ["4.14"]
- **Requirements and scenarios:** ["tag-management: Выбор тегов намерения в панели — Scenario: Черновик меняется без записи назначений", "intention-management: Сессия черновика создания намерения", "tag-management: Явно подтверждаемое удаление тега — Scenario: Удалённый тег уходит из черновика"]
- **Affected boundary:** Сессия создания намерения (`IntentionEditorViewModel`) и модель панели тегов в контексте черновика
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_draft_tag_set.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/tag/presentation/panel/tags_panel_view_model.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/tag/presentation/panel/tags_panel_test.dart", "test/tag/presentation/panel/tags_panel_view_model_test.dart"]
- **Applicable constraints and non-goals:** До принятия отправки выбор и снятие тегов меняют только черновик, без назначений и команд графа. С принятием отправки черновик фиксируется до её результата. Поведение панели тегов и панели создания не меняется. Каждая проверка ловит регресс, который не ловит другая.

### U2 · Каждое поведение панели фильтра проверяется один раз, на двух языках — только зависящие от языка строки

- **Work items:** ["4.15"]
- **Requirements and scenarios:** ["intention-management: Условия по тегам в панели тегов (все четыре сценария)", "intention-management: Снятие условий при удалении тега", "tag-management: Создание тега из панели — Scenario: Закрытие панели до подтверждения создания"]
- **Affected boundary:** Проверки модели и виджета панели тегов в режиме фильтра
- **Implementation target:** ["test/tag/presentation/panel/tags_panel_test.dart", "test/tag/presentation/panel/tags_panel_view_model_test.dart"]
- **Applicable constraints and non-goals:** Ни одно поведение режима фильтра не теряет проверки. Поведение панели в коде не меняется. В обычных тестах нет замеров времени.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | U1 и U2 делят два тестовых пути, поэтому их проверял один свежий изолированный ревьюер по `implementation-decision-review`. Он получил общий бриф с отдельными целями U1 и U2 и объединённым списком из семи путей на ff30c8cd4bfb21bd767d2b9e247c2e38304f734b..94da5942dd5b596d31535c9e829035d3f6a5f442. Артефактов планирования, истории коммитов и прежнего отчёта он не видел. Все семь путей он прочитал полностью, а неизменённые файлы — только как контекст. По U1 замечаний нет. По U2 одно замечание о дублях проверок; его исправление передано задаче 4.16. Тесты ревьюер не запускал: их прогон входит в проход соответствия. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии: она чистая, HEAD = 94da5942dd5b596d31535c9e829035d3f6a5f442. `mise run check` завершился с кодом 0: `flutter analyze` без замечаний, обычные тесты прошли все 3209, `check:process-tests` — 18 из 18. `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive --json` даёт valid. Поиск по `lib/` и `test/` на head не находит `IntentionDraftTagAddition`, `IntentionDraftTagSetSnapshot` и чтений доступности из снимка набора, как требует проверка задачи 4.14. Критерии приёмки 4.14 и 4.15 сверены с кодом и тестами диапазона. |
| Code quality | Complete | Линзы `code-review-and-quality` применены ко всем путям поставки: корректность, читаемость, архитектура, безопасность и производительность. Проверены `_SessionDraftTagSet` (`add`, `remove`, `_publish`, `_close`), `_addTag`, условие публикации в `listenSelf`, перенос `IntentionDraftAvailability` в состояние сессии и его потребители в `intention_editor_page.dart`. Проверены и чтение набора в `TagsPanelViewModel` (`build`, `toggle`, `_markCreated`, `_rowsOf`), а также оставшиеся и удалённые проверки панели фильтра. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Действие шапки раскрываемого листа при крупном системном шрифте вытесняет заголовок и список панели фильтра

- **Evidence:** В `lib/src/design_system/components/sheet.dart` (head) `_RenderTitleLayout.performLayout` раскладывает действие с `BoxConstraints(maxWidth: width)` и отдаёт заголовку ширину `math.max(0, width - 2 * inset)`, где `inset` — ширина действия. Нижней границы ширины заголовка нет. Шапка не прокручивается: в `_ExpandableSheetState.build` она стоит над `pinned` и `Expanded` тела. Ширина подписи растёт с масштабом текста, а масштаб в приложении не ограничен: кроме локального `TextScaler.noScaling` в `day_heading.dart`, ограничений нет. При этом компоненты модуля основ уже проверяются при масштабах до 2,5 (`button_test.dart`, `empty_state_test.dart`, `list_state_test.dart`, `tag_color_picker_test.dart`, `week_strip_day_test.dart`). Действие показывает панель тегов в режиме фильтра, пока есть условие по тегам (`lib/src/tag/presentation/panel/tags_panel.dart`).

  Замер сделан временным виджет-тестом в этой рабочей копии на head; после прогона тест удалён. Условия: шрифт Inter, окно 360×720 dp с отступами 24/48, заголовок «Фильтр по тегам», пояснение режима фильтра и действие «Сбросить». Результаты:

  При масштабе 1,0 заголовок занимает 161 × 22 (одна строка), тело — 264 px, как и без действия. При 1,3 заголовок 118 × 58 (две строки), тело 218 против 247 без действия. При 1,5 заголовок 89 × 99 (три строки), тело 142 против 208. При 1,75 заголовок 52 × 234, тело 0 против 187, `RenderFlex` переполнен на 8 px. При 2,0 заголовок 16 × 484 и переносится по буквам, тело 0 против 134, переполнение 306 px.
- **Evidence revisions:** ["e7ca4dce7be1fd016d22e390763f9ea3262cf141"]
- **Potential impact:** Человек с системным масштабом текста от 1,5 открывает панель фильтра, где уже есть условия. Заголовок «Фильтр по тегам» занимает три строки и больше, список тегов сжимается на треть. От 1,75 список сжимается до нуля, лист переполняется, заголовок рвётся внутри слов, и выбрать или переключить тег в панели нельзя, пока условия не сняты. Без условий «Сбросить» не показывается, и панель остаётся рабочей.
- **Acceptance rationale:** Пользователь решил принять деградацию без исправления в этом изменении и не назвал отдельной причины. Исправление потребовало бы новой задачи фазы 4: изменить раскладку шапки `Sheet.expandable` при нехватке ширины, решить это в design.md и закрепить проверкой компонента при крупном масштабе. Отказ от исправления сохраняет шапку по макету и не добавляет работы в фазу 4. Условие не исправлено и не опровергнуто.
- **Scope and assumptions:** Только действие шапки `Sheet.expandable` из `lib/src/design_system/components/sheet.dart` на ревизии e7ca4dce7be1fd016d22e390763f9ea3262cf141, у которого один потребитель — «Сбросить» в панели тегов в режиме фильтра при непустых условиях. Деградация начинается от системного масштаба текста 1,3 и делает панель непригодной от 1,75. Приложение масштаб текста не ограничивает. Принятие не распространяется на другие шапки и листы и на иное поведение шапки.
- **Reopen when:** Действие шапки получает второй потребитель или другую подпись; меняется раскладка шапки `Sheet.expandable`; спецификация или правило модуля основ начинают требовать работоспособности при крупном системном масштабе текста; человек сообщает о недоступной панели фильтра при крупном шрифте.
- **Acceptance authority:** Явное решение пользователя «Принять риск» по F1 в сессии разрешения замечаний ревью реализации add-tags-panel.
- **Originating finding:** F1
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

Просмотрены оба целевых коммита. Задача 4.14 сопоставлена с U1 (коммит e5661fd3d3587a834eea921728cbb421e3b26bda), задача 4.15 — с U2 (коммит 94da5942dd5b596d31535c9e829035d3f6a5f442). В `tasks.md` диапазон меняет только отметки выполнения 4.14 и 4.15. Это свидетельство планирования, и обе отметки подтверждены кодом и тестами. Все семь путей поставки и тестов вошли в единицы, несопоставленных путей нет. Тестовые пути панели входят в U1 механически: чтение `tagSet.current` вместо `tagSet.current.tagIds`. Задача 4.16 добавлена после проверки и в проверяемый диапазон не входит.

U1. `IntentionDraftTagSet` теперь даёт только `current` (`Set<TagId>`), `changes`, `add` и `remove` без результата. Единственный потребитель, `TagsPanelViewModel`, читает `current.contains`, подписывается на `changes` ради пересчёта отметок и вызывает `add` и `remove`. Доступность черновика перенесена в `intention_editor_state.dart`; её читают только страница и сессия создания. `listenSelf` публикует набор только при смене его экземпляра. `withTag`, `withoutTag` и снятие удалённых тегов возвращают прежний экземпляр, если состав не изменился. Поэтому смена доступности и пустое снятие удалённых во время отправки ничего не публикуют. `_close` больше не публикует закрытое состояние, а только завершает поток. Панель реагирует на поток лишь пересчётом отметок, так что потерь нет. `add` и `remove` проверяют `_isClosed`, а затем `_acceptsDraftChanges` сессии. Проверка `_isClosed` не дублирует `ref.mounted`: она не даёт набору прежнего построения менять черновик сессии, построенной заново. Тесты сессии показывают отвергнутые включение и исключение во время отправки, после успешного создания и после освобождения по неизменному набору и пустому `published`. После отказа отправки включение снова меняет набор и публикуется. Проверок исходов добавления и доступности в снимке больше нет.

U2. Удалены тесты модели «Нажатия переключают надобность по кругу…» и «Закрытие панели до подтверждения создания не добавляет условия». Их утверждения покрывают виджет-тесты `tags_panel_test.dart:265` и `:383`, включая отсутствие команд графа и пересчёт «Сбросить». Тесты цикла надобности и «Сбросить» выполняются один раз на русском. На двух языках остался только `:209`. Сценарии требования «Условия по тегам в панели тегов» проверены так: цикл — `:265`, открытая панель — `:209` и `tags_panel_view_model_test.dart:1072`, «Сбросить» — `:316`, созданный тег — `:346` и `tags_panel_view_model_test.dart:1108`. Оставшиеся дубли проверок создания и удаления тега в фильтре и не зависящие от языка утверждения теста `:209` переданы задаче 4.16.

AR1 перенесён без повторной проверки. `sheet.dart` и `tags_panel.dart` между e7ca4dce7be1fd016d22e390763f9ea3262cf141 и проверяемой головой не менялись, и условие принятия не нарушено.

Не выполнялись сборка APK и проверки на устройстве. На устройстве пользователю остаётся проверить выбор тегов черновика в панели над панелью создания, в том числе после отказа отправки, и панель фильтра (см. AR1).
