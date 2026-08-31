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

- [ ] 3.1 Сделать `IntentionId` закрытым UUID-value object со сменной политикой генерации и типизированным декодированием
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

- [ ] 3.2 Перевести существующий прикладной контракт на `IntentionId` без строковых обходов и зависимости от версии UUID
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

- [ ] 3.3 Проверить типобезопасную идентичность до реализации постоянного adapter
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
