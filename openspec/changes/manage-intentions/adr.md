# Манифест проверки ADR

- Status: completed
- Review date: 2026-09-03

## Результат проверки

Повторная проверка ADR для change `manage-intentions` завершена после уточнения границ идентичности, времени клиентского устройства, пользовательского Unicode-текста и application-defined SQLite-функций. ADR-0001–ADR-0006 перечитаны, их supersession graph пересмотрен, а новые общие контракты закреплены ADR-0007 и ADR-0008.

Ограниченный `getCatalogPage` остаётся долговечным repository contract из ADR-0005, который полностью supersedes ADR-0001. FTS5 trigram остаётся внутренним мигрируемым индексом Drift/SQLite adapter из ADR-0002, а политика локального Android storage из ADR-0004 не меняется.

Действующий ADR-0003 фиксирует общую политику отдельных типизированных UUID-идентификаторов предметных сущностей; `IntentionId` является её первым применением. Новые идентификаторы генерируются как UUID v7, но версия generator остаётся сменной implementation policy и не требует отдельного ADR.

Действующий ADR-0006 фиксирует общую политику timestamps, источником которых являются системные часы клиентского устройства. `createdAt` и `updatedAt` намерения являются её первым применением: их корректные UTC-значения не образуют инвариант взаимного порядка и не используются как revision или causal clock.

Действующий ADR-0007 ограничивает пользовательский текст личного графа и буквальные поисковые фильтры корректными скалярными значениями Unicode без `U+0000`, требует отказа от malformed UTF-16 до lossy boundary и сохраняет field-specific правила поверх общей внутренней проверки. Действующий ADR-0008 делает имя, сигнатуру, регистрацию и trust boundary SQLite schema-functions долговечным контрактом для всех connection paths.

## Рассмотренные действующие ADR

- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md)
- [ADR-0006: Считать timestamps с часов устройства наблюдениями, а не причинным порядком](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md)
- [ADR-0007: Ограничить пользовательский текст графа корректным Unicode без NUL](../../../docs/adr/0007-restrict-graph-user-text-to-unicode-without-nul.md)
- [ADR-0008: Считать SQLite schema-functions долговечным контрактом](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md)

## Superseded ADR, рассмотренные как исторический контекст

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md) — superseded ADR-0005.

## Созданные этим change долговечные ADR

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md)
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — supersedes ADR-0001.
- [ADR-0006: Считать timestamps с часов устройства наблюдениями, а не причинным порядком](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md)
- [ADR-0007: Ограничить пользовательский текст графа корректным Unicode без NUL](../../../docs/adr/0007-restrict-graph-user-text-to-unicode-without-nul.md)
- [ADR-0008: Считать SQLite schema-functions долговечным контрактом](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md)

ADR-0001 остаётся историческим документом и больше не входит в действующий набор решений. ADR-0006 распространяет доказанную для намерений семантику времени клиентского устройства на будущие сущности, не предрешая отдельный причинный механизм для синхронизации или хронологически значимого поведения. ADR-0007 задаёт общую входную границу для будущих описаний, тегов, импорта и синхронизации, а ADR-0008 не позволяет следующим adapters или schema changes потерять обязательную регистрацию сохраняемой функции.
