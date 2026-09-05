# ADR-0002: Хранить локальный граф в SQLite через Drift

- Status: proposed
- Originating change: manage-intentions
- Date: 2026-08-28

## Контекст

Первый change хранит только намерения, но ближайшие change добавят направленные связи, приоритеты, нормализованные пути выбора, теги и строгие правила ссылочной целостности. Хранилище должно поддерживать атомарные операции, ограничения, реактивное чтение и проверяемые миграции. Key-value storage не соответствует будущей реляционной модели; прямой `sqflite` требует вручную поддерживать SQL mapping, уведомления об изменениях и миграционные проверки.

Сохраняемая схема зависит от обязательной настройки SQLite-соединения, включая application-defined функции из ADR-0008. Произвольный `QueryExecutor` не выражает эту обязанность, поэтому новые platform adapters и тестовые пути могут обойти её. Ответственность за допустимое соединение должна принадлежать общему модулю локального хранения и распространяться на будущие сущности графа.

## Решение

Постоянным локальным хранилищем Doable становится один версионируемый SQLite database во внутреннем app-specific storage текущего platform host, доступ к которому реализуется через Drift. `AppDatabase` и предметные interfaces не знают платформенных путей. Низкоуровневой подстановкой внутри модуля соединений остаётся `QueryExecutor`; production connection текущего Android host использует файловый native executor в background isolate, а тесты repository — in-memory или file-backed SQLite через тот же модуль.

Обычный constructor `AppDatabase` принимает только закрытый platform-neutral тип `ConfiguredLocalDatabaseConnection`, создаваемый фабриками модуля соединений. Эта capability статически гарантирует не уже состоявшееся открытие, а то, что канонический pre-open setup из ADR-0008 привязан к executor и будет выполнен для каждого создаваемого им физического SQLite-соединения до первого использования зависимой схемы. `LocalDataReady` остаётся доступным для тестов верхних слоёв и означает runtime-result успешного production bootstrap, а не неподделываемую static capability или право создать `AppDatabase`. Канонический production composition использует такой result только как возврат `LocalDataBootstrap` после фактического открытия и завершения migration; bootstrap получает фабрику capability и владеет жизненным циклом созданной базы. Произвольный `QueryExecutor` не является допустимым входом этих границ; отдельный eager-open typestate не вводится.

Когда сторонний инструмент сам создаёт внутреннее SQLite-соединение и принимает только setup callback, capability не приписывается соединению, которым Doable не владеет. Такой API закрывается специализированным adapter: он получает фактическую `AppDatabase`, созданную из `ConfiguredLocalDatabaseConnection`, и сам передаёт тот же канонический setup каждому создаваемому инструментом соединению. Schema verifier является первым таким adapter; обычные harnesses не вызывают низкоуровневый verifier с произвольным setup напрямую.

Сохранение capability при декорировании не является общей публичной операцией. Его выполняют только закрытые принадлежащие local-data module adapters для конкретного tracing или fault-injection hook: caller передаёт только наблюдателя или политику отказа, которые не принимают и не возвращают `QueryExecutor`; implementation может обернуть выбранный executor, но безусловно делегирует ему `ensureOpen` и не может заменить либо создать physical connection. Произвольный `QueryInterceptor` остаётся только в явно отделённых raw test-only fixtures ниже этой seam и не может вернуть `ConfiguredLocalDatabaseConnection`. Любой decorator, владеющий созданием physical connection, сам проходит соответствующую factory или adapter boundary.

Изменяющие предметные операции выполняются транзакционно. Для каждой версии схемы коммитятся schema snapshot и пошаговая migration, а переходы со всех поддерживаемых версий проверяются generated migration tests. При открытии включается `PRAGMA foreign_keys = ON`; ошибка открытия или migration никогда не приводит к автоматическому удалению и пересозданию пользовательской базы.

## Последствия

- Следующие сущности графа используют ту же транзакционную и миграционную основу с нативными foreign keys.
- Другой platform host сможет использовать ту же схему, миграции и `AppDatabase`, предоставив собственную production connection и platform evidence без изменения предметных interfaces.
- Каждый новый Doable-owned adapter и поддерживаемый harness создаёт `AppDatabase` через общую типизированную границу; внешний инструмент, владеющий созданием соединения, получает отдельный закрытый adapter, который применяет тот же setup. Перенос существующих callers на эти границы и замена generic interceptor extension на узкие тестовые hooks являются ценой защиты от случайного обхода настройки.
- `ConfiguredLocalDatabaseConnection` остаётся узким типом соединения внутри data layer. Общая storage interface поверх Drift и универсальный registry функций ради будущих возможностей не вводятся.
- Drift, SQLite schema и generated code становятся долговременной частью data layer; их замена потребует миграции всех пользовательских данных.
- Code generation и schema snapshots увеличивают сложность сборки, поэтому lockfile, generated artifacts и отсутствие diff после генерации проверяются в CI.
- Downgrade migrations не поддерживаются; после несовместимого изменения схемы применяется forward fix без destructive recovery.
