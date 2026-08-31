# Манифест проверки ADR

- Status: completed
- Review date: 2026-08-31

## Результат проверки

Повторная проверка ADR для change `manage-intentions` завершена после уточнения границы идентичности. ADR-0001–ADR-0005 перечитаны, а их supersession graph пересмотрен.

Ограниченный `getCatalogPage` остаётся долговечным repository contract из ADR-0005, который полностью supersedes ADR-0001. FTS5 trigram остаётся внутренним мигрируемым индексом Drift/SQLite adapter из ADR-0002, а политика локального Android storage из ADR-0004 не меняется.

Действующий ADR-0003 фиксирует общую политику отдельных типизированных UUID-идентификаторов предметных сущностей; `IntentionId` является её первым применением. Новые идентификаторы генерируются как UUID v7, но версия generator остаётся сменной implementation policy и не требует отдельного ADR.

## Рассмотренные действующие ADR

- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md)

## Superseded ADR, рассмотренные как исторический контекст

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md) — superseded ADR-0005.

## Созданные этим change долговечные ADR

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md)
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — supersedes ADR-0001.

ADR-0001 остаётся историческим документом и больше не входит в действующий набор решений. Новых долговечных ADR по итогам повторной проверки не создано.
