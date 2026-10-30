# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F2 · Low — Проверка доступности берёт ожидаемое название поля из проверяемой семантики

- **Решение:** Устранить
- **Как устранить:** Итог: проверка доступности берёт ожидаемое название поля названия каталога из источника, не зависящего от проверяемой семантики, а смена подписи поля меняет только общий файл шагов; поведение приложения не меняется. Выбранный вариант: добавить в конец Phase 3 файла tasks.md новую задачу 3.9 (после всех существующих задач, включая 3.8) с критериями приёмки и проверкой и выполнить её. В test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart локальная titleFieldName, чтение семантики через EditableText, expect(titleFieldName, isNotEmpty) и поясняющий их комментарий удаляются, а containsAll в _traversal сравнивает с intentionCatalogTitleFieldLabel(tester). Там же, в tasks.md, предложение критерия задачи 3.4 о том, что intention_creation_sheet_accessibility_test.dart берёт название поля из семантики intentionCatalogTitleField, заменяется на чтение подписи шагом intentionCatalogTitleFieldLabel; отметка выполнения 3.4 остаётся, номера задач не меняются. Ограничения: lib/ не меняется, новых шагов и сценариев нет, строка catalogFilterLabel в этом тесте напрямую не появляется, поэтому поиск из задачи 3.7 остаётся чистым. Проверка задачи: flutter test для test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart и flutter analyze через mise exec --no-deps. Ожидаемые артефакты: tasks.md (критерий 3.4 и новая задача 3.9), test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart.
