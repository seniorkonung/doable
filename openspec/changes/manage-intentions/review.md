# OpenSpec Change Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Feature-specific keep-alive coordinator теперь задаёт lifetime
  принятых операций за пределами auto-dispose routes, не запрещая Back, а
  ADR-0005 теперь согласованно разделяет прямой read/query path и
  coordinator-owned command path. Revision protocol устранил неоднозначность
  порядка между completions и конкурентными snapshot-запросами, а единственный
  typed presentation claim исключает повтор уже показанного outcome после
  возврата в каталог. Закрытые состояния продолжения теперь различают локальный
  retry `unavailable`, terminal-результаты и явное восстановление `validation`
  с первой страницы; F8 устранён. Принятый риск AR1 сохраняется в прежних
  границах.
**Validation:** `openspec validate manage-intentions --type change --strict
  --no-interactive` и `openspec schema validate intent-driven --json` успешны.
  Phase 7 ещё не реализована, поэтому runtime- и widget-тесты её поведения в
  рамках этого planning audit не запускались.

## Findings

No unresolved findings remain in the reviewed change artifacts and relevant repository context.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** действующие specs, design и ADR-0006 считают UTC
  wall-clock timestamps наблюдениями; каталог использует сохранённое значение и
  идентификатор `IntentionId` как tie-breaker без causal clock.
- **Potential impact:** быстрые операции или перевод часов могут дать
  одинаковые либо убывающие timestamps, поэтому выбранный пользователем порядок
  иногда не совпадёт с фактической последовательностью действий.
- **Acceptance rationale:** отдельная revision/logical-clock модель или
  синтетическое продвижение времени несоразмерны вспомогательной сортировке и
  исказили бы наблюдаемое wall-clock значение.
- **Scope and assumptions:** timestamps не используются как revision, causal
  order, средство синхронизации, аудита или разрешения конфликтов.
- **Reopen when:** timestamps получают хронологически значимое
  поведение, появляется синхронизация/разрешение конфликтов либо наблюдается
  существенный пользовательский ущерб от перестановок.
- **Acceptance authority:** явное решение пользователя от 2026-09-03.
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** ADR-0006, соответствующие требования intention-management
  spec и раздел рисков design.

## Review coverage

Широко повторно проверены proposal, обе capability specs, design, ADR manifest,
phase plan, полный Phase 7 task graph, текущий review и schema-defined границы
будущего пакета Phase 8; commitments прослежены от intent и behavioral contract
через decisions к work и verification. Сверены ADR-0001–ADR-0008, корневой
доменный словарь и фактические классы `MainApp`, `LocalDataBootstrap` и
interface `IntentionRepository`, а также commands, sealed results/failures, Android host policy,
сборочная конфигурация и доступные lifecycle-примитивы зафиксированного
Riverpod. Углублённо проверены dependency direction, ownership принятого
выполнения `Future`, auto-dispose и повторное открытие routes, process-local
completion delivery, смена catalog query во время command, page/completion
races, paging/count/cursor reconciliation, initial и continuation failure
presentation, bounded state, privacy, localization, accessibility, delivery и
граница остановки процесса. Завершённые storage implementation details Phase
1–6 повторно не проверялись за пределами фактических seams, от которых зависит
Phase 7. После remediation F4 отдельно сверены общая табличная матрица всех
вариантов `IntentionFailure`, применимые command-specific fixtures, сохранение
формы или подтверждённого snapshot, retry-policy, отсутствие optimistic state и
повторная доступность gate. После remediation F5 сверены ADR-0005, ADR index,
change ADR manifest, coordinator/read paths design, behavioral contract
независимости принятой операции от экрана и задачи 7.1, 7.8–7.16; расхождение
dependency direction и ownership принятого `Future` устранено без изменения
capability boundary. После remediation F6 повторно проверены новые сценарии
сохранения загруженного каталога, ADR-0005 и тип ревизии
каталога `IntentionCatalogRevision` вместе с моделью мутации данных
типа `IntentionCatalogMutation`. Сверены единый repository sequencer и точные
снимки `before`/`after`, правила first/continuation pages, смена query generation,
ограниченность coordination state и задачи 7.19, 7.15, 7.17–7.18. Протокол
однозначно различает страницу до commit, страницу с уже включённым commit и
completion для текущей выдачи; F6 устранён без долговечной revision или
перечитывания подтверждённых порций. После remediation F7 сверены требование
независимости принятой операции от экрана, coordinator и UI ownership в
техническом `design.md`, а также задачи 7.1, 7.8, 7.10, 7.13 и 7.15–7.18. Каждый token теперь
имеет взаимоисключающий initiator либо catalog-fallback claim: каталог всегда
согласует подтверждённые данные, но показывает только непотреблённый дочерним
экраном outcome. Проверки явно охватывают открытый экран, уход до terminal
outcome, гонку disposal и failure → retry → success без ожидающей прежней ошибки.
После remediation F8 повторно сверены behavioral requirement и сценарии
получения данных, закрытая модель continuation state в `design.md`, repository
failure variants и задачи 7.6, 7.7 и 7.18. `unavailable` повторяет только ту же
порцию, `corruption` и `unexpected` сохраняют подтверждённый префикс без
обычного retry, а `validation` запускает только явное получение первой страницы
с `cursor: null`, защитой query generation и атомарной заменой snapshot после
успеха; требование и verification теперь прослеживаются полностью.
