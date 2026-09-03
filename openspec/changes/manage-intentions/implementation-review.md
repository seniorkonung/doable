# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** No unresolved findings

Неточность фактической хронологии при одинаковых или откатившихся системных
часах принята как ограниченный остаточный риск `AR1`. Отказ реальной операции
из-за `updatedAt < createdAt` в этот риск не входит: обновлённый контракт и
задача 6.19 владеют необходимым изменением модели, schema и repository. До
выполнения задачи текущий код сохраняет этот failure path; planning handoff
фиксирует владельца последующей реализации, а не утверждает, что код уже исправлен.

## Review target

- **Baseline:** configured `origin/main` @ `f29b7dcc1a515c357b6e93fa9a18cec43fc4a0cd`
- **Reviewed head:** `f27fddefc3e7998ac254e699860420f7811d9126`
- **Target commits:** 1
- **Reviewable paths:** 4; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed
- **Excluded worktree state:** локальные правки `apm.lock.yaml`, planning-
  артефактов и этого отчёта не входят в immutable review target

## Reviewed increment

### U1 · Готовность к действию, архивирование и восстановление намерения

- **Work items:** 6.6
- **Requirements and scenarios:** `Явная классификация действия` · подтверждение
  и обратимое выключение готовности; `Архивирование намерения` · активное
  намерение и действие; `Восстановление намерения из архива`; `Время создания и
  обновления намерения` · фактическое изменение и no-op; применимые сценарии
  `Изменения намерения`, `Целостности при ошибках записи` и подтверждённого
  наблюдения состояния
- **Affected boundary:** прикладной caller `IntentionRepository.execute`,
  подтверждённое локальное SQLite-состояние и `watchById`
- **Implementation target:** `lib/src/intention/data/drift_intention_repository.dart`,
  `test/intention/data/drift_intention_repository_command_test.dart`,
  `test/intention/data/drift_intention_repository_watch_test.dart`
- **Applicable constraints and non-goals:** подтверждённое SQLite-состояние
  остаётся единственным источником истины; transition применяется целиком либо
  не применяется, success соответствует commit, no-op не пишет данные,
  публичная seam и diagnostics не раскрывают storage details или пользовательские
  данные; физическое удаление, связи, UI и синхронизация не входят в unit
- **Excluded change scope:** задачи 6.7–6.20 и последующие фазы остаются будущей
  частью change и не являются обязательствами этого инкремента

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий изолированный reviewer проверил точный delivery/test target `f29b7dc…f27fdde`; planning-артефакты, commit history и прежний отчёт ему не раскрывались |
| OpenSpec conformance | Complete | полный граф proposal/specs/design/ADR/plan/tasks сопоставлен с задачей 6.6 и immutable diff; сфокусированные и полные тесты и анализ исходного инкремента успешны, а remediation-артефакты проходят строгую OpenSpec-валидацию |
| Code quality | Complete | delivery-path subset и неизменённые command, domain timestamp, schema, transaction, diagnostics и observer boundaries проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

В implementation review не осталось нерешённых замечаний.

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
  вспомогательной сортировки, когда при обычной работе системных часов сохранённые
  значения дают ожидаемый порядок.
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
  remediation F1.
- **Originating finding:** F1
- **Decision record:** `proposal.md` · сортировка по сохранённым показаниям;
  `specs/intention-management/spec.md` · требования `Время создания и обновления
  намерения` и `Упорядочивание каталогов намерений`; `design.md` · wall-clock
  contract и запись в `Риски / компромиссы`

## Review coverage

Все reviewable paths классифицированы: repository и два тестовых файла образуют
U1, `openspec/changes/manage-intentions/tasks.md` является planning evidence;
материальных несопоставленных путей нет. Проверены полная transition/no-op
матрица active/archived и ready/not-ready, сохранение identity, пользовательского
текста и непричастного флага, not-found, атомарная transaction, публикация через
`watchById` после commit, конкурентные вызовы одного и разных намерений,
типизированная failure-классификация, diagnostics, primary-key доступ и отсутствие
дополнительной materialization.

Сфокусированный запуск прошёл 22 теста, полный `flutter test` — 123 теста.
Targeted Dart MCP analysis и полный `flutter analyze` завершились без ошибок;
`openspec validate manage-intentions --json` успешен, `git diff --check` для
immutable range чист. Android build не запускался: задача 6.6 не меняет platform
delivery, а её собственная verification boundary состоит из repository command,
concurrency и observer tests. В remediation-run код и тесты не изменялись и
повторный implementation audit не выполнялся; planning handoff проходит
`openspec validate manage-intentions --type change --strict --no-interactive`,
а оставшаяся реализация принадлежит задаче 6.19.
