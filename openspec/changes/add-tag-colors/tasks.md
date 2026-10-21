Пакет относится только к первой фазе [плана](plan.md). Поведение задают спецификации [тегов](specs/tag-management/spec.md), [экспорта и импорта](specs/graph-export-import/spec.md) и [резервных копий](specs/graph-backups/spec.md); контракты и границы — [дизайн](design.md) и [ADR-обзор](adr.md). Компоненты выбора и визуальное отображение цвета входят во вторую фазу.

Задачи 1.1 и 1.4 устанавливают общие контракты для последующих потребителей. Обязательная механическая адаптация мест сборки и исчерпывающих обработчиков входит в соответствующий переход контракта. Последующие задачи проверяют поведение конкретных потребителей на реальном пути данных. Проверки используют небольшие фикстуры без измерений времени и расширенных тайм-аутов.

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

- [ ] 1.4 Сохранять название и цвет одной подтверждаемой операцией редактирования
  - **Критерии приёмки:**
    - `CreateTag` принимает явный nullable-цвет; `UpdateTag`, `TagUpdated` и `TagUpdatedChange` заменяют прежний контракт переименования по решению 2 дизайна. Координатор сохраняет `ExistingTagKey`, последовательность операций и завершение принятой команды независимо от экрана; все вызывающие стороны и обработчики переведены на новый контракт.
    - Репозиторий сохраняет оба поля атомарно, включая явный SQL `NULL`. Изменение только цвета подтверждается, конфликт названия откатывает оба поля, а совпадение обоих полей не создаёт записи, пакета фактов или новой ревизии.
    - Событие редактирования допускает различие цвета при прежнем названии и сохраняет проверку идентичности. Назначения, порядки и данные помеченных намерений остаются прежними; категория операции и диагностики обозначает редактирование.
    - Существующая проверка перезапуска в `test/graph/data/file_backed_tag_durability_test.dart`, подтверждающая сценарий «Теги сохраняются после полного перезапуска», учитывает цвет. Тег, созданный без цвета, после повторного открытия файловой БД остаётся без цвета. После подтверждённой правки только цвета на синий и следующего повторного открытия у тега синий цвет. Идентификаторы, назначения и порядок проверяются её прежними утверждениями без повторения; отдельный файл проверки не создаётся.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/application/tag_command_contract_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_graph_fact_log_write_test.dart test/graph/application/graph_command_coordinator_tag_test.dart`; `mise exec --no-deps -- flutter test --concurrency=1 test/graph/data/file_backed_tag_durability_test.dart` — проверка перезапуска и процесс `test/support/tag_operation_process_worker.dart`, переведённый на новый контракт; `mise exec --no-deps -- flutter analyze` для проверки всех потребителей заменённого контракта.
  - **Зависимости:** 1.1 — полное состояние тега; 1.3 — согласованные чтения и факты.
  - **Предполагаемые файлы:** `lib/src/tag/application/tag_command.dart`, `lib/src/tag/application/tag_result.dart`, `lib/src/tag/application/tag_change.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`, `test/graph/data/file_backed_tag_durability_test.dart`; механическая адаптация существующих обработчиков, тестовых репозиториев и вызовов команды.
  - **Размер:** M — один переход командного контракта с механической адаптацией потребителей.

- [ ] 1.5 Подтвердить сохранение цвета захватом фактов по независимой выгрузке БД
  - **Критерии приёмки:**
    - Независимая эталонная выгрузка БД читает фактический цвет тега; сравнение с состоянием, собранным из лога, обнаруживает потерю нового поля.
    - Существующая проверка полноты лога для команд тегов создаёт цветной и бесцветный теги, правит только цвет и возвращает «Без цвета». Состояние, собранное от позиции 0 и от промежуточного состояния, совпадает с выгрузкой. Проверки сборки состояния, сжатия и пересборки снимка цветом не расширяются: эти механизмы переносят `TagRecord` целиком через общий кодек.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_fact_log_completeness_test.dart`. Остальные потребители выгрузки до задачи 1.6 не создают цветных тегов, поэтому их результат не меняется.
  - **Зависимости:** 1.3 — захват фактов с цветом; 1.4 — правка только цвета.
  - **Предполагаемые файлы:** `test/support/graph_log_completeness_reference.dart`, `test/graph/data/drift_graph_fact_log_completeness_test.dart`.
  - **Размер:** S.

- [ ] 1.6 Воспроизводить цвет при атомарной замене графа
  - **Критерии приёмки:**
    - Вставка тега при замене переносит цвет из полного `TagRecord`, включая явное отсутствие цвета; назначения и порядок воспроизводятся по действующему контракту замены.
    - Существующие проверки успешной замены, отката и снимка замены учитывают цвета в исходном и новом графе; ошибки сохраняют прежнее полное состояние.
    - Один тег общего эталона файла версии 1 получает цвет, другой остаётся без цвета. Проверки, сравнивающие с эталоном прочитанные записи или выгрузку базы после замены и импорта, проходят с обоими тегами.
  - **Проверка:** `mise exec --no-deps -- flutter test test/graph/data/drift_graph_replacement_test.dart test/graph_snapshots/graph_replacement_snapshot_test.dart test/graph_format/graph_format_file_test.dart test/graph_snapshots/graph_import_snapshot_test.dart test/data_transfer/graph_import_test.dart test/app/graph_import_failures_app_flow_test.dart`.
  - **Зависимости:** 1.1 — новый формат; 1.2 — схема с цветом; 1.3 — чтение записей графа с цветом; 1.5 — выгрузка БД с фактическим цветом.
  - **Предполагаемые файлы:** `lib/src/graph/data/drift_personal_graph_repository_replacement.dart`, `test/graph/data/drift_graph_replacement_test.dart`, `test/graph_snapshots/graph_replacement_snapshot_test.dart`, `test/graph_format/golden/graph_format_v1.jsonl`, `test/graph_format/graph_format_file_test.dart`.
  - **Размер:** M.

- [ ] 1.7 Переносить выбранные цвета через настоящий файл экспорта и импорт
  - **Критерии приёмки:**
    - Существующая сквозная проверка сценария «Импорт экспорта воспроизводит граф» создаёт в исходной установке синий тег, назначенный сначала намерению А, затем намерению Б, и отдельный тег без цвета. После импорта в другую установку полное состояние графа совпадает с исходным, включая цвет одного тега и отсутствие цвета другого, а навигация по тегу показывает А раньше Б.
    - Проверки экспорта, записи состояния и разбора импортируемого файла цветом не расширяются: они используют уже проверенные кодек, сборку состояния и вставку при замене.
  - **Проверка:** `mise exec --no-deps -- flutter test test/app/graph_import_app_flow_test.dart`.
  - **Зависимости:** 1.4 — создание тега с цветом; 1.5 — выгрузка БД с фактическим цветом; 1.6 — вставка цвета при замене.
  - **Предполагаемые файлы:** `test/app/graph_import_app_flow_test.dart`.
  - **Размер:** S.

- [ ] 1.8 Согласовывать полный тег в каталоге, выборе и назначениях
  - **Критерии приёмки:**
    - Подтверждённая правка только цвета заменяет тег по идентификатору в загруженном каталоге, строках выбора и назначениях; признаки назначения и текущий выбор сохраняются.
    - Поздний снимок не возвращает прежний цвет; порядок строк, прокрутка и различие отказов записи и обновления сохраняются по действующему протоколу.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_view_model_test.dart test/tag/presentation/catalog/tag_catalog_snapshot_selection_test.dart test/tag/presentation/assignments/tag_assignments_view_model_test.dart`. Расширить существующие примеры согласования изменением без переименования.
  - **Зависимости:** 1.3 — снимки каталога и назначений с цветом; 1.4 — подтверждённое обновление полного тега.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart`, `lib/src/tag/presentation/assignments/tag_assignments_view_model.dart`, три перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.9 Учитывать изменение только цвета в наблюдении и навигации по тегу
  - **Критерии приёмки:**
    - Сравнения наблюдаемого тега и данных страниц учитывают цвет вместе с названием, поэтому новое состояние не пропускается при прежнем названии.
    - Подтверждённый цвет сохраняется при перестановке ответа страницы и наблюдения; идентичность выбранного тега, охват и порядок результатов остаются прежними.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/navigation/tag_navigation_view_model_test.dart test/tag/presentation/navigation/tag_navigation_page_test.dart` с расширением существующих сценариев запоздалых ответов.
  - **Зависимости:** 1.3 — полные снимки; 1.4 — событие обновления.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/navigation/tag_navigation_view_model.dart`, `test/tag/presentation/navigation/tag_navigation_view_model_test.dart`, существующие сценарии в `test/tag/presentation/navigation/` при необходимости.
  - **Размер:** M.

- [ ] 1.10 Передавать подтверждённый цвет в краткие данные намерений и их потребителей
  - **Критерии приёмки:**
    - Обновление тега заменяет его полное состояние в кратких данных по идентификатору, сохраняя состав и порядок тегов, временные отметки намерений, соответствие фильтру и порядок выдачи.
    - Существующие потребители кратких данных в поиске, подробностях, связях и дневных выборах получают цвет через действующее согласование; поздний ответ не отменяет обновление.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart test/graph/presentation/tag_package_catalog_consumers_test.dart`. Общую проверку потребителей расширить цветом вместо отдельных копий сценария для каждого экрана.
  - **Зависимости:** 1.3 — чтения полного состояния; 1.4 — пакет обновления тега.
  - **Предполагаемые файлы:** `lib/src/intention/application/intention_catalog.dart`, `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart`, `test/intention/presentation/catalog/intention_catalog_tag_change_reconciliation_test.dart`, `test/graph/presentation/tag_package_catalog_consumers_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M.

- [ ] 1.11 Сохранять актуальный цвет выбранных тегов в черновике намерения
  - **Критерии приёмки:**
    - Собственное представление тега черновика переносит типизированный цвет при добавлении, копировании и смене статуса; наблюдение принимает обновление цвета при прежнем названии.
    - Цвет обновляется по идентификатору без изменения выбранного набора черновика или постоянных назначений. Существующие состояния недоступного и удалённого тега сохраняют действующую семантику.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/tag/presentation/catalog/tag_catalog_draft_session_test.dart` с изменением только цвета уже выбранного тега.
  - **Зависимости:** 1.3 — наблюдение полного тега; 1.4 — событие редактирования.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.12 Переносить цвет в состояния условий фильтра намерений
  - **Критерии приёмки:**
    - Модели условия и внутренней записи хранят типизированный цвет, учитывают его в равенстве и переносят при копировании, повторном чтении и подтверждённом обновлении.
    - Правка только цвета не меняет идентификатор и надобность условия, набор совпадений и порядок выдачи; старое чтение не возвращает прежнее состояние.
  - **Проверка:** `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart` с расширением действующих сценариев обновления условия.
  - **Зависимости:** 1.3 — полное состояние; 1.4 — ревизия обновления.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart`, `test/intention/presentation/catalog/intention_tag_conditions_view_model_test.dart`, `test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart`.
  - **Размер:** M.

- [ ] 1.13 Сохранять цвет в состоянии редактора при использовании нового командного контракта
  - **Критерии приёмки:**
    - Новый тег начинается с отсутствия цвета, существующий — с сохранённого цвета. Текущее редактирование названия не сбрасывает цвет, в том числе у тега после импорта или восстановления копии.
    - Состояния отправки, ошибки, повторного чтения подтверждённого результата и потребления события передают цвет без потерь. Редактор отправляет полное состояние одной командой и сохраняет действующие правила экранной сессии.
    - В этой фазе подготовлена передача состояния; элементы пользовательского выбора цвета не подключаются.
  - **Проверка:** `mise exec --no-deps -- flutter test test/tag/presentation/editor/tag_editor_view_model_test.dart test/tag/presentation/editor/tag_editor_page_test.dart` с цветным исходным тегом при изменении названия и отказе сохранения.
  - **Зависимости:** 1.3 — чтение полного результата; 1.4 — команда редактирования.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_editor_state.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart`, два перечисленных тестовых файла.
  - **Размер:** M.

- [ ] 1.14 Предъявлять и диагностировать общее редактирование тега
  - **Критерии приёмки:**
    - Подтверждённое редактирование использует локализованное сообщение «Тег изменён» и соответствующую английскую строку. Исход без изменений и все существующие права предъявления сохраняются.
    - Проверки диагностики различают редактирование и его исходы через существующий безопасный контракт; названия, идентификаторы и содержимое графа в события не попадают. Новая поверхность результата и отдельная диагностика цвета не добавляются.
  - **Проверка:** `mise run codegen`; `mise exec --no-deps -- flutter test test/graph/presentation/graph_operation_presenter_test.dart test/graph/data/drift_tag_diagnostics_test.dart`.
  - **Зависимости:** 1.4 — смысл общего редактирования в координаторе и диагностике.
  - **Предполагаемые файлы:** `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, два перечисленных тестовых файла; генерируемые файлы локализации.
  - **Размер:** M.

- [ ] 1.15 Подтвердить готовность первой фазы к подключению выбора и отображения цвета
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
