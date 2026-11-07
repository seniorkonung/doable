# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F15 · Low — после удаления тестов в тесте контроллера быстрого создания остался псевдоним исхода

- **Решение:** Устранить
- **Как устранить:** Устранить упрощением теста, без изменения проверки и кода lib/. Добавить в конец Фазы 1 tasks.md (после задач по F13 и F14) новую задачу со следующим свободным номером 1.N через openspec-update-change; затем реализовать её. Результат: в test/app/quick_creation/quick_creation_mode_controller_test.dart тест «исход … после освобождения не обращается к состоянию» задаёт исход отказа QuickCreationModeSaveFailed(DiagnosticsFailureCode.unavailable) напрямую (без пары констант `failed` и `outcome = failed`), а его название содержит «отказ» обычным текстом (например «исход «отказ» после освобождения не обращается к состоянию»); функция `_outcomeName` удалена, если у неё не осталось других потребителей. Проверки теста (ожидание isA<QuickCreationModeSaveFailed>() и _acceptedModes(store) == [QuickCreationMode.intention]) не меняются. Проверка задачи: mise exec --no-deps -- flutter test test/app/quick_creation/quick_creation_mode_controller_test.dart; mise exec --no-deps -- flutter analyze test. Ожидаемые изменяемые артефакты: openspec/changes/introduce-actions-and-intention-kinds/tasks.md, test/app/quick_creation/quick_creation_mode_controller_test.dart.
