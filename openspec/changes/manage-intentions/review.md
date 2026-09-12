# OpenSpec Change Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F13–F15 блокируют финальную интеграционную готовность: command-path
  нарушает lossless storage boundary, packaged permission gate допускает часть
  неутверждённых media permissions, а negative-path detector test не входит в
  обязательный CI path. AR1, AR2 и AR3 остаются явно принятыми рисками.
**Validation:** `openspec validate manage-intentions --type change --strict --no-interactive` успешен на reviewed head; Dart MCP analysis, воспроизводимая генерация и `mise run check` с 331 тестом также успешны. GitHub подтверждает зелёный `Full checks` на tree reviewed head и required status context `Full checks` для `main`. Эти результаты не доказывают Android process restart, Android latency или фактическую работу TalkBack на устройстве.

## Findings

### F13 · Medium — Command-path публикует coerced значения повреждённой SQLite-строки

- **Evidence:** `design.md:615` требует lossless rehydration до необратимого typed coercion, а `specs/local-data-lifecycle/spec.md:27` запрещает успешную модель или сводку из непроверенного сохранённого представления. Но `lib/src/intention/data/drift_intention_repository.dart:258`, `:303`, `:345` и `:385` читают command row через generated Drift mapper; `lib/src/data/local/app_database.g.dart:193` преобразует storage values как `string`, `bool` и `int`. В Drift 2.34.3 это означает `toString()`, nonzero → `true` и `double.toInt()`, тогда как catalog/details уже валидируют raw storage classes.
- **Impact:** Readiness, archive/restore, update либо delete повреждённой строки может вернуть success и mutation snapshot со сфабрикованными значениями вместо `IntentionCorruptionFailure`, а необратимое удаление может состояться до обнаружения повреждения.
- **Required change:** Проверять raw SQLite storage classes и предметные инварианты всех полей command `before`/`after` до преобразования или mutation; malformed row должен остаться неизменным, вернуть typed corruption и не продвинуть revision.

### F14 · Medium — Packaged Android permission gate покрывает privacy policy неполным denylist

- **Evidence:** ADR-0004 и `design.md:598` запрещают `INTERNET` и разрешения внешнего хранилища для capability. `.github/workflows/ci.yml:72-87` отклоняет семь имён, но не отклоняет, например, `READ_MEDIA_VISUAL_USER_SELECTED` и `ACCESS_MEDIA_LOCATION`; source-manifest test не видит permissions, добавленные при manifest merge зависимостями.
- **Impact:** Release APK с неутверждённым доступом к shared/external media способен получить зелёный обязательный gate, хотя packaged manifest является финальной privacy boundary.
- **Required change:** Сделать packaged permission policy полной относительно утверждённой границы и покрыть её negative fixtures так, чтобы `INTERNET` и любой неутверждённый shared/external storage или media access гарантированно делали gate неуспешным.

### F15 · Medium — Обязательный CI path не исполняет negative test generated-artifact detector

- **Evidence:** Task 8.1 требует отдельно доказать, что detector замечает изменённый tracked и новый untracked artifact. Это делает `tool/check_generated_test.sh:36-52`, но `.github/workflows/ci.yml:44-55` его не запускает, а `mise run check` не включает зарегистрированный `codegen-check-test` из `mise.toml:28`.
- **Impact:** Регрессия `assert_clean_tree` может пройти на чистой генерации и дать false-success обязательного gate именно в той части, которая должна доказывать воспроизводимость committed artifacts.
- **Required change:** Включить negative-path regression evidence detector в обязательный CI path и сохранять failure gate при утрате обнаружения tracked или untracked drift.

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

Broad re-audit охватил proposal, оба delta spec, design, ADR manifest и ADR-0001–ADR-0008, plan, tasks, прежние review states и полный committed implementation range после предыдущего reviewed head. Требования прослежены через repository raw data, schema functions, revisions, process-local coordinator, bootstrap ownership, routing, локализацию, автоматизированную доступность, diagnostics allowlist, Android host privacy и Phase 8 CI.

Предыдущий implementation review доказал Phase 6 schema/NUL/bounded-catalog increment и сохранил AR1; текущий implementation review повторно проверил изменившийся repository и независимо покрыл presentation/composition и CI. Автоматизированные проверки подтвердили Unicode corpus, schema-function setup, file-backed persistence, migration/schema validation, localization, semantics/guidelines/text scale, release APK build и packaged backup references в указанных границах.

Ручная TalkBack qualification и device/emulator evidence отсутствуют по утверждённой границе. APK build и Linux tests не считаются доказательством Android restart, Android latency или фактического TalkBack. F11 и F12 поэтому заменены явно принятыми AR2 и AR3, а не объявлены исправленными; F13–F15 остаются blocking до выполнения новых Phase 8 remediation-задач.
