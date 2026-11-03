# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F7 · Low — Английские строки называют отметку в пакете двумя разными словами

- **Решение:** Устранить
- **Как устранить:** Исход: английские строки называют отметку намерения для новых связей тем же словом «selected», что и остальная лексика пакета. Выбранный вариант: в `lib/l10n/app_en.arb` `editorCreatedAndChosen` = «Intention created and selected.», `editorSearchSubtitle` = «Selected right away for new relations»; созданные файлы локализации обновить кодогенерацией. Ключи не переименовывать, русские строки не менять. Обновить ожидания английского текста в тестах, например `test/graph/presentation/graph_operation_presenter_test.dart`. Планирование через openspec-update-change: в критерии задачи 4.4 tasks.md заменить «Intention created and chosen.» на «Intention created and selected.» (отметку выполнения 4.4 не трогать) и добавить новую задачу в конец Phase 4 после всех существующих со следующим свободным номером 4.N; другие фазы не трогать. Проверка: `mise run codegen`, изменённые тесты, `flutter analyze`.

## F8 · Low — Сессию создания дневного выбора можно собрать без экземпляра пути её корня

- **Решение:** Устранить
- **Как устранить:** Исход: `DailyChoiceCreationFlowSession` нельзя построить без экземпляра пути её корня, и в рабочем коде нет ветки только для тестов. Выбранный подход: в `lib/src/daily_choice/presentation/daily_choice_creation_flow_session.dart` параметр `ChoicePathPageInstance` становится обязательным и ненулевым, подстановка нового экземпляра удаляется; рабочий вызов в `choice_path_page.dart` уже передаёт экземпляр корня. Тесты, полагавшиеся на подстановку (например `test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart:897` и другие найденные поиском), передают экземпляр явно. Поведение продукта не меняется. Планирование: новая задача в конец Phase 4 tasks.md после всех существующих со следующим свободным номером 4.N; другие фазы не трогать. Проверка: `mise exec --no-deps -- flutter test test/daily_choice/presentation` и `flutter analyze`.
