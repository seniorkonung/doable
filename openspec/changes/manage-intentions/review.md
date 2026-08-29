# OpenSpec Change Review: manage-intentions

## Оценка

**Результат:** Требуются изменения

Текущие артефакты задают связную модель ограниченного каталога: три охвата, буквальный фильтр по названию, точное количество совпадений, четыре временных порядка, keyset pagination и автоматическую подгрузку. Ресурсные границы catalog query теперь согласованы от пользовательского поведения до contract, adapter и widget tests: `pageSize` ограничен диапазоном 1–100, фильтр — 255 расширенными графемными кластерами с локализованной validation failure до storage query, sealed first/continuation pages допускают ровно один точный `COUNT` на последовательный проход query, а build-time и runtime обязательства FTS5 разделены и проверяются независимо. Однако доказательство согласованности external-content index по-прежнему задано небезопасно.

**Валидация:** `openspec validate manage-intentions --type change --strict --no-interactive` прошла; OpenSpec видит все 5 из 5 schema-артефактов, 26 требований и 120 сценариев в двух delta specs. Структурная валидация не запускает будущие Drift generation/runtime tests, не проверяет выполнение sealed page contract и ровно одного `COUNT` в коде, содержимое FTS-индекса или будущую реализацию Android host contract `root/app_flutter/doable.sqlite`; последняя однозначно зафиксирована в design и pending-задачах, но production connection ещё отсутствует. Код задачи 2.2 после отката отсутствует, поэтому реализация нового repository contract не проверялась.

## Замечания

### Medium — Проверка external-content FTS может подтвердить основную таблицу, не проверив индекс

- **Доказательства:** [design.md](design.md) связывает external-content FTS с hidden `rowid` таблицы `intentions` и предлагает сравнивать количество и содержимое индексируемых записей с основной таблицей; [tasks.md](tasks.md) требует FTS consistency, но не задаёт index-aware отрицательную проверку. SQLite поясняет, что обычное чтение external-content FTS без `MATCH` делегируется основной таблице и не зависит от содержимого индекса, поэтому такое сравнение может пройти при пустом или рассогласованном индексе; для сопоставления индекса с external content предусмотрен `integrity-check` с `rank = 1` ([официальная документация FTS5](https://www.sqlite.org/fts5.html#external_content_table_pitfalls)). Дополнительно `intentions` имеет `TEXT PRIMARY KEY`, поэтому используемый hidden rowid не является устойчивой идентичностью: SQLite допускает его изменение при `VACUUM` ([документация rowid tables](https://www.sqlite.org/rowidtable.html)), а design описывает будущие перестроения таблиц.
- **Влияние:** Ошибка triggers, backfill или rowid-rewriting migration может пройти заявленную проверку, после чего буквальный фильтр и его точный count будут молча пропускать записи либо возвращать ложные совпадения при целой основной таблице.
- **Требуемое изменение:** Зафиксировать проверку, которая действительно падает при намеренно рассогласованном FTS-индексе, и выполнять её после создания, backfill, rollback, повторного открытия и каждой затрагивающей индекс миграции. Одновременно определить устойчивый integer `content_rowid` либо обязательную атомарную пересборку индекса после любой операции, способной изменить hidden rowids.
- **Требуется решение:** Добавлять стабильный внутренний integer key для связи с FTS или сохранять hidden rowid с формальным запретом/обработкой rowid-rewriting операций? Выбор влияет на долговечную schema version 1 и будущие миграции.

## Покрытие ревью

Проверены полный граф артефактов `proposal → specs/design → adr → tasks`, обе delta specs, schema `intent-driven`, предметный язык и пять repository-level ADR с supersession ADR-0001 → ADR-0005. Для затронутых ресурсных границ повторно прослежены lifecycle точного count, sealed page contract, application/storage boundary, Drift 2.34.5 build-time configuration, runtime FTS5 evidence, command reconciliation и multi-page verification; также сохранено покрытие architecture/public interface, data/migrations, reliability/concurrency, security, performance, observability, UX и delivery применительно к модели каталога. Apply, implementation code и состояние checklist не изменялись.
