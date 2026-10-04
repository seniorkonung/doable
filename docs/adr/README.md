# Architecture Decision Records

| ADR | Краткое решение | Статус | Заменён |
| --- | --- | --- | --- |
| [0001 — Сосредоточить управление намерениями в глубоком модуле](0001-deep-intention-management-module.md) | Скрыть предметные правила и storage adapter за `IntentionRepository`. | accepted | [0005](0005-use-bounded-catalog-snapshots.md) |
| [0002 — Хранить локальный граф в SQLite через Drift](0002-use-drift-sqlite-for-local-graph.md) | Использовать Drift/SQLite и обязательные connection-owner boundaries для настройки каждого соединения. | accepted | — |
| [0003 — Использовать отдельные типы UUID-идентификаторов предметных сущностей](0003-use-typed-uuid-identifiers-for-domain-entities.md) | Разделить идентификаторы сущностей непрозрачными UUID-типами независимо от версии UUID. | accepted | — |
| [0004 — Хранить текущий граф во внутреннем хранилище Android](0004-keep-personal-graph-device-local.md) | Хранить граф в app-specific storage, исключить backup/transfer и ограничить release APK точным allowlist разрешений. | accepted | — |
| [0005 — Читать каталог намерений ограниченными снимками](0005-use-bounded-catalog-snapshots.md) | Разделить read/query и command paths и согласовать их эфемерной process-local revision за единственной storage-neutral repository seam. | accepted | [0009](0009-unify-personal-graph-module-and-revision.md) |
| [0006 — Считать timestamps с часов устройства наблюдениями, а не причинным порядком](0006-treat-device-clock-timestamps-as-observations.md) | Не выводить причинный порядок из wall-clock timestamps устройства. | accepted | — |
| [0007 — Ограничить пользовательский текст графа корректным Unicode без NUL](0007-restrict-graph-user-text-to-unicode-without-nul.md) | Принимать пользовательский текст только как корректные Unicode scalar values без `U+0000`. | accepted | — |
| [0008 — Считать SQLite schema-functions долговечным контрактом](0008-treat-sqlite-schema-functions-as-durable-contract.md) | Регистрировать используемые схемой функции на каждом физическом SQLite-соединении через его owner boundary. | accepted | — |
| [0009 — Объединить управление личным графом и согласование его снимков](0009-unify-personal-graph-module-and-revision.md) | Расширить единственную границу до `PersonalGraphRepository`, согласовывать ограниченные снимки общей ревизией и атомарно обновлять сводку с открытой группой; заменить ADR-0005. | accepted | — |
| [0010 — Хранить порядок создания долговременных связей отдельно от идентичности](0010-persist-long-term-relation-creation-order.md) | Сохранять неизменяемую последовательность через SQLite AUTOINCREMENT отдельно от UUID, часов и ревизии графа. | accepted | — |
| [0011 — Вычислять счётчики связей из согласованных снимков графа](0011-derive-relation-counts-from-graph-snapshots.md) | Получать точные агрегаты из связей на общей ревизии без независимо сохраняемых счётчиков и материализации списков в приложении. | accepted | — |
| [0012 — Централизовать предъявление результатов операций графа](0012-centralize-graph-operation-result-presentation.md) | Подтверждать и освобождать claims через общие владельцы точных поверхностей инлайн-сообщения и `SnackBar`. | accepted | — |
| [0013 — Читать списки тегов полными согласованными снимками](0013-load-complete-tag-snapshots.md) | Получать каталог и назначения целиком на общей ревизии; сохранять порции помеченных сущностей. | accepted | — |
| [0014 — Вести основную навигацию оболочкой корневых страниц над общим стеком](0014-host-primary-navigation-in-root-page-shell.md) | Держать пункты панели дочерними маршрутами оболочки без собственных стеков и без `Scaffold` оболочки; остальные страницы открывать поверх. | proposed | — |
| [0015 — Вести ручной порядок избранных намерений явными местами целого списка](0015-keep-favorite-order-as-explicit-whole-list-places.md) | Хранить отметку строкой отдельной таблицы с уникальным целым местом; читать и переписывать порядок целиком. | proposed | — |
| [0016 — Предъявлять только отказ операции, успех которой виден в согласованных данных](0016-present-only-failure-for-self-evident-success.md) | Задавать политику предъявления видом операции в координаторе: успех без права предъявления, отказ сразу общей поверхности. | proposed | — |
| [0017 — Вести модальные сессии создания в общем корневом стеке](0017-manage-modal-creation-sessions-in-root-stack.md) | Сохранять одну сессию при изменении размера и переходах в теги; все способы ухода согласовывать до освобождения черновика. | proposed | — |
| [0018 — Отделить контекст выбора тегов от постоянных назначений](0018-separate-tag-selection-context-from-persistence.md) | Передавать общему компоненту типизированный контекст действия; набор черновика хранить в сессии, назначения — за границей графа. | proposed | — |

ADR-0009–ADR-0012 приняты при архивации изменения `manage-long-term-relations`, ADR-0013 — при архивации `stabilize-tag-selection`. Принятая ADR-0009 заменяет ADR-0005 в области управления личным графом.

ADR-0014–ADR-0016 принадлежат изменению `add-home-navigation-and-favorites`, уже находящемуся в архиве. В самих записях статус остаётся `proposed`; индекс отражает его без предположения о принятии. Их финализация относится к исходному изменению и не выполняется изменением `compact-intention-creation`.

ADR-0017–ADR-0018 принадлежат активному изменению `compact-intention-creation` и остаются `proposed` и редактируемыми до его архивации.
