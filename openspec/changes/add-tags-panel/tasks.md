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

- [ ] 1.2 Сделать место обязательной частью тега, строки `tags` и записи формата графа и ставить новый тег перед текущим первым
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

- [ ] 1.3 Сделать схему 5 базовой, чтобы хранилище прежней тестовой сборки со схемой 4 распознавалось как повреждённое, а README описывал ручную очистку
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

- [ ] 1.4 Отклонять при чтении файл или снимок, в секции тегов которого повторяется место, как повреждение формата
  - **Критерии приёмки:**
    - Чтение записей файла или снимка с повторяющимся местом в секции тегов завершается `GraphFormatCorruption` до замены графа по решению 4 дизайна; ограничение `UNIQUE` при замене остаётся последней защитой.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph_format/graph_format_file_test.dart`.
  - **Зависимости:** 1.2 — место в записи формата.
  - **Предполагаемые файлы:** `lib/src/graph_format/graph_format_file.dart`, `test/graph_format/graph_format_file_test.dart`.
  - **Размер:** S.

- [ ] 1.5 Упорядочивать теги в каталоге, назначениях и кратких данных намерений только по месту
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

- [ ] 1.6 Убрать из базовой схемы 5 копию порядка создания тега в назначениях вместе с поддерживающими её объектами
  - **Критерии приёмки:**
    - Схема не содержит `tag_assignments.tag_creation_sequence`, трёх поддерживающих её триггеров, индекса `tag_assignments_intention_order` и условия по этому столбцу в триггере `graph_log_mark_tag_assignment_update` по решению 3 дизайна. Вставка назначения по-прежнему даёт одну отметку «вставка», а изменение строки — отметку «изменение». Проверка удалённой копии удаляется вместе с ней.
    - `tags.creation_sequence` остаётся неизменным ключом порций записей графа и порядка записей в файлах. Индекс `tag_assignments_tag_order` остаётся: он обслуживает порции навигации по тегу и удаляется вместе с ними в фазе 4 по решению 11 дизайна.
  - **Проверка:**
    - `mise run codegen`; сгенерированный `drift_schemas/drift_schema_v5.json` не содержит удалённых столбца, триггеров и индекса, а `tag_assignments_tag_order` в нём сохраняется.
    - `mise exec --no-deps -- flutter test test/data/local/tag_schema_test.dart test/data/local/graph_log_schema_test.dart test/data/local/app_database_schema_test.dart test/data/local/schema_verifier_test.dart test/graph/data/drift_tag_assignment_read_test.dart`.
  - **Зависимости:** 1.3 — базовая схема 5; 1.5 — чтения больше не используют копию.
  - **Предполагаемые файлы:** `lib/src/data/local/schema/tag_schema.drift`, `lib/src/data/local/schema/graph_log_schema.drift`, генерируемые `lib/src/data/local/app_database.g.dart` и `drift_schemas/drift_schema_v5.json`, `test/graph/data/drift_tag_assignment_read_test.dart`.
  - **Размер:** S.

- [ ] 1.7 Подтвердить готовность первой фазы: порядок тегов задаётся только местом и без потерь проходит полный круг данных
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
