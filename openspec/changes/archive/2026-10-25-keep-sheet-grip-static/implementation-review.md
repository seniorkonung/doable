# OpenSpec Implementation Review: keep-sheet-grip-static

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Ручка раскрываемого листа на каждом срабатывании (касание, `Enter`, пробел, действие диктора) вызывает `Feedback.forTap` и затем меняет размер, без визуального отклика; подписи, состояние раскрытия и жесты листа не изменены. Принятых рисков нет.

## Review target

- **Baseline ref:** 474559ec257aeaa8bfc4845336afbabb34824569
- **Base commit:** 474559ec257aeaa8bfc4845336afbabb34824569
- **Reviewed head:** 596ea908ee8eb9a46bbbc63588f204e0947a659d
- **Target commits:** ["d344447f703ca4a53c13670736dfe471728226a5", "596ea908ee8eb9a46bbbc63588f204e0947a659d"]
- **Reviewable paths:** ["lib/src/design_system/components/sheet.dart", "openspec/changes/keep-sheet-grip-static/tasks.md", "test/design_system/sheet_test.dart"]
- **OpenSpec change:** keep-sheet-grip-static
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/keep-sheet-grip-static/tasks.md"]

## Reviewed increment

### U1 · Системный отклик касания у ручки раскрываемого листа без подсветки

- **Work items:** ["1.5", "1.6"]
- **Requirements and scenarios:** ["bottom-sheets: Ручка нижней панели", "bottom-sheets: Нажатие ручки раскрывает панель без подсветки", "bottom-sheets: Экранный диктор сворачивает панель «Резервные копии»", "design: решение 2"]
- **Affected boundary:** Пользователь (палец, аппаратная клавиатура, экранный диктор) и компонент `Sheet` дизайн-системы
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "test/design_system/sheet_test.dart"]
- **Applicable constraints and non-goals:** Касание и нажатие не подсвечивают ручку и шапку; рамка только при фокусе с клавиатуры; объявление диктора прежнее; ручка распознаёт только нажатие и не мешает перетаскиванию. Модель положения, жесты, размеры, раскладка шапки и ручка листа по содержимому не меняются.
- **Excluded change scope:** Задачи 1.1–1.4 (облик ручки, замена `InkWell`, удаление `chevronDown`) выполнены до базового коммита и в этот диапазон не входят.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент по `implementation-decision-review` с нейтральным брифом и путями `lib/src/design_system/components/sheet.dart`, `test/design_system/sheet_test.dart` на 474559ec..596ea908: существенных замечаний нет, покрытие полное |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate keep-sheet-grip-static --strict --json` — valid, 0 issues; `mise run check` в рабочем дереве на 596ea908ee8eb9a46bbbc63588f204e0947a659d (чистое дерево, HEAD совпадает с проверяемой головой) — проходит |
| Code quality | Complete | Пять линз `code-review-and-quality` по `_SizeButtonState` и новой проверке в `sheet_test.dart`, включая соседнюю проверку пикселей шапки при удержании пальца |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

В `lib/src/design_system/components/sheet.dart:1219-1224` метод `_activate` вызывает `Feedback.forTap` и затем `widget.onTap`; все три пути срабатывания (`GestureDetector.onTap`, `CallbackAction` для `ActivateIntent` и `ButtonActivateIntent`, `Semantics.onTap`) идут через него, каждое срабатывание даёт ровно один отклик. Это повторяет поведение `InkWell` с `enableFeedback`, который был до задачи 1.2. Визуального отклика `Feedback.forTap` не даёт; рамка фокуса и семантика не изменены.

Новая проверка `test/design_system/sheet_test.dart:509-551` показывает, что на Android касание, `Enter`, пробел и действие диктора дают четыре `SystemSoundType.click` и меняют размер листа. Проверка `test/design_system/sheet_test.dart:455` (пиксели шапки при удержании пальца не меняются) идёт на платформе тестов по умолчанию — Android — и потому уже покрывает второй критерий задачи 1.5 с включённым звуком.

Звук касания не закреплён в требованиях `bottom-sheets` намеренно: это общий механизм кнопок, который не описан ни в одной спецификации проекта, а решение о нём записано в proposal и design, решение 2.

Задача 1.6 — проверочная: строгая проверка OpenSpec и `mise run check` прошли на проверяемой голове. Проверки на устройстве (реальный звук и TalkBack) пользователь выполняет сам; здесь они не выполнялись.
