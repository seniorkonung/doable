## 1. Сборочная основа, локализация и Android host adapter

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

## 2. Предметный контракт глубокого модуля

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

- [x] 2.2 Определить закрытые commands, typed `Result`/failures и небольшую seam `IntentionRepository`
  - **Критерии приёмки:**
    - Interface предоставляет только `watchCatalog`, `watchById` и `execute`, не раскрывая Drift или SQLite types.
    - Interface не раскрывает расположение данных, transport или состояние синхронизации; sync-specific методы, remote port, outbox, tombstones и revisions отсутствуют.
    - Commands различают создание, изменение данных, включение и выключение готовности, архивирование, восстановление и физическое удаление.
    - Закрытый success type различает `IntentionSaved` с подтверждённым намерением для create/change/no-op и `IntentionDeleted` с идентификатором только для подтверждённого удаления; отдельный `changed` flag отсутствует.
    - Scope, два порядка каталога и стабильные repository-level validation/not-found/conflict/unavailable/corruption failures выражены типами без bootstrap- или Drift-specific деталей.
    - Оба watch-метода допускают в error channel только типизированную repository failure, после неё завершают текущий stream и требуют новой подписки для retry.
  - **Проверка:**
    - Выполнить `flutter test test/intention/application/intention_contract_test.dart` для исчерпывающих success/failure variants, no-op/delete payloads и stream failure lifecycle.
    - Выполнить `flutter analyze` и проверить исчерпывающую обработку sealed variants.
  - **Зависимости:** 2.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/application/intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `lib/src/intention/application/intention_result.dart`, `test/intention/application/intention_contract_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 2.3 Ввести `DiagnosticsSink` с безопасными структурированными событиями и проверяемым запретом пользовательских данных
  - **Критерии приёмки:**
    - Контракт поддерживает события bootstrap/migration, чтения и commands с типом операции, длительностью, outcome, failure code, ожидаемой и обнаруженной версиями схемы.
    - Production adapter не записывает названия, описания, UUID, SQL-параметры или полные database exceptions.
    - In-memory adapter позволяет проверять диагностику без внешней telemetry.
  - **Проверка:**
    - Выполнить `flutter test test/shared/diagnostics/diagnostics_sink_test.dart` с canary-значениями пользовательского текста и UUID.
  - **Зависимости:** 2.2.
  - **Вероятно затронутые файлы:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`, `test/support/in_memory_diagnostics_sink.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 2.4 Проверить предметный контракт до реализации постоянного adapter
  - **Критерии приёмки:**
    - Граничные Unicode-инварианты, identity, все варианты command/result и завершение watch stream после typed failure проходят unit tests.
    - Публичная seam не содержит storage-, transport-, sync- или Flutter-specific types и допускает замену adapter без изменения callers.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 2.1, 2.2, 2.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## 3. Версионируемый lifecycle локальных данных

- [ ] 3.1 Реализовать `AppDatabase` schema version 1, production/in-memory executors и защиту от более новой версии хранилища
  - **Критерии приёмки:**
    - Таблица хранит UUID `TEXT PRIMARY KEY`, нормализованное название, nullable описание, готовность, архивное состояние и UTC timestamps в микросекундах без unique index по названию.
    - Production connection Android host открывает один файл во внутреннем app-specific storage в background isolate, а `AppDatabase`, migrations и тестовый in-memory executor не зависят от Android paths или permissions.
    - Отсутствующая или текущая версия открывается с `PRAGMA foreign_keys = ON`, а версия выше `AppDatabase.schemaVersion` возвращает typed `incompatibleSchema` до feature query и не изменяет, не удаляет и не пересоздаёт database.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs`.
    - Выполнить `flutter test test/data/local/app_database_test.dart test/data/local/database_version_compatibility_test.dart`.
  - **Зависимости:** 1.1, 2.1.
  - **Вероятно затронутые файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/database_connection.dart`, `lib/src/data/local/app_database.g.dart`, `test/data/local/app_database_test.dart`, `test/data/local/database_version_compatibility_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.2 Зафиксировать schema snapshot версии 1 и generated step-by-step migration harness
  - **Критерии приёмки:**
    - `drift_dev` конфигурация экспортирует и навсегда коммитит snapshot версии 1, который совпадает с фактической schema и становится исходной точкой всех следующих опубликованных переходов.
    - Generated step-by-step helper и migration test harness позволяют добавлять один `fromNToN+1` для каждой будущей версии и проверять прямой переход с любого сохранённого snapshot до целевой версии.
    - Повторный `make-migrations` и code generation не создают дополнительного diff.
  - **Проверка:**
    - Выполнить `dart run drift_dev make-migrations` с зафиксированной проектной конфигурацией.
    - Выполнить generated schema tests и повторить `dart run drift_dev make-migrations` без дополнительного diff.
  - **Зависимости:** 3.1.
  - **Вероятно затронутые файлы:** `build.yaml`, `drift_schemas/drift_schema_v1.json`, `lib/src/data/local/app_database.steps.dart`, `test/data/local/migrations/schema_v1_test.dart`, `test/data/local/migrations/generated/schema.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.3 Реализовать атомарный migration orchestrator и доказать rollback при ошибке или прерывании
  - **Критерии приёмки:**
    - Orchestrator выключает `foreign_keys` до транзакции, внутри одной write transaction выполняет generated DDL/DML migration steps и `foreign_key_check` до commit, а `beforeOpen` снова включает `foreign_keys`; `VACUUM` и destructive fallback отсутствуют.
    - Fault injection после изменений таблицы, данных и индекса откатывает схему, fixture-данные и marker версии, после чего повторное открытие успешно начинает с прежней целостной версии.
    - File-backed worker, принудительно завершённый до commit, и fixture с более новой версией доказывают соответственно crash recovery и отказ от feature query, записи, downgrade, удаления или пересоздания файла.
  - **Проверка:**
    - Выполнить `flutter test test/data/local/migrations/atomic_migration_test.dart test/data/local/migrations/migration_interruption_test.dart test/data/local/migrations/newer_schema_test.dart`.
    - Повторно открыть каждый file-backed fixture и проверить schema, данные, marker версии и `PRAGMA foreign_key_check`.
  - **Зависимости:** 3.1, 3.2.
  - **Вероятно затронутые файлы:** `lib/src/data/local/migrations/migration_strategy.dart`, `test/data/local/migrations/atomic_migration_test.dart`, `test/data/local/migrations/migration_interruption_test.dart`, `test/data/local/migrations/newer_schema_test.dart`, `test/support/migration_process_worker.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.4 Проверить версионируемую SQLite-основу перед реализацией жизненного цикла
  - **Критерии приёмки:**
    - In-memory и файловое открытие используют schema version 1 и включённые foreign keys, а более новая версия даёт typed `incompatibleSchema` без изменения файла.
    - Schema snapshot, generated steps, marker версии, atomic rollback, crash recovery и migration tests согласованы.
    - Проверки покрывают требования `local-data-lifecycle` к совместимому обновлению, пропуску опубликованных версий, прерыванию migration и отказу от более новой схемы.
  - **Проверка:**
    - Выполнить `flutter test test/data/local`.
    - Повторить `dart run drift_dev make-migrations` и `dart run build_runner build --delete-conflicting-outputs` без дополнительного diff.
  - **Зависимости:** 3.1, 3.2, 3.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## 4. Постоянный жизненный цикл через `IntentionRepository`

- [ ] 4.1 Реализовать создание намерения и реактивное чтение активного каталога, архива и подробных данных
  - **Критерии приёмки:**
    - Создание выдаёт новый UUID v4, принудительно создаёт активное неготовое намерение и атомарно записывает один UTC-момент в оба timestamp.
    - Одинаковые названия сохраняются как независимые сущности, а `watchCatalog` фильтрует scope и детерминированно сортирует по creation/update timestamp с `id ASC` как tie-breaker.
    - Streams публикуют начальный snapshot и только подтверждённое после commit состояние; `watchById` возвращает отсутствие для неизвестного идентификатора.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_create_read_test.dart`.
  - **Зависимости:** 2.2, 2.3, 3.4.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/data/intention_mapper.dart`, `test/intention/data/drift_intention_repository_create_read_test.dart`, `test/support/repository_harness.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.2 Реализовать атомарное изменение названия и описания с точной семантикой `updatedAt`
  - **Критерии приёмки:**
    - Допустимые изменения активного и архивированного намерения сохраняют идентификатор, `createdAt` и архивное состояние.
    - Фактическое изменение обновляет `updatedAt`, а no-op возвращает текущий `IntentionSaved` без записи и вместе с отклонённым значением или failure оставляет оба прежних timestamp.
    - Ошибка не заменяет последний подтверждённый snapshot в streams.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_edit_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_edit_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.3 Реализовать отдельные commands включения и выключения готовности к действию без автоматической классификации
  - **Критерии приёмки:**
    - Новое намерение нельзя создать готовым, а готовность активного или архивированного намерения меняется только соответствующим явным command.
    - Изменение названия или описания никогда не меняет готовность побочным эффектом.
    - Фактическое переключение обновляет только `updatedAt`; повтор того же состояния является no-op.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.4 Проверить создание, чтение, изменение и готовность через публичную seam
  - **Критерии приёмки:**
    - Все выполненные операции наблюдаемы через `IntentionRepository`, а тесты не обращаются к внутренним Drift rows для доказательства пользовательского поведения.
    - Активный каталог, архив и подробный поток остаются согласованными после каждого commit.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_create_read_test.dart test/intention/data/drift_intention_repository_edit_test.dart test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Зависимости:** 4.1, 4.2, 4.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 4.5 Реализовать архивирование и восстановление намерения без изменения остальных предметных данных
  - **Критерии приёмки:**
    - Архивирование переносит намерение из активного каталога в архив, не меняя его название, описание, идентификатор или готовность.
    - Восстановление возвращает архивированное намерение в активный каталог с теми же данными.
    - Каждое фактическое переключение атомарно обновляет `updatedAt`, а no-op не изменяет timestamps.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_archive_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_archive_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.6 Реализовать физическое удаление активного или архивированного несвязанного намерения как отдельный command
  - **Критерии приёмки:**
    - Удаление не требует архивирования, возвращает `IntentionDeleted` с тем же идентификатором только после commit и исключает сущность из обоих каталогов, а подробный поток публикует отсутствие.
    - Отсутствующее намерение возвращает typed not-found, failure не скрывает запись, а удалённый UUID никогда не переиспользуется новым созданием.
    - Repository оставляет транзакционную точку проверки блокирующих зависимостей для последующих change связей, не моделируя связи заранее.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_delete_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_delete_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.7 Завершить транзакционную классификацию storage failures и безопасную диагностику всех repository operations
  - **Критерии приёмки:**
    - Validation, not-found, UUID conflict, unavailable и corruption outcomes стабильно преобразуются в typed failures без утечки database exceptions.
    - Ошибки до commit не публикуют промежуточные snapshots и сохраняют возможность повторить command.
    - Ошибка чтения публикует ровно одну typed failure в error channel и завершает stream; новая попытка создаёт новую подписку, а raw Drift/SQLite exception не пересекает seam.
    - Диагностика содержит только разрешённый тип операции, duration, outcome и безопасный code, включая ошибки чтения и закрытую/повреждённую database.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_failure_test.dart`.
    - Выполнить `flutter test test/shared/diagnostics`.
  - **Зависимости:** 2.3, 4.2, 4.3, 4.5, 4.6.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/data/storage_failure_mapper.dart`, `test/intention/data/drift_intention_repository_failure_test.dart`, `test/support/failing_query_executor.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.8 Проверить полный repository lifecycle и отсутствие регрессий хранилища
  - **Критерии приёмки:**
    - Создание, два порядка чтения, изменение, готовность, архивирование, восстановление и удаление проходят через одну seam на in-memory SQLite.
    - Ошибочные, отклонённые и no-op operations сохраняют подтверждённые данные и timestamps.
  - **Проверка:**
    - Выполнить `flutter test test/intention test/data/local test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 4.4, 4.5, 4.6, 4.7.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## 5. Пользовательские вертикали Flutter

- [ ] 5.1 Реализовать локализуемый bootstrap shell и generated Riverpod composition root с явным retry и корректным закрытием ресурсов
  - **Критерии приёмки:**
    - Корневой `ProviderScope` предоставляет diagnostics, database, repository и router через generated `keepAlive` providers без service locator, глобальных mutable instances или database singleton.
    - До готовности database async bootstrap provider показывает loading; retryable opening/migration failure предоставляет явную invalidation для retry, а non-retryable `incompatibleSchema` не создаёт repository и сообщает о необходимости установить совместимое обновление без destructive recovery.
    - `ProviderScope` отключает automatic retry через `retry: (retryCount, error) => null`, а `ref.onDispose` закрывает database и подписки ровно один раз.
    - Loading, retryable failure, успешное восстановление после явного retry и non-retryable более новая schema наблюдаемо соответствуют сценариям `local-data-lifecycle`.
  - **Проверка:**
    - Выполнить `flutter test test/app/bootstrap` с отдельным `ProviderContainer` для loading, success, первого failure без автоматического повтора, явного retry и dispose.
  - **Зависимости:** 1.2, 3.4, 4.8.
  - **Вероятно затронутые файлы:** `lib/main.dart`, `lib/src/app/bootstrap/bootstrap_providers.dart`, `lib/src/app/bootstrap/bootstrap_view_model.dart`, `lib/src/app/app.dart`, `test/app/bootstrap/app_bootstrap_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.2 Настроить `MaterialApp.router` и generated типизированные AutoRoute-маршруты для внутренних переходов
  - **Критерии приёмки:**
    - `AppRouter` через `@AutoRouterConfig` и страницы через `@RoutePage` генерируют `PageRouteInfo` для каталога, создания и подробного просмотра; маршрут подробного просмотра требует предметный `IntentionId`, а router получается из generated `keepAlive` provider.
    - Внутренние переходы используют только generated route objects; строковые `pushNamed`, `replaceNamed`, `navigateNamed`, route names и ручная сборка path отсутствуют в прикладном коде.
    - Внешняя схема URI, строковый path-параметр, deep-link adapter и platform-регистрация внешних маршрутов отсутствуют; маршрут подробного просмотра не принимает недоверенную строку и не требует routing-level parser идентификатора.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs` и `flutter analyze`, чтобы проверить generated route types и обязательные аргументы.
    - Выполнить `flutter test test/app/routing` для типизированных переходов из активного каталога и архива, обязательного `IntentionId` и возврата в исходный scope.
    - Выполнить `rg -n --glob '!*.gr.dart' "pushNamed|replaceNamed|navigateNamed" lib` и убедиться, что строковая навигация отсутствует.
  - **Зависимости:** 5.1.
  - **Вероятно затронутые файлы:** `lib/src/app/app.dart`, `lib/src/app/routing/app_router.dart`, `lib/src/app/routing/app_router.gr.dart`, `test/app/routing/app_router_test.dart`, `test/support/app_harness.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.3 Реализовать активный каталог и архив с реактивными состояниями и переключением порядка
  - **Критерии приёмки:**
    - Generated class-based `@riverpod` Catalog ViewModel хранит порядок, а parameterized Stream provider представляет repository stream через `AsyncValue` и автоматически освобождается после ухода с экрана.
    - View различает loading/data/empty/failure, явно разделяет активный каталог и архив, предоставляет целевую invalidation для retry и не показывает failure как пустой результат.
    - Название, наличие описания, готовность и архивное состояние доступны текстом или semantics и не кодируются только цветом.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/catalog` через `ProviderContainer` для обоих scope, двух порядков, равных timestamps, loading/empty/failure/явного retry, automatic disposal и stream updates.
  - **Зависимости:** 5.2.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/catalog/catalog_view_model.dart`, `lib/src/intention/presentation/catalog/catalog_state.dart`, `lib/src/intention/presentation/catalog/catalog_view.dart`, `test/intention/presentation/catalog/catalog_view_model_test.dart`, `test/intention/presentation/catalog/catalog_view_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.4 Проверить bootstrap, routing и каталоги как первый читаемый пользовательский срез
  - **Критерии приёмки:**
    - Приложение проходит от bootstrap до активного каталога и архива при success, а retry восстанавливает работу после моделируемой ошибки.
    - Более новая версия хранилища оставляет feature routes и repository недоступными, показывает локализованное требование обновить приложение без retry и не изменяет database.
    - Внутренний переход к намерению из активного каталога или архива и возврат сохраняют исходный scope и корректное состояние навигации.
  - **Проверка:**
    - Выполнить `flutter test test/app test/intention/presentation/catalog`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 5.1, 5.2, 5.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 5.5 Реализовать общий presentation-модуль для эксклюзивного выполнения одной асинхронной операции
  - **Критерии приёмки:**
    - `ExclusiveOperation` предоставляет одну синхронную операцию `start`: первый вызов резервирует экземпляр и возвращает принятое выполнение с его `Future`, а вызов занятого экземпляра возвращает отдельный outcome `alreadyRunning`, не вызывая и не ставя в очередь второе действие.
    - Gate освобождается после success, failure или неожиданной ошибки принятого действия; общий неизменяемый `OperationState<TResult>` предоставляет ViewModels статусы `idle`, `running`, `succeeded` и `failed`, но module не знает о предметных сущностях, repository, локализации или навигации.
    - Разные экземпляры выполняются независимо; scope экземпляра задаёт владеющая ViewModel, а experimental Riverpod Mutations и глобальный registry операций не используются.
  - **Проверка:**
    - Выполнить `flutter test test/shared/presentation/exclusive_operation_test.dart` для принятого и отклонённого outcomes, двух быстрых вызовов, отсутствия отложенного второго запуска, освобождения после success/failure/exception и независимых экземпляров.
  - **Зависимости:** 1.1.
  - **Вероятно затронутые файлы:** `lib/src/shared/presentation/exclusive_operation.dart`, `test/shared/presentation/exclusive_operation_test.dart`.
  - **Оценка:** S (2 файла).

- [ ] 5.6 Реализовать пользовательский поток создания намерения без optimistic сохранения
  - **Критерии приёмки:**
    - Generated class-based `@riverpod` Editor ViewModel и форма используют общую предметную Unicode-валидацию, локализуют ошибки и не предлагают включить готовность при создании.
    - Отдельный для экземпляра формы `ExclusiveOperation` делает повторную отправку недоступной, защитно не запускает и не ставит её в очередь во время `running`, публикует одноразовый success event для навигации и сохраняет введённые данные для явного retry при failure.
    - Созданное намерение появляется в активном каталоге через repository stream, а пользовательский текст отображается без перевода или преобразования.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/editor/create_intention_test.dart` с пробелами, одинаковыми названиями, Unicode-границами, сохранением полей и повторной доступностью отправки после failure, а также double-submit без второго repository command.
  - **Зависимости:** 4.2, 5.3, 5.5.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `lib/src/intention/presentation/editor/intention_editor_view.dart`, `lib/src/intention/presentation/editor/intention_form.dart`, `test/intention/presentation/editor/create_intention_test.dart`, `test/support/fake_intention_repository.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.7 Реализовать подробный просмотр и изменение названия и описания активного или архивированного намерения
  - **Критерии приёмки:**
    - Parameterized Stream provider представляет подробные данные через `AsyncValue`, а generated class-based `@riverpod` Details ViewModel переиспользует для каждого `IntentionId` единый `ExclusiveOperation` и общий `OperationState` с видом текущей операции, сохраняя последний подтверждённый snapshot при write failure.
    - Пока mutation имеет статус `running`, ViewModel оставляет чтение активным, делает все изменяющие controls этого намерения недоступными и защитной проверкой не запускает и не ставит в очередь второй command; разные `IntentionId` не разделяют этот gate.
    - Первый snapshot имеет отдельное loading-состояние, успешный `null` показывает локализованный not-found, а typed read failure показывает отличимое сообщение об ошибке и явный retry только для устранимого случая.
    - Retry инвалидирует только provider текущего `IntentionId`, создаёт новую `watchById`-подписку и при успехе восстанавливает подробные данные; automatic disposal отменяет подписку после ухода последнего слушателя, а повторное открытие начинает новое чтение.
    - Пользователь видит название, полное описание, готовность и явное архивное состояние и может изменить текст без предварительного восстановления.
    - Success обновляет то же намерение с прежним идентификатором, а отмена, validation failure и storage failure сохраняют прежнее подтверждённое состояние.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/intention_details_read_states_test.dart test/intention/presentation/details/edit_intention_test.dart` для initial loading, data, not-found, read failure, targeted retry, recovery, disposal/re-entry, active/archive, no-op, validation и storage failure.
  - **Зависимости:** 4.2, 5.2, 5.5, 5.6.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `lib/src/intention/presentation/editor/intention_editor_view.dart`, `test/intention/presentation/details/intention_details_read_states_test.dart`, `test/intention/presentation/details/edit_intention_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.8 Реализовать явное подтверждение включения и обратимое выключение готовности к действию
  - **Критерии приёмки:**
    - Перед включением локализованный dialog объясняет оба критерия: полную выполнимость за один день и операционную понятность; отмена не запускает command.
    - Выключение остаётся отдельным явным действием, а название или описание не запускают автоматическую классификацию.
    - Общий для `IntentionId` mutation `OperationState` указывает операцию готовности, предотвращает double-submit и любое другое изменение до результата, а затем публикует доступный одноразовый success/failure event, сохраняя последний подтверждённый snapshot.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/readiness_test.dart` для confirm/cancel, enable/disable, failure и semantics.
  - **Зависимости:** 4.3, 5.7.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/readiness_dialog.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/readiness_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 5.9 Проверить создание, подробный просмотр, изменение и готовность как законченный редактируемый срез
  - **Критерии приёмки:**
    - Пользователь может создать намерение, открыть его, изменить текст, включить и выключить готовность с согласованным обновлением каталога.
    - Отмены и моделируемые failures не показывают несохранённое состояние как подтверждённое.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/editor test/intention/presentation/details`.
  - **Зависимости:** 5.6, 5.7, 5.8.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 5.10 Реализовать архивирование активного намерения и восстановление архивированного намерения в UI
  - **Критерии приёмки:**
    - Доступная операция зависит от текущего архивного состояния и не представляется как выполнение или удаление.
    - Success реактивно перемещает намерение между каталогами без изменения текста и готовности; failure оставляет подробный snapshot и даёт повторить операцию, а общий mutation gate до результата исключает пересечение с edit, readiness и delete.
    - Архивированное намерение остаётся доступным для просмотра и изменения.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/archive_restore_test.dart` для active/archive, success, failure и stream update.
  - **Зависимости:** 4.5, 5.7.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/archive_restore_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 5.11 Реализовать отдельное необратимое удаление активного или архивированного намерения с подтверждением
  - **Критерии приёмки:**
    - Delete недоступен как случайный побочный эффект архивирования и запускается только после локализованного явного подтверждения необратимости.
    - Отмена не выполняет command; success закрывает подробный экран и удаляет запись из обоих каталогов; failure сохраняет запись и предоставляет retry, а во время delete общий mutation gate не допускает другого изменения и второго события результата.
    - Dialog и результат операции имеют корректные semantics и не раскрывают пользовательский текст в diagnostics.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/delete_intention_test.dart` для active/archive, confirm/cancel, success/failure и double-submit.
  - **Зависимости:** 4.6, 4.7, 5.7.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/delete_confirmation_dialog.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/delete_intention_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 5.12 Проверить полный пользовательский жизненный цикл намерения через Riverpod overrides на fake repository
  - **Критерии приёмки:**
    - Widget tests покрывают создание, каталоги, подробности, изменение, готовность, архивирование, восстановление и удаление.
    - Отдельный `ProviderContainer`/`ProviderScope` override подменяет только `IntentionRepository`; для каждой операции проверены running/success/failure, одноразовые events, automatic disposal и сохранение последнего подтверждённого snapshot.
    - Parameterized tests для общего mutation gate доказывают, что любая выполняющаяся edit/readiness/archive/restore/delete operation блокирует запуск и постановку в очередь второй операции того же `IntentionId`; после success операции, сохраняющей существование намерения, или failure любой операции допустимые controls снова доступны, после delete success подробный просмотр завершается и controls удалённого намерения отсутствуют, а операция другого `IntentionId` остаётся независимой.
    - Fake adapter соблюдает те же `IntentionSaved`/`IntentionDeleted` payloads и завершение watch stream после typed failure, что и production adapter; явный retry создаёт новую подписку.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation test/app`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 5.9, 5.10, 5.11.
  - **Вероятно затронутые файлы:** `test/intention/presentation/details/mutation_serialization_test.dart`.
  - **Оценка:** S (1 файл).

## 6. Интеграция и production-readiness

- [ ] 6.1 Проверить локальную долговечность через повторное открытие file-backed SQLite
  - **Критерии приёмки:**
    - Первый независимый `AppDatabase`/`IntentionRepository` object graph создаёт во временном SQLite-файле представительные активные и архивированные намерения, изменяет текст и готовность к действию и фиксирует ожидаемые идентификаторы, данные и timestamps.
    - После отмены всех stream-подписок, закрытия первого `AppDatabase` и отбрасывания первого repository instance второй независимо созданный graph открывает тот же файл через новый file-backed `QueryExecutor` и восстанавливает точные идентификаторы, текст, готовность к действию, архивное состояние и timestamps только через публичную repository seam.
    - Удаление после повторного открытия сохраняется после закрытия второго и открытия третьего graph; in-memory executor, `ProviderContainer`, UI и повторное использование прежних database/repository objects отсутствуют, а временный файл очищается только после финальных assertions.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_persistence_test.dart`.
  - **Зависимости:** 3.4, 4.8.
  - **Вероятно затронутые файлы:** `test/intention/data/drift_intention_repository_persistence_test.dart`, `test/support/repository_harness.dart`.
  - **Оценка:** S (2 файла).

- [ ] 6.2 Закрыть русскую, английскую и fallback локализацию всех системных строк без изменения пользовательского текста
  - **Критерии приёмки:**
    - Все loading/empty/failure, validation, commands, критерии действия, подтверждения и semantics имеют содержательные `en` и `ru` значения.
    - Локали `ru` и `en` показывают соответствующие системные строки, любая другая локаль использует `en`.
    - Сохранённые названия и описания остаются посимвольно одинаковыми при смене локали и выводятся только как plain text.
  - **Проверка:**
    - Выполнить `flutter gen-l10n`.
    - Выполнить `flutter test test/app/localization test/intention/presentation/localization_test.dart`.
  - **Зависимости:** 5.12.
  - **Вероятно затронутые файлы:** `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`, `test/app/localization/locale_resolution_test.dart`, `test/intention/presentation/localization_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 6.3 Доказать platform-neutral доступность основного жизненного цикла и проверить Android host через TalkBack
  - **Критерии приёмки:**
    - Интерактивные элементы имеют роли, labels, state, предсказуемый focus order и tap targets не менее 48×48; ошибки и результаты операций объявляются доступно.
    - Архивное состояние и готовность воспринимаются без опоры на цвет, а пользовательский текст не обрезает необходимые данные или commands при text scale 200%.
    - Flutter semantics и layout не зависят от конкретного screen reader, а ручной TalkBack smoke test текущего Android host проходит создание, изменение, готовность, архивирование, восстановление и удаление.
  - **Проверка:**
    - Выполнить `flutter test test/accessibility` с semantics assertions и text scale 200%.
    - Выполнить ручной TalkBack smoke test на Android и зафиксировать результат в проверке change.
  - **Зависимости:** 5.12, 6.2.
  - **Вероятно затронутые файлы:** `test/accessibility/intention_semantics_test.dart`, `test/accessibility/intention_text_scale_test.dart`, `lib/src/shared/ui/accessible_operation_feedback.dart`.
  - **Оценка:** M (3 файла).

- [ ] 6.4 Проверить Android privacy adapter в release mode и полноту безопасной диагностики
  - **Критерии приёмки:**
    - Release-mode APK не запрашивает `INTERNET` или внешнее хранилище, а backup rules исключают database, WAL и временные файлы из cloud backup и device-to-device transfer согласно контракту одной установки.
    - События bootstrap, migration, чтения и каждого command содержат outcome и duration; migration events также содержат только ожидаемую и обнаруженную версии схемы, а тесты с canary-данными не обнаруживают название, описание, UUID, SQL-параметр или полный exception.
    - Проверка untrusted text/database inputs не выявляет обхода валидации, SQL interpolation, markup rendering или destructive recovery.
  - **Проверка:**
    - Выполнить `flutter build apk --release` и проверить permissions через `apkanalyzer manifest permissions build/app/outputs/flutter-apk/app-release.apk`.
    - Выполнить `flutter test test/shared/diagnostics test/security`.
  - **Зависимости:** 1.3, 4.7, 5.12, 6.1.
  - **Вероятно затронутые файлы:** `test/security/privacy_boundary_test.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** S (2 файла).

- [ ] 6.5 Настроить обязательный GitHub Actions PR gate для воспроизводимой проверки change
  - **Критерии приёмки:**
    - Workflow запускается для pull request и релевантного push из чистого checkout на Linux runner, устанавливает только явно зафиксированные версии используемых инструментов, разрешает зависимости без изменения `pubspec.lock`, а его статус настроен как обязательная проверка защищённой основной ветки.
    - Gate повторяет `flutter gen-l10n`, Riverpod/AutoRoute/Drift code generation и Drift schema/migration generation, после чего требует пустой `git status --porcelain`, включая отсутствие новых незакоммиченных generated files и schema snapshots.
    - Gate выполняет `mise run check`, file-backed repository и migration tests, собирает release-mode APK, проверяет его manifest permissions и запускает `openspec validate --all --strict --no-interactive`.
    - Android device/emulator job не создаётся: TalkBack остаётся отдельным ручным Android evidence из задачи 6.3, а CI-сборка и manifest check не объявляются проверкой platform bootstrap после завершения процесса.
  - **Проверка:**
    - Выполнить workflow в GitHub Actions для чистого commit и подтвердить, что все перечисленные команды присутствуют в log, generated worktree остаётся чистым, а единый required status проходит до merge.
    - Подтвердить, что настройка required status блокирует merge того же pull request при непройденном или отсутствующем результате workflow.
  - **Зависимости:** 6.1, 6.2, 6.3, 6.4.
  - **Вероятно затронутые файлы:** `.github/workflows/ci.yml`, `mise.toml`; настройка required status check хранится в GitHub.
  - **Оценка:** S (2 файла и настройка репозитория).

- [ ] 6.6 Провести многоосевой review реализации и устранить замечания до финальной проверки
  - **Критерии приёмки:**
    - Review проверяет корректность, читаемость, архитектуру, безопасность и производительность относительно proposal, spec, design и действующих ADR.
    - Устранены blocking замечания, отсутствуют unrelated refactors, dead code, debug output и дублирование предметных правил.
    - Отдельно подтверждены storage-neutral seam и независимая идентичность для будущего adapter, отсутствие sync-specific interface/metadata и отсутствие преждевременной модели связей, тегов, поиска или дневного выбора.
    - Предметный и прикладной modules, capability contracts и interfaces не зависят от Android SDK, путей, permissions или platform channels; Android-specific реализация локализована в host adapter и его evidence.
  - **Проверка:**
    - Применить `code-review-and-quality` к полному diff и повторить сфокусированные тесты затронутых замечаниями областей.
  - **Зависимости:** 6.5.
  - **Вероятно затронутые файлы:** Определяются найденными замечаниями; unrelated файлы не изменяются.
  - **Оценка:** M (до 5 файлов на один исправляемый набор замечаний).

- [ ] 6.7 Выполнить финальный checkpoint генерации, анализа, тестов, сборки и строгой валидации OpenSpec
  - **Критерии приёмки:**
    - Повторная генерация Riverpod, AutoRoute, Drift и локализации не создаёт дополнительного diff; generated providers, routes, все опубликованные schema snapshots, step-by-step migrations и остальные generated artifacts актуальны.
    - Полный анализ, unit/widget/integration tests и локальная сборка в release mode проходят, обязательный GitHub Actions status успешен для текущего commit, а ручные accessibility результаты и human review зафиксированы до merge; этот checkpoint не объявляет APK готовым к распространению и не требует production signing.
    - Change проходит строгую OpenSpec-валидацию и реализованное поведение не выходит за утверждённый scope.
  - **Проверка:**
    - Выполнить `flutter gen-l10n`, `dart run build_runner build --delete-conflicting-outputs` и убедиться в отсутствии дополнительного generated diff.
    - Выполнить `flutter test test/data/local/migrations test/intention/data/drift_intention_repository_persistence_test.dart`, `mise run check` и `flutter build apk --release`.
    - Выполнить `openspec validate manage-intentions --type change --strict`.
    - Подтвердить успешный required GitHub Actions status для текущего commit и наличие отдельного ручного TalkBack evidence.
  - **Зависимости:** 6.6.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.
