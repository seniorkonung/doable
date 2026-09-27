# OpenSpec Implementation Review: manage-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F1: отказ точечного чтения назначения может исчезнуть после успешного чтения выбранного тега, оставив действие недоступным без повтора. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** b99e2e12392c3da893f9c830becfa912345cc118
- **Base commit:** b99e2e12392c3da893f9c830becfa912345cc118
- **Reviewed head:** 555483c7626fb6be5d04361dff5cc6debc2204ad
- **Target commits:** ["555483c7626fb6be5d04361dff5cc6debc2204ad"]
- **Reviewable paths:** ["lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "lib/src/tag/application/tag_assignment_status.dart", "lib/src/tag/application/tag_read_result.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "openspec/changes/manage-tags/tasks.md", "test/graph/data/drift_tag_assignment_read_test.dart", "test/support/tag_read_contract_test_fallback.dart", "test/tag/application/tag_read_contract_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **OpenSpec change:** manage-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-tags/tasks.md"]

## Reviewed increment

### U1 · Подтверждение назначения тега вне загруженной порции

- **Work items:** ["2.30"]
- **Requirements and scenarios:** ["Каталог тегов и выбор для назначения", "Свободный тег выбран за пределами загруженных порций", "Назначенный тег выбран за пределами загруженных порций", "Подтверждённые изменения и согласованные представления тегов"]
- **Affected boundary:** Точечное чтение пары тега и намерения либо долговременной связи в локальном хранилище; состояние выбора и доступность назначения в каталоге.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "lib/src/tag/application/tag_assignment_status.dart", "lib/src/tag/application/tag_read_result.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "test/graph/data/drift_tag_assignment_read_test.dart", "test/support/tag_read_contract_test_fallback.dart", "test/tag/application/tag_read_contract_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Только намерения и долговременные связи могут получать теги; архивное состояние этому не мешает. Чтение пары должно быть ограниченным и согласованным с ревизией, диагностика не раскрывает личный граф. Общий поиск и синхронизация не входят в изменение.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Изолированный рецензент проверил все 12 путей реализации и тестов U1 в точном диапазоне и обнаружил F1; материалы планирования и прежний отчёт ему не передавались. |
| OpenSpec conformance | Complete | Задача 2.30 и оба сценария выбора вне порции сопоставлены с реализацией и тестами. На чистом 555483c7626fb6be5d04361dff5cc6debc2204ad прошли `mise exec --no-deps -- openspec validate manage-tags --json` (1/1), три целевых файла `flutter test` (74 теста) и `flutter analyze`; проверка плана индексного поиска включена в тест репозитория. Нарушение восстановления после отказа отражено в F1. |
| Code quality | Complete | Проверены все 12 путей реализации и тестов, SQL-запрос и индексы, ревизии, переходы состояния выбора, диагностика и поведение экрана. `git diff --check` и `flutter analyze` прошли; конкретный дефект управления состоянием отражён в F1. |

## Findings

### F1 · Medium — отказ чтения назначения скрывается поздним успехом чтения тега

- **Evidence:** В `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart` на 555483c7626fb6be5d04361dff5cc6debc2204ad строки 147–153 запускают точечное чтение до подписки `watchTag`. Строки 259–264 при отказе переводят выбор в `TagCatalogSelectionFailure`, а строки 310–330 затем принимают успешное чтение тега и заменяют его на `TagCatalogSelectionReady`, не повторяя точечное чтение. В `lib/src/tag/presentation/catalog/tag_catalog_page.dart` строки 419–425 показывают повтор только при `TagCatalogSelectionFailure`, строки 432–460 не дают повторного выбора внепорочной строки, а строки 506–520 блокируют назначение при неизвестном статусе. Тест `test/tag/presentation/catalog/tag_catalog_view_model_test.dart` строки 439–457 проверяет обратный порядок ответов: успех тега раньше отказа назначения.
- **Evidence revisions:** ["555483c7626fb6be5d04361dff5cc6debc2204ad"]
- **Impact:** После временного отказа точечного чтения и более позднего успешного ответа `watchTag` статус пары остаётся неизвестным, сообщение с повтором исчезает и пользователь не может продолжить назначение выбранного вне порции тега с этого экрана.
- **Required outcome:** Пока статус выбранной пары остаётся неизвестным после отказа, экран должен сохранять доступный способ повторить проверку; успешное чтение самого тега не должно скрывать нерешённый отказ проверки назначения.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]

## Review coverage

Единственный целевой коммит 555483c7626fb6be5d04361dff5cc6debc2204ad и задача 2.30 покрыты U1. `openspec/changes/manage-tags/tasks.md` использован как свидетельство планирования; остальные 12 изменённых путей входят в U1. Проверены результаты для обоих видов получателя, свободной и назначенной пары, отсутствия тега и получателя, отказа чтения, ревизий, выбранного вне порции тега и индексированного запроса. Рабочее дерево до записи отчёта было чистым; проверки выполнялись на записанном head. Прежний отчёт не содержал активных замечаний или принятых рисков.
