## Контекст

Doable остаётся Flutter-приложением с Android host без постоянного пользовательского хранилища. В рамках начатого change уже завершены предметный и прикладной контракты Phase 2 и типобезопасная граница идентичности Phase 3: `IntentionId` представляет канонический ненулевой UUID независимо от версии, новые значения создаются внедряемым UUIDv7-generator, а сохранённые представления восстанавливаются через типизированное декодирование; Drift/SQLite adapter ещё не реализован. Зафиксированный стек — Flutter 3.47.1 stable и Dart 3.13.1. Design ограничивают действующие ADR-0002 о Drift/SQLite, ADR-0003 о типобезопасной UUID-идентичности со сменной политикой генерации, ADR-0004 о локальном Android storage и ADR-0005 о глубоком модуле с ограниченными снимками каталога. ADR-0005 supersedes ADR-0001, который остаётся историческим контекстом и больше не задаёт действующий repository contract.

`manage-intentions` — первая законченная пользовательская вертикаль. Она должна провести правила намерения через платформонезависимые Flutter/Dart modules и прикладное состояние, а capability `local-data-lifecycle` — владеть общим открытием, миграцией и локальной долговечностью данных. Change не должен преждевременно моделировать долговременные связи, дневной выбор или синхронизацию, но создаваемая основа должна допускать последующее расширение SQLite-схемы, другой platform host и внутреннюю композицию локального adapter с будущим удалённым источником без зависимости UI от способа хранения.

Основные заинтересованные стороны:

- пользователь, который доверяет приложению личные названия и описания намерений и ожидает их сохранности;
- разработчики следующих change, которым нужны устойчивая идентичность намерения, проверяемые миграции и небольшая прикладная interface;
- тестирование и сопровождение, которым нужны воспроизводимые ошибки, доступные состояния интерфейса и диагностика без раскрытия пользовательского текста.

Технические решения сверены с первичными источниками: рекомендациями Flutter по [разделению UI и data layer, MVVM, repository, dependency injection и тестированию](https://docs.flutter.dev/app-architecture/recommendations) и [переиспользуемым асинхронным commands с защитой от повторного запуска](https://docs.flutter.dev/app-architecture/design-patterns/command), документацией Flutter по [локализации](https://docs.flutter.dev/ui/internationalization), [навигации](https://docs.flutter.dev/ui/navigation) и [доступности](https://docs.flutter.dev/ui/accessibility), официальной документацией Riverpod по [providers](https://riverpod.dev/docs/concepts2/providers), [ProviderScope и ProviderContainer](https://riverpod.dev/docs/concepts2/containers), [тестированию](https://riverpod.dev/docs/how_to/testing), [code generation](https://riverpod.dev/docs/concepts/about_code_generation) и [automatic retry](https://riverpod.dev/docs/concepts2/retry), официальной документацией AutoRoute по [generated типизированным маршрутам, nested navigation, deep links и declarative navigation](https://pub.dev/documentation/auto_route/latest/index.html), документацией Drift по [настройке](https://drift.simonbinder.eu/setup/), [транзакциям](https://drift.simonbinder.eu/dart_api/transactions/), [пошаговым миграциям](https://drift.simonbinder.eu/migrations/step_by_step/), [Migrator API](https://drift.simonbinder.eu/migrations/api/), [тестированию миграций и runtime-проверке схемы](https://drift.simonbinder.eu/migrations/tests/#verifying-a-database-schema-at-runtime), официальной процедурой SQLite для [произвольного изменения таблиц внутри транзакции](https://sqlite.org/lang_altertable.html#making_other_kinds_of_table_schema_changes), а также рекомендациями Android по [внутреннему хранилищу](https://developer.android.com/privacy-and-security/security-best-practices#store-data-safely) и [управлению резервными копиями](https://developer.android.com/identity/data/autobackup).

## Цели / Не-цели

**Цели:**

- реализовать полный жизненный цикл намерения с одной реализацией предметных инвариантов для всех точек входа;
- сделать подтверждённое состояние текущего локального SQLite adapter единственным источником истины и не показывать незафиксированные записи как сохранённые;
- отделить Flutter-представление, прикладное состояние и постоянное хранение через небольшие проверяемые interfaces;
- сохранить storage-neutral seam управления намерениями и независимую от SQLite типобезопасную идентичность, не вводя преждевременный sync interface;
- не позволять произвольной строке, nil UUID или некорректному представлению пересечь проверяемую границу и стать `IntentionId`;
- обеспечить ограниченное чтение каталога с тремя охватами, точным количеством совпадений, фильтрацией по названию и курсорной подгрузкой без материализации всех намерений;
- сохранять уже загруженный каталог и позицию прокрутки при внутренних переходах, отражая подтверждённые изменения через типизированные результаты commands;
- заложить версионируемую реляционную схему с атомарными пошаговыми миграциями от каждой опубликованной версии и проверяемым отказом от несовместимого downgrade;
- поддержать русскую и английскую локализацию, системный экранный диктор, системное масштабирование текста и безопасную диагностику с первого release capability.

**Не-цели:**

- моделировать долговременные связи, связь «я сегодня», пути выбора, теги, ранжированный или полнотекстовый поиск либо выполнение;
- добавлять учётную запись, cloud backup, device-to-device transfer, экспорт, удалённое хранилище, transport, разрешение конфликтов, само поведение синхронизации, сетевой API, аналитику или внешний crash-reporting;
- реализовывать и квалифицировать host adapters, сборки и platform-specific recovery для платформ, отличных от Android; текущий change проверяет только Android delivery;
- регистрировать внешнюю схему URI, принимать deep links или определять для них формат, platform integration, ожидание bootstrap и back stack;
- определять окончательную визуальную композицию экранов и богатую навигацию по будущему графу;
- добавлять прикладную аутентификацию, отдельный PIN-код или шифрование базы на уровне приложения;
- публиковать или распространять приложение, готовить store listing, настраивать production signing keys либо инфраструктуру секретов сборки; release mode нужен только для автоматизированной CI-проверки и локальной проверки Android-поведения и manifest;
- выполнять длительные фоновые миграции после открытия feature routes: текущая стратегия завершает совместимое обновление внутри bootstrap, а необходимость поэтапного backfill должна быть спроектирована отдельным change до появления такого объёма данных;
- превращать каждую простую операцию над намерением в отдельный shallow module или заранее создавать универсальные abstractions для ещё не существующих сущностей.

## Решения

### 1. Один офлайн-контейнер и облегчённое C4-представление

Architecture отделяет платформонезависимые Flutter/Dart modules от platform host. В текущем change квалифицируется один host adapter — Android — и принадлежащий установке SQLite-файл `doable.sqlite` в каталоге `root/app_flutter/` внутреннего app-specific storage. Сетевых контейнеров и внешних сервисов нет; поддержка другого host не заявляется без его сборки и platform evidence.

```text
+----------------+        использует        +----------------------------------+
|   Пользователь | -----------------------> | Doable                           |
+----------------+                          | Flutter/Dart modules              |
                                            |                                  |
+----------------+  локаль, экранный        |  +----------------------------+  |
| Platform host  |  диктор, scale, lifecycle|  | UI и управление намерениями |  |
+----------------+ -----------------------> |  +----------------------------+  |
                                            |               |                  |
                                            |               | читает / пишет    |
                                            |               v                  |
                                            |  +----------------------------+  |
                                            |  | SQLite                      |  |
                                            |  | внутреннее хранилище app    |  |
                                            |  +----------------------------+  |
                                            +----------------------------------+
```

Внутри Flutter-контейнера ответственность разделяется на модули, а не на слои-переадресаторы:

```text
Контейнер: Flutter-приложение

+----------------------------------------------------------------------------+
| Composition root: bootstrap + ProviderScope + router                       |
|                                                                            |
|  +----------------------+       события       +-------------------------+  |
|  | Views                | -------------------> | Riverpod ViewModels     |  |
|  | Material + Semantics | <------------------- | неизменяемое UI state   |  |
|  +----------------------+       состояние      +------------+------------+  |
|          ^                                                   |               |
|          | строки gen_l10n                                  | interface     |
|  +-------+------------+                                     v               |
|  | Локализация        |                         +-------------------------+  |
|  | en, ru, en fallback|                         | IntentionRepository     |  |
|  +--------------------+                         | правила + Result        |  |
|                                                 +------------+------------+  |
|                                                              |               |
|                                                              v               |
|                                                 +-------------------------+  |
|                                                 | Drift / AppDatabase     |  |
|                                                 | schema + migrations     |  |
|                                                 +------------+------------+  |
|                                                              |               |
+--------------------------------------------------------------|---------------+
                                                               v
                                                  +-------------------------+
                                                  | SQLite во внутреннем    |
                                                  | хранилище platform host |
                                                  +-------------------------+
```

Текущий `Platform host` — Android. Для локали, доступности и lifecycle Flutter уже предоставляет platform-neutral interfaces, а backup/manifest остаются конфигурацией host adapter; отдельный `PlatformPort` ради одного adapter не вводится. Поддержка следующей платформы потребует собственной storage/backup-конфигурации и platform evidence, но не изменения capability или предметных interfaces.

- View знает только generated provider собственной ViewModel; widgets не обращаются к repository или Drift.
- ViewModel реализуется class-based Riverpod Notifier, формирует неизменяемое UI state и выполняет типизированные `IntentionCommand` через repository.
- `IntentionRepository` является глубоким module: за небольшой interface скрыты нормализация, инварианты, транзакции, преобразование строк базы и классификация ошибок.
- Drift остаётся implementation detail repository. Тесты repository подменяют его `QueryExecutor` локальной in-memory SQLite, а тесты ViewModel используют `ProviderContainer` с override на fake adapter `IntentionRepository`.
- Корневой `ProviderScope` владеет container, связывает providers и закрывает ресурсы через `ref.onDispose`; ни database singleton, ни service locator из прикладного кода не используются.

Альтернатива — разнести приложение только по техническим каталогам `screens`, `models`, `services` — отклонена: правила одной capability пришлось бы искать и менять в нескольких несвязанных местах. Отдельный use case на каждую CRUD-операцию также отклонён как shallow modules, почти полностью повторяющие interface repository.

### 2. Глубокий модуль управления намерениями с ограниченным чтением каталога

В соответствии с ADR-0005 граница глубокого модуля из ADR-0001 сохраняется, а прежнее наблюдение всего каталога заменяется ограниченными snapshot-запросами. ADR-0001 полностью superseded и не является параллельным источником repository contract.

Внешняя interface модуля остаётся предметной и не раскрывает классы Drift:

```dart
abstract interface class IntentionRepository {
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  );
  Stream<Result<Intention?>> watchById(IntentionId id);
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command);
}

sealed class IntentionCatalogPage {
  const IntentionCatalogPage({
    required this.items,
    required this.nextCursor,
  });

  final List<IntentionSummary> items;
  final IntentionCatalogCursor? nextCursor;
}

final class IntentionCatalogFirstPage extends IntentionCatalogPage {
  const IntentionCatalogFirstPage({
    required super.items,
    required this.totalCount,
    required super.nextCursor,
  });

  final int totalCount;
}

final class IntentionCatalogContinuationPage extends IntentionCatalogPage {
  const IntentionCatalogContinuationPage({
    required super.items,
    required super.nextCursor,
  });
}

sealed class IntentionCommandSuccess {
  const IntentionCommandSuccess();
}

final class IntentionSaved extends IntentionCommandSuccess {
  const IntentionSaved(this.intention);
  final Intention intention;
}

final class IntentionDeleted extends IntentionCommandSuccess {
  const IntentionDeleted(this.id);
  final IntentionId id;
}
```

`IntentionScope` различает активные, архивированные и все существующие намерения. `IntentionCatalogOrder` состоит из выбранного поля — `createdAt` или `updatedAt` — и направления `ascending` или `descending`; начальное значение равно `createdAt descending`. Factory `IntentionCatalogQuery` принимает nullable пользовательскую строку фильтра, но после нормализации хранит только `IntentionTitleFilter?`: `null` представляет отсутствие фильтра, а закрытый конструктор `IntentionTitleFilter` не позволяет непустому допустимому значению снова стать произвольной, пустой или слишком длинной строкой. Query также содержит scope, порядок, проверяемый размер порции от 1 до 100 включительно и необязательный `IntentionCatalogCursor`, полученный из предыдущей страницы того же запроса. Query types предоставляют storage-neutral правила проверки принадлежности `IntentionSummary` текущему scope/filter и сравнения двух summaries в полном выбранном порядке; Catalog ViewModel использует те же правила для command results, а repository contract tests доказывают их соответствие SQL-выдаче для проекций, вычисленных текущей сборкой. Допустимое отличие исторической проекции после обновления Unicode-данных относится к явно принятому поисковому дрейфу и может сохраняться до следующей записи строки. `IntentionTitleFilter` не раскрывает Drift, SQLite, FTS или выбранную локальным adapter стратегию поиска.

Cursor остаётся storage-neutral opaque interface без публичных полей и фабрик: caller только возвращает полученный экземпляр repository и не строит его из SQLite row, offset или SQL-выражения. Каждый экземпляр конкретного adapter при создании получает собственный приватный process-local owner token, а каждый выданный им cursor содержит тот же token вместе с нормализованными параметрами запроса и граничной парой выбранной временной метки и `IntentionId`. До обращения к storage adapter требует идентичности owner token и совпадения параметров. Поэтому cursor любого другого экземпляра adapter возвращает validation failure даже тогда, когда оба экземпляра заимствуют один `AppDatabase`; token не сериализуется, не сохраняется в SQLite, не раскрывается через публичную seam и не удерживает ссылку на database.

Запрос с `cursor: null` всегда начинает новую независимую цепочку с первой страницы. Повторное начало на том же экземпляре adapter создаёт новый cursor с тем же owner token и новой boundary; несколько таких цепочек могут существовать одновременно. Каждое успешное продолжение возвращает новый cursor следующей boundary либо `null` после конца выдачи. Подтверждённое создание, изменение или удаление при неизменных параметрах запроса не инвалидирует уже выданную value boundary, однако пересоздание repository adapter инвалидирует его cursors и требует начать с первой страницы. Database-scoped identity отклонена, потому что обмен cursors между экземплярами repository не является требованием interface и потребовал бы отдельной общей seam; сохраняемая в SQLite identity также отклонена как не требуемая schema metadata для process-local cursor.

`IntentionCatalogPage` является sealed-контрактом и всегда содержит не больше запрошенного ограниченного размера и cursor следующей порции либо `null` после конца выдачи. Запрос без cursor возвращает только `IntentionCatalogFirstPage` с точным количеством всех совпадений до разбиения на порции; её release-safe constructor не допускает отрицательный count или count меньше числа возвращённых summaries. Запрос с cursor возвращает только `IntentionCatalogContinuationPage` без повторного count. Поэтому отсутствие count у продолжения не представляется nullable-полем, а caller исчерпывающе различает начальный snapshot и его продолжение. `IntentionSummary` несёт только необходимые каталогу идентификатор, название, наличие описания, готовность, архивное состояние и timestamps; полный текст описания получает только `watchById`. Предметная модель и summary принимают каждое представимое UTC-значение независимо от взаимного порядка `createdAt` и `updatedAt`: обратный порядок после перевода системных часов не означает повреждение данных. Это ограничивает I/O и память независимо от размера описаний. Невалидный или не соответствующий запросу cursor, размер порции вне диапазона 1–100 либо непустой нормализованный фильтр длиннее 255 расширенных графемных кластеров возвращают стабильную validation failure до обращения к storage adapter, а не выполняют чтение каталога.

Закрытый набор `IntentionCommand` содержит создание, изменение данных, включение или выключение готовности к действию, архивирование, восстановление и физическое удаление. Наличие одной `execute` не стирает различия операций: варианты command имеют собственные обязательные параметры, а `Result` возвращает типизированный успех или предметную/инфраструктурную failure. Создание и любая сохраняющая command возвращают `IntentionSaved` с подтверждённым после commit намерением; no-op также возвращает текущий `IntentionSaved`, не выполняет запись и не меняет timestamps. Успешное физическое удаление возвращает `IntentionDeleted` с удалённым `IntentionId` только после commit; отсутствие идентификатора остаётся typed not-found failure.

`getCatalogPage` возвращает один ограниченный подтверждённый snapshot через `Future<Result<...>>`; каталог не является stream всех намерений. Ошибка чтения возвращается как типизированная repository failure, а явный retry повторяет только требуемую страницу при доказанно устранимой недоступности. `watchById` продолжает публиковать `ResultSuccess` с подтверждённым snapshot или успешным отсутствием намерения; adapter преобразует ошибку в один `ResultFailure`, после чего текущий stream завершается, а retryable failure допускает новую подписку. Таким образом, все failure проходят одну исчерпывающую Result-модель, а нетипизированный Dart error channel и Drift/SQLite exceptions никогда не пересекают seam. После подтверждённого command экран, который его выполнил, возвращает typed success каталогу: `IntentionSaved` позволяет обновить или исключить summary согласно текущему запросу, а `IntentionDeleted` — удалить summary; `watchById` после удаления публикует `ResultSuccess(null)`.

`IntentionRepository` является storage-neutral seam: его interface не раскрывает расположение данных, transport, состояние синхронизации или типы конкретного adapter. В текущем change production adapter использует только Drift, а fake adapter заменяет его в тестах ViewModels. Будущий adapter сможет внутренне скомпоновать локальный и удалённый источники, не заставляя Flutter Views зависеть от их протокола. Отдельные `SyncRepository`, remote port, outbox, tombstones, revisions и конфликтные версии сейчас не вводятся: без наблюдаемого sync-контракта они образовали бы спекулятивные shallow modules и зафиксировали бы случайную семантику. В соответствии с [ADR-0006](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md) `updatedAt` остаётся показанием изменяемых UTC wall-clock часов клиентского устройства при последнем подтверждённом изменении и не является revision, causal clock, гарантией фактической хронологии или правилом разрешения конфликтов.

Модуль владеет следующими правилами:

- для названия применяется Dart `String.trim()`, который определяет пробелы через Unicode `White_Space` и BOM согласно [Dart API](https://api.dart.dev/dart-core/String/trim.html); нормализованный результат должен содержать от 1 до 255 расширенных графемных кластеров, внутренние пробелы не меняются;
- для описания `trim().isEmpty` используется только для решения «отсутствует или присутствует»; при присутствии исходная строка должна содержать не более 4096 расширенных графемных кластеров и сохраняется вместо результата `trim()`;
- единая предметная функция на основе `package:characters` считает расширенные графемные кластеры для repository, формы и тестов, чтобы составной Unicode-символ не занимал несколько единиц лимита;
- UUID v7 создаётся только через внедрённый `IntentionIdGenerator` при выполнении команды создания; изменение, архивирование и восстановление не меняют его;
- новое намерение всегда принудительно получает `isActionReady = false` и `isArchived = false`;
- следуя ADR-0006, предметная модель хранит неизменяемый `createdAt` и изменяемый `updatedAt` как независимые UTC-показания системных часов клиентского устройства; при создании они равны, а при фактическом успешном изменении `updatedAt` заменяется текущим показанием без требования быть больше прежнего значения или `createdAt`;
- repository получает функцию текущего UTC wall-clock time через constructor injection, чтобы создание, обновление, равные показания и перевод часов назад были детерминированно проверяемы без отдельного глобального clock service;
- фильтр каталога перед запросом проходит `trim()`; пустой результат означает отсутствие фильтра, а непустой результат проверяется общей Unicode-функцией и должен содержать не больше 255 расширенных графемных кластеров до создания `IntentionTitleFilter`; одна чистая storage-neutral операция `titleSearchKey` применяет к названию и нормализованному фильтру полный Default Case Folding по Unicode-данным текущей сборки не старше Unicode 17.0.0 без Turkic tailoring и дополнительной Unicode-нормализации, сохраняя внутренние пробелы и различие символов, которые folding не приравнивает, включая `е`/`ё` и `e`/`é`; `IntentionTitleFilter.matchesTitle`, ключ SQL-фильтра и зарегистрированная SQLite-функция используют эту операцию как единственного владельца вновь вычисляемого отношения совпадения, а превышение исходного лимита возвращает validation failure без storage query и UI локализует ошибку, сохраняя введённый текст для исправления;
- cursor строится из выбранной временной метки и `IntentionId`, которые вместе задают полную неизменяемую границу значений; существование прежней граничной строки для продолжения запроса не требуется, а идентификатор является только автоматическим tie-breaker и не становится пользовательской настройкой;
- первая страница и её `totalCount` читаются в одной read transaction из одного SQLite snapshot; продолжения того же запроса не выполняют повторный count, а Catalog ViewModel сохраняет начальное точное значение и корректирует его только по membership transition подтверждённых command results;
- UI-подтверждения готовности и необратимого удаления происходят до command, но repository повторно проверяет предметные предусловия непосредственно внутри транзакции;
- ошибки не локализуются в repository: failure содержит стабильный код и безопасные структурированные данные, а ViewModel выбирает системную строку текущей локали.

Новые идентификаторы генерируются как UUID v7 по [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-7) из `package:uuid`. Production-реализация `IntentionIdGenerator` получает `UuidValue` через `Uuid().v7obj()` с криптографически стойким источником случайности согласно [документации package](https://pub.dev/packages/uuid). UUID v7 сохраняет независимую от SQLite генерацию и глобальное пространство идентичности, а его упорядоченный временной префикс уменьшает случайность вставок в primary-key и будущие foreign-key indexes по сравнению с UUID v4. Автоинкрементный идентификатор SQLite отклонён, потому что привязывает идентичность к одной локальной базе и осложняет будущую синхронизацию. UUID v4 остаётся допустимым сохранённым идентификатором, но не используется текущим production generator; смена generator не меняет предметный контракт.

`IntentionId` является непрозрачным неизменяемым value object и не раскрывает `UuidValue` либо сырой `.value`. Его конструктор закрыт: production generation возвращает готовый `IntentionId`, а отдельная boundary-фабрика разбирает каноническую lower-case запись ненулевого UUID по RFC 9562 с дефисами и возвращает закрытый типизированный результат «корректный идентификатор / некорректное представление», а не частично допустимый объект или unchecked cast. Корректный UUID не отклоняется только из-за его версии, поэтому UUID v4 и UUID v7 одинаково восстанавливаются как `IntentionId`. Data adapter преобразует некорректный или nil сохранённый идентификатор в corruption failure до построения `Intention` или `IntentionSummary`; будущий внешний routing adapter обязан преобразовать недоверенную строку до вызова типизированного маршрута. Явная каноническая сериализация доступна только boundary adapters, а предметный и прикладной код передают сам `IntentionId`.

`IntentionId` реализует равенство, hashing и `Comparable<IntentionId>`, поэтому catalog query, cursor и дедупликация не извлекают строку для сравнения. Встроенный в UUID v7 Unix timestamp не является предметным `createdAt`, не восстанавливается как пользовательское время и не заменяет явные UTC timestamps или выбранный порядок каталога. При одинаковом `createdAt` полный UUID остаётся только детерминированным tie-breaker; порядок генерации нескольких UUID внутри одной миллисекунды не считается предметной гарантией. Generator передаётся repository через constructor injection, чтобы тесты использовали детерминированную последовательность корректных `IntentionId` без публичного обхода инвариантов.

Предлагаемая структура сохраняет locality и не создаёт общего каталога `utils`:

```text
lib/
  main.dart
  src/
    app/
      app.dart
      bootstrap/
      localization/
      routing/
    data/local/
      app_database.dart
      migrations/
    intention/
      domain/
      application/
      data/
      presentation/
        catalog/
        details/
        editor/
    shared/
      presentation/
      ui/
```

### 3. MVVM на generated Riverpod и AutoRoute

UI следует однонаправленному потоку: repository публикует неизменяемые предметные модели, generated Riverpod ViewModel формирует неизменяемое UI state, View отображает его, а взаимодействие возвращается через публичный метод ViewModel, выполняющий конкретный `IntentionCommand`. Это соответствует текущим [архитектурным рекомендациям Flutter](https://docs.flutter.dev/app-architecture/recommendations).

- Используются `flutter_riverpod` 3.4.2, `riverpod_annotation` 4.0.6 и `riverpod_generator` 4.0.8. Code generation выбран согласно рекомендации Riverpod для проектов, где он уже нужен другим инструментам; Doable уже генерирует AutoRoute и Drift artifacts.
- Приложение запускается внутри одного корневого `ProviderScope`. Database, repository, diagnostics и router публикуются через generated `keepAlive` providers, а их внешние ресурсы освобождаются через `ref.onDispose`.
- Каждая View имеет собственную class-based `@riverpod` ViewModel с неизменяемым state. Каталог использует generated `AsyncNotifier`, потому что накапливает последовательные `Future`-страницы в ответ на прокрутку и изменение запроса; editor и details используют подходящий generated Notifier. Экранные и parameterized providers используют automatic disposal по умолчанию; широкой глобальной ViewModel нет.
- `watchById` оформляется generated functional Stream provider и представляется `AsyncValue`: `loading`, `error`, `data` и успешное отсутствие. Catalog ViewModel отдельно различает initial loading/error/empty, сохранённые `items`, `totalCount`, `nextCursor`, выполняющуюся следующую порцию и её локальную retryable failure; ошибка следующей порции не заменяет уже загруженные данные.
- Создание и изменения используют общий in-process presentation module `ExclusiveOperation` с одной синхронной операцией `start`. Первый вызов резервирует экземпляр до запуска асинхронного действия и возвращает принятое выполнение с его `Future`; повторный вызов занятого экземпляра возвращает отдельный outcome `alreadyRunning`, не вызывает действие и не ставит его в очередь. Gate освобождается после любого завершения принятого `Future`, включая failure или неожиданную ошибку, поэтому явная повторная попытка снова допустима. Общий неизменяемый `OperationState<TResult>` со статусами `idle`, `running`, `succeeded` и `failed` остаётся частью UI state владеющей ViewModel: она синхронно публикует `running` для принятого запуска и преобразует завершившийся `Result` в итоговое состояние. Module скрывает конкурентный guard, но не знает о предметных сущностях, repository, локализации, навигации или политике retry и не становится универсальным creator для будущих сущностей.
- Scope конкурентной политики остаётся ответственностью конкретной ViewModel. Editor ViewModel владеет отдельным `ExclusiveOperation` для каждого экземпляра формы создания, сохраняет введённые данные при failure и не блокирует независимую форму. Parameterized Details ViewModel владеет единым экземпляром для каждого `IntentionId` и хранит в состоянии вид текущей операции изменения данных, готовности к действию, архивирования, восстановления или физического удаления. Пока операция выполняется, все изменяющие controls этого намерения недоступны, а чтение подтверждённых данных продолжается независимо; разные `IntentionId` имеют независимые gates. Экспериментальные Riverpod Mutations и offline persistence не используются.
- Последний подтверждённый snapshot остаётся видимым при failure записи; optimistic update постоянного состояния не используется.
- View реагирует через `ref.listen` на одноразовый UI event навигацией, SnackBar или доступным сообщением и после обработки вызывает метод ViewModel для очистки event.
- Generated Catalog `AsyncNotifier` хранит выбранные scope, исходный текст фильтра, `IntentionCatalogOrder`, накопленные summaries, точное количество и cursor. Начальный scope равен active, порядок — `createdAt descending`; переключение scope сохраняет фильтр и порядок, а изменение любого параметра увеличивает generation запроса, очищает порции, возвращает прокрутку наверх и не позволяет позднему результату прежней generation заменить новый.
- `CatalogPagingPolicy` является одной неизменяемой инженерной конфигурацией с начальными `pageSize = 100`, `prefetchRemaining = 30` и debounce фильтра 250 мс. Generated provider публикует policy для production и позволяет тестам подменять её малыми значениями; пользовательской настройки нет. Любая конфигурация обязана задавать `pageSize` от 1 до 100 включительно и `prefetchRemaining` от 0 включительно до значения меньше `pageSize`; недопустимая policy отклоняется до repository call.
- После debounce Catalog ViewModel получает `IntentionCatalogFirstPage`, принимает из неё точный count и cursor. `ScrollController` инициирует `loadNextPage`, когда до конца остаётся не больше `prefetchRemaining` элементов; synchronous single-flight guard не допускает второй запрос той же страницы. Успешная `IntentionCatalogContinuationPage` добавляет только новые summaries по `IntentionId`, сохраняет прежний точный count и обновляет cursor; `nextCursor == null` прекращает подгрузку, а failure сохраняет прежние items и предоставляет retry той же страницы. Изменение scope, фильтра или порядка создаёт новую query generation без cursor и получает новый count вместе с её первой страницей.
- Накопленные summaries всегда образуют непрерывный префикс актуального глобального порядка до сохранённой cursor boundary, но его длина может измениться после command. При `nextCursor == null` весь результат уже загружен, поэтому совпадающий `IntentionSaved` вставляется или перемещается в любое правильное место. При наличии следующей порции Catalog ViewModel применяет к `IntentionSaved` storage-neutral membership/order rules текущего query: summary с позицией не позже boundary вставляется или перемещается внутри префикса, а summary после boundary либо вне scope/filter удаляется или не добавляется. `IntentionDeleted` удаляет совпадающий summary. Membership transition корректирует точный count; сохранённый cursor не меняется, а следующая порция запрашивается от прежней value boundary и дедуплицируется по `IntentionId`. Предшествующие порции повторно не читаются, и результат не сбрасывается на первую страницу.
- Каталог строится через `ListView.builder`, поэтому Flutter [создаёт widgets по мере попадания в viewport](https://docs.flutter.dev/resources/inside-flutter#infinite-scrolling), а не для всех накопленных summaries. [`ScrollController.keepScrollOffset`](https://api.flutter.dev/flutter/widgets/ScrollController/keepScrollOffset.html) и уникальный [`PageStorageKey`](https://api.flutter.dev/flutter/widgets/PageStorage-class.html) сохраняют position внутри route; пока подробный экран находится поверх каталога, его ViewModel и накопленные страницы остаются тем же экранным состоянием. Перед локальным согласованием command result ViewModel сохраняет `IntentionId` первого видимого summary и внутристочный offset, после согласования восстанавливает этот visual anchor, если summary осталось, иначе использует ближайшего оставшегося соседа. Успешная операция сообщает о сохранении независимо от того, осталось ли изменённое намерение в загруженном префиксе.
- View предоставляет локализованные и доступные элементы выбора трёх scopes, поля времени и направления, показывает точное количество совпадений и применяет фильтр без отдельной кнопки отправки. Дополнительный порядок по `IntentionId`, page size и threshold в UI не показываются.
- Riverpod 3 по умолчанию автоматически повторяет упавшие providers. Корневой `ProviderScope` задаёт `retry: (retryCount, error) => null`, чтобы loading/failure и повторная попытка оставались явным пользовательским поведением; retry выполняется только через целевую invalidation соответствующего provider.
- Parameterized provider подробных данных отличает ожидание первого snapshot, успешное отсутствие `AsyncData(null)` и типизированную ошибку чтения. Устранимая ошибка показывает локализованный retry, который инвалидирует только provider данного `IntentionId` и создаёт новую `watchById`-подписку; уход последнего слушателя автоматически отменяет текущую подписку, а повторное открытие начинает новую вместо показа сохранённой ошибки.
- Views используют `ConsumerWidget` или `ConsumerStatefulWidget`, наблюдают только presentation providers и сужают rebuild через `select` лишь после измеренного подтверждения проблемы. Hooks не добавляются.

Для маршрутов используются `auto_route` 11.1.0, `auto_route_generator` 10.6.0 и `MaterialApp.router`. `AppRouter` объявляется через `@AutoRouterConfig`, страницы — через `@RoutePage`, а единственным представлением внутренних переходов служат generated `PageRouteInfo` с обязательными типизированными аргументами; маршрут подробного просмотра принимает предметный `IntentionId` из любого охвата каталога и возвращает необязательный typed `IntentionCommandSuccess` исходному Catalog ViewModel. Прикладной код не вызывает строковые `pushNamed`, `replaceNamed` или `navigateNamed` и не передаёт имена или path вручную. Router создаётся generated `keepAlive` provider внутри `ProviderScope`; глобальный экземпляр router не вводится.

Текущий change не регистрирует внешнюю схему URI, не принимает строковый path-параметр и не реализует deep-link adapter. Состояние отсутствующего намерения остаётся частью подробного просмотра, поскольку сущность может исчезнуть между внутренним переходом и получением подтверждённых данных. Когда появится требование внешней точки входа, отдельный routing adapter сможет проверить недоверенную строку, преобразовать её в `IntentionId` и переиспользовать тот же типизированный маршрут; формат URI, platform integration, ожидание bootstrap и back stack должны быть определены в соответствующем change. AutoRoute сохраняет пространство для nested stack/tab routers, guards, declarative navigation и custom transitions в будущей навигации по графу, но текущий change не вводит эти конструкции без пользовательской необходимости. Императивный `Navigator` остаётся только для pageless подтверждений.

`go_router` отклонён, потому что его основной interface допускает строковые маршруты и не обеспечивает требуемую статическую типизацию без дополнительного companion generator и отдельной дисциплины запрета нетипизированного API. AutoRoute выбран потому, что generated route objects являются основным документированным способом навигации и одновременно сохраняют нужные расширения Router API. `provider` с `ChangeNotifier` отклонён в пользу Riverpod: он потребовал бы ручного управления подписками, временем жизни и широкими уведомлениями, тогда как providers выражают зависимости, automatic disposal и test overrides непосредственно. BLoC добавил бы отдельную систему events поверх уже существующих `IntentionCommand`. Чистый `setState` отклонён из-за слабой test surface и смешения I/O с widgets. Riverpod hooks отклонены как необязательный второй механизм локального состояния. Named routes отклонены из-за строкового interface, ограничений восстановления маршрута и будущей навигации по графу.

### 4. Drift и SQLite как текущий подтверждённый источник истины

Для локального хранения выбирается Drift поверх SQLite через `drift` и `drift_flutter`; генерация schema/migration artifacts и полная семантическая проверка в migration/file-backed tests используют `drift_dev`, а orchestration генерации — `build_runner`. `drift_dev` остаётся прямой dev dependency и не импортируется production module graph приложения. Явная локальная debug/internal проверка запускается через тот же test harness вне обычного app bootstrap, поэтому пользовательский путь не создаёт эталонную базу и не включает tooling API. На момент design проверены совместимые с Dart 3.13.1 версии `drift` 2.34.3 и `drift_flutter` 0.3.1. Drift выбран за типизированные запросы, реактивные streams, транзакции и инструменты миграций; эти возможности описаны в [официальной документации Drift](https://drift.simonbinder.eu/).

Версия схемы 1 содержит таблицу `intentions`:

| Поле | Хранение | Ограничение |
| --- | --- | --- |
| `id` | `TEXT` | primary key, канонический ненулевой UUID; новые значения UUID v7 |
| `title` | `TEXT` | `NOT NULL`, непустое нормализованное значение |
| `title_search_key` | `TEXT` | `NOT NULL STORED GENERATED ALWAYS`, вычисляется только из `title`; не записывается adapter и не входит в предметную модель |
| `description` | `TEXT NULL` | `NULL` означает отсутствие; непустой текст хранится посимвольно |
| `is_action_ready` | SQLite boolean | `NOT NULL`, начальное значение `false` |
| `is_archived` | SQLite boolean | `NOT NULL`, начальное значение `false` |
| `created_at` | `INTEGER` | `NOT NULL`, UTC-время в микросекундах от Unix epoch, неизменяемое после создания |
| `updated_at` | `INTEGER` | `NOT NULL`, UTC-время в микросекундах от Unix epoch, равно `created_at` при создании; последующий порядок относительно `created_at` не ограничен |

Уникального индекса на `title` нет. Исходный `title` является единственным записываемым представлением названия и единственным источником истины для его пользовательского текста. `title_search_key` объявляется как `STORED GENERATED ALWAYS` и вычисляется SQLite-функцией `doable_title_search_key(title)`; обычный `INSERT` или `UPDATE` не может передать этой колонке отдельное значение, а generated Drift companion не предоставляет её как записываемое поле. Функция делегирует той же чистой storage-neutral операции `titleSearchKey`, которая строит новые ключи названия и фильтра полным Default Case Folding по Unicode-данным текущей сборки не старше Unicode 17.0.0 без зависимости от системной локали. Хэш либо повторная проверка пары `title`/`title_search_key` при чтении не вводятся: внутри одной записи generated-колонка делает их независимо записываемое рассогласованное состояние непредставимым, но её прежний результат не считается каноническим пользовательским данным.

```text
Storage-neutral application boundary                 SQLite boundary

IntentionTitleFilter.matchesTitle ----+
                                      |
Ключ нормализованного фильтра --------+--> titleSearchKey
                                                |
                                                | registered delegate
                                                v
Intention command --> intentions.title --> doable_title_search_key
                                                |
                                                v
                                    generated title_search_key
                                                |
                                                | transactional trigger
                                                v
                                    FTS5-индекс поискового ключа
```

Имя и сигнатура `doable_title_search_key(TEXT)` являются частью schema contract, а конкретная версия используемых Unicode-данных — сменной implementation dependency сборки. Совместимое обновление MAY продвинуть её без schema version bump и без обязательного массового пересчёта: нетронутая строка может сохранить ранее вычисленный ключ до следующей записи этой строки либо явно выбранного rebuild поисковой проекции и FTS. Этот редкий семантический дрейф сознательно принят только для восстанавливаемой поисковой проекции, которая не изменяет `title`, не участвует в предметной идентичности, уникальности, ссылочной целостности, авторизации или синхронизации. Будущее производное значение с любым из этих назначений не наследует этот компромисс и требует отдельного решения о стабильности, версии и миграции. Adapter записывает только каноническое представление `IntentionId`, а при чтении проверяет формат, RFC variant и ненулевое значение до построения предметной модели. SQL-ограничения защищают обязательность сохранённых значений, но не вводят `CHECK` взаимного порядка timestamps и не заменяют типизированное декодирование идентификатора и предметную валидацию расширенных графемных кластеров в repository: SQLite не является источником истины для формы UUID или пользовательски воспринимаемой длины Unicode-текста. Все запросы строятся типизированным API Drift или параметризованными variables; пользовательский текст не конкатенируется с SQL.

Версия 1 также создаёт external-content virtual table `intention_titles_fts` через SQLite FTS5 с единственной пользовательской колонкой `title_search_key`, `tokenize = 'trigram case_sensitive 0 remove_diacritics 0'` и связью с hidden `rowid` таблицы `intentions`. Исходный `title` повторно не индексируется и не образует резервную ветвь candidate selection. Insert/delete triggers и срабатывающий на любой `UPDATE` строки trigger передают вычисленное `new.title_search_key` или `old.title_search_key` и обновляют FTS-индекс в той же transaction, что и основную строку; широкая update-граница обязательна, потому что SQLite может заново вычислить `STORED`-проекцию при записи строки даже без изменения `title`. Обычное чтение external-content table без `MATCH` делегируется основной таблице и не считается доказательством согласованности. Каноническая index-aware проверка выполняет `INSERT INTO intention_titles_fts(intention_titles_fts, rank) VALUES ('integrity-check', 1)`: `rank = 1` заставляет FTS5 сопоставить сам индекс с external content. Schema test намеренно создаёт рассогласованный индекс и доказывает, что обычное content-чтение не обнаруживает ошибку, а эта команда завершается ошибкой. Корневой `build.yaml` сообщает анализатору `drift_dev` 2.34.5 о FTS5 и сигнатуре custom function через поддерживаемую вложенную конфигурацию:

Связь FTS с hidden `rowid` является явным storage-инвариантом, а не предметной идентичностью: UUID `id` остаётся `TEXT PRIMARY KEY` и единственным идентификатором за storage seam. Production-код, maintenance и diagnostics не выполняют `VACUUM` или иную нетранзакционную операцию, способную переписать hidden rowids. Любой будущий migration step, перестраивающий `intentions`, обязан либо явно перенести прежние rowids, либо пересоздать и заполнить FTS из уже перестроенной основной таблицы внутри той же write transaction; перед commit в обоих случаях обязателен `integrity-check` с `rank = 1`. Добавление внетранзакционной rowid-rewriting операции требует отдельного change с безопасным crash-recovery contract и не может быть добавлено как обычная maintenance-оптимизация.

```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          sql:
            dialect: sqlite
            options:
              modules:
                - fts5
              known_functions:
                doable_title_search_key: "text (text)"
```

Эта настройка разрешает статический анализ FTS5 virtual tables, оператора `MATCH` и [известной custom function](https://drift.simonbinder.eu/generation_options/#known-custom-functions), но сама не включает extension и не регистрирует функцию в runtime SQLite. Runtime-контракт проверяется отдельно через тот же native executor, который использует production adapter: schema test действительно создаёт generated-колонку, FTS5 virtual table и выполняет `MATCH`. Используемая native-сборка `package:sqlite3` включает `SQLITE_ENABLE_FTS5` согласно [официальному описанию Drift Native](https://drift.simonbinder.eu/platforms/vm/#used-compile-options-on-android), а [trigram tokenizer SQLite предназначен для substring matching](https://www.sqlite.org/fts5.html#the_trigram_tokenizer). SQLite разрешает generated columns участвовать в индексах и требует от их выражений только [детерминированных scalar functions](https://www.sqlite.org/gencol.html); поэтому runtime-регистрация помечает `doable_title_search_key` как deterministic.

Допустимый непустой `IntentionTitleFilter` пересекает локальную storage seam только через единственную операцию конкретного module `LocalIntentionTitleSearch`, семантически означающую буквальное регистронезависимое вхождение в название намерения. Эта interface не принимает raw `String`, готовую FTS phrase, route flag или заявленную caller минимальную длину и не возвращает FTS-specific варианты, SQL fragments, variables либо предварительно материализованные идентификаторы. Она предоставляет одно условие над сохранённой поисковой проекцией, которое Drift repository adapter включает в тот же запрос, что scope, count, cursor, порядок и limit; выбор `instr` или FTS, построение ключа, экранирование и parameterization остаются закрытой implementation module. Исходный `title` не добавляется в candidate predicate: отображаемый текст остаётся каноническим, а обслуживающая его поисковая проекция связана generated-выражением основной строки.

Готовый search key из одной или двух кодовых точек Unicode module направляет в параметризованный `instr(title_search_key, query_search_key)` по основной таблице, а при трёх и более кодовых точках — в column-qualified trigram `title_search_key MATCH`. Обе ветви используют только одну проекцию. Для `MATCH` implementation удваивает каждый символ `"` внутри search key, заключает весь результат в одну пару двойных кавычек согласно [синтаксису строк FTS5](https://www.sqlite.org/fts5.html#fts5_strings) и передаёт готовую phrase только SQL-параметром. Поэтому кавычки, `OR`, `AND`, `NOT`, `NEAR`, скобки, `*`, дефисы или пробелы пользовательского текста не становятся операторами поисковой грамматики, а caller не может направить короткий фильтр в trigram только по собственной дисциплине. Фильтр длиннее 255 расширенных графемных кластеров отклоняется до создания `IntentionTitleFilter`, построения search key, открытия read transaction, `COUNT` или чтения строк. Линейный scan для фильтра из одной или двух кодовых точек осознанно принимается на репрезентативном объёме 50 000 намерений: ограничение ввода минимум тремя символами изменило бы утверждённое поведение, а отдельный unigram/bigram-индекс увеличил бы постоянную схему, стоимость записи и миграций без измеренного основания.

Обе ветви допустимого поиска проверяются через одну и ту же local search interface и одинаковые fixtures. Границы в одну, две и три кодовые точки включают символы вне BMP, чтобы выбор не зависел от длины UTF-16; Unicode corpus отдельно включает неочевидные отображения регистра вроде `K` → `k` и доказывает равенство результата pure Dart operation, SQLite generated column и ключа фильтра в пределах одной сборки. SQL trace подтверждает отсутствие пользовательского текста в SQL и выбранный `instr` либо `MATCH`, а `EXPLAIN QUERY PLAN` — использование FTS virtual table длинной ветвью. FTS-ветвь дополнительно покрывает кавычки, операторы, скобки, `*`, дефисы, внутренние пробелы и Unicode. Для проекций одной сборки наблюдаемая семантика буквальной подстроки не зависит от storage path, а реализация не материализует множество совпавших идентификаторов в Dart; историческая Unicode-проекция следует принятому исключению выше.

`getCatalogPage` применяет scope и фильтр до count и порядка. Active/archive используют явный predicate `is_archived`, all не добавляет его. Для каждого поля времени создаются индексы, поддерживающие `ORDER BY <timestamp> ASC|DESC, id ASC`; cursor predicate сравнивает сохранённое значение выбранной временной метки, а при её равенстве — `id`. Repository не пытается восстановить реальную последовательность операций после перевода системных часов. Он запрашивает `pageSize + 1` summaries, возвращает не больше `pageSize` и строит следующий cursor только при наличии дополнительной строки. Offset не используется, поэтому стоимость прохода не растёт пропорционально номеру условной страницы. Для запроса без cursor точный `COUNT` и строки первой порции выполняются внутри одной read transaction, используют одно и то же составное условие `LocalIntentionTitleSearch` и видят один SQLite snapshot. Для запроса с cursor выполняется только чтение строк продолжения с тем же условием фильтра: неизменный count уже принадлежит состоянию Catalog ViewModel, а подтверждённые commands корректируют его по переходу принадлежности текущему scope/filter. Поэтому полный последовательный проход одного неизменного query выполняет ровно один точный `COUNT` независимо от числа порций.

`watchById` использует запрос по primary key и сохраняет прежнюю реактивную семантику. Drift stream выдаёт начальный snapshot и повторно выполняется после подтверждённой записи согласно [документации stream queries](https://drift.simonbinder.eu/dart_api/streams/).

До предметной rehydration подробный read-path получает lossless storage-представление строки, в котором Drift ещё не преобразовал значения по типам generated data class. Реактивный custom query явно объявляет `intentions` как читаемую таблицу и передаёт в закрытую mapping boundary только необходимые предметные поля из `QueryRow.data`; внутренний generated `title_search_key` не проецируется и не проверяется как независимо сохранённое значение. Boundary принимает `String` для `id`, `title` и присутствующего `description`, `null` для отсутствующего `description`, только целые `0` или `1` для readiness и archive state и только представимые целые микросекунды для обоих timestamps. `REAL`, `BLOB`, посторонний Dart-тип, `null` в обязательном поле, целое значение вне допустимого boolean-множества или значение вне поддерживаемого диапазона `DateTime` отклоняются до любого преобразования через generated `bool`/`int` mapping. Только после этой проверки adapter декодирует `IntentionId`, сверяет нормализацию текста и строит предметное намерение; взаимный порядок корректно представимых timestamps не считается нарушением. Любое фактическое нарушение завершает текущую подписку через `IntentionCorruptionFailure` без частично подтверждённого snapshot. Storage-specific представление остаётся закрытым внутри Drift adapter и не пересекает `IntentionRepository`.

Каждый изменяющий command выполняется в транзакции и сообщает успех только после commit. Создание и изменение передают в `intentions` исходный нормализованный `title`, но никогда не передают `title_search_key`; SQLite вычисляет проекцию до выполнения обслуживающего FTS trigger. Создание записывает одно UTC-показание системных часов в `created_at` и `updated_at`; command, который фактически меняет подтверждённое состояние, атомарно записывает текущее показание в `updated_at` вместе с изменёнными данными. Равное или более раннее показание не блокирует фактическое изменение. Отклонённый, отменённый, завершившийся ошибкой или не меняющий данные command сохраняет прежние временные метки. Это поддерживает правило «целиком или никак» и не публикует промежуточные snapshots; Drift гарантирует атомарную видимость транзакций для внешних streams согласно [документации транзакций](https://drift.simonbinder.eu/dart_api/transactions/). Уже в версии 1 при открытии включается `PRAGMA foreign_keys = ON`, чтобы следующие change могли добавлять ссылочную целостность без смены режима работы базы.

`AppDatabase` принимает `QueryExecutor`: Android production connection явно передаёт `getApplicationDocumentsDirectory` как `DriftNativeOptions.databaseDirectory` в `driftDatabase(name: 'doable', ...)`, получает файл `doable.sqlite` и выполняет SQLite в background isolate, а тесты используют `NativeDatabase.memory()`. Единая connection setup регистрирует `doable_title_search_key` на каждом underlying SQLite connection до разбора и использования schema, включая production background isolate, in-memory/file-backed harness и эталонное соединение полной schema verification. `package:sqlite3` 3.5.2 помечает функцию `deterministic: true`; для каждой конкретной сборки и регистрации callback является неизменным total pure transform одного `TEXT`, не выполняет I/O, не читает окружающее состояние и не раскрывает данные, тогда как явно принятый межрелизный Unicode-дрейф не вносит изменяемого состояния внутрь connection. Необходимое для вызова из generated schema значение `directOnly: false` допустимо только при этих свойствах и внутреннем app-specific файле. Приложение не открывает импортированные или полученные извне SQLite-файлы. Если эта trust boundary меняется либо connection начинает использовать `trusted_schema = OFF`, до такого изменения требуется innocuous-capable registration или отказ от application-defined function в schema; молчаливое отключение setup недопустимо.

Зафиксированный `path_provider_android` разрешает каталог базы через `Context.getDir("flutter")`, то есть как `root/app_flutter/` в терминах Android Auto Backup. Оба набора Android backup rules исключают весь `root/app_flutter/` для cloud backup и device-to-device transfer; исключение каталога охватывает основной файл, соседние WAL/SHM и другие создаваемые SQLite служебные файлы, а SQLite temp directory находится в не включаемом в backup cache storage. Production locator и backup rules образуют один проверяемый Android host contract: тест разрешает выбранные connection name/directory в ожидаемые `domain/path` и падает при расхождении любого из них. Android-specific расположение и backup domain не пересекают `AppDatabase`, `IntentionRepository` или предметные interfaces. Общая дополнительная storage interface поверх Drift не вводится: подстановка уже находится на существующей seam `QueryExecutor`, поэтому ещё один pass-through только увеличил бы interface.

`LocalDataBootstrap` является единственным lifetime-owner созданных им `AppDatabase` и `QueryExecutor` и закрывает этот ресурс ровно один раз. После готового bootstrap `DriftIntentionRepository` получает заимствованный `AppDatabase`, не закрывает его и не добавляет lifecycle-операцию в storage-neutral `IntentionRepository`. Composition root Phase 7 владеет `LocalDataBootstrap`: при освобождении object graph он сначала отменяет принадлежащие вызывающим сторонам stream subscriptions и отбрасывает repository adapter, затем вызывает `LocalDataBootstrap.close()`. File-backed tests воспроизводят тот же порядок вместо отдельного test-only ownership.

`SharedPreferences` отклонён: он не даёт реляционных ограничений, транзакций и проверяемых миграций для будущего графа. `sqflite` остаётся работоспособной альтернативой с меньшим code generation, но требует вручную поддерживать SQL, mapping, реактивное обновление и миграционные проверки; эта сложность будет расти в следующих change.

### 5. Bootstrap, миграции и восстановление после ошибок

Capability `local-data-lifecycle` владеет bootstrap, версиями и миграциями всего локального хранилища независимо от конкретных предметных таблиц. Приложение запускает локализуемый bootstrap shell до открытия feature routes. Он асинхронно открывает базу, проверяет совместимость версии, применяет необходимые миграции и только затем создаёт `IntentionRepository`. Пока операция идёт, показывается loading. Доказанно устранимая ошибка открытия или миграции даёт безопасное локализованное сообщение и retry; ошибка несовместимой более новой схемы вместо retry сообщает о необходимости установить совместимое обновление приложения. Неизвестная причина получает отдельный безопасный unexpected outcome без обычного retry и без утверждения о повреждении данных. Ни одна ошибка открытия, совместимости или миграции не приводит к автоматическому удалению или пересозданию файла.

Версия приложения и версия хранилища независимы. Монотонный `schemaVersion` увеличивается только при изменении постоянной SQLite-схемы или обязательном преобразовании сохранённых данных. Опубликованной считается версия схемы, с которой вышел хотя бы один production release; её snapshot, generated представление и migration step хранятся бессрочно и не перенумеровываются. До production release ещё не опубликованный snapshot может быть заменён вместе с исходниками. Каждая текущая версия приложения поддерживает прямое обновление с любой опубликованной версии схемы от `1` до собственного `schemaVersion` без установки промежуточных версий приложения.

Облегчённое динамическое представление открытия базы:

```text
Bootstrap              AppDatabase / Drift                    SQLite
    |                           |                                 |
    | открыть и сравнить версии |                                 |
    |-------------------------->|                                 |
    |                           | current > expected               |
    |<--------------------------| incompatibleSchema, без записи   |
    |                           |                                 |
    |                           | current = expected               |
    |                           | foreign_keys = ON                |
    |<--------------------------| repository готов                 |
    |                           |                                 |
    |                           | current < expected               |
    |                           | foreign_keys = OFF               |
    |                           |---------------> BEGIN            |
    |                           | DDL + DML шаги vN...vCurrent     |
    |                           |---------------> foreign_key_check|
    |                           |---------------> COMMIT           |
    |                           | foreign_keys = ON                |
    |<--------------------------| repository готов                 |
    |                           |                                 |
    |                           | exception / остановка до COMMIT  |
    |<--------------------------| rollback, retry с прежней версии |
```

При upgrade `PRAGMA foreign_keys = OFF` выполняется до начала транзакции, поскольку SQLite не меняет этот режим внутри активной транзакции. Затем одна write transaction охватывает все generated пошаговые переходы от исходной версии к целевой через `Migrator.runMigrationSteps`: DDL-изменения таблиц, ограничений, индексов, triggers и views; DML-перенос или backfill пользовательских данных; а также обязательный `PRAGMA foreign_key_check` до commit. Сложное изменение ограничения или типа столбца использует безопасное перестроение таблицы: создать новую схему, перенести и преобразовать строки, удалить старую таблицу, переименовать новую и восстановить индексы внутри той же транзакции. Если такой шаг затрагивает `intentions`, он явно сохраняет hidden rowids либо пересоздаёт и заполняет `intention_titles_fts` после окончательного переноса строк и до commit выполняет FTS `integrity-check` с `rank = 1`. `VACUUM` и другие нетранзакционные rowid-rewriting операции запрещены не только в migration steps, но и в production maintenance и diagnostics этого change.

Первичное создание schema version 1 использует тот же атомарный контур, что и upgrade. Проверка отсутствия пользовательских schema objects выполняется до начала write transaction; затем `createAll`, `foreign_key_check`, полный FTS `integrity-check` с `rank = 1` и запись `user_version = 1` завершаются внутри одной transaction. Ошибка после любого DDL до commit откатывает все созданные таблицы, индексы, triggers, virtual table и marker версии. File-backed fault injection прерывает создание между DDL-операциями, полностью закрывает неуспешный persistence object graph и доказывает успешное повторное открытие того же пустого файла без ручной очистки.

Только успешное завершение всех шагов и проверки подтверждает целевую версию. Exception либо остановка процесса до commit откатывает изменения схемы, индексов, ограничений и данных; тесты также доказывают, что marker версии не продвинулся. Неуспешное соединение закрывается, а следующая попытка начинает переход из последней целостной версии. После успешной миграции `beforeOpen` явно включает `PRAGMA foreign_keys = ON` до любого feature query.

После проверки версии и завершения применимой миграции production `beforeOpen` подтверждает ожидаемый `user_version` и явно включает `PRAGMA foreign_keys = ON` до любого feature query. Он не вызывает `validateDatabaseSchema`, не читает полный набор `CREATE`-определений из `sqlite_schema` и не создаёт вторую пустую in-memory database. Стоимость обычного открытия текущей версии поэтому не включает tooling API и не зависит ни от числа schema objects, ни от объёма пользовательских данных.

Полный index-aware FTS audit остаётся отдельным production helper и вызывается внутри атомарного первичного создания, каждой миграции, затрагивающей FTS, а также из явно выбранного будущего recovery/maintenance flow; обычный bootstrap не выбирает такой flow неявно. Instrumented file-backed test проверяет отсутствие эталонной базы, пользовательских reads и команды `integrity-check` при повторном production-подобном открытии текущей схемы независимо от объёма данных.

Полная семантическая проверка схемы находится вне production bootstrap. Migration/file-backed tests и явно запускаемый локальный debug/internal harness вызывают `validateDatabaseSchema(options: const ValidationOptions(validateDropped: true))`: Drift читает `CREATE`-определения фактических объектов из `sqlite_schema`, создаёт пустую эталонную in-memory database через `Migrator.createAll()` с той же предварительной регистрацией `doable_title_search_key` и семантически сравнивает оба набора. Проверка охватывает наличие и вид schema objects, generated expression и режим `STORED`, определения обычных и virtual tables вместе с FTS5-конфигурацией, тела triggers, а также поля, порядок и predicates indexes; `validateDropped: true` дополнительно отклоняет лишние пользовательские schema objects. Совпадение одних имён недостаточно.

File-backed matrix сохраняет текущий marker, но по отдельности меняет column constraint, FTS5-конфигурацию, тело trigger, поле или predicate index и добавляет лишний schema object. Каждый вариант обязан завершить verifier через `SchemaMismatch`; обязательный CI gate не признаёт production artifact готовым, пока текущая схема и каждый поддерживаемый migration path не проходят ту же проверку. Ошибка выполнения test/debug verifier остаётся отказом соответствующей проверки и не участвует в классификации production bootstrap.

Если сохранённая версия схемы выше `AppDatabase.schemaVersion`, bootstrap возвращает отдельный non-retryable `incompatibleSchema` failure до создания repository. Приложение не выполняет feature query, запись, downgrade, удаление или пересоздание файла; единственное предлагаемое восстановление — установка совместимой более новой версии приложения. Версии схемы ниже `1`, отсутствующая или структурно повреждённая metadata классифицируются как corruption, а не пытаются угадать исходную версию.

Ограниченная production-проверка создаёт `CorruptLocalDataSchemaException` только тогда, когда успешно прочитанный marker доказывает несовместимую версию или повреждённую version metadata. Ошибки чтения marker сохраняют исходную типизированную SQLite-причину и покидают migration boundary без преобразования в corruption. Скрыто изменённое, но читаемое определение schema object при совпадающем `user_version` не обязано обнаруживаться на этом bootstrap boundary и может проявиться позднее как типизированная ошибка конкретной SQLite-операции.

На boundary открытия bootstrap последовательно раскрывает известные транспортные обёртки Drift, включая `DriftRemoteException.remoteCause` production background executor, и классифицирует найденное `SqliteException` по полному `extendedResultCode`, а не только по его первичному семейству, локализованному сообщению или полному exception. Семейства `SQLITE_CORRUPT` и `SQLITE_NOTADB`, а также точный `SQLITE_IOERR_DATA` преобразуются в non-retryable `LocalDataCorruption`: первые два машинно указывают на повреждённую либо не-SQLite database, а последний — на неверную checksum страницы database.

Точный retryable allowlist состоит из `SQLITE_BUSY`, `SQLITE_BUSY_RECOVERY`, `SQLITE_BUSY_SNAPSHOT`, `SQLITE_BUSY_TIMEOUT`, `SQLITE_LOCKED`, `SQLITE_LOCKED_SHAREDCACHE` и `SQLITE_LOCKED_VTAB`: их машинная семантика доказывает временный конфликт доступа или блокировки. Первичные `SQLITE_CANTOPEN` и `SQLITE_IOERR`, их не вошедшие в другую категорию extended variants, включая постоянный `SQLITE_CANTOPEN_ISDIR` и недостаточно доказательный `SQLITE_IOERR_CORRUPTFS`, а также любой новый неизвестный extended code остаются non-retryable `LocalDataUnexpectedFailure`. Новый фактически временный код расширяет allowlist только отдельным подтверждённым решением по [официальной семантике result codes SQLite](https://www.sqlite.org/rescode.html).

Любая причина вне corruption и retryable allowlists, включая нераспознанный SQLite-код или неожиданный non-SQLite exception, преобразуется в отдельный non-retryable `LocalDataUnexpectedFailure`. Он не объявляет файл повреждённым, не предлагает обычный retry как восстановление и записывает только `DiagnosticsFailureCode.unexpected`. Каждый non-ready outcome закрывает неготовый executor; diagnostics не получает SQL, параметры, пользовательские данные или текст exception. File-backed fixtures отдельно покрывают произвольный non-database файл и повреждение header/schema, приводящие к `NOTADB` либо `CORRUPT`.

Для каждой версии схемы:

1. увеличивается `schemaVersion`;
2. сохраняется и навсегда коммитится schema snapshot в `drift_schemas/` до публикации release;
3. добавляется один переход `fromNToN+1`, способный изменить схему и данные без destructive fallback;
4. генерируется и выполняется прямой тест перехода с каждой опубликованной исходной версии до новой целевой версии;
5. для каждого исходного snapshot проверяются итоговая схема, marker версии, сохранность fixture-данных и `foreign_key_check`;
6. fault-injection tests доказывают rollback схемы, данных и marker версии при exception внутри каждого нового migration step, а file-backed integration test проверяет повторное открытие после прерывания;
7. fixture с версией выше текущей доказывает отказ от feature query, записи, downgrade и destructive recovery.

Drift рекомендует сохранять схемы, генерировать пошаговые migration helpers и проверять переходы; `migrateAndValidate` и `validateDatabaseSchema` сравнивают фактическую и ожидаемую схему, что описано в [руководстве по тестированию миграций и runtime-проверке](https://drift.simonbinder.eu/migrations/tests/#verifying-a-database-schema-at-runtime). Та же документация рекомендует runtime verifier преимущественно для debug builds из-за объёма дополнительного кода, поэтому текущий change оставляет его в dev/test boundary. Снимки схемы и сгенерированный код коммитятся вместе с исходным описанием схемы, а CI проверяет отсутствие незакоммиченного результата генерации и полную семантическую совместимость текущей file-backed схемы и каждого поддерживаемого перехода. Если будущий migration step нельзя безопасно завершить одной короткой bootstrap-транзакцией, соответствующий change обязан до публикации отдельно спроектировать поэтапный backfill и совместимость нескольких форматов; текущая реализация не запускает такое преобразование в фоне неявно.

### 6. Локализация и доступность являются частью architecture

Используется SDK-пакет `flutter_localizations` и `gen_l10n` с ARB-файлами `app_en.arb` и `app_ru.arb`; английский файл является template. `supportedLocales` содержит только `en` и `ru`, а `localeListResolutionCallback` одинаково для любого поддерживаемого platform host реализует правило: русский language code выбирает `ru`, английский — `en`, всё остальное — `en`. Это устраняет зависимость fallback от случайного порядка списка; механизм соответствует [документации Flutter по internationalization](https://docs.flutter.dev/ui/internationalization).

Все системные строки, включая semantic labels, ошибки, empty/loading, критерии действия и подтверждение удаления, берутся из generated localizations. Названия и описания остаются обычными значениями предметной модели, отображаются как plain text и никогда не проходят через перевод, interpolation как форматная строка или rich HTML renderer.

Views преимущественно используют стандартные Material controls с корректными roles и focus order. Пользовательские составные элементы получают `Semantics` с локализованными label/value/state; готовность и архивное состояние дублируются текстом или semantics, а не кодируются только цветом. Ошибки формы связываются с полем и объявляются системным экранным диктором; результат destructive/изменяющей операции доступно сообщается после завершения. Layout проверяется при системном text scale до 200%, без фиксированной высоты для пользовательского текста. Flutter рекомендует тестирование screen reader, минимальные targets 48×48 и работоспособность при большом масштабе в [accessibility checklist](https://docs.flutter.dev/ui/accessibility). Для текущего Android host ручным evidence служит TalkBack.

### 7. Приватность, trust boundaries и hardening

Активы — пользовательские названия и описания, идентичность намерений и целостность архивного состояния. Trust boundaries проходят через текстовые поля, SQLite-файл и входную схему миграции. Аутентификации и сетевой boundary нет: приложение обслуживает одного локального пользователя текущего platform profile.

Применяются следующие меры:

- каждый поддерживаемый platform host обязан размещать SQLite-файл и служебные данные во внутреннем app-specific storage и реализовать capability-политику backup/transfer собственными средствами;
- текущий Android host явно открывает `root/app_flutter/doable.sqlite` через `getApplicationDocumentsDirectory` в изолированном внутреннем хранилище согласно [Android security guidance](https://developer.android.com/privacy-and-security/security-best-practices#store-data-safely), а release manifest не получает `INTERNET` или разрешения внешнего хранилища в рамках change;
- Android adapter исключает каталог `root/app_flutter/` вместе с SQLite WAL/SHM и соседними служебными файлами из cloud backup и device-to-device transfer правилами для Android 12+ `data-extraction-rules` и Android 11- `full-backup-content`; contract test связывает production locator с обоими наборами правил, чтобы backup по умолчанию не мог незаметно вынести личный граф за локальную границу;
- название, описание и фильтр каталога, включая границы в 255, 4096 и 255 расширенных графемных кластеров соответственно, валидируются до использования; generated/параметризованные Drift queries исключают SQL injection, а недопустимый фильтр не достигает SQLite/FTS;
- Flutter выводит пользовательский текст как plain text; rich text с интерпретацией markup не используется;
- irreversible delete требует отдельного UI-подтверждения, а фактические предусловия удаления проверяются повторно в той же транзакции, где выполняется delete;
- production diagnostics не содержат названий, описаний, UUID, SQL с параметрами или полных database exceptions.

Эти правила задают текущую границу долговечности одной установки приложения, а не постоянный запрет на синхронизацию: совместимое обновление сохраняет внутреннее хранилище, но удаление приложения, очистка данных или утрата устройства не дают новой установке способа восстановить прежний граф. Будущая управляемая синхронизация сможет пересечь эту границу за storage-neutral seam и должна явно определить согласие пользователя, разрешение конфликтов и восстановление; текущий локальный adapter не содержит её transport или метаданные.

Отдельное шифрование SQLite отклонено для текущей модели угроз: ключ, доступный тому же процессу без пользовательского секрета, не защищает от полностью скомпрометированного разблокированного устройства, но добавляет риск потери данных и сложные миграции ключей. Базовая защита опирается на sandbox и шифрование внутреннего хранилища Android. При появлении синхронизации, экспорта, общего устройства или app lock модель угроз должна быть пересмотрена.

### 8. Ошибки и наблюдаемость без утечки данных

Repository преобразует outcomes в закрытый набор `IntentionValidationFailure`, `IntentionNotFoundFailure`, `IntentionConflictFailure`, `IntentionUnavailableFailure`, `IntentionCorruptionFailure` и `IntentionUnexpectedFailure`. `IntentionUnavailableFailure` означает только доказанно временную причину и допускает явный retry; `IntentionUnexpectedFailure` является отдельным non-retryable результатом, не утверждает о повреждении данных и не представляет повтор той же операции как восстановление. Bootstrap отдельно различает retryable opening/migration failure, corruption, non-retryable `incompatibleSchema` и такой же non-retryable `unexpected`; несовместимость содержит только ожидаемую и обнаруженную версии схемы и требует обновления приложения.

Единый внутренний `SqliteFailureClassifier` последовательно раскрывает известные `DriftRemoteException` и без анализа текста преобразует полный `extendedResultCode` в закрытую storage-категорию: `corruption`, allowlisted `unavailable`, constraint с сохранённым extended result code либо `unexpected`. Категория corruption охватывает семейства `SQLITE_CORRUPT`/`SQLITE_NOTADB` и точный `SQLITE_IOERR_DATA`; unavailable — только точно перечисленные `BUSY`/`LOCKED` primary и extended codes. `SQLITE_CANTOPEN`, остальные `SQLITE_IOERR`, включая `SQLITE_IOERR_CORRUPTFS`, и любой неизвестный extended code означают unexpected, пока отдельное решение не докажет более точную категорию. Классификатор не превращает constraint в предметный conflict самостоятельно: bootstrap отображает любую constraint-категорию в `LocalDataUnexpectedFailure`, сохраняя уже доказанные outcomes, а repository сопоставляет её с контекстом конкретной command.

В repository только `SQLITE_CONSTRAINT_PRIMARYKEY` при вставке нового `IntentionId` командой `CreateIntention` и `SQLITE_CONSTRAINT_FOREIGNKEY` при `DeleteIntention` являются ожидаемыми `IntentionConflictFailure`. `SQLITE_CONSTRAINT_CHECK`, `SQLITE_CONSTRAINT_NOTNULL`, `SQLITE_CONSTRAINT_UNIQUE`, `SQLITE_CONSTRAINT_ROWID`, `SQLITE_CONSTRAINT_TRIGGER`, общий либо неизвестный extended constraint, а также `PRIMARYKEY`/`FOREIGNKEY` вне утверждённых command contexts становятся `IntentionUnexpectedFailure`: проверенные предметные значения не должны нарушать эти ограничения, и такой отказ не доказывает ни конфликт, ни повреждение сохранённых данных. Нарушение исходного storage-представления или предметных инвариантов строки становится `IntentionCorruptionFailure` на lossless rehydration boundary до необратимого typed coercion. Любой неизвестный SQLite либо non-SQLite exception также становится `IntentionUnexpectedFailure`. Неожиданные exceptions перехватываются на ближайшей ответственной seam, передаются в diagnostics только как код `unexpected`; stack trace и внутренние детали пользователю не показываются. Типизированный `Result` следует документированному Flutter подходу к [обработке ошибок между слоями](https://docs.flutter.dev/app-architecture/design-patterns/result).

Локальный `DiagnosticsSink` является best-effort/no-throw interface: каждый
adapter обязан перехватывать собственные ошибки кодирования и вывода, не
предпринимать рекурсивную попытку диагностировать свой отказ и всегда возвращать
управление caller. Недоступность diagnostics не меняет результат предметной или
storage-операции, lifecycle stream, readiness bootstrap либо подтверждённое
состояние; в частности, после commit command сохраняет исходный typed success.
Production adapter использует `dart:developer`, а in-memory adapter — тесты.
Фиксируются только:

- начало, успех или failure bootstrap и миграции;
- тип intention command, длительность, outcome и безопасный failure code;
- начало, длительность, page size и outcome чтения порции каталога, а также начало и failure подробных данных;
- версия схемы и длительность открытия базы.

Пользовательский текст фильтра, названия, описания, UUID, cursors и SQL-параметры не фиксируются. Внешний telemetry adapter не добавляется, но seam позволяет в будущем подключить его отдельным решением с явной политикой приватности.

### 9. Стратегия проверки

Test surface совпадает с interfaces модулей:

- unit tests предметных значений и `IntentionRepository` на in-memory SQLite покрывают Unicode-нормализацию названия, границы 1/255/256 для названия и 4096/4097 для описания с составными графемами, точное сохранение описания, одинаковые названия, генерацию и стабильность новых UUID v7, канонический round trip UUID v4 и UUID v7, отклонение некорректного формата, variant и nil UUID, типизированный parse failure, сравнение без извлечения строки, детерминированный fake generator, временные метки, три scope, четыре комбинации порядка, готовность, архивирование, восстановление, удаление и исчерпывающий закрытый набор failures вместе с non-retryable `unexpected`;
- repository integration tests проверяют допустимые размеры страницы 1 и 100, validation failure для 0 и 101 без storage query, sealed-варианты первой и последующих страниц, точный count первой страницы, cursor boundary при равных timestamps, продолжение того же query после создания и изменения граничной строки, отсутствие offset, буквальную регистронезависимую фильтрацию на русском и английском, границы фильтра 255/256 расширенных графемных кластеров, отсутствие SQLite/FTS/`COUNT` для превышения, закрытый `IntentionTitleFilter`, единую local search interface с границами 1/2/3 кодовых точек и символами вне BMP, различие `е`/`ё` и диакритики, SQL trace выбранного `instr`/`MATCH`, буквальную обработку кавычек, FTS-операторов, скобок, `*`, дефисов, пробелов и Unicode, атомарную согласованность FTS triggers, index-aware `integrity-check` с `rank = 1` и отрицательную fixture, где content-чтение не видит намеренного рассогласования, а FTS-проверка падает, streams подробных данных после commit, lossless detail-row fixtures с boolean-значениями вне `0`/`1`, дробными timestamps и посторонними storage classes до typed mapping, закрытую/повреждённую базу и контекстное преобразование primary-key collision и blocking foreign key в conflict, `CHECK`/`NOT NULL` и остальных constraint-кодов в unexpected, точные `BUSY`/`LOCKED`-коды в unavailable, семейства `CORRUPT`/`NOTADB` и `IOERR_DATA` в corruption, а `CANTOPEN`, остальные `IOERR`, неизвестные SQLite и non-SQLite exceptions в unexpected;
- отдельный large-fixture test создаёт не меньше 50 000 коротких активных и архивированных намерений, проверяет через `EXPLAIN QUERY PLAN` использование FTS virtual table для фильтра от трёх символов и timestamp/cursor indexes для неотфильтрованных порций, а для фильтров из одной и двух Unicode-кодовых точек — намеренный `instr` scan как при частом, так и при отсутствующем совпадении. После пяти прогревочных вызовов по 30 последовательным вызовам первой страницы каждого short-filter case отдельно от SQL trace измеряют полный repository path с точным `COUNT` и `pageSize = 100`; 95-й процентиль каждого case не превышает 100 мс в авторитетном GitHub Actions Linux CI-профиле с зафиксированными версиями инструментов. Тот же test доказывает ровно один `COUNT` и один ограниченный `pageSize + 1` read для первой страницы, отсутствие `OFFSET` и description, ровно один `COUNT` при последовательной загрузке всех порций одного query и materialization не больше настроенного `pageSize` для каждой repository operation, даже когда точный count значительно больше. Этот suite получает объявленный file-level tag `slow`, означающий только длительность запуска, а не benchmark-семантику; новый `check-fast` выполняет форматирование, анализ и тесты без `slow`, тогда как существующий `check` остаётся полным обязательным контуром и включает все тесты;
- unit tests общего `ExclusiveOperation` проверяют синхронный переход в `running`, отсутствие запуска или очереди второго действия, освобождение gate после success/failure и независимость экземпляров; тесты generated Riverpod ViewModels и providers используют отдельный `ProviderContainer` с overrides на fake repository и проверяют initial loading/data/empty/failure, накопление порций, single-flight следующей страницы, inline failure/retry, конец выдачи, debounce, отклонение устаревшего результата, три scope, четыре порядка, точный count первой страницы, сохранение count при продолжениях, подмену `CatalogPagingPolicy` и согласование typed command result после нескольких порций. Параметризованная матрица `createdAt`/`updatedAt` × ascending/descending покрывает создание и изменение внутри и после boundary, неизменность cursor, немедленное обновление count по membership transition, сохранение visual anchor и последующую подгрузку без пропусков, повторов или преждевременно показанного намерения;
- widget tests проверяют русскую, английскую и fallback локали, локализованную валидацию длины названия, описания и фильтра, сохранение недопустимого фильтра для исправления без repository call, фильтр по названию, отображение точного количества, автоматическую подгрузку у threshold, сохранение scroll position, выбор scope/поля/направления, все подтверждения, отсутствие перевода пользовательского текста, навигацию и not-found;
- accessibility tests проверяют semantics labels/states, tap targets, contrast и layout при text scale 200%; критические потоки дополнительно проходят ручную проверку TalkBack на Android;
- Drift schema snapshots и generated migration tests проверяют атомарное первичное создание, прямой переход с каждой опубликованной версии до текущей, итоговую схему, marker версии, сохранность данных, `foreign_key_check`, FTS `integrity-check` с `rank = 1` после создания и каждого затрагивающего индекс перехода, rollback при fault injection и отказ от открытия более новой схемы для записи;
- test/debug schema-validation matrix сохраняет текущий marker и ожидаемые имена, но по отдельности изменяет колонки и constraints, FTS5-конфигурацию, тело trigger, поля или predicate index и добавляет лишний schema object; каждый `SchemaMismatch` проваливает обязательную проверку до поставки, а production SQL trace доказывает отсутствие эталонной базы, семантического verifier, пользовательских reads и полного FTS audit в обычном bootstrap;
- bootstrap classification tests вводят семейства `CORRUPT`/`NOTADB`, `IOERR_DATA`, каждый точно allowlisted `BUSY`/`LOCKED`-код, первичные `CANTOPEN`/`IOERR`, `CANTOPEN_ISDIR`, `IOERR_CORRUPTFS`, неизвестный extended code знакомого семейства, constraint и non-SQLite причину непосредственно во время ограниченного чтения marker версии. Production-подобный background executor подтверждает раскрытие `DriftRemoteException`, mapping любой constraint-категории в bootstrap `unexpected`, одинаковые остальные outcomes, закрытие неготового executor и безопасные diagnostics по ту сторону isolate boundary;
- diagnostics tests вводят отказ writer production adapter и доказывают
  no-throw поведение для каждого вида события без рекурсивной записи, а
  repository command tests подтверждают исходный typed success и committed
  SQLite-состояние при отказе diagnostics после commit;
- file-backed repository integration test создаёт представительные активные и архивированные намерения, отменяет активные stream subscriptions, вызывает `close()` у владеющего первым object graph `LocalDataBootstrap` и отбрасывает первый `IntentionRepository`, затем создаёт новый bootstrap и repository на том же SQLite-файле и проверяет прежние идентификаторы, текст, готовность к действию, архивное состояние, timestamps, фильтр и точный count через публичную seam; repository не получает собственного `close()` и не закрывает заимствованный `AppDatabase`. Отдельная повреждённая fixture с некорректным либо nil идентификатором подтверждает corruption failure без частично построенной предметной модели, а корректные UUID v4 и UUID v7 восстанавливаются одинаково. После повторного открытия storage-level harness отдельно вызывает явный FTS `integrity-check` с `rank = 1`, тогда как instrumented bootstrap доказывает отсутствие этого полного audit в обычном `beforeOpen`. Отдельные file-backed tests проверяют rollback и повтор первичного создания и upgrade, а fixtures `NOTADB`/`CORRUPT` — non-retryable классификацию с закрытием executor.
- Android host contract test разрешает явно выбранные `getApplicationDocumentsDirectory` и `doable.sqlite` в `root/app_flutter/doable.sqlite`, структурно читает оба набора backup rules и доказывает исключение всего `root/app_flutter/` для cloud backup и device-to-device transfer; отрицательные fixtures с прежним `database` domain или неполным путём обязаны падать.

Тестовые названия и описания пишутся по-русски. Авторитетная CI-среда репозитория — GitHub Actions. Обязательный PR gate запускается на Linux runner из чистого checkout, устанавливает только явно зафиксированные версии используемых инструментов, разрешает Dart/Flutter-зависимости без изменения committed lockfile, повторяет генерацию локализации, Riverpod, AutoRoute, Drift code и schema/migration artifacts и падает при любом tracked или untracked результате генерации. Затем gate выполняет анализ, полный test suite с file-backed repository, migration tests и полной schema-validation matrix, собирает release-mode APK, проверяет его manifest permissions и запускает `openspec validate --all --strict --no-interactive`. Статус этого workflow настраивается как обязательная проверка защищённой основной ветки.

Android device/emulator job в этот change не входит. Release-mode APK и manifest проверяются на CI runner без запуска приложения на Android, а автоматизированные unit, widget, accessibility и file-backed tests не заявляются доказательством platform bootstrap после завершения процесса. Ручной TalkBack smoke test выполняется отдельно на Android до merge и фиксируется как внешнее evidence; принятый остаточный риск Android-specific wiring остаётся ограничен так, как описано ниже.

## Риски / Компромиссы

- **[Drift, AutoRoute, Riverpod и code generation увеличивают build complexity]** → Зафиксировать lockfile, коммитить generated code и schema snapshots, проверять генерацию без diff в CI и обновлять зависимости отдельно от предметных change.
- **[Riverpod dependency graph может вызвать широкие rebuilds или непреднамеренно удержать экранное состояние]** → Публиковать неизменяемый state, использовать automatic disposal для экранных providers, наблюдать узкие presentation providers и добавлять `select` только после измеренной проблемы.
- **[Automatic retry Riverpod может скрыть первый failure и нарушить явную модель повторной попытки]** → Отключить глобальный retry в `ProviderScope` и повторять только целевой provider по явному действию пользователя.
- **[Каталог может со временем содержать десятки тысяч намерений]** → Никогда не предоставлять unbounded query, читать только `IntentionSummary` ограниченными keyset-порциями, лениво строить widgets и проверять maximum materialization на fixture из 50 000 строк.
- **[Точный count добавляет отдельную работу к каждой новой query generation]** → Выполнять count только для запроса без cursor внутри того же SQLite read snapshot, использовать FTS5 для подстрок от трёх символов, debounce ввода, сохранять count при продолжениях, корректировать его по membership transition подтверждённых commands и доказывать одним multi-page large-fixture test ровно один `COUNT` на последовательный проход query.
- **[Фильтр из одной или двух кодовых точек требует линейного scan и вместе с точным count может дважды пройти выбранный scope]** → Сохранить утверждённое поведение короткого фильтра без unigram/bigram-индекса, покрыть частое и отсутствующее совпадение на 50 000 строках, ограничить первую страницу одним `COUNT` и одним `pageSize + 1` read и удерживать 95-й процентиль полного вызова не выше 100 мс в авторитетном Linux CI-профиле. Это значение является regression budget, а не обещанием Android latency: переносимость результата на Android без device performance job остаётся явно принятым остаточным риском текущего change; превышение бюджета требует отдельного решения о поисковой стратегии, а не скрытого ослабления фильтра или точного count.
- **[Application-defined search-key function вызывается из schema и поэтому не может оставаться `directOnly`]** → Разрешить schema-вызов только для total pure function одного `TEXT`, которая не выполняет I/O, не читает внешнее состояние и не раскрывает данные; открывать только внутренний app-specific SQLite-файл без импорта, регистрировать функцию до работы со схемой на каждом connection и проверять отказ при пропущенном setup. При появлении импорта чужих баз, `trusted_schema = OFF` или более широкой модели угроз сначала перейти на innocuous-capable registration либо убрать application-defined function из schema.
- **[Unicode-данные будущей сборки могут изменить результат сохранённой `STORED`-проекции]** → Принять редкий дрейф фильтрации без обязательного schema version bump или массового rebuild, потому что `title_search_key` восстанавливается из канонического `title` и не влияет на предметные ограничения либо необратимые операции; любой row update обязан синхронно обновлять FTS из фактически пересчитанного generated key. При наблюдаемой пользовательской проблеме отдельный change может добавить явный rebuild поисковой проекции вместе с FTS. Производные значения для идентичности, уникальности, авторизации или синхронизации требуют отдельного version/migration решения и не наследуют этот компромисс.
- **[FTS-индекс может разойтись с основной таблицей после ошибки записи, миграции или перезаписи hidden rowids]** → Обслуживать external-content index транзакционными triggers, запретить `VACUUM` и иные нетранзакционные rowid-rewriting paths, сохранять rowids либо атомарно перестраивать FTS при table rebuild и до commit создания или затрагивающей индекс миграции выполнять index-aware `integrity-check` с `rank = 1`; отрицательный test доказывает, что проверка падает на намеренно рассогласованном индексе, а отдельный helper сохраняет явный full-audit path.
- **[Полный FTS audit на каждом запуске сделал бы стоимость bootstrap линейной по объёму индекса]** → Обычный `beforeOpen` проверяет marker версии и включает `foreign_keys`, полный audit выполняется только в атомарных schema changes или явно выбранном recovery/maintenance flow, а SQL-trace test запрещает пользовательские reads и `integrity-check` при повторном открытии текущей схемы.
- **[Без production schema verifier скрыто изменённая, но читаемая схема с корректным marker может не обнаружиться при bootstrap]** → Принять этот остаточный риск для внутреннего app-specific storage без импорта и backup чужих файлов; до поставки проверять committed snapshots, текущую file-backed схему и каждый migration path полной семантической CI-матрицей, а runtime оставлять с атомарными миграциями, `foreign_keys` и типизированной классификацией SQLite-ошибок. Если эксплуатационные данные потребуют дополнительной production-защиты, отдельный change должен выбрать компактный fingerprint/verifier без `drift_dev`, предпочтительно только после schema-changing migration, вместо возврата tooling package в каждый запуск.
- **[Cursor может вернуть пропуски или повторы при неполном порядке, смене параметров либо command между порциями]** → Включать timestamp и `IntentionId` в полный порядок, хранить cursor как value boundary без зависимости от существования строки, связывать его с нормализованными параметрами запроса, отбрасывать только при их изменении и проверять создание/изменение до и после boundary с последующей подгрузкой.
- **[Перевод системных часов может дать одинаковые или убывающие `createdAt`/`updatedAt`, поэтому сортировка не всегда отражает фактическую хронологию]** → Хранить полученные UTC wall-clock значения без синтетического продвижения, сравнивать именно их с `IntentionId` как tie-breaker и не использовать timestamps как revision или causal clock. Этот остаточный риск принят для вспомогательного упорядочивания каталога; пересмотреть решение при добавлении синхронизации, разрешения конфликтов, хронологически значимого поведения либо наблюдаемого пользовательского ущерба от перестановок.
- **[Сохранившийся в прикладном состоянии cursor может быть передан пересозданному repository adapter]** → Связывать каждый cursor с приватным process-local owner token конкретного экземпляра adapter, отклонять несовпадение до storage query и начинать новую цепочку с `cursor: null` после замены object graph.
- **[Ошибка или остановка процесса во время первичного создания или миграции может оставить приложение недоступным]** → Охватывать DDL, DML, проверку целостности и продвижение marker версии одной проверяемой транзакцией, никогда не удалять базу автоматически и давать retry из последнего целостного состояния, включая пустое хранилище до schema version 1.
- **[Автотесты не воспроизводят завершение Android-процесса и повторный platform bootstrap]** → Доказывать файловую долговечность полным закрытием persistence object graph и повторным открытием того же SQLite-файла, отдельно проверять crash recovery миграций, статически связывать production locator `root/app_flutter/doable.sqlite` с backup rules и собирать release-mode APK. Остаточный риск ошибки только в Android runtime wiring принят для текущего change; device E2E и `adb`-orchestrator не вводятся без отдельного подтверждённого основания.
- **[Новая фактически временная причина может отсутствовать в retryable allowlist и получить unexpected outcome]** → В bootstrap и repository считать retryable только точно перечисленные машинные коды, отправлять любой новый extended code в safe `unexpected`, проверять классификацию на in-process и production-подобном background executor и расширять allowlist отдельным подтверждённым решением вместо catch-all retry.
- **[Generated Drift mapping может необратимо привести некорректное сохранённое значение к допустимому Dart-типу]** → На detail read-path проверять исходные storage classes и допустимые значения из `QueryRow.data` до generated mapping, строить предметное намерение только после lossless validation и покрыть terminal corruption fixtures для boolean и timestamp coercion.
- **[Старая версия приложения может встретить более новую схему после rollback APK]** → Возвращать non-retryable `incompatibleSchema` без feature query и записи, не выполнять downgrade и выпускать forward fix.
- **[Перестроение будущей большой таблицы может превысить приемлемое время bootstrap или свободное место]** → Измерять migration step на репрезентативных fixtures в соответствующем change; до release отдельно проектировать поэтапный backfill, если короткая атомарная транзакция больше не подходит.
- **[Граница одной установки приводит к потере данных при удалении приложения, очистке данных или утрате устройства]** → Ограничить текущее обещание долговечности перезапусками и совместимыми обновлениями внутри одной установки; сохранить storage-neutral seam для будущей управляемой синхронизации, но не добавлять её transport, конфликтные правила или метаданные без наблюдаемого поведения.
- **[Sandbox не защищает от root-доступа или полностью скомпрометированного разблокированного устройства]** → Не обещать app-level secrecy, не добавлять сетевые и backup copies; пересмотреть encryption/app lock при изменении модели угроз.
- **[Временной префикс UUID v7 могут ошибочно принять за предметное время или гарантию строгого порядка]** → Не извлекать из идентификатора `createdAt`, хранить явные UTC timestamps, считать `IntentionId` только tie-breaker при равных timestamps и проверять несколько генераций внутри одной миллисекунды.
- **[UUID v7 теоретически может столкнуться либо раскрыть приблизительное время генерации при утечке значения]** → Использовать криптографически стойкий production generator, сохранять primary key последней защитой с безопасным conflict без перезаписи и не включать UUID в production diagnostics.
- **[UI и repository могут по-разному посчитать составной Unicode-символ]** → Использовать одну функцию подсчёта расширенных графемных кластеров, проверять границы составными emoji и не полагаться на число UTF-16 code units или SQLite `length()`.
- **[Локальная диагностика не сообщает о проблеме удалённо]** → Сохранить безопасные структурированные события и adapter seam; внешний сбор добавлять только отдельным change с политикой приватности.

## План миграции

1. Добавить и зафиксировать совместимые зависимости `flutter_riverpod`, `riverpod_annotation`, `auto_route`, `uuid`, `characters`, `drift`, `drift_flutter`, `flutter_localizations`, а также `riverpod_generator`, `auto_route_generator` и остальные dev-зависимости генерации; проверить supply-chain metadata и lockfile.
2. До реализации постоянного adapter заменить допускающий произвольные строки `IntentionId` типобезопасным value object, внедряемым UUIDv7-generator и явным version-neutral boundary-декодированием, затем перевести существующие callers и тестовые fixtures на новый контракт.
3. Ввести корневой `ProviderScope`, generated providers composition root, bootstrap shell, локализацию и routing, сохранив доступный loading/error до готовности базы.
4. Явно связать Android production connection `root/app_flutter/doable.sqlite` с исключением всего `root/app_flutter/` в обоих наборах backup rules и их contract test, зарегистрировать на каждом connection чистую deterministic `doable_title_search_key`, затем создать `AppDatabase` schema version 1 с UUID v7, временными метками намерения, единственным записываемым `title`, вычисляемым `STORED` search key, одноколоночным FTS5 trigram-индексом этой проекции, единой local search seam буквальной подстроки, triggers и index-aware `integrity-check` с отрицательной fixture, атомарными первичным созданием и migration harness, test/debug schema verifier с полным семантическим сравнением schema objects, ограниченным production bootstrap без `drift_dev`, классификацией `CORRUPT`/`NOTADB`, initial schema snapshot, проверкой несовместимой более новой версии и in-memory executor.
5. Реализовать глубокий `IntentionRepository` с ограниченным `getCatalogPage`, точным count, keyset cursor, предметными моделями и failures, затем generated Riverpod ViewModels, `CatalogPagingPolicy`, immutable operation states и Views.
6. Заменить экран-заглушку каталогом с тремя scopes, фильтром, четырьмя порядками и автоматической подгрузкой только после прохождения repository, large-fixture, migration, localization и accessibility tests.
7. Перед merge провести обязательный GitHub Actions PR gate с воспроизводимой генерацией без изменений, анализом, полным test suite, file-backed проверками, release-mode сборкой, проверкой manifest и строгой OpenSpec-валидацией; отдельно выполнить и зафиксировать ручной TalkBack smoke test на Android.

Для первой версии capability миграция идёт от отсутствующей базы к schema version 1 и не затрагивает прежние пользовательские данные. Постоянный adapter ещё не опубликован, поэтому существующая schema version 1 и её snapshot согласованно заменяются вариантом со `STORED GENERATED ALWAYS` без migration step для production-данных. После публикации такая колонка не добавляется и её выражение не меняется простым `ALTER TABLE`; при этом обычное обновление поставляемых Unicode-данных внутри неизменной `doable_title_search_key(TEXT)` не меняет schema version и не требует обязательного table/FTS rebuild. Нетронутые строки MAY сохранять прежний поисковый ключ, любая последующая запись строки пересчитывает generated key и синхронно обновляет FTS, а полный maintenance rebuild вводится отдельным change только при наблюдаемой необходимости. Существующие UUID v4 fixtures остаются корректными входами нового `IntentionId`; новые fixtures создания используют UUID v7. Пока приложение не опубликовано, rollback выполняется обычным возвратом исходников и lockfile, а ещё не опубликованный schema snapshot может быть заменён согласованно с кодом. После будущей публикации каждый следующий release хранит все опубликованные snapshots и шаги, поэтому пользователь может обновиться сразу с любой прежней версии схемы. Downgrade migrations не поддерживаются: rollback приложения допустим только при совпадающей или явно совместимой схеме, а при более новой схеме старое приложение отказывается от записи без удаления файла. Основная стратегия исправления после публикации — forward fix с более высоким номером версии приложения и совместимой схемой; ни один rollback или retry не удаляет базу автоматически. Локальный `flutter run --release` и локальный либо CI-запуск `flutter build apk --release` в текущем change не создают артефакт для распространения и не являются checkpoint готовности к публикации; signing и канал поставки должны быть определены отдельным change перед первой публикацией.

## Открытые вопросы

Отсутствуют.

ADR-0003 фиксирует type-safe границу идентичности и оставляет версию UUID сменной политикой production generator. Пересмотр ADR-0001 завершён принятым ADR-0005: граница глубокого модуля сохранена, а наблюдение всего каталога заменено ограниченными страничными snapshot-запросами. Действующими являются ADR-0002–ADR-0006; ADR-0001 остаётся только историческим контекстом.
