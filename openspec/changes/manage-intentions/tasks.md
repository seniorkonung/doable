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

- [ ] 2.2 Определить закрытые commands, страничные типы каталога и storage-neutral seam `IntentionRepository`
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

- [ ] 2.3 Ввести `DiagnosticsSink` с безопасными структурированными событиями и проверяемым запретом пользовательских данных
  - **Критерии приёмки:**
    - Контракт поддерживает события bootstrap/migration, страничного чтения, подробного чтения и commands с типом операции, длительностью, page size, outcome, failure code и версиями схемы там, где они применимы.
    - Production adapter не записывает фильтр, названия, описания, UUID, cursors, SQL-параметры или полные database exceptions.
    - In-memory adapter позволяет проверять диагностику без внешней telemetry.
  - **Проверка:**
    - Выполнить `flutter test test/shared/diagnostics/diagnostics_sink_test.dart` с canary-значениями пользовательского текста и UUID.
  - **Зависимости:** 2.2.
  - **Вероятно затронутые файлы:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`, `test/support/in_memory_diagnostics_sink.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 2.4 Проверить предметный контракт до реализации постоянного adapter
  - **Критерии приёмки:**
    - Граничные Unicode-инварианты, identity, все варианты catalog query/page, command/result и завершение `watchById` после typed failure проходят unit tests.
    - Публичная seam не содержит storage-, transport-, sync- или Flutter-specific types и допускает замену adapter без изменения callers.
  - **Проверка:**
    - Выполнить `flutter test test/intention/domain test/intention/application test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 2.1, 2.2, 2.3.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## 3. Версионируемый lifecycle локальных данных

- [ ] 3.1 Связать Android production connection с фактически исключённым из backup внутренним каталогом
  - **Критерии приёмки:**
    - Production connection явно передаёт `getApplicationDocumentsDirectory` как `DriftNativeOptions.databaseDirectory` в `driftDatabase(name: 'doable', ...)`, открывает `root/app_flutter/doable.sqlite` в background isolate и не переносит Android-specific расположение в `AppDatabase` или предметные interfaces.
    - Android 12+ data extraction rules и Android 11- full backup rules исключают весь `root/app_flutter/` из cloud backup и device-to-device transfer, охватывая SQLite-файл, WAL/SHM и соседние служебные файлы; прежнее исключение только `database` domain не считается достаточным.
    - Contract test разрешает production directory/name в ожидаемые Android `domain/path`, структурно проверяет оба XML-файла и падает для несовпадающего domain или неполного пути.
  - **Проверка:**
    - Выполнить `flutter test test/data/local/database_connection_test.dart test/android/backup_policy_test.dart`.
    - Выполнить `flutter build apk --debug` и проверить подключение обоих наборов правил в merged manifest.
  - **Зависимости:** 1.1, 1.3.
  - **Вероятно затронутые файлы:** `lib/src/data/local/database_connection.dart`, `android/app/src/main/res/xml/data_extraction_rules.xml`, `android/app/src/main/res/xml/backup_rules.xml`, `test/data/local/database_connection_test.dart`, `test/android/backup_policy_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.2 Реализовать основную `AppDatabase` schema version 1, in-memory executor и защиту от более новой версии
  - **Критерии приёмки:**
    - Таблица хранит UUID `TEXT PRIMARY KEY`, исходное название, внутренний search key, nullable описание, готовность, архивное состояние и UTC timestamps без unique index по названию.
    - `AppDatabase` принимает `QueryExecutor`, не знает Android-путей, а in-memory executor позволяет проверять schema и migrations без platform host.
    - Текущая версия открывается с `foreign_keys = ON`, а более новая возвращает typed `incompatibleSchema` до feature query без записи, downgrade или destructive recovery.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs`.
    - Выполнить `flutter test test/data/local/app_database_test.dart test/data/local/database_version_compatibility_test.dart`.
  - **Зависимости:** 2.1, 3.1.
  - **Вероятно затронутые файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/app_database.g.dart`, `test/data/local/app_database_test.dart`, `test/data/local/database_version_compatibility_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 3.3 Добавить FTS5 trigram-индекс названий, cursor indexes и транзакционную проверку согласованности
  - **Критерии приёмки:**
    - Drift schema включает FTS5 external-content table с регистронезависимым trigram без удаления диакритики и timestamp/id indexes для обоих полей порядка.
    - Insert/update/delete triggers атомарно поддерживают FTS rows вместе с основной таблицей, а пользовательский title не заменяется внутренним search key.
    - Tests доказывают consistency основной таблицы и FTS после create/rename/delete, rollback и повторного открытия.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs` с `sqlite_module: [fts5]`.
    - Выполнить `flutter test test/data/local/intention_search_schema_test.dart`.
  - **Зависимости:** 3.2.
  - **Вероятно затронутые файлы:** `build.yaml`, `lib/src/data/local/app_database.drift`, `lib/src/data/local/app_database.dart`, `test/data/local/intention_search_schema_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 3.4 Зафиксировать schema snapshot версии 1 и generated step-by-step migration harness
  - **Критерии приёмки:**
    - Snapshot версии 1 точно содержит основную таблицу, indexes, FTS virtual table и triggers и становится исходной точкой опубликованных переходов.
    - Generated helper и harness позволяют добавлять один `fromNToN+1` и проверять прямой переход с любого опубликованного snapshot.
    - Повторные migration/code generation не создают дополнительного diff.
  - **Проверка:**
    - Выполнить `dart run drift_dev make-migrations`, generated schema tests и повторную генерацию без diff.
  - **Зависимости:** 3.3.
  - **Вероятно затронутые файлы:** `build.yaml`, `drift_schemas/drift_schema_v1.json`, `lib/src/data/local/app_database.steps.dart`, `test/data/local/migrations/schema_v1_test.dart`, `test/data/local/migrations/generated/schema.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.5 Реализовать атомарный migration orchestrator и доказать rollback при ошибке или прерывании
  - **Критерии приёмки:**
    - Orchestrator выполняет generated DDL/DML/FTS steps и integrity checks в одной write transaction без `VACUUM` или destructive fallback.
    - Fault injection откатывает таблицы, FTS, fixture-данные и marker версии, после чего повторное открытие начинает с прежней целостной версии.
    - File-backed interruption и более новая schema доказывают crash recovery и полный отказ от feature query, записи, downgrade или пересоздания.
  - **Проверка:**
    - Выполнить `flutter test test/data/local/migrations/atomic_migration_test.dart test/data/local/migrations/migration_interruption_test.dart test/data/local/migrations/newer_schema_test.dart`.
  - **Зависимости:** 3.2, 3.4.
  - **Вероятно затронутые файлы:** `lib/src/data/local/migrations/migration_strategy.dart`, `test/data/local/migrations/atomic_migration_test.dart`, `test/data/local/migrations/migration_interruption_test.dart`, `test/data/local/migrations/newer_schema_test.dart`, `test/support/migration_process_worker.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 3.6 Проверить версионируемую SQLite-основу и FTS consistency перед repository
  - **Критерии приёмки:**
    - In-memory и файловая schema version 1 согласуют основную таблицу, FTS, indexes, triggers и включённые foreign keys.
    - Snapshot, generated steps, rollback, crash recovery и incompatible-schema behavior проходят совместно.
  - **Проверка:**
    - Выполнить `flutter test test/data/local`.
    - Повторить Drift/code generation без дополнительного diff.
  - **Зависимости:** 3.3, 3.4, 3.5.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

## 4. Постоянный жизненный цикл через `IntentionRepository`

- [ ] 4.1 Реализовать создание намерения и реактивное чтение его подробных данных
  - **Критерии приёмки:**
    - Создание выдаёт новый UUID v4, принудительно создаёт активное неготовое намерение и атомарно записывает один UTC-момент в оба timestamp.
    - Одинаковые названия сохраняются как независимые сущности, а исходный title и внутренний search key записываются согласованно без изменения пользовательского текста.
    - `watchById` публикует начальный и последующие подтверждённые snapshots и возвращает отсутствие для неизвестного идентификатора.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_create_read_test.dart`.
  - **Зависимости:** 2.2, 2.3, 3.6.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/data/intention_mapper.dart`, `test/intention/data/drift_intention_repository_create_read_test.dart`, `test/support/repository_harness.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.2 Реализовать ограниченные cursor-страницы для трёх scopes и четырёх порядков
  - **Критерии приёмки:**
    - `getCatalogPage` возвращает не больше page size summaries и следующий cursor для active/archive/all без загрузки полного описания или offset; запрос без cursor возвращает sealed first-page variant с точным count, а запрос с cursor — continuation variant без count.
    - Created/updated × ascending/descending используют timestamp и `id ASC` как полный порядок и не дают пропусков или повторов при равных timestamps.
    - Структурно невалидный cursor, cursor другого scope/filter/order и page size вне диапазона 1–100 возвращают typed validation failure до storage query; изменение или отсутствие прежней граничной строки само по себе cursor не инвалидирует.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_catalog_page_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/data/intention_mapper.dart`, `test/intention/data/drift_intention_repository_catalog_page_test.dart`, `test/support/repository_harness.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.3 Реализовать FTS5-фильтр названия, точный count и large-fixture проверку
  - **Критерии приёмки:**
    - Фильтр выполняет буквальное регистронезависимое substring-сопоставление с trim, внутренними пробелами и различием `е`/`ё` и диакритики; search key короче трёх кодовых точек Unicode использует согласованный fallback, значение длиной 255 расширенных графемных кластеров принимается, а 256 возвращает typed validation failure до построения search key/FTS phrase, `COUNT` или чтения строк.
    - Count и строки первой страницы видят один read snapshot, фильтр и scope применяются до count, порядка и cursor boundary, а страницы с cursor не выполняют `COUNT`.
    - Fixture из 50 000 строк подтверждает FTS query plan для допустимых строк от трёх символов, timestamp/cursor indexes без фильтра, отсутствие SQL-операций для недопустимого фильтра, ровно один `COUNT` при последовательной загрузке всех порций одного query и materialization не больше page size для каждой operation.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_filter_test.dart test/intention/data/drift_intention_repository_large_catalog_test.dart`.
  - **Зависимости:** 4.2.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `test/intention/data/drift_intention_repository_filter_test.dart`, `test/intention/data/drift_intention_repository_large_catalog_test.dart`, `test/support/large_intention_fixture.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.4 Реализовать атомарное изменение названия и описания с точной семантикой `updatedAt`
  - **Критерии приёмки:**
    - Допустимые изменения активного и архивированного намерения сохраняют идентификатор, `createdAt` и архивное состояние.
    - Фактическое изменение обновляет `updatedAt`, а no-op возвращает текущий `IntentionSaved` без записи и вместе с отклонённым значением или failure оставляет оба прежних timestamp.
    - Rename атомарно обновляет исходный title, search key и FTS entry; failure не заменяет подтверждённый `watchById` snapshot или catalog summary.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_edit_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_edit_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.5 Реализовать отдельные commands включения и выключения готовности к действию без автоматической классификации
  - **Критерии приёмки:**
    - Новое намерение нельзя создать готовым, а готовность активного или архивированного намерения меняется только соответствующим явным command.
    - Изменение названия или описания никогда не меняет готовность побочным эффектом.
    - Фактическое переключение обновляет только `updatedAt`; повтор того же состояния является no-op.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Зависимости:** 4.1.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.6 Проверить создание, страничное чтение, фильтр, изменение и готовность через публичную seam
  - **Критерии приёмки:**
    - Все выполненные операции наблюдаемы через `IntentionRepository`, а тесты не обращаются к внутренним Drift rows для доказательства пользовательского поведения.
    - Три scope, четыре порядка, фильтр, exact count, pages и подробный stream показывают только подтверждённое состояние после каждого commit.
    - Для `createdAt`/`updatedAt` × ascending/descending сохранённый cursor того же query продолжает выдачу после создания и изменения до либо после boundary без требования неизменной граничной строки, пропусков или повторов.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_create_read_test.dart test/intention/data/drift_intention_repository_catalog_page_test.dart test/intention/data/drift_intention_repository_filter_test.dart test/intention/data/drift_intention_repository_edit_test.dart test/intention/data/drift_intention_repository_readiness_test.dart`.
  - **Зависимости:** 4.1, 4.2, 4.3, 4.4, 4.5.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 4.7 Реализовать архивирование и восстановление намерения без изменения остальных предметных данных
  - **Критерии приёмки:**
    - Архивирование исключает намерение из active, включает в archive и сохраняет в all, не меняя title, description, identity или готовность.
    - Восстановление выполняет обратное изменение scopes с теми же данными.
    - Каждое фактическое переключение атомарно обновляет `updatedAt`, а no-op не изменяет timestamps.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_archive_test.dart`.
  - **Зависимости:** 4.2.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_archive_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.8 Реализовать физическое удаление активного или архивированного несвязанного намерения как отдельный command
  - **Критерии приёмки:**
    - Удаление не требует архивирования, возвращает `IntentionDeleted` только после commit, исключает сущность из всех scopes и FTS, а подробный поток публикует отсутствие.
    - Отсутствующее намерение возвращает typed not-found, failure не скрывает запись, а удалённый UUID никогда не переиспользуется новым созданием.
    - Repository оставляет транзакционную точку проверки блокирующих зависимостей для последующих change связей, не моделируя связи заранее.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_delete_test.dart`.
  - **Зависимости:** 4.2.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/application/intention_command.dart`, `test/intention/data/drift_intention_repository_delete_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 4.9 Завершить транзакционную классификацию storage failures и безопасную диагностику всех repository operations
  - **Критерии приёмки:**
    - Validation, not-found, UUID conflict, unavailable и corruption outcomes стабильно преобразуются в typed failures без утечки database exceptions.
    - Ошибки до commit не публикуют промежуточные snapshots и сохраняют возможность повторить command.
    - Ошибка страницы возвращает typed failure в `Result`, а ошибка `watchById` завершает stream одной typed failure; raw Drift/SQLite/FTS exception не пересекает seam.
    - Диагностика страницы содержит только operation, duration, page size, outcome и safe code без фильтра, UUID, cursor или SQL parameters.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_failure_test.dart`.
    - Выполнить `flutter test test/shared/diagnostics`.
  - **Зависимости:** 2.3, 4.3, 4.4, 4.5, 4.7, 4.8.
  - **Вероятно затронутые файлы:** `lib/src/intention/data/drift_intention_repository.dart`, `lib/src/intention/data/storage_failure_mapper.dart`, `test/intention/data/drift_intention_repository_failure_test.dart`, `test/support/failing_query_executor.dart`.
  - **Оценка:** M (4 файла).

- [ ] 4.10 Проверить полный repository lifecycle и отсутствие регрессий хранилища
  - **Критерии приёмки:**
    - Создание, три scope, четыре порядка, фильтр, cursor pages, exact count, изменение, готовность, архивирование, восстановление и удаление проходят через одну seam.
    - Ошибочные, отклонённые и no-op operations сохраняют подтверждённые данные и timestamps.
  - **Проверка:**
    - Выполнить `flutter test test/intention test/data/local test/shared/diagnostics`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 4.6, 4.7, 4.8, 4.9.
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
  - **Зависимости:** 1.2, 3.6, 4.10.
  - **Вероятно затронутые файлы:** `lib/main.dart`, `lib/src/app/bootstrap/bootstrap_providers.dart`, `lib/src/app/bootstrap/bootstrap_view_model.dart`, `lib/src/app/app.dart`, `test/app/bootstrap/app_bootstrap_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.2 Настроить `MaterialApp.router` и generated типизированные AutoRoute-маршруты для внутренних переходов
  - **Критерии приёмки:**
    - Generated routes для каталога, создания и подробного просмотра требуют предметный `IntentionId` там, где он применим, и возвращают необязательный typed `IntentionCommandSuccess` исходному каталогу.
    - Внутренние переходы используют только generated route objects; строковые `pushNamed`, `replaceNamed`, `navigateNamed`, route names и ручная сборка path отсутствуют в прикладном коде.
    - Внешняя схема URI, строковый path-параметр, deep-link adapter и platform-регистрация внешних маршрутов отсутствуют; маршрут подробного просмотра не принимает недоверенную строку и не требует routing-level parser идентификатора.
  - **Проверка:**
    - Выполнить `dart run build_runner build --delete-conflicting-outputs` и `flutter analyze`, чтобы проверить generated route types и обязательные аргументы.
    - Выполнить `flutter test test/app/routing` для переходов из трёх scopes, обязательного `IntentionId`, typed saved/deleted result и возврата в исходный query state.
    - Выполнить `rg -n --glob '!*.gr.dart' "pushNamed|replaceNamed|navigateNamed" lib` и убедиться, что строковая навигация отсутствует.
  - **Зависимости:** 5.1.
  - **Вероятно затронутые файлы:** `lib/src/app/app.dart`, `lib/src/app/routing/app_router.dart`, `lib/src/app/routing/app_router.gr.dart`, `test/app/routing/app_router_test.dart`, `test/support/app_harness.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.3 Реализовать query state каталога с тремя scopes, фильтром, точным count и четырьмя порядками
  - **Критерии приёмки:**
    - Generated Catalog `AsyncNotifier` хранит active/archive/all, title filter, created/updated × ascending/descending, накопленные pages, total count первой страницы и query generation; defaults равны active и created descending, а нормализованный фильтр длиннее 255 расширенных графемных кластеров получает локализованную validation error, сохраняется для исправления и не вызывает repository.
    - Debounce берётся из подменяемой `CatalogPagingPolicy`, поздний результат старого фильтра игнорируется, а смена scope сохраняет filter/order, но сбрасывает pages и scroll наверх.
    - View различает initial loading/data/empty/no-matches/failure, показывает exact count и доступные summary/archived states без опоры только на цвет.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/catalog/catalog_query_test.dart test/intention/presentation/catalog/catalog_view_test.dart` через `ProviderContainer` для трёх scopes, четырёх порядков, trim/case filter, границ фильтра 255/256 с отсутствием repository call при превышении, debounce, stale results, count и initial states.
  - **Зависимости:** 5.2.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/catalog/catalog_view_model.dart`, `lib/src/intention/presentation/catalog/catalog_state.dart`, `lib/src/intention/presentation/catalog/catalog_view.dart`, `test/intention/presentation/catalog/catalog_query_test.dart`, `test/intention/presentation/catalog/catalog_view_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.4 Реализовать автоматическую подгрузку и согласование command results без потери позиции каталога
  - **Критерии приёмки:**
    - `CatalogPagingPolicy` задаёт production `pageSize = 100` и `prefetchRemaining = 30`, принимает только `pageSize` 1–100 и `prefetchRemaining` от 0 до значения меньше `pageSize`, тесты подменяют их допустимыми малыми значениями, а `ScrollController` запускает не больше одной следующей страницы у threshold; success continuation дедуплицирует summaries, добавляет page и сохраняет count первой страницы, конец прекращает запросы, а failure сохраняет items и показывает inline retry.
    - При незавершённой выдаче typed saved result вставляется или перемещается только не позже сохранённой boundary, а summary после неё либо вне query не показывается до своей порции; при завершённой выдаче совпадающий summary размещается в любом правильном месте. Cursor сохраняется, count обновляется по membership transition, а deleted result удаляет summary.
    - `ListView.builder`, `PageStorageKey` и visual anchor по первому видимому `IntentionId` сохраняют accumulated state и позицию при вставке, перемещении или исключении summary без перечитывания прежних pages и без сброса к началу.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/catalog/catalog_paging_test.dart test/intention/presentation/catalog/catalog_scroll_state_test.dart` с параметризованной матрицей create/edit для `createdAt`/`updatedAt` × ascending/descending после нескольких порций, сохранением count на continuation pages, его изменением только по membership transition, последующей подгрузкой, cursor, дедупликацией и visual anchor.
  - **Зависимости:** 5.3.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/catalog/catalog_view_model.dart`, `lib/src/intention/presentation/catalog/catalog_state.dart`, `lib/src/intention/presentation/catalog/catalog_view.dart`, `test/intention/presentation/catalog/catalog_paging_test.dart`, `test/intention/presentation/catalog/catalog_scroll_state_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.5 Проверить bootstrap, routing и каталог как первый читаемый пользовательский срез
  - **Критерии приёмки:**
    - Приложение проходит от bootstrap до трёх scopes каталога, фильтра, count и автоматической подгрузки, а retry восстанавливает initial или следующую page после моделируемой ошибки.
    - Более новая версия хранилища оставляет feature routes и repository недоступными, показывает локализованное требование обновить приложение без retry и не изменяет database.
    - Переход к намерению из любого scope и возврат сохраняют query, loaded pages и visual anchor; typed result сохраняет непрерывный глобальный порядок и не показывает намерение раньше незагруженных предшественников.
  - **Проверка:**
    - Выполнить `flutter test test/app test/intention/presentation/catalog`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 5.1, 5.2, 5.3, 5.4.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 5.6 Реализовать общий presentation-модуль для эксклюзивного выполнения одной асинхронной операции
  - **Критерии приёмки:**
    - `ExclusiveOperation` предоставляет одну синхронную операцию `start`: первый вызов резервирует экземпляр и возвращает принятое выполнение с его `Future`, а вызов занятого экземпляра возвращает отдельный outcome `alreadyRunning`, не вызывая и не ставя в очередь второе действие.
    - Gate освобождается после success, failure или неожиданной ошибки принятого действия; общий неизменяемый `OperationState<TResult>` предоставляет ViewModels статусы `idle`, `running`, `succeeded` и `failed`, но module не знает о предметных сущностях, repository, локализации или навигации.
    - Разные экземпляры выполняются независимо; scope экземпляра задаёт владеющая ViewModel, а experimental Riverpod Mutations и глобальный registry операций не используются.
  - **Проверка:**
    - Выполнить `flutter test test/shared/presentation/exclusive_operation_test.dart` для принятого и отклонённого outcomes, двух быстрых вызовов, отсутствия отложенного второго запуска, освобождения после success/failure/exception и независимых экземпляров.
  - **Зависимости:** 1.1.
  - **Вероятно затронутые файлы:** `lib/src/shared/presentation/exclusive_operation.dart`, `test/shared/presentation/exclusive_operation_test.dart`.
  - **Оценка:** S (2 файла).

- [ ] 5.7 Реализовать пользовательский поток создания намерения без optimistic сохранения
  - **Критерии приёмки:**
    - Generated class-based `@riverpod` Editor ViewModel и форма используют общую предметную Unicode-валидацию, локализуют ошибки и не предлагают включить готовность при создании.
    - Отдельный для экземпляра формы `ExclusiveOperation` делает повторную отправку недоступной, защитно не запускает и не ставит её в очередь во время `running`, публикует одноразовый success event для навигации и сохраняет введённые данные для явного retry при failure.
    - Typed `IntentionSaved` возвращается каталогу, который корректирует count и показывает summary сразу только внутри загруженной boundary либо после подтверждённого конца выдачи; при `createdAt ascending` новое намерение за незагруженными совпадениями остаётся вне префикса до своей порции. Пользовательский текст не переводится и не преобразуется.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/editor/create_intention_test.dart` с пробелами, одинаковыми названиями, Unicode-границами, сохранением полей, `createdAt` ascending/descending после нескольких порций, повторной доступностью отправки после failure и double-submit без второго repository command.
  - **Зависимости:** 4.1, 5.4, 5.6.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `lib/src/intention/presentation/editor/intention_editor_view.dart`, `lib/src/intention/presentation/editor/intention_form.dart`, `test/intention/presentation/editor/create_intention_test.dart`, `test/support/fake_intention_repository.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.8 Реализовать подробный просмотр и изменение названия и описания активного или архивированного намерения
  - **Критерии приёмки:**
    - Parameterized `watchById` provider различает initial loading, data, not-found и typed failure; targeted retry создаёт новую подписку, а automatic disposal корректно завершает прежнюю.
    - Details ViewModel использует один mutation gate на `IntentionId`, оставляет подтверждённый snapshot видимым и не допускает второй command того же намерения, не блокируя другое.
    - Активное или архивированное намерение редактируется без восстановления; success возвращает typed saved result каталогу, а cancel/validation/storage failure сохраняют прежние данные.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/intention_details_read_states_test.dart test/intention/presentation/details/edit_intention_test.dart` для initial loading, data, not-found, read failure, targeted retry, recovery, disposal/re-entry, active/archive, no-op, validation и storage failure.
  - **Зависимости:** 4.4, 5.2, 5.6, 5.7.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `lib/src/intention/presentation/editor/intention_editor_view.dart`, `test/intention/presentation/details/intention_details_read_states_test.dart`, `test/intention/presentation/details/edit_intention_test.dart`.
  - **Оценка:** M (5 файлов).

- [ ] 5.9 Реализовать явное подтверждение включения и обратимое выключение готовности к действию
  - **Критерии приёмки:**
    - Перед включением локализованный dialog объясняет оба критерия: полную выполнимость за один день и операционную понятность; отмена не запускает command.
    - Выключение остаётся отдельным явным действием, а название или описание не запускают автоматическую классификацию.
    - Общий для `IntentionId` mutation `OperationState` указывает операцию готовности, предотвращает double-submit и любое другое изменение до результата, а затем публикует доступный одноразовый success/failure event, сохраняя последний подтверждённый snapshot.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/readiness_test.dart` для confirm/cancel, enable/disable, failure и semantics.
  - **Зависимости:** 4.5, 5.8.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/readiness_dialog.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/readiness_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 5.10 Проверить создание, подробный просмотр, изменение и готовность как законченный редактируемый срез
  - **Критерии приёмки:**
    - Пользователь может создать намерение, открыть его, изменить текст, включить и выключить готовность с согласованным обновлением каталога.
    - Отмены и моделируемые failures не показывают несохранённое состояние как подтверждённое.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/editor test/intention/presentation/details`.
  - **Зависимости:** 5.7, 5.8, 5.9.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.

- [ ] 5.11 Реализовать архивирование активного намерения и восстановление архивированного намерения в UI
  - **Критерии приёмки:**
    - Доступная операция зависит от текущего архивного состояния и не представляется как выполнение или удаление.
    - Typed success согласует принадлежность active/archive/all, count и позицию summary с загруженной boundary без изменения текста и готовности; failure оставляет подробный snapshot и даёт повторить операцию.
    - Архивированное намерение остаётся доступным для просмотра и изменения.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/archive_restore_test.dart` для active/archive, success, failure и stream update.
  - **Зависимости:** 4.7, 5.8.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/archive_restore_test.dart`.
  - **Оценка:** M (3 файла).

- [ ] 5.12 Реализовать отдельное необратимое удаление активного или архивированного намерения с подтверждением
  - **Критерии приёмки:**
    - Delete недоступен как случайный побочный эффект архивирования и запускается только после локализованного явного подтверждения необратимости.
    - Отмена не выполняет command; typed success закрывает подробный экран и удаляет summary из всех scopes с обновлением count; failure сохраняет запись и предоставляет retry.
    - Dialog и результат операции имеют корректные semantics и не раскрывают пользовательский текст в diagnostics.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation/details/delete_intention_test.dart` для active/archive, confirm/cancel, success/failure и double-submit.
  - **Зависимости:** 4.8, 4.9, 5.8.
  - **Вероятно затронутые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/delete_confirmation_dialog.dart`, `lib/src/intention/presentation/details/intention_details_view.dart`, `test/intention/presentation/details/delete_intention_test.dart`.
  - **Оценка:** M (4 файла).

- [ ] 5.13 Проверить полный пользовательский жизненный цикл намерения через Riverpod overrides на fake repository
  - **Критерии приёмки:**
    - Widget tests покрывают каталог с paging/filter/count/sort, boundary-согласование create/edit во всех четырёх порядках, последующую подгрузку, сохранение visual anchor, подробности, готовность, архивирование, восстановление и удаление через override только `IntentionRepository`.
    - Parameterized mutation tests покрывают running/success/failure, одноразовые events, общий gate одного `IntentionId`, независимость другого и отсутствие controls после delete.
    - Fake adapter соблюдает page bounds/cursor, возвращает count только в sealed first-page variant и continuation без count, а также typed saved/deleted payloads, page failure через `Result` и завершение только `watchById` после typed stream failure.
  - **Проверка:**
    - Выполнить `flutter test test/intention/presentation test/app`.
    - Выполнить `flutter analyze`.
  - **Зависимости:** 5.10, 5.11, 5.12.
  - **Вероятно затронутые файлы:** `test/intention/presentation/details/mutation_serialization_test.dart`.
  - **Оценка:** S (1 файл).

## 6. Интеграция и production-readiness

- [ ] 6.1 Проверить локальную долговечность через повторное открытие file-backed SQLite
  - **Критерии приёмки:**
    - Первый независимый object graph создаёт активные и архивированные намерения, изменяет title/готовность и фиксирует expected identities, timestamps, scopes, filter results и count.
    - Второй graph открывает тот же файл и восстанавливает данные, FTS-фильтр, cursor pages и exact count только через публичную seam; FTS consistency подтверждена.
    - Удаление сохраняется после третьего открытия, а прежние database/repository objects, in-memory executor, UI и `ProviderContainer` не переиспользуются.
  - **Проверка:**
    - Выполнить `flutter test test/intention/data/drift_intention_repository_persistence_test.dart`.
  - **Зависимости:** 3.6, 4.10.
  - **Вероятно затронутые файлы:** `test/intention/data/drift_intention_repository_persistence_test.dart`, `test/support/repository_harness.dart`.
  - **Оценка:** S (2 файла).

- [ ] 6.2 Закрыть русскую, английскую и fallback локализацию всех системных строк без изменения пользовательского текста
  - **Критерии приёмки:**
    - Три scopes, filter/count/sort, initial/next-page states, включая ошибку превышения 255 расширенных графемных кластеров фильтра, validation, commands, критерии действия, подтверждения и semantics имеют содержательные `en` и `ru` значения.
    - Локали `ru` и `en` показывают соответствующие системные строки, любая другая локаль использует `en`.
    - Сохранённые названия и описания остаются посимвольно одинаковыми при смене локали и выводятся только как plain text.
  - **Проверка:**
    - Выполнить `flutter gen-l10n`.
    - Выполнить `flutter test test/app/localization test/intention/presentation/localization_test.dart`.
  - **Зависимости:** 5.13.
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
  - **Зависимости:** 5.13, 6.2.
  - **Вероятно затронутые файлы:** `test/accessibility/intention_semantics_test.dart`, `test/accessibility/intention_text_scale_test.dart`, `lib/src/shared/ui/accessible_operation_feedback.dart`.
  - **Оценка:** M (3 файла).

- [ ] 6.4 Проверить Android privacy adapter в release mode и полноту безопасной диагностики
  - **Критерии приёмки:**
    - Release-mode APK не запрашивает `INTERNET` или внешнее хранилище, production connection разрешается в `root/app_flutter/doable.sqlite`, а оба набора backup rules исключают весь `root/app_flutter/` вместе с SQLite WAL/SHM и соседними служебными файлами из cloud backup и device-to-device transfer.
    - События bootstrap, migration, page/detail reads и commands содержат только разрешённые поля; canary-тесты не обнаруживают filter, title, description, UUID, cursor, SQL parameter или полный exception.
    - Проверка untrusted text и FTS query syntax не выявляет обхода лимита фильтра, literal substring semantics, SQL/FTS injection, markup rendering или destructive recovery; фильтр из 256 расширенных графемных кластеров отклоняется без SQLite/FTS/`COUNT`.
  - **Проверка:**
    - Выполнить `flutter build apk --release` и проверить permissions через `apkanalyzer manifest permissions build/app/outputs/flutter-apk/app-release.apk`.
    - Выполнить `flutter test test/data/local/database_connection_test.dart test/android/backup_policy_test.dart`.
    - Выполнить `flutter test test/shared/diagnostics test/security`.
  - **Зависимости:** 3.1, 4.9, 5.13, 6.1.
  - **Вероятно затронутые файлы:** `test/security/privacy_boundary_test.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`.
  - **Оценка:** S (2 файла).

- [ ] 6.5 Настроить обязательный GitHub Actions PR gate для воспроизводимой проверки change
  - **Критерии приёмки:**
    - Workflow запускается для pull request и релевантного push из чистого checkout на Linux runner, устанавливает только явно зафиксированные версии используемых инструментов, разрешает зависимости без изменения `pubspec.lock`, а его статус настроен как обязательная проверка защищённой основной ветки.
    - Gate повторяет `flutter gen-l10n`, Riverpod/AutoRoute/Drift code generation и Drift schema/migration generation, после чего требует пустой `git status --porcelain`, включая отсутствие новых незакоммиченных generated files и schema snapshots.
    - Gate выполняет `mise run check`, large-catalog/query-plan, file-backed и migration/FTS tests, release APK/manifest и OpenSpec; TalkBack остаётся отдельным ручным evidence без device/emulator job.
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
    - Подтверждены bounded catalog/FTS/count/cursor, storage-neutral platform-independent seam, независимая identity и отсутствие преждевременных sync, tags, full-text/ranking, links или daily-choice contracts.
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
    - Выполнить `flutter test test/data/local/migrations test/intention/data/drift_intention_repository_large_catalog_test.dart test/intention/data/drift_intention_repository_persistence_test.dart`, `mise run check` и `flutter build apk --release`.
    - Выполнить `openspec validate manage-intentions --type change --strict`.
    - Подтвердить успешный required GitHub Actions status для текущего commit и наличие отдельного ручного TalkBack evidence.
  - **Зависимости:** 6.6.
  - **Вероятно затронутые файлы:** Нет, только проверка.
  - **Оценка:** XS.
