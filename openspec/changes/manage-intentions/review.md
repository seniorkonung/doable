# Проверка OpenSpec change: manage-intentions

## Оценка

**Результат:** Требуются изменения.

В графе артефактов остаются пять активных замечаний: versioned search key не
имеет независимой от toolchain неизменяемой реализации, remediation
транзитивно опирается на completion claim, который должна исправить, граница
`U+0000` не определена, для активного дефекта описания нет corrective work, а
долговечный ADR graph не владеет schema-function contract.

**Валидация:** `openspec validate manage-intentions --type change --strict
--no-interactive --json` успешна: 1/1, структурных issues нет. Эта проверка не
обнаруживает семантические противоречия ниже и не является разрешением на Apply.

## Замечания

### F2 · High — `v1` не имеет зафиксированных реализации и Unicode data

- **Evidence:** `specs/intention-management/spec.md:126` задаёт точный Full
  Default Case Folding Unicode 17.0.0, а `design.md:189` и `:273` передают его
  одной операции `titleSearchKeyV1`. Однако `design.md:294` ограничивается
  проверкой конечного corpus при toolchain upgrade, `:491` прямо допускает
  изменение Unicode-таблиц Dart, а задача 6.20 не назначает собственные
  неизменяемые algorithm/data для всей допустимой области Unicode. SQLite
  определяет deterministic function как всегда возвращающую один ответ для
  одного ввода и предупреждает, что изменившаяся функция в generated/index
  expressions может сделать базу некорректной:
  https://www.sqlite.org/deterministic.html.
- **Impact:** после toolchain upgrade уже сохранённые `STORED`-ключи могут быть
  вычислены прежней семантикой, а ключ нового фильтра и новые строки — новой.
  Один logical schema version тогда содержит смешанные значения, из-за чего
  FTS, точный count и страницы могут давать ложные совпадения или пропуски.
  Выборочный corpus не доказывает стабильность на всём разрешённом Unicode
  input domain.
- **Required change:** после решения F1 реализация `titleSearchKeyV1` должна
  зафиксировать собственную версию алгоритма и Unicode data независимо от
  текущего SDK либо planning должно определить исчерпывающе доказуемый version
  bump/rebuild contract. Будущая `v2` обязана сохранять доступную реализацию и
  регистрацию `v1` на время открытия и атомарной миграции старой базы; query
  key, generated column и FTS rebuild должны переключаться одной schema
  migration.

### F3 · Medium — Remediation транзитивно зависит от опровергнутого completion claim

- **Evidence:** завершённые задачи 6.16 и 6.17 утверждают отсутствие успешной
  страницы и ложного count при несогласованном `title_search_key`
  (`tasks.md:572`–`:595`), но текущий `implementation-review.md:7`–`:10`
  прямо не подтверждает completion 6.17, а новые задачи 6.21–6.22 заново
  реализуют и доказывают тот же результат. При этом 6.18 зависит от 6.17
  (`tasks.md:597`–`:607`), 6.19 зависит от 6.18, а 6.20 начинает поисковую
  remediation только после 6.19. Таким образом, исправление транзитивно
  использует как выполненную предпосылку утверждение, которое оно исправляет.
- **Impact:** Apply видит 6.16/6.17 как надёжное завершённое evidence и может
  повторно использовать неверную corrupt-row матрицу либо ошибочно считать
  Phase 6 согласованной до выполнения новых задач. Финальный checkpoint не
  получает однозначного источника истины о том, какие прежние search claims
  superseded.
- **Required change:** с учётом запрета редактировать checked blocks новые
  unchecked задачи должны явно supersede search-key/write/count части 6.5,
  6.16 и 6.17. Независимая cursor-задача 6.18 не должна зависеть от
  неподтверждённого search completion, а 6.20–6.23 и финальный checkpoint
  должны собирать evidence только из новой цепочки remediation.

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
  полную готовность Phase 6 и переход к Phase 7 (`tasks.md:621`–`:669`) без
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

- **Evidence:** `design.md:290`, `:327` и `:517` делает имя и неизменяемую
  реализацию `doable_title_search_key_v1`, обязательную регистрацию на каждом
  connection, trust boundary `directOnly: false` и сохранение старой функции при
  будущей migration долговечным межрелизным schema contract. `adr.md:10`
  относит поиск лишь к общему решению об «internal migratable FTS5 index» из
  ADR-0002, тогда как сам ADR-0002 не фиксирует versioned application-defined
  function, Unicode data, connection/trust requirements или совместимость
  прежних функций. Дополнительно `design.md:523` называет действующими только
  ADR-0002–ADR-0005, хотя `adr.md:16`–`:22` включает ADR-0006.
- **Impact:** будущий change, следующий по долговечному ADR graph, может
  обновить Unicode/toolchain, отключить регистрацию `v1`, изменить
  `trusted_schema` или перестроить таблицу, не сохранив обязательную функцию для
  открытия и миграции прежней базы. Design текущего change тогда останется
  единственным и противоречиво перечисленным источником критичного lifecycle
  решения.
- **Required change:** после разрешения F1/F2 выбранную архитектуру search-key
  function, её security boundary и правила version/migration compatibility
  нужно закрепить в подходящем долговечном ADR, а `adr.md`, design active-set и
  downstream dependencies привести к одному графу решений.

## Охват проверки

Перечитаны полный artifact graph `proposal → specs → design → adr → plan →
tasks`, действующие ADR-0002–ADR-0006, предметный glossary, текущие
implementation-review findings, schema/search/repository code и подключённые
Drift/sqlite3 seams. Повторно проверены intent, behavioral ownership,
двусторонняя traceability и исполнимость задач; углублённо рассмотрены Unicode
и NUL input boundaries, application/SQL membership parity, description
integrity, generated persistent data, migration/versioning, connection setup,
FTS consistency, security boundary `directOnly: false`, ADR durability,
bounded count/page и регрессионный performance budget. UI не переоценивался
глубже необходимого для проверки post-command membership границы Phase 6.
