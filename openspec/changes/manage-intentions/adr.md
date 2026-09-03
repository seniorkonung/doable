# Манифест проверки ADR

- Status: completed
- Review date: 2026-09-03

## Результат проверки

Повторная проверка ADR для change `manage-intentions` завершена после уточнения границ идентичности и времени клиентского устройства. ADR-0001–ADR-0005 перечитаны, их supersession graph пересмотрен, а политика timestamp закреплена новым ADR-0006.

Ограниченный `getCatalogPage` остаётся долговечным repository contract из ADR-0005, который полностью supersedes ADR-0001. FTS5 trigram остаётся внутренним мигрируемым индексом Drift/SQLite adapter из ADR-0002, а политика локального Android storage из ADR-0004 не меняется.

Действующий ADR-0003 фиксирует общую политику отдельных типизированных UUID-идентификаторов предметных сущностей; `IntentionId` является её первым применением. Новые идентификаторы генерируются как UUID v7, но версия generator остаётся сменной implementation policy и не требует отдельного ADR.

Действующий ADR-0006 фиксирует общую политику timestamps, источником которых являются системные часы клиентского устройства. `createdAt` и `updatedAt` намерения являются её первым применением: их корректные UTC-значения не образуют инвариант взаимного порядка и не используются как revision или causal clock.

## Рассмотренные действующие ADR

- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md)
- [ADR-0006: Считать timestamps с часов устройства наблюдениями, а не причинным порядком](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md)

## Superseded ADR, рассмотренные как исторический контекст

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md) — superseded ADR-0005.

## Созданные этим change долговечные ADR

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md)
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — supersedes ADR-0001.
- [ADR-0006: Считать timestamps с часов устройства наблюдениями, а не причинным порядком](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md)

ADR-0001 остаётся историческим документом и больше не входит в действующий набор решений. ADR-0006 распространяет доказанную для намерений семантику времени клиентского устройства на будущие сущности, не предрешая отдельный причинный механизм для синхронизации или хронологически значимого поведения.
