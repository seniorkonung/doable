## Phase 1: Приложение работает без избранности намерений

- [ ] 1.1 Сохранить доказательство атомарного отката создания на отказе записи назначений тегов
  - **Критерии приёмки:**
    - По решению 6 [дизайна](design.md) `IntentionCreationStorageObserver` прерывает реальную запись назначений через существующий наблюдатель настроенного соединения; в точке отказа транзакция открыта, намерение и часть назначений уже записаны.
    - Существующая интеграционная проверка подтверждает полный откат намерения и назначений, сохранение самостоятельных тегов, черновика и прежнего графа; явный повтор создаёт ровно одно намерение. Проверка не зависит от записи в `favorite_intentions`.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Зависимости:** нет; выполнить до удаления записи избранного из создания.
  - **Вероятные файлы:** `test/support/intention_creation_storage_observer.dart`, `test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Объём:** S.

- [ ] 1.2 Перевести смешанные проверки навигации на входы, сохраняющиеся после удаления списка Главной
  - **Критерии приёмки:**
    - Проверки возврата, сброса истории, состояния каталогов и общей поверхности открывают намерения через каталог или быстрое создание и используют сохраняющиеся команды вместо отметки избранного.
    - Сохраняются проверки фильтров и прокрутки каталогов, продолжения принятой операции после сброса и невмешательства позднего результата в новую страницу по [дельте навигации](specs/app-navigation/spec.md). Проверки только прокрутки, согласования и перестановки списка Главной удалены.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app/navigation/app_shell_state_test.dart test/app/navigation/app_shell_back_test.dart test/app/navigation/app_shell_pages_above_test.dart test/app/navigation/app_shell_layout_test.dart test/app/navigation/app_shell_operation_reset_test.dart`.
  - **Зависимости:** нет.
  - **Вероятные файлы:** перечисленные пять файлов тестов навигации; их общие фикстуры в `test/support/app_root_pages.dart` при необходимости.
  - **Объём:** M.

- [ ] 1.3 Оставить пустую стартовую Главную в области приложения
  - **Критерии приёмки:**
    - `HomePage` перенесена в `lib/src/app/home/home_page.dart` как `StatelessWidget` с собственным `Scaffold`, локализованным заголовком и пустым телом по решению 1 дизайна; имя `HomeRoute`, начальный пункт, панель и быстрое создание сохранены.
    - У Главной нет репозитория, ViewModel, подписок, списка, прокрутки и состояний получения данных. Удалены прежняя реализация и её генерируемый провайдер, специализированные проверки Главной, примеры `HomeIntentionRow` и относящиеся к ним проверки Widgetbook.
    - Существующие проверки стартовой страницы подтверждают пустое содержимое при пустом и непустом графе, включая архивированные намерения, и возврат на Главную после перезапуска; импорты сохранённых потребителей перенесены.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/app/navigation test/app/routing`; из `widgetbook/` — `mise exec --no-deps -- flutter test test/widgetbook_app_test.dart`.
  - **Зависимости:** 1.2.
  - **Вероятные файлы:** `lib/src/favorite/presentation/home/` → `lib/src/app/home/home_page.dart` (новый путь задан дизайном), `lib/src/app/routing/app_router.gr.dart`, `test/app/navigation/app_start_page_test.dart`, импорты в `test/support/app_root_pages.dart` и тестах навигации; удаляемые `test/favorite/presentation/home/` и `test/app/home_favorites*_test.dart`; `widgetbook/lib/catalog.dart`, `widgetbook/lib/favorite/home_row_use_cases.dart`, `widgetbook/test/widgetbook_app_test.dart`.
  - **Объём:** M.

- [ ] 1.4 Удалить управление избранностью со страницы намерения
  - **Критерии приёмки:**
    - Страница активного и архивированного намерения не предоставляет отметку избранного; из её состояния и ViewModel удалены соответствующие действия, ожидание снимка, ошибка и повтор.
    - Редактирование, готовность, архивирование, восстановление, теги и удаление сохраняют прежние контракты. Из смешанных проверок удалены только обязанности избранного; специализированные проверки управления отметкой удалены.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/details test/app/intention_app_lifecycle_test.dart`.
  - **Зависимости:** 1.2, 1.3 — навигационные проверки больше не используют удаляемое действие.
  - **Вероятные файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `intention_details_state.dart`, `intention_details_view_model.dart` в той же папке; `test/intention/presentation/details/`, удаляемые `test/app/favorite_mark_app_flow_test.dart` и `test/intention/presentation/favorite_mark_accessibility_test.dart`.
  - **Объём:** M.

- [ ] 1.5 Убрать передачу отметки в строки каталога и четырёх контекстов поиска
  - **Критерии приёмки:**
    - Каталог и общий поиск намерений, поиск действия, исходного намерения и участника долговременной связи больше не передают `confirmedFavoriteMark` в общую строку.
    - Сохранены выбор по идентификатору, готовность, архивное состояние, теги и счётчики; смешанные проверки этих данных продолжают действовать без ожидания звезды.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog test/daily_choice/presentation/action_picker test/daily_choice/presentation/source_picker test/long_term_relation/presentation/participant_picker`.
  - **Зависимости:** нет; сокращение параметров общего компонента выполняется в 1.6.
  - **Вероятные файлы:** `lib/src/intention/presentation/catalog/intention_catalog_page.dart`, `lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart`, `lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart`, `lib/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart`; соответствующие существующие тесты.
  - **Объём:** M.

- [ ] 1.6 Сократить общий компонент строки намерения до используемых вариантов
  - **Критерии приёмки:**
    - Из `IntentionSummaryView` удалены звезда, `confirmedFavoriteMark`, `IntentionSummarySemanticsNode` и `semanticsNode`; обычное объединение семантики через `MergeSemantics` сохранено по решению 3 дизайна.
    - Тексты и действия оставшихся потребителей доступны прежним образом; Widgetbook и тесты строки сохраняют примеры готовности, архивирования, тегов и связей без вариантов избранного. Другие параметры с потребителями сохранены.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/intention_summary_view_test.dart test/intention/presentation/intention_tag_search_accessibility_test.dart`; из `widgetbook/` — `mise exec --no-deps -- flutter test`.
  - **Зависимости:** 1.3, 1.5 — удалены переставляемая строка и передача отметки оставшимися экранами.
  - **Вероятные файлы:** `lib/src/intention/presentation/intention_summary_view.dart`, `test/intention/presentation/intention_summary_view_test.dart`, `widgetbook/lib/intention/intention_summary_view_use_cases.dart`.
  - **Объём:** M.

- [ ] 1.7 Создавать намерение с тегами и готовностью без поля избранного
  - **Критерии приёмки:**
    - Из панели, `IntentionCreationDraft` и `CreateIntention` удалены отметка, её обработчики, копирование и сравнение. Изменённость черновика определяется текстом, тегами и готовностью; минимальный и полный конструкторы сохраняют свои назначения и неизменяемый набор идентификаторов тегов.
    - Drift создаёт намерение и назначения одной транзакцией с проверкой текста, выбранных тегов и окончательного результата; удалены запись места и проверка отметки. Сохраняются единый подтверждённый пакет после commit, равные начальные временные метки и полный откат при отказе по [дельте намерений](specs/intention-management/spec.md) и ADR-0009.
    - Существующие проверки черновика и создания адаптированы к сокращённому контракту, включая реальные отказы сохраняющихся записей и окончательного чтения; удалены только точки отказа и варианты, относящиеся к избранному. Прямые вызовы полного конструктора в тестах переведены вместе с контрактом.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/application/intention_contract_test.dart test/intention/presentation/editor test/intention/data/drift_intention_repository_command_test.dart test/intention/data/drift_intention_repository_fault_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_sheet_tags_test.dart`.
  - **Зависимости:** 1.1.
  - **Вероятные файлы:** `lib/src/intention/application/intention_command.dart`, `lib/src/intention/presentation/editor/intention_editor_state.dart`, `intention_editor_view_model.dart`, `intention_editor_page.dart` в той же папке, `lib/src/graph/data/drift_personal_graph_repository.dart`; перечисленные проверки и их прямые вызовы `CreateIntention.withInitialState`.
  - **Объём:** M.

- [ ] 1.8 Подтвердить сохранность навигации и сессии создания после сокращения интерфейса
  - **Критерии приёмки:**
    - Проверки 1.1–1.7 подтверждают пустую Главную, три пункта навигации, быстрое создание, возврат и сохранение состояния каталогов.
    - Проверки существующей сессии подтверждают геометрию и доступность панели, выбор тегов, взаимное исключение выбора и отправки, подтверждение ухода, сохранение черновика при отказе и принадлежность позднего результата исходной сессии по ADR-0018 и ADR-0019.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app test/intention/presentation test/daily_choice/presentation/action_picker test/daily_choice/presentation/source_picker test/long_term_relation/presentation/participant_picker test/tag/presentation/catalog`; сообщить результаты в сессии.
  - **Зависимости:** 1.1–1.7.
  - **Вероятные файлы:** нет, только проверка.
  - **Объём:** XS.

- [ ] 1.9 Удалить команду перестановки и её прикладной путь
  - **Критерии приёмки:**
    - Удалены `MoveFavoriteIntention`, типы порядка и результатов, ключ, токен, принятие и исполнение перестановки в координаторе, её завершения и ветки общей поверхности.
    - Удалены Drift-реализация перестановки, сообщение её отказа и специализированные проверки порядка, конкурентности, отказов и долговечности; общий исполнитель графа, блокировки других команд и ожидание принятых операций при завершении приложения сохранены.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/application test/intention/presentation/operation test/graph/presentation/graph_operation_presenter_test.dart test/app/bootstrap/app_runtime_test.dart`; проверить отсутствие использования удалённых типов в действующем коде через `rg`.
  - **Зависимости:** 1.3, 1.8 — потребители перестановки удалены, интерфейс проверен.
  - **Вероятные файлы:** `lib/src/favorite/application/favorite_order_command.dart`, `lib/src/favorite/domain/favorite_order.dart`, `lib/src/favorite/presentation/favorite_order_failure_message.dart`, `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, удаляемая часть `drift_personal_graph_repository_favorite_order.dart`; соответствующие специализированные тесты в `test/favorite/` и `test/graph/`.
  - **Объём:** M.

- [ ] 1.10 Удалить чтение полного списка избранных из границы личного графа
  - **Критерии приёмки:**
    - `PersonalGraphRepository` больше не наследует `FavoriteReadContract`; удалены контракт списка, его модели и `drift_personal_graph_repository_favorite_list.dart`, включая подключения в основной реализации.
    - Тестовые репозитории освобождены от `FavoriteReadContractTestFallback` и прежнего чтения; сам fallback и специализированные проверки списка удалены. Пустых совместимых реализаций не осталось, а порционные чтения графа и полные снимки тегов сохранены по ADR-0009 и ADR-0013.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph test/intention test/tag test/daily_choice test/long_term_relation`; `rg -n 'FavoriteReadContract|FavoriteIntentions|favorite_read_contract_test_fallback' lib/src test widgetbook/lib` — остатки допустимы только в ещё удаляемых диагностических объявлениях задачи 1.14.
  - **Зависимости:** 1.8, 1.9 — Главная и специализированные проверки перестановки больше не читают список.
  - **Вероятные файлы:** `lib/src/favorite/application/favorite_intentions.dart`, `lib/src/graph/application/personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `drift_personal_graph_repository_favorite_list.dart` в той же папке, `test/support/favorite_read_contract_test_fallback.dart`; использующие fallback тестовые репозитории и специализированные тесты списка.
  - **Объём:** M.

- [ ] 1.11 Удалить команды добавления и снятия отметки из графа
  - **Критерии приёмки:**
    - Удалены `MarkIntentionFavorite`, `UnmarkIntentionFavorite`, их виды в координаторе, выполнение и ветки сообщений; оставшиеся команды намерения сохраняют прежние результаты и классификацию отказов.
    - Из части `drift_personal_graph_repository_favorite_marks.dart` удалена запись отметки и места после исчезновения её последнего вызова из создания. Чтение отметок, ещё необходимое старым проекциям, удаляется вместе с ними в 1.13; заглушки вместо операций не вводятся.
    - Специализированные проверки команд отметки и их пакетов удалены; смешанные проверки остальных операций и тестовые исполнители сохраняют своё назначение.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention test/graph/presentation test/app/navigation`; `rg -n 'MarkIntentionFavorite|UnmarkIntentionFavorite' lib/src test widgetbook/lib` не находит использований.
  - **Зависимости:** 1.4, 1.7, 1.9, 1.10 — удалены экранные потребители, начальная запись и проверки списка/порядка, использовавшие команды отметки.
  - **Вероятные файлы:** `lib/src/intention/application/intention_command.dart`, `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `drift_personal_graph_repository_favorite_marks.dart` в той же папке; специализированные тесты отметки в `test/intention/data/` и `test/graph/presentation/favorite_mark_package_consumers_test.dart`.
  - **Объём:** M.

- [ ] 1.12 Оставить один тип завершения для общего протокола предъявления результатов
  - **Критерии приёмки:**
    - `GraphPresentableCompletion` объединён с `GraphCommandCompletion`; очередь, claims и presenter работают с единой базой, без политики «только отказ» и отбрасывания успешной перестановки.
    - Существующие контрактные проверки ADR-0012 подтверждают последовательность сообщений, единственное предъявление, передачу неподтверждённого отказа общей поверхности после исчезновения инициатора и бездействие позднего callback прежнего claim. Протокол не дублируется в отдельных проверках каждого экрана.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart test/intention/presentation/operation/intention_command_coordinator_test.dart test/graph/application`.
  - **Зависимости:** 1.9 — удалено единственное успешное завершение без права предъявления.
  - **Вероятные файлы:** `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`; существующие тесты координатора и общей поверхности.
  - **Объём:** M.

- [ ] 1.13 Удалить отметку из проекций намерений и общих чтений Drift
  - **Критерии приёмки:**
    - Из `IntentionSummary` и `IntentionDetails` удалены поле отметки и его копирование; из чтений каталога, подробных данных и снимков команд исчезли запросы отметок и их проверки. Состав тегов, счётчики, курсоры и ревизия сохраняются.
    - Удалены оставшиеся `drift_personal_graph_repository_favorite_marks.dart` и `FavoriteMark`; все конструкторы, общие фикстуры и смешанные проверки используют сокращённые данные. В `lib/src/favorite/` не остаётся исходников или осиротевших генерируемых файлов.
    - Существующие проверки каталога, наблюдения и помеченных намерений сохраняют гарантии согласования; оценки стоимости чтений больше не включают исчезнувшие запросы отметок. Новые совместимые поля или постоянные значения вместо отметки не вводятся.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention test/graph/data test/tag/presentation/navigation test/graph/presentation`; `rg -n 'FavoriteMark|favoriteMark|_readFavoriteMarks|_readFavoriteMark' lib/src test widgetbook/lib` — остающиеся диагностические имена относятся к 1.14.
  - **Зависимости:** 1.6, 1.7, 1.10, 1.11 — больше нет потребителей отметки и команд, использующих её в снимках.
  - **Вероятные файлы:** `lib/src/intention/application/intention_catalog.dart`, `lib/src/intention/application/intention_details.dart`, `lib/src/intention/domain/intention.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, удаляемая часть `drift_personal_graph_repository_favorite_marks.dart`; конструкторы и проверки в `test/intention/`, `test/graph/`, `test/tag/`, `test/support/`.
  - **Объём:** M.

- [ ] 1.14 Сократить диагностику до сохраняющихся операций графа
  - **Критерии приёмки:**
    - Удалены события, виды команд, этапы и сериализация избранного; вместо семейства `IntentionCommandDiagnosticsStage` используется оставшийся `IntentionCreationCommandDiagnosticsStage` по решению 4 дизайна.
    - Создание сохраняет этапы проверки, записи и проверки результата; существующие тесты подтверждают безопасную передачу диагностики, отсутствие данных личного графа и неизменность результатов при отказе диагностического приёмника.
  - **Проверка:** `mise exec --no-deps -- flutter test test/shared/diagnostics/diagnostics_sink_test.dart test/intention/data/drift_intention_repository_fault_test.dart test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Зависимости:** 1.9–1.11, 1.13 — источники удаляемых событий больше не существуют.
  - **Вероятные файлы:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `developer_diagnostics_sink.dart` в той же папке, `lib/src/graph/data/drift_personal_graph_repository.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`; связанные существующие проверки отказов.
  - **Объём:** M.

- [ ] 1.15 Подтвердить сохранность границы графа перед удалением объектов SQLite
  - **Критерии приёмки:**
    - Проверки сокращённых контрактов, атомарной записи и отката, ревизий, согласования и предъявления результатов проходят; общие тестовые репозитории не содержат совместимых заглушек избранного.
    - В действующем прикладном коде и Widgetbook нет потребителей модуля избранного или таблицы `favorite_intentions`. Оставшиеся объекты схемы, их генерируемые представления, специализированная фикстура и локализации имеют задачи удаления 1.16–1.17.
  - **Проверка:** `mise exec --no-deps -- flutter analyze`; `mise exec --no-deps -- flutter test test/graph test/intention test/tag test/daily_choice test/long_term_relation test/shared/diagnostics`; адресный поиск `rg -n -i 'favorite|GraphPresentableCompletion|IntentionCommandDiagnosticsStage' lib/src test widgetbook/lib` с разбором оставшихся совпадений; сообщить результаты в сессии.
  - **Зависимости:** 1.9–1.14.
  - **Вероятные файлы:** нет, только проверка.
  - **Объём:** XS.

- [ ] 1.16 Создавать новую файловую базу схемы 1 без объектов избранного
  - **Критерии приёмки:**
    - Удалены `favorite_schema.drift` и его подключение в `AppDatabase`; в новой схеме отсутствуют таблица избранного, уникальность места и триггер неизменяемой идентичности. Версия остаётся 1; миграция старых файлов, их распознавание и автоматическое пересоздание не добавлены по решению 5 дизайна и исключению из ADR-0002 в [обзоре ADR](adr.md).
    - Штатной генерацией обновлены `app_database.g.dart` и `drift_schemas/drift_schema_v1.json`; удалены специализированный тест схемы и ставшая неиспользуемой `favorite_storage_fixture.dart`. Сохраняются настройки соединения и функции SQLite по ADR-0008.
    - Существующая проверка `verifyDoableDatabaseSchema` с `validateDropped: true` подтверждает точную схему; проверки повторного открытия файловой базы сохраняют свидетельства долговечности намерений с тегами и готовностью, связей, дневных выборов и согласованности FTS.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/data/local test/intention/data/file_backed_drift_intention_repository_test.dart test/graph/data/file_backed_graph_durability_test.dart test/graph/data/file_backed_daily_choice_durability_test.dart test/graph/data/file_backed_tag_durability_test.dart`; сверить снимок схемы и отсутствие новых версий.
  - **Зависимости:** 1.15 — обращения к удаляемому хранению уже отсутствуют.
  - **Вероятные файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/schema/favorite_schema.drift`, `lib/src/data/local/app_database.g.dart`, `drift_schemas/drift_schema_v1.json`, удаляемые `test/data/local/favorite_schema_test.dart` и `test/support/favorite_storage_fixture.dart`; существующие проверки в `test/data/local/migrations/` и файлового хранения при наличии прежних фикстур избранного.
  - **Объём:** M.

- [ ] 1.17 Удалить локализованные строки исчезнувшей возможности
  - **Критерии приёмки:**
    - Из обеих ARB-локалей и генерируемых локализаций удалены только ключи отметки, списка, перестановки и их сообщений; заголовок Главной, навигация, быстрое создание и сообщения оставшихся операций сохранены.
    - Поиск подтверждает отсутствие обращений к удалённым ключам; смешанные проверки обеих локалей и доступности сохранены.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter analyze`; `mise exec --no-deps -- flutter test test/app/localization test/app/navigation/app_navigation_accessibility_test.dart test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`; из `widgetbook/` — `mise exec --no-deps -- flutter test`.
  - **Зависимости:** 1.3, 1.4, 1.6, 1.7, 1.9, 1.11 — все источники удаляемых сообщений уже удалены.
  - **Вероятные файлы:** `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_ru.dart`, `lib/l10n/app_localizations_en.dart`; существующие проверки локализованного интерфейса при наличии прежних ожиданий.
  - **Объём:** S.

- [ ] 1.18 Привести действующий язык продукта и руководство запуска к новой структуре данных
  - **Критерии приёмки:**
    - Из `CONTEXT.md` удалены понятие избранного намерения и связанные описания; готовность, архивирование, теги и черновик сохраняют прежние значения.
    - `README.md` на его существующем английском языке объясняет самостоятельную очистку прежних локальных данных человеком перед новой сборкой и перед откатом, отсутствие переноса и автоматического удаления базы, одинаковую версию несовместимых структур и невозможность восстановить уже удалённые данные откатом.
    - Сохранены исторические ADR и уже существующее пояснение их применимости в `docs/adr/README.md`. Основные спецификации остаются предметом штатной синхронизации дельт OpenSpec с установленным `retire_capabilities: true`; ручная правка основных спецификаций и переписывание архивов в эту задачу не входят.
  - **Проверка:** сверить `CONTEXT.md` и руководство с предложением, решением 5 дизайна и обзором ADR; проверить ссылки и `git diff --check`.
  - **Зависимости:** 1.16 — руководство описывает итоговую структуру хранения.
  - **Вероятные файлы:** `CONTEXT.md`, `README.md`.
  - **Объём:** S.

- [ ] 1.19 Подтвердить готовность всей фазы одной согласованной сборкой
  - **Критерии приёмки:**
    - Условие `Ready to advance` из [плана](plan.md) подтверждено: отсутствует поддержка избранного, сохранены навигация и сессия создания, атомарная запись и откат, предъявление результатов и долговечность остальных данных. Новая файловая база и повторное открытие сохраняют созданное намерение с тегами и готовностью; Главная остаётся пустой.
    - Итоговая схема и все генерируемые представления воспроизводимы, полные проверки приложения и Widgetbook и строгая проверка дельт проходят. В действующем коде, тестах, примерах, локализациях и снимке схемы нет осиротевшей поддержки; исторические ссылки, архивы и дельты удаления не считаются остатками реализации.
    - Руководство содержит условия запуска и отката; результаты проверок сообщены в сессии без отдельного документа. Выполнение задач и фиксация реализации не подменяют штатную синхронизацию спецификаций или архивацию изменения.
  - **Проверка:**
    - Выполнить `mise run codegen`, затем `mise run check` и `mise exec --no-deps -- openspec validate remove-favorite-intentions --type change --strict --no-interactive`.
    - Проверить `rg -n -i 'favorite|избран|GraphPresentableCompletion|IntentionCommandDiagnosticsStage|IntentionSummarySemanticsNode' lib test widgetbook/lib widgetbook/test drift_schemas CONTEXT.md README.md` и `git diff --check`; разобрать каждое оставшееся совпадение по его назначению.
    - После фиксации реализации и отметок уже завершённых задач в чистой рабочей копии выполнить `mise run codegen-check`. Саму задачу 1.19 отметить завершённой только после успешной проверки и зафиксировать эту отметку отдельно. Если генерация дала изменения, устранить причину, зафиксировать исправление и повторить детектор из чистого состояния; не запускать его заведомо на незакоммиченных файлах.
    - Если приложение запущено, через Dart MCP обнаружить его с помощью `dtd`, выполнить hot reload или restart и проверить `get_runtime_errors`; иначе использовать результаты CLI-проверок. Проверять новую сборку только после самостоятельной очистки прежних данных человеком.
  - **Зависимости:** 1.1–1.18.
  - **Вероятные файлы:** нет, только проверка и штатные отметки выполнения в `tasks.md`.
  - **Объём:** XS.
