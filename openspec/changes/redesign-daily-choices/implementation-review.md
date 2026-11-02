# OpenSpec Implementation Review: redesign-daily-choices

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 1.15–1.18 выполнены по критериям приёмки, а две находки низкой серьёзности остаются открытыми: постоянный слот при крупном шрифте разрывает длинный день недели посреди слова, а правило повтора отказа обновления повторено в трёх местах. Принятых рисков нет.

## Review target

- **Baseline ref:** c499430a6f98e95fde6ee2285e0f7b2489bcd65f
- **Base commit:** c499430a6f98e95fde6ee2285e0f7b2489bcd65f
- **Reviewed head:** 702ff26f9996e647fa6e9a76bfbc530ae9e81618
- **Target commits:** ["4ad528b9f62eda9294cd79b4ccf0e31520b2ec21", "a7d1534993aa5e13db53c2314e89b50333d9f3b3", "5564f454ec77ac1713ab0d42a6b8ef731b8a7968", "1e531a97df6270ad9796196d98c79aa7f09b493d", "702ff26f9996e647fa6e9a76bfbc530ae9e81618"]
- **Reviewable paths:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/design_system/components/day_heading.dart", "openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md", "test/app/daily_choice_app_lifecycle_test.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/design_system/choice_check_test.dart", "test/design_system/day_heading_test.dart", "test/design_system/scroll_top_button_test.dart"]
- **OpenSpec change:** redesign-daily-choices
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choices/task-profiles.md", "openspec/changes/redesign-daily-choices/tasks.md"]

## Reviewed increment

### U1 · Устаревшая выдача показывает отказ на месте продолжения

- **Work items:** ["1.15"]
- **Requirements and scenarios:** ["Каталог дневных выборов по дате и секциям: Отказ обновления виден на месте продолжения", "Подтверждённые результаты и безопасные ошибки дневного выбора"]
- **Affected boundary:** Человек в корневом каталоге и каталоге на дату, в том числе с экранным диктором
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart"]
- **Applicable constraints and non-goals:** Модель, чтение и схема не меняются. `Notice` в начале выдачи остаётся. Повтор предлагается только при доказанно временном отказе.

### U2 · Строка обновления не ложится на заголовок дня и ничего не двигает

- **Work items:** ["1.16"]
- **Requirements and scenarios:** ["Задача 1.9: обновление выдачи не сдвигает строки", "Каталог дневных выборов по дате и секциям"]
- **Affected boundary:** Человек в каталоге дня, в том числе с экранным диктором и крупным шрифтом, и потребители `DayHeading`
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "lib/src/design_system/components/day_heading.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart", "test/design_system/day_heading_test.dart"]
- **Applicable constraints and non-goals:** Компоненты модуля основ остаются представлениями без предметных типов по ADR-0030. При масштабе шрифта 1 вид заголовка не меняется. Спецификация и design не меняются.

### U3 · Проверка перезапуска подтверждает строку выбора именно этого дня

- **Work items:** ["1.17"]
- **Requirements and scenarios:** ["Начальное состояние и сохранение календаря каталога: Перезапуск на следующий день", "Краткая карточка дневного выбора"]
- **Affected boundary:** Защита от регрессий долговечности каталога при перезапуске
- **Implementation target:** ["test/app/daily_choice_app_lifecycle_test.dart"]
- **Applicable constraints and non-goals:** Дата в карточку не возвращается. Производственный код не меняется, остальные ожидания теста не ослаблены.

### U4 · В тестах компонентов нет тестов без отдельной регрессии

- **Work items:** ["1.18"]
- **Requirements and scenarios:** ["Правило proven-necessity: тест ловит отдельную регрессию"]
- **Affected boundary:** Защита от регрессий компонентов модуля основ
- **Implementation target:** ["test/design_system/choice_check_test.dart", "test/design_system/scroll_top_button_test.dart"]
- **Applicable constraints and non-goals:** Производственный код, спецификация и design не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные проверяющие получили нейтральные задания без артефактов планирования. U1 и U2 делят пути, поэтому у них один проверяющий и объединённое задание на четыре пути. U4 проверена отдельно на двух путях. Для U3 первый проверяющий прочитал изменённый вне границы путь и вернул неполное покрытие, поэтому его результат заменён: новый свежий проверяющий получил тест и `daily_choice_catalog_body.dart` как контекст ключа и вернул полное покрытие. Контекстные пути проверяющих вне цели не менялись в диапазоне |
| OpenSpec conformance | Complete | `mise exec --no-deps -- openspec validate redesign-daily-choices --strict --json` проходит. Единственное сообщение уровня `INFO` о `Сброс истории пунктом панели` ожидаемо по D12. Целевые тесты изменённых модулей: 340 прошли. `mise run check` завершился с кодом 0 в этом worktree на `702ff26f9996e647fa6e9a76bfbc530ae9e81618`; менялся только этот отчёт, который проверки не читают. Задачи 1.15–1.18 и их сценарии сопоставлены с кодом и тестами |
| Code quality | Complete | Линзы `code-review-and-quality` применены ко всем путям поставки на проверенной ревизии: корректность, читаемость, архитектура, безопасность, производительность. Новых зависимостей, секретов и внешних границ в диапазоне нет |

## Findings

### F1 · Low — Постоянный слот разрывает длинный день недели посреди слова при крупном шрифте

- **Evidence:** `lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart:222` всегда передаёт строку обновления в слот, а `lib/src/design_system/components/day_heading.dart:90-100` отдаёт ей до половины ширины заголовка. Измерение в одноразовой копии проверенной ревизии со шрифтом Inter из пакета приложения: при окне 360 и масштабе 1,75 слот занимает 160, дню недели остаётся 152, и «Понедельник» и «Воскресенье» стоят на двух строках как одно слово. При масштабе 2 то же происходит с «Wednesday», а также при окнах 390 и 412. Без слота при тех же условиях слово стоит на одной строке, а при масштабе 1,5 разрыва нет. Тест при масштабе 200% проверяет только непересечение и не видит разрыва.
- **Evidence revisions:** ["702ff26f9996e647fa6e9a76bfbc530ae9e81618"]
- **Impact:** Человек с крупным системным шрифтом в поддерживаемых окнах от 360 постоянно читает заголовок вида «Понедельни / к», хотя обновление на экране редко. Текст не теряется, страдает читаемость именно у тех, кто увеличил шрифт ради неё.
- **Required outcome:** В поддерживаемых окнах при масштабе до 200% день недели не разрывается внутри слова, либо человек явно принимает этот разрыв как часть следствия задачи 1.16.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/design_system/components/day_heading.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart", "test/daily_choice/presentation/catalog/daily_choice_catalog_page_test.dart"]
- **Decision needed:** Задача 1.16 принимает, что день недели и отметка «Сегодня» раньше переносятся на вторую строку, но не называет разрыв внутри слова. Нужно решить, устранять его или принять как остаточный риск: от этого зависит, остаётся ли слот шириной до половины заголовка.

### F2 · Low — Правило повтора отказа обновления повторено в трёх местах

- **Evidence:** `lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart:439` и `:716` одинаково решают, есть ли повтор, проверкой `failure is DailyChoiceCatalogUnavailableFailure`. `lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart:105-111` проверяет то же условие и иначе молча возвращает `Future.value()`. Отказы первой загрузки и порции несут готовое свойство `canRetry` (`daily_choice_catalog_state.dart:99`, `:174`), а подвал стал вторым потребителем правила без такого общего ответа.
- **Evidence revisions:** ["702ff26f9996e647fa6e9a76bfbc530ae9e81618"]
- **Impact:** Если правило доказанной временности изменится, забытая копия даст кнопку «Повторить», нажатие на которую ничего не делает, либо скроет действующий повтор. Подвал закрепил это расхождение вторым местом показа.
- **Required outcome:** Решение о том, допускает ли отказ обновления повтор, принимается в одном месте, а оба места показа опираются на него.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart"]

## Review coverage

Прочитаны proposal, дельта `daily-choice-management`, design, adr, plan и tasks на проверенной ревизии. Покрыты все пять целевых коммитов: `4ad528b9f62eda9294cd79b4ccf0e31520b2ec21` относится только к планированию и добавляет профили задач, `a7d1534993aa5e13db53c2314e89b50333d9f3b3`, `5564f454ec77ac1713ab0d42a6b8ef731b8a7968`, `1e531a97df6270ad9796196d98c79aa7f09b493d` и `702ff26f9996e647fa6e9a76bfbc530ae9e81618` соответствуют задачам 1.15–1.18 один к одному. Изменения `tasks.md` в диапазоне — только отметки выполнения. Посторонних изменений нет.

Проверены сброс `refreshFailure` при запуске обновления и возврат кольца в подвал, сохранение `_requestPage`, скрытие строки обновления от нажатий и семантики, остановка кольца вне обновления, живая область во время обновления, совпадение `durabilityUuid` с ключом `daily-choice-completion-<id>` и достаточность оставшихся тестов после удалений. Вид заголовка при масштабе 1 в окнах 360 и 390 измерен со слотом: день недели с отметкой «Сегодня» стоит на одной строке. Окна уже 360 не входят в область поддержки `app-appearance`.

Замечание проверяющего о том, что тест кольца не заметит галочку у невыполненного выбора, опровергнуто мутацией в одноразовой копии: при всегда рисуемой галочке падают тесты кольца в обеих темах. Удаление теста «выбор без выполнения не рисует галочку» обосновано.

Ручные проверки на устройстве остаются за владельцем продукта. Папка `context/` с README дизайна в этом worktree отсутствует, поэтому вид заголовка сверен с тестами, а не с README `DayHeading`.
