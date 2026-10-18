# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.25–2.27 выполнены, и полные проверки проекта на проверяемой голове проходят. Плагин запрашивает размер выбранного документа до ответа в Dart. В файл, о котором поставщик сообщил, что он не пуст, экспорт не пишет и не удаляет его, а общая поверхность предлагает «Повторить». После отказа удаляется только документ, пустой при выборе. Копирование заменяет прежнее содержимое целиком. Тест отказа удаления, который проверял только подмену, удалён. Тест уровня приложения для выбора файла с данными не ловит регрессий, которых не ловят другие тесты, а его название обещает проверку, которой в нём нет. По решению человека его и проверки, верные по построению, удаляет невыполненная задача 2.28, которая заменяет третий пункт проверки задачи 2.25. Активных замечаний нет. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** a891602bdf651fb17696d3754b107fd913e4c952
- **Base commit:** a891602bdf651fb17696d3754b107fd913e4c952
- **Reviewed head:** 99a31dbed697ebee1ef2701b3c7a9ca10ab5a389
- **Target commits:** ["2a8d84f73a6677011cdb530bfb2250ea9acd3805", "554e31f94b8914305e9ae56f3a04d6a98ff7043f", "99a31dbed697ebee1ef2701b3c7a9ca10ab5a389"]
- **Reviewable paths:** ["android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/application/graph_export_provider.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "openspec/changes/add-graph-export-import/tasks.md", "test/app/graph_export_app_flow_test.dart", "test/data_transfer/graph_export_test.dart", "test/data_transfer/method_channel_document_access_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart", "test/support/file_document_access.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Экспорт не начинается в выбранный файл с данными, а после отказа удаляется только документ, пустой при выборе

- **Work items:** ["2.25", "2.26"]
- **Requirements and scenarios:** ["graph-export-import: Экспорт в файл — сценарий «В диалоге выбран прежний файл»", "graph-export-import: Отказы экспорта и импорта — сценарий «Отказ экспорта не оставляет файла»", "graph-export-import: Локализация и доступность экспорта и импорта", "graph-export-import: Диагностика экспорта и импорта без пользовательского содержимого", "design: решение 12 — выбор файла с данными предъявляется как отказ", "design: решение 13 — выбор существующего файла, документ после отказа экспорта, режим \"wt\"", "plan: Phase 2 Ready to advance"]
- **Affected boundary:** Человек в сценарии экспорта; поставщики документов Storage Access Framework за системным диалогом сохранения; встроенный плагин `DocumentAccessPlugin` и его канал; контракт `DocumentAccess`, `GraphExport`, `GraphExportController`, координатор и `GraphOperationPresenter`.
- **Implementation target:** ["android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/application/graph_export_provider.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "test/app/graph_export_app_flow_test.dart", "test/data_transfer/graph_export_test.dart", "test/data_transfer/method_channel_document_access_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Нет новых разрешений, записей манифеста и `FileProvider` (ADR-0004, ADR-0037).
  Память операций с данными не растёт с размером графа и файла.
  Диагностика не содержит имён, адресов и содержимого файлов.
  Команды графа не ждут экспорта.
  Отмена диалога ничего не меняет и сообщения не показывает.
  Перезапись выбранного файла с данными не делается безопасной, а запрещается.
- **Excluded change scope:** Открытие документов и импорт относятся к этапу 4. Документ, оставшийся после завершения процесса посреди экспорта, при запуске не удаляется.

### U2 · Устойчивость экспорта к отказу удаления проверяется только там, где этот отказ возникает

- **Work items:** ["2.27"]
- **Requirements and scenarios:** ["graph-export-import: Отказы экспорта и импорта — неудача удаления не меняет исход и сообщение экспорта"]
- **Affected boundary:** Набор автоматических проверок экспорта.
- **Implementation target:** ["test/data_transfer/graph_export_test.dart", "test/support/file_document_access.dart"]
- **Applicable constraints and non-goals:** Код приложения и другие проверки не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | U1 и U2 делят `test/data_transfer/graph_export_test.dart`, поэтому их проверял один свежий изолированный рецензент `implementation-decision-review` по общей записке с двумя разделами намерения и объединённым списком из 18 путей поставки и тестов диапазона `a891602bdf651fb17696d3754b107fd913e4c952..99a31dbed697ebee1ef2701b3c7a9ca10ab5a389`. Планирующие артефакты, история Git, прежний отчёт и обсуждение реализации ему не передавались. Рецензент сообщил полное покрытие всех 18 путей. |
| OpenSpec conformance | Complete | Проверено в чистом рабочем дереве worktree, `HEAD` которого совпадает с `99a31dbed697ebee1ef2701b3c7a9ca10ab5a389`. `mise run check`: формат (723 файла без изменений), проверки CI-скриптов и `flutter analyze` без замечаний; обычные тесты — 3038 прошли; процессные тесты — 14 прошли. `mise run codegen-check` — успешно. `JAVA_HOME=<temurin-25> android/gradlew -p android :app:testDebugUnitTest --console=plain --rerun`: `DocumentAccessPluginTest` 16 из 16, `DisplayWindowPolicyTest` 44 из 44. `mise exec --no-deps -- openspec validate add-graph-export-import --strict` — успешно. `mise exec --no-deps -- flutter build apk --release` собран, `tool/check_android_privacy_manifest.dart` с `build-tools/36.0.0/aapt2` проходит. `git grep failsDeletes` по `lib` и `test` ничего не находит. Манифест, `res/`, `build.gradle.kts` и `pubspec` в диапазоне не менялись. |
| Code quality | Complete | Все пути поставки диапазона пройдены по линзам `code-review-and-quality`: корректность, читаемость, архитектура, безопасность и производительность. Учтены неизменённые вызывающие и зависимые места: `DisplayHostActivity`, `GraphCommandCoordinator.acceptExport`, `claimInitiatorFailure`, `planGraphOperationMessage`, общая поверхность `GraphOperationPresenter` с `persist: false`, обвязки `FileDocumentAccess` и presenter-теста. Сверены байткод Robolectric 4.16 (`ShadowContentResolver.openOutputStream`, `ShadowParcelFileDescriptor.open`) и поведение `ParcelFileDescriptor.parseMode` для режимов `"w"` и `"wt"`. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

**Цель и сопоставление.**

Цель — 3 коммита `a891602bdf651fb17696d3754b107fd913e4c952..99a31dbed697ebee1ef2701b3c7a9ca10ab5a389` и 19 путей. Рабочее дерево чистое, `HEAD` совпадает с проверяемой головой.

Файл `tasks.md` — свидетельство планирования. Диапазон меняет в нём только отметки 2.25–2.27.

Остальные 18 путей распределены по U1 и U2. Путь `test/data_transfer/graph_export_test.dart` общий: коммит `2a8d84f73a6677011cdb530bfb2250ea9acd3805` добавляет в него проверку выбора файла с данными, а `99a31dbed697ebee1ef2701b3c7a9ca10ab5a389` удаляет тест отказа удаления.

Задаче 2.25 соответствует `2a8d84f73a6677011cdb530bfb2250ea9acd3805`, задаче 2.26 — `554e31f94b8914305e9ae56f3a04d6a98ff7043f`, задаче 2.27 — `99a31dbed697ebee1ef2701b3c7a9ca10ab5a389`. Задача 2.26 — только проверка: её утверждения подтверждены повторным запуском проверок из таблицы покрытия. Посторонней работы и путей без задачи нет.

Прежний отчёт относился к диапазону `4f1380513622b1731d6b76c53e17fcbcab416f80..794a9f818889c20858e28894794a4c2fe810aacd`. Активных замечаний и принятых рисков в нём не было, поэтому переносить нечего. Доработку выбора существующего файла, которую он отдал задачам 2.25–2.26, этот диапазон выполняет.

**Проверенные свойства.**

После ответа диалога плагин закрепляет право записи и в фоновом потоке запрашивает `COLUMN_SIZE`; ответ в Dart приходит только после запроса. Размер больше нуля даёт код канала `existing_file`, право отпускается, документ не пишется и не удаляется. Нулевой размер вносит документ в `emptyDocuments` до ответа в Dart, поэтому шаг завершения на главном потоке видит эту отметку. Отсутствующий столбец, `NULL`, отрицательный размер и исключение поставщика дают неизвестный размер: экспорт идёт, а после отказа документ остаётся. Шаг завершения отпускает право при любом исходе.

Копирование открывает документ в режиме `"wt"`. Тест «Копирование заменяет прежнее содержимое документа целиком» различает регрессию к `"w"`: Robolectric передаёт режим настоящему `ContentResolver` и поставщику, `ParcelFileDescriptor.parseMode("w")` не даёт `MODE_TRUNCATE`, а теневой `ParcelFileDescriptor.open` усекает файл только с этим флагом.

Исход `ExistingFileChosen` — отдельный вариант запечатанного `DocumentCreation` без `CreatedDocument`, поэтому ни запись, ни шаг завершения для него вызвать нельзя. `_write` теперь возвращает `CreatedDocumentOutcome`, и запись не может породить исход `existingFile`. Исход предъявляется как отказ: `isFailure` даёт те же правила показа и объединения, что у «Не удалось сохранить файл», а общая поверхность выключает `persist` для всех сообщений с действием. Строки есть на русском и английском. Диагностических событий этот исход не даёт, как и отмена диалога.

Удаление `failsDeletes` и его теста обосновано: экспорт не получает результата шага завершения. Требование о неудаче удаления по-прежнему подтверждают `DocumentAccessPluginTest.kt:159-170` и `method_channel_document_access_test.dart:142-152`.

Файл экспорта читается модулем формата как выгрузка базы: эти тесты в `graph_export_test.dart` не менялись и прошли. Запись состояния и `GraphLogCompaction` в диапазоне не менялись, поэтому бюджет экспорта из задачи 2.9 в силе.

**Рассмотрено, но в замечания не записано.**

Ответ канала из фонового потока плагина допустим: так же устроены запись документа задачи 2.4 и шаг завершения задачи 2.23, а прежний отчёт сверил это с `FlutterJNI` Flutter 3.47.1.

Запрос размера опирается на временное право чтения из ответа диалога; плагин закрепляет только право записи. Если смена дисплея при открытом диалоге заменит хост в `onResume`, а прежняя Activity будет уничтожена раньше, чем поставщик ответит на запрос, запрос откажет. Тогда файл с данными будет считаться файлом неизвестного размера, и экспорт пойдёт в него, как решение 13 предписывает для отказавшего запроса. Уничтожение прежней Activity идёт после показа новой, а запрос метаданных у поставщика короче. Свидетельств, что это окно достижимо, не найдено.

Кодирование выбора файла с данными ошибкой канала задокументировано в плагине и адаптере канала: успешный ответ канала несёт только адрес документа.

**Ограничения.**

Поведение DocumentsUI при выборе существующего файла и значение `COLUMN_SIZE` у поставщиков установлены по исходникам Android и описаниям поставщиков, на устройстве не проверялись.

На устройстве ничего не проверялось, и эти проверки остаются ручными проверками пользователя. Нужно убедиться, что выбор прежнего файла в диалоге сохранения оставляет его без изменений и показывает «Такой файл уже есть. Сохраните копию под новым именем». Нужно убедиться, что экспорт в новый файл локальной папки и облачного хранилища по-прежнему проходит, а после отказа файла не остаётся.
