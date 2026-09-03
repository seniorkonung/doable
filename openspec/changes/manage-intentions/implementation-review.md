# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** No unresolved findings

Задача 6.11 реализует точную консервативную классификацию SQLite-отказов без
незакрытых findings. Ранее принятый ограниченный риск неточной хронологии
системных часов (`AR1`) остаётся применимым и не относится к текущему инкременту.

## Review target

- **Baseline:** configured `origin/main` @
  `6721e4a81a8e662d1fb3e5f7685900cab3cd99ce`
- **Reviewed head:** `66e5dcf4193ab8497f2c9a8587a1b0fbb02eae10`
- **Target commits:** 1
- **Reviewable paths:** 5; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed

## Reviewed increment

### U1 · Точная и консервативная классификация SQLite-отказов

- **Work items:** 6.11
- **Requirements and scenarios:** `Безопасный bootstrap локального хранилища` ·
  устранимая ошибка, неизвестная причина отказа и повреждённый SQLite-файл;
  `Безопасное представление неизвестного отказа операции с намерением` ·
  неизвестная причина получения данных; `Состояния получения данных` ·
  устранимая ошибка подробного чтения
- **Affected boundary:** общий classifier локального persistence, bootstrap
  хранилища и typed failure channel подробного чтения через
  `IntentionRepository.watchById`
- **Implementation target:**
  `lib/src/data/local/sqlite_failure_classifier.dart`,
  `test/data/local/sqlite_failure_classifier_test.dart`,
  `test/data/local/bootstrap/local_data_bootstrap_test.dart`,
  `test/intention/data/drift_intention_repository_watch_test.dart`
- **Applicable constraints and non-goals:** retry разрешён только для доказанно
  временных машинных причин; подтверждённое повреждение, временная
  недоступность и unknown остаются различимыми; diagnostics не раскрывает текст
  exception, SQL, параметры, идентификаторы или пользовательский текст;
  изменение schema, успешного data-path, catalog/command semantics, UI,
  синхронизации и platform support не входит в unit
- **Excluded change scope:** задачи 6.12–6.20 и последующие фазы остаются будущей
  частью change и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий zero-history reviewer проверил четыре delivery/test-пути U1 на точном `6721e4a…66e5dcf`; planning-артефакты, commit history, прежний отчёт и accepted risks ему не раскрывались |
| OpenSpec conformance | Complete | полный граф proposal/specs/design/ADR/plan/tasks сопоставлен с 6.11 и immutable diff; все пять путей классифицированы, будущая 6.12+ исключена, task-prescribed tests и структурная OpenSpec-валидация успешны |
| Code quality | Complete | delivery/test subset и неизменённые bootstrap, repository, diagnostics и dependency contracts проверены по correctness, readability, architecture, security, performance и evidence |

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

Все пять reviewable paths классифицированы: общий production classifier и три
тестовых файла образуют U1,
`openspec/changes/manage-intentions/tasks.md` является planning evidence;
материальных несопоставленных или посторонних путей нет. Проверены полный
`extendedResultCode`, семейства `CORRUPT`/`NOTADB`, точный `IOERR_DATA`, закрытый
retryable allowlist `BUSY`/`LOCKED`, первичные и extended `CANTOPEN`/`IOERR`,
неизвестные коды знакомых семейств, nested `DriftRemoteException`, bootstrap
mapping, terminal detail streams и безопасные diagnostics. Неизменённые
catalog/command consumers осмотрены как контекст изменённого общего classifier.

Task-prescribed запуск прошёл 36 тестов; полный `mise run check` прошёл
форматирование, `flutter analyze` и 145 тестов, включая slow large-fixture suite.
Targeted Dart MCP analysis завершился без ошибок; `openspec validate
manage-intentions --json` успешен как структурная проверка; `git diff --check`
для immutable range чист. Android build не запускался: target не меняет host
delivery, а проверка 6.11 ограничена storage classifier, bootstrap, repository и
diagnostics boundaries.
