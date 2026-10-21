Файл содержит пакеты задач по фазам [плана](plan.md). Поведение задают спецификации [тегов](specs/tag-management/spec.md), [экспорта и импорта](specs/graph-export-import/spec.md) и [резервных копий](specs/graph-backups/spec.md); контракты и границы — [дизайн](design.md) и [ADR-обзор](adr.md).

В пакете первой фазы задачи 1.1 и 1.4 устанавливают общие контракты для последующих потребителей. Обязательная механическая адаптация мест сборки и исчерпывающих обработчиков входит в соответствующий переход контракта. Последующие задачи этого пакета проверяют поведение конкретных потребителей на реальном пути данных. Проверки используют небольшие фикстуры без измерений времени и расширенных тайм-аутов.

## Phase 1: Цвет сохраняется как полное состояние тега

- [x] 1.1 Сделать цвет явной частью тега и общего формата графа
  - **Критерии приёмки:**
    - `TagColor` задаёт девять вариантов с устойчивыми кодами по решению 1 дизайна; `Tag.color` — обязательный параметр типа `TagColor?`. Все места сборки явно передают отсутствие цвета либо сохраняют цвет исходного тега при копировании.
    - Общий кодек файла, снимка и пакета фактов записывает обязательное поле `color` после `name`; `null` означает «Без цвета». Отсутствующее поле, неверный тип и неизвестный код дают существующий отказ повреждения формата.
    - Эталон пакета версии 1 и встроенные примеры проверок кодека содержат цветной и бесцветный теги. В общем эталоне файла версии 1 и во всех рукописных записях формата, включая снимок замены в `test/app/navigation/app_shell_graph_generation_test.dart`, у тегов поле `color` равно `null`: база ещё не хранит и не вставляет цвет, поэтому цветной тег в эталон файла добавляет задача 1.6. Номер неопубликованного формата и пустая цепочка повышения сохраняются; совместимость со старым представлением не добавляется.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/domain test/tag/application/tag_read_contract_test.dart test/graph_format test/graph_snapshots/graph_import_snapshot_test.dart test/graph/data/drift_graph_replacement_test.dart test/data_transfer/graph_import_test.dart test/app/graph_import_failures_app_flow_test.dart test/app/navigation/app_shell_graph_generation_test.dart` — проверки тега, его контракта чтения и кодека, а также потребители эталона файла и рукописного снимка, сравнивающие записи или выгрузку базы с файлом; `mise exec --no-deps -- flutter analyze` для проверки обязательной адаптации вызовов.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/tag/domain/tag_color.dart` (новый), `lib/src/tag/domain/tag.dart`, `lib/src/graph_format/graph_format_codec.dart`, `test/graph_format/graph_format_codec_test.dart`, `test/graph_format/graph_format_file_test.dart`, оба эталона в `test/graph_format/golden/`, `test/app/navigation/app_shell_graph_generation_test.dart`; механические изменения существующих конструкторов в коде, тестах и бенчмарках.
  - **Размер:** M — один переход общего контракта с механической адаптацией вызовов.

- [x] 1.2 Хранить цвет в новой базовой схеме БД 4
  - **Критерии приёмки:**
    - Столбец цвета допускает только SQL `NULL` и девять кодов; существующие ограничения идентичности, уникальности названия и назначений сохраняются.
    - Базовая версия схемы БД — 4 по разделу «Migration Plan» дизайна: новая установка создаёт её одним шагом, генерируемое представление и эталон `drift_schema_v4.json` согласованы, а эталон `drift_schema_v3.json` удалён. Миграции прежних неопубликованных данных и автоматическое пересоздание хранилища не добавляются.
    - Хранилище прежней тестовой сборки с маркером 3 bootstrap классифицирует как повреждение и не изменяет, как хранилища маркеров 1 и 2.
    - Раздел `README.md` «Local data before launch and rollback» описывает базовую схему 4. В нём сказано, что данные установок со схемами 1–3 вместе со снимками, логом и копиями очищаются вручную перед первым запуском новой сборки, а та же очистка нужна перед откатом к любой сборке без схемы 4.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/data/local/tag_schema_test.dart test/data/local/app_database_schema_test.dart test/data/local/bootstrap/local_data_bootstrap_test.dart test/data/local/migrations/migration_test.dart test/data/local/migrations/fault_injection_test.dart`; `mise exec --no-deps -- flutter test --concurrency=1 test/data/local/migrations/file_backed_migration_test.dart` — потребители номера текущей версии схемы.
  - **Зависимости:** 1.1 — согласованные коды цвета.
  - **Предполагаемые файлы:** `lib/src/data/local/schema/tag_schema.drift`, `lib/src/data/local/app_database.dart`, `lib/src/data/local/app_database.g.dart`, `lib/src/data/local/migrations/migration_strategy.dart`, `drift_schemas/drift_schema_v4.json` (новый), `drift_schemas/drift_schema_v3.json` (удаляется), `test/data/local/tag_schema_test.dart`, `test/data/local/app_database_schema_test.dart`, `test/data/local/bootstrap/local_data_bootstrap_test.dart`, `README.md`.
  - **Размер:** M.

- [x] 1.3 Передавать цвет через все чтения тега и захват фактов
  - **Критерии приёмки:**
    - Общий декодер различает отсутствующий столбец и SQL `NULL`, преобразует допустимый код в `TagColor` и использует `StoredGraphCorruption` для некорректного представления.
    - Каталог, выбор, назначения, наблюдение тега, навигация, краткие данные намерений и чтение результата команды возвращают полный тег с цветом. Все использующие общий декодер проекции обновлены согласованно.
    - Порционное чтение записей графа и существующий захват фактов включают тот же цвет; изменение цвета использует действующий триггер обновления тега.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_tag_read_test.dart test/graph/data/drift_tag_assignment_read_test.dart test/graph/data/drift_tagged_entities_read_test.dart test/graph/data/graph_fact_capture_test.dart test/graph/data/drift_graph_fact_log_access_test.dart`. Проверка отсутствующего столбца проходит через общий декодер, а проверки чтений используют цветной тег.
  - **Зависимости:** 1.1 — тип и формат; 1.2 — схема с цветом.
  - **Предполагаемые файлы:** `lib/src/graph/data/stored_graph_rows.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart`, `lib/src/graph/data/drift_personal_graph_repository_fact_log.dart`, `lib/src/graph/data/graph_fact_capture.dart`; перечисленные проверки чтений.
  - **Размер:** M — общий декодер и согласованное расширение его проекций.

- [x] 1.4 Сохранять название и цвет одной подтверждаемой операцией редактирования
  - **Критерии приёмки:**
    - `CreateTag` принимает явный nullable-цвет; `UpdateTag`, `TagUpdated` и `TagUpdatedChange` заменяют прежний контракт переименования по решению 2 дизайна. Координатор сохраняет `ExistingTagKey`, последовательность операций и завершение принятой команды независимо от экрана; все вызывающие стороны и обработчики переведены на новый контракт.
    - Репозиторий сохраняет оба поля атомарно, включая явный SQL `NULL`. Изменение только цвета подтверждается, конфликт названия откатывает оба поля, а совпадение обоих полей не создаёт записи, пакета фактов или новой ревизии.
    - Событие редактирования допускает различие цвета при прежнем названии и сохраняет проверку идентичности. Назначения, порядки и данные помеченных намерений остаются прежними; категория операции и диагностики обозначает редактирование.
    - Существующая проверка перезапуска в `test/graph/data/file_backed_tag_durability_test.dart`, подтверждающая сценарий «Теги сохраняются после полного перезапуска», учитывает цвет. Тег, созданный без цвета, после повторного открытия файловой БД остаётся без цвета. После подтверждённой правки только цвета на синий и следующего повторного открытия у тега синий цвет. Идентификаторы, назначения и порядок проверяются её прежними утверждениями без повторения; отдельный файл проверки не создаётся.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/application/tag_command_contract_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_graph_fact_log_write_test.dart test/graph/application/graph_command_coordinator_tag_test.dart`; `mise exec --no-deps -- flutter test --concurrency=1 test/graph/data/file_backed_tag_durability_test.dart` — проверка перезапуска и процесс `test/support/tag_operation_process_worker.dart`, переведённый на новый контракт; `mise exec --no-deps -- flutter analyze` для проверки всех потребителей заменённого контракта.
  - **Зависимости:** 1.1 — полное состояние тега; 1.3 — согласованные чтения и факты.
  - **Предполагаемые файлы:** `lib/src/tag/application/tag_command.dart`, `lib/src/tag/application/tag_result.dart`, `lib/src/tag/application/tag_change.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`, `test/graph/data/file_backed_tag_durability_test.dart`; механическая адаптация существующих обработчиков, тестовых репозиториев и вызовов команды.
  - **Размер:** M — один переход командного контракта с механической адаптацией потребителей.

- [x] 1.5 Подтвердить сохранение цвета захватом фактов по независимой выгрузке БД
  - **Критерии приёмки:**
    - Независимая эталонная выгрузка БД читает фактический цвет тега; сравнение с состоянием, собранным из лога, обнаруживает потерю нового поля.
    - Существующая проверка полноты лога для команд тегов создаёт цветной и бесцветный теги, правит только цвет и возвращает «Без цвета». Состояние, собранное от позиции 0 и от промежуточного состояния, совпадает с выгрузкой. Проверки сборки состояния, сжатия и пересборки снимка цветом не расширяются: эти механизмы переносят `TagRecord` целиком через общий кодек.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_fact_log_completeness_test.dart`. Остальные потребители выгрузки до задачи 1.6 не создают цветных тегов, поэтому их результат не меняется.
  - **Зависимости:** 1.3 — захват фактов с цветом; 1.4 — правка только цвета.
  - **Предполагаемые файлы:** `test/support/graph_log_completeness_reference.dart`, `test/graph/data/drift_graph_fact_log_completeness_test.dart`.
  - **Размер:** S.

- [x] 1.6 Воспроизводить цвет при атомарной замене графа
  - **Критерии приёмки:**
    - Вставка тега при замене переносит цвет из полного `TagRecord`, включая явное отсутствие цвета; назначения и порядок воспроизводятся по действующему контракту замены.
    - Существующие проверки успешной замены, отката и снимка замены учитывают цвета в исходном и новом графе; ошибки сохраняют прежнее полное состояние.
    - Один тег общего эталона файла версии 1 получает цвет, другой остаётся без цвета. Проверки, сравнивающие с эталоном прочитанные записи или выгрузку базы после замены и импорта, проходят с обоими тегами.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_replacement_test.dart test/graph_snapshots/graph_replacement_snapshot_test.dart test/graph_format/graph_format_file_test.dart test/graph_snapshots/graph_import_snapshot_test.dart test/data_transfer/graph_import_test.dart test/app/graph_import_failures_app_flow_test.dart`.
  - **Зависимости:** 1.1 — новый формат; 1.2 — схема с цветом; 1.3 — чтение записей графа с цветом; 1.5 — выгрузка БД с фактическим цветом.
  - **Предполагаемые файлы:** `lib/src/graph/data/drift_personal_graph_repository_replacement.dart`, `test/graph/data/drift_graph_replacement_test.dart`, `test/graph_snapshots/graph_replacement_snapshot_test.dart`, `test/graph_format/golden/graph_format_v1.jsonl`, `test/graph_format/graph_format_file_test.dart`.
  - **Размер:** M.

- [x] 1.7 Переносить выбранные цвета через настоящий файл экспорта и импорт
  - **Критерии приёмки:**
    - Существующая сквозная проверка сценария «Импорт экспорта воспроизводит граф» создаёт в исходной установке синий тег, назначенный сначала намерению А, затем намерению Б, и отдельный тег без цвета. После импорта в другую установку полное состояние графа совпадает с исходным, включая цвет одного тега и отсутствие цвета другого, а навигация по тегу показывает А раньше Б.
    - Проверки экспорта, записи состояния и разбора импортируемого файла цветом не расширяются: они используют уже проверенные кодек, сборку состояния и вставку при замене.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app/graph_import_app_flow_test.dart`.
  - **Зависимости:** 1.4 — создание тега с цветом; 1.5 — выгрузка БД с фактическим цветом; 1.6 — вставка цвета при замене.
  - **Предполагаемые файлы:** `test/app/graph_import_app_flow_test.dart`.
  - **Размер:** S.

- [x] 1.8 Согласовывать полный тег в каталоге, выборе и назначениях
  - **Критерии приёмки:**
    - Подтверждённая правка только цвета заменяет тег по идентификатору в загруженном каталоге, строках выбора и назначениях; признаки назначения и текущий выбор сохраняются.
    - Поздний снимок не возвращает прежний цвет; порядок строк, прокрутка и различие отказов записи и обновления сохраняются по действующему протоколу.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_view_model_test.dart test/tag/presentation/catalog/tag_catalog_snapshot_selection_test.dart test/tag/presentation/assignments/tag_assignments_view_model_test.dart`. Расширить существующие примеры согласования изменением без переименования.
  - **Зависимости:** 1.3 — снимки каталога и назначений с цветом; 1.4 — подтверждённое обновление полного тега.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart`, `lib/src/tag/presentation/assignments/tag_assignments_view_model.dart`, три перечисленных тестовых файла.
  - **Размер:** M.

- [x] 1.9 Учитывать изменение только цвета в наблюдении и навигации по тегу
  - **Критерии приёмки:**
    - Сравнения наблюдаемого тега и данных страниц учитывают цвет вместе с названием, поэтому новое состояние не пропускается при прежнем названии.
    - Подтверждённый цвет сохраняется при перестановке ответа страницы и наблюдения; идентичность выбранного тега, охват и порядок результатов остаются прежними.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/navigation/tag_navigation_view_model_test.dart test/tag/presentation/navigation/tag_navigation_page_test.dart` с расширением существующих сценариев запоздалых ответов.
  - **Зависимости:** 1.3 — полные снимки; 1.4 — событие обновления.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/navigation/tag_navigation_view_model.dart`, `test/tag/presentation/navigation/tag_navigation_view_model_test.dart`, существующие сценарии в `test/tag/presentation/navigation/` при необходимости.
  - **Размер:** M.

- [x] 1.10 Передавать подтверждённый цвет в краткие данные намерений и их потребителей
  - **Критерии приёмки:**
    - Обновление тега заменяет его полное состояние в кратких данных по идентификатору, сохраняя состав и порядок тегов, временные отметки намерений, соответствие фильтру и порядок выдачи.
    - Существующие потребители кратких данных в поиске, подробностях, связях и дневных выборах получают цвет через действующее согласование; поздний ответ не отменяет обновление.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart test/graph/presentation/tag_package_catalog_consumers_test.dart`. Общую проверку потребителей расширить цветом вместо отдельных копий сценария для каждого экрана.
  - **Зависимости:** 1.3 — чтения полного состояния; 1.4 — пакет обновления тега.
  - **Предполагаемые файлы:** `lib/src/intention/application/intention_catalog.dart`, `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart`, `test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart`, `test/graph/presentation/tag_package_catalog_consumers_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M.

- [x] 1.11 Сохранять актуальный цвет выбранных тегов в черновике намерения
  - **Критерии приёмки:**
    - Собственное представление тега черновика переносит типизированный цвет при добавлении, копировании и смене статуса; наблюдение принимает обновление цвета при прежнем названии.
    - Цвет обновляется по идентификатору без изменения выбранного набора черновика или постоянных назначений. Существующие состояния недоступного и удалённого тега сохраняют действующую семантику.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/tag/presentation/catalog/tag_catalog_draft_session_test.dart` с изменением только цвета уже выбранного тега.
  - **Зависимости:** 1.3 — наблюдение полного тега; 1.4 — событие редактирования.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [x] 1.12 Переносить цвет в состояния условий фильтра намерений
  - **Критерии приёмки:**
    - Модели условия и внутренней записи хранят типизированный цвет, учитывают его в равенстве и переносят при копировании, повторном чтении и подтверждённом обновлении.
    - Правка только цвета не меняет идентификатор и надобность условия, набор совпадений и порядок выдачи; старое чтение не возвращает прежнее состояние.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart` с расширением действующих сценариев обновления условия.
  - **Зависимости:** 1.3 — полное состояние; 1.4 — ревизия обновления.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart`, `test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart`, `test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart`.
  - **Размер:** M.

- [x] 1.13 Сохранять цвет в состоянии редактора при использовании нового командного контракта
  - **Критерии приёмки:**
    - Новый тег начинается с отсутствия цвета, существующий — с сохранённого цвета. Текущее редактирование названия не сбрасывает цвет, в том числе у тега после импорта или восстановления копии.
    - Состояния отправки, ошибки, повторного чтения подтверждённого результата и потребления события передают цвет без потерь. Редактор отправляет полное состояние одной командой и сохраняет действующие правила экранной сессии.
    - В этой фазе подготовлена передача состояния; элементы пользовательского выбора цвета не подключаются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/editor/tag_editor_view_model_test.dart test/tag/presentation/editor/tag_editor_page_test.dart` с цветным исходным тегом при изменении названия и отказе сохранения.
  - **Зависимости:** 1.3 — чтение полного результата; 1.4 — команда редактирования.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_editor_state.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [x] 1.14 Предъявлять и диагностировать общее редактирование тега
  - **Критерии приёмки:**
    - Подтверждённое редактирование использует локализованное сообщение «Тег изменён» и соответствующую английскую строку. Исход без изменений и все существующие права предъявления сохраняются.
    - Проверки диагностики различают редактирование и его исходы через существующий безопасный контракт; названия, идентификаторы и содержимое графа в события не попадают. Новая поверхность результата и отдельная диагностика цвета не добавляются.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/graph/presentation/graph_operation_presenter_test.dart test/graph/data/drift_tag_diagnostics_test.dart`.
  - **Зависимости:** 1.4 — смысл общего редактирования в координаторе и диагностике.
  - **Предполагаемые файлы:** `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, два перечисленных тестовых файла; генерируемые файлы локализации.
  - **Размер:** M.

- [x] 1.15 Подтвердить готовность первой фазы к подключению выбора и отображения цвета
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» первой фазы: единый контракт цвета подтверждён на границах данных — в схеме, чтениях, захвате фактов, общем формате и замене графа, — при повторном открытии, сквозном переносе и согласовании потребителей; действующие операции графа работоспособны.
    - Пакет не содержит реализации визуальной части второй фазы. Результаты проверок и путь к APK сообщены в сессии; ручная проверка устройства остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - Выполнить `mise run check` и `openspec validate add-tag-colors --strict --no-interactive`. После фиксации изменений выполнить `mise run codegen-check` на чистой рабочей копии, подтвердив воспроизводимость генерируемых файлов и эталона схемы.
    - Собрать `mise exec --no-deps -- flutter build apk --release` и предоставить `build/app/outputs/flutter-apk/app-release.apk`. После изменения Dart-кода при наличии запущенного приложения выполнить hot reload или restart и проверить `get_runtime_errors`; запускать устройство или эмулятор для этого не требуется.
    - Сообщить оставшиеся ручные проверки первой фазы: работа прежнего редактирования названия с сохранением цвета, восстановление копии и перенос графа с новым форматом на установке, данные которой очищены по README. Завершение этого пакета означает завершение первой фазы; перед реализацией второй требуется отдельный пакет задач по плану.
  - **Зависимости:** 1.1–1.14.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

## Phase 2: Пользователь выбирает и видит цвет общего тега

- [ ] 2.1 Добавить в дизайн-систему точку цвета тега `TagDot` с визуальными вариантами `DoableTagColor`
  - **Критерии приёмки:**
    - По решению 6 [дизайна](design.md) и [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) перечисление `DoableTagColor` задаёт девять вариантов в порядке палитры, без сериализации и предметных правил; отсутствие варианта означает «Без цвета». Варианты сопоставлены токенам `tag-*` в одном месте модуля, общем для точки и выбора цвета задачи 2.3.
    - `TagDot` получает вариант или его отсутствие и размер из закрытого набора 7, 8 и 10. Цветной вариант — круг с заливкой токеном действующей темы, «Без цвета» — кольцо толщиной 1,5 цвета `grip` без заливки. Без расширения `DoableColors` в теме компонент берёт палитру по яркости темы, как `OptionRow` и `Sheet`, встраиваемые в существующие экраны.
    - Точка не создаёт узла экранного диктора.
  - **Проверка:** `mise exec --no-deps -- flutter test test/design_system/tag_dot_test.dart`. Новая проверка компонента: в светлой и тёмной темах цветной вариант залит своим токеном, «Без цвета» — кольцо `grip` без заливки, размер совпадает с заданным, узла семантики нет. Сопоставление всех вариантов с токенами проверяется одной проверкой по именам, без отдельного сценария на каждый оттенок.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/tag_dot.dart` (новый), `test/design_system/tag_dot_test.dart` (новый).
  - **Размер:** S.

- [ ] 2.2 Показывать цвет тега точкой в каталоге и выборе тегов
  - **Критерии приёмки:**
    - Адаптер модуля представления тегов исчерпывающе переводит `TagColor?` в `DoableTagColor?`; предметный тип в дизайн-систему не передаётся.
    - `TagDot` размера 10 стоит перед названием в строках каталога при просмотре, назначении намерению и добавлении в черновик, в строке выбранного тега вне загруженного снимка и в области выбранного тега, скрытого поиском. Название сохраняет обычный цвет текста.
    - Признаки выбора, назначения и включения в черновик, действия строк и их доступные подписи не меняются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/tag_color_presentation_test.dart test/tag/presentation/catalog/ test/tag/presentation/tag_accessibility_test.dart`. Новая проверка адаптера одной проверкой по именам сопоставляет все значения `TagColor` и отсутствие цвета. Проверка страницы каталога воспроизводит сценарий «Цветной и бесцветный теги в каталоге»: перед «Дом» точка `tag-blue` действующей темы, перед «Работа» — кольцо `grip`, названия обоих тегов одного обычного цвета текста. Существующие проверки семантики строк проходят без изменений.
  - **Зависимости:** 2.1 — `TagDot`; 1.8 — полный тег в каталоге, выборе и назначениях.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/tag_color_presentation.dart` (новый, название рабочее), `lib/src/tag/presentation/catalog/tag_catalog_view.dart`, `test/tag/presentation/tag_color_presentation_test.dart` (новый, название рабочее), `test/tag/presentation/catalog/tag_catalog_page_test.dart`.
  - **Размер:** M.

- [ ] 2.3 Добавить в дизайн-систему выбор цвета тега `TagColorPicker`
  - **Критерии приёмки:**
    - По решению 6 [дизайна](design.md) и правилам `context/doable-design-system/components/TagColorPicker/README.md` компонент получает выбранный вариант `DoableTagColor?`, готовые подписи и обработчик выбора. Подписи — это заголовок, названия десяти вариантов и доступное название группы образцов; названия передаются так, что пропустить вариант нельзя, например функцией от варианта, а не словарём. Провайдеров, `Tag`, `TagColor`, маршрутизатора и `AppLocalizations` в компоненте нет.
    - Шапка показывает заголовок и название выбранного варианта и при крупном тексте растёт, не обрезая подписи. Под ней — десять образцов в сетке 5×2: первый — «Без цвета» в виде пустого кольца `grip`, за ним девять цветов по общему сопоставлению задачи 2.1. Выбранный образец отмечен галочкой и внешним кольцом, поэтому выбор различим без цвета; повторное нажатие оставляет его выбранным.
    - Каждый образец — кнопка экранного диктора со своим названием и состоянием выбранности; область нажатия — вся ячейка высотой не меньше `tap-min`. Смену названия объявляет владелец формы, а не компонент.
  - **Проверка:** `mise exec --no-deps -- flutter test test/design_system/tag_color_picker_test.dart`. Новая проверка компонента: десять кнопок с переданными названиями, из них выбрана ровно одна; нажатие сообщает вариант обработчику; в светлой и тёмной темах образцы залиты своими токенами, а отметка выбора видна; область нажатия не меньше `tap-min`; при масштабе текста 2,5 шапка не обрезает подписи.
  - **Зависимости:** 2.1 — `DoableTagColor` и сопоставление с токенами.
  - **Предполагаемые файлы:** `lib/src/design_system/components/tag_color_picker.dart` (новый), `test/design_system/tag_color_picker_test.dart` (новый).
  - **Размер:** S.

- [ ] 2.4 Выбирать цвет тега в форме создания и изменения
  - **Критерии приёмки:**
    - Под полем названия форма показывает `TagColorPicker`, а в начале поля — `TagDot` размера 10 выбранного варианта. Новый тег начинается с «Без цвета», существующий — с сохранённого цвета. Выбор сразу меняет точку поля, название в шапке и отмеченный образец, но только в состоянии формы: команда отправляется лишь при сохранении, а отмена оставляет тег прежним.
    - Адаптер представления тегов переводит выбор обратно в `TagColor?` и даёт названия «Без цвета», «Коричневый», «Оранжевый», «Оливковый», «Зелёный», «Бирюзовый», «Синий», «Сиреневый», «Фиолетовый» и «Розовый», заголовок «Цвет» и название группы «Цвет тега». По-английски это «No color», «Brown», «Orange», «Olive», «Green», «Teal», «Blue», «Violet», «Purple», «Pink», «Color» и «Tag color». Когда пользователь меняет выбор, форма объявляет экранному диктору название нового варианта; открытие формы ничего не объявляет.
    - Сохранение передаёт название и выбранный цвет одной командой по задаче 1.13, в том числе при правке только цвета и возврате к «Без цвета». После отказа, включая конфликт названия, форма показывает введённое название и прежний выбор цвета.
  - **Проверка:**
    - `mise run codegen`; `mise exec --no-deps -- flutter test test/tag/presentation/editor/ test/tag/presentation/tag_color_presentation_test.dart test/tag/presentation/tag_accessibility_test.dart test/app/localization/locale_resolution_test.dart`.
    - Расширить существующие проверки страницы редактора. Новая форма отмечает «Без цвета», форма синего тега — синий. Выбор синего меняет предварительный показ без команды, а отмена не меняет тег. Сохранение только цвета и возврат к «Без цвета» отправляют по одной команде с прежним названием. Сценарий «Конфликт названия не сохраняет выбранный цвет» оставляет в форме введённое название и зелёный выбор. В русской и английской локалях выбор показывает названия всех вариантов, а смена объявляется по сценарию «Выбор цвета доступен экранному диктору».
    - Проверку адаптера дополнить обратным сопоставлением всех вариантов.
  - **Зависимости:** 2.2 — адаптер и `TagDot`; 2.3 — `TagColorPicker`; 1.13 — цвет в состоянии и команде редактора.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_editor_page.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart`, `lib/src/tag/presentation/editor/tag_editor_state.dart`, адаптер задачи 2.2 и его проверка, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `test/tag/presentation/editor/tag_editor_page_test.dart`; генерируемые файлы локализации.
  - **Размер:** M — одна вертикальная правка формы; строки ARB и адаптер дополняются механически.

- [ ] 2.5 Называть форму существующего тега и открывающее её действие каталога изменением тега
  - **Критерии приёмки:**
    - Действие строки каталога называется «Изменить тег», форма существующего тега — «Изменение тега», её кнопка сохранения — «Сохранить»; по-английски — «Edit tag», «Edit tag» и «Save». Подписи формы создания не меняются, а описания этих строк в ARB говорят об изменении тега.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/tag/presentation/catalog/ test/tag/presentation/editor/ test/intention/presentation/catalog/tag_condition_picker_page_test.dart test/app/tag_app_lifecycle_test.dart test/app/tag_navigation_app_lifecycle_test.dart test/app/navigation/app_shell_pages_above_test.dart`. Существующие проверки, искавшие прежние подписи, переведены на новые.
  - **Зависимости:** 2.4 — форма с выбором цвета.
  - **Предполагаемые файлы:** `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, генерируемые файлы локализации; замена подписей в `test/tag/presentation/catalog/tag_catalog_page_test.dart`, `test/tag/presentation/catalog/tag_catalog_navigation_test.dart`, `test/intention/presentation/catalog/tag_condition_picker_page_test.dart`, `test/app/tag_app_lifecycle_test.dart`, `test/app/tag_navigation_app_lifecycle_test.dart` и `test/app/navigation/app_shell_page_matrix.dart`.
  - **Размер:** S — механическая замена подписей.

- [ ] 2.6 Показывать точки перед названиями в строке тегов результатов поиска намерений
  - **Критерии приёмки:**
    - Общий помощник модуля представления тегов ставит `TagDot` непосредственно перед каждым названием тега внутри локализованной фразы и не меняет её доступный текст. Строка результата выглядит как «Теги: ● Здоровье, ● Отдых»: точки размера 7, порядок кратких данных, полный состав, названия без преобразования. «Без тегов» не меняется.
    - Объединённая доступная подпись результата остаётся прежней, а у тегов нет отдельных узлов и действий. Каталог намерений, поиск действия и исходного намерения для дневного выбора и поиск участника связи получают точки через общее `IntentionSummaryView`; представления без строки тегов её не получают.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/intention_summary_view_test.dart test/intention/presentation/catalog/intention_catalog_page_test.dart test/intention/presentation/intention_tag_search_accessibility_test.dart test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart test/app/intention_tag_search_app_flow_test.dart test/app/intention_creation_sheet_integration_test.dart`. Проверка представления: у цветного тега точка, у бесцветного кольцо перед своим названием, доступная подпись совпадает с прежней. Проверки, искавшие строку тегов по точному тексту, переведены на поиск, не зависящий от точек.
  - **Зависимости:** 2.2 — адаптер и `TagDot`; 1.10 — подтверждённый цвет в кратких данных намерений.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/intention_summary_view.dart`, помощник рядом с адаптером задачи 2.2, `test/intention/presentation/intention_summary_view_test.dart`; правка поиска строки тегов в `test/intention/presentation/catalog/intention_catalog_page_test.dart`, `test/intention/presentation/intention_tag_search_accessibility_test.dart`, `test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart`, `test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart`, `test/app/intention_tag_search_app_flow_test.dart` и `test/app/intention_creation_sheet_integration_test.dart`.
  - **Размер:** M — помощник и одно представление; остальное — механическая правка поиска в проверках.

- [ ] 2.7 Показывать точку в назначениях тегов в подробностях намерения
  - **Критерии приёмки:**
    - Строка назначения показывает `TagDot` размера 8 перед названием. Переход к навигации, снятие назначения, их подписи и состояния не меняются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/assignments/ test/intention/presentation/details/intention_details_tags_test.dart test/tag/presentation/tag_accessibility_test.dart`. Дополнить проверку раздела назначений цветным и бесцветным тегами; существующие проверки семантики проходят без изменений.
  - **Зависимости:** 2.2 — адаптер и `TagDot`; 1.8 — полные назначения.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/assignments/tag_assignments_section.dart`, `test/tag/presentation/assignments/tag_assignments_section_test.dart`.
  - **Размер:** S.

- [ ] 2.8 Показывать точку перед названием в заголовке навигации по тегу
  - **Критерии приёмки:**
    - Через помощник задачи 2.6 заголовок показывает точку размера 10 непосредственно перед названием: «Тег: ● Дом», «Tag: ● Home». Экранный диктор по-прежнему получает заголовок «Тег: Дом».
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/navigation/ test/tag/presentation/tag_accessibility_test.dart test/tag/presentation/catalog/tag_catalog_navigation_test.dart test/app/tag_navigation_app_flow_test.dart test/app/tag_navigation_app_lifecycle_test.dart`. Проверить заголовок с цветным и бесцветным тегами: точка стоит перед названием, а доступный заголовок совпадает с прежним «Тег: Дом». Проверки, искавшие заголовок по точному тексту, переведены на поиск, не зависящий от точек. Отрицательные проверки в `tag_navigation_semantics_scenarios.dart` (заголовок исчезает после подтверждённого отсутствия тега) и в `tag_navigation_app_lifecycle_test.dart` (прежнее название не остаётся в заголовке после переименования) по-прежнему падают, если фраза показана. Остальные утверждения сценариев семантики и доступности навигации не меняются.
  - **Зависимости:** 2.6 — помощник фразы с точкой; 1.9 — полный тег навигации.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/navigation/tag_navigation_page.dart`, `test/tag/presentation/navigation/tag_navigation_page_test.dart`; правка поиска заголовка в `test/tag/presentation/navigation/tag_navigation_semantics_scenarios.dart`, `test/tag/presentation/tag_navigation_accessibility_scenarios.dart`, `test/tag/presentation/catalog/tag_catalog_navigation_test.dart`, `test/app/tag_navigation_app_flow_test.dart`, `test/app/tag_navigation_graph_lifecycle_scenarios.dart`, `test/app/tag_navigation_app_lifecycle_test.dart` и `test/app/tag_navigation_terminal_app_scenarios.dart`.
  - **Размер:** M — правка одного заголовка; остальное — механическая правка поиска в проверках.

- [ ] 2.9 Показывать точку у тегов черновика создания намерения
  - **Критерии приёмки:**
    - Элемент тега черновика получает цвет из `IntentionDraftTag` и показывает `TagDot` размера 8 перед названием. Состояния проверки, недоступности и удаления, зачёркивание, действия повтора и удаления из черновика и точные доступные подписи не меняются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/editor/`. Дополнить `test/intention/presentation/editor/intention_creation_tags_test.dart` цветным и бесцветным тегами; существующие точные подписи семантики проходят без изменений.
  - **Зависимости:** 2.2 — адаптер и `TagDot`; 1.11 — актуальный цвет в черновике.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/editor/intention_creation_tags.dart`, `test/intention/presentation/editor/intention_creation_tags_test.dart`.
  - **Размер:** S.

- [ ] 2.10 Показывать точку в условиях фильтра намерений
  - **Критерии приёмки:**
    - Через помощник задачи 2.6 отметка условия показывает после значка надобности точку размера 8 непосредственно перед названием: «● Дом», «не ● Дом», в том числе с пометкой удалённого тега. Значок надобности, переключение, снятие и доступные подписи условия не меняются; все четыре контекста поиска получают точку через общий раздел условий.
    - Строка выбора тега для условия показывает точку размера 10 перед названием; выделение строки и кнопки выбора требования не меняются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_tag_conditions_section_test.dart test/intention/presentation/catalog/tag_condition_picker_page_test.dart test/intention/presentation/intention_tag_search_accessibility_test.dart test/intention/presentation/catalog/intention_catalog_page_test.dart test/daily_choice/presentation/action_picker/daily_choice_action_picker_page_test.dart test/daily_choice/presentation/source_picker/daily_choice_source_picker_page_test.dart test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart test/app/intention_tag_search_app_flow_test.dart test/app/graph_import_app_flow_test.dart test/app/graph_restore_app_flow_test.dart test/app/navigation/app_shell_state_test.dart test/app/navigation/app_shell_graph_generation_test.dart`. Проверить цветной и бесцветный теги в обязательном и исключённом условиях и в строке выбора. Проверки, читавшие подпись условия по ключу `intention-tag-condition-label` как `Text.data`, переведены на чтение, не зависящее от точек. Сравнения подписей до и после перехода в `app_shell_state_test.dart` по-прежнему различают показанные названия. Существующие проверки доступных подписей условия проходят без изменений.
  - **Зависимости:** 2.6 — помощник фразы с точкой; 1.8 — полный тег в каталоге выбора; 1.12 — цвет в условиях фильтра.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/catalog/intention_tag_conditions_section.dart`, `lib/src/intention/presentation/catalog/tag_condition_picker_page.dart`, `test/intention/presentation/catalog/intention_tag_conditions_section_test.dart`, `test/intention/presentation/catalog/tag_condition_picker_page_test.dart`; правка чтения подписи условия в `test/intention/presentation/catalog/intention_catalog_page_test.dart`, `test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart`, `test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart`, `test/app/intention_tag_search_app_flow_test.dart`, `test/app/graph_import_app_flow_test.dart`, `test/app/graph_restore_app_flow_test.dart`, `test/app/navigation/app_shell_state_test.dart` и `test/app/navigation/app_shell_graph_generation_test.dart`.
  - **Размер:** M — раздел условий и строка выбора; остальное — механическая правка чтения подписи в проверках.

- [ ] 2.11 Подтвердить в приложении, что цвет, выбранный в форме, сохраняется и сразу виден в представлениях тега
  - **Критерии приёмки:**
    - На реальном хранилище приложения проходит сценарий «Изменение только цвета общего тега»: тег «Дом» без цвета назначен активному и архивированному намерениям, пользователь открывает изменение «Дом» из каталога, выбирает «Синий» и сохраняет.
    - Без перезапуска синюю точку показывают строка каталога тегов, строка результата в каталоге намерений, назначение в подробностях намерения и заголовок навигации по тегу. Название, идентификатор и оба назначения тега сохраняются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app/tag_app_flow_test.dart` — новый сценарий в существующем файле проверок потока тегов.
  - **Зависимости:** 2.2, 2.4–2.8.
  - **Предполагаемые файлы:** `test/app/tag_app_flow_test.dart`.
  - **Размер:** S.

- [ ] 2.12 Подтвердить готовность второй фазы к итоговой проверке изменения
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» второй фазы: автоматизированные проверки подтверждают сквозной путь от выбора цвета до сохранения и согласованного отображения, включая локализацию и доступность. Вместе с первой фазой обеспечено поведение спецификаций тегов, экспорта и импорта и резервных копий; изменение готово к итоговой проверке перед архивированием.
    - Результаты проверок и путь к APK сообщены в сессии. Ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - Выполнить `mise run check` и `mise exec --no-deps -- openspec validate add-tag-colors --strict --no-interactive`. После фиксации изменений выполнить `mise run codegen-check` на чистой рабочей копии.
    - Собрать `mise exec --no-deps -- flutter build apk --release` и предоставить `build/app/outputs/flutter-apk/app-release.apk`. После изменения Dart-кода при наличии запущенного приложения выполнить hot reload или restart и проверить `get_runtime_errors`; запускать устройство или эмулятор не требуется.
    - Сообщить оставшиеся ручные проверки: сверку точек и выбора цвета с макетами в светлой и тёмной темах, объявление TalkBack названия и выбранности цвета на русском и английском, выбор цвета при создании и изменении тега и его показ во всех местах на устройстве.
  - **Зависимости:** 2.1–2.11.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.
