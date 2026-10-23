# OpenSpec Implementation Review: add-tags-panel

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 3.21–3.23 выполнены по существу. Меню тега теперь стоит у текущего положения удерживаемой строки при каждой раскладке и выбирает сторону по высоте, которую названия пунктов получат на экране. Тег, удаление которого подтверждено пакетом координатора, уходит из черновика при любом состоянии его наблюдения. Тесты изменённых модулей и полная проверка фазы `mise run check` на проверяемой голове проходят. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 52efec008f604601ce9a6fe41a257e7e6832a14b
- **Base commit:** 52efec008f604601ce9a6fe41a257e7e6832a14b
- **Reviewed head:** 29ddbaf6f78f5ff6d824646c8cf7bdcae7b12e33
- **Target commits:** ["726d3ca9f0050ed90f318b8e7c94d53953508528", "1f1a407995c377e82716f9de4659508a28aacb52", "29ddbaf6f78f5ff6d824646c8cf7bdcae7b12e33"]
- **Reviewable paths:** ["lib/src/design_system/components/popup_menu.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "openspec/changes/add-tags-panel/tasks.md", "test/design_system/popup_menu_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **OpenSpec change:** add-tags-panel
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-tags-panel/tasks.md"]

## Reviewed increment

### U1 · Меню тега у текущего положения строки со стороной по высоте на экране

- **Work items:** ["3.21", "3.22"]
- **Requirements and scenarios:** ["tag-management: Панель тегов (Удержание тега открывает его действия)", "tag-management: Локализация и доступность управления тегами", "design: решение 6 (меню у удерживаемой строки через showMenu корневого навигатора)", "design: решение 10 (PopupMenu)"]
- **Affected boundary:** Компонент `showPopupMenu` модуля основ и его единственный потребитель — строка тега в панели тегов
- **Implementation target:** ["lib/src/design_system/components/popup_menu.dart", "test/design_system/popup_menu_test.dart"]
- **Applicable constraints and non-goals:** Компонент остаётся представлением по ADR-0030. Меню остаётся маршрутом над корневым навигатором с барьером, «назад» и семантикой Material. Вид, пункты и порог удержания не меняются. Область поддержки интерфейса — окна шириной от 360 dp (`app-appearance`); раскладка в произвольном окне большого дисплея не гарантируется (ADR-0031).

### U2 · Подтверждённое удаление выбранного тега убирает его из черновика при любом состоянии наблюдения

- **Work items:** ["3.23"]
- **Requirements and scenarios:** ["intention-management: Создание намерения с начальными данными (Выбранный тег удалён перед сохранением; Удаление выбранного тега завершилось после отправки)", "tag-management: Явно подтверждаемое удаление тега (Удалённый тег уходит из черновика)", "design: решение 8 (черновик при удалении тега)"]
- **Affected boundary:** Сессия черновика создания намерения и подтверждённые пакеты координатора графа
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_editor_view_model.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **Applicable constraints and non-goals:** Все записи графа идут через координатор, источник подтверждённых пакетов для открытых представлений. Наблюдение `watchTag` остаётся источником проекции. Атомарная проверка существования тегов при создании остаётся. Протокол отправки, предъявление отказов и поведение условий поиска не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных ревьюера работали по `implementation-decision-review` с нейтральными брифами без артефактов планирования, истории коммитов и прежнего отчёта, на 52efec008f604601ce9a6fe41a257e7e6832a14b..29ddbaf6f78f5ff6d824646c8cf7bdcae7b12e33. U1 получил `popup_menu.dart` и его тест, U2 — `intention_editor_view_model.dart` и его тест; пути не пересекаются. Оба доложили полное покрытие. Ревьюер U2 существенных замечаний не нашёл. Ревьюер U1 сообщил о переполнении строки пункта в окне уже 244 dp; оно не признано замечанием, довод — в разделе покрытия. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии: она чистая, HEAD = 29ddbaf6f78f5ff6d824646c8cf7bdcae7b12e33. `mise exec --no-deps -- flutter test test/design_system/popup_menu_test.dart test/design_system/text_metrics_test.dart test/intention/presentation/editor/intention_editor_view_model_test.dart test/tag/presentation/panel/tags_panel_test.dart`: все 100 тестов прошли. `mise run check`: код 0; `flutter analyze` прошёл без замечаний, обычные тесты прошли все 3528, `check:process-tests` — 18 из 18. `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive --json`: valid. Критерии приёмки и проверки 3.21–3.23 сверены с кодом и тестами диапазона. |
| Code quality | Complete | Линзы `code-review-and-quality` применены к `showPopupMenu`, `_rectIn`, `_PopupMenuPanel.heightOf` и `_nameStyle`, `tallestTextHeight` как контексту, `IntentionEditorViewModel._onCompletion`, `_tagDeleted`, `_removeTagsDeletedDuringSubmission` и освобождению подписок. Сверены порядок публикации пакетов координатора (синхронный broadcast в порядке принятия) и ограничения маршрута меню Flutter. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Просмотрены все три целевых коммита. Задачи 3.21 и 3.22 сопоставлены с U1, 3.23 — с U2. `tasks.md` в диапазоне меняет только отметки выполнения 3.21–3.23; это свидетельство планирования, и отметки подтверждены кодом и тестами. Все четыре пути поставки и тестов вошли в единицы, несопоставленных путей нет.

U1. `positionBuilder` вызывается в `LayoutBuilder` маршрута меню при каждой раскладке и берёт прямоугольник строки заново. Обратный вызов после кадра перестраивает меню, если строка разложилась позже маршрута, и затихает, когда строка стоит на месте. Строка, ушедшая из дерева, оставляет меню на последнем месте. Тест «меню следует за строкой, которую опускает скрытая после открытия меню клавиатура» проверяет критерий 3.21; поворот и изменение окна идут тем же путём перестройки по `MediaQuery`. Стиль названия с `inherit: false` одинаково разрешается в `tallestTextHeight` и в `Text`, а жирность, масштаб, локаль и направление берутся из одного `MediaQuery`; шрифт Inter задан явно, поэтому вид не меняется. Ширина и стиль названия берутся из `_nameWidth` и `_nameStyle` и для измерения, и для отрисовки. Тест с системным жирным шрифтом при масштабе 1,5 проверяет критерий 3.22.

Не признано замечанием переполнение строки пункта, о котором сообщил ревьюер U1. Фиксированная ширина названия 170 требует от плоскости 228 логических пикселей, а маршрут Flutter сжимает меню полями 8 и безопасными отступами экрана. Переполнение возникает только в окне уже примерно 244 dp. Такое окно лежит вне области поддержки интерфейса `app-appearance` (не уже 360 dp), а ADR-0031 прямо не гарантирует раскладку в произвольном окне большого дисплея. Поэтому этот случай не входит в обязательства изменения.

U2. `_onCompletion` смотрит только на `state.draft.tagIds` и потому действует и после отказа наблюдения. Повторное известие гасится проверкой `contains`, проверкой `tag == null` в `_onTagRead` и тем, что `withoutDeletedTags` без изменений возвращает то же состояние. Во время отправки удаление откладывается до результата на путях результата и исключения. Координатор публикует пакеты синхронно в порядке принятия и до завершения будущего инициатора, поэтому удаление, принятое до отправки, приходит, пока она выполняется. Подписка освобождается при закрытии и при освобождении сессии. Тот же приём уже применяет `IntentionTagConditionsViewModel`. Два новых теста покрывают обе проверки из 3.23.

Не выполнялись: сборка APK, `mise run codegen-check`, проверки на устройстве. На устройстве пользователю остаётся проверить: меню тега, открытое из поиска панели при открытой клавиатуре, после её скрытия остаётся у удерживаемой строки; при системном жирном и крупном шрифте меню у строки у нижнего края стоит над ней; меню следует за строкой при повороте планшета.
