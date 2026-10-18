# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.1–2.16 этапа 2 реализуют экспорт по существу: переход к «Настройкам», раздел «Данные», строку и панель экспорта, фоновую запись согласованного состояния с защитой истории от сжатия, плагин документов, предъявление результата на общей поверхности, диагностику и бюджет. Но этап не готов. На проверяемой голове `mise run check` не проходит: 260 виджетных тестов в 28 файлах падают на построении `HomePage`, потому что их обвязки строят корневую оболочку без темы Doable. Поэтому подтверждение готовности в задаче 2.16 не соответствует действительности. Исправление обвязок и повторное подтверждение готовности отслеживаются задачами 2.17 и 2.18. Неудачный экспорт пока оставляет в выбранной папке пустой или усечённый файл под именем экспорта. Требование «Отказы экспорта и импорта» теперь предписывает удалять такой файл, если поставщик места это позволяет; реализация и повторное подтверждение готовности отслеживаются задачами 2.23 и 2.24. Активных замечаний и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 86b632af83727b04b963e83d6d818ae0346e26bf
- **Base commit:** 86b632af83727b04b963e83d6d818ae0346e26bf
- **Reviewed head:** 5d7bf4b03c157a348f9d1f6530248d635fd7f1df
- **Target commits:** ["9938885ef0ce812b8265b94c04b2b0a377230cb0", "e0e3fa32525fc740672f8d4e84008a265b47669a", "91bff8c865d2812f12ef4abcb80585baadced556", "3c7ef537208d4a48940ccada08057a389c49e8d2", "d44132d40620b3bea47ded48c595ba3020bea938", "0e07f177d1e354a8f7aafb5e6b7a87594870deef", "666e7c4f24630f7810ce38698d3ffa0f3ee8cd3e", "d8a0b5dad240222c1160aa38e3224ee4f5e63fde", "0398d9a1985c3ffa01fa3bddb8b68ff2a1a038bb", "8655c20f9b9bfbaa366842afa0ea9618a357362f", "5fc88aceb8256dbc16c7211da6dedbfba5719c32", "201ebd9405158c166439f18132aa664e4b7538bb", "44958f6048d5fda5cb8a56f15495148afc2c181c", "e6b5d2438f402aeb84c7ca947b117769d193bb0c", "8952bfab0a02e7fe1201df65bf853af2168b8c69", "6f00fdfb7cdb5434d628a62ee38a157871862ed7", "8f2526bc9b696a2933bdc11fcd0a7470ce7ea3d6", "5d7bf4b03c157a348f9d1f6530248d635fd7f1df"]
- **Reviewable paths:** ["README.md", "android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "benchmark/graph_export/graph_export_benchmark.dart", "benchmark/graph_log/graph_log_benchmark.dart", "benchmark/support/graph_log_database.dart", "benchmark/support/graph_log_memory_worker.dart", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/app_runtime.dart", "lib/src/app/home/home_page.dart", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/app/settings/settings_page.dart", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/application/graph_composition.dart", "lib/src/data_transfer/application/graph_composition_provider.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/application/graph_export_provider.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "lib/src/data_transfer/presentation/export_data_sheet.dart", "lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/design_system/components/caution.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/export.svg", "lib/src/design_system/icons/assets/lock_open.svg", "lib/src/design_system/icons/assets/settings.svg", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_composition.dart", "lib/src/graph/presentation/graph_operation_message_plan.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "lib/src/graph_snapshots/graph_log_compaction.dart", "lib/src/graph_snapshots/graph_snapshot_store.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "openspec/changes/add-graph-export-import/design.md", "openspec/changes/add-graph-export-import/tasks.md", "test/app/bootstrap/app_runtime_graph_export_test.dart", "test/app/bootstrap/app_runtime_graph_snapshots_test.dart", "test/app/bootstrap/app_runtime_test.dart", "test/app/graph_export_app_flow_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/settings_navigation_test.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart", "test/data_transfer/graph_export_test.dart", "test/data_transfer/method_channel_document_access_test.dart", "test/data_transfer/presentation/export_data_sheet_test.dart", "test/data_transfer/presentation/settings_data_section_test.dart", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/option_row_test.dart", "test/graph/application/graph_command_coordinator_export_test.dart", "test/graph/data/drift_graph_composition_read_test.dart", "test/graph/presentation/graph_operation_message_plan_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart", "test/graph_snapshots/graph_history_read_test.dart", "test/graph_snapshots/graph_state_export_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/failing_snapshot_temporary_files.dart", "test/support/file_document_access.dart", "test/support/temporary_graph_files.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/design.md", "openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Согласованное состояние графа записывается в файл в фоне, не теряя историю, нужную записи

- **Work items:** ["2.1", "2.2", "2.3"]
- **Requirements and scenarios:** ["graph-export-import: Состав файла экспорта — сценарий «Изменение во время экспорта»", "design: решение 7 — идущие чтения истории, граница хранения, пересборка последнего снимка вне порога", "design: решение 9 — сборка файла, согласованность и ход", "plan: Phase 2 Ready — согласованность файла при одновременных изменениях и при сжатии, завершившемся во время экспорта; успешный повтор после пересборки"]
- **Affected boundary:** Модуль снимков и фоновое сжатие лога фактов. Его потребитель — операция экспорта.
- **Implementation target:** ["lib/src/graph_snapshots/graph_log_compaction.dart", "lib/src/graph_snapshots/graph_snapshot_store.dart", "test/graph_snapshots/graph_history_read_test.dart", "test/graph_snapshots/graph_state_export_test.dart", "test/support/failing_snapshot_temporary_files.dart"]
- **Applicable constraints and non-goals:** Команды графа не ждут записи. База получает от изолята записи только короткие операции.
  Память не растёт с размером графа.
  В этой фазе вне сжатия идёт не больше одного чтения истории.
  Учёт хранимых копий в границе хранения относится к этапу 3.

### U2 · Документ создаётся системным диалогом сохранения, и в него копируется временный файл без новых разрешений

- **Work items:** ["2.4"]
- **Requirements and scenarios:** ["design: решение 13 — плагин доступа к документам, перенос движка", "ADR-0037", "plan: Phase 2 Ready — набор разрешений Android не изменился"]
- **Affected boundary:** Хост `DisplayHostActivity` и движок Flutter, системный интерфейс документов, Dart-контракт доступа к документам.
- **Implementation target:** ["android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DocumentAccessPlugin.kt", "android/app/src/test/kotlin/software/doable/doable/DocumentAccessPluginTest.kt", "lib/src/data_transfer/application/document_access.dart", "lib/src/data_transfer/data/method_channel_document_access.dart", "test/data_transfer/method_channel_document_access_test.dart"]
- **Applicable constraints and non-goals:** Нет новых разрешений, записей манифеста, `FileProvider` и правил резервного копирования (ADR-0004).
  Байты через канал не передаются.
  Открытие документов (`ACTION_OPEN_DOCUMENT`) относится к этапу 4.

### U3 · Координатор принимает экспорт операцией с данными, а общая поверхность предъявляет его исход

- **Work items:** ["2.5"]
- **Requirements and scenarios:** ["graph-export-import: Экспорт в файл — сообщение «Данные сохранены в файл»", "graph-export-import: Отказы экспорта и импорта — сценарий «Отказ экспорта не задерживает другие сообщения»", "design: решение 12", "ADR-0012", "ADR-0023"]
- **Affected boundary:** `GraphCommandCoordinator`, `GraphOperationPresenter` и слушатели завершений команд.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "lib/src/graph/presentation/graph_operation_message_plan.dart", "lib/src/graph/presentation/graph_operation_presenter.dart", "test/graph/application/graph_command_coordinator_export_test.dart", "test/graph/presentation/graph_operation_message_plan_test.dart", "test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Результаты команд графа и их предъявление не меняются.
  Действие сообщения не продлевает показ, в том числе при включённом экранном дикторе.
  Операции импорта, восстановления и ручной копии относятся к этапам 3 и 4.

### U4 · Фоновая операция экспорта от выбора документа до записанного файла, её диагностика и жизненный цикл

- **Work items:** ["2.6", "2.7", "2.8"]
- **Requirements and scenarios:** ["graph-export-import: Экспорт в файл — имя по умолчанию, отмена диалога, фон, ход, один экспорт", "graph-export-import: Диагностика экспорта и импорта без пользовательского содержимого", "local-data-lifecycle: Локальная долговечность данных приложения — временные файлы внутри исключённого каталога", "design: решения 9, 13 и 14"]
- **Affected boundary:** `AppRuntime` и его выключение, состояние экспорта в области приложения, граница диагностики.
- **Implementation target:** ["lib/src/app/app_runtime.dart", "lib/src/data_transfer/application/graph_export.dart", "lib/src/data_transfer/application/graph_export_provider.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/app/bootstrap/app_runtime_graph_export_test.dart", "test/app/bootstrap/app_runtime_graph_snapshots_test.dart", "test/data_transfer/graph_export_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart", "test/support/failing_snapshot_temporary_files.dart", "test/support/file_document_access.dart"]
- **Applicable constraints and non-goals:** Временные файлы лежат только в `app_flutter/tmp/`.
  Очистка при запуске не задерживает готовность и команды.
  В диагностике нет имён, путей, адресов, содержимого и исходных исключений.

### U5 · Память и длительность экспорта измерены на профиле, а бюджет записан

- **Work items:** ["2.9"]
- **Requirements and scenarios:** ["graph-export-import: Размер графа и файла", "design: решение 15 — замеры экспорта", "plan: Phase 2 Ready — память экспорта не растёт, длительность укладывается в бюджет"]
- **Affected boundary:** Бенчмарки и их документация для разработчиков.
- **Implementation target:** ["README.md", "benchmark/graph_export/graph_export_benchmark.dart", "benchmark/graph_log/graph_log_benchmark.dart", "benchmark/support/graph_log_database.dart", "benchmark/support/graph_log_memory_worker.dart"]
- **Applicable constraints and non-goals:** Время измеряется только в бенчмарках.
  Бюджеты мягкие.
  Серия по методике занимает не больше 10 минут.
  Смысл замеров бенчмарка лога фактов сохраняется.

### U6 · Состав графа читается коротким агрегатным чтением и наблюдается после подтверждённых изменений

- **Work items:** ["2.10"]
- **Requirements and scenarios:** ["graph-export-import: Раздел «Данные» на странице настроек — пустой граф и отказ чтения состава", "graph-export-import: Экспорт в файл — состав в панели", "local-data-lifecycle: Обработка обнаруженного повреждения данных", "design: решение 9 — состав в панели", "ADR-0009"]
- **Affected boundary:** `DriftPersonalGraphRepository` как единственная граница графа; раздел «Данные».
- **Implementation target:** ["lib/src/app/app_runtime.dart", "lib/src/data_transfer/application/graph_composition.dart", "lib/src/data_transfer/application/graph_composition_provider.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_composition.dart", "lib/src/shared/diagnostics/developer_diagnostics_sink.dart", "lib/src/shared/diagnostics/diagnostics_sink.dart", "test/app/bootstrap/app_runtime_test.dart", "test/graph/data/drift_graph_composition_read_test.dart", "test/shared/diagnostics/diagnostics_sink_test.dart"]
- **Applicable constraints and non-goals:** Чтение идёт через последовательный исполнитель и не материализует сущности.
  Интерфейс `PersonalGraphRepository` и его подмены не меняются.
  Отказ чтения не выдаётся за пустой граф.

### U7 · Шестерёнка, значок экспорта и открытый замок из макетов добавлены в иконки дизайн-системы

- **Work items:** ["2.11"]
- **Requirements and scenarios:** ["app-appearance: Иконки из дизайна"]
- **Affected boundary:** Набор иконок дизайн-системы и его эталон.
- **Implementation target:** ["lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/export.svg", "lib/src/design_system/icons/assets/lock_open.svg", "lib/src/design_system/icons/assets/settings.svg", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png"]
- **Applicable constraints and non-goals:** Графика, размеры и толщина линий из `Home.dc.html` и `Settings.dc.html` сохраняются.

### U8 · С Главной открывается страница «Настройки» с разделом «Данные», строкой и панелью экспорта, и этап подтверждён

- **Work items:** ["2.12", "2.13", "2.14", "2.15", "2.16"]
- **Requirements and scenarios:** ["app-navigation: Переход к настройкам с Главной — сценарий «Настройки открываются с Главной»", "app-navigation: Панель на обычных страницах", "graph-export-import: Раздел «Данные» на странице настроек — сценарий «Пустой граф новой установки» в части строки экспорта", "graph-export-import: Экспорт в файл — сценарии «Экспорт не мешает работе» и «Отказ чтения состава графа»", "graph-export-import: Локализация и доступность экспорта и импорта", "plan: Phase 2 Ready to advance"]
- **Affected boundary:** Главная, маршрутизация и навигация, страница «Настройки», компоненты строки, листа и предупреждения дизайн-системы, локализация.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/app/home/home_page.dart", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/app/settings/settings_page.dart", "lib/src/data_transfer/application/graph_composition_provider.dart", "lib/src/data_transfer/presentation/export_data_sheet.dart", "lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/design_system/components/caution.dart", "lib/src/design_system/components/option_row.dart", "lib/src/design_system/components/sheet.dart", "test/app/graph_export_app_flow_test.dart", "test/app/navigation/app_shell_page_matrix.dart", "test/app/navigation/app_shell_pages_above_test.dart", "test/app/navigation/settings_navigation_test.dart", "test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart", "test/data_transfer/presentation/export_data_sheet_test.dart", "test/data_transfer/presentation/settings_data_section_test.dart", "test/design_system/option_row_test.dart", "test/support/temporary_graph_files.dart"]
- **Applicable constraints and non-goals:** Компоненты дизайн-системы не содержат предметной логики (ADR-0030).
  Листы открываются над корневым навигатором (ADR-0032).
  «Настройки» — обычная страница с панелью (ADR-0020).
  Строк «Резервные копии» и «Импорт данных» и заглушек для них нет.
  Задача 2.16 только проверяет готовность и меняет лишь `tasks.md`. Её утверждения сверены со всеми единицами.
- **Excluded change scope:** Резервные копии, восстановление и замена графа, сброс корневых страниц после замены относятся к этапу 3.
  Импорт, открытие документа и проверка недоверенного файла относятся к этапу 4.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Работали два свежих рецензента `implementation-decision-review` с общей нейтральной запиской U1–U8. У обоих одна и та же цель — все 69 путей поставки в `86b632af83727b04b963e83d6d818ae0346e26bf..5d7bf4b03c157a348f9d1f6530248d635fd7f1df`. Единицы делят изменённые файлы: локализацию, `app_runtime.dart`, диагностику, провайдер состава и тестовую подмену файлов снимков. Кроме того, они читают изменённые контракты друг друга, поэтому образуют одну группу с перекрытием. Рецензент A углублённо проверил U1, U4, U5 и U6, рецензент B — U2, U3, U7 и U8. Каждый сообщил полное покрытие своих единиц. Планирующие артефакты, история Git и прежние отчёты им не передавались. |
| OpenSpec conformance | Complete | Проверено на голове `5d7bf4b03c157a348f9d1f6530248d635fd7f1df` в чистом рабочем дереве worktree. `openspec validate add-graph-export-import --strict` — успешно. `mise run check`: формат, проверки CI-скриптов и `flutter analyze` без замечаний; обычные тесты — 2770 прошли, 260 упали (задачи 2.17 и 2.18). Процессные тесты `mise run check:process-tests` запущены отдельно, потому что `mise run check` остановился на тестах: 14 прошли. `mise run codegen-check` — успешно. Нативные тесты `android/gradlew -p android :app:testDebugUnitTest` на JDK 21: `DocumentAccessPluginTest` 6 из 6, `DisplayWindowPolicyTest` 44 из 44. Серия бенчмарка экспорта по методике решения 15 перезапущена (итог — в разделе покрытия). Манифест, ресурсы, `pubspec` и сборочные скрипты Android в диапазоне не менялись. |
| Code quality | Complete | Все изменённые пути поставки пройдены по линзам `code-review-and-quality`: корректность, читаемость, архитектура, безопасность и производительность. Учтены непосредственно затронутые неизменённые вызывающие и зависимые места: подписчики `completions`, `DisplayWindowPolicy`, `AppNavigationBar`, тема `doable_theme.dart`, тестовые обвязки корневой оболочки, `FlutterJNI` и `DartMessenger` Flutter 3.47.1. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

**Цель и сопоставление.**

Цель — 18 коммитов `86b632af83727b04b963e83d6d818ae0346e26bf..5d7bf4b03c157a348f9d1f6530248d635fd7f1df` и 71 путь.

Файлы `design.md` и `tasks.md` — свидетельства планирования. Диапазон меняет в `tasks.md` только отметки 2.1–2.16, а в `design.md` добавляет замеры и бюджет экспорта в решение 15.

Остальные 69 путей распределены по U1–U8. Общие пути: локализация (U3, U8), `app_runtime.dart` и диагностика (U4, U6), провайдер состава (U6, U8), подмена файлов снимков (U1, U4).

Каждая задача 2.1–2.16 сопоставлена с единицей. Посторонней работы и путей без задачи нет.

Прежний отчёт относился к этапу 1 и не содержал активных замечаний и принятых рисков, поэтому переносить нечего.

**Проверенные свойства.**

Отметка чтения истории ставится до чтения позиции. Пока базовый снимок чтения не выбран, `removeHistoryBefore` ничего не удаляет, а после выбора сохраняет снимок и пакеты после него. Отложенное удаление выполняет следующее сжатие. Оба окна из задачи 2.1 покрыты тестами.

Запись состояния идёт в изоляте через порт сжатия. Ход сообщается не чаще ста раз, файл удаляется при любом отказе, повреждение базы даёт `GraphSnapshotCorruption`.

Координатор вызывает экспорт синхронно внутри `acceptExport`, поэтому между ответом диалога и состоянием «экспорт идёт» нет окна для второго диалога. Завершение экспорта публикуется вне последовательной публикации команд. Перестановка записи при публикации сохраняет прежний порядок предъявления команд.

Параметр `persist: false` во Flutter 3.47.1 даёт обычное время показа и при экранном дикторе. Ответ канала из фонового потока допустим: `FlutterJNI.invokePlatformMessageResponseCallback` вызывается из любого потока.

Повторное добавление плагина на перенесённом движке пропускает реестр.

Временный каталог `app_flutter/tmp/` очищается до первой записи этого запуска и не задерживает готовность. Выключение дожидается экспорта через координатор, а повреждение после выключения сжатия пересборку не запускает.

Состав графа читается одним оператором через исполнитель. Отказ приходит типизированным значением и закрывает наблюдение, после чего строка остаётся доступной с обычной подписью.

Тексты на двух языках с формами чисел, семантика недоступной строки и хода, шестерёнка только на Главной, «Настройки» в матрице обычных страниц.

Сценарии «Изменение во время экспорта», «Экспорт не мешает работе», «Отказ чтения состава графа», «Отказ экспорта не задерживает другие сообщения» и «Настройки открываются с Главной» подтверждены тестами диапазона. Сценарий отказа чтения состава подтверждают вместе тест строки и тест панели.

Сценарии импорта, замены графа и восстановления копий относятся к этапам 3 и 4 и обязательствами этого диапазона не считались.

Серия бенчмарка экспорта перезапущена на голове командой `mise run --skip-tools benchmark -- --plain-name 'бенчмарк экспорта' --dart-define=BENCHMARK_SAMPLES=40 --dart-define=BENCHMARK_WARMUPS=3`; машина и версии те же, что в решении 15. Пик живых данных экспорта вырос с 5,8 МиБ на 100 000 сущностях до 6,0 МиБ на 1 000 000, то есть на 0,1 МиБ при допуске 8 МиБ. Наибольшая длительность экспорта профиля — 33,0 с при бюджете 45 с; из неё запись документа заняла около 21 мс. Полный запуск длился 279 с, в пределах 10 минут. Это совпадает с замерами, записанными в решении 15.

**Рассмотрено, но в замечания не записано.**

Удержание истории для нескольких одновременных чтений с разными базами было бы неверным. Но сейчас вне сжатия идёт не больше одного чтения истории (решение 9, задача 2.1), а несколько чтений появятся вместе с копиями этапа 3, и их границу задаёт его план.

Отказ открыть диалог сохранения (`DocumentCreationFailed`) и этап диагностики `documentCreation` достижимы при отсутствии обработчика `ACTION_CREATE_DOCUMENT`. Задача 2.4 требует типизированный отказ.

Гонка выключения с открытым диалогом недостижима в приложении: `AppRuntime.shutdown` вызывают только тесты.

Отказ первого получения каталога документов теперь завершает подготовку, а не только отключает сжатие. Но тот же каталог уже нужен для открытия базы.

**Ограничения.**

На устройстве ничего не проверялось. Не проверены системный диалог сохранения, запись в локальную папку и облачный документ, перенос движка с открытым диалогом и во время экспорта (задача 2.19), чтение хода и сообщений экранным диктором. Это остаётся ручными проверками пользователя.

Release APK в этом ревью не собирался. Набор разрешений не изменился, что видно из диапазона: манифест, ресурсы, `pubspec.yaml`, `pubspec.lock` и сборочные скрипты не менялись, а плагин разрешений не объявляет.

Пробная правка `HomePage` в одноразовой копии служила только проверкой причины падения тестов. В репозиторий она не вносилась: по решению пользователя исправляются тестовые обвязки (задача 2.17).
