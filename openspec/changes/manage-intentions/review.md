# OpenSpec Change Review: manage-intentions

## Оценка

**Результат:** Существенных замечаний нет

Текущие артефакты задают связную модель полного жизненного цикла намерения и ограниченного каталога: три охвата, буквальный фильтр по названию, точное количество совпадений, четыре временных порядка, keyset pagination и автоматическую подгрузку. Ресурсные границы прослеживаются от specs до repository и widget verification. External-content FTS теперь имеет явный hidden-rowid contract: `VACUUM` и иные нетранзакционные rowid-rewriting paths запрещены, table rebuild сохраняет rowids либо атомарно перестраивает индекс, а его реальная согласованность доказывается `integrity-check` с `rank = 1` и отрицательной fixture, а не делегируемым content-чтением.

**Валидация:** `openspec validate manage-intentions --type change --strict --no-interactive` прошла; OpenSpec видит все 5 из 5 schema-артефактов, 26 требований и 120 сценариев в двух delta specs. Структурная валидация не запускает будущие Drift generation/runtime, migration, negative FTS, file-backed и repository tests, не проверяет выполнение sealed page/count и Android host contracts в коде. Эти обязательства однозначно зафиксированы в design и pending-задачах, но соответствующая реализация ещё не написана и этим review не проверялась.

## Замечания

Существенных замечаний в проверенных артефактах change и релевантном контексте репозитория не найдено.

## Покрытие ревью

Проверены полный граф артефактов `proposal → specs/design → adr → tasks`, обе delta specs, schema `intent-driven`, предметный язык и пять repository-level ADR с supersession ADR-0001 → ADR-0005. Повторно прослежены capability boundaries, lifecycle точного count, sealed page contract, application/storage boundary, Drift build-time и runtime FTS5 contracts, hidden-rowid lifecycle, index-aware negative verification, migration rollback и file-backed reopening. Также проверены architecture/public interface, data/migrations, reliability/concurrency, security, performance, observability, UX и delivery применительно к change. Apply, implementation code и состояние checklist не изменялись.
