# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Инкремент задач 2.22–2.23 выполняет требование «Отказ обновления не останавливает выдачу молча и бессрочно». Теперь каждый подтверждённый пакет, полученный после отказа согласования области, применяется к сохранённому содержимому и запускает одно новое чтение недостающей части на актуальной ревизии. Пакеты во время чтения ждут в очереди, таймеров нет, `retryRefresh` запускает то же чтение. Повторный отказ снова публикуется поверх того же содержимого, смена условий отменяет повтор. Полная проверка на head проходит, generated-артефакты воспроизводимы. Предъявление отказа и действия повтора на страницах остаётся в границах третьей фазы plan. Неразрешённых находок и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 1cedcfee42b837f45c2b68d43ad2946dea21b1f9
- **Base commit:** 1cedcfee42b837f45c2b68d43ad2946dea21b1f9
- **Reviewed head:** 904df386fd2ec55079b01cdd157be75425790da5
- **Target commits:** ["fc57f81c96ef5068bd19c2a7d0b2948bac9d5661","ab8f3b10e49bcf389063e660b234375bace79078","904df386fd2ec55079b01cdd157be75425790da5"]
- **Reviewable paths:** ["lib/src/intention/presentation/catalog/intention_catalog_view_model.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U1 · Следующий подтверждённый пакет после отказа согласования области сам повторяет её чтение

- **Work items:** ["2.22","2.23"]
- **Requirements and scenarios:** ["intention-management: Актуальность тегов и результатов совместного поиска — Следующее изменение повторяет неудавшееся обновление","intention-management: Актуальность тегов и результатов совместного поиска — Отказ обновления выдачи виден и устраняется повтором","design: решение 6 — автоматический и явный повтор после отказа согласования области"]
- **Affected boundary:** `IntentionCatalogViewModel` четырёх назначений поиска: приём подтверждённых пакетов, очередь согласования области, публикация состояния обновления и чтение согласования через `PersonalGraphRepository.getCatalogReconciliationPortion`.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_view_model.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart","test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart","test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart"]
- **Applicable constraints and non-goals:** Пока отказ не снят, опубликовано последнее целиком подтверждённое содержимое. Обычное продолжение после границы не читается. Порции одного согласования отражают одну ревизию; новая ревизия — повтор, а не отказ. Количество из пакета применяется один раз. Повтор запускается только новым пакетом или явным вызовом, таймеров и нарастающих пауз нет. Каждое чтение записывает обычную диагностику чтения согласования.
- **Excluded change scope:** Третья фаза: предъявление отказа обновления и действия повтора на четырёх страницах, элементы фильтра, предъявление выбранных условий и тегов. Её задач в tasks.md пока нет, и их отсутствие само по себе находкой не считается.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | U1 проверял один свежий субагент по навыку implementation-decision-review. Он получил нейтральный brief и точный диапазон 1cedcfee42b837f45c2b68d43ad2946dea21b1f9..904df386fd2ec55079b01cdd157be75425790da5 с четырьмя путями вне openspec/. Planning, история коммитов, отчёт и прежние находки ему не передавались. Неизменённый контекст (репозиторий графа) он читал только после проверки `git diff --quiet`. На временном снимке head он прогнал оба тестовых файла (62 теста) и `dart analyze`, а generated-файл воспроизвёл байт в байт. Итог: Coverage Complete, существенных замечаний нет. |
| OpenSpec conformance | Complete | Задачи 2.22 и 2.23 сопоставлены с U1 и сверены на head с требованием спецификации намерений и решением 6 design. HEAD совпадал с Reviewed head, рабочая копия была чистой, поэтому проверки шли в рабочей копии на 904df386fd2ec55079b01cdd157be75425790da5. Первый прогон `mise run --skip-tools check` завершился с exit 1: две 30-секундные задержки в `test/graph/data/file_backed_tag_durability_test.dart`. Этот тест запускает отдельные процессы, не входит в диапазон и шёл одновременно с тестами и build_runner субагента. Отдельный прогон этого файла: 14 тестов, All tests passed. Повторный полный прогон на свободной машине: exit 0; формат (0 changed), CI scope и flutter analyze без замечаний, 2788 тестов вместе с медленными, All tests passed. `mise run --skip-tools codegen-check` и `mise run --skip-tools codegen-check-test` — exit 0, git status после них пуст. `mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json` — valid, 0 failed. |
| Code quality | Complete | Координатор применил линзы code-review-and-quality ко всем изменённым delivery- и тестовым путям. Проверено новое условие запуска чтения в `_advanceAreaReconciliation`: `readRequired` либо одновременно `packagesRequireRead` и снятый `area.isFailed` (приоритет `&&` в Dart выше, чем у логического ИЛИ) на каждом месте вызова. Пакет вне чтения даёт `readRequired: true`, успешное чтение даёт `false`. Устаревшее чтение с пакетами даёт `true`. Отказ даёт `false` и не запускает новое чтение из пакетов, накопленных во время отказавшего чтения. Проверены защита `isReading` от параллельных чтений в `_reconcilePackage` и `retryRefresh`, сброс отказа в `_readArea` и отказ от публикации после `_abandonAreaReconciliation`. Также проверены блокировка продолжения при активном согласовании и отмена через `_invalidatePageRequest`. Неразрешённых существенных замечаний нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверен сохранённый диапазон 1cedcfee42b837f45c2b68d43ad2946dea21b1f9..904df386fd2ec55079b01cdd157be75425790da5. Discovery выполнен локальным helper. Три коммита совпадают с workflow, диапазоны задач смежны и упорядочены. До аудита HEAD совпадал с Reviewed head, рабочая копия была чистой. Исключённой пользовательской работы и незакоммиченных planning-различий нет.

Классификация путей. tasks.md — planning-артефакт; в нём меняются только отметки выполнения 2.22 (commit fc57f81c96ef5068bd19c2a7d0b2948bac9d5661) и 2.23 (commit 904df386fd2ec55079b01cdd157be75425790da5). Два пути `lib/` — delivery, два пути `test/` — тесты. Несопоставленных путей нет.

Planning прочитан из head: plan (границы второй и третьей фаз), требование «Актуальность тегов и результатов совместного поиска» спецификации намерений, решение 6 design и задачи 2.22–2.23. Прежний отчёт относился к диапазону задач 2.1–2.21; в нём не было активных находок и принятых рисков, переносить нечего. Номера, описания и порядок задач 1.1–2.23 не менялись, прежние отметки выполнения сохранены, новых задач нет. Коррекций кода и артефактов на этом этапе не вносилось.

Задача ID 46 (2.22), «Подтверждённый пакет после отказа согласования области автоматически повторяет её чтение», commit fc57f81c96ef5068bd19c2a7d0b2948bac9d5661: U1. `_advanceAreaReconciliation` различает пакет вне чтения (`readRequired`) и пакеты, потребовавшие чтения во время прежнего чтения (`packagesRequireRead`). Поэтому пакет после отказа запускает чтение, а отказ из пакетов своего чтения не выходит. Документация `retryRefresh` и `_failAreaReconciliation` обновлена. Прежняя проверка «пакет после отказа не запускает чтение» заменена параметризованной по трём категориям отказа проверкой автоматического повтора. Добавлены проверки: отсутствие чтений без пакета и явный повтор тем же чтением; очередь пакета во время повтора без параллельного чтения и однократное изменение количества; повторный отказ другой категории поверх того же содержимого и последующий автоматический повтор; отмена повтора сменой фильтра. Интеграционный тест через настоящий репозиторий и SQLite-отказ подтверждает автоматический повтор после назначения тега, публикацию с тем же объектом запроса и курсором и парные диагностические события чтения согласования без чтений порций каталога. Commit fc57f81c96ef5068bd19c2a7d0b2948bac9d5661 сам по себе оставлял устаревший хэш в `intention_catalog_view_model.g.dart`; commit ab8f3b10e49bcf389063e660b234375bace79078 из диапазона задачи 2.23 его перегенерировал. На head codegen-check проходит, поэтому это не находка. Ожидаемый в задаче `catalog_reconciliation_test_support.dart` не понадобился и не менялся.

Задача ID 47 (2.23), «Подтвердить готовность второй фазы после автоматического повтора согласования области», commits ab8f3b10e49bcf389063e660b234375bace79078 и 904df386fd2ec55079b01cdd157be75425790da5: U1, контрольная. Первый commit перегенерирует хэш провайдера, второй меняет только отметку. Проверки задачи выполнены на head в этом ревью: полный `check` с медленными тестами, codegen-check обоих видов на чистой рабочей копии, strict-валидация change. Результат второй фазы по plan выполнен, интерфейс третьей фазы выполненным не объявляется.

Независимый рецензент отметил состояние вне этого инкремента, не признав его находкой. Если чтение повтора завершается как устаревшее, пока пакет новой ревизии ещё не доставлен, признак отказа уже снят, и область ждёт этого пакета без видимого отказа. Такое же поведение есть на base для явного повтора и первичного согласования. Оно опирается на доставку пакета каждой подтверждённой ревизии подписчику через координатор команд, поэтому находкой не записано.

Принятых человеком остаточных рисков нет.
