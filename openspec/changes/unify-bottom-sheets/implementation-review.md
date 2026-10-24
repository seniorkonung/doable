# OpenSpec Implementation Review: unify-bottom-sheets

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 1.9 фазы 1 выполнена. Комментарий у суммы сдвигов листа `_distance` теперь описывает и сдвиги до принятия жеста. После принятия лист без скачка переходит к другому пальцу, а до принятия первое обновление несёт сумму сдвигов всех пальцев на листе. Это совпадает с решением 1 design и с исходниками Flutter 3.47.1. Код и поведение листа не изменились: в диапазоне поменялись только строки комментария. Активных замечаний нет. Принятый остаточный риск AR1 остаётся в силе: два пальца на элементе, который соперничает за касание, до принятия жеста один раз сдвигают лист и на движение второго пальца. Отчёт не одобряет push, merge или архивирование.

## Review target

- **Baseline ref:** 2945b1381fc06bb2a37fcfdb23b91a827a692590
- **Base commit:** 2945b1381fc06bb2a37fcfdb23b91a827a692590
- **Reviewed head:** 7a2522fcec9dd5b068da0f99adcb8fb2fc0289b7
- **Target commits:** ["7a2522fcec9dd5b068da0f99adcb8fb2fc0289b7"]
- **Reviewable paths:** ["lib/src/design_system/components/sheet.dart", "openspec/changes/unify-bottom-sheets/tasks.md"]
- **OpenSpec change:** unify-bottom-sheets
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/unify-bottom-sheets/tasks.md"]

## Reviewed increment

### U1 · Комментарий у суммы сдвигов листа верно описывает поведение при нескольких пальцах

- **Work items:** ["1.9"]
- **Requirements and scenarios:** ["design: решение 1 — после принятия жеста лист без скачка переходит к другому пальцу, до принятия первое обновление несёт сумму сдвигов всех пальцев", "accepted risk: AR1"]
- **Affected boundary:** Разработчики, которые сопровождают лист дизайн-системы.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart"]
- **Applicable constraints and non-goals:** Меняется только комментарий; код и поведение листа остаются прежними. Комментарии в коде пишутся по-русски. Само поведение при нескольких пальцах не меняется (AR1).

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент по `implementation-decision-review` проверил диапазон `2945b138..7a2522fc` с одним путём `lib/src/design_system/components/sheet.dart`. Он сверил текст комментария с `packages/flutter/lib/src/gestures/monodrag.dart`, `widgets/gesture_detector.dart` и `widgets/scroll_configuration.dart` Flutter 3.47.1. Замечаний нет. Рецензент не получал артефакты планирования, историю коммитов и отчёты. |
| OpenSpec conformance | Complete | `git diff 2945b138 7a2522fc -- lib`: изменены только строки `///` у `_distance` (`sheet.dart:230-240`). `mise exec --no-deps -- flutter analyze lib/src/design_system/components/sheet.dart`: без замечаний. `mise exec --no-deps -- openspec validate unify-bottom-sheets --strict --json`: valid, ошибок нет. `mise run check` в рабочей копии на `7a2522fc` (HEAD совпадает с проверенной головой, код не изменён): код 0 — формат без изменений (792 файла), `flutter analyze` без замечаний, тесты `+3290`, тесты процессов `+18`; фаза 1 этим закрыта по проверкам. Критерии приёмки 1.9 сверены с текстом комментария и решением 1 design. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены к `sheet.dart` на `7a2522fc`. Комментарий сверен с кодом: `_startDrag`, `_updateDrag` (`sheet.dart:261-290`) и `DragStartBehavior.down` (`sheet.dart:331`). Ссылка на `MultitouchDragStrategy.latestPointer` относится к фразе о поведении после принятия. Влияния на безопасность и производительность нет. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · До принятия жеста лист сдвигается и на движение второго пальца

- **Evidence:** `lib/src/design_system/components/sheet.dart:241, 261-290` ставит лист в `_drag.offset - _distance`, где `_distance` — сумма `details.delta.dy` всех обновлений жеста. Распознаватель настроен с `DragStartBehavior.down` (`sheet.dart:331`). В Flutter 3.47.1 (`packages/flutter/lib/src/gestures/monodrag.dart`) до принятия жеста `_activePointer == null`, поэтому движения любого пальца складываются в `_pendingDragOffset`, и `_checkDrag` отдаёт эту сумму первым `onUpdate`. Жест принимается не сразу, когда за касание соперничает другой элемент листа: `Button.primary`, `SearchField`, ручка или действие шапки, как в `lib/src/tag/presentation/panel/tags_panel.dart`. Одноразовая проверка при разборе F1, на коде листа, который с тех пор не менялся: два пальца на «Готово» прошли вниз по 60 пикселей, а лист сместился на 69,8. Комментарий у `_distance` (`sheet.dart:230-240`) теперь описывает это поведение. Изолированный рецензент подтвердил накопление по исходникам Flutter на `7a2522fc`.
- **Evidence revisions:** ["7a2522fcec9dd5b068da0f99adcb8fb2fc0289b7"]
- **Potential impact:** Если два пальца касаются кнопки, поля или ручки листа и двигаются до принятия жеста, лист один раз уходит от отслеживаемого пальца на движение второго пальца, и расхождение остаётся до конца жеста. Около порога половины высоты оно может решить, закроется лист после отпускания или останется.
- **Acceptance rationale:** Случай редкий: нужно касание двумя пальцами элемента, который соперничает за касание. Расхождение однократное, и при движении в одну сторону оно не больше допуска касания. Так же ведут себя стандартные перетаскивания Flutter, например списки приложения. Чтобы это исправить, положение листа пришлось бы вести в обход стандартного накопления распознавателя со своим учётом касаний. Это усложнило бы `_SheetMotionState` и добавило бы риск ошибок при смене пальца. Решение 1 design описывает это поведение и отвергнутую альтернативу, а комментарий у `_distance` после задачи 1.9 ему соответствует.
- **Scope and assumptions:** Только сдвиг до принятия жеста при нескольких пальцах на листе с распознавателем `DragStartBehavior.down`, стратегией `MultitouchDragStrategy.latestPointer` и накоплением сдвигов распознавателя Flutter 3.47.1. После принятия жеста лист без скачка переходит к другому пальцу. Приложение работает только на Android.
- **Reopen when:** Расхождение растёт заметно больше допуска касания, например при встречном движении пальцев на устройстве. Лист закрывается или остаётся вопреки положению пальца в обычном использовании. Меняется стратегия многопальцевого ввода или накопление сдвигов во Flutter. Появляется платформа со стратегией `averageBoundaryPointers`.
- **Acceptance authority:** Явное решение пользователя 2026-10-25 при разборе F1: «Принять риск, поправить текст».
- **Originating finding:** F1
- **Acceptance lifetime:** Change-scoped
- **Decision record:** openspec/changes/unify-bottom-sheets/design.md, решение 1

## Review coverage

Единственный целевой коммит `7a2522fc` относится к задаче 1.9 (U1). Отметка выполнения 1.9 в `tasks.md` подтверждена поставкой диапазона. Оба изменённых пути отнесены к единице или к планированию; несвязанной работы в диапазоне нет. На проверенной голове прочитаны решение 1 design, задачи фазы 1 в tasks и текущий отчёт; рабочее дерево чистое. Все задачи фазы 1 (1.1–1.9) выполнены. Фазы 2 и 3 (передача жеста от тела, раскрываемые резервные копии) не считались обязательствами диапазона.

Комментарий прочитан в контексте `_SheetMotionState`. Он утверждает два разных поведения. После принятия жеста стратегия `latestPointer` ведёт отслеживаемый палец без скачка. До принятия общая сумма сдвигов приходит первым обновлением, потому что выбран `DragStartBehavior.down`. Если распознаватель на арене один, он принимает жест уже при касании, и до движения общей суммы ещё нет. Поэтому комментарий верно ограничивает расхождение случаем, когда за касание соперничает другой элемент листа. Поведение iOS и macOS (`averageBoundaryPointers`) не рассматривалось: у приложения есть только платформа Android. Данные, миграции, конфигурация и внешние зависимости изменение не затрагивает.

Проверки на устройстве не выполнялись и остаются за пользователем: поведение при перетаскивании двумя пальцами, чтение шапки панели тегов настоящим TalkBack и перетаскивание за поле поиска и кнопку «Готово».
