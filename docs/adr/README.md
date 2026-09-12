# Architecture Decision Records

| ADR | Краткое решение | Статус | Заменён |
| --- | --- | --- | --- |
| [0001 — Сосредоточить управление намерениями в глубоком модуле](0001-deep-intention-management-module.md) | Скрыть предметные правила и storage adapter за `IntentionRepository`. | accepted | [0005](0005-use-bounded-catalog-snapshots.md) |
| [0002 — Хранить локальный граф в SQLite через Drift](0002-use-drift-sqlite-for-local-graph.md) | Использовать Drift/SQLite и обязательные connection-owner boundaries для настройки каждого соединения. | accepted | — |
| [0003 — Использовать отдельные типы UUID-идентификаторов предметных сущностей](0003-use-typed-uuid-identifiers-for-domain-entities.md) | Разделить идентификаторы сущностей непрозрачными UUID-типами независимо от версии UUID. | accepted | — |
| [0004 — Хранить текущий граф во внутреннем хранилище Android](0004-keep-personal-graph-device-local.md) | Хранить граф в app-specific storage, исключить backup/transfer и ограничить release APK точным allowlist разрешений. | accepted | — |
| [0005 — Читать каталог намерений ограниченными снимками](0005-use-bounded-catalog-snapshots.md) | Разделить read/query и command paths и согласовать их эфемерной process-local revision за единственной storage-neutral repository seam. | accepted | — |
| [0006 — Считать timestamps с часов устройства наблюдениями, а не причинным порядком](0006-treat-device-clock-timestamps-as-observations.md) | Не выводить причинный порядок из wall-clock timestamps устройства. | accepted | — |
| [0007 — Ограничить пользовательский текст графа корректным Unicode без NUL](0007-restrict-graph-user-text-to-unicode-without-nul.md) | Принимать пользовательский текст только как корректные Unicode scalar values без `U+0000`. | accepted | — |
| [0008 — Считать SQLite schema-functions долговечным контрактом](0008-treat-sqlite-schema-functions-as-durable-contract.md) | Регистрировать используемые схемой функции на каждом физическом SQLite-соединении через его owner boundary. | accepted | — |
