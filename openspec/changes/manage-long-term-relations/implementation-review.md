# OpenSpec Implementation Review: manage-long-term-relations

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задача 5.22 подключила открытый редактор к подтверждённым снимкам исходной связи и сохранила черновик. Снимок связи всё ещё может вытеснить более свежий снимок каталога для того же ID; этот дефект требует исправления. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 674c6f63b889c4e59e9cb7f8c7c94ca39c14cfa1
- **Base commit:** 674c6f63b889c4e59e9cb7f8c7c94ca39c14cfa1
- **Reviewed head:** 76c9f2ab0f52851af9b369caadad7373a06ad5cf
- **Target commits:** ["76c9f2ab0f52851af9b369caadad7373a06ad5cf"]
- **Reviewable paths:** ["lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","openspec/changes/manage-long-term-relations/tasks.md","test/long_term_relation/presentation/editor/relation_editor_page_test.dart"]
- **OpenSpec change:** manage-long-term-relations
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-long-term-relations/tasks.md"]

## Reviewed increment

### U1 · Обновление участников открытой формы изменения связи

- **Work items:** ["85 / 5.22 / 76c9f2ab0f52851af9b369caadad7373a06ad5cf"]
- **Requirements and scenarios:** ["long-term-relation-management / Requirement: Базовая навигация и выбор участников","long-term-relation-management / Requirement: Изменение долговременной связи","long-term-relation-management / Requirement: Локализация и формулировки связей","long-term-relation-management / Requirement: Доступность управления связями","tasks.md / 5.22 / подтверждённые снимки открытой формы"]
- **Affected boundary:** Пользователь, открытая форма изменения связи, наблюдение подробных данных связи и выбранные намерения.
- **Implementation target:** ["lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","test/long_term_relation/presentation/editor/relation_editor_page_test.dart"]
- **Applicable constraints and non-goals:** Идентификаторы выбранных намерений, введённые поля, исходная основа частичной правки и актуальная ошибка сохраняются при обновлении отображения. Формулировка использует буквальные названия и локализованные системные слова; архивное состояние доступно без опоры на цвет. Массовые операции и изменение хранилища не входят в этот инкремент.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный reviewer проверил оба delivery/test пути U1 по точному `674c6f63b889c4e59e9cb7f8c7c94ca39c14cfa1..76c9f2ab0f52851af9b369caadad7373a06ad5cf`; изучил неизменённые зависимости только как контекст и сообщил оба дефекта. |
| OpenSpec conformance | Complete | На recorded head сопоставлены задача 5.22, delta spec, проектные ограничения, diff страницы и widget-теста. `mise exec --no-deps -- openspec validate manage-long-term-relations --json` вернул `valid: true`; `mise exec --no-deps -- flutter test test/long_term_relation/presentation/editor test/long_term_relation/presentation/details` завершился с 86 успешными тестами. Проверки выполнены в чистом рабочем дереве на указанном head; оставшийся активный дефект отражён в F2. |
| Code quality | Complete | Для обоих delivery/test путей проверены корректность и гонки снимков, читаемость, границы компонентов, безопасность отображаемого текста и стоимость подписки. Dart MCP `analyze_files` для двух изменённых Dart-файлов вернул `No errors`; `git diff --check` точного диапазона прошёл. DTD не обнаружил работающего приложения; требуемые CLI-проверки выполнены. |

## Findings

### F2 · Medium — старый снимок связи может перезаписать новый снимок каталога

- **Evidence:** `lib/src/long_term_relation/presentation/editor/relation_editor_page.dart:247-270` допускает повторный выбор того же ID и переносит снимок из каталога без ревизии; `:57-63` затем передаёт свежий для своего наблюдения снимок связи без сравнения с версией уже выбранного намерения. `lib/src/long_term_relation/presentation/details/relation_details_view_model.dart:342-349` сравнивает ревизии только внутри наблюдения связи. Добавленный тест `test/long_term_relation/presentation/editor/relation_editor_page_test.dart:773-795` проверяет порядок снимков связи, но не порядок между каталогом и связью.
- **Evidence revisions:** ["76c9f2ab0f52851af9b369caadad7373a06ad5cf"]
- **Impact:** После повторного выбора переименованного намерения на более новой ревизии задержанный снимок связи со старым названием может вернуть в форме и формулировке устаревшие данные того же ID.
- **Required outcome:** При объединении подтверждённых снимков разных источников более старая версия не вытесняет более новую для текущего выбранного намерения.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["tasks.md / 5.22","lib/src/long_term_relation/presentation/editor/relation_editor_page.dart","test/long_term_relation/presentation/editor/relation_editor_page_test.dart"]

## Review coverage

Точный диапазон содержит один целевой коммит задачи 85 / 5.22 и три reviewable paths: `tasks.md` служит planning evidence, оба Dart-пути входят в U1; неотнесённых путей нет. Изменённая подписка получает новые данные прежних участников через `RelationDetailsFresh`, отображает название и архивное состояние и не вызывает повторную команду; тест проверяет это вместе с сохранением описания и ошибки пары. Проверены контекст формы и построение частичной правки, фильтр ревизий подробного просмотра, выбор из каталога и поведение после замены участника. Проверки OpenSpec, 86 widget/модельных тестов, анализ файлов и `git diff --check` прошли на head. Рабочее дерево до записи отчёта было чистым; работающего приложения для DTD нет. После рассмотренного head создана незавершённая задача 5.23 для оставшейся работы по выбранному на замену участнику; реализация этой задачи не входила в диапазон. Активное F2 относится к рассмотренному диапазону; принятых рисков и неразрешённых продуктовых решений нет.
