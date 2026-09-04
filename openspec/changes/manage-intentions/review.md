# Проверка OpenSpec change: manage-intentions

## Оценка

**Результат:** Требуются изменения.

В графе артефактов остаются три требующих исправления замечания: граница
`U+0000` не определена, для активного дефекта описания нет corrective work, а
долговечный ADR graph не владеет schema-function contract.

Редкий межрелизный дрейф Unicode folding явно принят только для восстанавливаемой
поисковой проекции. Он может изменить включение намерения в фильтр и зависимый
точный count, но не изменяет канонический `title`, другое предметное состояние
или поведение идентичности, уникальности, авторизации и синхронизации. Specs,
design и новые задачи согласованно ограничивают этот residual risk;
дополнительная migration/versioning infrastructure в текущем scope не требуется.

**Валидация:** `openspec validate manage-intentions --type change --strict
--no-interactive --json` успешна: 1/1, структурных issues нет. Эта проверка не
обнаруживает семантические противоречия ниже и не является разрешением на Apply.

## Замечания

### F4 · Medium — Допустимый `U+0000` ломает буквальную семантику FTS5 и storage-проверки

- **Evidence:** specs разрешают название, описание и фильтр из Unicode-графем
  без запрета `U+0000` (`specs/intention-management/spec.md:30`–`:31`,
  `:63`–`:64`, `:125`–`:126`). В зафиксированных Dart 3.13.1 и
  `characters` 1.4.1 строка `U+0000` не удаляется `trim()` и считается одной
  графемой, то есть проходит эту прикладную границу. SQLite официально допускает
  встроенный NUL, но предупреждает, что строковые операции, в частности
  `length()`, ведут себя для него неожиданно:
  https://www.sqlite.org/nulinstr.html. В воспроизводимой проверке текущего
  `package:sqlite3` 3.5.2 / SQLite 3.53.4 параметризованный trigram `MATCH` с
  фразой `"ab\u0000cde"` завершился `SQLITE_ERROR: unterminated string`, а
  название `ab\u0000cde` совпало с фразой `"abc"`, хотя буквальной подстроки
  `abc` в нём нет. Design и задача 6.22 не включают эту границу в corpus.
- **Impact:** допустимый по behavioral spec пользовательский текст может дать
  нетипизированную ошибку поиска, ложное совпадение и неверный exact count;
  `length()` в текущем description constraint также может отклонить значение,
  которое предметная граница считает присутствующим. Параметризация защищает
  SQL, но сама по себе не делает NUL буквальным для FTS parser/tokenizer.
- **Required change:** behavioral contract должен либо явно исключить
  `U+0000` для каждого затронутого пользовательского поля с типизированной
  локализуемой validation failure, либо потребовать end-to-end представление и
  поисковую стратегию, сохраняющие его буквально. Выбранная граница должна быть
  одинаковой в domain/application, schema, FTS и adversarial tests.
- **Decision needed:** является ли `U+0000` допустимой частью пользовательских
  названий, описаний и фильтров или capability сознательно запрещает его? Это
  изменение публичного контракта ввода, а не только SQL-деталь.

### F6 · Medium — Финальный checkpoint не устраняет активный дефект описания

- **Evidence:** текущий `implementation-review.md:89`–`:110` сохраняет finding
  F4: schema допускает предметно отсутствующее либо слишком длинное описание,
  а catalog projection публикует только `description IS NOT NULL`. Утверждавшие
  обратное задачи 6.16 и 6.17 уже отмечены выполненными
  (`tasks.md:572`–`:595`) и по правилам task ledger не редактируются. Новая
  цепочка 6.20–6.22 владеет только search key/FTS, однако 6.23 после неё заявляет
  полную готовность Phase 6 и переход к Phase 7 (`tasks.md:621`–`:672`) без
  отдельной unchecked-задачи для описания.
- **Impact:** весь новый task chain может быть формально завершён, хотя каталог
  по-прежнему способен вернуть успешный `IntentionSummary(hasDescription:
  true)` для предметно отсутствующего или недопустимого сохранённого описания.
  Финальный checkpoint тогда подтверждает заведомо неполную integrity matrix.
- **Required change:** до финального checkpoint нужна новая unchecked
  remediation/evidence chain, явно superseding description-части 6.16/6.17 и
  доказывающая полный nullable/whitespace/4096-grapheme contract без
  материализации полного описания в summary. 6.23 должен зависеть от этого
  нового evidence наряду с cursor и search remediation.

### F7 · Medium — Долговечный schema-function contract отсутствует в ADR graph

- **Evidence:** `design.md:294`, `:315`, `:331` и `:516` делают имя и сигнатуру
  `doable_title_search_key(TEXT)`, обязательную регистрацию на каждом
  connection и trust boundary `directOnly: false` долговечным schema contract.
  `adr.md:10` относит поиск лишь к общему решению об internal migratable FTS5
  index из ADR-0002, тогда как сам ADR-0002 не фиксирует application-defined
  function, connection/trust requirements или совместимость schema с
  обязательной регистрацией функции.
- **Impact:** будущий change, следующий только по долговечному ADR graph, может
  отключить регистрацию, изменить `trusted_schema` или перестроить таблицу, не
  сохранив обязательную функцию для открытия прежней базы. Design текущего
  change тогда останется единственным источником критичного lifecycle решения.
- **Required change:** архитектуру search-key function, принятую область
  допустимого Unicode-дрейфа, её security boundary и обязательную регистрацию
  для совместимости schema нужно закрепить в подходящем долговечном ADR, а
  `adr.md` и downstream dependencies привести к одному графу решений.

## Охват проверки

Перечитаны полный artifact graph `proposal → specs → design → adr → plan →
tasks`, действующие ADR-0002–ADR-0006, предметный glossary, текущие
implementation-review findings, schema/search/repository code и подключённые
Drift/sqlite3 seams. Повторно проверены intent, behavioral ownership,
двусторонняя traceability и исполнимость задач; углублённо рассмотрены принятый
Unicode-data drift, NUL input boundary, application/SQL membership parity,
description integrity, generated persistent data, migration/versioning,
connection setup, FTS consistency, security boundary `directOnly: false`, ADR
durability, bounded count/page и регрессионный performance budget. UI не
переоценивался глубже необходимого для проверки post-command membership границы
Phase 6.
