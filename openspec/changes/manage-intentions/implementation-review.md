# OpenSpec Implementation Review: manage-intentions

## Оценка

**Результат:** Changes needed

Экранирование буквальной FTS5 phrase и adversarial-проверки корректны для
FTS-пути, но публичная граница helper допускает короткий валидный фильтр, для
которого trigram `MATCH` молча возвращает пустой результат вместо выбора
параметризованного `instr`-пути.

## Граница ревью

- **Явная локальная база:** `1e3a9d563b6bb900996360cf8627067f74e5a2db`
- **Проверенная вершина:** `9eb803822545536e937bae8c160afbbf2724a95d`
- **Проверенный implementation-коммит:** `52191fdfdde2696423119dc61527cbf40dba0926`
- **Коммиты в техническом диапазоне:** 2; `9eb803822545536e937bae8c160afbbf2724a95d` содержит только исключённый отчёт предыдущего ревью
- **Проверяемые пути:** 3; `implementation-review.md` исключён
- **OpenSpec change:** `manage-intentions` (`intent-driven`)
- **Свежесть базы:** явный локальный ref; `fetch` не выполнялся
- **Исключённый диапазон:** пять более ранних исходящих коммитов до `1e3a9d563b6bb900996360cf8627067f74e5a2db` не проверялись по прямому указанию пользователя

## Проверенный инкремент

### U1 · Буквальная граница FTS5 phrase для фильтра названия

- **Work items:** 5.4
- **Requirements and scenarios:** `Фильтрация каталога по названию`; буквальная регистронезависимая подстрока, сохранение внутренних пробелов и различие Unicode-букв и диакритики
- **Affected boundary:** внутренний ввод фильтра названия из будущего локального repository adapter в SQLite search
- **Implementation target:** `lib/src/data/local/fts_query.dart`, `test/data/local/fts_consistency_test.dart`
- **Planning evidence:** `openspec/changes/manage-intentions/tasks.md` отмечает задачу 5.4 выполненной
- **Applicable constraints and non-goals:** пользовательский фильтр не изменяет SQL или FTS-грамматику; ключи короче трёх Unicode-кодовых точек используют параметризованный `instr`; production repository, каталог и UI не входят в инкремент
- **Excluded change scope:** задача 5.5 и последующие repository/UI-фазы не проверялись

## Покрытие проходов

| Проход | Статус | Доказательство или ограничение |
|---|---|---|
| Independent decision review | Complete | свежий изолированный reviewer проверил только `fts_query.dart` и `fts_consistency_test.dart` на неизменяемой границе; установлен F1 |
| OpenSpec conformance | Complete | задача 5.4 и относящиеся к ней требования сопоставлены с diff в обе стороны; `openspec validate manage-intentions --json` успешен |
| Code quality | Complete | delivery-пути и неизменённые schema/caller boundaries проверены по correctness, readability, architecture, security и performance; целевой Flutter-тест и полный анализ успешны |

## Findings

### F1 · Medium — Применимость trigram FTS не закреплена в публичной границе

- **Evidence:** `lib/src/data/local/fts_query.dart:4` принимает любой `String` и только экранирует кавычки перед созданием `Variable<String>`. Trigram FTS5 не возвращает совпадений для полнотекстового запроса короче трёх Unicode-кодовых точек, что прямо оговорено в [официальной документации SQLite](https://www.sqlite.org/fts5.html#the_trigram_tokenizer). `test/data/local/fts_consistency_test.dart:57`–`59` проверяет `к` и `ко` через отдельный приватный `_findByShortSearchKey`, а не через общую границу, выбирающую его вместо FTS-helper; все новые FTS-fixtures имеют не меньше трёх кодовых точек.
- **Impact:** будущий repository caller может передать в экспортируемый helper валидный короткий фильтр. SQL останется безопасным, но `MATCH` молча вернёт пустую выдачу вместо буквального подстрочного совпадения; компилятор и API не обнаружат неверный выбор пути.
- **Required outcome:** локальная поисковая граница или её типы должны гарантировать буквальную подстрочную семантику для каждого валидного фильтра, включая значения короче трёх Unicode-кодовых точек, и не позволять направить их в trigram `MATCH` только по дисциплине caller.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** задача 5.4; раздел design о буквальной FTS phrase и коротком `instr`-пути; `fts_query.dart`; `fts_consistency_test.dart`
- **Disposition:** Open

## Покрытие ревью

Проверены только три reviewable path узкого диапазона, FTS5 phrase escaping,
SQL parameterization, trigram substring semantics, короткий fallback, граница
будущего repository caller и adversarial matrix. Целевой Flutter-тест прошёл 5
сценариев, `flutter analyze` и целевой Dart-анализ завершились без замечаний,
`git diff --check` и OpenSpec JSON-валидация успешны. Активного
Flutter/DTD-приложения не обнаружено, поэтому hot reload не выполнялся. Полный
test suite и build не запускались, поскольку они относятся к отдельной задаче
5.5 и выходят за запрошенный узкий review.
