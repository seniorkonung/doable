## Phase 1: Сборочная основа воспроизводима и соблюдает Android privacy boundary

- [x] 1.1 Подключить совместимые зависимости управления состоянием, навигации, UUID, Unicode-графем, Drift и code generation с зафиксированным lockfile
  - **Критерии приёмки:**
    - `pubspec.yaml` содержит только обоснованные design зависимости `flutter_riverpod`, `riverpod_annotation`, `auto_route`, `uuid`, `characters`, `drift`, `drift_flutter` и `flutter_localizations`, а `riverpod_generator`, `auto_route_generator`, `build_runner` и `drift_dev` находятся в dev dependencies.
    - Разрешённые версии совместимы с Flutter 3.47.1 и Dart 3.13.1, а `pubspec.lock` воспроизводимо фиксирует выбранный набор.
  - **Проверка:**
    - Выполнить `flutter pub get`.
    - Выполнить `flutter pub deps` и убедиться, что нет конфликтующих или необоснованных прямых зависимостей.
  - **Зависимости:** Нет.
  - **Вероятно затронутые файлы:** `pubspec.yaml`, `pubspec.lock`.
  - **Оценка:** S (2 файла).

- [x] 1.2 Настроить platform-neutral generated локализацию с русским, английским и явным английским fallback
  - **Критерии приёмки:**
    - `gen_l10n` использует английский template и генерирует типизированные строки для `en` и `ru`.
    - Начальный каталог строк покрывает bootstrap, навигацию, общие состояния, retryable migration failure и требование установить совместимое обновление при более новой схеме; ручного переключателя языка нет.
    - Правило разрешения системной локали одинаково для любого platform host выбирает `ru` для русского language code, `en` для английского и `en` для любого другого значения.
  - **Проверка:**
    - Выполнить `flutter gen-l10n`.
    - Выполнить сфокусированные тесты разрешения локали через `flutter test test/app/localization`.
  - **Зависимости:** 1.1.
  - **Вероятно затронутые файлы:** `l10n.yaml`, `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`, `test/app/localization/locale_resolution_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 1.3 Реализовать политику одной установки в Android host adapter: исключить SQLite-файл и его служебные файлы из cloud backup и device-to-device transfer
  - **Критерии приёмки:**
    - Android 12+ data extraction rules и Android 11- full backup rules исключают database, WAL и временные файлы внутреннего хранилища.
    - Application manifest ссылается на оба набора правил и не объявляет `INTERNET` или разрешения внешнего хранилища ради capability.
    - Конфигурация не добавляет backup agent, экспорт, перенос или синхронизацию и сохраняет данные только при перезапусках и совместимых обновлениях существующей установки.
    - Android-specific пути, permissions и backup rules не входят в предметный или прикладной modules и не пересекают interfaces `IntentionRepository`/`AppDatabase`.
  - **Проверка:**
    - Выполнить `flutter build apk --debug`.
    - Проверить manifest и оба XML-файла командой `rg -n "allowBackup|dataExtractionRules|fullBackupContent|INTERNET|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE" android/app/src/main`.
  - **Зависимости:** Нет.
  - **Вероятно затронутые файлы:** `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml`, `android/app/src/main/res/xml/backup_rules.xml`.
  - **Оценка:** M (3 файла).

- [x] 1.4 Проверить сборочную основу до добавления предметного кода
  - **Критерии приёмки:**
    - Зависимости разрешаются, локализация генерируется, Android debug APK собирается.
    - Анализатор не сообщает ошибок в обновлённом каркасе.
  - **Проверка:**
    - Выполнить `flutter gen-l10n`, `flutter analyze` и `flutter build apk --debug`.
  - **Зависимости:** 1.1, 1.2, 1.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## Phase 2: Предметный контракт управления намерениями стабилен

- [x] 2.1 Реализовать неизменяемую модель намерения, тип `IntentionId` и единую Unicode-валидацию названия и описания
  - **Критерии приёмки:**
    - Название нормализуется через `trim()`, сохраняет внутренние пробелы и принимает 1–255 расширенных графемных кластеров.
    - Полностью пробельное описание становится отсутствующим, а непустое сохраняется посимвольно при длине до 4096 расширенных графемных кластеров.
    - `IntentionId`, готовность к действию, архивное состояние и UTC timestamps имеют предметные типы и не зависят от Drift.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain` с границами 1/255/256 и 4096/4097, составными emoji, BOM, пробелами и переносами строк.
  - **Зависимости:** 1.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/domain/intention.dart`, `lib/src/intention/domain/intention_id.dart`, `lib/src/intention/domain/intention_text.dart`, `test/intention/domain/intention_text_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 2.2 Определить закрытые commands, страничные типы каталога и storage-neutral seam `IntentionRepository`
  - **Критерии приёмки:**
    - В соответствии с ADR-0005 interface сохраняет границу глубокого модуля и предоставляет только ограниченный `getCatalogPage`, реактивный `watchById` и `execute`, не раскрывает Drift/SQLite, transport или sync-specific types и не имеет unbounded-варианта каталога из superseded ADR-0001.
    - Query/page types выражают три scope, фильтр названия не длиннее 255 расширенных графемных кластеров, поле и направление порядка, page size от 1 до 100 включительно, облегчённые summaries и конец выдачи; sealed first-page variant обязательно несёт точный count, а continuation variant не допускает повторного count или nullable-представления его отсутствия. Единые storage-neutral правила membership и полного сравнения summaries служат repository и локальному согласованию command results; opaque cursor связывает query с неизменяемой boundary, остаётся допустимым после command того же query без требования существования граничной строки и отбрасывается при изменении scope/filter/order.
    - Commands и sealed results/failures исчерпывающе различают create/change/no-op/delete, validation/not-found/conflict/unavailable/corruption; только `watchById` использует typed error channel с новой подпиской для retry.
  - **Проверка:**
    - Выполнить `flutter test test/intention/application/intention_contract_test.dart` для page size 1/100 и validation failure 0/101, фильтра 255/256 расширенных графемных кластеров, sealed first/continuation page variants, обязательного count только у первой страницы, query membership/order, cursor value-boundary semantics, success/failure variants, no-op/delete payloads и `watchById` failure lifecycle.
    - Выполнить `flutter analyze` и проверить исчерпывающую обработку sealed variants.
  - **Зависимости:** 2.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/application/intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `lib/src/intention/application/intention_result.dart`, `test/intention/application/intention_contract_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 2.3 Ввести `DiagnosticsSink` с безопасными структурированными событиями и проверяемым запретом пользовательских данных
  - **Критерии приёмки:**
    - Контракт поддерживает события bootstrap/migration, страничного чтения, подробного чтения и commands с типом операции, длительностью, page size, outcome, failure code и версиями схемы там, где они применимы.
    - Production adapter не записывает фильтр, названия, описания, UUID, cursors, SQL-параметры или полные database exceptions.
    - In-memory adapter позволяет проверять диагностику без внешней telemetry.
  - **Проверка:**
    - Выполнить `flutter test test/shared/diagnostics/diagnostics_sink_test.dart` с canary-значениями пользовательского текста и UUID.
  - **Зависимости:** 2.2.
  - **Вероятно затронутые файлы:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`, `test/support/in_memory_diagnostics_sink.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 2.4 Усилить типобезопасность предметного контракта до реализации постоянного adapter
  - **Критерии приёмки:**
    - `watchById` публикует `ResultSuccess<Intention?>` и `ResultFailure<Intention?>` как значения, завершает подписку после failure и не использует нетипизированный Dart error channel для ожидаемых repository failures.
    - Публичный `IntentionCatalogCursor` не раскрывает поля или фабрику boundary, допускает adapter-owned implementation и оставляет будущему конкретному adapter проверку чужого, несовместимого или структурно недопустимого cursor через validation failure.
    - `Intention` и `IntentionSummary` отклоняют `updatedAt` раньше `createdAt`, а первая страница в release mode не допускает отрицательный total count или count меньше числа items.
    - Unit tests используют исчерпывающие `switch` для всех command/result/failure/page variants и доказывают завершение `watchById` после typed failure.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application` с отрицательными timestamp/page fixtures, opaque test cursor, исчерпывающими switch helpers и последовательностью typed failure → done.
  - **Зависимости:** 2.1, 2.2, 2.3.
  - **Вероятно затронутые файлы:** `lib/src/intention/domain/intention.dart`, `lib/src/intention/application/intention_repository.dart`, `lib/src/intention/application/intention_result.dart`, `test/intention/domain/intention_test.dart`, `test/intention/application/intention_contract_test.dart`.
  - **Оценка:** M (5 файлов).

- [x] 2.5 Проверить предметный контракт до реализации постоянного adapter
  - **Критерии приёмки:**
    - Граничные Unicode-инварианты, identity, все варианты catalog query/page, command/result и завершение `watchById` после typed failure проходят unit tests.
    - Публичная seam не содержит storage-, transport-, sync- или Flutter-specific types и допускает замену adapter без изменения callers.
    - Change проходит строгую OpenSpec-валидацию после завершения пакета Phase 2.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
    - Выполнить `openspec validate manage-intentions --type change --strict`.
  - **Зависимости:** 2.4.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## Phase 3: Идентичность намерения типобезопасна до появления постоянных данных

- [x] 3.1 Сделать `IntentionId` закрытым UUID-value object со сменной политикой генерации и типизированным декодированием
  - **Критерии приёмки:**
    - Публичный API не позволяет создать `IntentionId` из произвольной строки, не раскрывает `UuidValue` или сырой `.value` и предоставляет равенство, hashing, `Comparable<IntentionId>` и явную каноническую сериализацию для boundary adapters.
    - Production `IntentionIdGenerator` создаёт UUID v7 через `Uuid().v7obj()`, а тестовый generator выдаёт детерминированную последовательность корректных `IntentionId` без обхода предметных инвариантов.
    - Boundary-декодирование возвращает закрытый типизированный результат, принимает канонические lower-case записи ненулевых RFC 9562 UUID разных версий, включая v4 и v7, и отклоняет неверный формат, variant и nil UUID.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain/intention_id_test.dart` с корректным round trip UUID v4 и UUID v7, nil UUID, верхним регистром, записью без дефисов, неверным variant и несколькими генерациями в одну миллисекунду.
    - Выполнить `flutter analyze`.
  - **Зависимости:** Нет.
  - **Вероятно затронутые файлы:** `lib/src/intention/domain/intention_id.dart`, `lib/src/intention/application/intention_id_generator.dart`, `test/intention/domain/intention_id_test.dart`.
  - **Оценка:** M (3 файла).

- [x] 3.2 Перевести существующий прикладной контракт на `IntentionId` без строковых обходов и зависимости от версии UUID
  - **Критерии приёмки:**
    - Catalog ordering использует `IntentionId.compareTo`, а commands, results, summaries и тестовые fixtures передают предметный тип без чтения сырой строки.
    - Корректные UUID v4 fixtures сохраняются как проверка version-neutral decoding, а сценарии создания используют детерминированные UUID v7; гарантии равенства, стабильности identity, opaque cursor и исчерпывающих command/result variants не зависят от версии UUID.
    - В `lib/src/intention` и `test/intention` отсутствуют вызовы публичного строкового конструктора `IntentionId(...)` и обращения к `IntentionId.value`.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application`.
    - Выполнить `rg -n "IntentionId\\(|\.id\.value|IntentionId.*\.value" lib/src/intention test/intention` и убедиться, что совпадений обхода нового API нет.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 3.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/application/intention_repository.dart`, `test/intention/domain/intention_test.dart`, `test/intention/application/intention_contract_test.dart`.
  - **Оценка:** M (3 файла).

- [x] 3.3 Проверить типобезопасную идентичность до реализации постоянного adapter
  - **Критерии приёмки:**
    - Действующий ADR, design, предметный API и прикладные callers согласованно отделяют version-neutral `IntentionId` от production-генерации новых UUID v7 и не допускают произвольные строки или nil UUID.
    - Domain/application/diagnostics tests подтверждают генерацию, декодирование, стабильность identity, отсутствие UUID в production diagnostics и сохранность прежнего repository contract.
    - Статический анализ и строгая OpenSpec-валидация проходят, а Definition of Done для корректирующей фазы выполнен без появления постоянных пользовательских данных.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
    - Выполнить `openspec validate manage-intentions --type change --strict`.
  - **Зависимости:** 3.1, 3.2.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## Phase 4: Локальные данные имеют надёжный версионируемый lifecycle

- [x] 4.1 Подключить Android production connection через `QueryExecutor` и связать расположение SQLite-файла с действующей backup policy
  - **Критерии приёмки:**
    - `AppDatabase` принимает только `QueryExecutor` и не знает Android paths, backup domains или platform APIs, а production connection использует `driftDatabase(name: 'doable', ...)`, `getApplicationDocumentsDirectory` и background isolate.
    - Production locator однозначно разрешается в `root/app_flutter/doable.sqlite`, включая соседние WAL/SHM, а contract test доказывает исключение всего `root/app_flutter/` из cloud backup и device-to-device transfer обоими наборами Android rules.
    - Отрицательные fixtures с прежним `database` domain, неполным путём или другим именем connection не проходят contract; capability не получает `INTERNET`, разрешения внешнего хранилища, экспорт или синхронизацию.
  - **Проверка:**
    - Выполнить `flutter test test/android/backup_policy_test.dart test/data/local/database_connection_test.dart`.
    - Выполнить `flutter build apk --debug`.
  - **Зависимости:** 1.3, 3.3.
  - **Вероятно затронутые файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/database_connection.dart`, `test/data/local/database_connection_test.dart`, `test/android/backup_policy_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 4.2 Зафиксировать Drift schema version 1 для намерений и ограничивающие индексы будущих catalog queries
  - **Критерии приёмки:**
    - Таблица `intentions` хранит канонический UUID как `TEXT PRIMARY KEY`, исходное название, внутренний `title_search_key`, nullable-описание, обязательные состояния готовности и архива и UTC timestamps в микросекундах; уникального ограничения на название нет.
    - SQL constraints защищают обязательность, начальные boolean-состояния и допустимое соотношение timestamps, не подменяя предметную Unicode-валидацию или типизированное декодирование `IntentionId`.
    - Индексы поддерживают active, archived и all scopes и полный порядок по `created_at` либо `updated_at` с `id` как tie-breaker без offset pagination или неограниченного чтения.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs`.
    - Выполнить `flutter test test/data/local/app_database_schema_test.dart` с duplicate-title, nullable-description, timestamp и index fixtures.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 3.3.
  - **Вероятно затронутые файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/schema/intention_schema.drift`, `lib/src/data/local/app_database.g.dart`, `test/data/local/app_database_schema_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 4.3 Добавить транзакционно согласованный external-content FTS5-индекс названий и index-aware проверку его целостности
  - **Критерии приёмки:**
    - `intention_titles_fts` индексирует `title_search_key` с `trigram case_sensitive 0 remove_diacritics 0`, связан с hidden `rowid` таблицы `intentions`, а insert/update/delete triggers изменяют индекс в той же transaction, что и основную строку.
    - Native runtime действительно создаёт FTS5 virtual table и выполняет параметризованный буквальный `MATCH`; короткие search keys из одной или двух кодовых точек остаются возможны через параметризованный storage path без FTS operators из пользовательского текста.
    - Канонический `integrity-check` с `rank = 1` проходит для согласованных данных и падает на намеренно рассогласованной fixture, тогда как обычное external-content чтение демонстративно не считается доказательством; production и migration paths не выполняют `VACUUM`.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs`.
    - Выполнить `flutter test test/data/local/fts_consistency_test.dart test/data/local/app_database_schema_test.dart`.
  - **Зависимости:** 4.2.
  - **Вероятно затронутые файлы:** `build.yaml`, `lib/src/data/local/schema/intention_schema.drift`, `lib/src/data/local/fts_integrity.dart`, `test/data/local/fts_consistency_test.dart`.
  - **Оценка:** M (4 файла).

- [x] 4.4 Закрепить schema snapshot и атомарный migration harness без destructive fallback
  - **Критерии приёмки:**
    - Schema version 1 имеет committed snapshot и generated migration artifacts; дальнейшие пошаговые переходы выполняются от каждой опубликованной версии к текущей в одной write transaction с `foreign_keys = OFF` до её начала и `foreign_key_check` до commit.
    - Migration step, перестраивающий `intentions`, обязан сохранить прежние hidden rowids либо атомарно пересоздать и заполнить FTS, после чего выполнить `integrity-check` с `rank = 1`; нет downgrade, автоматического удаления, пересоздания базы или нетранзакционного rowid-rewriting path.
    - Fault-injection harness доказывает rollback схемы, данных и version marker при exception, закрытие неуспешного соединения и безопасный повтор из последней целостной версии; test-only переход не объявляется опубликованной production schema.
  - **Проверка:**
    - Выполнить `dart run drift_dev schema dump lib/src/data/local/app_database.dart drift_schemas/` и `dart run drift_dev schema steps drift_schemas/ lib/src/data/local/migrations/generated_schema.dart`.
    - Выполнить `flutter test test/data/local/migrations` с generated validation, fault injection, `foreign_key_check` и FTS integrity fixtures.
  - **Зависимости:** 4.2, 4.3.
  - **Вероятно затронутые файлы:** `drift_schemas/`, `lib/src/data/local/migrations/migration_strategy.dart`, `lib/src/data/local/migrations/generated_schema.dart`, `test/data/local/migrations/migration_test.dart`, `test/data/local/migrations/fault_injection_test.dart`.
  - **Оценка:** M (до 5 файлов или групп артефактов).

- [x] 4.5 Реализовать типизированный bootstrap локального хранилища с безопасной проверкой совместимости и диагностикой
  - **Критерии приёмки:**
    - Bootstrap не предоставляет repository или feature operations до успешного открытия, проверки версии, необходимых миграций и включения `foreign_keys = ON`; результат исчерпывающе различает готовность, устранимую ошибку, corruption и non-retryable `incompatibleSchema`.
    - Более новая версия хранилища обнаруживается до feature query или записи и остаётся побайтно неизменной без downgrade, удаления или пересоздания; версия ниже 1 и отсутствующая либо повреждённая metadata не угадываются и классифицируются как corruption.
    - Устранимая ошибка закрывает неготовое соединение и допускает явную новую попытку, а bootstrap/migration diagnostics содержат только длительность, outcome, безопасный failure code и применимые версии схемы без пользовательского текста, UUID, SQL parameters или полного exception.
  - **Проверка:**
    - Выполнить `flutter test test/data/local/bootstrap` с new/current/newer/corrupt schema fixtures, retry и проверкой отсутствия feature access до ready.
    - Выполнить `flutter test test/shared/diagnostics/diagnostics_sink_test.dart` с canary-значениями.
  - **Зависимости:** 2.3, 4.1, 4.4.
  - **Вероятно затронутые файлы:** `lib/src/data/local/bootstrap/local_data_bootstrap.dart`, `lib/src/data/local/bootstrap/local_data_bootstrap_result.dart`, `lib/src/data/local/app_database.dart`, `test/data/local/bootstrap/local_data_bootstrap_test.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** M (5 файлов).

- [x] 4.6 Доказать in-memory и file-backed lifecycle схемы до подключения `IntentionRepository`
  - **Критерии приёмки:**
    - Общий storage-level harness работает с `NativeDatabase.memory()` и реальным временным SQLite-файлом, полностью закрывает первый persistence object graph и после повторного открытия подтверждает те же UUID разных версий, текст, состояния и UTC timestamps.
    - Повторное открытие подтверждает `foreign_keys = ON`, согласованность основной таблицы и FTS через `integrity-check` с `rank = 1`, а также отсутствие частично подтверждённого состояния после fault-injected migration failure.
    - File-backed fixture с более новой схемой остаётся неизменной после отказа bootstrap; тесты освобождают executor и временные ресурсы и не используют будущий `IntentionRepository` или presentation composition.
  - **Проверка:**
    - Выполнить `flutter test test/data/local/file_backed_database_test.dart test/data/local/migrations/file_backed_migration_test.dart`.
    - Повторить `flutter test test/android/backup_policy_test.dart test/data/local/database_connection_test.dart`.
  - **Зависимости:** 4.1, 4.3, 4.4, 4.5.
  - **Вероятно затронутые файлы:** `test/data/local/file_backed_database_test.dart`, `test/data/local/migrations/file_backed_migration_test.dart`, `test/support/local_database_harness.dart`.
  - **Оценка:** M (3 файла).

- [x] 4.7 Проверить надёжный версионируемый lifecycle локальных данных перед реализацией repository adapter
  - **Критерии приёмки:**
    - In-memory и file-backed evidence подтверждает schema version 1, catalog indexes, runtime FTS5, `foreign_key_check`, index-aware FTS consistency, атомарный rollback/retry и безопасный отказ от более новой схемы.
    - Android production locator, SQLite service files и оба набора backup/transfer rules образуют один проверяемый host contract, а `AppDatabase` и bootstrap остаются свободны от `IntentionRepository`, UI, transport и sync-specific interfaces.
    - Повторная генерация не оставляет tracked или untracked diff, статический анализ, storage tests, Android debug build и строгая OpenSpec-валидация проходят на текущем состоянии change.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs` и `git status --short`, ожидая отсутствие результата генерации.
    - Выполнить `flutter test test/data/local test/android/backup_policy_test.dart test/shared/diagnostics` и `flutter analyze`.
    - Выполнить `flutter build apk --debug` и `openspec validate manage-intentions --type change --strict`.
  - **Зависимости:** 4.1, 4.2, 4.3, 4.4, 4.5, 4.6.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.
