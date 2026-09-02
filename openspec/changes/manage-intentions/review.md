# Проверка OpenSpec change: manage-intentions — Phase 6

## Оценка

**Результат:** Требуются изменения.

Phase 6 сохраняет правильную границу: production Drift adapter должен провести полный постоянный lifecycle намерения через storage-neutral `IntentionRepository`, не забирая Riverpod, navigation и пользовательские состояния из Phase 7. Задачи 6.1–6.10 в целом трассируют catalog reads, commands, file-backed persistence, атомарность, диагностику и representative-volume evidence, однако в трёх местах implementer всё ещё должен самостоятельно выбрать наблюдаемый либо архитектурный контракт.

**Валидация:** `openspec validate manage-intentions --type change --strict --no-interactive` успешна. Это подтверждает структуру change, но не разрешает перечисленные семантические пробелы. Аудит не проверяет ещё не существующую реализацию Phase 6 и не является разрешением на Apply.

## Замечания

### F2 · Medium — `updatedAt` не определён при равном или откатившемся UTC-clock

- **Доказательства:** спецификация требует сохранять «момент последнего успешного изменения» и после фактического изменения записывать новый момент (`specs/intention-management/spec.md:230-245`); этот момент является пользовательским ключом упорядочивания (`:257-283`). Design внедряет функцию текущего UTC-времени (`design.md:185-186`), но не задаёт поведение при `now <= previous.updatedAt`. Текущий `IntentionTimestamp` проверяет только `updatedAt >= createdAt` (`lib/src/intention/domain/intention.dart:17-24`), а задачи 6.5–6.6 не содержат fixtures для равного времени или отката часов.
- **Влияние:** два фактических изменения могут получить одинаковый `updatedAt`, а после коррекции системных часов timestamp может уменьшиться. Тогда каталог «по последнему изменению» перестаёт отражать последовательность подтверждённых операций, намерение неожиданно перемещается через cursor boundary, а test author вынужден сам выбрать допустимый результат.
- **Требуемое изменение:** определить invariant обновления времени при `now == previous.updatedAt` и `now < previous.updatedAt`, провести его через spec/design/tasks и добавить deterministic clock fixtures к 6.5, 6.6 и cursor evidence 6.4.
- **Требуется решение:** обязан ли `updatedAt` быть строго монотонным для одного намерения; если да, какая утверждённая политика формирует следующий момент при неувеличившемся wall clock?

### F3 · Medium — Checkpoint Phase 6 не доказывает стоимость допустимого фильтра длиной 1–2 символа

- **Доказательства:** design направляет search key длиной 1–2 Unicode code points в `instr` по основной таблице, а фильтр от трёх — в FTS (`design.md:294`). Точный `COUNT` обязателен для каждой новой query generation (`design.md:298`, `:440`), а spec применяет фильтр автоматически и допускает любую непустую длину до 255 графем. Large-fixture evidence в `design.md:420` и `tasks.md:449-456` проверяет query plan только для FTS-фильтра от трёх символов и неотфильтрованного каталога; short-filter path на 50 000 строк не имеет объективного критерия.
- **Влияние:** Phase 6 может формально пройти checkpoint «ограниченной стоимости», не проверив поддерживаемый интерактивный путь, где первая страница и точный count требуют полного `instr` scan при каждом применённом фильтре. Возможная задержка будет обнаружена только в Phase 7 либо на реальных данных, когда смена query strategy затронет уже реализованный adapter.
- **Требуемое изменение:** добавить к representative-volume evidence запросы с 1- и 2-code-point фильтрами и заранее определить проверяемый предел либо явно принятый residual risk для их полного scan. Критерий должен охватывать первую страницу вместе с точным count и не сводиться только к числу возвращённых summaries.
- **Требуется решение:** считается ли линейный short-filter scan приемлемым контрактом текущего change, и какое измеримое evidence достаточно для такого принятия?

### F4 · Low — Ownership закрытия repository object graph сформулирован противоречиво

- **Доказательства:** публичный `IntentionRepository` содержит только `getCatalogPage`, `watchById` и `execute` (`lib/src/intention/application/intention_repository.dart:7-15`), а текущим владельцем и точкой закрытия `AppDatabase` является `LocalDataBootstrap` (`lib/src/data/local/bootstrap/local_data_bootstrap.dart:20-23,128+`). Задача 6.8 требует «полностью закрыть первый `AppDatabase` и `DriftIntentionRepository`» (`tasks.md:437-446`), хотя 6.1 не вводит repository lifecycle contract и design не передаёт adapter владение database.
- **Влияние:** implementer может добавить лишний `close` в storage-neutral seam, создать двойное владение одним executor либо написать file-backed test, который не воспроизводит production ownership.
- **Требуемое изменение:** назвать единственного владельца `AppDatabase`/executor и сформулировать 6.8 как закрытие этого владельца с отбрасыванием repository adapter, если отдельного ресурса у repository нет. Новый lifecycle API допустим только после явного архитектурного решения и трассировки в composition root Phase 7.

## Охват проверки

Проверены фактический artifact graph `proposal → specs → design → adr → plan → tasks`, только commitments Phase 6 и их необходимые связи с завершённой storage foundation Phase 5 и consumer boundary Phase 7. Повторно проверены пять основных вопросов, а углублённо — architecture/dependency ownership, public failure interface, persistent data invariants, transactions и concurrency, keyset pagination, reliability, privacy-safe diagnostics, representative-volume performance и file-backed recovery. Schema migration, platform delivery и UI не расширялись: Phase 6 не меняет schema version и не реализует presentation flows. Канонических specs для новых capability ещё нет; delta specs этого change остаются их первичным поведенческим контрактом.
