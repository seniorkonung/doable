Файл содержит пакеты задач по фазам [плана](plan.md). Поведение задают [спецификации](specs/), технический подход — [дизайн](design.md), долговременные ограничения — ADR из [манифеста](adr.md); для этой фазы главное из них — [ADR-0039](../../../docs/adr/0039-keep-manual-tag-order-as-fractional-keys.md).

## Phase 1: Ручной порядок хранится и переносится вместе с тегом

- [x] 1.1 Ввести в модуле тегов значение места `TagPosition` с канонической формой, строгим разбором и генерацией ключа для размещения тега первым
  - **Критерии приёмки:**
    - `TagPosition` хранит строку ASCII в канонической форме дробного индекса base62 по решению 1 дизайна: целая часть с префиксом длины и дробная часть без завершающего нуля, без предела длины. `TagPosition.decode` возвращает закрытый результат по образцу `TagColor.decode` и отклоняет неканоническую строку, не исправляя её.
    - Чистая функция модуля тегов без внешней зависимости даёт начальный ключ для пустого каталога, а для любого ключа, который принимает `decode`, — допустимый ключ строго перед ним по сравнению кодовых единиц. Поэтому каноническая форма не содержит ключа, перед которым нельзя поставить другой.
    - Генерации после тега и между соседями в задаче нет: её добавляет фаза 3 вместе с перестановкой и дублированием.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/tag/domain/tag_position_test.dart`: канонические и отклоняемые строки — пустая, с посторонними символами, с неверным префиксом длины, с завершающим нулём дробной части; цепочка ключей перед первым от начального со сменой префикса длины; ключи у нижней границы целой части и ключи с дробной частью.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/tag/domain/tag_position.dart` (новый), `test/tag/domain/tag_position_test.dart` (новый).
  - **Размер:** S.

- [x] 1.2 Сделать место обязательной частью тега, строки `tags` и записи формата графа и ставить новый тег перед текущим первым
  - **Критерии приёмки:**
    - `Tag.position` — обязательное поле типа `TagPosition`. Текущая базовая схема получает столбец `tags.position TEXT NOT NULL UNIQUE` с `CHECK` на непустую строку из цифр и латинских букв по решению 3 дизайна; новой schema-функции нет. Общий декодер строк проверяет каноническую форму и даёт `StoredGraphCorruption`, а каждое чтение, которое собирает тег, выбирает место. Сортировка SQLite по столбцу на ключах разных регистров и длин совпадает с порядком их кодовых единиц.
    - Создание тега в транзакции записи вычисляет ключ перед местом текущего первого тега, а в пустом каталоге — начальный ключ. Оно меняет только строку нового тега: пакет фактов содержит один факт создания тега. `CreateTag` не получает размещения: в этой фазе тег создаётся только первым. Замена графа вставляет место из `TagRecord`.
    - Общий кодек файла, снимка и пакета фактов пишет обязательное поле `position` после `color` по решению 4 дизайна. Отсутствующее поле, неверный тип и неканонический ключ дают `GraphFormatCorruption`. Номер формата 1 и пустая цепочка повышения сохраняются, а эталоны файла и пакета версии 1 содержат места тегов.
    - Все места сборки тега, рукописные записи формата и вставки строк в `tags` в проверках, их поддержке и бенчмарках передают явные различные допустимые места; эталонная выгрузка БД читает фактическое место строки. Чтения сохраняют прежний порядок до задачи 1.5, номер версии схемы — до задачи 1.3.
  - **Проверка:**
    - `mise run codegen` и `mise exec --no-deps -- flutter analyze`.
    - `mise exec --no-deps -- flutter test test/tag/domain test/graph_format test/data/local/tag_schema_test.dart test/graph/data/drift_tag_read_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_graph_fact_log_write_test.dart` — ограничения и сортировка столбца, декодер строк, создание первым одним фактом, строгий кодек и эталоны.
    - `mise exec --no-deps -- flutter test test/graph/data/drift_graph_fact_log_completeness_test.dart test/graph/data/drift_graph_replacement_test.dart test/graph_snapshots test/data_transfer test/app/graph_import_app_flow_test.dart test/app/graph_restore_app_flow_test.dart` — выгрузка БД с местом подтверждает перенос через факты, снимки, копии, экспорт и импорт.
    - `mise run check:tests -- 0 1` и `mise run check:process-tests`: переход меняет фикстуры по всему набору.
    - `mise exec --no-deps -- flutter test --no-pub --plain-name 'длительность сжатия на профиле' benchmark/graph_log/graph_log_benchmark.dart` — пробный прогон с одним замером без сравнения с бюджетом: все бенчмарки графа заполняют базу той же адаптированной фикстурой.
  - **Зависимости:** 1.1 — значение места и ключ для размещения первым.
  - **Предполагаемые файлы:** `lib/src/tag/domain/tag.dart`, `lib/src/data/local/schema/tag_schema.drift`, `lib/src/graph/data/stored_graph_rows.dart`, `lib/src/graph/data/drift_personal_graph_repository_tag_commands.dart`, `lib/src/graph/data/drift_personal_graph_repository_replacement.dart`, `lib/src/graph_format/graph_format_codec.dart`; списки выбираемых столбцов в `lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart`, `lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart`, `lib/src/graph/data/drift_personal_graph_repository_fact_log.dart` и `lib/src/graph/data/graph_fact_capture.dart`; генерируемые `lib/src/data/local/app_database.g.dart` и `drift_schemas/drift_schema_v4.json`; `test/graph_format/golden/graph_format_v1.jsonl`, `test/graph_format/golden/graph_fact_package_v1.jsonl`, `test/graph_format/graph_format_codec_test.dart`, `test/graph_format/graph_format_file_test.dart`, `test/data/local/tag_schema_test.dart`, `test/graph/data/drift_tag_read_test.dart`, `test/graph/data/drift_tag_lifecycle_test.dart`, `test/graph/data/drift_graph_fact_log_write_test.dart`, `test/app/navigation/app_shell_graph_generation_test.dart`, `test/support/graph_log_completeness_reference.dart`, `test/support/tag_storage_fixture.dart`, `benchmark/support/graph_log_fixture.dart`; механическая адаптация остальных проверок, которые собирают `Tag` или вставляют строки в `tags`.
  - **Размер:** M — один переход общего контракта: обязательное место нельзя ввести по частям, поэтому механическая адаптация мест сборки и фикстур входит в задачу.

- [x] 1.3 Сделать схему 5 базовой, чтобы хранилище прежней тестовой сборки со схемой 4 распознавалось как повреждённое, а README описывал ручную очистку
  - **Критерии приёмки:**
    - Текущая версия схемы — 5 по разделу «Migration Plan» дизайна: новая установка создаёт её одним шагом, а эталон `drift_schema_v5.json` заменяет `drift_schema_v4.json`. Миграции прежних неопубликованных данных и автоматическое пересоздание хранилища не добавляются.
    - Хранилище с маркером 4 bootstrap классифицирует как повреждение локальных данных и не изменяет, как хранилища с маркерами 1–3.
    - Раздел `README.md` «Local data before launch and rollback» описывает базовую схему 5 с местом тега в ручном порядке. Данные установок со схемами 1–4 вместе с логом фактов, снимками и копиями очищаются вручную перед первым запуском новой сборки, а та же очистка нужна перед откатом к сборке без схемы 5.
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/data/local/bootstrap/local_data_bootstrap_test.dart test/data/local/app_database_schema_test.dart test/data/local/schema_verifier_test.dart test/data/local/migrations/migration_test.dart test/data/local/migrations/fault_injection_test.dart` и `mise exec --no-deps -- flutter test --concurrency=1 test/data/local/migrations/file_backed_migration_test.dart` — потребители номера текущей версии.
  - **Зависимости:** 1.2 — схема с местом тега.
  - **Предполагаемые файлы:** `lib/src/data/local/app_database.dart`, `lib/src/data/local/migrations/migration_strategy.dart`, `drift_schemas/drift_schema_v5.json` (новый), `drift_schemas/drift_schema_v4.json` (удаляется), `test/data/local/bootstrap/local_data_bootstrap_test.dart`, `README.md`.
  - **Размер:** S.

- [x] 1.4 Отклонять при чтении файл или снимок, в секции тегов которого повторяется место, как повреждение формата
  - **Критерии приёмки:**
    - Чтение записей файла или снимка с повторяющимся местом в секции тегов завершается `GraphFormatCorruption` до замены графа по решению 4 дизайна; ограничение `UNIQUE` при замене остаётся последней защитой.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph_format/graph_format_file_test.dart`.
  - **Зависимости:** 1.2 — место в записи формата.
  - **Предполагаемые файлы:** `lib/src/graph_format/graph_format_file.dart`, `test/graph_format/graph_format_file_test.dart`.
  - **Размер:** S.

- [x] 1.5 Упорядочивать теги в каталоге, назначениях и кратких данных намерений только по месту
  - **Критерии приёмки:**
    - Каталог в режимах просмотра и выбора, назначения намерения и теги намерений в кратких данных и снимках команд идут по месту тега. Теги намерения читаются соединением `tag_assignments` с `tags` в порядке `intention_id, tags.position` по решению 3 дизайна, поэтому очерёдность создания и назначения на порядок не влияет. Контракты чтений, которые называли порядок создания тегов, называют ручной порядок; порядок выбранных тегов черновика создания намерения задача не меняет.
    - Проверки чтений задают места, отличные от порядка создания и назначения, и подтверждают требование «Ручной порядок тегов»: созданный командой тег стоит первым в каталоге, а сценарий «Порядок тегов намерения не зависит от очерёдности назначения» выполняется для назначений и кратких данных. Проверки, ожидавшие порядок создания, ожидают ручной порядок.
    - Проверка перезапуска в `test/graph/data/file_backed_tag_durability_test.dart`, подтверждающая сценарий «Теги сохраняются после полного перезапуска», показывает, что после повторного открытия файловой БД тег, созданный позже, стоит первым.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph/data/drift_tag_read_test.dart test/graph/data/drift_tag_lifecycle_test.dart test/graph/data/drift_tag_assignment_read_test.dart test/intention/data/drift_intention_catalog_test.dart test/intention/data/drift_intention_repository_command_test.dart`.
    - `mise exec --no-deps -- flutter test --concurrency=1 test/graph/data/file_backed_tag_durability_test.dart`.
    - `mise run check:tests -- 0 1`: видимый порядок тегов меняется на всех экранах и в сквозных сценариях.
  - **Зависимости:** 1.2 — хранимое место и создание первым.
  - **Предполагаемые файлы:** `lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart`, `lib/src/tag/application/tag_catalog.dart`, `lib/src/tag/application/tag_assignments.dart`, `lib/src/tag/application/tag_read_result.dart`, `lib/src/intention/application/intention_catalog.dart`, `lib/src/intention/presentation/catalog/tag_condition_picker_page.dart` (описание экрана), `test/graph/data/drift_tag_read_test.dart`, `test/graph/data/drift_tag_lifecycle_test.dart`, `test/graph/data/drift_tag_assignment_read_test.dart`, `test/intention/data/drift_intention_catalog_test.dart`, `test/intention/data/drift_intention_repository_command_test.dart`, `test/graph/data/file_backed_tag_durability_test.dart`; ожидания проверок экранов и сквозных сценариев, которые полагались на порядок создания.
  - **Размер:** M.

- [x] 1.6 Убрать из базовой схемы 5 копию порядка создания тега в назначениях вместе с поддерживающими её объектами
  - **Критерии приёмки:**
    - Схема не содержит `tag_assignments.tag_creation_sequence`, трёх поддерживающих её триггеров, индекса `tag_assignments_intention_order` и условия по этому столбцу в триггере `graph_log_mark_tag_assignment_update` по решению 3 дизайна. Вставка назначения по-прежнему даёт одну отметку «вставка», а изменение строки — отметку «изменение». Проверка удалённой копии удаляется вместе с ней.
    - `tags.creation_sequence` остаётся неизменным ключом порций записей графа и порядка записей в файлах. Индекс `tag_assignments_tag_order` остаётся: он обслуживает порции навигации по тегу и удаляется вместе с ними в фазе 4 по решению 11 дизайна.
  - **Проверка:**
    - `mise run codegen`; сгенерированный `drift_schemas/drift_schema_v5.json` не содержит удалённых столбца, триггеров и индекса, а `tag_assignments_tag_order` в нём сохраняется.
    - `mise exec --no-deps -- flutter test test/data/local/tag_schema_test.dart test/data/local/graph_log_schema_test.dart test/data/local/app_database_schema_test.dart test/data/local/schema_verifier_test.dart test/graph/data/drift_tag_assignment_read_test.dart`.
  - **Зависимости:** 1.3 — базовая схема 5; 1.5 — чтения больше не используют копию.
  - **Предполагаемые файлы:** `lib/src/data/local/schema/tag_schema.drift`, `lib/src/data/local/schema/graph_log_schema.drift`, генерируемые `lib/src/data/local/app_database.g.dart` и `drift_schemas/drift_schema_v5.json`, `test/graph/data/drift_tag_assignment_read_test.dart`.
  - **Размер:** S.

- [x] 1.7 Подтвердить готовность первой фазы: порядок тегов задаётся только местом и без потерь проходит полный круг данных
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» первой фазы: порядок тегов задаётся только местом во всех чтениях и проходит без потерь полный круг данных через БД, журнал фактов, копии и экспорт с импортом, а существующие экраны тегов продолжают работать.
    - Пакет не содержит перестановки, дублирования и нового интерфейса. Результаты проверок и путь к APK сообщены в сессии; ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - `mise run check` и `openspec validate add-tags-panel --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`; эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки на установке, данные которой очищены по README: новый тег встаёт первым на прежних экранах тегов, а порядок сохраняется после перезапуска, восстановления копии и переноса файлом экспорта в другую установку.
  - **Зависимости:** 1.1–1.6.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

- [x] 1.8 Сверять точку отказа создания намерения с формой строки `tag_assignments` базовой схемы 5
  - **Критерии приёмки:**
    - `_expectFaultPoint` в `test/app/intention_creation_sheet_failure_integration_test.dart` находит назначения намерения по столбцу `intention_id` строки схемы 5 и ожидает ровно её столбцы `creation_sequence`, `tag_id`, `intention_id`: после задачи 1.6 столбца `tag_creation_sequence` нет. Проверка по-прежнему подтверждает, что отказ прерывает открытую транзакцию после записи намерения и одного из выбранных назначений.
    - Комментарий помощника описывает фактически проверяемые столбцы и не упоминает сохраняемый в назначениях порядок тегов.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test --no-pub test/app/intention_creation_sheet_failure_integration_test.dart` проходит.
  - **Зависимости:** 1.6 — схема 5 без копии порядка в назначениях.
  - **Предполагаемые файлы:** `test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Размер:** XS.

- [x] 1.9 Сверять назначения последнего тега в сценарии навигации по тегу в определённом порядке строк
  - **Критерии приёмки:**
    - В проверке «открытая навигация обновляет поля и порядок назначений» из `test/app/tag_navigation_graph_lifecycle_scenarios.dart` запрос назначений последнего тега упорядочен по `creation_sequence`, как строки помощника `_snapshot` (`ORDER BY rowid`), с которыми его сравнивают. После задачи 1.6 строки без `ORDER BY` приходят в порядке намерений, поэтому сравнение не должно зависеть от плана запроса SQLite. Оно по-прежнему строгое по составу и порядку строк.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test --no-pub test/app/tag_navigation_app_flow_test.dart` проходит.
  - **Зависимости:** 1.6 — схема 5 без индекса `tag_assignments_intention_order`.
  - **Предполагаемые файлы:** `test/app/tag_navigation_graph_lifecycle_scenarios.dart`.
  - **Размер:** XS.

- [x] 1.10 Описывать в комментариях изменённых проверок ручной порядок тегов вместо порядка создания
  - **Критерии приёмки:**
    - Комментарии, которые называют порядок создания тегов, описывают ручной порядок по месту тега. Там, где фикстура даёт места по возрастанию номера тега, комментарий явно говорит, что ручной порядок в ней совпадает с порядком создания:
      - комментарий группы «Создание с полным начальным состоянием» в `test/intention/data/drift_intention_repository_command_test.dart`;
      - помощник `tagNames` в `test/data_transfer/presentation/backups_sheet_test.dart`: он читает каталог в ручном порядке, в котором «Сад», созданный позже «Дома», стоит первым;
      - помощники `_backgroundTags` и `_fixtureTagIds` в `test/intention/data/drift_intention_repository_large_fixture_test.dart`.
    - Ожидания, фикстуры и код проверок не меняются: задача правит только комментарии.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test --no-pub test/intention/data/drift_intention_repository_command_test.dart test/data_transfer/presentation/backups_sheet_test.dart test/intention/data/drift_intention_repository_large_fixture_test.dart` проходит.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `test/intention/data/drift_intention_repository_command_test.dart`, `test/data_transfer/presentation/backups_sheet_test.dart`, `test/intention/data/drift_intention_repository_large_fixture_test.dart`.
  - **Размер:** XS.

- [x] 1.11 Сохранять место тега во входных данных проверки изменения только цвета
  - **Критерии приёмки:**
    - В проверке «изменение только цвета тега заменяет его состояние в сводке» из `test/intention/application/intention_contract_test.dart` тег, переданный в `withUpdatedTag`, сохраняет исходное место второго тега `tagPositionAt(1008)`: по решению 2 дизайна `UpdateTag` меняет только название и цвет, а место не трогает.
    - Ожидания проверки не меняются: порядок `[firstId, secondId]`, названия и цвета сводки остаются прежними.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test --no-pub test/intention/application/intention_contract_test.dart` проходит.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `test/intention/application/intention_contract_test.dart`.
  - **Размер:** XS.

## Phase 2: Теги намерения выбираются и создаются в панели тегов

- [x] 2.1 Ввести в модуле основ раскрываемый лист: половинная высота, раскрытие на весь экран и сворачивание жестом шапки и нажатием ручки
  - **Критерии приёмки:**
    - `showDoableSheet` получает вариант размера «раскрываемый», а `Sheet` — соответствующий режим по решению 9 дизайна и [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md). Половинная высота — 534, но не больше доступной; полный размер — весь экран под строкой состояния; при открытой клавиатуре высота не больше доступной над ней. Тело — лениво строящийся прокручиваемый список между закреплёнными частью под шапкой и подвалом, и его прокрутка не меняет размер листа.
    - Перетаскивание всего листа средствами Material в этом варианте выключено. Перетаскивание шапки на 48 и более вверх раскрывает лист, вниз — сворачивает полный или закрывает половинный через `Navigator.pop`. Нажатие на ручку переключает размер; в полном размере ручку заменяет шеврон сворачивания. Ручка — кнопка с подписями раскрытия и сворачивания от потребителя. Размер меняется за 180 мс с замедлением в конце, при уменьшенной анимации — сразу.
    - Затемнение, закрытие касанием затемнения, системное «назад» и семантика маршрута остаются за Material, а листы по содержимому сохраняют поведение ADR-0032. Иконка шеврона вниз переносится из исходного SVG дизайна.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/sheet_test.dart`: пороги жеста шапки из обоих размеров, нажатие на ручку и шеврон, закрытие с половинной высоты, уменьшенная анимация, высота при клавиатуре, прокрутка тела без изменения размера, «назад» и касание затемнения.
    - `mise exec --no-deps -- flutter test --update-goldens test/design_system/doable_icon_test.dart`, затем тот же набор без обновления эталона.
    - `mise exec --no-deps -- flutter test test/data_transfer/presentation/export_data_sheet_test.dart test/data_transfer/presentation/backups_sheet_test.dart test/app/quick_creation/quick_creation_mode_menu_test.dart test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart` — листы по содержимому не изменились.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/sheet.dart`, `lib/src/design_system/doable_icon.dart`, `lib/src/design_system/icons/assets/chevron_down.svg` (новый), `lib/src/design_system/icons/README.md`, `test/design_system/sheet_test.dart` (новый), `test/design_system/doable_icon_test.dart`, `test/design_system/goldens/doable_icons.png`.
  - **Размер:** M.

- [x] 2.2 Показывать сообщения общей поверхности поверх открытого листа, в котором выполняются операции графа
  - **Критерии приёмки:**
    - `showDoableSheet` получает необязательный признак размещения сообщений по решению 7 дизайна и [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md). Лист с признаком содержит собственный прозрачный `Scaffold`, а его закреплённый подвал стоит в `bottomNavigationBar`: `SnackBar` общей поверхности появляется над подвалом верхнего листа, и показ подтверждается кадром на верхнем маршруте. Признак работает и для раскрываемого листа, и для листа по содержимому, высота которого по-прежнему следует за содержимым.
    - При открытой клавиатуре лист с признаком обоих размеров ведёт себя как лист `showDoableSheet` без признака: он ограничен местом над клавиатурой, которая не учитывается повторно ни отступом листа, ни уменьшением тела `Scaffold`, а закреплённые часть под шапкой и подвал видны.
    - Владелец поверхности, очередь, объединение сообщений по ADR-0023 и политика предъявления не меняются. Листы без признака — экспорт, резервные копии и листы быстрого создания — по-прежнему оставляют сообщение на странице до своего закрытия. Описание `GraphOperationPresenter` соответствует новому месту показа.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph/presentation/graph_operation_presenter_test.dart`: ожидающий результат показан над подвалом открытого листа с признаком обоих размеров и подтверждён, пока лист открыт; под листом без признака результат ждёт его закрытия.
    - `mise exec --no-deps -- flutter test test/design_system/sheet_test.dart test/data_transfer/presentation/export_data_sheet_test.dart test/data_transfer/presentation/backups_sheet_test.dart test/app/quick_creation/quick_creation_mode_menu_test.dart test/app/quick_creation/quick_creation_daily_choice_start_sheet_test.dart`; в `sheet_test.dart` лист с признаком обоих размеров при открытой клавиатуре занимает не больше места над ней, а его закреплённая часть и подвал видны.
  - **Зависимости:** 2.1 — раскрываемый лист.
  - **Предполагаемые файлы:** `lib/src/design_system/components/sheet.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/design_system/sheet_test.dart`.
  - **Размер:** M.

- [x] 2.3 Перевести все операции тегов на политику «только отказ»: успех не объявляется, а отказ сразу принадлежит общей поверхности
  - **Критерии приёмки:**
    - Координатор задаёт политику ADR-0016 для создания, изменения, удаления, назначения и снятия назначения тега по требованию «Согласование панели тегов с подтверждёнными изменениями». Успех публикуется только для согласования данных и не оставляет непредъявленной записи, а отказ сразу принадлежит общей поверхности без права инициатора.
    - Экраны тегов не притязают на отказы этих операций и не рисуют их сами: прежние редактор и каталог тегов, включая контекст назначения, сохраняемый до фазы 4, и снятие назначения на странице намерения. Сообщения об успехе операций тегов удаляются из `GraphOperationPresenter` и локализации; тексты отказов и сообщения об отклонённом старте, например «уже выполняется», остаются.
    - Проверки, ожидавшие сообщения об успехе или инлайн-отказ операций тегов, ожидают отсутствие сообщения об успехе и отказ на общей поверхности.
  - **Проверка:**
    - `mise run codegen` и `mise exec --no-deps -- flutter analyze`: ни одна проверка не ссылается на удалённые сообщения об успехе.
    - `mise exec --no-deps -- flutter test test/graph/application/graph_command_coordinator_tag_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart test/graph/presentation/graph_reconciliation_checkpoint_test.dart`: успех без права предъявления и без оставшейся записи, отказ без права инициатора и его показ общей поверхностью для каждого вида операции.
    - `mise exec --no-deps -- flutter test test/tag/presentation/editor test/tag/presentation/catalog test/tag/presentation/assignments test/tag/presentation/tag_accessibility_test.dart test/app/tag_app_flow_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/tag_navigation_app_lifecycle_test.dart` — экраны и сквозные сценарии с прежними сообщениями.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart`, `lib/src/tag/presentation/editor/tag_editor_state.dart`, `lib/src/tag/presentation/editor/tag_editor_page.dart`, `lib/src/tag/presentation/catalog/tag_catalog_view.dart`, `lib/src/tag/presentation/assignments/tag_assignments_section.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые файлы локализации; проверки из раздела «Проверка».
  - **Размер:** M — один переход политики предъявления: по частям его не ввести без двойного предъявления отказа.

- [x] 2.4 Искать теги без учёта окружающих пробелов запроса по одному правилу для панели и прежних страниц
  - **Критерии приёмки:**
    - `TagCatalogFilter.fromInput` после проверки Unicode удаляет окружающие пробелы по правилу `TagName` и только затем строит ключ сопоставления по решению 5 дизайна: запрос из одних пробелов даёт пустой фильтр, а внутренние пробелы остаются частью искомой подстроки. Поле поиска сохраняет исходный ввод.
    - По этому правилу до своего удаления в фазе 4 ищут прежние каталог тегов и выбор условия по тегу. Проверки, закреплявшие значимость окружающих пробелов, заменяются проверками требования «Поиск тегов в панели», включая сценарий «Запрос из одних пробелов не сужает список».
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_filter_test.dart test/tag/presentation/catalog/tag_catalog_search_page_test.dart test/intention/presentation/catalog/tag_condition_picker_page_test.dart test/tag/presentation/tag_accessibility_test.dart`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/catalog/tag_catalog_filter.dart`, `test/tag/presentation/catalog/tag_catalog_filter_test.dart`; проверки поиска прежних страниц, которые ожидали значимые окружающие пробелы.
  - **Размер:** S.

- [x] 2.5 Добавить в модуль основ поле поиска с очисткой и строкой ошибки ввода
  - **Критерии приёмки:**
    - `SearchField` по правилам компонента дизайн-системы: плоскость `fill` высотой `tap-min` с иконкой поиска, заполнителем, крестиком очистки, пока поле не пусто, строкой ошибки ввода под полем и действием клавиатуры «поиск». Контроллер, тексты, доступные названия поля и крестика и обработчики задаёт потребитель по ADR-0030.
    - Иконки поиска и очистки переносятся из исходного SVG дизайна, а таблица источников иконок дополняется.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/search_field_test.dart`: размеры и цвета по токенам в обеих темах, крестик только при непустом поле и очистка им, строка ошибки и её объявление, доступные названия.
    - `mise exec --no-deps -- flutter test --update-goldens test/design_system/doable_icon_test.dart`, затем тот же набор без обновления эталона.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/search_field.dart` (новый), `lib/src/design_system/doable_icon.dart`, `lib/src/design_system/icons/assets/search.svg` (новый), `lib/src/design_system/icons/assets/clear.svg` (новый), `lib/src/design_system/icons/README.md`, `test/design_system/search_field_test.dart` (новый), `test/design_system/doable_icon_test.dart`, `test/design_system/goldens/doable_icons.png`.
  - **Размер:** S.

- [x] 2.6 Добавить в модуль основ строку тега с отметкой выбора
  - **Критерии приёмки:**
    - `TagRow` по правилам компонента дизайн-системы: высота не меньше 48, `TagDot` 10, название в стиле `action` с переносом без обрезки и отметка «нет» или «отмечен» — галочка 20 цвета `accent` справа, различимая без опоры на цвет. Доступное название и отметку строки, обработчик нажатия и его недоступность задаёт потребитель по ADR-0030.
    - Ручка перестановки, удержание и отметки фильтра появляются вместе с потребителями в фазах 3 и 4.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/tag_row_test.dart`: размеры и цвета по токенам в обеих темах, перенос длинного названия, точка тега без цвета, отметка и её семантика, недоступное нажатие, отсутствие отдельного элемента навигации диктора у точки.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/tag_row.dart` (новый), `test/design_system/tag_row_test.dart` (новый).
  - **Размер:** S.

- [x] 2.7 Добавить в модуль основ основную кнопку, состояние списка и пустое состояние
  - **Критерии приёмки:**
    - `Button` вида primary по правилам компонента дизайн-системы: плоскость `ink` с текстом `bg`, высота `control-height`, растяжение на ширину, выключенное состояние на месте кнопки и область нажатия не меньше `tap-min`. Виды quiet, danger и text появляются с потребителями в фазах 3 и 4.
    - `ListState` с видами «загрузка», объявляемой как статус, и «ошибка» — карточка со значком, сообщением и необязательным действием повтора, объявляемая как оповещение. `EmptyState` — заголовок и текст без значка и кнопки по центру оставшегося места.
    - Тексты, доступные названия и обработчики задаёт потребитель по ADR-0030.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/button_test.dart test/design_system/list_state_test.dart test/design_system/empty_state_test.dart`: размеры и цвета по токенам в обеих темах, выключенная кнопка, семантика статуса и оповещения, ошибка без действия повтора, рост с крупным шрифтом.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/button.dart`, `lib/src/design_system/components/list_state.dart`, `lib/src/design_system/components/empty_state.dart`, `test/design_system/button_test.dart`, `test/design_system/list_state_test.dart`, `test/design_system/empty_state_test.dart` (все новые).
  - **Размер:** M.

- [x] 2.8 Ввести модель панели тегов в контексте назначения существующему намерению: полный снимок с отметками, поиск и согласование с подтверждёнными пакетами
  - **Критерии приёмки:**
    - `TagsPanelContext` — закрытый тип контекста по [ADR-0040](../../../docs/adr/0040-choose-and-manage-tags-in-one-context-panel.md); в этой фазе в нём только вариант назначения по идентификатору намерения, варианты черновика и фильтра добавляет фаза 4. Прежний `TagAssignmentContext` выбора в каталоге остаётся до фазы 4, и введение контекста панели его не меняет. `TagsPanelViewModel` привязана к токену открытия, поэтому каждое открытие начинает с пустого поиска.
    - Модель читает полный снимок в режиме выбора и различает первоначальную загрузку, пустой каталог, отсутствие намерения, устранимый отказ с повтором, повреждение и неизвестный отказ без повтора как восстановления. Поиск применяет общий фильтр к каталогу в ручном порядке; некорректный ввод сохраняет последний корректный фильтр с признаком ошибки, а обновления и повторы сохраняют ввод и фильтр.
    - Пакеты, которые модель полностью объясняет, — изменения назначений этого намерения, создание, изменение и удаление тегов — применяются к строкам локально с сохранением ручного порядка. Остальные пакеты запускают фоновое перечитывание, во время которого строки доступны. Отказ обновления делает строки неактуальными до успешного обновления, а запоздалое чтение не возвращает состояние до подтверждённой операции.
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/tag/presentation/panel/tags_panel_view_model_test.dart`: сценарии «Фоновое обновление сохраняет список», «Запоздалое чтение после изменения тега», «Неизвестный отказ получения каталога», «Обновление сохраняет поиск и применяет его к актуальному каталогу», «Повтор чтения сохраняет запрос», «Некорректный ввод сохраняет последний корректный фильтр» и «Запрос из одних пробелов не сужает список»; отсутствие намерения и новое открытие с пустым поиском.
  - **Зависимости:** 2.4 — общее правило поиска.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/panel/tags_panel_context.dart`, `lib/src/tag/presentation/panel/tags_panel_state.dart`, `lib/src/tag/presentation/panel/tags_panel_view_model.dart` и генерируемый `tags_panel_view_model.g.dart`, `test/tag/presentation/panel/tags_panel_view_model_test.dart` (все новые); `test/support/tag_catalog_test_repository.dart`.
  - **Размер:** M.

- [x] 2.9 Назначать и снимать тег нажатием на строку в модели панели
  - **Критерии приёмки:**
    - Нажатие на неотмеченный тег отправляет через координатор `AssignTag`, на отмеченный — `RemoveTagAssignment` по требованию «Выбор тегов намерения в панели». Отметка меняется только по подтверждённому пакету без повторного получения каталога, а отказ записи оставляет её прежней.
    - Пока назначение или снятие этого намерения выполняется, следующее нажатие координатор отклоняет по занятому ключу намерения: модель не ставит его в очередь, не показывает сообщения, и строки остаются на месте. Нажатие недоступно на неактуальных строках и при отсутствии намерения; закрытие панели не отменяет принятую команду.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/panel/tags_panel_view_model_test.dart`: сценарии «Нажатие сразу назначает и снимает тег» и «Отказ записи оставляет прежнюю отметку»; отклонение нажатия во время выполняющегося назначения; недоступное нажатие на неактуальной строке; завершение принятой команды после освобождения модели.
  - **Зависимости:** 2.3 — отказ назначения принадлежит общей поверхности; 2.8 — модель панели.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/panel/tags_panel_state.dart`, `lib/src/tag/presentation/panel/tags_panel_view_model.dart`, `test/tag/presentation/panel/tags_panel_view_model_test.dart`.
  - **Размер:** S.

- [x] 2.10 Показывать панель тегов функцией `showTagsPanel` с поиском, каталогом и отметками назначений
  - **Критерии приёмки:**
    - `showTagsPanel(context, TagsPanelContext)` открывает над страницей или листом инициатора раскрываемый лист с признаком размещения сообщений по требованию «Панель тегов»: шапка «Теги» и «Выберите сколько нужно», закреплённое поле «Найти или создать тег», каталог строками `TagRow` в ручном порядке и «Готово» в подвале. «Готово», свайп вниз, касание затемнения и «назад» только закрывают панель без подтверждения.
    - Состояния: загрузка и отказ первоначального чтения в `ListState`, пустой каталог в `EmptyState` с подсказкой «Тегов пока нет. Введите название в поиске, чтобы создать первый», ошибка некорректного ввода под полем, отказ обновления в `Notice` с «Повторить» над неактуальным списком и отсутствие намерения. Отказ назначения виден поверх открытой панели над «Готово».
    - Фоновое обновление, его отказ с появлением `Notice` и повтор «Повторить» сохраняют показанные строки и положение прокрутки списка по требованию «Согласование панели тегов с подтверждёнными изменениями».
    - Русские и английские строки панели; доступное название строки передаёт название тега и его отметку, ручка листа объявляет раскрытие и сворачивание, а открытая клавиатура не скрывает поле поиска и первую строку.
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/tag/presentation/panel/tags_panel_test.dart` на обоих языках с проверкой семантики, с панелью, открытой с тестовой страницы: каталог с неиспользуемыми тегами и тегами только архивированных намерений с отметкой назначенных; сценарии «Большой каталог получен целиком» на каталоге длиннее экрана, «Пустой каталог отличается от отсутствия совпадений», «Цветной и бесцветный теги в каталоге», «Поиск при назначении намерению», «Назначенный тег скрыт фильтром» и «Новое открытие начинает поиск заново»; сценарий «Фоновое обновление сохраняет список» на прокрученном каталоге длиннее экрана — фоновое перечитывание, его отказ с `Notice` и успешный повтор «Повторить» оставляют те же строки и то же положение прокрутки; отказ назначения поверх панели и закрытие всеми способами; при открытой клавиатуре поле поиска и первая строка видны в обоих размерах панели.
  - **Зависимости:** 2.1, 2.2 — раскрываемый лист и сообщения поверх него; 2.5–2.7 — компоненты; 2.9 — модель панели с назначением.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/panel/tags_panel.dart` (новый), `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые файлы локализации, `test/tag/presentation/panel/tags_panel_test.dart` (новый).
  - **Размер:** M.

- [x] 2.11 Проверять название в модели листа тега при каждом вводе и отдавать принятое создание вызывающему
  - **Критерии приёмки:**
    - `TagEditorViewModel` проверяет название `TagName.fromInput` при каждом вводе по решению 6 дизайна: пустое после удаления пробелов делает создание недоступным без сообщения, непустое недопустимое получает различимую причину, а совпадение ключа сопоставления с названием из переданного снимка даёт «Тег с таким названием уже есть». Создание доступно только для допустимого свободного названия, не больше одной отправки сразу и без очереди.
    - Контекст создания несёт начальное название. Модель отдаёт вызывающему принятую команду создания до её завершения, и закрытие сессии листа команду не отменяет. Успех завершает сессию подтверждённым тегом из результата команды. Отказ записи, в том числе занятость, обнаруженную при записи, предъявляет общая поверхность, а модель сохраняет название и цвет для исправления или допустимого повтора.
    - Ответвление «Использовать существующий тег» и чтения после записи удаляются вместе с их состояниями и строками. Прежняя страница редактора по-прежнему создаёт и изменяет теги из прежнего каталога; снимок названий ей не передаётся, и занятость для неё определяет запись. Правила листа изменения остаются фазе 3.
  - **Проверка:**
    - `mise run codegen` и `mise exec --no-deps -- flutter analyze`: ни одна проверка не ссылается на удалённые ключи и строки ответвления и чтений после записи.
    - `mise exec --no-deps -- flutter test test/tag/presentation/editor`: сценарии «Пустое после нормализации название», «Регистр и окружающие пробелы не создают новый тег», «Недопустимые скалярные значения» и «Повторная отправка создания»; передача принятой команды и сохранение ввода после отказа записи.
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog test/app/intention_creation_sheet_tags_test.dart test/app/tag_app_flow_test.dart test/app/tag_app_lifecycle_test.dart` — прежние каталог и редактор без ответвления «Использовать существующий тег» и повтора чтения после записи.
  - **Зависимости:** 2.3 — модель уже не притязает на отказы.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_editor_state.dart`, `lib/src/tag/presentation/editor/tag_editor_view_model.dart` и генерируемый `tag_editor_view_model.g.dart`, `lib/src/tag/presentation/editor/tag_editor_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые файлы локализации, `test/tag/presentation/editor/tag_editor_view_model_test.dart`, `test/tag/presentation/editor/tag_editor_page_test.dart`, `test/tag/presentation/catalog/tag_catalog_page_test.dart`, `test/app/tag_app_flow_test.dart`, `test/app/tag_app_lifecycle_test.dart`.
  - **Размер:** M.

- [x] 2.12 Добавить в модуль основ однострочное текстовое поле с ведущей меткой и строку создания тега
  - **Критерии приёмки:**
    - Компонент `TextField` дизайн-системы в однострочном виде `name`: плоскость `fill` высотой 48 без рамки и кольца фокуса, ведущая метка перед текстом, заполнитель `muted` и строка ошибки под полем в стиле `hint` цвета `danger`, объявляемая как оповещение. Многострочный вид и сохранённый текст появляются с потребителями.
    - `TagCreateRow` — строка высотой не меньше 48 с плюсом 18 и текстом в стиле `action` цвета `accent`; длинный текст переносится без обрезки. Текст, доступное название и обработчик задаёт потребитель по ADR-0030.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/text_field_test.dart test/design_system/tag_create_row_test.dart`: размеры и цвета по токенам в обеих темах, ведущая метка, строка ошибки и её семантика, перенос длинного текста строки создания.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/text_field.dart`, `lib/src/design_system/components/tag_create_row.dart`, `test/design_system/text_field_test.dart`, `test/design_system/tag_create_row_test.dart` (все новые).
  - **Размер:** S.

- [x] 2.13 Предлагать в модели панели создание тега по применённому запросу и отмечать созданный тег в пределах открытия панели
  - **Критерии приёмки:**
    - Модель предлагает создание первой строкой, когда применённый запрос не пуст и ни одно название не совпадает с ним по правилу уникальности; предлагаемое название — применённый запрос в исходном регистре по требованию «Создание тега из панели».
    - Принятое из листа создание принадлежит открытию панели: после подтверждения модель один раз очищает поиск и отмечает тег отдельной командой `AssignTag` для намерения контекста, а при отклонённом или неудавшемся назначении тег остаётся неотмеченным. Ранее закрытый лист результат не меняет, и тег отмечается ровно один раз. Если до подтверждения закрыта сама панель, тег остаётся неотмеченным и не влияет на следующее открытие.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/panel/tags_panel_view_model_test.dart`: сценарии «Строка создания предлагает название из поиска», «Совпадающее название не предлагает создание», «Новый тег встаёт первым и очищает поиск», «Созданный тег сразу назначен», «Закрытие листа до подтверждения создания» и «Подтверждённая запись и ошибка обновления»; закрытие панели до подтверждения и отказ назначения после создания.
  - **Зависимости:** 2.9 — назначение из панели; 2.11 — принятое создание из модели листа.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/panel/tags_panel_state.dart`, `lib/src/tag/presentation/panel/tags_panel_view_model.dart`, `lib/src/tag/presentation/catalog/tag_catalog_filter.dart`, `test/tag/presentation/panel/tags_panel_view_model_test.dart`.
  - **Размер:** M.

- [x] 2.14 Создавать тег из панели в листе «Новый тег» поверх неё
  - **Критерии приёмки:**
    - Предложенное создание стоит первой строкой `TagCreateRow` «Создать тег «‹запрос›»». Её нажатие открывает поверх панели лист по содержимому с признаком размещения сообщений: заголовок «Новый тег», поле «Название» с точкой выбранного цвета и строкой ошибки, `TagColorPicker` с выбранным «Без цвета» и «Создать тег» в подвале; начальное название — применённый запрос.
    - Выбор цвета сразу меняет точку в поле и не меняет сохранённые данные до создания. Закрытие листа без отправки свайпом, касанием затемнения или «назад» возвращает ту же панель без подтверждения с прежними каталогом, отметками и поиском. Подтверждённое создание закрывает лист, если он ещё открыт; отказ записи виден поверх листа, а лист сохраняет название и цвет.
    - Русские и английские строки листа и строки создания; поле, ошибка и выбор цвета доступны экранному диктору, а «назад» в листе закрывает только лист. Открытая клавиатура не скрывает поле «Название» и «Создать тег».
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/tag/presentation/panel test/tag/presentation/editor`: сценарии «Совпадений нет, создание доступно» и «Создание тега без выбора цвета»; закрытие листа без отправки; отказ записи поверх листа; «назад» в листе и в панели; при открытой клавиатуре поле «Название» и «Создать тег» видны.
  - **Зависимости:** 2.2 — сообщения поверх листа; 2.10 — панель; 2.12 — компоненты; 2.13 — создание в модели панели.
  - **Предполагаемые файлы:** `lib/src/tag/presentation/editor/tag_sheet.dart` (новый), `lib/src/tag/presentation/panel/tags_panel.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и генерируемые файлы локализации, `test/tag/presentation/panel/tags_panel_test.dart`, `test/tag/presentation/editor/tag_sheet_test.dart` (новый).
  - **Размер:** M.

- [ ] 2.15 Открывать со страницы намерения панель тегов вместо прежнего выбора и перевести на неё сквозные проверки
  - **Критерии приёмки:**
    - Выбор тегов на странице активного и архивированного намерения открывает панель в контексте назначения этого намерения по требованию «Управление тегами намерения»; прежний каталог в контексте назначения больше не открывается ни одним входом и остаётся в коде до фазы 4. Панель перекрывает страницу и панель навигации, которые недоступны, пока она открыта, а «назад» закрывает только панель, не меняя выбранный пункт.
    - После закрытия панели страница намерения показывает подтверждённые назначения без сообщения об успехе, в том числе назначение, завершившееся после закрытия панели.
    - Сквозные проверки и матрица страниц, которые проходили через прежний выбор, проходят через панель.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details/intention_details_tags_test.dart test/app/tag_assignment_app_flow_test.dart test/app/tag_assignment_app_lifecycle_test.dart test/app/tag_app_flow_test.dart test/app/navigation test/tag/presentation/tag_accessibility_test.dart`: сценарии «Панель со страницы намерения показывает назначенные теги», «Закрытие панели сохраняет применённые изменения», «Закрытие панели во время назначения», «Созданный тег сразу назначен», «Теги архивированного действия», «Назначение конкретному одноимённому намерению» и «Успех операции в панели не объявляется сообщением» без перестановки; «назад» из панели над страницей намерения.
  - **Зависимости:** 2.14 — панель с выбором и созданием.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `test/intention/presentation/details/intention_details_tags_test.dart`, `test/app/tag_assignment_app_flow_test.dart`, `test/app/tag_assignment_app_lifecycle_test.dart`, `test/app/tag_app_flow_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`, `test/app/navigation/app_shell_pages_above_test.dart`, `test/tag/presentation/tag_accessibility_test.dart`.
  - **Размер:** M.

- [ ] 2.16 Подтвердить готовность второй фазы: выбор и создание тегов существующего намерения полностью идут через панель
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» второй фазы: выбор и создание тегов для существующего намерения полностью идут через панель по спецификациям, включая отказы, доступность и локализацию, а прежний выбор тегов со страницы намерения больше не открывается.
    - Пакет не содержит меню тега, изменения, дублирования, удаления и перестановки в панели, контекстов черновика и фильтра. Результаты проверок и путь к APK сообщены в сессии; ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - `mise run check` и `mise exec --no-deps -- openspec validate add-tags-panel --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`; эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки на устройстве: панель со страницы намерения открывается на половину высоты, раскрывается и сворачивается перетаскиванием шапки и нажатием ручки, поиск виден при открытой клавиатуре, теги назначаются и снимаются нажатием и создаются из строки создания, отказ виден над «Готово» и над «Создать тег», TalkBack озвучивает строки, ручку и поле названия; вид сверяется с макетами `PageTags`, `TagsPanel`, `IntentionTagsFull`, `IntentionTagSearch`, `IntentionTagNew`, `IntentionTagCreated`, `NewTag`, `TagTaken` и `TagDark`.
  - **Зависимости:** 2.1–2.15.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.
