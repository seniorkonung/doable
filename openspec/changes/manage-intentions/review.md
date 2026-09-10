# OpenSpec Change Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** План теперь задаёт ожидаемый shutdown через единственного
  process-local владельца bootstrap и Riverpod container, поэтому F9 устранена.
  Три обязательные границы остаются нерешёнными: порядок detail snapshot
  относительно terminal outcome команды, фактический Android bootstrap/restart
  и производительность короткого фильтра на целевом Android host. Принятый риск
  AR1 о wall-clock timestamps остаётся применимым в прежнем объёме.
**Validation:** `openspec validate manage-intentions --type change --strict
  --no-interactive`, `openspec schema validate intent-driven --json` и
  целевой Dart-анализ текущих application/data/bootstrap seams успешны. Целевая
  повторная проверка F9 подтверждает согласованный протокол quiesce → drain →
  close для ready и in-flight bootstrap. Phase 7 ещё не реализована, поэтому её
  runtime- и widget-поведение не запускалось; Phase 8 по правилам schema получит
  task package только после завершения текущего пакета Phase 7.

## Findings

### F10 · Medium — Подробный экран не защищён от запоздалого подтверждённого snapshot прежнего состояния

- **Evidence:** requirement `Последовательное изменение одного намерения`
  требует после success показывать последнее подтверждённое состояние.
  ADR-0005 и `design.md`, решение 2, оставляют `watchById` прямым
  неревизионным stream path, а command outcome доставляют отдельно через
  coordinator; revision protocol распространяется только на catalog pages и
  mutations. Задача 7.9 делает stream provider источником details, а задача
  7.10 использует `IntentionSaved`, но не задаёт, какой результат авторитетен
  при перестановке их доставки. Её verification покрывает delayed catalog
  completion и dispose/reopen, но не pre-command detail snapshot, поступивший
  после terminal success.
- **Impact:** старый, хотя и когда-то подтверждённый, результат `watchById`
  сможет после успешного update/readiness/archive/restore временно или устойчиво
  заменить более новое состояние экрана. Пользователь увидит регрессию данных и
  сможет начать следующую операцию из устаревшего представления; storage-neutral
  contract не даёт ViewModel способа доказать, что snapshot уже новее результата
  объекта `IntentionSaved`.
- **Required change:** определить единый observable порядок или правило
  авторитетности между detail stream и terminal command outcome и добавить
  управляемые проверки перестановок для update, state transition и delete:
  запоздалое прежнее значение не возвращается после success, post-commit
  snapshot принимается, а удалённое намерение не появляется снова.

### F11 · High — Ключевая долговечность Android host не имеет runtime-доказательства

- **Evidence:** `proposal.md` обещает проверить Android host adapter и сохранять
  намерения между полными запусками. `design.md`, стратегия проверки, прямо
  исключает Android device/emulator job и признаёт, что unit, widget,
  file-backed tests, сборка APK и статическая проверка manifest не доказывают
  platform bootstrap после завершения процесса. Phase 8 требует интеграционное
  доказательство и ручной TalkBack smoke, но её readiness не требует создать
  намерение через production Android connection, полностью завершить процесс и
  восстановить данные после нового запуска. Текущий `lib/main.dart` остаётся
  заглушкой, поэтому существующий host wiring такого evidence не даёт.
- **Impact:** APK может собираться и backup rules могут быть корректны, но
  production composition, plugin path, background SQLite connection или
  lifecycle процесса могут не открыться либо не восстановить данные на
  единственной заявленной платформе. Это нарушит центральное обещание change
  только после интеграции Phase 7.
- **Required change:** выбрать и зафиксировать либо воспроизводимую Android
  runtime-проверку production bootstrap и сценария create → полное завершение
  процесса → relaunch → read, либо явно принять ограниченный остаточный риск и
  согласовать его scope, rationale и reopening conditions с design и текущим
  review state.
- **Decision needed:** должен ли change включать Android device/emulator evidence
  долговечности, или вы явно принимаете отсутствие такого доказательства для
  первой интеграции?

### F12 · Medium — Бюджет короткого фильтра не проверяется на единственном целевом host

- **Evidence:** `design.md`, решения 3–4 и риск короткого фильтра, задаёт
  debounce 250 мс и выполняет для строки из одной-двух кодовых точек линейный
  SQL-операция `instr` выполняет scan вместе с точным `COUNT`; задача 6.9
  проверяет p95 ≤ 100 мс на
  Linux CI для 50 000 намерений, а design прямо говорит, что это не обещание
  Android latency и что Android device performance job отсутствует. Phase 7
  применяет фильтр автоматически при вводе, но Phase 8 не задаёт Android budget,
  representative device profile или критерий приемлемого отклика.
- **Impact:** функциональные и Linux regression tests могут пройти, тогда как
  ввод первого или второго символа на целевом Android-устройстве будет регулярно
  задерживать актуальный результат и создавать очередь новых query generations;
  implementer не знает, при каком наблюдаемом результате менять search strategy.
- **Required change:** определить приемлемое наблюдаемое поведение короткого
  фильтра на representative Android profile и добавить соответствующее evidence
  и advance/hold criterion, либо явно принять ограниченный остаточный риск с
  условиями пересмотра до того, как Phase 8 назовёт capability доказанной.
- **Decision needed:** требуется ли Android performance evidence для короткого
  фильтра в этом change, или вы явно принимаете переносимость Linux-бюджета как
  остаточный риск?

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** действующие specs, design и ADR-0006 считают UTC wall-clock
  timestamps наблюдениями; каталог использует сохранённое значение и тип
  тип `IntentionId` как tie-breaker без causal clock.
- **Potential impact:** быстрые операции или перевод часов могут дать
  одинаковые либо убывающие timestamps, поэтому выбранный пользователем порядок
  иногда не совпадёт с фактической последовательностью действий.
- **Acceptance rationale:** отдельная revision/logical-clock модель или
  синтетическое продвижение времени несоразмерны вспомогательной сортировке и
  исказили бы наблюдаемое wall-clock значение.
- **Scope and assumptions:** timestamps не используются как revision, causal
  order, средство синхронизации, аудита или разрешения конфликтов.
- **Reopen when:** timestamps получают хронологически значимое поведение,
  появляется синхронизация/разрешение конфликтов либо наблюдается существенный
  пользовательский ущерб от перестановок.
- **Acceptance authority:** явное решение пользователя от 2026-09-03.
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** ADR-0006, соответствующие требования intention-management
  spec и раздел рисков design.

## Review coverage

Проверен фактический schema graph `proposal → specs → design → adr → plan →
tasks`, оба delta spec, ADR manifest и ADR-0001–ADR-0008, корневой предметный
словарь, прежний change review и implementation review. Commitments прослежены
через текущий Phase 7 package к verification; отсутствие Phase 8 package
признано ожидаемым по phase-by-phase правилам schema, поскольку Phase 7 ещё не
завершена. Сверены текущие `MainApp`, `IntentionRepository`, commands, sealed
results/failures, `DriftIntentionRepository`, `LocalDataBootstrap`, Android
connection/backup boundary, test layout и зафиксированные lifecycle signatures
Riverpod 3.4.2. Углублённо проверены capability ownership, public interface,
persistence, migration и rollback assumptions, async disposal, page/command и
detail/command races, operation lifetime, paging/count/cursor reconciliation,
bounded state, failure/retry semantics, privacy diagnostics, Android runtime и
performance evidence, localization, accessibility и delivery boundary. После
подтверждённой remediation F9 повторно прослежены `AppRuntime`, terminal closing
bootstrap, coordinator draining, disposal container и запрет повторного открытия
того же SQLite-файла до завершения ожидаемого shutdown; новых противоречий в
затронутой границе не обнаружено.
