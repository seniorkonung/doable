## Phase 1: Ручка листа — неизменная линия без отклика на касание

- [x] 1.1 Ручка раскрываемого листа — одна и та же линия в компактном и полном размере, при перетаскивании и смене размера
  - **Acceptance criteria:**
    - `_SizeIcon` удалён; кнопка ручки рисует только `_Grip` на прежнем месте, и шеврон не появляется ни в каком размере и положении листа (design, решение 1)
    - Нажатие ручки раскрывает и сворачивает лист, подписи и состояние раскрытия у диктора прежние; сценарии «Нажатие ручки раскрывает панель без подсветки» в части облика, «Шапка не меняется при сворачивании панели с пустым списком» и «Экранный диктор сворачивает панель „Резервные копии“» выполняются
    - Проверки `sheet_test.dart` и `backups_sheet_test.dart`, которые ждали шеврон, проверяют ту же линию ручки в обоих размерах; в названиях проверок и переменных шеврона нет
  - **Verification:**
    - `flutter test test/design_system/sheet_test.dart test/data_transfer/presentation/backups_sheet_test.dart test/tag/presentation/panel/tags_panel_test.dart`
  - **Dependencies:** None
  - **Files likely touched:** `lib/src/design_system/components/sheet.dart`, `test/design_system/sheet_test.dart`, `test/data_transfer/presentation/backups_sheet_test.dart`
  - **Estimated scope:** S

- [ ] 1.2 Касание и нажатие ручки раскрываемого листа ничего не подсвечивают, а рамка вокруг ручки видна только при фокусе с аппаратной клавиатуры
  - **Acceptance criteria:**
    - `InkWell` заменён связкой `FocusableActionDetector`, `Semantics` и `GestureDetector` по образцу `CalendarHandle` (design, решение 2); касание принимает вся прежняя область 88×44
    - Пока палец удерживается на ручке, пиксели шапки не меняются; после нажатия лист меняет размер, как прежде
    - Фокус с клавиатуры рисует рамку только вокруг линии ручки, не заходя на заголовок, а `Enter` или пробел меняют размер листа; без фокуса рамки нет
  - **Verification:**
    - `flutter test test/design_system/sheet_test.dart`
  - **Dependencies:** 1.1
  - **Files likely touched:** `lib/src/design_system/components/sheet.dart`, `test/design_system/sheet_test.dart`
  - **Estimated scope:** S

- [ ] 1.3 В наборе значков дизайн-системы нет шеврона сворачивания, а вписывание графики в квадрат `size` остаётся
  - **Acceptance criteria:**
    - Значение `DoableIconData.chevronDown`, файл `chevron_down.svg` и его строка в описании значков удалены; вписывание графики в `DoableIcon` не меняется (design, решение 3)
    - Проверка неквадратной графики удалена вместе с шевроном, эталонное изображение набора значков обновлено и отличается только отсутствием шеврона
  - **Verification:**
    - `flutter test --update-goldens test/design_system/doable_icon_test.dart`, затем просмотр разницы эталона и `flutter test test/design_system/doable_icon_test.dart`
    - `rg -n "chevronDown|chevron_down" lib test` ничего не находит
  - **Dependencies:** 1.1
  - **Files likely touched:** `lib/src/design_system/doable_icon.dart`, `lib/src/design_system/icons/assets/chevron_down.svg`, `lib/src/design_system/icons/README.md`, `test/design_system/doable_icon_test.dart`, `test/design_system/goldens/doable_icons.png`
  - **Estimated scope:** S

- [ ] 1.4 Изменённые требования `bottom-sheets` выполнены, проверки листа и набора значков проходят, общие проверки проекта проходят
  - **Acceptance criteria:**
    - Условие Ready to advance фазы 1 из `plan.md` выполнено
    - Изменение проходит строгую проверку OpenSpec
  - **Verification:**
    - `mise run check`
    - `openspec validate keep-sheet-grip-static --strict`
  - **Dependencies:** 1.1, 1.2, 1.3
  - **Files likely touched:** None (verification only)
  - **Estimated scope:** XS
