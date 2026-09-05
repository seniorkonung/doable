# Проверка OpenSpec change: manage-intentions

## Оценка

**Результат:** Changes needed

Новая типобезопасная connection boundary направлена на правильную корневую
проблему, а последовательность зависимостей `6.20b → 6.20c → 6.21 → 6.22 →
6.23 → 6.24 → 6.25 → 6.26` не содержит обратных или пропущенных связей. Однако
артефакты пока не дают implementer непротиворечивого и полностью исполнимого
контракта: design и задачи описывают ленивый Drift setup как уже выполненный
и ошибочно распространяют одну executor capability на эталонное соединение
schema verifier, которое создаётся самим
`drift_dev` через отдельный callback. Кроме того, ownership mapping-drift
evidence пересекается между 6.20c и 6.22.

Предложение и behavioral specs менять не требуется: они владеют наблюдаемым
пользовательским и local-data lifecycle поведением, а обсуждаемая correction
остаётся внутренним механизмом исполнения уже утверждённого schema-function
contract. Принятый остаточный риск `AR1` сохраняется и не считается активным
замечанием.

**Валидация:** `openspec validate manage-intentions --type change --strict
--no-interactive`, `openspec schema validate intent-driven --json` и
`git diff --check` успешны. Структурная валидация OpenSpec не выявляет
перечисленные архитектурные и dependency-semantics расхождения.

## Замечания

### F2 · High — `ConfiguredLocalDatabaseConnection` обещает состояние, которого не может доказать на всех connection paths

- **Доказательства:** `design.md:340`, `design.md:543` и `tasks.md:649` описывают
  capability как создаваемую после уже применённого обязательного setup. В
  текущих factories `lib/src/data/local/database_connection.dart:32`–`45`
  создаётся ленивый `QueryExecutor`; Drift вызывает `_setup` только при первом
  открытии underlying database, до migrations/schema use, а не при создании
  wrapper. Отдельно `design.md:522` и `tasks.md:650` утверждают, что обе стороны
  schema verification проходят через capability. Фактические вызовы
  `validateDatabaseSchema` в
  `test/data/local/migrations/migration_test.dart:19` и
  `test/data/local/file_backed_database_test.dart:180`/`:215` передают
  `configureDoableSqliteConnection` отдельным параметром `setup:`; эталонную
  database создаёт внутри себя `drift_dev`, поэтому она не может получить
  `ConfiguredLocalDatabaseConnection` от application factory.
- **Влияние:** реализация может формально ввести новый тип и всё равно оставить
  недоказанный verifier callback либо неверно считать функцию уже
  зарегистрированной до открытия. Новый тип тогда создаёт ложную гарантию и не
  закрывает фундаментальный класс обхода для следующих schema-functions.
- **Требуемое изменение:** определить capability как доказательство того, что
  канонический setup привязан к ленивому executor и будет выполнен до любого
  schema use, а не как доказательство уже завершённой регистрации. Для verifier
  нужна отдельная закрытая Doable verification seam/helper, которая принимает
  configured actual database и сама передаёт тот же канонический setup каждой
  создаваемой `drift_dev` эталонной connection; прямые вызовы
  `validateDatabaseSchema(setup: ...)` должны исчезнуть из обычных harnesses.
  Diagram, risk, migration plan, 6.20b и 6.20c должны различать эти две формы
  enforcement.

### F3 · Medium — Задачи смешивают synthetic connection evidence с фактическим mapping drift generated schema

- **Доказательства:** 6.20c в `tasks.md:664` уже требует две реализации
  mapping-drift и dependent-schema evidence до выполнения 6.21, тогда как 6.22
  в `tasks.md:689` снова назначает той же fixture две реализации и только после
  6.21 проверяет реальный `STORED GENERATED ALWAYS` key и FTS. До 6.21 текущая
  schema хранит независимо записываемый `title_search_key`, поэтому реальный
  межрелизный mapping-drift contract приложения ещё нечему наблюдать. При этом
  6.20c не объявляет, что supersedes оставшиеся невыполненные claims завершённой
  6.20a о missing-setup/composed-setup evidence и прежний ownership wording
  задачи 6.8.
- **Влияние:** implementer либо преждевременно потянет schema work 6.21 в 6.20c,
  либо продублирует file-backed drift matrix в двух задачах; completion ledger
  продолжит одновременно считать старый широкий контракт 6.20a выполненным и
  планировать его недостающие части без однозначного ownership.
- **Требуемое изменение:** оставить 6.20c migration/collision/missing-setup
  evidence на минимальной synthetic dependent schema и явно передать ей
  оставшиеся corrective claims 6.20a и lifecycle wording 6.8. Фактические две
  версии mapping function над `title_search_key STORED GENERATED` и FTS должны
  принадлежать только 6.22 после 6.21. Финальный checkpoint 6.26 должен явно
  включить evidence типизированной connection и verifier boundaries, а не
  полагаться только на транзитивную зависимость.

## Принятые риски

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Доказательства:** действующие specs, design и ADR-0006 считают UTC
  wall-clock timestamps наблюдениями; каталог использует сохранённое значение и
  `IntentionId` как tie-breaker без causal clock.
- **Потенциальное влияние:** быстрые операции или перевод часов могут дать
  одинаковые либо убывающие timestamps, поэтому выбранный пользователем порядок
  иногда не совпадёт с фактической последовательностью действий.
- **Обоснование принятия:** отдельная revision/logical-clock модель или
  синтетическое продвижение времени несоразмерны вспомогательной сортировке и
  исказили бы наблюдаемое wall-clock значение.
- **Граница и предпосылки:** timestamps не используются как revision, causal
  order, средство синхронизации, аудита или разрешения конфликтов.
- **Пересмотреть, когда:** timestamps получают хронологически значимое
  поведение, появляется синхронизация/разрешение конфликтов либо наблюдается
  существенный пользовательский ущерб от перестановок.
- **Кем принято:** явное решение пользователя от 2026-09-03.
- **Исходное замечание:** F1 предыдущего implementation review.
- **Запись решения:** ADR-0006, соответствующие требования intention-management
  spec и раздел рисков design.

## Охват проверки

В рамках выбранного исправления проверено согласование ADR-0002, ADR manifest,
design, Phase 6 и задачи 6.20b с общей типизированной connection boundary.
Статусы и принадлежность ADR сверены с правилами схемы: собственные ADR активного
change остаются `proposed` и редактируются до архивации, которая переводит их в
`accepted`. Проверено, что proposal и behavioral specs не требуют изменений,
а корректирующая задача явно заменяет прежний допуск raw executor без
переписывания выполненных задач и фаз.

Замечания F2 и F3 и принятый риск AR1 сохранены; эта сфокусированная проверка
не является повторным полным аудитом и не закрывает оставшиеся замечания.
Их доказательства опираются на проверенные при исходном аудите connection
factories, test harnesses и pinned исходники Drift: native setup выполняется
лениво, а `drift_dev` создаёт reference database через собственный `setup:`
callback. Код реализации не менялся; runtime-проверки не выполнялись.
