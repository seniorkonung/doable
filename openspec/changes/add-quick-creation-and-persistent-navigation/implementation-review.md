# OpenSpec Implementation Review: add-quick-creation-and-persistent-navigation

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Неразрешённых замечаний не осталось. Защита последующих страниц и их ввода от позднего удаления закреплена в спецификации навигации, решении 4 дизайна и новых задачах Phase 1: 1.12–1.14. Это передача корректирующей работы в планирование по явному решению пользователя, а не проверенное исправление кода; готовность Phase 1 требует выполнения этих задач. Сохранены диапазон ревью, полное покрытие проходов и сопоставление всех 11 целевых коммитов.

## Review target

- **Baseline ref:** 7cfab9ff744f248e7fd377bde7436bc40fa482f2
- **Base commit:** 7cfab9ff744f248e7fd377bde7436bc40fa482f2
- **Reviewed head:** 6bd572d41ff519b82e14bc04a51c94379bd48265
- **Target commits:** ["94f96be2795f1bb1e4dd72873f6ff7b0b64021d8", "069f7a6329766f611c01589d95cd05ec88ef9002", "c239969f04755c0378be5e99ee1cb73af8e713b2", "e57c3c69b2704e9a9933fa38692bcc3db7aa3197", "ed28b74ba9207cfa50c6b990d04bc9dd8a691626", "c912b1fc6c24d2e24e590f04f543282f08aeb8c0", "2319e0f75a10707b361f2920c9ce66edb3d47b9b", "5a6638c6fd06dc6e017731e51f7046dfc9167ca7", "1e3f1e0c25b54e9eace01c7db6f6ac0495126d50", "a7d7116cb96827b5861d96cf898d5487bc1eebd7", "6bd572d41ff519b82e14bc04a51c94379bd48265"]
- **Reviewable paths:** ["docs/verification/persistent-navigation-1.10.md", "docs/verification/persistent-navigation-phase-one-readiness.md", "lib/src/app/navigation/app_destination.dart", "lib/src/app/navigation/app_navigation.dart", "lib/src/app/navigation/app_shell_page.dart", "lib/src/app/navigation/ordinary_page_scaffold.dart", "lib/src/app/routing/app_router.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/details/daily_choice_details_page.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/details/relation_details_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_view.dart", "lib/src/tag/presentation/navigation/tag_navigation_page.dart", "openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md", "test/app/full_intention_creation_checkpoint_test.dart", "test/app/home_favorites_app_flow_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/intention_creation_sheet_tags_test.dart", "test/app/navigation/app_navigation_accessibility_test.dart", "test/app/navigation/app_navigation_transition_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/navigation/app_start_page_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/navigation/ordinary_page_scaffold_test.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_primary_navigation_app_scenarios.dart", "test/daily_choice/presentation/details/daily_choice_details_page_test.dart", "test/intention/presentation/catalog/tag_condition_picker_page_test.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/favorite_mark_accessibility_test.dart", "test/long_term_relation/presentation/details/relation_details_navigation_test.dart", "test/long_term_relation/presentation/details/relation_details_widget_test.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/support/ordinary_page_test_app.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_navigation_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_scaffold_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/catalog/tag_catalog_search_read_cost_widget_test.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_primary_navigation_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_semantics_scenarios.dart", "widgetbook/lib/navigation/app_navigation_bar_use_cases.dart", "widgetbook/test/widgetbook_app_test.dart"]
- **OpenSpec change:** add-quick-creation-and-persistent-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["docs/verification/persistent-navigation-1.10.md", "docs/verification/persistent-navigation-phase-one-readiness.md", "openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md"]

## Reviewed increment

### U1 · Основная навигация сохраняется на обычных страницах

- **Work items:** ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8", "1.9", "1.10", "1.11"]
- **Requirements and scenarios:** ["Панель на обычных страницах", "Сброс истории выбором пункта", "Панель и содержимое обычных страниц", "Сохранённое состояние корневых страниц", "Обычное действие назад", "Защищённая модальная сессия создания намерения", "Независимость принятой операции и предъявления результата от сброса", "Локализованная семантика и переходы панели"]
- **Affected boundary:** Человек переключается между Главной, каталогом намерений и каталогом дневных выборов из обычной страницы над оболочкой; корневой маршрутизатор взаимодействует с сохранёнными вкладками, задачами, координатором команд и общей поверхностью сообщений.
- **Implementation target:** ["lib/src/app/navigation/app_destination.dart", "lib/src/app/navigation/app_navigation.dart", "lib/src/app/navigation/app_shell_page.dart", "lib/src/app/navigation/ordinary_page_scaffold.dart", "lib/src/app/routing/app_router.dart", "lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart", "lib/src/daily_choice/presentation/details/daily_choice_details_page.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/details/relation_details_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_view.dart", "lib/src/tag/presentation/navigation/tag_navigation_page.dart", "test/app/full_intention_creation_checkpoint_test.dart", "test/app/home_favorites_app_flow_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_integration_test.dart", "test/app/intention_creation_sheet_tags_test.dart", "test/app/navigation/app_navigation_accessibility_test.dart", "test/app/navigation/app_navigation_transition_test.dart", "test/app/navigation/app_shell_back_test.dart", "test/app/navigation/app_shell_layout_test.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/app_shell_state_test.dart", "test/app/navigation/app_shell_test.dart", "test/app/navigation/app_shell_unnamed_page_scenarios.dart", "test/app/navigation/app_start_page_test.dart", "test/app/navigation/ordinary_page_layout_scenarios.dart", "test/app/navigation/ordinary_page_scaffold_test.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_primary_navigation_app_scenarios.dart", "test/daily_choice/presentation/details/daily_choice_details_page_test.dart", "test/intention/presentation/catalog/tag_condition_picker_page_test.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/favorite_mark_accessibility_test.dart", "test/long_term_relation/presentation/details/relation_details_navigation_test.dart", "test/long_term_relation/presentation/details/relation_details_widget_test.dart", "test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart", "test/support/ordinary_page_test_app.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_navigation_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_scaffold_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/catalog/tag_catalog_search_read_cost_widget_test.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_primary_navigation_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_semantics_scenarios.dart"]
- **Applicable constraints and non-goals:** Повторный выбор текущего пункта тоже сбрасывает историю; Back закрывает одну верхнюю страницу. Корни сохраняют фильтры, порции и прокрутку. Принятая команда завершается один раз независимо от жизни страницы. Задачи и защищённая модальная сессия не дают доступ к основной панели. Сохраняются локали ru/en, английский fallback, доступность, безопасные отступы и работа с клавиатурой.
- **Excluded change scope:** Phase 2 — новые входы и завершение создания; Phase 3 — быстрое создание, режимы, меню, новое хранение режима и удаление прежних кнопок каталогов. Пакетов задач для этих фаз нет; их реализация и завершение всего изменения не оценивались как обязательства Phase 1.

### U2 · Галерея показывает выбранные состояния постоянной панели

- **Work items:** ["1.10", "1.11"]
- **Requirements and scenarios:** ["Примеры каждого выбранного пункта", "Русский и английский интерфейс", "Доступная раскладка при системном масштабе текста 2.5"]
- **Affected boundary:** Разработчик или дизайнер просматривает изолированные примеры панели и обычной страницы в Widgetbook.
- **Implementation target:** ["widgetbook/lib/navigation/app_navigation_bar_use_cases.dart", "widgetbook/test/widgetbook_app_test.dart"]
- **Applicable constraints and non-goals:** Три выбранных состояния, согласованные шапка, содержимое и панель, локализация и доступная раскладка. Примеры не требуют хранилища графа или маршрутизатора приложения.
- **Excluded change scope:** Примеры режимов быстрого создания из Phase 3.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два ревьюера с пустой историей получили нейтральное описание намерения и точный сохранённый диапазон. Первый полностью прочитал head и изменения относительно base всех 51 пути U1; второй — оба снимка и diff двух путей U2. Артефакты планирования, прежний отчёт и история решений им не передавались. |
| OpenSpec conformance | Complete | Сопоставлены proposal, пять delta specs, design, adr, plan, все задачи Phase 1 и основная спецификация навигации на reviewed head. Проверки выполнены на reviewed head в этом рабочем каталоге: строгая валидация OpenSpec, codegen-check, анализатор, Widgetbook и release-сборка успешны. Полный прогон дал 4803 успешных теста и один сбой дочернего процесса; изолированный повтор всего затронутого файла дал 26 успешных тестов. Подробности и границы ручных свидетельств приведены ниже. |
| Code quality | Complete | Проверены все 53 изменённых пути кода и тестов на корректность, читаемость, границы и зависимости, безопасность и производительность. Проверены типизированные назначения и контексты тегов, владение стеком и командой, освобождение слушателей, отмена выбора, семантика и фокус скрытых страниц, отсутствие новых чтений первых порций, геометрия и изоляция тестовых каркасов. Анализатор не сообщил проблем. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Исходное ревью выполнено в указанном рабочем каталоге на неизменённом reviewed head. Все 56 путей обнаруженного диапазона учтены ровно один раз: 51 в U1, два в U2, три как свидетельства планирования. Несопоставленных путей нет. Просмотрены изменения каждого из 11 целевых коммитов и их совокупный результат; задачи, включая контрольные 1.4 и 1.11, сопоставлены ниже. Документы проверки прочитаны как свидетельства, а не как замена просмотра кода.

Идентификатор задачи 1, задача 1.1, коммит `94f96be2795f1bb1e4dd72873f6ff7b0b64021d8`, единицы U1. Общий каркас, повторный выбор текущего пункта, типизированный и безымянный стек.

Идентификатор задачи 2, задача 1.2, коммит `069f7a6329766f611c01589d95cd05ec88ef9002`, единицы U1. Намерение над формой, утрата прежнего черновика, сохранённые фильтры, прокрутка и порции корней.

Идентификатор задачи 3, задача 1.3, коммит `c239969f04755c0378be5e99ee1cb73af8e713b2`, единицы U1. Связь, дневной выбор, переходы к участникам и пути; редакторы остаются задачами.

Идентификатор задачи 4, задача 1.4, коммит `e57c3c69b2704e9a9933fa38692bcc3db7aa3197`, единицы U1. Контроль глубокой истории, обычного Back и прежних входов создания.

Идентификатор задачи 5, задача 1.5, коммит `ed28b74ba9207cfa50c6b990d04bc9dd8a691626`, единицы U1. Навигация по тегу, переход к намерению, возврат, сброс и порционное чтение.

Идентификатор задачи 6, задача 1.6, коммит `c912b1fc6c24d2e24e590f04f543282f08aeb8c0`, единицы U1. Три типизированных контекста тегов и защита модального черновика намерения.

Идентификатор задачи 7, задача 1.7, коммит `2319e0f75a10707b361f2920c9ce66edb3d47b9b`, единицы U1. Принятая команда, отмена выбора, очередь сообщений и поздние callbacks.

Идентификатор задачи 8, задача 1.8, коммит `5a6638c6fd06dc6e017731e51f7046dfc9167ca7`, единицы U1. Полнота матрицы маршрутов и назначений, безымянные задачи, bootstrap и модальные ограничения.

Идентификатор задачи 9, задача 1.9, коммит `1e3f1e0c25b54e9eace01c7db6f6ac0495126d50`, единицы U1. Геометрия последнего элемента, поиска, клавиатуры, безопасных отступов и сообщений.

Идентификатор задачи 10, задача 1.10, коммит `a7d7116cb96827b5861d96cf898d5487bc1eebd7`, единицы U1, U2. Семантика, фокус, локали, Hero, переходы и примеры Widgetbook при масштабе 2.5.

Идентификатор задачи 11, задача 1.11, коммит `6bd572d41ff519b82e14bc04a51c94379bd48265`, единицы U1, U2. Готовность только Phase 1, проверки генерации, анализа, тестов, сборки и OpenSpec.

Сопоставление требований включает все состояния обычных страниц; типизированные и безымянные задачи; глубокие переходы и Back; сохранение трёх корней; контексты просмотра, назначения и черновика тегов; блокировку панели под модальной сессией; загрузку и отказ bootstrap; единичность команд и сообщений; клавиатуру, отступы, последние элементы выдачи, ru/en, масштаб 2.5, Hero и скрытые вкладки. Инвентарь маршрутов сопоставлен с матрицей тестов. Новых сетевых границ, схем хранения, зависимостей или протоколов аутентификации диапазон не вводит.

Проверки на reviewed head при исходном ревью.

Все команды выполнены в корне проекта, кроме отдельно указанного Widgetbook; инструменты не устанавливались и не обновлялись.

Команда `MISE_AUTO_INSTALL=false mise run codegen-check`: Успешно, exit 0; генерируемые файлы и схема не изменились.

Команда `MISE_AUTO_INSTALL=false mise run check` завершилась кодом 1. Форматирование 562 файлов без изменений, проверка CI scope и анализатор успешны. Полный тестовый прогон завершился с 4803 успешными тестами и одним отказом: «прерывание каскадного архивирования после commit оставляет целое состояние» в `test/graph/data/file_backed_graph_durability_test.dart`. Его таймаут ожидания after_commit сопровождался сообщениями дочернего Flutter-процесса `The Dart compiler exited unexpectedly` и ошибкой в test_compiler. После завершения общего прогона команда `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter test test/graph/data/file_backed_graph_durability_test.dart` повторила весь файл изолированно: 26 тестов успешны, exit 0, включая упавший сценарий. Сбой не повторился; исходный общий запуск остаётся зафиксирован как неуспешный, отдельного продуктового дефекта из него не установлено. Логи — `/tmp/hypnotic-bird-review-check.log` и `/tmp/hypnotic-bird-review-durability-retry.log`.

В каталоге `widgetbook/` команда `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter test` прошла: 8 тестов, exit 0.

Команда `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter build apk --release` прошла, exit 0. Создан `build/app/outputs/flutter-apk/app-release.apk`, 66.4 MB.

Команда `mise exec --no-deps -- openspec validate add-quick-creation-and-persistent-navigation --strict --json`: Успешно, valid: true, issues: [].

Dart MCP, поиск DTD при исходном ревью: Запущенных приложений нет; проверка hot reload/runtime тогда была неприменима.

Ручные свидетельства задачи 1.10 сохранены в `docs/verification/persistent-navigation-1.10.md` на reviewed head: Android 16/API 36, Pixel 7, ru/en и масштаб 2.5, обычный и предиктивный Back, UIAutomator и Linux Widgetbook. В текущей сессии этот ручной проход не повторялся. Документ также отделяет существующий сбой Flutter 3.47.1 при дробной ширине PageView, воспроизведённый на чистом Flutter, и не заявляет проверку озвучивания TalkBack; это границы прежнего ручного свидетельства, не новые замечания к диапазону.

Корректирующее поведение принадлежит требованию «Сброс истории выбором пункта» [спецификации навигации](specs/app-navigation/spec.md) и решению 4 [дизайна](design.md): удалённый из истории экземпляр сразу теряет право на навигацию, даже до завершения обратной анимации. Последующая реализация и регрессионные проверки принадлежат новым незавершённым задачам 1.12–1.14 в [tasks.md](tasks.md), добавленным в порядке исполнения после дословно сохранённых 1.1–1.11. Это передача в планирование; код и тесты не изменены, проверка исправления и повторное ревью реализации не выполнялись. Готовность Phase 1 требует выполнения нового пакета; Phase 2 и Phase 3 остаются без задач и вне этой стадии.

Проверка текущего планирования: `MISE_AUTO_INSTALL=false mise exec --no-deps -- openspec validate add-quick-creation-and-persistent-navigation --strict --json` — exit 0, `valid: true`, `issues: []`. Дословная сохранность исходного списка задач, порядок новых идентификаторов и отсутствие изменений вне выбранного change root проверены отдельно. Эти проверки не заменяют продуктовые проверки будущей реализации.
