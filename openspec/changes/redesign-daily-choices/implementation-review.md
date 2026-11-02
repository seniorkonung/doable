# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 1.19 и 1.20 выполнены по критериям приёмки. Активных находок нет. Принят остаточный риск AR1: граница 1,5, до которой слово обновления видно в заголовке дня, не закреплена тестом каталога. Условие не устранено и не опровергнуто.

## Review target

- **Baseline ref:** 50289c5e96801e5f051bb3933d6c816b74acaba5
- **Base commit:** 50289c5e96801e5f051bb3933d6c816b74acaba5
- **Reviewed head:** 402b9271783e3b2701fc4958aa121bc8e3ab4c79
- **Target commits:** ["ebdf7555859d8a442f66a69907420f51e6617007", "0e9e174b0ff971f5bac57c0deae490ace9eb7901", "402b9271783e3b2701fc4958aa121bc8e3ab4c79"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart", "lib/src/design_system/components/list_state.dart", "openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart", "test/design_system/list_state_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · При крупном шрифте день недели не разрывается внутри слова

- **Work items:** ["1.19"]
- **Requirements and scenarios:** ["Задача 1.19: строка обновления сужается до кольца", "Задача 1.16: постоянное место строки обновления", "Каталог дневных выборов по дате и секциям"]
- **Affected boundary:** Человек в экране дня корневого каталога и каталога на дату, в том числе с экранным диктором и крупным шрифтом, и потребители `ListState`
- **Implementation target:** ["lib/src/design_system/components/list_state.dart", "test/design_system/list_state_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart"]
- **Applicable constraints and non-goals:** Компоненты модуля основ остаются представлениями без предметных типов по ADR-0030. Вид заголовка при масштабе 1, его высота и позиции строк не зависят от обновления. Окна уже 360 не входят в область поддержки. Спецификация и design не меняются.

### U2 · Решение о повторе отказа обновления принимается в одном месте

- **Work items:** ["1.20"]
- **Requirements and scenarios:** ["Каталог дневных выборов по дате и секциям: Отказ обновления виден на месте продолжения", "Подтверждённые результаты и безопасные ошибки дневного выбора"]
- **Affected boundary:** Человек с устаревшей выдачей в каталоге и слой представления каталога
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart"]
- **Applicable constraints and non-goals:** Рефакторинг без смены поведения: тексты отказов, модель выдачи, чтение и схема не меняются. Повтор предлагается только при доказанно временном отказе и запускается только при устаревшей выдаче.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные проверяющие получили нейтральные задания без артефактов планирования. Отдельный проверяющий U1 вернул неполное покрытие: ему нужен изменённый в диапазоне `daily_choice_catalog_body.dart` вне его цели. Поэтому U1 и U2 объединены, и новый свежий проверяющий с объединённым заданием на все семь путей поставки и тестов вернул полное покрытие на `50289c5e96801e5f051bb3933d6c816b74acaba5..402b9271783e3b2701fc4958aa121bc8e3ab4c79`. Контекстные пути `day_heading.dart` и `doable_type.dart` в диапазоне не менялись |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate redesign-daily-choices --strict --json` проходит. Единственное сообщение уровня `INFO` о `Сброс истории пунктом панели` ожидаемо по D12. `mise run check` завершился с кодом 0 в этом worktree на `402b9271783e3b2701fc4958aa121bc8e3ab4c79`: статический анализ без замечаний, 4029 обычных и 18 процессных тестов прошли; рабочее дерево отличалось только этим отчётом, который проверки не читают. Задачи 1.19 и 1.20 и их сценарии сопоставлены с кодом и тестами |
| Code quality | Complete | Линзы `code-review-and-quality` применены ко всем путям поставки на проверенной ревизии: корректность, читаемость, архитектура, безопасность, производительность. Новых зависимостей, секретов и внешних границ в диапазоне нет |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Граница показа слова обновления не закреплена тестом каталога

- **Evidence:** `lib/src/design_system/components/list_state.dart:86` и `:97-99` оставляют слово до масштаба 1,5 включительно. `test/daily_choice/presentation/catalog/daily_choice_catalog_supported_layout_test.dart:52-81` проверяет день недели только при масштабе 2, где слова уже нет, а `test/design_system/list_state_test.dart:138` и `:146` проверяют голый `ListState` вне `DayHeading`. Ширину слота ограничивает половина заголовка: `lib/src/design_system/components/day_heading.dart:100`. Замер с настоящим Inter в окне 360 на этой ревизии: при 1,5 заголовок шириной 320 вмещает слот 150,0, промежуток 8 и «Понедельник» 149,1, поэтому сейчас свободно 12,9 dp. Слот не шире половины заголовка, значит дню недели остаётся не меньше 152 dp, и реальный запас против изменений шрифта и отступов около 3 dp. Этот расчёт опирается на замеры отчёта и заново не снимался. При слове на масштабе 1,6 «Понедельник» и «Воскресенье» уже разрываются.
- **Evidence revisions:** ["402b9271783e3b2701fc4958aa121bc8e3ab4c79"]
- **Potential impact:** Сейчас день недели цел при всех замеренных масштабах от 1 до 2. Другой шрифт, другая типографика или другие отступы могут вернуть разрыв дня недели внутри слова при масштабе до 1,5, и все тесты останутся зелёными. Длинное слово обновления само по себе день недели не порвёт, потому что слот ограничен половиной заголовка. Вред только внешний: данные и поведение не затрагиваются.
- **Acceptance rationale:** Пользователь явно принял остаточный риск. Вред ограничен видом заголовка дня, запас зависит от редко меняемых шрифта и отступов, а цена устранения — новая задача 1.21 и ещё один цикл реализации и проверки Фазы 1. Условие не устранено и не опровергнуто.
- **Scope and assumptions:** Заголовок дня в корневом каталоге и каталоге на дату, окно шириной 360, масштаб текста до 1,5 включительно, русская и английская локали. Допущения: шрифт Inter, текущая типографика `body` и `caption`, текущая геометрия `DayHeading` и текущие отступы заголовка в каталоге. Подъём порога `_wordMaxScale` в промежуток между 1,5 и 1,75 тестами не ловится и тоже входит в принятый риск как осознанная правка константы. Тесты, код, спецификация, design, plan.md и tasks.md не меняются, корректирующая задача не создаётся.
- **Reopen when:** Смена шрифта, изменение типографики `body` или `caption`, изменение геометрии `DayHeading`, отступов заголовка дня в каталоге или порога `_wordMaxScale`, а также жалоба на разрыв дня недели внутри слова.
- **Acceptance authority:** Явное решение пользователя: запись о находке F1 в `openspec/changes/redesign-daily-choices/implementation-review-decisions.md` на коммите `8caa1f456d7b3dd20df12f86431c5fc0246cc3f1`. Коммит этой резолюции удаляет запись из текущей версии файла.
- **Originating finding:** F1
- **Acceptance lifetime:** Change-scoped

## Review coverage

Прочитаны proposal, дельта `daily-choice-management`, design, adr, plan и tasks на проверенной ревизии. Покрыты все три целевых коммита: `ebdf7555859d8a442f66a69907420f51e6617007` относится только к планированию и добавляет профили задач 1.19 и 1.20, `0e9e174b0ff971f5bac57c0deae490ace9eb7901` соответствует задаче 1.19, `402b9271783e3b2701fc4958aa121bc8e3ab4c79` — задаче 1.20. Изменения `tasks.md` в диапазоне — только отметки выполнения. Посторонних изменений нет.

По задаче 1.19 проверены все критерии приёмки. Замер в одноразовой копии подтвердил основание порога: до 1,5 день недели на одной строке, а со словом при 1,6 и 1,75 разрываются русские названия, при 2 ещё и «Wednesday». Мутации в той же копии: всегда видимое слово ломает тест `ListState` и все три теста дня недели при 200%, а убранное название живой области ломает тест `ListState` и тест строки обновления при 200%. Скрытие строки вне обновления при масштабе 200% проверяет `expectRefreshLineHidden`, поэтому название в режиме кольца не попадает в семантику вне обновления.

По задаче 1.20 найдены все три места чтения `canRetryRefresh`, других проверок типа отказа обновления для решения о повторе в `lib` нет: `daily_choice_catalog_body.dart:740` выбирает текст отказа. Проверка `freshness == stale` сохранена. Мутация, разрешающая повтор при любом отказе, ломает оба теста каталога о повторе только при доказанно временном отказе, поэтому существующие тесты действительно закрепляют неизменность поведения.

Две мысли проверяющих не стали находками. Порог, подобранный под геометрию заголовка, не вредит сейчас: у `ListState.refreshing` один потребитель, выбор места в компоненте задан задачей 1.19, а параметр для другого потребителя был бы преждевременным. Отдельный тест нелинейного масштаба не добавлен в находку: код уже читает размер caption через `TextScaler`, а откат к другому чтению лишь немного сместил бы порог, и такой тест не окупается.

Темы коммитов задач длиннее правила в 72 символа: 76 и 74. Переписывать историю этапу запрещено, на поведение это не влияет.

Ручные проверки на устройстве остаются за владельцем продукта. Папка `context/` с README дизайна в этом worktree отсутствует, поэтому вид заголовка сверен с тестами, а не с README `DayHeading`.
