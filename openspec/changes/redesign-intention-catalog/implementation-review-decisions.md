# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F2 · Low — Загрузка и отказы экрана выбора возвращаются к началу пружиной от прежнего смещения

- **Решение:** Устранить
- **Как устранить:** Сделать так, чтобы пауза ввода (IntentionCatalogDebouncing), загрузка и отказы первой порции (Unavailable, Corruption, Unexpected, а также AsyncValue loading/error) в общей выдаче IntentionSearchList показывались сверху сразу, без пружинной анимации прокрутки от смещения прежней выдачи. Выбранный вариант: ответственность у ResultsScrollKeeper (lib/src/intention/presentation/search/results_scroll_keeper.dart), который владеет прокруткой: в onCatalogChanged при переходе модели к состоянию, где вместо строк показывается состояние, он мгновенно (jumpTo(0), без анимации) переводит список наверх и сбрасывает отложенный якорь; прокрутка остаётся одной для всех состояний (единый CustomScrollView с контроллером хранителя сохраняется, отдельный ListView для состояний не возвращать). Удержание видимой строки при согласовании выдачи того же запроса, начало новой выдачи сверху и поведение прежней выдачи каталога не меняются. Добавить в test/intention/presentation/search/intention_search_list_test.dart проверку: выдача прокручена вниз, модель переходит к паузе ввода или загрузке и к отказу первой порции, и уже в первом кадре после перехода смещение равно 0 и состояние стоит сверху. Оформить как новую задачу 1.10 в конце фазы 1 tasks.md после задачи 1.9 (F1 правит те же файлы и выполняется раньше), с проверкой flutter test test/intention/presentation/search test/intention/presentation/picker test/intention/presentation/catalog/intention_search_results_test.dart и flutter analyze.

## F3 · Low — Проверки `IntentionSearchKind` для экранов выбора повторяют существующие

- **Решение:** Устранить
- **Как устранить:** Убрать из test/intention/presentation/search/intention_search_kind_test.dart повторяющие проверки: случаи префикса ключей и называния типа для трёх экранов выбора (выбор действия, исходного намерения, участника) и тест «четыре назначения не делят префикс ключей». Оставить проверку варианта каталога (префикс intention-catalog и называние типа) и проверку текстов каталога — только они ловят регрессию, не пойманную другими тестами (префиксы экранов выбора закреплены тестами экранов, находящими элементы по ключам daily-choice-action-, daily-choice-source-, participant-picker-; называние типа — доступными названиями в test/intention/presentation/picker/intention_picker_row_test.dart). Код приложения и поведение не меняются. Оформить как новую задачу 1.11 в конце фазы 1 tasks.md после задачи 1.10, с проверкой flutter test test/intention/presentation/search и flutter analyze.
