# OpenSpec Change Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Planning artifacts содержат связную и проверяемую Phase 8
  remediation, включая обязательное исполнение negative-path evidence
  generated-artifact detector в task 8.9. AR1, AR2 и AR3 остаются явно
  принятыми рисками.
**Validation:** `openspec validate manage-intentions --type change --strict --no-interactive` успешен для текущих planning artifacts; на прежнем reviewed implementation head также были успешны Dart MCP analysis, воспроизводимая генерация и `mise run check` с 331 тестом. GitHub подтверждает зелёный `Full checks` на tree этого reviewed head и required status context `Full checks` для `main`. Эти результаты не квалифицируют Android process restart, Android latency или фактическую работу TalkBack на устройстве.

## Findings

No unresolved findings remain in the reviewed change artifacts and relevant repository context.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** ADR-0006, действующие specs и `design.md` считают UTC wall-clock timestamps независимыми наблюдениями; каталог использует сохранённое значение и `IntentionId` как tie-breaker без causal clock.
- **Potential impact:** Быстрые операции или перевод часов могут дать одинаковые либо убывающие timestamps, поэтому выбранный порядок иногда не совпадёт с фактической последовательностью действий.
- **Acceptance rationale:** Отдельная revision/logical-clock модель или синтетическое продвижение времени несоразмерны вспомогательной сортировке и исказили бы наблюдаемое wall-clock значение.
- **Scope and assumptions:** Timestamps не используются как revision, causal order, средство синхронизации, аудита или разрешения конфликтов.
- **Reopen when:** Timestamps получают хронологически значимое поведение, появляется синхронизация/разрешение конфликтов либо наблюдается существенный ущерб от перестановок.
- **Acceptance authority:** Явное решение пользователя от 2026-09-03.
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** ADR-0006, соответствующие требования intention-management spec и раздел рисков `design.md`.

### AR2 · Android process restart и production wiring не проверены на device/emulator

- **Evidence:** File-backed и app-runtime tests закрывают и повторно открывают тот же SQLite object graph, CI собирает release APK и проверяет packaged manifest, но `design.md` и task 8.6 исключают device/emulator integration test и не называют эти проверки Android relaunch evidence.
- **Potential impact:** Ошибка только в Android plugin/host wiring может проявиться при production bootstrap или повторном запуске, несмотря на успешные platform-neutral и file-backed tests.
- **Acceptance rationale:** Для первой интеграции человек решил не добавлять device/E2E infrastructure; имеющееся evidence остаётся полезным в своей более узкой границе без ложной runtime qualification.
- **Scope and assumptions:** Первая локальная Android capability внутри одной установки; публикация, device qualification и production release readiness остаются вне change.
- **Reopen when:** Наблюдается Android bootstrap/relaunch failure, меняется host wiring или capability готовится к publication/device qualification.
- **Acceptance authority:** Явное решение пользователя не добавлять интеграционные тесты, закреплённое в task 8.6 и `design.md`.
- **Originating finding:** F11
- **Acceptance lifetime:** Change-scoped

### AR3 · Linux budget короткого фильтра не доказывает Android latency

- **Evidence:** Large file-backed suite на 50 000 строк проверяет p95 не выше 100 мс в Linux; `design.md` и tasks 8.2/8.6 прямо запрещают считать результат Android latency measurement, а device benchmark отсутствует.
- **Potential impact:** На слабом Android-устройстве scan одной-двух кодовых точек вместе с точным `COUNT` может задерживать актуальный результат после debounce.
- **Acceptance rationale:** Человек решил не добавлять Android performance/integration infrastructure; bounded paging, debounce и Linux regression budget ограничивают риск без ложного Android SLO.
- **Scope and assumptions:** До 50 000 локальных намерений, текущие query/schema/search strategy и отсутствие обещанного Android latency SLO.
- **Reopen when:** Появляется наблюдаемая задержка, меняется объём или search strategy либо вводится Android latency/SLO или publication criterion.
- **Acceptance authority:** Явное решение пользователя не добавлять интеграционные тесты, закреплённое в task 8.6 и `design.md`.
- **Originating finding:** F12
- **Acceptance lifetime:** Change-scoped

## Review coverage

Broad re-audit охватил proposal, оба delta spec, design, ADR manifest и ADR-0001–ADR-0008, plan, tasks, прежние review states и полный committed implementation range после предыдущего reviewed head. Требования прослежены через repository raw data, schema functions, revisions, process-local coordinator, bootstrap ownership, routing, локализацию, автоматизированную доступность, diagnostics allowlist, Android host privacy и Phase 8 CI. Для packaged Android permissions текущий контракт прослежен от exact allowlist и `signature`-декларации в ADR-0004 через fail-closed design до task 8.8 с положительной и отрицательными fixtures.

Предыдущий implementation review доказал Phase 6 schema/NUL/bounded-catalog increment и сохранил AR1; текущий implementation review повторно проверил изменившийся repository и независимо покрыл presentation/composition и CI. Автоматизированные проверки подтвердили Unicode corpus, schema-function setup, file-backed persistence, migration/schema validation, localization, semantics/guidelines/text scale, release APK build и packaged backup references в указанных границах.

Ручная TalkBack qualification и device/emulator evidence отсутствуют по утверждённой границе. APK build и Linux tests не считаются доказательством Android restart, Android latency или фактического TalkBack. Эти границы сохранены как явно принятые AR2 и AR3. Неотмеченные задачи Phase 8 остаются implementation work и не являются пробелами текущего planning review; их фактическое выполнение и обязательный CI run проверяются task 8.10.
