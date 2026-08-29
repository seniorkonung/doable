# Манифест проверки ADR

- Status: completed
- Review date: 2026-08-30

## Результат проверки

Повторная проверка ADR для change `manage-intentions` завершена после уточнения каталога намерений. ADR-0001–ADR-0004 перечитаны, а их supersession graph пересмотрен после принятия ADR-0005.

Ограниченный `getCatalogPage` является долговечным изменением repository contract: принятый ADR-0005 полностью supersedes ADR-0001, сохраняет границу глубокого модуля и заменяет наблюдение всего каталога ограниченными страничными snapshot-запросами. FTS5 trigram остаётся внутренним мигрируемым индексом уже выбранного Drift/SQLite adapter из ADR-0002, а идентичность из ADR-0003 и политика локального Android storage из ADR-0004 не меняются.

## Рассмотренные действующие ADR

- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать UUID v4 для идентичности намерений](../../../docs/adr/0003-use-uuid-v4-for-domain-identities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md)

## Superseded ADR, рассмотренные как исторический контекст

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md) — superseded ADR-0005.

## Созданные этим change долговечные ADR

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md)
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать UUID v4 для идентичности намерений](../../../docs/adr/0003-use-uuid-v4-for-domain-identities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — supersedes ADR-0001.

Прежние принятые ADR не изменялись. ADR-0001 остаётся неизменяемым историческим документом и больше не входит в действующий набор решений.
