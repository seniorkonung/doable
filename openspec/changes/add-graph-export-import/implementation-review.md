# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 2.28 выполнена, и полные проверки проекта на проверяемой голове проходят. Из тестов приложения удалён тест выбора файла с данными. Каждое его звено ловит другой тест, а проверки пустых `created` и `finished` в нём верны по построению. Из теста экспорта удалены проверки пустого временного каталога и пустого `finished`, а название теста теперь описывает то, что он проверяет. Сценарий «В диалоге выбран прежний файл» по-прежнему подтверждают нативная проверка, проверка канала, тест экспорта и тест presenter. Повтор, который снова открывает диалог, одинаков для всех исходов экспорта и проверен на отказе записи документа. Активных замечаний нет. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 5a8ec9392ddb59f12a9d00aa2c1c6cd4b8b5c627
- **Base commit:** 5a8ec9392ddb59f12a9d00aa2c1c6cd4b8b5c627
- **Reviewed head:** 3ae49beda0690d97615ac068ec0d0b5307674c67
- **Target commits:** ["3ae49beda0690d97615ac068ec0d0b5307674c67"]
- **Reviewable paths:** ["openspec/changes/add-graph-export-import/tasks.md", "test/app/graph_export_app_flow_test.dart", "test/data_transfer/graph_export_test.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Сценарий выбора файла с данными подтверждают только проверки, которые ловят собственную регрессию и названы по тому, что проверяют

- **Work items:** ["2.28"]
- **Requirements and scenarios:** ["graph-export-import: Экспорт в файл — сценарий «В диалоге выбран прежний файл»", "plan: Phase 2 Ready to advance — сценарии экспорта подтверждены проверками"]
- **Affected boundary:** Набор автоматических проверок экспорта: тесты приложения, тесты `GraphExport` и `GraphExportController` с настоящим координатором, а также неизменённые тест presenter, проверка канала и нативная проверка Robolectric, на которые теперь опирается сценарий.
- **Implementation target:** ["test/app/graph_export_app_flow_test.dart", "test/data_transfer/graph_export_test.dart"]
- **Applicable constraints and non-goals:** Код приложения и другие проверки не меняются.
  Каждый оставшийся тест ловит правдоподобную регрессию, которую не ловит другой тест, и назван по тому, что проверяет.
  Названия тестов на русском. В обычных тестах нет замеров времени. Проверок на устройстве нет.
- **Excluded change scope:** Открытие документов и импорт относятся к этапу 4.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Один свежий изолированный рецензент `implementation-decision-review` проверил U1 по нейтральной записке о намерении. В записке были оба тестовых пути диапазона `5a8ec9392ddb59f12a9d00aa2c1c6cd4b8b5c627..3ae49beda0690d97615ac068ec0d0b5307674c67`. Планирующие артефакты, история Git, прежний отчёт и обсуждение реализации ему не передавались. Прежде чем читать контекстные пути, рецензент проверял их неизменность через `git diff --quiet`. Он сообщил полное покрытие и не нашёл существенных замечаний. |
| OpenSpec conformance | Complete | Проверено в чистом рабочем дереве worktree, `HEAD` которого совпадает с `3ae49beda0690d97615ac068ec0d0b5307674c67`. `rg 'ExistingFileChosen' test/app` ничего не находит. `mise exec --no-deps -- flutter test test/data_transfer/graph_export_test.dart test/app/graph_export_app_flow_test.dart` — 12 тестов прошли. `mise run check` (этап 2 завершается): формат — 723 файла без изменений; проверки CI-скриптов и `flutter analyze` — без замечаний; обычные тесты — 3037 прошли, на один меньше, чем 3038 прежнего прогона, то есть ровно удалённый тест; процессные тесты — 14 прошли. `mise exec --no-deps -- openspec validate add-graph-export-import --strict` — успешно. |
| Code quality | Complete | Оба тестовых пути пройдены по линзам `code-review-and-quality`: корректность, читаемость, архитектура, безопасность и производительность. Учтены неизменённые `GraphExport.chooseDocument` и `write`, `GraphExportController.start`, `GraphExportCompletion`, `_exportMessage` в `GraphOperationPresenter`, подмена `FileDocumentAccess`, тест presenter, проверка канала и `DocumentAccessPluginTest.kt`. После удаления не осталось неиспользуемых импортов и помощников. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

**Цель и сопоставление.**

Цель — коммит `3ae49beda0690d97615ac068ec0d0b5307674c67` и 3 пути. Рабочее дерево чистое, `HEAD` совпадает с проверяемой головой.

Файл `tasks.md` — свидетельство планирования. Диапазон меняет в нём только отметку задачи 2.28.

Оба тестовых пути входят в U1 и соответствуют задаче 2.28. Посторонней работы и путей без задачи нет.

Прежний отчёт относился к диапазону `a891602bdf651fb17696d3754b107fd913e4c952..99a31dbed697ebee1ef2701b3c7a9ca10ab5a389`. Активных замечаний и принятых рисков в нём не было, поэтому переносить нечего. Задача 2.28, которой он отдал удаление проверок, в этом диапазоне выполнена.

**Проверенные свойства.**

Удалённый тест приложения не ловил регрессий, которых не ловят другие тесты. Исход `GraphExportOutcome.existingFile` настоящих `GraphExportController` и координатора проверяет тест `graph_export_test.dart:331`. Текст на русском и английском и «Повторить», вызывающее повтор, проверяет тест presenter `graph_operation_presenter_test.dart:1427-1445` с настоящим координатором.

Повтор одинаков для всех исходов. `GraphExportController.start` передаёт координатору единственный `retry: () => unawaited(start())` для любого исхода, кроме отмены. `_exportMessage` берёт `completion.retry` и для `failed`, и для `existingFile`. То, что повтор снова открывает диалог, проверяют `graph_export_test.dart:273` и тест приложения `graph_export_app_flow_test.dart:104`.

Список `created` пополняет только подмена при выборе нового документа. `finishDocument` требует `CreatedDocument`, а `ExistingFileChosen` его не несёт. Поэтому проверки пустых `created` и `finished` верны по построению.

Временный файл пишется только в `GraphExport._write`, а ему нужен `CreatedDocument`. Путь до ответа диалога общий с отменой, и пустоту временного каталога на нём проверяет тест отмены `graph_export_test.dart:183`. Поэтому удалённая проверка временного каталога ничего не добавляла.

Оставшиеся проверки теста `graph_export_test.dart:331` ловят собственные регрессии. Проверка исхода `existingFile` ловит смешение с `failed`. Пустая диагностика ловит расширение условия диагностики в `chooseDocument`. Пустой ход экспорта ловит публикацию хода при принятии экспорта вне `_write`. Её не ловит тест отмены, который завершается до принятия, и тест неоткрывшегося диалога, который ход не проверяет. Новое название описывает именно эти проверки.

Ниже Dart-слоя сценарий подтверждают неизменённые проверки. `DocumentAccessPluginTest.kt:173` проверяет, что файл остаётся прежним, право отпущено, а удаления нет. `method_channel_document_access_test.dart:70` проверяет, что ответ `existing_file` превращается в `ExistingFileChosen`.

**Рассмотрено, но в замечания не записано.**

Коммит не запускал полный `mise run check`, который требует проверка задачи 2.28, и раскрывает это в описании. Полные проверки выполнены в этом ревью на проверяемой голове и прошли.

Ни один тест не проверяет, что `GraphExportCompletion.isFailure` для `existingFile` равно `true`. От этого зависит, какое сообщение общая поверхность предъявляет, если одновременно ожидают несколько результатов. Удалённый тест показывал один результат и этого тоже не проверял. Диапазон этот пробел не создаёт и не усиливает. `isFailure` задан исчерпывающим `switch` по запечатанному перечислению, а прежнее ревью задачи 2.25 сверило его с требованием показывать сообщение по тем же правилам, что «Не удалось сохранить файл».

**Ограничения.**

На устройстве ничего не проверялось, и эти проверки остаются ручными проверками пользователя. Нужно убедиться, что выбор прежнего файла в диалоге сохранения оставляет его без изменений и показывает «Такой файл уже есть. Сохраните копию под новым именем». Нужно убедиться, что экспорт в новый файл локальной папки и облачного хранилища по-прежнему проходит.
