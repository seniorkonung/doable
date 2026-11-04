# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F8 · Low — Формат часов выбирается в двух местах, хотя комментарий и критерий 4.18 называют одно

- **Решение:** Устранить
- **Как устранить:** Вариант А. Итог: формат часов (12 или 24) для циферблата и всех подписей времени дневных выборов решается в одном месте — `dailyChoiceUsesTwelveHourClock` в `lib/src/daily_choice/presentation/details/daily_choice_field_labels.dart`, и её комментарий об единственном месте становится правдой. Правило: `dailyChoiceTimeValue` форматирует время с форматом из `dailyChoiceUsesTwelveHourClock` (например, `MaterialLocalizations.of(context).formatTimeOfDay(time, alwaysUse24HourFormat: !dailyChoiceUsesTwelveHourClock(context))`), а не решает его сам через `TimeOfDay.format(context)`; комментарии обеих функций описывают это устройство. Ограничения: видимый вывод не меняется (ru при выключенном 24-часовом времени «18:00» и 24-часовой циферблат, en «6:00 PM» и 12-часовой, en с включённым 24-часовым временем — 24-часовой); «Весь день», подписи половин суток, `backup_descriptions.dart`, `TimeDial` и лист времени не меняются; существующие тесты совпадения формата в `daily_choice_time_sheet_test.dart` и `daily_choice_sheet_test.dart` остаются зелёными без ослабления; новый тест — только если они не ловят расхождение циферблата и подписей. Новая задача 4.23 в конце Phase 4 `tasks.md` (после 4.22), зависимость 4.18, проверка `mise exec --no-deps -- flutter test test/daily_choice/presentation/details test/daily_choice/presentation/catalog`; в задаче указать, что она заменяет критерий 4.18 о `dailyChoiceTimeValue` через `TimeOfDay.format`; 4.18 не переписывать. Меняются: `tasks.md`, `daily_choice_field_labels.dart`.
