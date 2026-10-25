# OpenSpec Implementation Review: add-intention-picker-sorting-and-purpose

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задача 1.11 выполнена. Производный запрос «тот же, но без условия готовности» теперь определяет сам контракт `IntentionCatalogQuery.withAnyReadiness()`. Метод собирает запрос через приватный конструктор, в котором все поля обязательны, поэтому новое поле запроса не скомпилируется, пока его не перенесут. Модель каталога больше не копирует поля вручную, а поведение чисел типов и выдачи не изменилось. Прежняя находка F2 закрыта кодом. Фаза 1 завершена, `mise run check` проходит. Активных находок нет. Остаётся в силе принятый риск AR1: индексы порядка по названию для архивного охвата пока никто не читает.

## Review target

- **Baseline ref:** 53e1bbd1d0ad86124a6bdf342fa8d564d252da5c
- **Base commit:** 53e1bbd1d0ad86124a6bdf342fa8d564d252da5c
- **Reviewed head:** d4fc4f874d8af4cf3c1ca04a4e8afb1ee98610ed
- **Target commits:** ["d4fc4f874d8af4cf3c1ca04a4e8afb1ee98610ed"]
- **Reviewable paths:** ["lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md", "test/intention/application/intention_contract_test.dart"]
- **OpenSpec change:** add-intention-picker-sorting-and-purpose
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-intention-picker-sorting-and-purpose/tasks.md"]

## Reviewed increment

### U1 · Контракт запроса сам определяет запрос «без условия готовности» для чисел типов

- **Work items:** ["1.11"]
- **Requirements and scenarios:** ["intention-management: точное количество совместного поиска (числа типов)", "intention-management: Упорядочивание каталогов намерений (согласование правок)", "design: решение 2 (модель, правки графа)"]
- **Affected boundary:** Контракт запроса каталога `IntentionCatalogQuery` в слое приложения и его потребитель `IntentionCatalogViewModel`: согласование чисел типов при правках графа.
- **Implementation target:** ["lib/src/intention/application/intention_catalog.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "test/intention/application/intention_contract_test.dart"]
- **Applicable constraints and non-goals:** Детали хранения и SQL остаются в модуле графа (ADR-0009). В обычных тестах нет измерений времени. Смысл чисел типов, проверка запроса и видимое поведение каталога не меняются.
- **Excluded change scope:** Фазы 2–4 плана.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Одна единица U1. Ревьюер — свежий изолированный субагент по `implementation-decision-review`. Он получил нейтральный бриф и три пути поставки и тестов; `tasks.md`, планирование, история коммитов и отчёт ему не передавались. Находок нет. Он отметил, что `_DriftIntentionCatalogEntrySnapshot.matches` в адаптере тоже перечисляет условия запроса вручную. Этот файл в диапазоне не менялся, и такое перечисление — собственная реализация принадлежности в адаптере, парная его SQL; к цели задачи 1.11 оно не относится. |
| OpenSpec conformance | Complete | Задача 1.11 сверена с критериями приёмки в `tasks.md`, прежней находкой F2 и решением 2 в design. `openspec validate add-intention-picker-sorting-and-purpose --strict --no-interactive --json` — valid, без замечаний. В рабочей копии на `d4fc4f87` (HEAD совпадает с проверяемой головой, рабочее дерево чистое) выполнена полная проверка фазы `mise run check` — exit 0 (формат: 794 файла, 0 изменённых; `flutter analyze` без замечаний; обычные тесты +3339, процессные тесты +18, все прошли). Сборку APK этот этап не делал: диапазон меняет только код Dart без нативных и сборочных файлов. |
| Code quality | Complete | Применены пять линз `code-review-and-quality`: корректность, читаемость, архитектура, безопасность, производительность. Проверены `withAnyReadiness`, приватный конструктор, `includes`, `_reconcileTypeCounts`, реализация `matches` в адаптере Drift и новый тест контракта. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Индексы порядка по названию для архивного охвата не читает ни один запрос до сортировки каталога графа

- **Evidence:** `lib/src/data/local/schema/intention_schema.drift` на проверяемой голове содержит `intentions_archived_title_search_key_asc_id_asc` и `intentions_archived_title_search_key_desc_id_asc` с условием `is_archived = 1`. Архивный охват выбирает только каталог графа намерений, а он через `_OfferedCatalogOrder` в `intention_catalog_page.dart` предлагает только четыре порядка по времени. Поиски читают активный или полный охват.
- **Evidence revisions:** ["38cd39baf4b7979ab433974a66b2cfa02f96fed4"]
- **Potential impact:** Два неиспользуемых индекса в базовом снимке схемы 6 обновляются каждой записью архивного намерения, архивированием и восстановлением и занимают место в файле. Если каталог графа получит порядок по названию в другой форме, индексы останутся мёртвыми, и убрать их можно будет только миграцией.
- **Acceptance rationale:** Владелец решил заложить основу сразу. Сортировка по названию в каталоге графа, где есть архивный охват, — ближайшее следующее изменение, а базовая схема 6 без миграции — последний случай добавить индексы без пути обновления. Цена записи для масштаба личного графа мала.
- **Scope and assumptions:** Только два индекса `(title_search_key ASC|DESC, id ASC)` с условием архивного охвата в схеме 6. Предполагается, что каталог графа получит порядок по названию через тот же ключ сохранённой проекции по ADR-0045 и с тем же курсором `(ключ, id ASC)`.
- **Reopen when:** Сортировку по названию в каталоге графа отменят или отложат на неопределённый срок; её спроектируют на другом ключе, направлении или форме курсора; схема 6 перестанет быть базовой версией без миграции.
- **Acceptance authority:** Явное решение владельца при разборе F4 ревью планирования 25.10.2026: каталог намерений с сортировкой по названию будет сделан вскоре, и основу под него нужно заложить сразу, пока это можно сделать без миграции.
- **Originating finding:** F4
- **Acceptance lifetime:** Durable
- **Decision record:** `docs/adr/0045-order-titles-by-opaque-key-of-stored-search-projection.md` («Последствия»); решение 3 и «Risks / Trade-offs» в `design.md`.
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

**U1.** `withAnyReadiness()` (`lib/src/intention/application/intention_catalog.dart:189-201`) вызывает приватный `IntentionCatalogQuery._`, где все девять полей обязательны. Метод переносит все поля, кроме условия готовности, которое становится `all`. Фабрику он не вызывает, поэтому значения повторно не проверяются и не нормализуются, но они уже прошли фабрику при создании исходного запроса. `_reconcileTypeCounts` (`lib/src/intention/presentation/catalog/intention_catalog_view_model.dart:894-921`) использует производный запрос только для `snapshot.matches`. Адаптер в `matches` читает охват, готовность, исключённого участника, теги и название, а курсор, размер порции и `requestsTypeCounts` не читает. Значит, перенос курсора и `requestsTypeCounts`, которые прежняя копия сбрасывала, на принадлежность не влияет, и поведение чисел типов не изменилось. Новый тест контракта (`test/intention/application/intention_contract_test.dart:366-469`) проверяет, что производный запрос включает обе готовности и исключает намерение, которое не проходит охват, название, обязательный или исключённый тег либо исключение участника. Это закрывает третий критерий приёмки задачи 1.11. Отметка `[x]` у 1.11 в `tasks.md` подтверждается кодом, тестом и проверками этого этапа.

Ручные проверки на устройстве остаются за пользователем и не выполнялись: перенос данных экспортом, очисткой и импортом; каталог и три поиска выглядят и работают как прежде.
