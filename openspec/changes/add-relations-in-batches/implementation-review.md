# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 2.22 выполнена и подтверждена тестами на рассмотренной голове: панель связи стала панелью по содержимому, а `Sheet.untitled` потерял раскрытие и ручку-кнопку. Активных находок и принятых рисков нет. Фаза 2 завершена: полные проверки проходят, а ручные проверки на устройстве остаются за владельцем продукта.

## Review target

- **Baseline ref:** 9b3411067fabbad8ed9381961c8ff4ad26a9bec5
- **Base commit:** 9b3411067fabbad8ed9381961c8ff4ad26a9bec5
- **Reviewed head:** 7c03c0bba92209f9f2d5f65a03a2fd112d425641
- **Target commits:** ["313d6f88c03e3c34cdb0a4348b1ea4a6339d32f4","7c03c0bba92209f9f2d5f65a03a2fd112d425641"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/design_system/sheet_test.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Панель связи следует содержимому и не раскрывается

- **Work items:** ["2.22"]
- **Requirements and scenarios:** ["long-term-relation-management: Подробный просмотр связи в нижней панели","long-term-relation-management: Отказ действия из шапки виден без ручной прокрутки","long-term-relation-management: Повторный отказ снова виден","bottom-sheets: Размеры нижней панели","bottom-sheets: Перетаскивание нижней панели","bottom-sheets: Передача жеста между телом и панелью","bottom-sheets: Ручка нижней панели"]
- **Affected boundary:** Человек в панели связи, пользователь экранного диктора и потребители `Sheet` в модуле основ.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/sheet.dart","lib/src/long_term_relation/presentation/details/relation_details_sheet.dart","test/design_system/sheet_test.dart","test/long_term_relation/presentation/details/relation_details_sheet_test.dart"]
- **Applicable constraints and non-goals:** Поведение `Sheet` и `Sheet.expandable` не меняется, строки есть на двух языках, а созданные файлы локализации соответствуют ARB. Компоненты остаются без предметной логики. Состав панели, её операции и тексты отказов не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный ревьюер `implementation-decision-review` (Sonnet) проверил U1 на диапазоне `9b341106…..7c03c0bb…` по девяти рабочим и тестовым путям. Покрытие полное, существенных находок нет. Ограничение: его поиск удалённых строк вернул одну строку `tasks.md:594` с критерием 2.22. Файл он не открывал, а строка лишь повторяет цель из его задания. Тесты он не запускал. |
| OpenSpec conformance | Complete | Критерии 2.22, сценарии «Отказ действия из шапки виден без ручной прокрутки» и «Повторный отказ снова виден» и требования `bottom-sheets` сверены с кодом и тестами на `7c03c0bb…`. На дереве с `HEAD` = `7c03c0bb…` без правок: `mise run check` — код 0 (`flutter analyze` без замечаний, 4020 обычных и 18 процессных тестов); `mise run codegen-check` — код 0; `mise exec --no-deps -- openspec validate add-relations-in-batches --strict` — успех, это только структурное свидетельство. Дерево после проверок чистое. Устройство и эмулятор не использовались. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем рабочим путям на `7c03c0bb…`. Вне правок учтены `_SheetMotion` и `_SheetBodyPosition` в `sheet.dart` и `_revealFailure` в `relation_details_sheet.dart`. Новых зависимостей, границ доверия и неограниченных чтений в диапазоне нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Оба коммита диапазона разобраны. `313d6f88…` только планирующий и добавляет профили задач фазы 2. Задача 2.22 — коммит `7c03c0bb…` (U1), неотнесённых путей нет.

Файл `sheet.dart` на голове полностью совпадает с `18357db0…`, родителем `8ca3b18f…`, и других коммитов между ними нет. Поэтому `_SheetResizing`, `origin` и `fullness` ушли, а `Sheet` и `Sheet.expandable` вернулись к прежнему коду. `sheet_test.dart` отличается от того состояния только переписанным тестом высокого содержимого, поэтому тесты `Sheet` и `Sheet.expandable` не менялись. В `lib/` и `test/` нет `relationSheetExpand` и `relationSheetCollapse`, а единственный потребитель `Sheet.untitled` — `relation_details_sheet.dart:270`.

Мутации в одноразовой копии подтвердили, что тесты ловят откат. Без вызова `_revealFailure` при новом отказе падают оба теста сценариев. Предел 534 в первой раскладке `_RenderUntitledFrame` роняет переписанный тест «лист без заголовка, содержимое которого выросло выше экрана».

Ревьюер отметил, что прямого теста на закрытие и на запрет подъёма у листа без полосы нет. Находкой это не считается. Закрытие после снятия полосы проверяет `sheet_test.dart:2090`, а запрет подъёма — общий механизм `_SheetMotion` с `expansion: null`, который закреплён тестами листа по содержимому в `sheet_test.dart:1413` и `:1711`.

Доводка раскрытия в `didUpdateWidget` ушла вместе с раскрытием: движения вверх у листа больше нет. Обрыв перетаскивания вниз появлением полосы диапазон не менял: доводка и раньше не трогала анимацию маршрута. Этот случай требует активации поля с аппаратной клавиатуры во время жеста за ручку, поэтому находкой он не считается.

Задачи 2.17 и 2.18 остаются выполненными как история: их раскрытие снял 2.22, а спецификации, design и plan на голове описывают панель по содержимому. Прошлый отчёт не содержал находок и принятых рисков, поэтому переносить нечего. Код и планирующие артефакты в этом этапе не менялись. На устройстве вручную остаётся проверить высоту панели, закрытие жестом и изменение описания над клавиатурой.
