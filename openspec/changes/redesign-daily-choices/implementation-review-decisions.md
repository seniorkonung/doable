# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F2 · Low — Правило повтора отказа обновления повторено в трёх местах

- **Решение:** Устранить
- **Как устранить:** Итог: решение о том, допускает ли отказ обновления повтор, принимается в одном месте. Как: в `DailyChoiceCatalogLoaded` (`lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart`) добавляется свойство `canRetryRefresh`, истинное при `refreshFailure is DailyChoiceCatalogUnavailableFailure`, по образцу `canRetry` у отказов первой загрузки и порции. Его читают три места: `Notice` в начале выдачи и подвал секции в `daily_choice_catalog_body.dart` и `retryRefresh` в `daily_choice_catalog_view_model.dart`; прямых проверок типа отказа обновления в них не остаётся. Ограничения: это рефакторинг без смены поведения, проверка `freshness == stale` в `retryRefresh` сохраняется, тексты отказов, модель выдачи, чтение и схема не меняются; новые тесты не добавляются, потому что существующие тесты каталога уже закрепляют, когда повтор предлагается, и проходят без изменения ожиданий. Новая задача добавляется в конец Фазы 1 после всех существующих задач с номером 1.<следующий свободный>. Ожидаемые артефакты: `openspec/changes/redesign-daily-choices/tasks.md`, `daily_choice_catalog_state.dart`, `daily_choice_catalog_body.dart`, `daily_choice_catalog_view_model.dart`.
