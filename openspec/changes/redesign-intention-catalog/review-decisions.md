# Решения по findings OpenSpec review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F2 · Low — Проверки 2.1, 2.3 и 2.4 пропускают прямых потребителей модели и `answerCatalogQuery`

- **Решение:** Устранить
- **Как устранить:** Выбран вариант A: точечное добавление трёх файлов. Исход: проверки задач 2.1, 2.3 и 2.4 запускают прямых потребителей `answerCatalogQuery` и модели, поэтому их поломка обнаруживается в своей задаче, а не в 2.6. Изменить только tasks.md: в команду `flutter test` каждой из задач 2.1, 2.3 и 2.4 добавить файлы `test/long_term_relation/presentation/editor/relation_editor_page_test.dart`, `test/long_term_relation/presentation/editor/relation_creation_navigation_test.dart` и `test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart`. Каталоги `test/long_term_relation/presentation/editor` и `test/daily_choice/presentation/catalog` целиком не добавлять: второй состоит в основном из тестов календаря, не связанных с этими изменениями. Остальные команды, критерии приёмки и порядок задач не менять, новых задач не добавлять, plan.md, design и спецификации не менять. Поведение приложения не меняется.
