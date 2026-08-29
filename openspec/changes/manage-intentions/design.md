## Контекст

Doable остаётся Flutter-приложением с Android host без постоянного пользовательского хранилища; в рамках начатого change уже реализованы только предметная модель намерения и Unicode-валидация задачи 2.1, а repository contract задачи 2.2 отсутствует. Зафиксированный стек — Flutter 3.47.1 stable и Dart 3.13.1. Design ограничивают действующие ADR-0002 о Drift/SQLite, ADR-0003 об UUID v4, ADR-0004 о локальном Android storage и ADR-0005 о глубоком модуле с ограниченными снимками каталога. ADR-0005 supersedes ADR-0001, который остаётся историческим контекстом и больше не задаёт действующий repository contract.

`manage-intentions` — первая законченная пользовательская вертикаль. Она должна провести правила намерения через платформонезависимые Flutter/Dart modules и прикладное состояние, а capability `local-data-lifecycle` — владеть общим открытием, миграцией и локальной долговечностью данных. Change не должен преждевременно моделировать долговременные связи, дневной выбор или синхронизацию, но создаваемая основа должна допускать последующее расширение SQLite-схемы, другой platform host и внутреннюю композицию локального adapter с будущим удалённым источником без зависимости UI от способа хранения.

Основные заинтересованные стороны:

- пользователь, который доверяет приложению личные названия и описания намерений и ожидает их сохранности;
- разработчики следующих change, которым нужны устойчивая идентичность намерения, проверяемые миграции и небольшая прикладная interface;
- тестирование и сопровождение, которым нужны воспроизводимые ошибки, доступные состояния интерфейса и диагностика без раскрытия пользовательского текста.

Технические решения сверены с первичными источниками: рекомендациями Flutter по [разделению UI и data layer, MVVM, repository, dependency injection и тестированию](https://docs.flutter.dev/app-architecture/recommendations) и [переиспользуемым асинхронным commands с защитой от повторного запуска](https://docs.flutter.dev/app-architecture/design-patterns/command), документацией Flutter по [локализации](https://docs.flutter.dev/ui/internationalization), [навигации](https://docs.flutter.dev/ui/navigation) и [доступности](https://docs.flutter.dev/ui/accessibility), официальной документацией Riverpod по [providers](https://riverpod.dev/docs/concepts2/providers), [ProviderScope и ProviderContainer](https://riverpod.dev/docs/concepts2/containers), [тестированию](https://riverpod.dev/docs/how_to/testing), [code generation](https://riverpod.dev/docs/concepts/about_code_generation) и [automatic retry](https://riverpod.dev/docs/concepts2/retry), официальной документацией AutoRoute по [generated типизированным маршрутам, nested navigation, deep links и declarative navigation](https://pub.dev/documentation/auto_route/latest/index.html), документацией Drift по [настройке](https://drift.simonbinder.eu/setup/), [транзакциям](https://drift.simonbinder.eu/dart_api/transactions/), [пошаговым миграциям](https://drift.simonbinder.eu/migrations/step_by_step/), [Migrator API](https://drift.simonbinder.eu/migrations/api/) и [тестированию миграций](https://drift.simonbinder.eu/migrations/tests/), официальной процедурой SQLite для [произвольного изменения таблиц внутри транзакции](https://sqlite.org/lang_altertable.html#making_other_kinds_of_table_schema_changes), а также рекомендациями Android по [внутреннему хранилищу](https://developer.android.com/privacy-and-security/security-best-practices#store-data-safely) и [управлению резервными копиями](https://developer.android.com/identity/data/autobackup).

## Цели / Не-цели

**Цели:**

- реализовать полный жизненный цикл намерения с одной реализацией предметных инвариантов для всех точек входа;
- сделать подтверждённое состояние текущего локального SQLite adapter единственным источником истины и не показывать незафиксированные записи как сохранённые;
- отделить Flutter-представление, прикладное состояние и постоянное хранение через небольшие проверяемые interfaces;
- сохранить storage-neutral seam управления намерениями и независимую от SQLite идентичность, не вводя преждевременный sync interface;
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
  Stream<Intention?> watchById(IntentionId id);
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command);
}

final class IntentionCatalogPage {
  const IntentionCatalogPage({
    required this.items,
    required this.totalCount,
    required this.nextCursor,
  });

  final List<IntentionSummary> items;
  final int totalCount;
  final IntentionCatalogCursor? nextCursor;
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

`IntentionScope` различает активные, архивированные и все существующие намерения. `IntentionCatalogOrder` состоит из выбранного поля — `createdAt` или `updatedAt` — и направления `ascending` или `descending`; начальное значение равно `createdAt descending`. `IntentionCatalogQuery` содержит scope, нормализуемый фильтр названия, порядок, проверяемый размер порции от 1 до 100 включительно и необязательный `IntentionCatalogCursor`, полученный из предыдущей страницы того же запроса. Query types предоставляют storage-neutral правила проверки принадлежности `IntentionSummary` текущему scope/filter и сравнения двух summaries в полном выбранном порядке; Catalog ViewModel использует те же правила для command results, а repository contract tests доказывают их соответствие SQL-выдаче.

Cursor остаётся storage-neutral value object: caller только возвращает его repository и не строит из SQLite row, offset или SQL-выражения. Он связывает нормализованные параметры запроса с граничной парой выбранной временной метки и `IntentionId`, но не с существованием или текущим состоянием строки, из которой был получен. Поэтому подтверждённое создание, изменение или удаление при неизменных параметрах запроса не инвалидирует сохранённую границу; прежний cursor отбрасывается только при изменении scope, фильтра или порядка. Cursor с другой нормализованной комбинацией параметров либо структурно недопустимое значение возвращают validation failure.

`IntentionCatalogPage` всегда содержит не больше запрошенного ограниченного размера, точное количество всех совпадений до разбиения на порции и cursor следующей порции либо `null` после конца выдачи. `IntentionSummary` несёт только необходимые каталогу идентификатор, название, наличие описания, готовность, архивное состояние и timestamps; полный текст описания получает только `watchById`. Это ограничивает I/O и память независимо от размера описаний. Невалидный или не соответствующий запросу cursor, размер порции вне диапазона 1–100 либо непустой нормализованный фильтр длиннее 255 расширенных графемных кластеров возвращают стабильную validation failure до обращения к storage adapter, а не выполняют чтение каталога.

Закрытый набор `IntentionCommand` содержит создание, изменение данных, включение или выключение готовности к действию, архивирование, восстановление и физическое удаление. Наличие одной `execute` не стирает различия операций: варианты command имеют собственные обязательные параметры, а `Result` возвращает типизированный успех или предметную/инфраструктурную failure. Создание и любая сохраняющая command возвращают `IntentionSaved` с подтверждённым после commit намерением; no-op также возвращает текущий `IntentionSaved`, не выполняет запись и не меняет timestamps. Успешное физическое удаление возвращает `IntentionDeleted` с удалённым `IntentionId` только после commit; отсутствие идентификатора остаётся typed not-found failure.

`getCatalogPage` возвращает один ограниченный подтверждённый snapshot через `Future<Result<...>>`; каталог не является stream всех намерений. Ошибка чтения возвращается как типизированная repository failure, а явный retry повторяет только требуемую страницу. `watchById` продолжает публиковать подтверждённые snapshots одного намерения; его ошибка преобразуется adapter в одну типизированную repository failure в error channel, после чего текущий stream завершается и retry создаёт новую подписку. Drift/SQLite exception никогда не пересекает seam. После подтверждённого command экран, который его выполнил, возвращает typed success каталогу: `IntentionSaved` позволяет обновить или исключить summary согласно текущему запросу, а `IntentionDeleted` — удалить summary; `watchById` после удаления публикует `null`.

`IntentionRepository` является storage-neutral seam: его interface не раскрывает расположение данных, transport, состояние синхронизации или типы конкретного adapter. В текущем change production adapter использует только Drift, а fake adapter заменяет его в тестах ViewModels. Будущий adapter сможет внутренне скомпоновать локальный и удалённый источники, не заставляя Flutter Views зависеть от их протокола. Отдельные `SyncRepository`, remote port, outbox, tombstones, revisions и конфликтные версии сейчас не вводятся: без наблюдаемого sync-контракта они образовали бы спекулятивные shallow modules и зафиксировали бы случайную семантику. `updatedAt` остаётся предметным временем последнего подтверждённого изменения и не является revision, causal clock или правилом разрешения конфликтов.

Модуль владеет следующими правилами:

- для названия применяется Dart `String.trim()`, который определяет пробелы через Unicode `White_Space` и BOM согласно [Dart API](https://api.dart.dev/dart-core/String/trim.html); нормализованный результат должен содержать от 1 до 255 расширенных графемных кластеров, внутренние пробелы не меняются;
- для описания `trim().isEmpty` используется только для решения «отсутствует или присутствует»; при присутствии исходная строка должна содержать не более 4096 расширенных графемных кластеров и сохраняется вместо результата `trim()`;
- единая предметная функция на основе `package:characters` считает расширенные графемные кластеры для repository, формы и тестов, чтобы составной Unicode-символ не занимал несколько единиц лимита;
- UUID создаётся только внутри команды создания; изменение, архивирование и восстановление не меняют его;
- новое намерение всегда принудительно получает `isActionReady = false` и `isArchived = false`;
- предметная модель хранит неизменяемый `createdAt` и изменяемый `updatedAt` как UTC-моменты; при создании они равны, а `updatedAt` меняется только вместе с фактическим успешным изменением подтверждённого состояния;
- repository получает функцию текущего UTC-времени через constructor injection, чтобы создание, обновление и граничные случаи одинаковых временных меток были детерминированно проверяемы без отдельного глобального clock service;
- фильтр каталога перед запросом проходит `trim()`; пустой результат означает отсутствие фильтра, а непустой результат проверяется общей Unicode-функцией и должен содержать не больше 255 расширенных графемных кластеров до построения search key; допустимое значение проходит регистронезависимое Unicode-преобразование, совпадающее с ключом поискового индекса, сохраняя внутренние пробелы и различие `е`/`ё` и диакритики; превышение возвращает validation failure без storage query, а UI локализует ошибку и сохраняет введённый текст для исправления;
- cursor строится из выбранной временной метки и `IntentionId`, которые вместе задают полную неизменяемую границу значений; существование прежней граничной строки для продолжения запроса не требуется, а идентификатор является только автоматическим tie-breaker и не становится пользовательской настройкой;
- страница и её `totalCount` читаются в одной read transaction из одного SQLite snapshot, чтобы интерфейс не показывал количество от другого состояния данных;
- UI-подтверждения готовности и необратимого удаления происходят до command, но repository повторно проверяет предметные предусловия непосредственно внутри транзакции;
- ошибки не локализуются в repository: failure содержит стабильный код и безопасные структурированные данные, а ViewModel выбирает системную строку текущей локали.

Для идентификатора используется случайный UUID v4 из `package:uuid`. Пакет генерирует RFC 4122/RFC 9562 UUID на всех поддерживаемых платформах с криптографически стойким источником случайности согласно [документации package](https://pub.dev/packages/uuid). Автоинкрементный идентификатор SQLite отклонён, потому что привязывает идентичность к одной локальной базе и осложняет будущую синхронизацию. UUID v7 отклонён, поскольку сортировка по времени создания не является предметным требованием, а кодирование времени в идентификаторе не даёт текущей capability ценности.

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
- После debounce Catalog ViewModel получает первую страницу. `ScrollController` инициирует `loadNextPage`, когда до конца остаётся не больше `prefetchRemaining` элементов; synchronous single-flight guard не допускает второй запрос той же страницы. Success добавляет только новые summaries по `IntentionId`, обновляет точный count и cursor, `nextCursor == null` прекращает подгрузку, а failure сохраняет прежние items и предоставляет retry той же страницы.
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

Для локального хранения выбирается Drift поверх SQLite через `drift` и `drift_flutter`; генерация выполняется `drift_dev` и `build_runner`. На момент design проверены совместимые с Dart 3.13.1 версии `drift` 2.34.3 и `drift_flutter` 0.3.1. Drift выбран за типизированные запросы, реактивные streams, транзакции и инструменты миграций; эти возможности описаны в [официальной документации Drift](https://drift.simonbinder.eu/).

Версия схемы 1 содержит таблицу `intentions`:

| Поле | Хранение | Ограничение |
| --- | --- | --- |
| `id` | `TEXT` | primary key, UUID v4 |
| `title` | `TEXT` | `NOT NULL`, непустое нормализованное значение |
| `title_search_key` | `TEXT` | `NOT NULL`, внутренний регистронезависимый ключ фильтра; не входит в предметную модель |
| `description` | `TEXT NULL` | `NULL` означает отсутствие; непустой текст хранится посимвольно |
| `is_action_ready` | SQLite boolean | `NOT NULL`, начальное значение `false` |
| `is_archived` | SQLite boolean | `NOT NULL`, начальное значение `false` |
| `created_at` | `INTEGER` | `NOT NULL`, UTC-время в микросекундах от Unix epoch, неизменяемое после создания |
| `updated_at` | `INTEGER` | `NOT NULL`, UTC-время в микросекундах от Unix epoch, равно `created_at` при создании |

Уникального индекса на `title` нет. `title_search_key` вычисляется repository из уже нормализованного названия единым Unicode-преобразованием регистра и никогда не показывается вместо исходного текста; `е`/`ё` и диакритика не сворачиваются. Идентификатор не переиспользуется после удаления. SQL-ограничения защищают обязательность и форму сохранённых значений, но не заменяют предметную валидацию расширенных графемных кластеров в repository: SQLite не является источником истины для пользовательски воспринимаемой длины Unicode-текста. Все запросы строятся типизированным API Drift или параметризованными variables; пользовательский текст не конкатенируется с SQL.

Версия 1 также создаёт external-content virtual table `intention_titles_fts` через SQLite FTS5 с `tokenize = 'trigram case_sensitive 0 remove_diacritics 0'`, индексирующую `title_search_key` и связанную с hidden `rowid` таблицы `intentions`. Insert/update/delete triggers обновляют FTS-индекс в той же transaction, что и основную строку; миграционная проверка сравнивает количество и содержимое индексируемых записей с основной таблицей. FTS5 включается для Drift generated queries через `sqlite_module: [fts5]`; [Drift поддерживает FTS5 virtual tables](https://drift.simonbinder.eu/sql_api/extensions/), а [trigram tokenizer SQLite предназначен для substring matching](https://www.sqlite.org/fts5.html#the_trigram_tokenizer). Используемая `package:sqlite3` native build включает `SQLITE_ENABLE_FTS5` согласно её [официальным build options](https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html).

Допустимый непустой фильтр, чей готовый search key содержит не меньше трёх кодовых точек Unicode, преобразуется в безопасно экранированную единственную FTS phrase и передаётся параметром `MATCH`; это не позволяет пользовательскому тексту стать FTS operator. Поскольку trigram не индексирует подстроки короче трёх кодовых точек, допустимый search key из одной или двух кодовых точек использует параметризованный `instr(title_search_key, query_search_key)` по основной таблице. Фильтр длиннее 255 расширенных графемных кластеров отклоняется до построения search key и FTS phrase, открытия read transaction, `COUNT` или чтения строк. Обе ветви допустимого поиска дополнительно проверяются одинаковыми fixtures, чтобы наблюдаемая семантика буквальной подстроки не зависела от выбранного пути.

`getCatalogPage` применяет scope и фильтр до count и порядка. Active/archive используют явный predicate `is_archived`, all не добавляет его. Для каждого поля времени создаются индексы, поддерживающие `ORDER BY <timestamp> ASC|DESC, id ASC`; cursor predicate сравнивает выбранную временную метку, а при её равенстве — `id`. Repository запрашивает `pageSize + 1` summaries, возвращает не больше `pageSize` и строит следующий cursor только при наличии дополнительной строки. Offset не используется, поэтому стоимость прохода не растёт пропорционально номеру условной страницы. Точный `COUNT` и строки порции выполняются внутри одной read transaction и видят один SQLite snapshot.

`watchById` использует запрос по primary key и сохраняет прежнюю реактивную семантику. Drift stream выдаёт начальный snapshot и повторно выполняется после подтверждённой записи согласно [документации stream queries](https://drift.simonbinder.eu/dart_api/streams/).

Каждый изменяющий command выполняется в транзакции и сообщает успех только после commit. Создание записывает один UTC-момент в `created_at` и `updated_at`; command, который фактически меняет подтверждённое состояние, атомарно записывает новое `updated_at` вместе с изменёнными данными. Отклонённый, отменённый, завершившийся ошибкой или не меняющий данные command сохраняет прежние временные метки. Это поддерживает правило «целиком или никак» и не публикует промежуточные snapshots; Drift гарантирует атомарную видимость транзакций для внешних streams согласно [документации транзакций](https://drift.simonbinder.eu/dart_api/transactions/). Уже в версии 1 при открытии включается `PRAGMA foreign_keys = ON`, чтобы следующие change могли добавлять ссылочную целостность без смены режима работы базы.

`AppDatabase` принимает `QueryExecutor`: Android production connection явно передаёт `getApplicationDocumentsDirectory` как `DriftNativeOptions.databaseDirectory` в `driftDatabase(name: 'doable', ...)`, получает файл `doable.sqlite` и выполняет SQLite в background isolate, а тесты используют `NativeDatabase.memory()`. Зафиксированный `path_provider_android` разрешает этот каталог через `Context.getDir("flutter")`, то есть как `root/app_flutter/` в терминах Android Auto Backup. Оба набора Android backup rules исключают весь `root/app_flutter/` для cloud backup и device-to-device transfer; исключение каталога охватывает основной файл, соседние WAL/SHM и другие создаваемые SQLite служебные файлы, а SQLite temp directory находится в не включаемом в backup cache storage. Production locator и backup rules образуют один проверяемый Android host contract: тест разрешает выбранные connection name/directory в ожидаемые `domain/path` и падает при расхождении любого из них. Android-specific расположение и backup domain не пересекают `AppDatabase`, `IntentionRepository` или предметные interfaces. Общая дополнительная storage interface поверх Drift не вводится: подстановка уже находится на существующей seam `QueryExecutor`, поэтому ещё один pass-through только увеличил бы interface.

`SharedPreferences` отклонён: он не даёт реляционных ограничений, транзакций и проверяемых миграций для будущего графа. `sqflite` остаётся работоспособной альтернативой с меньшим code generation, но требует вручную поддерживать SQL, mapping, реактивное обновление и миграционные проверки; эта сложность будет расти в следующих change.

### 5. Bootstrap, миграции и восстановление после ошибок

Capability `local-data-lifecycle` владеет bootstrap, версиями и миграциями всего локального хранилища независимо от конкретных предметных таблиц. Приложение запускает локализуемый bootstrap shell до открытия feature routes. Он асинхронно открывает базу, проверяет совместимость версии, применяет необходимые миграции и только затем создаёт `IntentionRepository`. Пока операция идёт, показывается loading. Устранимая ошибка открытия или миграции даёт безопасное локализованное сообщение и retry; ошибка несовместимой более новой схемы вместо retry сообщает о необходимости установить совместимое обновление приложения. Ни одна ошибка открытия, совместимости или миграции не приводит к автоматическому удалению или пересозданию файла.

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

При upgrade `PRAGMA foreign_keys = OFF` выполняется до начала транзакции, поскольку SQLite не меняет этот режим внутри активной транзакции. Затем одна write transaction охватывает все generated пошаговые переходы от исходной версии к целевой через `Migrator.runMigrationSteps`: DDL-изменения таблиц, ограничений, индексов, triggers и views; DML-перенос или backfill пользовательских данных; а также обязательный `PRAGMA foreign_key_check` до commit. Сложное изменение ограничения или типа столбца использует безопасное перестроение таблицы: создать новую схему, перенести и преобразовать строки, удалить старую таблицу, переименовать новую и восстановить индексы внутри той же транзакции. `VACUUM` и другие операции, которые SQLite не допускает в транзакции, не входят в migration step.

Только успешное завершение всех шагов и проверки подтверждает целевую версию. Exception либо остановка процесса до commit откатывает изменения схемы, индексов, ограничений и данных; тесты также доказывают, что marker версии не продвинулся. Неуспешное соединение закрывается, а следующая попытка начинает переход из последней целостной версии. После успешной миграции `beforeOpen` явно включает `PRAGMA foreign_keys = ON` до любого feature query.

Если сохранённая версия схемы выше `AppDatabase.schemaVersion`, bootstrap возвращает отдельный non-retryable `incompatibleSchema` failure до создания repository. Приложение не выполняет feature query, запись, downgrade, удаление или пересоздание файла; единственное предлагаемое восстановление — установка совместимой более новой версии приложения. Версии схемы ниже `1`, отсутствующая или структурно повреждённая metadata классифицируются как corruption, а не пытаются угадать исходную версию.

Для каждой версии схемы:

1. увеличивается `schemaVersion`;
2. сохраняется и навсегда коммитится schema snapshot в `drift_schemas/` до публикации release;
3. добавляется один переход `fromNToN+1`, способный изменить схему и данные без destructive fallback;
4. генерируется и выполняется прямой тест перехода с каждой опубликованной исходной версии до новой целевой версии;
5. для каждого исходного snapshot проверяются итоговая схема, marker версии, сохранность fixture-данных и `foreign_key_check`;
6. fault-injection tests доказывают rollback схемы, данных и marker версии при exception внутри каждого нового migration step, а file-backed integration test проверяет повторное открытие после прерывания;
7. fixture с версией выше текущей доказывает отказ от feature query, записи, downgrade и destructive recovery.

Drift рекомендует сохранять схемы, генерировать пошаговые migration helpers и проверку переходов; `migrateAndValidate` сравнивает фактическую и ожидаемую схему, что описано в [руководстве по тестированию миграций](https://drift.simonbinder.eu/migrations/tests/). Снимки схемы и сгенерированный код коммитятся вместе с исходным описанием схемы, а CI проверяет отсутствие незакоммиченного результата генерации. Если будущий migration step нельзя безопасно завершить одной короткой bootstrap-транзакцией, соответствующий change обязан до публикации отдельно спроектировать поэтапный backfill и совместимость нескольких форматов; текущая реализация не запускает такое преобразование в фоне неявно.

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

Repository преобразует ожидаемые validation, not-found, conflict, unavailable и corruption outcomes в закрытый набор failures. Bootstrap отдельно различает retryable opening/migration failure, corruption и non-retryable `incompatibleSchema`; последний содержит только ожидаемую и обнаруженную версии схемы и требует обновления приложения. Неожиданные exceptions перехватываются на ближайшей ответственной seam, передаются в diagnostics и превращаются в общий безопасный failure; stack trace и внутренние детали пользователю не показываются. Типизированный `Result` следует документированному Flutter подходу к [обработке ошибок между слоями](https://docs.flutter.dev/app-architecture/design-patterns/result).

Локальный `DiagnosticsSink` имеет production adapter поверх `dart:developer` и in-memory adapter для тестов. Фиксируются только:

- начало, успех или failure bootstrap и миграции;
- тип intention command, длительность, outcome и безопасный failure code;
- начало, длительность, page size и outcome чтения порции каталога, а также начало и failure подробных данных;
- версия схемы и длительность открытия базы.

Пользовательский текст фильтра, названия, описания, UUID, cursors и SQL-параметры не фиксируются. Внешний telemetry adapter не добавляется, но seam позволяет в будущем подключить его отдельным решением с явной политикой приватности.

### 9. Стратегия проверки

Test surface совпадает с interfaces модулей:

- unit tests предметных значений и `IntentionRepository` на in-memory SQLite покрывают Unicode-нормализацию названия, границы 1/255/256 для названия и 4096/4097 для описания с составными графемами, точное сохранение описания, одинаковые названия, стабильный UUID, временные метки, три scope, четыре комбинации порядка, готовность, архивирование, восстановление и удаление;
- repository integration tests проверяют допустимые размеры страницы 1 и 100, validation failure для 0 и 101 без storage query, точный count, cursor boundary при равных timestamps, продолжение того же query после создания и изменения граничной строки, отсутствие offset, буквальную регистронезависимую фильтрацию на русском и английском, границы фильтра 255/256 расширенных графемных кластеров, отсутствие SQLite/FTS/`COUNT` для превышения, отдельную ветвь для 1–2 символов, различие `е`/`ё` и диакритики, атомарную согласованность FTS triggers, streams подробных данных после commit, закрытую/повреждённую базу и преобразование storage exceptions в failures;
- отдельный large-fixture test создаёт не меньше 50 000 коротких активных и архивированных намерений, проверяет через `EXPLAIN QUERY PLAN` использование FTS virtual table для фильтра от трёх символов и timestamp/cursor indexes для неотфильтрованных порций, а также доказывает, что одна repository operation материализует не больше настроенного `pageSize`, даже когда точный count значительно больше;
- unit tests общего `ExclusiveOperation` проверяют синхронный переход в `running`, отсутствие запуска или очереди второго действия, освобождение gate после success/failure и независимость экземпляров; тесты generated Riverpod ViewModels и providers используют отдельный `ProviderContainer` с overrides на fake repository и проверяют initial loading/data/empty/failure, накопление порций, single-flight следующей страницы, inline failure/retry, конец выдачи, debounce, отклонение устаревшего результата, три scope, четыре порядка, точный count, подмену `CatalogPagingPolicy` и согласование typed command result после нескольких порций. Параметризованная матрица `createdAt`/`updatedAt` × ascending/descending покрывает создание и изменение внутри и после boundary, неизменность cursor, немедленное обновление count, сохранение visual anchor и последующую подгрузку без пропусков, повторов или преждевременно показанного намерения;
- widget tests проверяют русскую, английскую и fallback локали, локализованную валидацию длины названия, описания и фильтра, сохранение недопустимого фильтра для исправления без repository call, фильтр по названию, отображение точного количества, автоматическую подгрузку у threshold, сохранение scroll position, выбор scope/поля/направления, все подтверждения, отсутствие перевода пользовательского текста, навигацию и not-found;
- accessibility tests проверяют semantics labels/states, tap targets, contrast и layout при text scale 200%; критические потоки дополнительно проходят ручную проверку TalkBack на Android;
- Drift schema snapshots и generated migration tests проверяют прямой переход с каждой опубликованной версии до текущей, итоговую схему, marker версии, сохранность данных, `foreign_key_check`, rollback при fault injection и отказ от открытия более новой схемы для записи;
- file-backed repository integration test создаёт представительные активные и архивированные намерения, закрывает `AppDatabase` и отбрасывает первый `IntentionRepository`, затем создаёт новый persistence object graph на том же SQLite-файле и проверяет прежние идентификаторы, текст, готовность к действию, архивное состояние, timestamps, фильтр и точный count через публичную seam; отдельный file-backed migration test проверяет FTS consistency и повторное открытие после прерывания upgrade.
- Android host contract test разрешает явно выбранные `getApplicationDocumentsDirectory` и `doable.sqlite` в `root/app_flutter/doable.sqlite`, структурно читает оба набора backup rules и доказывает исключение всего `root/app_flutter/` для cloud backup и device-to-device transfer; отрицательные fixtures с прежним `database` domain или неполным путём обязаны падать.

Тестовые названия и описания пишутся по-русски. Авторитетная CI-среда репозитория — GitHub Actions. Обязательный PR gate запускается на Linux runner из чистого checkout, устанавливает только явно зафиксированные версии используемых инструментов, разрешает Dart/Flutter-зависимости без изменения committed lockfile, повторяет генерацию локализации, Riverpod, AutoRoute, Drift code и schema/migration artifacts и падает при любом tracked или untracked результате генерации. Затем gate выполняет анализ, полный test suite с file-backed repository и migration tests, собирает release-mode APK, проверяет его manifest permissions и запускает `openspec validate --all --strict --no-interactive`. Статус этого workflow настраивается как обязательная проверка защищённой основной ветки.

Android device/emulator job в этот change не входит. Release-mode APK и manifest проверяются на CI runner без запуска приложения на Android, а автоматизированные unit, widget, accessibility и file-backed tests не заявляются доказательством platform bootstrap после завершения процесса. Ручной TalkBack smoke test выполняется отдельно на Android до merge и фиксируется как внешнее evidence; принятый остаточный риск Android-specific wiring остаётся ограничен так, как описано ниже.

## Риски / Компромиссы

- **[Drift, AutoRoute, Riverpod и code generation увеличивают build complexity]** → Зафиксировать lockfile, коммитить generated code и schema snapshots, проверять генерацию без diff в CI и обновлять зависимости отдельно от предметных change.
- **[Riverpod dependency graph может вызвать широкие rebuilds или непреднамеренно удержать экранное состояние]** → Публиковать неизменяемый state, использовать automatic disposal для экранных providers, наблюдать узкие presentation providers и добавлять `select` только после измеренной проблемы.
- **[Automatic retry Riverpod может скрыть первый failure и нарушить явную модель повторной попытки]** → Отключить глобальный retry в `ProviderScope` и повторять только целевой provider по явному действию пользователя.
- **[Каталог может со временем содержать десятки тысяч намерений]** → Никогда не предоставлять unbounded query, читать только `IntentionSummary` ограниченными keyset-порциями, лениво строить widgets и проверять maximum materialization на fixture из 50 000 строк.
- **[Точный count добавляет отдельную работу к каждой новой комбинации scope и фильтра]** → Выполнять count внутри того же SQLite read snapshot, использовать FTS5 для подстрок от трёх символов, debounce ввода и проверять query plan на большом fixture; не выполнять count повторно на каждое событие прокрутки уже открытого запроса.
- **[FTS-индекс может разойтись с основной таблицей после ошибки записи или миграции]** → Обслуживать external-content index транзакционными triggers, включить его создание и backfill в schema/migration tests и проверять consistency до принятия миграции.
- **[Cursor может вернуть пропуски или повторы при неполном порядке, смене параметров либо command между порциями]** → Включать timestamp и `IntentionId` в полный порядок, хранить cursor как value boundary без зависимости от существования строки, связывать его с нормализованными параметрами запроса, отбрасывать только при их изменении и проверять создание/изменение до и после boundary с последующей подгрузкой.
- **[Ошибка или остановка процесса во время миграции может временно сделать приложение недоступным]** → Охватывать DDL, DML, проверку целостности и продвижение marker версии одной проверяемой транзакцией, никогда не удалять базу автоматически и давать retry из последней целостной версии.
- **[Автотесты не воспроизводят завершение Android-процесса и повторный platform bootstrap]** → Доказывать файловую долговечность полным закрытием persistence object graph и повторным открытием того же SQLite-файла, отдельно проверять crash recovery миграций, статически связывать production locator `root/app_flutter/doable.sqlite` с backup rules и собирать release-mode APK. Остаточный риск ошибки только в Android runtime wiring принят для текущего change; device E2E и `adb`-orchestrator не вводятся без отдельного подтверждённого основания.
- **[Старая версия приложения может встретить более новую схему после rollback APK]** → Возвращать non-retryable `incompatibleSchema` без feature query и записи, не выполнять downgrade и выпускать forward fix.
- **[Перестроение будущей большой таблицы может превысить приемлемое время bootstrap или свободное место]** → Измерять migration step на репрезентативных fixtures в соответствующем change; до release отдельно проектировать поэтапный backfill, если короткая атомарная транзакция больше не подходит.
- **[Граница одной установки приводит к потере данных при удалении приложения, очистке данных или утрате устройства]** → Ограничить текущее обещание долговечности перезапусками и совместимыми обновлениями внутри одной установки; сохранить storage-neutral seam для будущей управляемой синхронизации, но не добавлять её transport, конфликтные правила или метаданные без наблюдаемого поведения.
- **[Sandbox не защищает от root-доступа или полностью скомпрометированного разблокированного устройства]** → Не обещать app-level secrecy, не добавлять сетевые и backup copies; пересмотреть encryption/app lock при изменении модели угроз.
- **[UUID v4 теоретически может столкнуться]** → Primary key является последней защитой; collision возвращает безопасный conflict и не перезаписывает существующее намерение.
- **[UI и repository могут по-разному посчитать составной Unicode-символ]** → Использовать одну функцию подсчёта расширенных графемных кластеров, проверять границы составными emoji и не полагаться на число UTF-16 code units или SQLite `length()`.
- **[Локальная диагностика не сообщает о проблеме удалённо]** → Сохранить безопасные структурированные события и adapter seam; внешний сбор добавлять только отдельным change с политикой приватности.

## План миграции

1. Добавить и зафиксировать совместимые зависимости `flutter_riverpod`, `riverpod_annotation`, `auto_route`, `uuid`, `characters`, `drift`, `drift_flutter`, `flutter_localizations`, а также `riverpod_generator`, `auto_route_generator` и остальные dev-зависимости генерации; проверить supply-chain metadata и lockfile.
2. Ввести корневой `ProviderScope`, generated providers composition root, bootstrap shell, локализацию и routing, сохранив доступный loading/error до готовности базы.
3. Явно связать Android production connection `root/app_flutter/doable.sqlite` с исключением всего `root/app_flutter/` в обоих наборах backup rules и их contract test, затем создать `AppDatabase` schema version 1 с временными метками намерения, внутренним поисковым ключом, FTS5 trigram-индексом и его triggers, initial schema snapshot, атомарным migration harness, проверкой несовместимой более новой версии и in-memory executor.
4. Реализовать глубокий `IntentionRepository` с ограниченным `getCatalogPage`, точным count, keyset cursor, предметными моделями и failures, затем generated Riverpod ViewModels, `CatalogPagingPolicy`, immutable operation states и Views.
5. Заменить экран-заглушку каталогом с тремя scopes, фильтром, четырьмя порядками и автоматической подгрузкой только после прохождения repository, large-fixture, migration, localization и accessibility tests.
6. Перед merge провести обязательный GitHub Actions PR gate с воспроизводимой генерацией без изменений, анализом, полным test suite, file-backed проверками, release-mode сборкой, проверкой manifest и строгой OpenSpec-валидацией; отдельно выполнить и зафиксировать ручной TalkBack smoke test на Android.

Для первой версии capability миграция идёт от отсутствующей базы к schema version 1 и не затрагивает прежние пользовательские данные. Пока приложение не опубликовано, rollback выполняется обычным возвратом исходников и lockfile, а ещё не опубликованный schema snapshot может быть заменён согласованно с кодом. После будущей публикации каждый следующий release хранит все опубликованные snapshots и шаги, поэтому пользователь может обновиться сразу с любой прежней версии схемы. Downgrade migrations не поддерживаются: rollback приложения допустим только при совпадающей или явно совместимой схеме, а при более новой схеме старое приложение отказывается от записи без удаления файла. Основная стратегия исправления после публикации — forward fix с более высоким номером версии приложения и совместимой схемой; ни один rollback или retry не удаляет базу автоматически. Локальный `flutter run --release` и локальный либо CI-запуск `flutter build apk --release` в текущем change не создают артефакт для распространения и не являются checkpoint готовности к публикации; signing и канал поставки должны быть определены отдельным change перед первой публикацией.

## Открытые вопросы

Отсутствуют.

Пересмотр ADR-0001 завершён принятым ADR-0005: граница глубокого модуля сохранена, а наблюдение всего каталога заменено ограниченными страничными snapshot-запросами. Действующими являются ADR-0002–ADR-0005; ADR-0001 остаётся только историческим контекстом. Других действующих ADR, требующих пересмотра или supersession, нет.
