# OpenSpec Implementation Review: redesign-intention-catalog

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 4.15–4.17 выполнены по своим критериям, поведение приложения не изменилось, а прокрутка и название теста исправлены верно. Осталась одна находка F1 низкой важности: проверки условий по тегам всё ещё сравнивают порядок условий, хотя он вышел из контракта.

## Review target

- **Baseline ref:** 445a1e0cf2361ad7b6632472809fb554b6c5c3b2
- **Base commit:** 445a1e0cf2361ad7b6632472809fb554b6c5c3b2
- **Reviewed head:** 1e2ea1bd210644e03bbbf7cfe3ace9c30ebeacd4
- **Target commits:** ["9b8a0ee953d252216378763b3be5bc9d3a5d8dcb", "f53428a5788c19e6bcbad6f82e68cc75cfe95ee2", "faf2ef5c7de5968c3fe000834b2c5334d001f156", "1e2ea1bd210644e03bbbf7cfe3ace9c30ebeacd4"]
- **Reviewable paths:** ["lib/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart", "openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md", "test/app/tag_app_flow_test.dart", "test/intention/presentation/catalog/intention_catalog_page_test.dart", "test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart"]
- **OpenSpec change:** redesign-intention-catalog
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-catalog/task-profiles.md", "openspec/changes/redesign-intention-catalog/tasks.md"]

## Reviewed increment

### U1 · Модель условий по тегам не обещает порядка условий

- **Work items:** ["4.15"]
- **Requirements and scenarios:** ["intention-management: Условия по тегам в панели тегов", "intention-management: Нажатия переключают надобность по кругу", "tag-management: порядок добавления условий уходит из контракта (proposal)"]
- **Affected boundary:** Разработчики, которые читают и меняют модель условий, и автоматические проверки этой модели. Пользователь изменений не видит.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart", "test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart"]
- **Applicable constraints and non-goals:** Поведение приложения не меняется. Новое поведение, панель тегов и страница каталога в задачу не входят.

### U2 · Название теста сброса фильтров называет только проверенное

- **Work items:** ["4.16"]
- **Requirements and scenarios:** ["intention-management: Пустая выдача поиска намерений", "intention-management: «Сбросить фильтры» снимает название и условия"]
- **Affected boundary:** Разработчики, которые судят о покрытии по названиям тестов.
- **Implementation target:** ["test/intention/presentation/catalog/intention_catalog_page_test.dart"]
- **Applicable constraints and non-goals:** Код приложения, спецификации, шаги и проверки теста не меняются.

### U3 · Сценарий общего переименования тега без устаревшего шага прокрутки

- **Work items:** ["4.17"]
- **Requirements and scenarios:** ["intention-management: Страница каталога намерений", "intention-management: Кнопка фильтра по тегам в поиске намерений"]
- **Affected boundary:** Разработчики, которые читают сценарий, и автоматическая проверка потока переименования.
- **Implementation target:** ["test/app/tag_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Код приложения не меняется, новых проверок в сценарии нет, а общий шаг `jumpIntentionCatalog` остаётся для других тестов.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Для каждого из трёх непересекающихся по путям блоков работал отдельный новый ревьюер с нейтральным описанием цели, полными идентификаторами коммитов и только своими путями. Покрытие всех трёх полное. U2 и U3 без замечаний, по U1 замечание низкой важности: оно проверено и стало F1. |
| OpenSpec conformance | Complete | Все проверки шли в рабочем дереве на голове 1e2ea1bd210644e03bbbf7cfe3ace9c30ebeacd4, код не менялся. Целевые тесты трёх затронутых файлов прошли (49 тестов). `mise run check` — код 0: формат без изменений в 857 файлах, `flutter analyze` без замечаний, 3859 обычных тестов и 18 тестов процессов. Обычных тестов на один меньше, чем в прошлом обзоре, потому что 4.15 удалила один случай. `mise exec --no-deps -- openspec validate redesign-intention-catalog --strict --json` — valid. Устройство и эмулятор не использовались. |
| Code quality | Complete | Навык `code-review-and-quality` применён ко всем четырём путям доставки на голове. Изменён один файл `lib/` и только в комментариях. Прочитаны потребители `conditions`: `intention_search_bar.dart:47` и `tags_panel_view_model.dart:378,400`. Новых входов, данных, зависимостей и внешних вызовов нет, производительность не затронута. |

## Findings

### F1 · Low — Проверки условий по тегам всё ещё сравнивают порядок условий

- **Evidence:** `test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart:101-106` сравнивает опубликованные снимки упорядоченным списком, где второй снимок равен `[(_id(1), _present), (_id(2), _present)]`. `test/intention/presentation/intention_tag_search_accessibility_test.dart:134-143` так же сравнивает `conditions` с упорядоченным списком из семи условий. Модель сохраняет порядок только потому, что `_snapshot` обходит словарь `_requirements` (`intention_tag_conditions_view_model.dart:193-197`). Потребители порядок не читают: кнопка берёт `length`, а панель собирает словарь по `tagId`. `proposal.md:83` выводит порядок добавления условий из контракта, delta-спецификации его не упоминают, а задача 4.15 называется «Убрать порядок условий по тегам из документации их модели и из её проверок». Её критерии назвали только удалённый случай и случай подтверждённого удаления.
- **Evidence revisions:** ["1e2ea1bd210644e03bbbf7cfe3ace9c30ebeacd4"]
- **Impact:** Смена хранения условий, незаметная пользователю, уронит оба теста. Читатель снова примет случайный порядок за контракт, то есть цель 4.15 достигнута только в части проверок.
- **Required outcome:** Ни одна проверка состояния с двумя и более условиями не зависит от их относительного порядка. Поведение приложения не меняется.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart", "test/intention/presentation/intention_tag_search_accessibility_test.dart"]

## Review coverage

Проверены все 4 коммита и все 6 путей диапазона: 2 планирующих пути и 4 пути в блоках U1–U3. Каждая задача 4.15–4.17 привязана к блоку, кода без задачи нет. Коммит 9b8a0ee953d252216378763b3be5bc9d3a5d8dcb меняет только `task-profiles.md`. Планирующие файлы читались на голове, рабочее дерево было чистым, а HEAD совпадал с проверяемой головой. Прежний отчёт активных находок и принятых рисков не содержал.

**Соответствие 4.15.** Из документации `IntentionTagConditionsState`, `tagFilter` и `cycle` упоминания порядка убраны, изменены только комментарии. Случая о месте условия больше нет, а случай подтверждённого удаления сравнивает условия через `unorderedEquals` и не говорит о местах. Удалённый тест других регрессий не ловил: цикл и фильтр проверяет первый случай файла. Требование основной спецификации с «местом условия» снимается разделом REMOVED delta-спецификации, а раздел «Условия по тегам в панели тегов» в delta о порядке молчит. Остаток — находка F1.

**Соответствие 4.16.** Название совпадает с критерием дословно, шаги и проверки не менялись. Спецификация требует сохранять при сбросе охват и порядок, но сценарий этого не называет, и задача 4.16 намеренно не расширяет тест. Сброс очищает только название и условия (`intention_catalog_page.dart:49-57`), а сохранение порядка при очистке названия проверяет `intention_catalog_view_model_test.dart:653-659`. Новой находкой это не стало.

**Соответствие 4.17.** Комментарий, `jumpIntentionCatalog(tester, 0)` и `pump` удалены, остальные шаги целы. `shownIntentionCatalogParameters` читает `FilterButton` и заголовок из дерева виджетов, а поиск закреплён над списком, поэтому прокрутка на проверку не влияла. Шаг `jumpIntentionCatalog` по-прежнему используют пять мест в других тестах.

**Журнал коммитов.** Темы f53428a5788c19e6bcbad6f82e68cc75cfe95ee2, faf2ef5c7de5968c3fe000834b2c5334d001f156 и 1e2ea1bd210644e03bbbf7cfe3ace9c30ebeacd4 написаны по-русски, а первая и третья длиннее 72 символов, что расходится с `.claude/rules/commit-message-conventions.md`. На поставку это не влияет, а исправление требует переписать историю, которая в этом процессе запрещена, поэтому это раскрыто здесь, а не оформлено находкой.

Устройство и эмулятор не использовались. Отчёт не даёт разрешения на публикацию или архивацию.
