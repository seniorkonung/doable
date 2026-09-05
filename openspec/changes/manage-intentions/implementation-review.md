# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** No unresolved findings

Активных findings не осталось. Исправление F2 передано обновлённому design и
новым незавершённым задачам 6.20b–6.20c: отдельно зафиксированы типобезопасная
connection capability, невозможность обычного обхода либо затенения setup и
перевод всех repository/migration/verification harnesses. Это planning handoff,
а не утверждение, что текущая реализация уже исправлена. Ранее принятый риск
`AR1` остаётся применимым и не считается активным finding.

## Review target

- **Baseline:** user-requested local parent `fac05cb^` @
  `d4d45bed8337f097db6f736c0ebb63e9c486213d`
- **Reviewed head:** `fac05cba31fb354a7f95e263a84dabaa79e07a18`
- **Target commits:** 1
- **Reviewable paths:** 13; `implementation-review.md` не входил в target
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Explicit local ref; no fetch performed
- **Excluded committed state:** текущий branch `HEAD`
  `f42d5732c41071b9e5bc33a3c748aee94cbc1681` и его изменение
  `apm.lock.yaml` находятся после reviewed head и исключены по прямому указанию
  пользователя

## Reviewed increment

### U1 · Единая SQLite connection setup для поисковой проекции названия

- **Work items:** 6.20a; выполненная 6.20 является входной зависимостью
- **Requirements and scenarios:** `Фильтрация каталога по названию` · единое
  locale-independent Unicode Default Case Folding; ADR-0008 · долговечное имя,
  сигнатура, регистрация и trust boundary SQLite schema-function
- **Affected boundary:** Android production background connection,
  in-memory/file-backed test executors, migration connections и фактическая и
  эталонная стороны schema verification
- **Implementation target:** `build.yaml`,
  `lib/src/data/local/database_connection.dart`,
  `lib/src/data/local/sqlite_connection_setup.dart`,
  `test/data/local/app_database_schema_test.dart`,
  `test/data/local/bootstrap/local_data_bootstrap_test.dart`,
  `test/data/local/database_connection_test.dart`,
  `test/data/local/file_backed_database_test.dart`,
  `test/data/local/fts_consistency_test.dart`,
  `test/data/local/migrations/fault_injection_test.dart`,
  `test/data/local/migrations/file_backed_migration_test.dart`,
  `test/data/local/migrations/migration_test.dart`,
  `test/support/local_database_harness.dart`
- **Applicable constraints and non-goals:** callback делегирует единственной
  чистой storage-neutral операции, остаётся sendable, deterministic, не
  выполняет I/O и не читает изменяемое состояние; `directOnly: false` допустим
  только для внутреннего app-specific SQLite-файла; публичная
  `IntentionRepository` seam остаётся storage-neutral; schema, FTS/catalog
  behavior и общая Unicode text boundary в этом инкременте не меняются
- **Excluded change scope:** типобезопасная connection remediation 6.20b–6.20c,
  generated search projection и repository changes 6.21, mapping-drift и
  missing-setup matrix 6.22, checkpoints и общая text integrity 6.23–6.26

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий zero-history reviewer проверил все 12 delivery/test/configuration путей U1 на точном `d4d45be…fac05cb`; planning artifacts, commit history, прежний отчёт и accepted risks ему не раскрывались |
| OpenSpec conformance | Complete | полный artifact graph и ADR-0008 сопоставлены с 6.20a и immutable diff; все 13 путей классифицированы, последующая remediation 6.20b–6.20c и будущие 6.21–6.26 не приняты за обязанности этого инкремента, completion claim и предписанная verification matrix проверены отдельно |
| Code quality | Complete | изменённые setup, factories, harnesses и tests вместе с окружающими AppDatabase/repository connection paths и pinned Drift/sqlite3 behavior проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** на предыдущем reviewed head
  `faf205fbf1c4429cefe695cba06a7c938210ef83`
  `_changeReadiness` и `_changeArchiveState` в
  `lib/src/intention/data/drift_intention_repository.dart:262` получают
  `updatedAt` непосредственно из `_now()` без логического счётчика или
  синтетического продвижения относительно прежнего значения. Каталог сравнивает
  сохранённый timestamp и использует `IntentionId` только как tie-breaker;
  detail rehydration принимает представимое `updatedAt < createdAt`.
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
- **Current target relation:** Carried forward; not re-reviewed — текущий
  инкремент не меняет timestamp contract или границу принятия риска

## Review coverage

Все 13 reviewable paths классифицированы: 12 delivery/test/configuration путей
входят в U1, а `openspec/changes/manage-intentions/tasks.md` является planning
evidence с изменённым completion claim 6.20a. Несопоставленных и посторонних
путей нет. Проверены порядок и sendability connection setup, arity и flags
SQLite-функции, делегирование `titleSearchKey`, Android background connection,
in-memory/file-backed factories, fixture composition, migration/bootstrap
connections, обе стороны schema verification, прямые repository-test executors,
analyzer configuration, diagnostics и internal-file trust boundary.

Проверка выполнена в изолированном checkout точного reviewed head. Предписанный
6.20a набор прошёл 35 тестов; оставшиеся изменённые file-backed/FTS tests — ещё
17; полный `flutter test` — 164. `flutter analyze` не нашёл замечаний.
`dart run build_runner build --delete-conflicting-outputs` завершился успешно,
создал 107 outputs и не оставил diff (текущая версия build_runner сообщила, что
этот флаг удалён и проигнорирован). `dart format --output=none
--set-exit-if-changed` подтвердил 11 изменённых Dart-файлов без изменений,
`git diff --check` чист, а `openspec validate manage-intentions --type change
--strict --no-interactive` успешен. При исходном discovery staged, unstaged и
untracked work отсутствовали и не использовались как evidence. Последующие
изменения `design.md` и `tasks.md`, передающие F2 в planning, не входят в
immutable review target и не считаются доказательством исправленного code.
Аудит не изменял Dart/Flutter code, поэтому DTD hot reload/restart не применим.
