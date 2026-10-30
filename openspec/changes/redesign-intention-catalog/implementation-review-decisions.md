# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F3 · Low — Проверки `IntentionSearchKind` для экранов выбора повторяют существующие

- **Решение:** Устранить
- **Как устранить:** Убрать из test/intention/presentation/search/intention_search_kind_test.dart повторяющие проверки: случаи префикса ключей и называния типа для трёх экранов выбора (выбор действия, исходного намерения, участника) и тест «четыре назначения не делят префикс ключей». Оставить проверку варианта каталога (префикс intention-catalog и называние типа) и проверку текстов каталога — только они ловят регрессию, не пойманную другими тестами (префиксы экранов выбора закреплены тестами экранов, находящими элементы по ключам daily-choice-action-, daily-choice-source-, participant-picker-; называние типа — доступными названиями в test/intention/presentation/picker/intention_picker_row_test.dart). Код приложения и поведение не меняются. Оформить как новую задачу 1.11 в конце фазы 1 tasks.md после задачи 1.10, с проверкой flutter test test/intention/presentation/search и flutter analyze.
