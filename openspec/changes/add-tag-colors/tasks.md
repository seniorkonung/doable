Пакет относится только к первой фазе [плана](plan.md). Поведение задают спецификации [тегов](specs/tag-management/spec.md), [экспорта и импорта](specs/graph-export-import/spec.md) и [резервных копий](specs/graph-backups/spec.md); контракты и границы — [дизайн](design.md) и [ADR-обзор](adr.md). Компоненты выбора и визуальное отображение цвета входят во вторую фазу.

Задачи 1.1 и 1.4 устанавливают общие контракты для последующих потребителей. Обязательная механическая адаптация мест сборки и исчерпывающих обработчиков входит в соответствующий переход контракта. Последующие задачи проверяют поведение конкретных потребителей на реальном пути данных. Проверки используют небольшие фикстуры без измерений времени и расширенных тайм-аутов.

## Phase 1: Цвет сохраняется как полное состояние тега

- [ ] 1.1 Сделать цвет явной частью тега и общего формата графа
  - **Критерии приёмки:**
    - `TagColor` задаёт девять вариантов с устойчивыми кодами по решению 1 дизайна; `Tag.color` — обязательный параметр типа `TagColor?`. Все места сборки явно передают отсутствие цвета либо сохраняют цвет исходного тега при копировании.
    - Общий кодек файла, снимка и пакета фактов записывает обязательное поле `color` после `name`; `null` означает «Без цвета». Отсутствующее поле, неверный тип и неизвестный код дают существующий отказ повреждения формата.
    - Эталон пакета версии 1 и встроенные примеры проверок кодека содержат цветной и бесцветный теги. В общем эталоне файла версии 1 и во всех рукописных записях формата, включая снимок замены в `test/app/navigation/app_shell_graph_generation_test.dart`, у тегов поле `color` равно `null`: база ещё не хранит и не вставляет цвет, поэтому цветной тег в эталон файла добавляет задача 1.8. Номер неопубликованного формата и пустая цепочка повышения сохраняются; совместимость со старым представлением не добавляется.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/domain test/graph_format test/graph_snapshots/graph_import_snapshot_test.dart test/graph/data/drift_graph_replacement_test.dart test/data_transfer/graph_import_test.dart test/app/graph_import_failures_app_flow_test.dart test/app/navigation/app_shell_graph_generation_test.dart` — проверки кодека, а также потребители эталона файла и рукописного снимка, сравнивающие записи или выгрузку базы с файлом; `mise exec --no-deps -- flutter analyze` для проверки обязательной адаптации вызовов.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/tag/domain/tag_color.dart` (новый), `lib/src/tag/domain/tag.dart`, `lib/src/graph_format/graph_format_codec.dart`, `test/graph_format/graph_format_codec_test.dart`, `test/graph_format/graph_format_file_test.dart`, оба эталона в `test/graph_format/golden/`, `test/app/navigation/app_shell_graph_generation_test.dart`; механические изменения существующих конструкторов в коде, тестах и бенчмарках.
  - **Размер:** M — один переход общего контракта с механической адаптацией вызовов.

- [ ] 1.2 Разрешить хранение цвета в текущей базовой схеме БД
  - **Критерии приёмки:**
    - Столбец цвета допускает только SQL `NULL` и девять кодов; существующие ограничения идентичности, уникальности названия и назначений сохраняются.
    - Текущая схема БД 3, её генерируемое представление и эталон согласованы. Миграции прежних неопубликованных данных и автоматическое пересоздание хранилища не добавляются.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/data/local/tag_schema_test.dart test/data/local/app_database_schema_test.dart`.
  - **Зависимости:** 1.1 — согласованные коды цвета.
  - **Предполагаемые файлы:** `lib/src/data/local/schema/tag_schema.drift`, `lib/src/data/local/app_database.g.dart`, `drift_schemas/drift_schema_v3.json`, `test/data/local/tag_schema_test.dart`, `test/data/local/app_database_schema_test.dart`.
  - **Размер:** M.

- [ ] 1.3 Передавать цвет через все чтения тега и захват фактов
  - **Критерии приёмки:**
    - Общий декодер различает отсутствующий столбец и SQL `NULL`, преобразует допустимый код в `TagColor` и использует `StoredGraphCorruption` для некорректного представления.
    - Каталог, выбор, назначения, наблюдение тега, навигация, краткие данные намерений и чтение результата команды возвращают полный тег с цветом. Все использующие общий декодер проекции обновлены согласованно.
    - Порционное чтение записей графа и существующий захват фактов включают тот же цвет; изменение цвета использует действующий триггер обновления тега.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_tag_read_test.dart test/graph/data/drift_tag_assignment_read_test.dart test/graph/data/drift_tagged_entities_read_test.dart test/graph/data/graph_fact_capture_test.dart test/graph/data/drift_graph_fact_log_access_test.dart`. Проверка отсутствующего столбца проходит через общий декодер, а проверки чтений используют цветной тег.
  - **Зависимости:** 1.1 — тип и формат; 1.2 — схема с цветом.
  - **Предполагаемые файлы:** `lib/src/graph/data/stored_graph_rows.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart`, `lib/src/graph/data/drift_personal_graph_repository_fact_log.dart`, `lib/src/graph/data/graph_fact_capture.dart`; перечисленные проверки чтений.
  - **Размер:** M — общий декодер и согласованное расширение его проекций.

- [ ] 1.4 Сохранять название и цвет одной подтверждаемой операцией редактирования
  - **Критерии приёмки:**
    - `CreateTag` принимает явный nullable-цвет; `UpdateTag`, `TagUpdated` и `TagUpdatedChange` заменяют прежний контракт переименования по решению 2 дизайна. Координатор сохраняет `ExistingTagKey`, последовательность операций и завершение принятой команды независимо от экрана; все вызывающие стороны и обработчики переведены на новый контракт.
    - Репозиторий сохраняет оба поля атомарно, включая явный SQL `NULL`. Изменение только цвета подтверждается, конфликт названия откатывает оба поля, а совпадение обоих полей не создаёт записи, пакета фактов или новой ревизии.
    - Событие редактирования допускает различие цвета при прежнем названии и сохраняет проверку идентичности. Назначения, порядки и данные помеченных намерений остаются прежними; категория операции и диагностики обозначает редактирование.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/application/tag_command_contract_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_graph_fact_log_write_test.dart test/graph/application/graph_command_coordinator_tag_test.dart`; `mise exec --no-deps -- flutter analyze` для проверки всех потребителей заменённого контракта.
  - **Зависимости:** 1.1 — полное состояние тега; 1.3 — согласованные чтения и факты.
  - **Предполагаемые файлы:** `lib/src/tag/application/tag_command.dart`, `lib/src/tag/application/tag_result.dart`, `lib/src/tag/application/tag_change.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`; механическая адаптация существующих обработчиков, тестовых репозиториев и вызовов команды.
  - **Размер:** M — один переход командного контракта с механической адаптацией потребителей.

- [ ] 1.5 Подтвердить сохранение цвета после повторного открытия файловой БД
  - **Критерии приёмки:**
    - Небольшая проверка настоящего репозитория на файловой БД подтверждает сохранение цветного и бесцветного тегов, правки только цвета и возврата к «Без цвета» после закрытия и нового открытия.
    - Повторное чтение сохраняет идентификаторы, назначения активному и архивированному намерениям и их порядок. Проверка использует существующий модуль соединения и не требует отдельного процесса или устройства.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/file_backed_tag_color_test.dart`.
  - **Зависимости:** 1.4 — готовый путь записи и чтения.
  - **Предполагаемые файлы:** `test/graph/data/file_backed_tag_color_test.dart` (новый); существующий `test/support/local_database_harness.dart` используется без расширения контракта.
  - **Размер:** S.

- [ ] 1.6 Проверить согласованность состояния тега перед подключением остальных потребителей
  - **Критерии приёмки:**
    - Проверены новый формат, ограничения схемы, чтение полного тега, атомарное редактирование и повторное открытие БД; основные операции тегов сохраняют прежнее поведение.
    - Дальнейшие задачи могут использовать готовые контракты `TagColor?`, `UpdateTag` и `TagUpdatedChange` без дополнительных способов записи или сериализации.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/domain test/tag/application test/graph_format test/data/local/tag_schema_test.dart test/data/local/app_database_schema_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_tag_read_test.dart test/graph/data/graph_fact_capture_test.dart test/graph/data/drift_graph_fact_log_write_test.dart test/graph/data/file_backed_tag_color_test.dart test/graph/application/graph_command_coordinator_tag_test.dart`; `openspec validate add-tag-colors --strict --no-interactive`. Результаты сообщить в сессии.
  - **Зависимости:** 1.1–1.5.
  - **Предполагаемые файлы:** нет, только проверка.
  - **Размер:** XS.

- [ ] 1.7 Подтвердить сохранение цвета при сборке истории и пересборке снимков
  - **Критерии приёмки:**
    - Независимая эталонная выгрузка БД включает фактический цвет; сравнение с состоянием из снимка и пакетов обнаруживает потерю нового поля.
    - Существующие проверки полноты лога, сжатия и пересборки снимка используют небольшой граф с цветным и бесцветным тегами и правкой только цвета. Сравнение полного состояния учитывает цвет во всех этих путях.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_fact_log_completeness_test.dart test/graph_snapshots/graph_state_assembly_test.dart test/graph_snapshots/graph_log_compaction_test.dart test/graph_snapshots/graph_snapshot_rebuild_test.dart`. Расширить существующие проверки этих механизмов без отдельного механизма истории цвета.
  - **Зависимости:** 1.6 — согласованный путь состояния и фактов.
  - **Предполагаемые файлы:** `test/support/graph_log_completeness_reference.dart`, `test/graph/data/drift_graph_fact_log_completeness_test.dart`, `test/graph_snapshots/graph_state_assembly_test.dart`, `test/graph_snapshots/graph_log_compaction_test.dart`, `test/graph_snapshots/graph_snapshot_rebuild_test.dart`.
  - **Размер:** M.

- [ ] 1.8 Воспроизводить цвет при атомарной замене графа
  - **Критерии приёмки:**
    - Вставка тега при замене переносит цвет из полного `TagRecord`, включая явное отсутствие цвета; назначения и порядок воспроизводятся по действующему контракту замены.
    - Существующие проверки успешной замены, отката и снимка замены учитывают цвета в исходном и новом графе; ошибки сохраняют прежнее полное состояние.
    - Один тег общего эталона файла версии 1 получает цвет, другой остаётся без цвета. Проверки, сравнивающие с эталоном прочитанные записи или выгрузку базы после замены и импорта, проходят с обоими тегами.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_replacement_test.dart test/graph_snapshots/graph_replacement_snapshot_test.dart test/graph_format/graph_format_file_test.dart test/graph_snapshots/graph_import_snapshot_test.dart test/data_transfer/graph_import_test.dart test/app/graph_import_failures_app_flow_test.dart`.
  - **Зависимости:** 1.6 — новый формат, схема и чтение записей графа с цветом.
  - **Предполагаемые файлы:** `lib/src/graph/data/drift_personal_graph_repository_replacement.dart`, `test/graph/data/drift_graph_replacement_test.dart`, `test/graph_snapshots/graph_replacement_snapshot_test.dart`, `test/graph_format/golden/graph_format_v1.jsonl`, `test/graph_format/graph_format_file_test.dart`.
  - **Размер:** M.

- [ ] 1.9 Подтвердить восстановление цветов резервной копии и учёт правки цвета в сводке
  - **Критерии приёмки:**
    - Через существующий путь восстановления готового приложения копия возвращает цветной и бесцветный теги к состоянию на её позиции вместе с идентификаторами и назначениями.
    - Сводки между копиями и между копией и текущим графом учитывают правку только цвета как изменение тега, включая возврат к прежнему цвету. Используется общий подсчёт по фактам.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph_backups/graph_change_summary_test.dart test/graph_backups/graph_backups_test.dart test/app/bootstrap/app_runtime_graph_restore_test.dart`. Расширить существующие примеры сводки и восстановления цветами.
  - **Зависимости:** 1.7 — история полного состояния; 1.8 — замена графа.
  - **Предполагаемые файлы:** `test/graph_backups/graph_change_summary_test.dart`, `test/graph_backups/graph_backups_test.dart`, `test/app/bootstrap/app_runtime_graph_restore_test.dart`.
  - **Размер:** M.

- [ ] 1.10 Переносить выбранные цвета через настоящий файл экспорта и импорт
  - **Критерии приёмки:**
    - Существующая проверка экспорта и импорта в другую установку сравнивает полное состояние цветного и бесцветного тегов вместе с остальными данными и порядками графа.
    - Отсутствующий или недопустимый цвет в импортируемой записи отклоняется общим строгим разбором до замены графа; граф и резервные копии остаются прежними. Дополнительный разбор цвета в модуле переноса не появляется.
  - **Проверка:** `mise exec --no-deps -- flutter test test/data_transfer/graph_export_test.dart test/data_transfer/graph_import_test.dart test/graph_snapshots/graph_state_export_test.dart`. Цвет включить в существующие сравнения состояния и примеры повреждённого файла.
  - **Зависимости:** 1.7 — сборка состояния; 1.8 — импортируемая замена.
  - **Предполагаемые файлы:** `test/data_transfer/graph_export_test.dart`, `test/data_transfer/graph_import_test.dart`, `test/graph_snapshots/graph_state_export_test.dart`; существующие фикстуры файла в `test/support/graph_import_files.dart` при необходимости.
  - **Размер:** M.

- [ ] 1.11 Согласовывать полный тег в каталоге, выборе и назначениях
  - **Критерии приёмки:**
    - Подтверждённая правка только цвета заменяет тег по идентификатору в загруженном каталоге, строках выбора и назначениях; признаки назначения и текущий выбор сохраняются.
    - Поздний снимок не возвращает прежний цвет; порядок строк, прокрутка и различие отказов записи и обновления сохраняются по действующему протоколу.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_view_model_test.dart test/tag/presentation/catalog/tag_catalog_snapshot_selection_test.dart test/tag/presentation/assignments/tag_assignments_view_model_test.dart`. Расширить существующие примеры согласования изменением без переименования.
  - **Зависимости:** 1.6 — подтверждённое обновление полного тега.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart`, `lib/src/tag/presentation/assignments/tag_assignments_view_model.dart`, три перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.12 Учитывать изменение только цвета в наблюдении и навигации по тегу
  - **Критерии приёмки:**
    - Сравнения наблюдаемого тега и данных страниц учитывают цвет вместе с названием, поэтому новое состояние не пропускается при прежнем названии.
    - Подтверждённый цвет сохраняется при перестановке ответа страницы и наблюдения; идентичность выбранного тега, охват и порядок результатов остаются прежними.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/navigation/tag_navigation_view_model_test.dart test/tag/presentation/navigation/tag_navigation_page_test.dart` с расширением существующих сценариев запоздалых ответов.
  - **Зависимости:** 1.6 — полные снимки и событие обновления.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/navigation/tag_navigation_view_model.dart`, `test/tag/presentation/navigation/tag_navigation_view_model_test.dart`, существующие сценарии в `test/tag/presentation/navigation/` при необходимости.
  - **Размер:** M.

- [ ] 1.13 Передавать подтверждённый цвет в краткие данные намерений и их потребителей
  - **Критерии приёмки:**
    - Обновление тега заменяет его полное состояние в кратких данных по идентификатору, сохраняя состав и порядок тегов, временные отметки намерений, соответствие фильтру и порядок выдачи.
    - Существующие потребители кратких данных в поиске, подробностях, связях и дневных выборах получают цвет через действующее согласование; поздний ответ не отменяет обновление.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart test/graph/presentation/tag_package_catalog_consumers_test.dart`. Общую проверку потребителей расширить цветом вместо отдельных копий сценария для каждого экрана.
  - **Зависимости:** 1.6 — чтения и пакет полного состояния.
  - **Предполагаемые файлы:** `lib/src/intention/application/intention_catalog.dart`, `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart`, `test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart`, `test/graph/presentation/tag_package_catalog_consumers_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M.

- [ ] 1.14 Сохранять актуальный цвет выбранных тегов в черновике намерения
  - **Критерии приёмки:**
    - Собственное представление тега черновика переносит типизированный цвет при добавлении, копировании и смене статуса; наблюдение принимает обновление цвета при прежнем названии.
    - Цвет обновляется по идентификатору без изменения выбранного набора черновика или постоянных назначений. Существующие состояния недоступного и удалённого тега сохраняют действующую семантику.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/tag/presentation/catalog/tag_catalog_draft_session_test.dart` с изменением только цвета уже выбранного тега.
  - **Зависимости:** 1.6 — наблюдение полного тега.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.15 Переносить цвет в состояния условий фильтра намерений
  - **Критерии приёмки:**
    - Модели условия и внутренней записи хранят типизированный цвет, учитывают его в равенстве и переносят при копировании, повторном чтении и подтверждённом обновлении.
    - Правка только цвета не меняет идентификатор и надобность условия, набор совпадений и порядок выдачи; старое чтение не возвращает прежнее состояние.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart` с расширением действующих сценариев обновления условия.
  - **Зависимости:** 1.6 — полное состояние и ревизия обновления.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart`, `test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart`, `test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart`.
  - **Размер:** M.

- [ ] 1.16 Сохранять цвет в состоянии редактора при использовании нового командного контракта
  - **Критерии приёмки:**
    - Новый тег начинается с отсутствия цвета, существующий — с сохранённого цвета. Текущее редактирование названия не сбрасывает цвет, в том числе у тега после импорта или восстановления копии.
    - Состояния отправки, ошибки, повторного чтения подтверждённого результата и потребления события передают цвет без потерь. Редактор отправляет полное состояние одной командой и сохраняет действующие правила экранной сессии.
    - В этой фазе подготовлена передача состояния; элементы пользовательского выбора цвета не подключаются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/editor/tag_editor_view_model_test.dart test/tag/presentation/editor/tag_editor_page_test.dart` с цветным исходным тегом при изменении названия и отказе сохранения.
  - **Зависимости:** 1.6 — команда редактирования и чтение полного результата.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_editor_state.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.17 Предъявлять и диагностировать общее редактирование тега
  - **Критерии приёмки:**
    - Подтверждённое редактирование использует локализованное сообщение «Тег изменён» и соответствующую английскую строку. Исход без изменений и все существующие права предъявления сохраняются.
    - Проверки диагностики различают редактирование и его исходы через существующий безопасный контракт; названия, идентификаторы и содержимое графа в события не попадают. Новая поверхность результата и отдельная диагностика цвета не добавляются.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/graph/presentation/graph_operation_presenter_test.dart test/graph/data/drift_tag_diagnostics_test.dart`.
  - **Зависимости:** 1.4 — смысл общего редактирования в координаторе и диагностике.
  - **Предполагаемые файлы:** `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, два перечисленных тестовых файла; генерируемые файлы локализации.
  - **Размер:** M.

- [ ] 1.18 Подтвердить готовность первой фазы к подключению выбора и отображения цвета
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» первой фазы: единый контракт цвета подтверждён на границах данных, при повторном открытии, восстановлении, переносе и согласовании потребителей; действующие операции графа работоспособны.
    - Пакет не содержит реализации визуальной части второй фазы. Результаты проверок и путь к APK сообщены в сессии; ручная проверка устройства остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - Выполнить `mise run check` и `openspec validate add-tag-colors --strict --no-interactive`. После фиксации изменений выполнить `mise run codegen-check` на чистой рабочей копии, подтвердив воспроизводимость генерируемых файлов и эталона схемы.
    - Собрать `mise exec --no-deps -- flutter build apk --release` и предоставить `build/app/outputs/flutter-apk/app-release.apk`. После изменения Dart-кода при наличии запущенного приложения выполнить hot reload или restart и проверить `get_runtime_errors`; запускать устройство или эмулятор для этого не требуется.
    - Сообщить оставшиеся ручные проверки первой фазы: работа прежнего редактирования названия с сохранением цвета, восстановление копии и перенос графа с новым форматом на согласованном наборе тестовых данных. Завершение этого пакета означает завершение первой фазы; перед реализацией второй требуется отдельный пакет задач по плану.
  - **Зависимости:** 1.1–1.17.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.
