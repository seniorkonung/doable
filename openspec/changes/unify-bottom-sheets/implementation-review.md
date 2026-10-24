# OpenSpec Implementation Review: unify-bottom-sheets

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Фаза 1 в основном реализует единую модель движения листов: лист по содержимому и панель тегов идут за пальцем на подклассе `ModalBottomSheetRoute`, отпускание выбирает цель по таблице решения 2 design, закрытие маршрута во время жеста, отмена жеста, отсутствие места для роста и уменьшение движения обработаны и проверены, а шеврон рисуется 28×10. `mise run check` на проверенной голове падает на прежней проверке общего узла шапки панели тегов; раздельное чтение шапки диктором выбрано намеренно и записано в design (решение 5), а исправление проверки и повторная полная проверка фазы отданы задаче 1.6. Многопальцевый ввод уводил лист на расстояние между пальцами; ведение суммой сдвигов отслеживаемого пальца записано в design (решение 1) и отдано задаче 1.7. Перетаскивание за нижнюю кнопку и закреплённое поле и нажатие кнопки после малого сдвига не защищены проверками (F3). Принятых остаточных рисков нет. Отчёт не одобряет push, merge или архивирование.

## Review target

- **Baseline ref:** 3bb9dc7c522b406007ec8974d7f3116d9cbef968
- **Base commit:** 3bb9dc7c522b406007ec8974d7f3116d9cbef968
- **Reviewed head:** e2ea99fcad4fa5e85667eaa28faff005d3a81e33
- **Target commits:** ["4b1c9e0bd8188878bd36ee22cbdab5f55327cd7a", "3d7dd57453130382cd334eb4151fbd9e5567e023", "539aadf4647a63cee9617e38dae0689d01d14ac2", "0c0b63183ccdfe8529fc395cff4ea2606616ea0d", "e2ea99fcad4fa5e85667eaa28faff005d3a81e33"]
- **Reviewable paths:** ["lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/data_transfer/presentation/backups_sheet.dart", "lib/src/data_transfer/presentation/export_data_sheet.dart", "lib/src/design_system/components/action_sheet.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_icon.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/tag/presentation/editor/tag_sheet.dart", "lib/src/tag/presentation/panel/tags_panel.dart", "openspec/changes/unify-bottom-sheets/tasks.md", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/sheet_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart", "test/tag/presentation/panel/tags_panel_test.dart"]
- **OpenSpec change:** unify-bottom-sheets
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/unify-bottom-sheets/tasks.md"]

## Reviewed increment

### U1 · Неквадратная графика `DoableIcon` рисуется в своих пропорциях

- **Work items:** ["1.1"]
- **Requirements and scenarios:** ["app-appearance: Иконки из дизайна", "proposal: размер шеврона полного размера 28×10"]
- **Affected boundary:** Пользователь, который видит значки дизайн-системы; все вызовы `DoableIcon` в `lib/`.
- **Implementation target:** ["lib/src/design_system/doable_icon.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png"]
- **Applicable constraints and non-goals:** Значки соответствуют графике и размерам дизайна; вызывающие по-прежнему раскладывают значок квадратом `size`; графика и набор значков не меняются; новых зависимостей нет.

### U2 · Лист по содержимому идёт за пальцем на собственном маршруте и доводится по положению и скорости

- **Work items:** ["1.2"]
- **Requirements and scenarios:** ["bottom-sheets: Размеры нижней панели", "bottom-sheets: Перетаскивание нижней панели", "bottom-sheets: Перетаскивание нижней панели / Закрытие уводит панель вместе с кнопкой", "bottom-sheets: Перетаскивание нижней панели / Короткий быстрый бросок закрывает панель", "bottom-sheets: Ручка и шеврон нижней панели", "bottom-sheets: Закрытие нижней панели", "bottom-sheets: Закрытие нижней панели / «Назад» во время перетаскивания закрывает только панель", "bottom-sheets: Нижняя панель при уменьшении движения"]
- **Affected boundary:** Пользователь, который тянет, бросает и закрывает пять листов по содержимому и `ActionSheet`; модальный маршрут Material в корневом навигаторе.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "test/design_system/sheet_test.dart"]
- **Applicable constraints and non-goals:** Затемнение, «назад», фокус и семантика маршрута остаются у Material (ADR-0032, ADR-0044); пороги закрытия 700 пикселей в секунду и половины высоты сохраняют нынешнее ощущение; движение 180 мс `easeOut` без пружин; содержимое и тексты листов не меняются.
- **Excluded change scope:** Передача жеста от прокручиваемого тела (фаза 2) и раскрываемая панель «Резервные копии» (фаза 3).

### U3 · Оба варианта листа показывает одна функция с одним типом возможности

- **Work items:** ["1.3"]
- **Requirements and scenarios:** ["design: решение 4 — одна функция показа и `SheetPresentation`", "bottom-sheets: Размеры нижней панели — общее поведение для нынешних и будущих панелей"]
- **Affected boundary:** API модуля основ для шести листов-потребителей, `ActionSheet`, описание `GraphOperationPresenter` и вспомогательные листы проверок.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "lib/src/design_system/components/action_sheet.dart", "lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart", "lib/src/app/quick_creation/quick_creation_mode_menu.dart", "lib/src/data_transfer/presentation/backups_sheet.dart", "lib/src/data_transfer/presentation/export_data_sheet.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/tag/presentation/editor/tag_sheet.dart", "lib/src/tag/presentation/panel/tags_panel.dart", "test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Поведение и содержимое потребителей не меняются; сообщения общей поверхности над листами с `hostsMessages` остаются по ADR-0042; панель создания намерения не затрагивается.

### U4 · Панель тегов идёт за пальцем между полным, компактным и закрытым состоянием

- **Work items:** ["1.4"]
- **Requirements and scenarios:** ["bottom-sheets: Перетаскивание нижней панели", "bottom-sheets: Перетаскивание нижней панели / Раскрытие следует за пальцем, а кнопка стоит на месте", "bottom-sheets: Перетаскивание нижней панели / Бросок вниз из полного размера сворачивает панель", "bottom-sheets: Ручка и шеврон нижней панели", "bottom-sheets: Закрытие нижней панели / «Назад» закрывает раскрытую панель", "bottom-sheets: Нижняя панель при уменьшении движения / Раскрытие нажатием без анимации", "tag-management: Панель тегов", "tag-management: Панель тегов / Закрытие панели сохраняет применённые изменения", "tag-management: Панель тегов / Поиск не меняет высоту компактной панели"]
- **Affected boundary:** Пользователь и экранный диктор в панели тегов; раскрываемый вариант `Sheet.expandable`.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "test/design_system/sheet_test.dart", "test/tag/presentation/panel/tags_panel_test.dart"]
- **Applicable constraints and non-goals:** Предел компактной высоты 534, но не больше доступного места; без места для роста жест не меняет размер; ручка и шеврон — кнопки с подписями и состоянием раскрытия; затемнение, «назад», фокус и семантика маршрута остаются у Material.
- **Excluded change scope:** Передача жеста между телом и панелью (фаза 2): тело в этой фазе прокручивается как прежде.

### U5 · Готовность фазы 1

- **Work items:** ["1.5"]
- **Requirements and scenarios:** ["plan: Phase 1 / Ready to advance"]
- **Affected boundary:** Все существующие листы модуля основ и полные проверки репозитория.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "test/design_system/sheet_test.dart", "test/tag/presentation/panel/tags_panel_test.dart"]
- **Applicable constraints and non-goals:** Готовность подтверждается `mise run check` и `openspec validate unify-bottom-sheets --strict`; проверки на устройстве остаются за пользователем.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных рецензента по `implementation-decision-review` на диапазоне `3bb9dc7c..e2ea99fc`: U1 — отдельно с путями `doable_icon.dart`, `doable_icon_test.dart`, `doable_icons.png` (замечаний нет, эталон сравнен попиксельно: изменилась только строка шеврона); U2–U5 — одна группа пересечения по `sheet.dart` с объединением двенадцати путей доставки и проверок (два замечания: многопальцевый сдвиг отдан задаче 1.7, отсутствие проверок перетаскивания за нижнюю кнопку и поле вошло в F3). Рецензенты не получали артефакты планирования, историю коммитов и отчёты. |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate unify-bottom-sheets --strict --json` — valid, ошибок нет. `mise run check` в рабочей копии на `e2ea99fc` (HEAD совпадает с проверенной головой, дерево чистое): формат и `flutter analyze` без замечаний, тесты `+3283 -1`, код 1 — падает `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart:233` (исправление отдано задаче 1.6). Тот же тест отдельно: падает на `e2ea99fc` и `0c0b6318`, проходит на `539aadf4` и `3bb9dc7c` (одноразовая рабочая копия `/tmp/unify-base-wt`). Требования и сценарии U1–U5 сверены с тестами `sheet_test.dart`, `tags_panel_test.dart`, `doable_icon_test.dart`. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем путям доставки на `e2ea99fc`: модель положения и обратная функция кривой, выбор цели, отмена жеста и закрытие маршрута во время жеста, путь без места для роста, уменьшение движения, семантика ручки и шеврона, отступ клавиатуры в высоте пути, `hostsMessages`, механическая замена типа у потребителей. Распознаватели поля поиска сверены с исходником Flutter 3.47.1 (`text_selection.dart`), многопальцевый сдвиг — с `gestures/monodrag.dart`. |

## Findings

### F3 · Low — Перетаскивание за нижнюю кнопку и закреплённое поле не защищено проверками

- **Evidence:** Все перетаскивания в `test/design_system/sheet_test.dart` начинаются на тексте шапки: `_header` (`find.text('Выберите сколько нужно')`) у раскрываемого листа и `'Новый тег'` у листа по содержимому. Закреплённая часть и нижняя часть тестового раскрываемого листа — не поле ввода и не кнопка. `tags_panel_test.dart` тянет только за шапку и только нажимает «Готово». Требование «Перетаскивание нижней панели» разрешает тянуть за шапку, закреплённые поле и кнопку, а design (решение 3) — и за пустые места; кнопка получает нажатие, если движение не превысило допуска. Сейчас это работает, потому что `GestureDetector` в `_SheetMotion` охватывает всю поверхность (`sheet.dart:314-329`), а `TextField` на Android и iOS распознаёт только горизонтальное перетаскивание (`packages/flutter/lib/src/widgets/text_selection.dart:3719-3741`); рецензент подтвердил это одноразовым тестом.
- **Evidence revisions:** ["e2ea99fcad4fa5e85667eaa28faff005d3a81e33"]
- **Impact:** Фаза 2 перестраивает источники жеста вокруг тела листа. Перенос распознавателя или замена закреплённой части виджетом с собственным вертикальным жестом незаметно вернёт перетаскивание только за шапку или отнимет нажатие у «Готово», и ни одна проверка этого не поймает.
- **Required outcome:** Автоматическая проверка показывает, что вертикальное перетаскивание, начатое на нижней кнопке и на настоящем закреплённом поле ввода, двигает лист, а нажатие нижней кнопки с движением в пределах допуска срабатывает.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["openspec/changes/unify-bottom-sheets/tasks.md", "test/design_system/sheet_test.dart"]

## Review coverage

Каждый из пяти целевых коммитов отнесён к своей задаче: `4b1c9e0b` — 1.1 (U1), `3d7dd574` — 1.2 (U2), `539aadf4` — 1.3 (U3), `0c0b6318` — 1.4 (U4), `e2ea99fc` — 1.5 (U5, только отметка в `tasks.md`). Все шестнадцать изменённых путей отнесены к единицам или к планированию; несвязанной работы в диапазоне нет. Прочитаны proposal, delta-спецификации `bottom-sheets`, `tag-management` и `graph-backups`, design, манифест ADR и ADR-0044, plan и tasks на проверенной голове; рабочее дерево чистое. Требования о передаче жеста от тела и о раскрываемых резервных копиях отнесены к фазам 2 и 3 и не считались обязательствами этого диапазона.

Файл `sheet.dart` прочитан целиком на голове и сверен с базой. Проверены: обратная функция `easeOut` (32 шага деления пополам, концы пути ставятся точно) и её соответствие кривой, которой модальная панель Material ставит лист; разделение положения на сдвиг маршрута и раскрытие без разрыва при смене направления; таблица целей отпускания, включая бросок вниз из полного размера и путь без места для роста (`_growth == 0`); отмена жеста системой и проверка `isCurrent` перед записью значения маршрута и `Navigator.pop`; нулевые длительности маршрута и раскрытия при уменьшении движения; учёт отступа клавиатуры в высоте пути; семантика ручки и шеврона и декоративная ручка листа по содержимому; замена типа возможности у шести потребителей, `ActionSheet` и вспомогательных листов проверок. Безопасность, данные, миграции, конфигурация и внешние зависимости изменение не затрагивает.

Рецензент группы U2–U5 оставил открытым вопрос: маршрут, открытый поверх листа во время перетаскивания, оставил бы лист в промежуточном положении из-за возврата по `isCurrent` в `_endDrag` (`sheet.dart:280`). В нынешней системе путь к этому не найден: касания листа занимает активный жест, а асинхронного открытия маршрутов поверх открытых листов нет. Поэтому это не замечание. Проверки на устройстве — следование за пальцем, плавность доводки, длительность открытия меню и поведение двумя пальцами — не выполнялись и остаются за пользователем.
