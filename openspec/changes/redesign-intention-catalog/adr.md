# ADR Review Manifest

- Status: completed
- Review date: 2026-10-30

## Review Summary

Проверены решения [design.md](design.md) против индекса `docs/adr/README.md` и записей, которые касаются каталога, чисел, состояния корневых страниц, дизайн-системы и панели тегов.

Новая долговременная запись одна — [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md): представления каталога и поисков для выбора строятся из одного модуля поиска, а различия контекстов выражаются данными выбора параметров.

Числа по охватам и типам ADR не получили. Они продолжают действующий протокол ограниченного чтения и согласования снимками, а расширение вида подсчёта записано как часть ADR-0049. Числа типов в прошлом изменении тоже не получили отдельной записи.

Остальные решения дизайна тактические: каркас страницы, API `CatalogRow`, отступы, тексты, перенос тестов. Принятые записи не пересматриваются. `design.md` ссылается на ADR-0049 и согласован с ней.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md) — proposed, originating change `redesign-intention-catalog`. Принадлежит этому изменению. Задаёт модуль `presentation/search/`, разбор назначения в одном месте и выбор вида подсчёта моделью.
- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Ограничение: ограниченные порции, точное количество, согласование подтверждёнными снимками на ревизии. Матрица чисел считается в первой порции и согласуется по этому протоколу.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, originating change `add-contribution-statistics`. Контекст: у корневого каталога один ключ состояния на процесс, поэтому охват, тип и порядок каталога живут в модели этого ключа.
- [ADR-0036](../../../docs/adr/0036-replace-graph-atomically-with-new-epoch-and-generation.md) — proposed, originating change `add-graph-export-import`. Контекст: после замены графа модель каталога сбрасывает параметры, включая тип, по смене поколения.
- [ADR-0045](../../../docs/adr/0045-order-titles-by-opaque-key-of-stored-search-projection.md) — proposed, originating change `add-intention-picker-sorting-and-purpose`. Контекст: порядок по названию, который теперь открыт и каталогу, использует существующий ключ и индексы.
- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Контекст: `CatalogRow` получает готовые строки, метки и обработчик без предметных типов.
- [ADR-0040](../../../docs/adr/0040-choose-and-manage-tags-in-one-context-panel.md) — proposed, originating change `add-tags-panel`. Контекст: кнопка фильтра каталога открывает ту же панель тегов в контексте фильтра.

## Additional Context

- [ADR-0005](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — accepted, заменена ADR-0009. Историческое происхождение протокола каталога.
- [ADR-0011](../../../docs/adr/0011-derive-relation-counts-from-graph-snapshots.md) — accepted. Образец: точные числа вычисляются агрегатами хранилища, а не хранимыми счётчиками.
- [ADR-0043](../../../docs/adr/0043-read-relation-counts-only-for-intention-page.md) — proposed, originating change `redesign-intention-pickers`. Сводки каталога по-прежнему не несут чисел связей.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, originating change `add-design-foundation`. Решения проекта важнее правил README дизайн-системы, поэтому API `CatalogRow` следует `PickerRow`.
- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — proposed, originating change `redesign-navigation-bar`. Лист «Показать и упорядочить» открывается над корневым навигатором.
- [ADR-0014](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — proposed, originating change `add-home-navigation-and-favorites`. Панель навигации живёт в оболочке, поэтому конец выдачи каталога — её верхний край.

## ADRs Owned by This Change

- [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md) — proposed.
