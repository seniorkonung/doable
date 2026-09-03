# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** No unresolved findings

Активных findings не осталось. Ранее принятый ограниченный риск неточной
хронологии системных часов (`AR1`) остаётся применимым.

## Review target

- **Baseline:** configured `origin/main` @ `bdd76790e5b8f89b864b8f88bca38a6e37c2e3b7`
- **Reviewed head:** `52efc3c1a43a5f998336490a4e034ce473ba3d7d`
- **Target commits:** 4
- **Reviewable paths:** 5; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed
- **Excluded worktree state:** локальные remediation-правки `tasks.md` и этого
  отчёта не входят в immutable target

## Reviewed increment

### U1 · Физическое удаление и атомарность command-paths

- **Work items:** 6.7
- **Requirements and scenarios:** `Физическое удаление намерения` · удаление
  active/archived намерения и отсутствие после успеха; `Целостность при ошибках
  записи` · ошибка физического удаления и сохранение подтверждённого состояния;
  `Безопасное представление неизвестного отказа операции с намерением`;
  применимые сценарии `Сохранения результата операций с намерениями`
- **Affected boundary:** прикладной caller `IntentionRepository.execute`,
  подтверждённое локальное SQLite-состояние, FTS-представление и публичные read
  operations
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`,
  `test/intention/data/drift_intention_repository_command_test.dart`,
  `test/intention/data/drift_intention_repository_fault_test.dart`,
  `test/intention/data/file_backed_drift_intention_repository_test.dart`
- **Applicable constraints and non-goals:** success соответствует завершённой
  transaction; failure сохраняет последнее подтверждённое состояние и не
  раскрывает SQLite через публичную seam; связи моделировать не требуется,
  UI-подтверждение удаления и platform-specific process orchestration не входят
  в unit
- **Excluded change scope:** задачи 6.8a–6.20 и последующие фазы остаются будущей
  частью change и не являются обязательствами этого инкремента

### U2 · Полный repository lifecycle после повторного открытия SQLite-файла

- **Work items:** 6.8
- **Requirements and scenarios:** `Сохранение результата операций с
  намерениями` · сохранение данных и физического удаления после перезапуска;
  `Локальная долговечность данных приложения` · сохранение после полного
  перезапуска; применимые сценарии каталога, подробного чтения и corruption
  boundary
- **Affected boundary:** публичная `IntentionRepository` seam между полным
  закрытием владельца локального persistence graph и новым object graph над тем
  же файлом одной установки
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`,
  `test/intention/data/file_backed_drift_intention_repository_test.dart`
- **Applicable constraints and non-goals:** repository заимствует database и не
  владеет её lifecycle; подтверждённые identity, пользовательский текст,
  readiness, archive state, timestamps, каталог и удаление должны переживать
  reopen; large-fixture performance, UI composition, синхронизация и другие
  platform hosts не входят в unit
- **Excluded change scope:** задачи 6.8a–6.20 и последующие фазы остаются будущей
  частью change и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий zero-history reviewer проверил объединённый delivery target двух path-overlapping units на точном `bdd7679…52efc3c`; planning-артефакты, commit history, прежний отчёт и accepted risks ему не раскрывались |
| OpenSpec conformance | Complete | полный граф proposal/specs/design/ADR/plan/tasks сопоставлен с 6.7–6.8 и immutable diff; каждый reviewable path классифицирован, будущие задачи исключены, task-prescribed tests и структурная валидация выполнены |
| Code quality | Complete | production/test delivery subset и неизменённые schema/FTS, classifier, bootstrap/ownership, diagnostics и observer boundaries проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

В implementation review не осталось незакрытых findings.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** `_changeReadiness` и `_changeArchiveState` в
  `lib/src/intention/data/drift_intention_repository.dart:247-310` получают
  `updatedAt` непосредственно из `_now()` без логического счётчика или
  синтетического продвижения относительно прежнего значения. Каталог сравнивает
  сохранённый timestamp и использует `IntentionId` только как tie-breaker при
  равенстве.
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
  фактической операции только из-за `updatedAt < createdAt` не принят и передан
  в задачу 6.19.
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
  contract и запись в `Риски / компромиссы`
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

Все пять reviewable paths классифицированы: production repository и три тестовых
файла образуют U1/U2, `openspec/changes/manage-intentions/tasks.md` является
planning evidence; материальных несопоставленных путей нет. Проверены
исчерпывающий command dispatcher, delete по типизированному ID, not-found,
контекстный foreign-key conflict, transaction rollback после insert/update/state
transition/delete, FTS consistency, safe diagnostics, active/archived/all reads,
UUID v4/v7, точный пользовательский текст и timestamps после file-backed reopen.

`flutter test test/intention/data` прошёл 42 теста. Отдельный объединённый запуск
task-prescribed repository, FTS, diagnostics, file-backed и bootstrap tests прошёл
60 тестов. Targeted Dart MCP analysis и полный `flutter analyze` завершились без
ошибок; `openspec validate manage-intentions --json` успешен, `git diff --check`
для immutable range чист. Android build не запускался: target не меняет host
delivery, а проверки 6.7–6.8 ограничены repository, FTS, file-backed и bootstrap
boundaries.

В remediation-run код и тесты не изменялись, повторный implementation audit не
выполнялся. Новая задача 6.8a владеет file-backed adverse-path evidence для
последующего Apply; строгая OpenSpec-валидация planning handoff успешна.
