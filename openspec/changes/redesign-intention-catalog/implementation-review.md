# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 3.8 и 3.9 выполнены: сценарий создания и проверка доступности больше не зависят от устройства прежней страницы, а смена подписи поля затрагивает только `test/support/intention_catalog_controls.dart`. Фаза 3 достигла цели, `lib/` не менялся, активных находок и принятых рисков нет.

## Review target

- **Baseline ref:** 8e9a39c5d28e61cb4b41e83c203e19531ceea592
- **Base commit:** 8e9a39c5d28e61cb4b41e83c203e19531ceea592
- **Reviewed head:** 675cbe4f45bf79cd7db7828af139ed02dc1ca1d8
- **Target commits:** ["fa472ceba2594b7a8481fdfd1c7f3e3c6f303711", "1c426db59883af24738fadb97b0aeaf2697d7e83", "675cbe4f45bf79cd7db7828af139ed02dc1ca1d8"]
- **Reviewable paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/app/intention_creation_sheet_integration_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/support/intention_catalog_controls.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Проверки каталога не зависят от устройства страницы и не сверяют семантику с ней самой

- **Work items:** ["3.8", "3.9"]
- **Requirements and scenarios:** ["plan.md: Phase 3 / Ready to advance", "design: решение 10, сценарные шаги каталога"]
- **Affected boundary:** Авторы сценарных тестов и защита от регрессий, которую эти тесты дают приложению. Поведение приложения не меняется.
- **Implementation target:** ["test/app/intention_creation_sheet_integration_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/support/intention_catalog_controls.dart"]
- **Applicable constraints and non-goals:** `lib/` не меняется. Шаги действуют и наблюдают через интерфейс, а не через модель. Проверка сдвига списка не ослабляется. Новых сценариев нет.
- **Excluded change scope:** Переключение шагов на новую страницу и перестройка проверок прежней страницы — фаза 4.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный ревьюер (Sonnet, high, `implementation-decision-review`) проверил U1 по трём путям тестов. Планирующие артефакты, история коммитов и прежний отчёт ему не передавались. Результат: `No substantive findings`, покрытие полное. |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве на голове 675cbe4f45bf79cd7db7828af139ed02dc1ca1d8 без незакоммиченных изменений. Первый `mise run check` дал код 1: `test/graph/data/file_backed_tag_durability_test.dart` упал по `TimeoutException` за 45 с в ожидании готовности рабочего процесса; ревьюер в это время запускал тесты параллельно. Диапазон не меняет этот файл и `lib/`. Тот же тест отдельно прошёл три раза подряд примерно за 15 с. Повторный `mise run check` без параллельной нагрузки прошёл, код 0: `dart format`, `test/tool`-проверки и `flutter analyze` без замечаний, 3848 обычных тестов, 18 тестов процессов. `mise exec --no-deps -- openspec validate redesign-intention-catalog --strict --json` — valid. Поиск из задачи 3.7 нашёл ключи и строки только в `test/support/intention_catalog_controls.dart` и пяти разрешённых файлах проверок прежней страницы. `git diff --quiet d6de1fac77d46e512fde7ff981ac01e2aa535b6f 675cbe4f45bf79cd7db7828af139ed02dc1ca1d8 -- lib` — код 0. |
| Code quality | Complete | Навык `code-review-and-quality` применён ко всем трём путям: дифф сверен с базой, файл шагов прочитан целиком на голове, места вызова изменённых и использованных шагов прочитаны в обоих сценариях. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверены все три коммита диапазона и все пять изменённых путей. Задача 3.8 привязана к U1 и коммиту 1c426db59883af24738fadb97b0aeaf2697d7e83, задача 3.9 — к U1 и коммиту 675cbe4f45bf79cd7db7828af139ed02dc1ca1d8. Коммит fa472ceba2594b7a8481fdfd1c7f3e3c6f303711 меняет только `task-profiles.md`, а отметки `tasks.md` — планирующие свидетельства. Обе задачи служат одному результату и одной границе, поэтому они образуют один блок и один проход ревьюера.

**Задача 3.8.** Шаг `shownIntentionCatalogOuterOffsets` исключает список по самому положению `intentionCatalogListPosition`, а не по месту в дереве: `ScrollPosition` сравнивается по тождеству объекта. `_catalogView` берёт `list` и `outer` из этих шагов, `offsets.last`, `offsets.sublist` и комментарий о порядке удалены. Документация `shownIntentionCatalogOffsets` порядка не упоминает, вызовы шага не менялись. Ожидания сценария те же: `outer` и `rows` не меняются, `list` растёт. Значения `outer` читаются так же, как до правки, поэтому проверка не ослабла.

**Задача 3.9.** Локальная `titleFieldName`, чтение семантики и её комментарий удалены, `containsAll` сравнивает с `intentionCatalogTitleFieldLabel(tester)`. Ожидание больше не выводится из проверяемой семантики, а подпись из локализации не бывает пустой, поэтому `expect(titleFieldName, isNotEmpty)` не нужен. Отмена предложения критерия задачи 3.4 записана в самой задаче 3.9, история задач сохранена. Строка `catalogFilterLabel` в тесте напрямую не появилась.

**Замечание независимого ревьюера, которое не стало находкой.** `expect(viewAfter.outer, viewBefore.outer)` прошёл бы вхолостую, если бы на странице осталась только прокрутка списка. Прежний `sublist` вёл себя так же, поэтому диапазон этого свойства не вводил, а критерий задачи 3.8 — не ослаблять проверку — выполнен.

**Сбой первого прогона полной проверки.** Упавший тест лежит вне диапазона, а его изоляция и повторный прогон сбой не воспроизвели. Он записан как ограничение, а не как находка: один случай под параллельной нагрузкой не даёт доказанной причины.

Безопасность: диапазон меняет только тесты и планирующие файлы, новых входов, данных и зависимостей нет. Новый шаг имеет одного вызывающего, новых тестов и сценариев нет. Задачи фазы 4 обязательствами диапазона не считались. Проверки на устройстве не выполнялись и для этой фазы не нужны: поведение приложения не менялось.
