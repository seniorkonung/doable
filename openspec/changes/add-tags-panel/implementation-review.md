# OpenSpec Implementation Review: add-tags-panel

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 2.17–2.23 выполнены по существу. Отметка созданного тега теперь принадлежит открытию панели. Диктор объявляет отметку строки один раз — состоянием отметки. Недостижимые отказы чтения убраны из модели панели. Вариант листа связан с функцией показа типом. Новые проверки листа «Новый тег», прежнего каталога и модуля основ ловят заявленные регрессии. Полная проверка фазы на проверяемой голове всё же не проходит. Задача 2.19 убрала слова отметки из доступного названия строки, а сквозная проверка `test/app/tag_app_flow_test.dart` по-прежнему ищет строку по названию «Работа, отмечен» (F1). Пока F1 не устранено, фаза 2 не готова к завершению. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** a23257b331cb017014f20cbe132e6504f0fd9ae1
- **Base commit:** a23257b331cb017014f20cbe132e6504f0fd9ae1
- **Reviewed head:** d3e9f32eb2bf61df4e6296518202ae4025965dd8
- **Target commits:** ["bf30523e3fa4584b7c3bc2bf042d3e85c3093646","ef372b90be6ad1e3040733f8e9fdf7885452739f","fef5be7eddd89ce7e57b4b3a3e094662dfcf9563","bc2bb1b2c61c57a56994adadeae11bdf22866c44","2d28d322c21f1ca04b75c44e6be8796c2cd71663","b1b8ec78e4b0bbbe2629e957cd7ab01611fb3ad3","d3e9f32eb2bf61df4e6296518202ae4025965dd8"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart","lib/src/app/quick_creation/quick_creation_mode_menu.dart","lib/src/data_transfer/presentation/backups_sheet.dart","lib/src/data_transfer/presentation/export_data_sheet.dart","lib/src/design_system/components/action_sheet.dart","lib/src/design_system/components/sheet.dart","lib/src/design_system/components/tag_row.dart","lib/src/graph/presentation/graph_operation_presenter.dart","lib/src/tag/presentation/editor/tag_sheet.dart","lib/src/tag/presentation/panel/tags_panel.dart","lib/src/tag/presentation/panel/tags_panel_context.dart","lib/src/tag/presentation/panel/tags_panel_state.dart","lib/src/tag/presentation/panel/tags_panel_view_model.dart","lib/src/tag/presentation/panel/tags_panel_view_model.g.dart","openspec/changes/add-tags-panel/tasks.md","test/design_system/sheet_test.dart","test/design_system/tag_row_test.dart","test/graph/presentation/graph_operation_presenter_test.dart","test/tag/presentation/catalog/tag_catalog_page_test.dart","test/tag/presentation/editor/tag_sheet_test.dart","test/tag/presentation/panel/tags_panel_test.dart","test/tag/presentation/panel/tags_panel_view_model_test.dart","test/tag/presentation/tag_accessibility_test.dart"]
- **OpenSpec change:** add-tags-panel
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-tags-panel/tasks.md"]

## Reviewed increment

### U1 · Отметка созданного тега принадлежит открытию панели

- **Work items:** ["2.18"]
- **Requirements and scenarios:** ["tag-management: Создание тега из панели", "tag-management: Закрытие панели до подтверждения создания", "tag-management: Закрытие листа до подтверждения создания", "tag-management: Выбор тегов намерения в панели", "design: решение 5", "ADR-0040"]
- **Affected boundary:** Человек, создающий тег в листе поверх панели со страницы намерения; координатор команд графа и хранилище
- **Implementation target:** ["lib/src/tag/presentation/panel/tags_panel_context.dart","lib/src/tag/presentation/panel/tags_panel_view_model.dart","lib/src/tag/presentation/panel/tags_panel.dart","test/tag/presentation/panel/tags_panel_test.dart"]
- **Applicable constraints and non-goals:** Принятое создание завершается независимо от закрытия листа и панели. Изменения назначений одного намерения идут последовательно, без очереди. Контексты черновика и фильтра — фаза 4.

### U2 · Отметка строки тега объявляется диктору один раз

- **Work items:** ["2.19"]
- **Requirements and scenarios:** ["tag-management: Локализация и доступность управления тегами", "tag-management: Отметка тега объявляется один раз", "design: решение 10", "ADR-0030"]
- **Affected boundary:** Пользователи экранного диктора в панели тегов; строка тега модуля основ
- **Implementation target:** ["lib/src/design_system/components/tag_row.dart","lib/src/tag/presentation/panel/tags_panel.dart","lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/tag/presentation/panel/tags_panel_view_model.g.dart","test/design_system/tag_row_test.dart","test/tag/presentation/panel/tags_panel_test.dart","test/tag/presentation/tag_accessibility_test.dart"]
- **Applicable constraints and non-goals:** Компоненты модуля основ получают готовые тексты и подписи. Нажатие, его недоступность, вид строки и отсутствие отдельного элемента навигации у точки не меняются. В коммите задачи у `tags_panel_view_model.g.dart` изменился только хеш генерации.
- **Excluded change scope:** Подпись удержания и отметки режима фильтра появятся в фазах 3 и 4.

### U3 · Модель панели обрабатывает только достижимые отказы чтения

- **Work items:** ["2.20"]
- **Requirements and scenarios:** ["tag-management: Получение каталога тегов и безопасные ошибки", "tag-management: Неизвестный отказ получения каталога", "tag-management: Согласование панели тегов с подтверждёнными изменениями", "tag-management: Запоздалое чтение после изменения тега", "tag-management: Фоновое обновление сохраняет список"]
- **Affected boundary:** Панель тегов и контракт чтения каталога `TagReadContract.getTagCatalog`
- **Implementation target:** ["lib/src/tag/presentation/panel/tags_panel_state.dart","lib/src/tag/presentation/panel/tags_panel_view_model.dart","lib/src/tag/presentation/panel/tags_panel_view_model.g.dart","lib/src/tag/presentation/panel/tags_panel.dart","test/tag/presentation/panel/tags_panel_view_model_test.dart"]
- **Applicable constraints and non-goals:** Видимое поведение панели не меняется: те же сообщения, повтор только для доказанно устранимой недоступности, отсутствие намерения — отдельное состояние. Прежний каталог со своим перехватом исключений остаётся до фазы 4.

### U4 · Проверки конфликта при записи и причины недопустимого названия

- **Work items:** ["2.17", "2.21"]
- **Requirements and scenarios:** ["tag-management: Уникальность названия тега", "tag-management: Допустимое название тега", "tag-management: Согласование панели тегов с подтверждёнными изменениями"]
- **Affected boundary:** Форма прежней страницы каталога и общая поверхность; лист «Новый тег» и репозиторий тегов
- **Implementation target:** ["test/tag/presentation/catalog/tag_catalog_page_test.dart","test/tag/presentation/editor/tag_sheet_test.dart"]
- **Applicable constraints and non-goals:** Только проверки, поведение приложения не меняется. Обычные тесты обходятся без замеров времени и расширенных тайм-аутов.

### U5 · Вариант листа связан с функцией показа; отменённое касание и рост содержимого проверены

- **Work items:** ["2.22", "2.23"]
- **Requirements and scenarios:** ["tag-management: Панель тегов", "tag-management: Согласование панели тегов с подтверждёнными изменениями", "design: решения 7 и 9", "ADR-0041", "ADR-0042", "ADR-0032"]
- **Affected boundary:** Модуль основ и все места показа листов: панель тегов, лист «Новый тег», экспорт, резервные копии, меню режима быстрого создания и лист начала дневного выбора; общая поверхность результатов операций
- **Implementation target:** ["lib/src/design_system/components/sheet.dart","lib/src/design_system/components/action_sheet.dart","lib/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart","lib/src/app/quick_creation/quick_creation_mode_menu.dart","lib/src/data_transfer/presentation/backups_sheet.dart","lib/src/data_transfer/presentation/export_data_sheet.dart","lib/src/tag/presentation/editor/tag_sheet.dart","lib/src/tag/presentation/panel/tags_panel.dart","lib/src/graph/presentation/graph_operation_presenter.dart","test/design_system/sheet_test.dart","test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Лист показывается над корневым навигатором, учитывает клавиатуру, возвращает результат типа `T` и может размещать сообщения общей поверхности. Затемнение, «назад» и семантика маршрута остаются за Material. Вид, жесты, закрытие и размещение сообщений у мест показа не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих изолированных ревьюера по `implementation-decision-review` получили нейтральные брифы без артефактов планирования, истории коммитов и прежнего отчёта. Первый получил общий бриф U1, U2, U3 и U5 и все 25 их путей: эти единицы делят `tags_panel.dart`. Второй проверил 2 пути U4. Наборы путей не пересекаются. Оба сообщили о полном покрытии своих путей. Первый ревьюер один раз вывел каталогом `test/tag` diff двух путей U4, но не опирался на них. Второй не читал изменённые `tag_sheet.dart` и презентер. Оба файла входят в цель первого ревьюера, а допущение об активном приложении оркестратор подтвердил по `graph_operation_presenter.dart:118-131`. |
| OpenSpec conformance | Complete | Проверки шли в этой рабочей копии: она чистая, HEAD = d3e9f32eb2bf61df4e6296518202ae4025965dd8. `mise run check`: код 1. `dart format` и `flutter analyze` прошли без замечаний. Из обычных тестов 3479 прошли, 1 упал — `test/app/tag_app_flow_test.dart`, «серия назначений и снятий сохраняется без сообщений об успехе» (F1). Отдельный прогон этой проверки снова падает. `mise run check:process-tests` отдельно: код 0, 18 прошли. `mise run codegen-check`: код 0. `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive --json`: valid. Критерии задач 2.17–2.23 сопоставлены с кодом и тестами диапазона. В `tasks.md` диапазон только отметил задачи выполненными. Сборка APK и проверки на устройстве не выполнялись. |
| Code quality | Complete | Оркестратор применил линзы `code-review-and-quality` ко всем путям поставки на проверяемой голове. Проверены закрытие открытия через `PopScope` для «Готово», свайпа шапки, затемнения и «назад», а также путь удаления маршрута, где отметку не даёт `ref.mounted`. Сверены контракт `getTagCatalog` с перехватом всех исключений, сериализация чтений и ревизий без `_precedesShown`, исчерпывающий разбор `TagsPanelReadFailure` и семантика `TagRow`. Просмотрены также закрытые возможности листа, все шесть мест показа, отсутствие ссылок на `DoableSheetSize` и удалённые строки локализации. Наконец, проверены потребители в `test/` и необходимость новых проверок. |

## Findings

### F1 · High — Сквозная проверка назначения ищет строку по прежнему доступному названию, и полная проверка фазы падает

- **Evidence:** Коммит `fef5be7e` (задача 2.19) сделал доступным названием строки панели только название тега. Он удалил `tagsPanelRowMarked` и `tagsPanelRowUnmarked`: в `lib/src/tag/presentation/panel/tags_panel.dart:261` теперь `label: name`. Проверка `test/app/tag_app_flow_test.dart:185` в диапазоне не менялась. Она по-прежнему ждёт `find.bySemanticsLabel('Работа, отмечен')` — строку, которую код больше не формирует. Литерал не связан с ключом локализации, поэтому `flutter analyze` удаление не заметил. Проверка задачи 2.19 запускала `tag_row_test`, `tags_panel_test` и `tag_accessibility_test`, но не этот потребитель. В `mise run check` на d3e9f32e падает ровно эта проверка: «Не появился элемент: Found 0 widgets with a semantics label named "Работа, отмечен"». Отдельный запуск `flutter test test/app/tag_app_flow_test.dart --plain-name "серия назначений и снятий"` падает так же.
- **Evidence revisions:** ["d3e9f32eb2bf61df4e6296518202ae4025965dd8"]
- **Impact:** Полная проверка проекта, обязательная для завершения фазы 2, на проверяемой голове не проходит. Сквозной сценарий серии назначений и снятий со страницы намерения обрывается на первом назначении. Поэтому после этого шага приложение не проверяет ни отсутствие сообщений об успехе, ни сохранённые назначения, ни их согласованность после повторного открытия.
- **Required outcome:** Сквозная проверка серии назначений и снятий дожидается подтверждённой отметки строки по текущей семантике: название тега и отмеченное состояние. Она снова проходит целиком, а `mise run check` на голове с исправлением завершается успешно.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/app/tag_app_flow_test.dart", "tasks.md: 2.19 — проверка не включала затронутого потребителя"]

## Review coverage

Просмотрены все 7 целевых коммитов. Задача 2.18 сопоставлена с U1, 2.19 — с U2, 2.20 — с U3, 2.17 и 2.21 — с U4, 2.22 и 2.23 — с U5. `tasks.md` служит свидетельством планирования с отметками выполнения. Несопоставленных путей нет. Кода фаз 3–4 в диапазоне нет.

Подтверждено следующее. В U1 `PopScope.onPopInvokedWithResult` закрывает открытие при любом `Navigator.pop` маршрута панели ещё до закрывающей анимации. Закрытие листа «Новый тег» закрывает другой маршрут и открытие не трогает. Новая проверка падала бы на прежнем коде: модель во время анимации жива, а строка создания видна. В U2 строка отдаёт название, а отметку передаёт одно состояние `checked`. Ни `lib`, ни `test` больше не ссылаются на удалённые ключи, но строковый литерал в сквозной проверке остался (F1). В U3 `_readTagCatalog` перехватывает любое исключение и возвращает `TagCatalogError`. Показанная ревизия не опережает требуемую, потому что применённый пакет поднимает обе. Чтения сериализованы, поэтому без `_precedesShown` запоздалое чтение по-прежнему отсекается. В U4 конфликт действительно обнаруживается при записи, ожидание идёт по появлению сообщения, а не по времени, а 256 графемных кластеров — минимальный выход за предел. В U5 закрытые конструкторы возможностей не дают построить вариант листа без своей функции показа, а обе функции различаются только `enableDrag`. Проверки отменённого касания и роста содержимого падали бы при нарушении.

Часть кандидатов отклонена. Замечание «отдельный `label` у `TagRow` позволяет вызывающему снова продублировать отметку» не принято. Отдельное доступное название требуется самим изменением: по требованию «Локализация и доступность управления тегами» оно сообщает о действиях по удержанию (фаза 3) и о надобностях режима фильтра (фаза 4). Двойное объявление в текущем коде недостижимо, а `tags_panel_test` и `tag_accessibility_test` закрепляют название без слов отметки. Возможность листа из объемлющего построителя можно передать во вложенную функцию показа, и несогласованная пара скомпилируется. Это тоже не принято замечанием: в текущем коде такого пути нет, а Dart не умеет ограничить значение областью замыкания без несоразмерной сложности. Критерий 2.23 — нельзя получить возможность вне функции показа — выполнен закрытыми конструкторами.

Nit, не замечание: в описании `GraphOperationPresenter` (`graph_operation_presenter.dart:31`) после правки 2.23 осталась одна не перенесённая строка комментария длиннее соседних.

Исправлений кода и артефактов в этой стадии не было: навык проверки реализации запрещает править код, поэтому F1 передаётся последующим стадиям устранения замечаний. Сборка APK и проверки на устройстве не выполнялись. Ручные проверки остаются за пользователем: объявление отметки строки TalkBack один раз, закрытие панели свайпом шапки во время создания тега, отменённое системой касание шапки и вид всех листов после перехода на новые функции показа.
