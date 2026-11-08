# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F3 · Low — В тестах остались пустые строки на месте удалённого аргумента `mainsLosingRelation:`

- **Решение:** Устранить
- **Как устранить:** Устранить прямо в сессии решения finding по особому разрешению пользователя: сессия сама правит тесты и коммитит исправление, не добавляя задач в tasks.md и не меняя plan.md. Итог: в списках аргументов конструкторов составов каскада (ArchiveCascadeComposition, DeleteCascadeComposition и т. п.) в тестах нет пустых строк, оставшихся от удалённого аргумента `mainsLosingRelation:`. Известные места на ed4d2350: test/graph/presentation/graph_operation_presenter_test.dart:71, :93, :272, :348; test/intention/presentation/details/intention_details_options_test.dart:40, :46, :85, :124, :309; test/intention/presentation/details/intention_options_test.dart:43; test/long_term_relation/presentation/details/relation_details_sheet_test.dart:1015, :1021; test/support/intention_cascade_execution.dart:150. Перед правкой перепроверить их поиском по этим файлам, потому что номера строк могли сдвинуться. Удалить только эти пустые строки; ожидания и логику тестов не менять, код приложения не трогать. Проверка: `dart format` не меняет файлы; `mise exec --no-deps -- flutter test` для пяти изменённых файлов проходит. Commit type: style(test) или test(cascade).
