# Architecture Decision Records

| ADR | Краткое решение | Статус | Заменён |
| --- | --- | --- | --- |
| [0001 — Сосредоточить управление намерениями в глубоком модуле](0001-deep-intention-management-module.md) | Скрыть предметные правила и storage adapter за `IntentionRepository`. | accepted | [0005](0005-use-bounded-catalog-snapshots.md) |
| [0002 — Хранить локальный граф в SQLite через Drift](0002-use-drift-sqlite-for-local-graph.md) | Использовать Drift/SQLite и обязательные connection-owner boundaries для настройки каждого соединения. | accepted | — |
| [0003 — Использовать отдельные типы UUID-идентификаторов предметных сущностей](0003-use-typed-uuid-identifiers-for-domain-entities.md) | Разделить идентификаторы сущностей непрозрачными UUID-типами независимо от версии UUID. | accepted | — |
| [0004 — Хранить текущий граф во внутреннем хранилище Android](0004-keep-personal-graph-device-local.md) | Хранить граф в app-specific storage, исключить backup/transfer и ограничить release APK точным allowlist разрешений. | accepted | — |
| [0005 — Читать каталог намерений ограниченными снимками](0005-use-bounded-catalog-snapshots.md) | Разделить read/query и command paths и согласовать их эфемерной process-local revision за единственной storage-neutral repository seam. | accepted | Предложена замена: [0009](0009-unify-personal-graph-module-and-revision.md) |
| [0006 — Считать timestamps с часов устройства наблюдениями, а не причинным порядком](0006-treat-device-clock-timestamps-as-observations.md) | Не выводить причинный порядок из wall-clock timestamps устройства. | accepted | — |
| [0007 — Ограничить пользовательский текст графа корректным Unicode без NUL](0007-restrict-graph-user-text-to-unicode-without-nul.md) | Принимать пользовательский текст только как корректные Unicode scalar values без `U+0000`. | accepted | — |
| [0008 — Считать SQLite schema-functions долговечным контрактом](0008-treat-sqlite-schema-functions-as-durable-contract.md) | Регистрировать используемые схемой функции на каждом физическом SQLite-соединении через его owner boundary. | accepted | — |
| [0009 — Объединить управление личным графом и согласование его снимков](0009-unify-personal-graph-module-and-revision.md) | Расширить единственную границу до `PersonalGraphRepository`, с общим coordinator, ревизией и ограниченными снимками намерений и связей; предложить замену ADR-0005. | proposed | — |
| [0010 — Хранить порядок создания долговременных связей отдельно от идентичности](0010-persist-long-term-relation-creation-order.md) | Сохранять неизменяемую последовательность через SQLite AUTOINCREMENT отдельно от UUID, часов и ревизии графа. | proposed | — |
| [0011 — Вычислять счётчики связей из согласованных снимков графа](0011-derive-relation-counts-from-graph-snapshots.md) | Получать точные агрегаты из связей на общей ревизии без независимо сохраняемых счётчиков и материализации списков в приложении. | proposed | — |

ADR-0009–ADR-0011 принадлежат активному изменению `manage-long-term-relations` и остаются `proposed` до его архивации. Предложенная ADR-0009 замена не меняет статус принятого ADR-0005; целевой контракт этого изменения учитывает её явно.
