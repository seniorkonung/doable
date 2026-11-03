# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 4.22–4.25 выполнены по своим критериям, `mise run check` и `mise run codegen-check` проходят. Активна одна находка F13 (Low): ни один тест не ловит, если удержание начала выдачи в `ResultsScrollKeeper` перестанет сниматься после перестройки списка. Принятых рисков нет.

## Review target

- **Baseline ref:** 5494b67b8e57106e49094bb4f78b78808e9b9709
- **Base commit:** 5494b67b8e57106e49094bb4f78b78808e9b9709
- **Reviewed head:** f8aebaf5634b60df6c5073c4b4c53bebf8351a4f
- **Target commits:** ["15edb8938b1c8827b908e77b6b28915d80a14884","94ca900050bc9144765ebe2c426c0294fa9d1a7f","d5215821562018db4102670ac85f7f20c043590a","22addecd8445dbbba79a39310f97744b905c3ba3","f8aebaf5634b60df6c5073c4b4c53bebf8351a4f"]
- **Reviewable paths:** ["lib/src/intention/presentation/editor/intention_editor_page.dart","lib/src/intention/presentation/editor/intention_editor_view_model.dart","lib/src/intention/presentation/editor/intention_editor_view_model.g.dart","lib/src/intention/presentation/search/results_scroll_keeper.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/intention/presentation/search/intention_search_list_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Созданный файл провайдера редактора соответствует исходнику

- **Work items:** ["4.22"]
- **Requirements and scenarios:** ["plan: Phase 4 «Ready to advance» — полные проверки проекта проходят"]
- **Affected boundary:** Разработчики и проверка кодогенерации в CI.
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_editor_view_model.g.dart"]
- **Applicable constraints and non-goals:** Созданные файлы приходят только из `mise run codegen` и не правятся вручную. Исходники, тесты и поведение продукта не меняются.

### U2 · Описания правила закрытия сессии создания согласованы с поведением

- **Work items:** ["4.24"]
- **Requirements and scenarios:** ["intention-management: Уход во время сохранения непоправленного названия требует подтверждения"]
- **Affected boundary:** Разработчики, читающие код панели создания намерения.
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_editor_view_model.dart","lib/src/intention/presentation/editor/intention_editor_page.dart","lib/src/intention/presentation/editor/intention_editor_view_model.g.dart"]
- **Applicable constraints and non-goals:** Меняются только комментарии на русском. Код, тесты и поведение не меняются, новых тестов нет.

### U3 · Строка «Создать» остаётся видна в начале выдачи после нескольких изменений до перестройки

- **Work items:** ["4.23"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника","long-term-relation-management: Точное совпадение убирает строку создания","intention-management: Сохранение состояния загруженного каталога","long-term-relation-management: Причина занятой пары в поиске участника (исключение со сбросом позиции)"]
- **Affected boundary:** Человек, прокручивающий выдачу поиска участника.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** В остальных случаях якорь по видимой строке работает как прежде, лишних `jumpTo` нет. Тесты без замеров времени, фикстура минимальна, названия на русском.

### U4 · Поиск участника открывает панель создания по фактическому стеку навигации

- **Work items:** ["4.25"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника","long-term-relation-management: Намерение из подстроки сразу отмечено"]
- **Affected boundary:** Человек в поиске участника и корневой стек навигации auto_route.
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart"]
- **Applicable constraints and non-goals:** Пока панель открыта, второй панели нет. Пока идёт добавление, панель не открывается. После любого снятия панели создание снова доступно. Страница панели создания не меняется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные ревьюеры `implementation-decision-review` проверяли `5494b67b…..f8aebaf5…` и получали только нейтральный бриф и пути своей группы. U1 и U2 делят `intention_editor_view_model.g.dart`, поэтому шли одной группой с объединёнными путями (Sonnet, medium): находок нет, `mise run codegen-check` прошёл на чистом дереве. U3 — отдельно (Sonnet, high): одна находка, она записана как F13. U4 — отдельно (Opus, high): находок нет. Этот ревьюер разобрал auto_route 11.1.0: страница попадает в `_pages` в микрозадаче после нажатия, но до следующего пакета событий указателя. Его допущение, что панель снимает себя через маршрутизатор, подтверждено в координаторе: `intention_editor_page.dart` на голове использует `router.removeRoute` (строки 434 и 471). |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве с `HEAD` = `f8aebaf5634b60df6c5073c4b4c53bebf8351a4f` без правок. `mise run check` — код 0: анализ без замечаний, 4018 и 18 тестов прошли. `mise run codegen-check` — код 0, дерево после него чистое. `mise exec --no-deps -- openspec validate add-relations-in-batches --strict --json` — успех; это только структурное свидетельство. Критерии приёмки 4.22–4.25 сверены с диффом. Для 4.25 тест на повторное нажатие уже был: `relation_batch_picker_page_test.dart:279-307` нажимает плюс и сразу вызывает `onCreate` без кадра. Регрессионный тест 4.17 (`:310-345`) не изменён. Тест 4.23 воспроизводит два изменения подряд без кадра, тесты 4.19 и «появление и уход строки…» сохранены. Коммит `15edb893` добавляет только профили задач 4.22–4.25. Устройство и эмулятор не использовались. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем рабочим путям на `f8aebaf5…`. Вне правок как контекст учтены `intention_search_list.dart`, `app_router.dart`, `requestClose` и `_CloseConfirmationDialog`, а также `push`, `_canNavigate`, `_addNewPage` и `_removeRoute` из auto_route 11.1.0. Новых зависимостей и границ доверия нет. Для F13 выполнена мутация: без строки `_holdsStart = false` (`results_scroll_keeper.dart:252`) прошли все 316 тестов `test/intention/presentation/search/`, `test/intention/presentation/catalog/` и `test/long_term_relation/presentation/batch_picker/`. Затем файл возвращён к закоммиченному. |

## Findings

### F13 · Low — Снятие удержания начала выдачи не защищено тестом

- **Evidence:** `results_scroll_keeper.dart:92` ставит `_holdsStart`, когда над выдачей появляется строка «Создать», а список стоит в начале. Снимает флаг только послекадровое обслуживание (`:252`). Пока флаг стоит, `:95` не даёт захватить якорь видимой строки. Новый тест (`intention_search_list_test.dart:667-702`) и тест 4.19 (`:640-665`) заканчиваются сразу после перестройки. Ни один тест не проверяет, что после показа «Создать» в начале и перестройки следующее подтверждённое изменение снова сохраняет положение видимой строки. Мутация подтвердила пробел: без строки `:252` все 316 тестов поиска, каталога и поиска участника проходят.
- **Evidence revisions:** ["f8aebaf5634b60df6c5073c4b4c53bebf8351a4f"]
- **Impact:** Сброс флага живёт в общем колбэке, который также ведёт приближение к якорю и чистку ключей. Если при правке колбэка сброс потеряется, проверки останутся зелёными. Тогда после первого появления «Создать» в начале выдачи поиск участника перестанет сохранять положение видимой строки при всех следующих подтверждённых изменениях. Это нарушает требование «Сохранение состояния загруженного каталога» из `intention-management`.
- **Required outcome:** Регрессионный тест доказывает, что удержание начала заканчивается с перестройкой списка. После того как «Создать» показана в начале и список перестроен, следующее подтверждённое изменение выдачи сохраняет экранное положение видимой строки. Тест падает, если сброс удержания убран.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["tasks.md: 4.23","test/intention/presentation/search/intention_search_list_test.dart"]

## Review coverage

Изучены все пути диапазона на `f8aebaf5…`. Хранитель прокрутки: установка и снятие `_holdsStart`, смена запроса и `_jumpToTop`, состояния-статусы, ожидающий якорь, `dispose`, ранний возврат `onListBuilt`. Поиск участника: проверка `canEdit` и стека над `matchId` поиска, поздний `onCreated` после ухода, порядок добавления страницы в стек auto_route относительно событий указателя, снятие панели через `removeRoute` и `onPopPage`. Комментарии правила закрытия сверены с `requestClose` и диалогом подтверждения. Созданный файл провайдера сверен через `codegen-check`. Требования «Создание намерения из поиска участника», «Сохранение состояния загруженного каталога» и «Компактная панель создания намерения» прочитаны на голове.
