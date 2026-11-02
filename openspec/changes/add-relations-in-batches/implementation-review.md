# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 3.24–3.27 выполнены: занятая строка сообщает диктору название и причину одним элементом, действия строк экрана выбора заданы закрытым типом, отказ занятой пары говорит о связи с намерением страницы, а строка без читателя удалена. Активных находок и принятых рисков нет, полные проверки фазы 3 проходят. Ручная проверка диктора на устройстве остаётся за владельцем продукта.

## Review target

- **Baseline ref:** 3875db90cafcc66a05d93c524a44918368f69b6d
- **Base commit:** 3875db90cafcc66a05d93c524a44918368f69b6d
- **Reviewed head:** 2a97cf9333ef07474bfa50976398c80caadde72b
- **Target commits:** ["6656201a1ffc1c9bbe2cbe97dc9f6fe2da456ec2","1e385bc4af91f2efedb3d78ba7deed6c1e42083a","8e4d28b4e6ffe626881fc6c6c756cd834957366e","98c9256cb0669b7010379d565bf6db2748e0735f","2a97cf9333ef07474bfa50976398c80caadde72b"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/design_system/components/picker_row.dart","lib/src/intention/presentation/picker/intention_picker_row.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/design_system/picker_row_test.dart","test/graph/presentation/graph_operation_presenter_test.dart","test/intention/presentation/picker/intention_picker_test_support.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Занятая строка сообщает диктору название и причину одним элементом

- **Work items:** ["3.24"]
- **Requirements and scenarios:** ["intention-management: Строка результата поиска намерений","intention-management: Карточка занятой пары называет отметку","long-term-relation-management: Причина занятой пары в поиске участника"]
- **Affected boundary:** Пользователь экранного диктора в поиске участника и общая строка экрана выбора.
- **Implementation target:** ["lib/src/design_system/components/picker_row.dart","test/design_system/picker_row_test.dart"]
- **Applicable constraints and non-goals:** Компонент основ не знает предмета, новых строк локализации нет. Вид строки и незанятые варианты не меняются.

### U2 · Набор действий строки экрана выбора задан закрытым вариантом

- **Work items:** ["3.25"]
- **Requirements and scenarios:** ["intention-management: Строка результата поиска намерений"]
- **Affected boundary:** Виджеты строк экрана выбора, их вызывающие и тестовая опора.
- **Implementation target:** ["lib/src/design_system/components/picker_row.dart","lib/src/intention/presentation/picker/intention_picker_row.dart","test/intention/presentation/picker/intention_picker_test_support.dart"]
- **Applicable constraints and non-goals:** Поведение продукта и спецификации не меняются, вызывающим правки не нужны, открытого варианта поведения ради тестов нет.

### U3 · Отказ занятой пары говорит о связи с намерением страницы

- **Work items:** ["3.26"]
- **Requirements and scenarios:** ["long-term-relation-management: Направленная уникальность долговременной связи","long-term-relation-management: Добавление отмеченных намерений в группу"]
- **Affected boundary:** Человек, добавляющий пачку связей, и поверхность сообщения об отказе.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","test/graph/presentation/graph_operation_presenter_test.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **Applicable constraints and non-goals:** Строки есть на двух языках, созданные файлы приходят из кодогенерации. Контракт отказа и команда не меняются, конкретные намерения сообщение не называет.

### U4 · Строка без читателя удалена

- **Work items:** ["3.27"]
- **Requirements and scenarios:** ["proposal: Локализация — строки удалённых потоков уходят"]
- **Affected boundary:** Ресурсы локализации.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb"]
- **Applicable constraints and non-goals:** Поведение и спецификации не меняются, другие строки без читателя, существовавшие до изменения, остаются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных ревьюера `implementation-decision-review` на `3875db90…..2a97cf93…`, по одному на группу с общими файлами: U1 и U2 (Sonnet, medium), U3 и U4 (Sonnet, low). Оба вернули «No substantive findings» и полное покрытие. Первый ревьюер U3 и U4 (Haiku) увидел строки `tasks.md` и `task-profiles.md` в поиске и вернул `Incomplete`, поэтому его результат отброшен и заменён новым запуском с поиском только по `lib` и `test`. Ограничение: ревьюер U1 и U2 искал вызывающих в `lib` и `test` без предварительной проверки границы и видел только совпавшие строки других изменённых файлов, на вывод это не повлияло. Ревьюеры тесты не запускали. |
| OpenSpec conformance | Complete | Задачи 3.24–3.27, план фазы 3, сценарии спецификаций и D4 сверены с кодом и тестами на `2a97cf93…`. На дереве с `HEAD` = `2a97cf9333ef07474bfa50976398c80caadde72b` без правок: `mise run check` — код 0 (`flutter analyze` без замечаний, 3936 обычных и 18 процессных тестов); `mise run codegen-check` — код 0; `mise exec --no-deps -- openspec validate add-relations-in-batches --strict` — успех, это только структурное свидетельство. Дерево после проверок чистое. Устройство и эмулятор не использовались. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем рабочим путям на `2a97cf93…`. Вне правок учтены `IntentionRowContent`, `IntentionPickerView`, `longTermRelationCommandFailureMessage` и четыре вызова `intentionPickerPick`. Новых зависимостей, границ доверия и запросов в диапазоне нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все пять коммитов разобраны по диапазонам задач: `6656201a…` только планирующий и добавляет профили задач, поэтому входит в диапазон задачи 3.24, а `1e385bc4…`, `8e4d28b4…`, `98c9256c…` и `2a97cf93…` дают U1–U4 по порядку. U1 и U2 делят `picker_row.dart`, U3 и U4 — файлы локализации, поэтому каждая пара шла к одному ревьюеру. Все пути учтены, неотнесённых нет.

По U1 `MergeSemantics` охватывает только название и причину, а конструктор `PickerRow.occupied` фиксирует пустые описание, метки и теги и `archived = false`, поэтому лишнего в названии нет. Текст занятой строки не обёрнут в `InkWell`, стрелка остаётся отдельной областью. Тест ждёт название `Бег\nУже добавлено` и проверяет название и действие стрелки. Что текст не реагирует на нажатие, подтверждает существующее нажатие в том же тесте.

По U2 `_behavior` стал единственным полем обоих виджетов, а геттеры и `onPick!` исчезли. Сигнатуры конструкторов сохранены, `intention_picker_view.dart` и проверки строк не менялись, вызовов с `const` нет. `requiredTagIds` остаётся, потому что его читает `IntentionRowContent.of`. Два закрытых типа с одинаковыми именами живут в разных файлах и несут разные данные, поэтому находкой не считаются. `intentionPickerPick` берёт первый `InkWell`, и у занятой строки это была бы стрелка, но все четыре вызова идут по выбираемым строкам.

По U3 ключ читается только в ветке `LongTermRelationCommandKind.add`, поэтому другие команды новый текст не показывают. Спецификации не задают его дословно. Запоздавший отказ показывает оболочка после закрытия поиска, и там «этим намерением» опирается на страницу под поиском; по D5 пара отмеченного намерения занятой стать не должна, поэтому случай редкий, а дословный текст задан задачей. По U4 ключа нет в `lib` и `test`, соседние строки изменения и перечисленные в задаче строки без читателя не тронуты.

Прошлый отчёт не содержал находок и принятых рисков, поэтому переносить нечего. Код в этом этапе не менялся, новых задач нет. Вручную на устройстве остаётся проверить, как диктор читает занятую строку.
