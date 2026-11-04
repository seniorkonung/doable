# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F5 · Low — У `TimeDial` есть параметры, которые не нужны ни одному вызову

- **Решение:** Устранить
- **Как устранить:** В конец Фазы 4 в tasks.md добавить новую задачу 4.<следующий свободный номер> (после всех существующих задач; выполняется после задачи по F4, так как обе меняют `time_dial.dart`). Итог: у `TimeDial` и его частей нет параметров, которые не нужны текущему вызову. 1) У `_DialButton` построитель больше не принимает `showsFocus` (оба вызова его отбрасывали, кольцо фокуса рисует сама кнопка): параметр становится построителем без аргументов или готовым дочерним виджетом. 2) Публичный параметр `allDayHint` удаляется; доступное название кнопки «Весь день» берётся из `allDayLabel`. Доступные названия часов по-прежнему задаёт потребитель через `hourLabel`. Вызов в `lib/src/daily_choice/presentation/details/daily_choice_time_sheet.dart` перестаёт передавать `allDayHint`. Видимый текст, доступные названия, кольцо фокуса и поведение циферблата не меняются. Тесты `test/design_system/time_dial_test.dart` обновляются только там, где передавали удалённый параметр. Ожидаемые файлы: `lib/src/design_system/components/time_dial.dart`, `daily_choice_time_sheet.dart`, `test/design_system/time_dial_test.dart`, tasks.md. Проверка: `mise exec --no-deps -- flutter test test/design_system/time_dial_test.dart test/daily_choice/presentation/details`.

## F6 · Low — Тест подтверждения создания проверяет отказ по полю даты, которого система не порождает

- **Решение:** Устранить
- **Как устранить:** Вариант A (узкий). В конец Фазы 4 в tasks.md добавить новую задачу 4.<следующий свободный номер> (после всех существующих задач). Итог: из `test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart` удаляется тест «отказ по полю даты показан уведомлением отказа страницы», который подставляет `DailyChoiceValidationFailure(DailyChoiceValidationField.date)`: ни команда, ни репозиторий такой отказ не порождают, а общий путь уведомления отказа покрыт остальными тестами страницы. Из критерия приёмки задачи 4.11 через openspec-update-change убирается фраза «Отказ команды по полю даты показывается уведомлением отказа страницы, как прочие отказы.». Производственный код, значение `DailyChoiceValidationField.date`, строка `dailyChoiceDateInvalid`, тесты модели создания и презентера не меняются: удаление недостижимого типа `DailyChoiceValidationFailure` целиком существовало до этого изменения и при необходимости делается отдельным изменением. Ожидаемые файлы: `daily_choice_creation_page_test.dart`, tasks.md. Проверка: `mise exec --no-deps -- flutter test test/daily_choice/presentation/editor`.
