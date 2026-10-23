# OpenSpec Implementation Review: redesign-intention-pickers

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задача 1.8 выполнена. Набор свёртки в `IntentionDescriptionPreview` теперь записан только видимыми экранированиями и по кодовым точкам совпадает с прежним, поэтому начало любого описания не меняется. Новый тест ловит потерю любого символа набора. Остаётся одно замечание низкой серьёзности. F2: два прежних теста стали дублировать новые проверки. Сверку набора со `String.trim` в обе стороны теперь ведёт открытая задача 1.9. `mise run check` на проверяемой голове проходит. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 7d40133e28abb06e42f8618fe613db1e919c8ff3
- **Base commit:** 7d40133e28abb06e42f8618fe613db1e919c8ff3
- **Reviewed head:** 00114351b14326c2c3244acce248c56e222d4acb
- **Target commits:** ["00114351b14326c2c3244acce248c56e222d4acb"]
- **Reviewable paths:** ["lib/src/intention/application/intention_description_preview.dart", "openspec/changes/redesign-intention-pickers/tasks.md", "test/intention/application/intention_description_preview_test.dart"]
- **OpenSpec change:** redesign-intention-pickers
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-pickers/tasks.md"]

## Reviewed increment

### U1 · Набор пробельных символов начала описания читается в исходнике и закреплён тестом

- **Work items:** ["1.8"]
- **Requirements and scenarios:** ["design: решение 5 «Начало описания — часть краткой сводки», п. 1 — пробельные символы те же, что у `String.trim`: Unicode `White_Space` и `U+FEFF`"]
- **Affected boundary:** Фабрика `IntentionDescriptionPreview.fromDescription` и её модульные тесты
- **Implementation target:** ["lib/src/intention/application/intention_description_preview.dart", "test/intention/application/intention_description_preview_test.dart"]
- **Applicable constraints and non-goals:** Набор свёртки — ровно символы, которые обрезает `String.trim`. Доменная проверка пустого описания использует `trim`, поэтому начало описания непусто ровно тогда, когда описание сохранено. Набор, предел длины и прочее поведение фабрики не меняются. Текст описания не попадает в диагностику. В тестах нет замеров времени.
- **Excluded change scope:** Показ начала описания и новый вид поисков относятся к фазам 2 и 3.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный ревьюер работал по `implementation-decision-review`. Он получил нейтральный бриф U1 и оба пути цели на 7d40133e28abb06e42f8618fe613db1e919c8ff3..00114351b14326c2c3244acce248c56e222d4acb. Артефакты планирования, история коммитов и отчёт ему не передавались. Он побайтно раскодировал литералы базы и сравнил новое регулярное выражение со `String.trim` текущего SDK на всех кодовых точках U+0000–U+10FFFF, кроме суррогатов: расхождений нет. Целевой тест у него прошёл: 30 тестов. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии на HEAD = 00114351b14326c2c3244acce248c56e222d4acb; рабочая копия была чистой. `mise run check` завершился с кодом 0: `dart format` не изменил ни одного из 770 файлов, `flutter analyze` без замечаний, прошли 3217 обычных и 18 процессных тестов. `mise exec --no-deps -- openspec validate redesign-intention-pickers --strict --no-interactive --json` даёт valid. Критерии 1.8 сверены с диффом в обе стороны. Сырых пробельных и невидимых символов, кроме U+0020, в исходнике фабрики нет. Тест перечисляет все 26 символов набора через `\uXXXX`. Отметка 1.8 подкреплена кодом и тестом. |
| Code quality | Complete | Линзы `code-review-and-quality` применены к обоим путям U1: корректность, читаемость, архитектура, безопасность и производительность. Регулярное выражение по-прежнему компилируется один раз как статическое поле. Прослежены вызов фабрики в `_rehydrateSummary` (`drift_personal_graph_repository.dart:1357`) и доменная проверка `IntentionText.normalizeDescription` (`intention_text.dart:59`). |

## Findings

### F2 · Low — Два прежних теста фабрики теперь дублируют новые посимвольные проверки

- **Evidence:** Новые посимвольные тесты (`test/intention/application/intention_description_preview_test.dart:37-46`) для каждого символа набора сворачивают внутреннюю серию и обрезают серию в начале и символ в конце. Смешанную внутреннюю серию проверяет тест «заменяет каждую серию пробельных символов одним пробелом» (`:47-53`). Тесты «обрезает пробельные символы по краям» (`:55-61`) и «у описания с краевыми пробелами и переносами начало непусто» (`:73-79`) проверяют только смешанные серии по краям. Такая серия после свёртки становится одним пробелом, а его обрезку уже покрывают посимвольные тесты. Регресса, который поймал бы только один из этих двух тестов, нет. Первый тест правился в диапазоне: литералы заменены экранированиями.
- **Evidence revisions:** ["00114351b14326c2c3244acce248c56e222d4acb"]
- **Impact:** Лишние тесты удорожают каждое следующее изменение фабрики и создают видимость защиты, которой они не добавляют. Это нарушает правило проекта о доказанной необходимости тестов.
- **Required outcome:** Каждый тест фабрики ловит регресс, который не ловит никакой другой тест файла.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/intention/application/intention_description_preview_test.dart"]

## Review coverage

Прежние невидимые литералы базы раскодированы по кодовым точкам: U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000 и U+FEFF. Новые экранирования `\t`, `\n`, `\u000B`, `\f`, `\r`, пробел и `\u0085` дают тот же набор из 26 символов. Он совпадает с Unicode `White_Space` и U+FEFF, поэтому начало любого описания не меняется. Строка регулярного выражения не сырая, так что ` - ` превращается в символьный диапазон внутри класса.

Подсчитано, что тест покрывает все символы, которые перечисляет критерий 1.8, включая U+0085, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F и U+205F. Входная строка содержит двойную внутреннюю серию, поэтому удаление любого символа из регулярного выражения валит соответствующий тест. Это верно и для символов, которые обрезал бы `trim`. В остальных тестах файла пробельные символы тоже записаны экранированиями. Единственный невидимый символ — соединитель U+200D внутри emoji семьи в тесте предела длины. Он был там до диапазона и пробельным не является.

Других путей поставки в диапазоне нет; `tasks.md` меняет только отметку 1.8. Проверки на устройстве не выполнялись по правилу проекта. Поведение экрана диапазон не меняет, поэтому новых ручных проверок он не добавляет.
