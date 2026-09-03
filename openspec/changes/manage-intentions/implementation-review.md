# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** No unresolved findings

Задача 6.14 устраняет lossy typed coercion на detail read-path до построения
предметного намерения. Незакрытых findings в проверенном инкременте нет. Ранее
принятый ограниченный риск неточной хронологии системных часов (`AR1`) остаётся
применимым и не считается активным finding.

## Review target

- **Baseline:** configured `origin/main` @
  `e893ab7956aa7479f3c1f2478d5725eccb09128f`
- **Reviewed head:** `e973884e3dc1c3af5b50a7dbbb9a0fb744b9f70e`
- **Target commits:** 1
- **Reviewable paths:** 3; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed

## Reviewed increment

### U1 · Lossless rehydration подробных данных намерения

- **Work items:** 6.14
- **Requirements and scenarios:** `Время создания и обновления намерения` ·
  успешное изменение после перевода системных часов назад; `Состояния получения
  данных` · загрузка, подтверждённое отсутствие и ошибка подробных данных;
  `Безопасное представление неизвестного отказа операции с намерением` ·
  безопасный typed failure вместо успешных или частичных данных
- **Affected boundary:** локальный Drift/SQLite adapter и вызывающие стороны
  `IntentionRepository.watchById`
- **Implementation target:**
  `lib/src/intention/data/drift_intention_repository.dart`,
  `test/intention/data/drift_intention_repository_watch_test.dart`
- **Applicable constraints and non-goals:** публичная repository seam остаётся
  storage-neutral; detail read принимает только lossless raw-представления
  обязательного и nullable-текста, бинарных состояний и представимых UTC
  timestamps; обратный порядок представимых timestamps допустим; corruption
  завершается одним typed failure без частичного success; diagnostics не
  раскрывает пользовательские данные или storage details. Catalog pages,
  commands, schema migrations и UI не входят в unit.
- **Excluded change scope:** задачи 6.15–6.20 и последующие фазы остаются будущей
  частью change и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий zero-history reviewer проверил два delivery/test-пути U1 на точном `e893ab7…e973884`; planning-артефакты, commit history, прежний отчёт и accepted risks ему не раскрывались |
| OpenSpec conformance | Complete | полный граф proposal/specs/design/ADR/plan/tasks сопоставлен с 6.14 и immutable diff; все три пути классифицированы, будущая 6.15+ исключена, task-prescribed tests и структурная OpenSpec-валидация успешны |
| Code quality | Complete | production/test subset и неизменённые schema, domain, repository, diagnostics и Drift `QueryRow.data` contracts проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

В implementation review не осталось незакрытых findings.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** `_changeReadiness` и `_changeArchiveState` в
  `lib/src/intention/data/drift_intention_repository.dart:262` получают
  `updatedAt` непосредственно из `_now()` без логического счётчика или
  синтетического продвижения относительно прежнего значения. Каталог сравнивает
  сохранённый timestamp и использует `IntentionId` только как tie-breaker;
  detail rehydration и тест в
  `test/intention/data/drift_intention_repository_watch_test.dart:193`
  сохраняют представимое `updatedAt < createdAt` как допустимое состояние.
- **Potential impact:** два быстрых изменения могут получить одинаковое время,
  а перевод системных часов назад может дать меньшее значение; поэтому порядок
  каталога по `createdAt` или `updatedAt` иногда отличается от фактической
  последовательности операций.
- **Acceptance rationale:** монотонное логическое время, искусственное
  продвижение либо дополнительная revision-модель усложнили бы контракт и могли
  бы исказить показываемое wall-clock время. Эти компромиссы не оправданы для
  вспомогательной сортировки, когда при обычной работе системных часов
  сохранённые значения дают ожидаемый порядок.
- **Scope and assumptions:** решение относится только к локальным UTC wall-clock
  timestamps одной установки и сортировке по их сохранённым значениям;
  timestamps не используются как revision, causal clock, средство разрешения
  конфликтов или гарантия порядка. Неизменность `createdAt`, атомарность
  фактического изменения и отсутствие записи для no-op сохраняются. Отказ
  фактической операции только из-за `updatedAt < createdAt` не принят и остаётся
  запрещён действующим контрактом.
- **Reopen when:** timestamps становятся основой синхронизации, разрешения
  конфликтов, аудита, истечения срока или другого хронологически значимого
  поведения; пользователи наблюдают существенный ущерб от неверного порядка;
  либо поддерживаемая платформа демонстрирует систематические скачки часов.
- **Acceptance authority:** явное решение пользователя от 2026-09-03 в рамках
  remediation F1
- **Originating finding:** F1
- **Decision record:** `proposal.md` · сортировка по сохранённым показаниям;
  `specs/intention-management/spec.md` · требования `Время создания и обновления
  намерения` и `Упорядочивание каталогов намерений`; `design.md` · wall-clock
  contract и запись в `Риски / компромиссы`; ADR-0006
- **Current target relation:** Carried forward; catalog ordering not re-reviewed

## Review coverage

Все три reviewable paths классифицированы: production adapter и его watch-тест
образуют U1, а `openspec/changes/manage-intentions/tasks.md` является planning
evidence. Материальных несопоставленных или посторонних путей нет. Проверены raw
storage classes для обязательного и nullable-текста, бинарных состояний и
timestamps, представимость времени, UUID v4/v7, обратный порядок timestamps,
initial/commit/delete/not-found semantics, terminal failure lifecycle,
параметризация SQL и безопасные diagnostics. Неизменённые schema, domain,
command и file-backed consumers осмотрены только как контекст изменённого
detail-path.

Сфокусированный запуск прошёл 14 тестов. `mise run check-fast` прошёл
форматирование, полный `flutter analyze` и 149 тестов без тега `slow`; полный
`mise run check` с catalog large-fixture в этом ревью не запускался, поскольку
инкремент не меняет catalog path. Targeted Dart MCP analysis завершился без
ошибок; `openspec validate manage-intentions --json` успешен как структурная
проверка; `git diff --check` для immutable range чист. Android build и runtime
DTD-проверка не запускались: target не меняет host/UI delivery, а сам аудит не
изменял Dart/Flutter code.
