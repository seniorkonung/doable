# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 2.17–2.24 выполнены, и полные проверки проекта на проверяемой голове проходят. Обвязки корневой оболочки строят её с темой Doable. Право на выбранный документ удерживается до исхода экспорта. После отказа документ удаляется. Экспорт, наткнувшийся на повреждённый последний снимок, дожидается пересборки. На проверяемой голове экспорт по-прежнему считает выбранный в диалоге существующий файл новым документом. По решению человека экспорт в такой файл с данными не должен начинаться. Это записано в требовании «Экспорт в файл» и решении 13 дизайна, а доработку кода ведут невыполненные задачи 2.25–2.26. Остаются две находки низкой важности: тест отказа удаления не ловит регрессию (F2), а решение 13 дизайна перечисляет методы канала без шага завершения (F3). Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 4f1380513622b1731d6b76c53e17fcbcab416f80
- **Base commit:** 4f1380513622b1731d6b76c53e17fcbcab416f80
- **Reviewed head:** 794a9f818889c20858e28894794a4c2fe810aacd
- **Target commits:** ["cc9fa3d0ba02cfdcd3db06cb4dd8ea851d37831e", "d7f3670365ad2edb7b30b2ed254229ec9198fc94", "ac60244eb3b25baf44881db05f95a51425d3c5c9", "3ea4c4cd4db555957e0fe2fe5a0aec3a0d11f786", "077a05b2335d74a7301d2a465c8dccc1b7f64edd", "3034a313dc99e1fd009845b36c24eb60edc28bd9", "75f4e491ef173d5392b5279f5d451465c5b884a7", "a1969b63862d8e77421d9c2060d1ba14eb7d6237", "d8c6dc941a30a6d09b0cf064666a1ec9967cd880", "794a9f818889c20858e28894794a4c2fe810aacd"]
- **Reviewable paths:** ["android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "lib/src/graph_snapshots/graph_log_compaction.dart", "openspec/changes/add-graph-export-import/tasks.md", "test/app/tag_assignment_app_lifecycle_test.dart", "test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_completion_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/daily_choice/presentation/daily_choice_picker_context_test_support.dart", "test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart", "test/daily_choice/presentation/details/daily_choice_details_page_test.dart", "test/daily_choice/presentation/path/choice_path_page_test.dart", "test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart", "test/data_transfer/graph_export_test.dart", "test/data_transfer/method_channel_document_access_test.dart", "test/graph_snapshots/graph_state_export_test.dart", "test/intention/presentation/catalog/intention_catalog_page_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_statistics_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_creation_sheet_layout_test.dart", "test/intention/presentation/editor/intention_creation_tags_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/intention_tag_search_accessibility_test.dart", "test/long_term_relation/presentation/details/relation_details_tags_test.dart", "test/long_term_relation/presentation/editor/relation_creation_navigation_test.dart", "test/long_term_relation/presentation/editor/relation_editor_page_test.dart", "test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart", "test/support/file_document_access.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_navigation_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_read_cost_widget_test.dart", "test/tag/presentation/tag_accessibility_test.dart", "test/tag/presentation/tag_catalog_search_accessibility_scenarios.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Тестовые обвязки строят корневую оболочку с темой Doable, как приложение

- **Work items:** ["2.17", "2.18"]
- **Requirements and scenarios:** ["tasks: 2.17 — каждая обвязка `MaterialApp.router` с `AppRouter` задаёт `doableTheme(Brightness.light)`", "plan: Direction — поведение, которого спецификации изменения не касаются, сохраняется", "ADR-0029"]
- **Affected boundary:** Виджетные тесты представлений намерений, дневных выборов, тегов, долговременных связей и тест жизненного цикла приложения при назначении тегов.
- **Implementation target:** ["test/app/tag_assignment_app_lifecycle_test.dart", "test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart", "test/daily_choice/presentation/daily_choice_creation_completion_test.dart", "test/daily_choice/presentation/daily_choice_creation_exit_test.dart", "test/daily_choice/presentation/daily_choice_picker_context_test_support.dart", "test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart", "test/daily_choice/presentation/details/daily_choice_details_page_test.dart", "test/daily_choice/presentation/path/choice_path_page_test.dart", "test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart", "test/intention/presentation/catalog/intention_catalog_page_test.dart", "test/intention/presentation/catalog/intention_picker_session_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_statistics_test.dart", "test/intention/presentation/details/intention_details_tags_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_creation_sheet_layout_test.dart", "test/intention/presentation/editor/intention_creation_tags_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/intention_tag_search_accessibility_test.dart", "test/long_term_relation/presentation/details/relation_details_tags_test.dart", "test/long_term_relation/presentation/editor/relation_creation_navigation_test.dart", "test/long_term_relation/presentation/editor/relation_editor_page_test.dart", "test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_navigation_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_search_page_test.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_read_cost_widget_test.dart", "test/tag/presentation/tag_accessibility_test.dart", "test/tag/presentation/tag_catalog_search_accessibility_scenarios.dart"]
- **Applicable constraints and non-goals:** Код приложения не меняется.
  Проверяемые сценарии и названия тестов прежние; ожидание меняется только там, где оно зависело от темы Material по умолчанию.
  Обычные тесты остаются быстрыми и без замеров времени.

### U2 · Право на выбранный документ удерживается до исхода экспорта, а документ неудавшегося экспорта удаляется

- **Work items:** ["2.19", "2.20", "2.23", "2.24"]
- **Requirements and scenarios:** ["graph-export-import: Экспорт в файл — принятый экспорт продолжается до результата", "graph-export-import: Отказы экспорта и импорта — сценарий «Отказ экспорта не оставляет файла»", "design: решение 13 — право на документ, документ после отказа экспорта", "ADR-0031", "ADR-0037", "plan: Phase 2 Ready — набор разрешений Android не изменился"]
- **Affected boundary:** Поставщики документов Storage Access Framework, встроенный плагин `DocumentAccessPlugin` и его канал, контракт `DocumentAccess` и операция `GraphExport`.
- **Implementation target:** ["android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "test/data_transfer/graph_export_test.dart", "test/data_transfer/method_channel_document_access_test.dart", "test/support/file_document_access.dart"]
- **Applicable constraints and non-goals:** Нет новых разрешений, записей манифеста, правил резервного копирования и `FileProvider` (ADR-0004, ADR-0037).
  Байты через канал не передаются.
  Диагностика не содержит адресов документов.
  Документ, оставшийся после завершения процесса посреди экспорта, при запуске не удаляется.
- **Excluded change scope:** Открытие документов и их копирование для импорта относятся к этапу 4.

### U3 · Экспорт, наткнувшийся на повреждённый последний снимок, дожидается пересборки и пишет файл из нового снимка

- **Work items:** ["2.21", "2.22"]
- **Requirements and scenarios:** ["design: решение 7 — пересборка из базы и исключение для записи состояния экспорта", "plan: Phase 2 Ready — успешный повтор экспорта после пересборки повреждённого последнего снимка", "graph-export-import: Экспорт в файл — изменения графа не ждут окончания экспорта"]
- **Affected boundary:** Сжатие лога фактов `GraphLogCompaction` и запись состояния графа для экспорта.
- **Implementation target:** ["lib/src/graph_snapshots/graph_log_compaction.dart", "test/graph_snapshots/graph_state_export_test.dart", "test/data_transfer/graph_export_test.dart"]
- **Applicable constraints and non-goals:** Команды графа не ждут экспорта, сжатия и пересборки.
  Одновременно идёт не больше одного сжатия, а неудачное сжатие не повторяется на каждом новом пакете.
  Алгоритм пересборки, правило автоматического повтора и события диагностики не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Работали два свежих изолированных рецензента `implementation-decision-review`. Рецензент U1 получил 32 пути U1. U2 и U3 делят `test/data_transfer/graph_export_test.dart`, поэтому их проверял один рецензент по общей записке с двумя разделами намерения и объединённым списком из 10 путей. Оба получили только нейтральную записку и точный диапазон `4f1380513622b1731d6b76c53e17fcbcab416f80..794a9f818889c20858e28894794a4c2fe810aacd`. Планирующие артефакты, история Git, прежний отчёт и обсуждение реализации им не передавались. Оба сообщили полное покрытие своих путей. |
| OpenSpec conformance | Complete | Проверено в чистом рабочем дереве worktree, `HEAD` которого совпадает с `794a9f818889c20858e28894794a4c2fe810aacd`. `mise run check`: формат (723 файла без изменений), проверки CI-скриптов и `flutter analyze` без замечаний; обычные тесты — 3034 прошли; процессные тесты — 14 прошли. `mise run codegen-check` — успешно. `JAVA_HOME=<temurin-25> android/gradlew -p android :app:testDebugUnitTest --console=plain --rerun`: `DocumentAccessPluginTest` 12 из 12, `DisplayWindowPolicyTest` 44 из 44. `mise exec --no-deps -- openspec validate add-graph-export-import --strict` — успешно. Команда проверки задачи 2.17 по `MaterialApp` и `AppRouter` без `doableTheme(` ничего не находит. Release APK собран, `tool/check_android_privacy_manifest.dart` проходит. Манифест, `res/xml` и сборочные файлы в диапазоне не менялись. |
| Code quality | Complete | Все пути поставки диапазона пройдены по линзам `code-review-and-quality`: корректность, читаемость, архитектура, безопасность и производительность. Учтены неизменённые вызывающие и зависимые места: `GraphExportController`, `DisplayHostActivity.configureFlutterEngine`, `AppRuntime.shutdown`, `GraphSnapshotStore`, модуль формата `graph_format_file.dart`. Сверены исходники Android SDK 36.1: `ContentResolver`, `DocumentsProvider`, `FileSystemProvider`, `FileUtils`. |

## Findings

### F2 · Low — Проверка «поставщик не удалил документ» не ловит регрессию экспорта

- **Evidence:** Тест `test/data_transfer/graph_export_test.dart:311-325` включает у подмены флаг `failsDeletes` и проверяет, что исход экспорта — отказ, документ остался, а работа с ним завершена один раз. Но `GraphExport.write` не получает результата удаления: `finishDocument` возвращает `Future<void>` и вызывается в `finally` (`graph_export.dart:86-88`). А `failsDeletes` (`test/support/file_document_access.dart:28-30`, `:61-70`) лишь пропускает удаление файла подменой и не меняет того, что видит экспорт. Флаг нужен только этому тесту. Проверки исхода и однократного завершения повторяют тест `:273-309`, а проверка существования документа проверяет саму подмену. Отказ удаления, который действительно возникает, изолируют и проверяют `DocumentAccessPluginTest.kt` (тест «Исключение поставщика при удалении документа не мешает отпустить право и ответить без ошибки») и `test/data_transfer/method_channel_document_access_test.dart:131-141`. Этот тест предписан проверкой задачи 2.23: «При отказе удаления исход экспорта остаётся прежним отказом».
- **Evidence revisions:** ["794a9f818889c20858e28894794a4c2fe810aacd"]
- **Impact:** Тест проходит при любом поведении экспорта после отказа удаления и создаёт видимость покрытия. Подмена получает опцию, которую нужно сопровождать без пользы для проверок.
- **Required outcome:** Устойчивость к отказу удаления проверяется только там, где отказ возникает и доходит до проверяемого кода. У тестовой подмены нет опций, нужных только тесту, который не может обнаружить регрессию.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["tasks.md: 2.23 Verification", "test/data_transfer/graph_export_test.dart", "test/support/file_document_access.dart"]

### F3 · Low — Решение 13 дизайна перечисляет методы канала документов без шага завершения работы с документом

- **Evidence:** Решение 13 в `design.md` перечисляет методы канала: «создать документ, открыть документ, скопировать документ во временный файл, скопировать временный файл в документ». На проверяемой голове канал обрабатывает и `finishDocument` (`DocumentAccessPlugin.kt:103-107`). Контракт `DocumentAccess.finishDocument` (`document_access.dart:30-45`) обязывает завершать работу с каждым созданным документом один раз при любом исходе.
- **Evidence revisions:** ["794a9f818889c20858e28894794a4c2fe810aacd"]
- **Impact:** Дизайн описывает контракт канала неполно, а этап 4 будет расширять тот же канал открытием и копированием документа по этому перечню. Читатель дизайна не видит шага, который отпускает закреплённое право и удаляет документ после отказа.
- **Required outcome:** Решение 13 описывает канал документов в реализованном составе, включая шаг завершения работы с документом.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** ["design.md: решение 13"]

## Review coverage

**Цель и сопоставление.**

Цель — 10 коммитов `4f1380513622b1731d6b76c53e17fcbcab416f80..794a9f818889c20858e28894794a4c2fe810aacd` и 43 пути. Рабочее дерево чистое, `HEAD` совпадает с проверяемой головой.

Файл `tasks.md` — свидетельство планирования. Диапазон меняет в нём только отметки 2.17–2.24.

Остальные 42 пути распределены по U1–U3. Путь `test/data_transfer/graph_export_test.dart` общий для U2 и U3: коммит `75f4e491ef173d5392b5279f5d451465c5b884a7` уточняет в нём название проверки при выключенном сжатии.

Задачи сопоставлены с коммитами так. Задаче 2.17 соответствует `cc9fa3d0ba02cfdcd3db06cb4dd8ea851d37831e`, задаче 2.18 — `d7f3670365ad2edb7b30b2ed254229ec9198fc94`. Задаче 2.19 соответствуют `ac60244eb3b25baf44881db05f95a51425d3c5c9` и `3ea4c4cd4db555957e0fe2fe5a0aec3a0d11f786`, задаче 2.20 — `077a05b2335d74a7301d2a465c8dccc1b7f64edd`. Задаче 2.21 соответствует `3034a313dc99e1fd009845b36c24eb60edc28bd9`, задаче 2.22 — `75f4e491ef173d5392b5279f5d451465c5b884a7` и `a1969b63862d8e77421d9c2060d1ba14eb7d6237`. Задаче 2.23 соответствует `d8c6dc941a30a6d09b0cf064666a1ec9967cd880`, задаче 2.24 — `794a9f818889c20858e28894794a4c2fe810aacd`.

Посторонней работы и путей без задачи нет.

Прежний отчёт относился к диапазону `86b632af83727b04b963e83d6d818ae0346e26bf..5d7bf4b03c157a348f9d1f6530248d635fd7f1df`. Активных замечаний и принятых рисков в нём не было, поэтому переносить нечего. Его вывод о падении 260 тестов закрыт задачами 2.17 и 2.18: `mise run check` теперь проходит.

**Проверенные свойства.**

Обвязки U1 задают ту же светлую тему, что `lib/main.dart`. Тёмная тема тестам не нужна, потому что яркость платформы в них светлая. Добавленный `pumpAndSettle()` после `scrollUntilVisible` в двух тестах выбора с 250 элементами не меняет проверяемых ожиданий.

Право записи закрепляется в `onActivityResult`, пока жива Activity, получившая ответ, и до ответа в Dart. Если поставщик не дал закрепляемого права, адрес всё равно передаётся. Повторное добавление плагина при переносе движка реестр пропускает, поэтому очистка прав при подключении к движку срабатывает один раз за жизнь движка и не отпускает право идущего экспорта.

После удаления `DocumentsProvider` сам отзывает права на документ, поэтому следующее отпускание бросает `SecurityException`, и плагин его перехватывает. Шаг завершения выполняется ровно один раз при успехе, при отказе записи документа и при отказе записи состояния. Исключение `writeCurrentState` проходит дальше после завершения работы с документом. Повтор из сообщения об отказе открывает диалог, только когда удаление уже завершено, поэтому имя по умолчанию свободно.

Запись состояния при повреждённом базовом снимке снимает отметку чтения до ожидания. Проверка `_running` и запуск сжатия выполняются без промежуточного `await`, поэтому второго сжатия нет. Повтор выполняется один раз, и ход отсчитывается с нуля. Повреждение во второй записи сразу даёт отказ. При выключенном сжатии отказ наступает без ожидания. База закрывается только после экспорта и сжатия (`AppRuntime._finishShutdown`), поэтому повтор после выключения сжатия её ещё застаёт.

Сценарий «Отказ экспорта не оставляет файла» для документа, созданного диалогом, подтверждают `graph_export_test.dart` и нативная проверка удаления до отпускания права. Выбор в диалоге существующего файла на проверяемой голове экспорт считает новым документом: после отказа такой файл удаляется, а режим `"w"` у поставщика локальных папок не усекает его при успехе. По решению человека экспорт в файл с данными не начинается; требование «Экспорт в файл», решение 13 дизайна и задачи 2.25–2.26 владеют этой доработкой.

**Рассмотрено, но в замечания не записано.**

Ответ канала из фонового потока плагина допустим: так же устроена запись документа задачи 2.4, а прежний отчёт сверил это с `FlutterJNI` Flutter 3.47.1.

Комментарий в `releaseGrant` называет отсутствие права только случаем поставщика без закрепляемого права. Права нет и после удаления документа. Поведение верное, это лишь неполнота комментария.

Экспорт, не принятый координатором при выключении, оставляет пустой документ и закреплённое право до следующего запуска. Так предписывает задача 2.19, а импорт отклоняет такой файл.

**Ограничения.**

Поведение DocumentsUI при перезаписи установлено по исходникам AOSP, на устройстве не проверялось. Диалоги сохранения других производителей могут отличаться.

На устройстве ничего не проверялось, и эти проверки остаются ручными проверками пользователя. Нужно проверить экспорт в локальную папку и в облачный документ со сменой дисплея при открытом диалоге и во время записи временного файла. Нужно убедиться, что после отказа экспорта файла не остаётся, а повтор сохраняет файл под именем по умолчанию. Выбор существующего файла в диалоге проверяется после задачи 2.25.
