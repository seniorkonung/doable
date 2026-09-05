# Манифест проверки ADR

- Status: completed
- Review date: 2026-09-05

## Результат проверки

Проверка ADR для change `manage-intentions` завершена. Статус `completed` относится к проверке: все созданные этим активным change ADR имеют `Status: proposed` и `Originating change: manage-intentions`, остаются редактируемыми и получают окончательный `Status: accepted` только при архивации change. Завершение реализации или отдельной проверки не меняет этот статус.

Действующий набор решений внутри change — ADR-0002–ADR-0008. ADR-0005 через отдельное поле `Supersedes: ADR-0001` заменяет прежний repository contract в рамках этого change; ADR-0001 остаётся историческим контекстом. Эта связь сохраняется при переходе статусов во время архивации.

Ключевые ADR выделены по близости к теме change и помогают определить, каким решениям уделить внимание в первую очередь. Эта группировка не меняет принадлежность, статус или силу решений; `proposed` не отменяет выбранных человеком решений и принятых остаточных рисков внутри change. ADR-0002 и ADR-0008 согласованно различают два способа enforcement: capability для Doable-owned ленивых executors и специализированный adapter для соединений, создаваемых внешним инструментом. Только закрытые adapters local-data module сохраняют capability при tracing и fault injection; generic `QueryInterceptor` её не сохраняет. `LocalDataReady` остаётся удобным для тестов runtime-result production bootstrap, а не неподделываемым type proof; отдельный eager-open typestate не вводится. Список собственных ADR для архивации ведётся отдельно. Новых ADR при уточнении манифеста не создано.

## Ключевые ADR для этого change

Все ADR этого раздела имеют статус `proposed` и принадлежат `manage-intentions`.

- [ADR-0005](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — задаёт границу управления намерениями и модель ограниченных снимков каталога, вокруг которых строятся repository, прикладное состояние и пользовательские представления.
- [ADR-0002](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md) — определяет основу постоянного хранения намерений: Drift/SQLite, транзакции, миграции, capability для Doable-owned соединений и adapter boundary для внешнего владельца соединения.
- [ADR-0003](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md) — важен для идентичности намерения во всех операциях change и её независимости от названия, хранилища и стратегии генерации UUID.
- [ADR-0004](../../../docs/adr/0004-keep-personal-graph-device-local.md) — определяет защиту личных данных на текущем Android host и границы обещанной долговечности без неуправляемого backup/transfer.
- [ADR-0006](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md) — нужен для корректной трактовки времени создания и изменения намерений, проверки сохранённых данных и сортировки каталога.
- [ADR-0007](../../../docs/adr/0007-restrict-graph-user-text-to-unicode-without-nul.md) — связывает названия, описания и фильтр единым допустимым Unicode-repertoire на всём пути от ввода до хранения и поиска.
- [ADR-0008](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md) — важен для вычисляемого поискового ключа названия: его schema-function должна регистрироваться на каждом физическом соединении через принадлежащую соответствующему connection-owning path границу.

## Дополнительный контекст

- [ADR-0001](../../../docs/adr/0001-deep-intention-management-module.md) — статус `proposed`, принадлежит `manage-intentions`; исторический контекст выбора глубокого модуля. Заменён ADR-0005 внутри change и помогает понять переход от наблюдения всего каталога к ограниченным снимкам, но не задаёт параллельный repository contract.

## ADR, принадлежащие этому change

Все перечисленные документы имеют статус `proposed`, принадлежат `manage-intentions` и входят в набор перевода в `accepted` при архивации. Принадлежность, а не попадание в ключевые ADR или дополнительный контекст, определяет этот набор. Перечень включает исторический ADR-0001; после архивации его отношение к ADR-0005 по-прежнему определяется полем `Supersedes`.

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md) — исторический контекст, заменён ADR-0005 внутри change.
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать отдельные типы UUID-идентификаторов предметных сущностей](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md)
- [ADR-0004: Хранить текущий граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md)
- [ADR-0005: Читать каталог намерений ограниченными снимками](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — supersedes ADR-0001.
- [ADR-0006: Считать timestamps с часов устройства наблюдениями, а не причинным порядком](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md)
- [ADR-0007: Ограничить пользовательский текст графа корректным Unicode без NUL](../../../docs/adr/0007-restrict-graph-user-text-to-unicode-without-nul.md)
- [ADR-0008: Считать SQLite schema-functions долговечным контрактом](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md)
