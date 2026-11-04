# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F6 · Low — Тест подтверждения создания проверяет отказ по полю даты, которого система не порождает

- **Решение:** Устранить
- **Как устранить:** Вариант A (узкий). В конец Фазы 4 в tasks.md добавить новую задачу 4.<следующий свободный номер> (после всех существующих задач). Итог: из `test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart` удаляется тест «отказ по полю даты показан уведомлением отказа страницы», который подставляет `DailyChoiceValidationFailure(DailyChoiceValidationField.date)`: ни команда, ни репозиторий такой отказ не порождают, а общий путь уведомления отказа покрыт остальными тестами страницы. Из критерия приёмки задачи 4.11 через openspec-update-change убирается фраза «Отказ команды по полю даты показывается уведомлением отказа страницы, как прочие отказы.». Производственный код, значение `DailyChoiceValidationField.date`, строка `dailyChoiceDateInvalid`, тесты модели создания и презентера не меняются: удаление недостижимого типа `DailyChoiceValidationFailure` целиком существовало до этого изменения и при необходимости делается отдельным изменением. Ожидаемые файлы: `daily_choice_creation_page_test.dart`, tasks.md. Проверка: `mise exec --no-deps -- flutter test test/daily_choice/presentation/editor`.
