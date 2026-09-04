# OpenSpec Implementation Review: manage-intentions

## Assessment

**Result:** Changes needed

В immutable инкременте остаются три активных finding: short-filter recovery
неполон для Unicode-регистра, storage constraint описания уже предметной
нормализации, а реализация ещё не соответствует согласованной схеме поисковой
проекции. Отметка 6.17 как завершённой поэтому не подтверждена. Ранее принятый
риск `AR1` остаётся применимым и не считается активным finding.

## Review target

- **Baseline:** configured `origin/main` @
  `0d8f9cfecce5d62db0b4847c8c8a393fbc68de48`
- **Reviewed head:** `faf205fbf1c4429cefe695cba06a7c938210ef83`
- **Target commits:** 3
- **Reviewable paths:** 9; excludes `implementation-review.md`
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local tracking state; no fetch performed
- **Excluded worktree state:** неподтверждённые коммитом remediation-изменения
  `design.md`, `tasks.md` и этого отчёта не входят в immutable review target

## Reviewed increment

### U1 · Семантически целостные ограниченные snapshots каталога намерений

- **Work items:** 6.15, 6.16, 6.17
- **Requirements and scenarios:** `Каталог намерений и его охват` · сводные
  данные намерения; `Фильтрация каталога по названию` · регистронезависимое
  буквальное вхождение; `Ограниченная выдача и автоматическая подгрузка
  каталога` · ограниченная первая порция и последовательность порций; `Точное
  количество совпадений каталога`
- **Affected boundary:** локальная persistence boundary и вызывающие стороны
  `IntentionRepository.getCatalogPage`
- **Implementation target:** `drift_schemas/drift_schema_v1.json`,
  `lib/src/data/local/app_database.g.dart`,
  `lib/src/data/local/fts_query.dart`,
  `lib/src/data/local/schema/intention_schema.drift`,
  `lib/src/intention/data/drift_intention_repository.dart`,
  `test/data/local/fts_consistency_test.dart`,
  `test/intention/data/drift_intention_catalog_test.dart`,
  `test/intention/data/drift_intention_repository_large_fixture_test.dart`
- **Applicable constraints and non-goals:** первая страница получает count и
  строки из одного SQLite snapshot; каждая порция читает не больше
  `pageSize + 1` строк, не использует `OFFSET`, не проецирует полный текст
  описания и не материализует неограниченный результат в Dart; публичная seam
  остаётся storage-neutral
- **Excluded change scope:** cursor ownership, remediation поисковой проекции и
  финальные проверки 6.18–6.23,
  Flutter navigation, presentation state и Views

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | свежий zero-history reviewer проверил восемь delivery/test-путей U1 на точном `0d8f9cf…faf205f`; planning-артефакты, commit history, прежний отчёт и accepted risks ему не раскрывались |
| OpenSpec conformance | Complete | полный граф proposal/specs/design/ADR/plan/tasks сопоставлен с 6.15–6.17 и immutable diff; все девять путей классифицированы, будущая 6.18+ исключена, task-prescribed и полный project workflow выполнены, строгая OpenSpec-валидация успешна |
| Code quality | Complete | полный delivery-path subset и затронутые domain, schema, search, repository, migration и diagnostics boundaries проверены по correctness, readability, architecture, security, performance и evidence |

## Findings

### F3 · Medium — Short-filter recovery не является полным обратным Unicode lowercasing

- **Evidence:** публичное правило сравнивает
  `title.toLowerCase().contains(filter.toLowerCase())` в
  `lib/src/intention/application/intention_repository.dart:152`. Для фильтра из
  одной-двух кодовых точек новый код строит варианты только через lower/upper
  каждой кодовой точки самого фильтра
  (`lib/src/data/local/fts_query.dart:66`–`:79`). В используемом Dart 3.13
  `K`.toLowerCase() равно `k`, но варианты фильтра `k` равны только `k` и `K`.
  Поэтому название `Kettle` с повреждённым посторонним `title_search_key` не
  попадает ни в одну ветвь candidate predicate, хотя публичная seam считает его
  совпадением. Добавленный short-filter test покрывает только обычную кириллицу
  (`test/intention/data/drift_intention_catalog_test.dart:413`).
- **Impact:** для допустимого Unicode-названия каталог может успешно вернуть
  ложное отсутствие и count `0`, не обнаружив одновременно повреждённый search
  key.
- **Required outcome:** short-filter candidate selection должна включать каждое
  название, совпадающее по каноническому repository-правилу Unicode lowercasing,
  и при этом выводить релевантное рассогласованное storage-представление на
  corruption boundary.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задачи 6.16 и 6.17; `LocalIntentionTitleSearch`;
  application matching contract; short-filter adversarial tests

### F4 · Medium — Storage constraint описания уже предметной семантики

- **Evidence:** schema отклоняет только значения, состоящие из кодовых точек
  9–13 и 32 (`lib/src/data/local/schema/intention_schema.drift:5`), тогда как
  предметная граница считает отсутствующим любое значение с пустым Dart
  `String.trim()` и ограничивает присутствующее описание 4096 графемами
  (`lib/src/intention/domain/intention_text.dart:36`). Каталог проецирует только
  `description IS NOT NULL` и не проверяет само значение
  (`lib/src/intention/data/drift_intention_repository.dart:346`). В Dart 3.13
  строки только из NBSP (`U+00A0`) или BOM (`U+FEFF`) обрезаются до пустых, но
  проходят новый SQL constraint; описание из 4097 графем также проходит его.
  Добавленный тест проверяет лишь пустую строку и ASCII whitespace
  (`test/intention/data/drift_intention_catalog_test.dart:564`).
- **Impact:** свежая schema допускает предметно отсутствующее или недопустимое
  описание, после чего каталог публикует успешный summary с
  `hasDescription = true` вместо typed corruption.
- **Required outcome:** каждое ненулевое сохранённое описание, влияющее на
  успешный summary, должно удовлетворять полному предметному контракту
  представления без материализации полного текста в `IntentionSummary`.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задачи 6.16 и 6.17; исходная/generated/snapshot schema;
  catalog projection и adversarial description tests

### F5 · Low — Реализация ещё не соответствует согласованной схеме поисковой проекции

- **Evidence:** актуальный `design.md:266` и `:273` определяет
  `title_search_key` как `STORED GENERATED ALWAYS` от единственного
  записываемого `title`; `design.md:292` оставляет в FTS только generated key,
  а `design.md:313`–`:315` запрещает резервную ветвь по исходному `title`.
  Текущий committed target по-прежнему хранит обычный записываемый
  `title_search_key`, индексирует в FTS и `title`, и `title_search_key`
  (`lib/src/data/local/schema/intention_schema.drift:17`), а short-filter
  predicate дополнительно ищет case variants в `title`
  (`lib/src/data/local/fts_query.dart:41`). Новые задачи 6.20–6.22 владеют
  реализацией этого решения, но находятся вне immutable target.
- **Impact:** пока задачи remediation не реализованы, generated/schema
  artifacts, runtime connection setup, trigger content и candidate semantics
  противоречат техническому источнику истины; следующий change не может
  безопасно полагаться на инвариант единственного записываемого названия.
- **Required outcome:** реализация, generated artifacts, schema snapshot и тесты
  должны подтвердить versioned SQLite-функцию, generated search key,
  одно-колоночный FTS и единое условие count/page; финальный checkpoint 6.23
  должен повторно доказать согласованность Phase 6.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задачи 6.20–6.23; `build.yaml`; connection setup;
  исходная/generated/snapshot schema; `LocalIntentionTitleSearch`; repository
  write/read paths; schema, FTS, migration и catalog tests

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** `_changeReadiness` и `_changeArchiveState` в
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
- **Current target relation:** сохранён; текущий инкремент не меняет контракт
  сортировки по timestamps или границу принятия риска

## Review coverage

Все девять reviewable paths классифицированы: восемь delivery/test-путей входят
в U1, а `openspec/changes/manage-intentions/tasks.md` является planning evidence
с изменёнными completion claims 6.15–6.17. Несопоставленных и посторонних путей
нет. Проверены исходная, generated и snapshot schema, FTS columns/triggers,
короткая и длинная ветви фильтра, exact count, первая и последующие keyset
порции, summary rehydration, Unicode-нормализация, nullable description,
параметризация SQL, diagnostics и regression budget. Перезапись ещё не
опубликованной schema version 1 согласуется с явно зафиксированным ограничением
change и поэтому не требует migration step для прежних production-данных.

Сфокусированный combined run задач 6.15–6.17 прошёл 109 тестов. `mise run check`
прошёл форматирование, полный `flutter analyze` и 156 тестов, включая
large-fixture; targeted Dart MCP analysis изменённых Dart-путей не нашёл ошибок.
`openspec validate manage-intentions --type change --strict --no-interactive
--json` успешен как структурная проверка, `git diff --check` чист. Android build
не запускался: он относится к будущему checkpoint 6.20, а текущий инкремент не
меняет host/UI delivery. Аудит не изменял Dart/Flutter code, поэтому DTD hot
reload/restart не применим.
