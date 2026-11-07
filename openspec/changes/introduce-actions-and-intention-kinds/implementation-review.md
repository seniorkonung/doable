# OpenSpec Implementation Review: introduce-actions-and-intention-kinds

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 1.43–1.45 выполнены. Новый тест порций вкладки «Действия» падает при потере условия курсора в любой из двух ветвей слияния, при перестановке привязанных значений часа и последовательности и при нестрогом сравнении. Переименования в тестах экрана дня и упрощение теста контроллера быстрого создания не меняют проверок. Неустранённых находок нет. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 9cb3a7fe743f89c613853e3c153e9ef21c14c8f4
- **Base commit:** 9cb3a7fe743f89c613853e3c153e9ef21c14c8f4
- **Reviewed head:** 4c528d0aac864c1f12d95beadf3546cda1940dc1
- **Target commits:** ["b0397be65c6cc2a9c1748f4b385d7d01db0e1341", "acbdfb34e03c0909023b376e27206106da4292bf", "67742d1aa65767ed01fa39b741f9c9eeb595dcfa", "4c528d0aac864c1f12d95beadf3546cda1940dc1"]
- **Reviewable paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md", "test/action/presentation/day/action_day_layout_test.dart", "test/action/presentation/day/action_day_supported_layout_test.dart", "test/app/quick_creation/quick_creation_mode_controller_test.dart", "test/graph/data/drift_intention_actions_read_test.dart"]
- **OpenSpec change:** introduce-actions-and-intention-kinds
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/introduce-actions-and-intention-kinds/task-profiles.md", "openspec/changes/introduce-actions-and-intention-kinds/tasks.md"]

## Reviewed increment

### U1 · Порции списков «Корневое» и «Конечное» сливают путь из одного намерения с многозвенным без повторов и пропусков

- **Work items:** ["1.43"]
- **Requirements and scenarios:** ["action-management: Список действий роли намерения", "design D10"]
- **Affected boundary:** Чтение списка роли намерения в локальном репозитории, наблюдаемое регрессионным набором тестов
- **Implementation target:** ["test/graph/data/drift_intention_actions_read_test.dart"]
- **Applicable constraints and non-goals:** Код `lib/`, тест стоимости чтения и бенчмарки не меняются. Обычный тест быстрый, с минимальными данными и без замеров времени. Название и комментарии на русском.

### U2 · Тесты экрана дня называют экран дня, а не «каталог»

- **Work items:** ["1.44"]
- **Requirements and scenarios:** ["CONTEXT.md: канонические термины"]
- **Affected boundary:** Читаемость тестов раскладки экрана дня
- **Implementation target:** ["test/action/presentation/day/action_day_layout_test.dart", "test/action/presentation/day/action_day_supported_layout_test.dart"]
- **Applicable constraints and non-goals:** Проверки, данные тестов и `lib/` не меняются. Имена каталога намерений (`IntentionCatalog*`, `getCatalogPage` и т. п.) и `_catalogDirectory` остаются.

### U3 · Тест освобождения контроллера быстрого создания задаёт исход отказа напрямую

- **Work items:** ["1.45"]
- **Requirements and scenarios:** ["quick-creation: сохранение режима после освобождения контроллера"]
- **Affected boundary:** Читаемость тестов контроллера режима быстрого создания
- **Implementation target:** ["test/app/quick_creation/quick_creation_mode_controller_test.dart"]
- **Applicable constraints and non-goals:** Проверки теста и `lib/` не меняются; покрытие других исходов не добавляется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Три свежих изолированных рецензента `implementation-decision-review` (по одному на U1, U2, U3; пути не пересекаются) получили нейтральные описания намерения, точные `9cb3a7fe…4c528d0a` и полные списки своих путей, без артефактов планирования, истории коммитов и прежних находок. U2 и U3 вернули «No substantive findings» с полным покрытием. U1 вернул два замечания с полным покрытием; оба отклонены координатором по результатам мутаций (см. «Review coverage»). |
| OpenSpec conformance | Complete | Координатор сверил критерии 1.43–1.45 с диффом в обе стороны: в `tasks.md` в диапазоне меняются только отметки 1.43–1.45, в `task-profiles.md` добавлены профили этих задач; кода вне задач нет, `lib/` не менялся. Мутационная проверка 1.43 в отдельной отсоединённой копии на `4c528d0a` (удалена после проверки): без условия курсора в ветви `single` или `root`, с переставленными значениями часа и последовательности и с `<=` вместо `<` новый тест падает; на неизменённом коде тест проходит. `mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --no-interactive` — valid; трекер задач: 45 из 45. В этом рабочем дереве, чистом и совпадающем с `4c528d0a`, `mise run check` завершился с EXIT 0: `dart format` не изменил 846 файлов, `flutter analyze` сообщил «No issues found», прошли 3930 обычных и 18 процессных тестов. Рецензенты прогнали затронутые файлы: U1 — 10 тестов, U2 — 35, U3 — 4, все прошли. |
| Code quality | Complete | Координатор применил линзы корректности, читаемости, архитектуры, безопасности и производительности `code-review-and-quality` ко всем четырём тестовым путям: данные теста 1.43 и комментарии о порядке последовательностей, границы порций и ожидания, полнота переименований 1.44 (поиск `catalog` и `каталог` по `test/action/presentation/day` находит только каталог намерений и `_catalogDirectory`), отсутствие остатков `_outcomeName`, `failed` и `outcome` в 1.45. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Целевой диапазон — 4 коммита и 6 путей. 4 тестовых пути распределены по трём блокам: U1 — 1, U2 — 2, U3 — 1. Остальные 2 пути — свидетельства планирования: `task-profiles.md` (коммит `b0397be6`, профили задач 1.43–1.45) и `tasks.md` (отметки выполнения). Задача 1.43 сопоставлена с коммитом `acbdfb34`, 1.44 — с `67742d1a`, 1.45 — с `4c528d0a`.

В новом тесте 1.43 действия с путём из одного намерения и многозвенные чередуются, в том числе внутри одной пары (дата, час): 31 и 32, 35 и 36 различаются только последовательностью. Границы порций приходятся на действие 33 из одного намерения («Весь день») и на многозвенное 36.

Отклонено после проверки замечание рецензента U1 (Medium): границы порций не делят группу с одинаковыми датой и часом, поэтому ошибки в часе и последовательности ключа будто бы не ловятся. Мутации опровергают каждый названный им дефект. Перестановку значений часа и последовательности ловит новый тест. Потерю часа или последовательности в сравнении ключа ловит `drift_intention_actions_read_cost_test.dart`: он требует в плане каждой ветви полное условие `(order_date,order_hour,order_sequence)<(?,?,?)`. Последовательность из первой строки порции вместо последней ловит существующий тест «порции идут от поздней даты к ранней…», где граница делит пару 14 и 13 с одинаковыми датой и часом. Кодировку «Весь день» в курсоре значением больше хранимого `-1` ловит граница на действии 33: такая порция повторно возвращает 33, а при часе 9 и выше — ещё 31 и 32.

Отклонено замечание рецензента U1 (Low) о том, что порции роли «Конечное» не проверяются. Критерий 1.43 допускает любую из двух ролей. Продолжение обеих ролей проходит один и тот же цикл по хранимым ролям. Сопоставление «Конечное» с хранимыми ролями `terminal` и `single` уже проверяет тест первой порции этой роли.
