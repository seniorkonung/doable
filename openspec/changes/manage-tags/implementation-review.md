# OpenSpec Implementation Review: manage-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Повтор проверки назначения после исчерпания устаревших чтений теряет предусмотренный бюджет попыток. Активно замечание F2; исправление гонки ответа точечного чтения и следующей порции передано в незавершённую задачу 2.32. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 0f82de80f912e47fb3f9483421c23a53a5430855
- **Base commit:** 0f82de80f912e47fb3f9483421c23a53a5430855
- **Reviewed head:** ff8482bacdfc0b206fe824fcb7cda14525123356
- **Target commits:** ["ff8482bacdfc0b206fe824fcb7cda14525123356"]
- **Reviewable paths:** ["lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "openspec/changes/manage-tags/tasks.md", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **OpenSpec change:** manage-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-tags/tasks.md"]

## Reviewed increment

### U1 · Повтор проверки назначения тега вне загруженной порции

- **Work items:** ["2.31"]
- **Requirements and scenarios:** ["Каталог тегов и выбор для назначения", "Отказ проверки назначения выбранного вне порции тега", "Получение данных и безопасные ошибки тегов"]
- **Affected boundary:** Пользователь каталога, состояние выбранной пары TagId и TagTarget, точечное чтение статуса назначения и доступность явной команды назначения.
- **Implementation target:** ["lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Назначение допускается только для подтверждённо свободной пары намерения или долговременной связи; ответы прежнего выбора, получателя, ревизии и эпохи не должны менять текущий статус. Порционный каталог и явная команда назначения сохраняются. Смешанная выдача сущностей по тегу и другие виды получателей не входят в эту работу.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Изолированный рецензент проверил все пять путей реализации и тестов U1 в точном диапазоне; материалы планирования, прежний отчёт и история коммитов ему не передавались. Выявлены ошибки согласования ответов и бюджета повторов; активное замечание — F2. |
| OpenSpec conformance | Complete | Задача 2.31 и сценарий отказа проверки сопоставлены с кодом и тестами обоих видов получателя, обоих порядков ответов и обоих статусов пары. На чистом ff8482bacdfc0b206fe824fcb7cda14525123356 прошли mise exec --no-deps -- openspec validate manage-tags --json (1/1), строгая проверка OpenSpec и два целевых файла flutter test (79 тестов). Оставшийся дефект отражён в F2; исправление гонки ответов принадлежит незавершённой задаче 2.32. |
| Code quality | Complete | Проверены переходы состояния и ревизии во ViewModel, отображение и доступность повтора, тестовые двойники, обработка отказов, границы входных данных и стоимость дополнительных чтений. На записанном head прошли mise exec --no-deps -- flutter analyze и git diff --check; зависимостей и запросов к хранилищу в диапазоне не добавлено. |

## Findings

### F2 · Medium — повтор использует исчерпанный счётчик устаревших чтений

- **Evidence:** lib/src/tag/presentation/catalog/tag_catalog_view_model.dart:233–249 после восьми устаревших ответов устанавливает unavailable, оставляя _assignmentStaleReads равным пределу. retrySelectedAssignment в строках 181–190 запускает новую проверку без сброса счётчика. Поэтому первый устаревший ответ новой попытки сразу вновь приводит к unavailable. Новые тесты test/tag/presentation/catalog/tag_catalog_view_model_test.dart:328–379 покрывают повтор после ошибки хранилища, но не после исчерпания устаревших снимков.
- **Evidence revisions:** ["ff8482bacdfc0b206fe824fcb7cda14525123356"]
- **Impact:** Повторная попытка теряет предусмотренную устойчивость к временному отставанию снимка и может требовать от пользователя многократных ручных повторов вместо автоматического согласования.
- **Required outcome:** Каждая новая попытка проверки пары должна получать полный бюджет обработки устаревших ответов либо равноценный механизм восстановления без открытия действия по устаревшему снимку.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart", "openspec/changes/manage-tags/tasks.md"]

## Review coverage

Единственный целевой коммит ff8482bacdfc0b206fe824fcb7cda14525123356 и задача 2.31 покрыты U1. openspec/changes/manage-tags/tasks.md использован как свидетельство планирования; все пять изменённых путей кода и тестов входят в U1. Проверены свободная и назначенная пара для намерения и долговременной связи, порядок ответов чтения тега и пары, поздние ответы прежнего выбора и получателя, ревизии и эпохи, появление тега в следующей порции, сообщения об отказах и право на повтор. Рабочее дерево до записи отчёта было чистым; проверки выполнялись на записанном head. Исправление гонки ответов передано в незавершённую задачу 2.32; F2 остаётся активным и требует отдельного решения. Принятых остаточных рисков нет.
