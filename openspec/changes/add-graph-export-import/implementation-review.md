# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 3.28–3.34 поставлены, их целевые тесты и полные проверки проекта на проверяемой голове проходят. Активных замечаний нет. Есть один принятый остаточный риск AR1 (бывшее замечание F1): копии, сделанные после повреждённого последнего снимка до его пересборки, не восстанавливаются, пока хранятся. Владелец продукта принял этот риск, и решение 7 дизайна это фиксирует.

## Review target

- **Baseline ref:** 6c9b22e85c2448527a39499e8cf01fb920285219
- **Base commit:** 6c9b22e85c2448527a39499e8cf01fb920285219
- **Reviewed head:** b28e1db28f14512d628d546075c703204f70fc12
- **Target commits:** ["5caf5ead4d805a824be2f73ea5b4d7157f2c94a4", "9a8274d7e5952e4f3830d01b8b4f5e6653ce2ee1", "8719193046ce1b1ff70680e1accc550242e7973a", "4074293ef057e10132c575bbb63d674327cf48a5", "8f9970a45ada2ee43886c76c094242859a18a97b", "989fda10f9554945cf334f5c32e4f1d00c852445", "b28e1db28f14512d628d546075c703204f70fc12"]
- **Reviewable paths:** ["lib/src/data/local/database_connection.dart", "lib/src/data/local/sqlite_failure_classifier.dart", "lib/src/data_transfer/application/graph_replacement.dart", "lib/src/data_transfer/application/graph_restore.dart", "lib/src/data_transfer/application/graph_restore_provider.dart", "lib/src/data_transfer/presentation/backups_sheet.dart", "lib/src/data_transfer/presentation/graph_restore_progress.dart", "lib/src/data_transfer/presentation/restore_backup_confirmation.dart", "lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/design_system/components/sheet.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_fact_log.dart", "lib/src/graph/data/drift_personal_graph_repository_replacement.dart", "lib/src/graph_snapshots/graph_fact_log.dart", "openspec/changes/add-graph-export-import/tasks.md", "test/app/navigation/app_shell_graph_generation_test.dart", "test/data/local/sqlite_failure_classifier_test.dart", "test/data_transfer/graph_restore_test.dart", "test/data_transfer/presentation/backups_sheet_test.dart", "test/data_transfer/presentation/graph_restore_progress_test.dart", "test/data_transfer/presentation/restore_backup_confirmation_test.dart", "test/data_transfer/presentation/settings_data_section_test.dart", "test/graph/data/drift_graph_fact_log_access_test.dart", "test/graph/data/drift_graph_replacement_process_durability_test.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/graph_snapshots/graph_log_compaction_test.dart", "test/support/graph_replacement_process_worker.dart", "test/support/transaction_storage_exhaustion.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Сжатие сохраняет ближайший снимок каждой хранимой копии, а пакет «сброс» читается только с позицией

- **Work items:** ["3.28", "3.34"]
- **Requirements and scenarios:** ["graph-backups: Резервные копии на устройстве", "graph-backups: Восстановление копии — сценарий «Восстановление отменяет изменения после копии»", "design: решение 7 «Хранение истории»", "plan: этап 3, условие готовности о границе хранения истории и памяти восстановления"]
- **Affected boundary:** Локальное хранилище графа: лог фактов, реестр и файлы снимков, фоновое сжатие лога и сборка состояния на позиции копии для восстановления.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository_fact_log.dart", "lib/src/graph_snapshots/graph_fact_log.dart", "test/graph_snapshots/graph_log_compaction_test.dart", "test/graph/data/drift_graph_fact_log_access_test.dart", "test/graph/data/drift_graph_replacement_process_durability_test.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/data_transfer/graph_restore_test.dart"]
- **Applicable constraints and non-goals:** Схема версии 3 не меняется, и в ней пакет «сброс» ссылается на снимок замены, а удалить такой снимок нельзя. Место под снимок каждого интервала сжатия с копиями владелец продукта принял. Команды не ждут сжатия, а граница хранения не зависит от часов устройства. Порог сжатия, окно копий и формат файлов не меняются.

### U2 · Нехватка места, после которой SQLite сам откатил транзакцию замены, остаётся нехваткой места

- **Work items:** ["3.29"]
- **Requirements and scenarios:** ["graph-backups: Восстановление копии — отказ при нехватке места с «Повторить»", "graph-backups: Диагностика резервных копий без пользовательского содержимого — сценарий «Отказ восстановления диагностируется без содержимого»", "graph-export-import: Атомарная замена графа"]
- **Affected boundary:** Общий классификатор отказов SQLite и исход восстановления копии, который видит человек, вместе с его диагностикой.
- **Implementation target:** ["lib/src/data/local/sqlite_failure_classifier.dart", "test/data/local/sqlite_failure_classifier_test.dart", "test/support/transaction_storage_exhaustion.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/data_transfer/graph_restore_test.dart"]
- **Applicable constraints and non-goals:** Поведение Drift и SQLite при отказе отката — внешняя данность. Диагностика без пользовательского содержимого. Команды и чтения, которые объединяют нехватку места с неизвестным отказом, сохраняют прежние исходы. Новых текстов нет.

### U3 · Последняя проверка отмены замены — точка невозврата, после которой «Отменить» недоступна

- **Work items:** ["3.30", "3.31"]
- **Requirements and scenarios:** ["graph-export-import: Атомарная замена графа — сценарий «Отмена замены»", "graph-export-import: Атомарная замена графа — «Отменить» недоступна, когда замену уже нельзя откатить", "design: решение 10, точка невозврата"]
- **Affected boundary:** Человек перед модальным прогрессом восстановления, в том числе с экранным диктором; контроллер восстановления и контракт замены графа между приложением и хранилищем.
- **Implementation target:** ["lib/src/data_transfer/application/graph_replacement.dart", "lib/src/data_transfer/application/graph_restore.dart", "lib/src/data_transfer/application/graph_restore_provider.dart", "lib/src/data_transfer/presentation/graph_restore_progress.dart", "lib/src/graph/data/drift_personal_graph_repository.dart", "lib/src/graph/data/drift_personal_graph_repository_replacement.dart", "lib/src/data/local/database_connection.dart", "test/graph/data/drift_graph_replacement_test.dart", "test/data_transfer/graph_restore_test.dart", "test/data_transfer/presentation/graph_restore_progress_test.dart", "test/app/navigation/app_shell_graph_generation_test.dart", "test/support/graph_replacement_process_worker.dart"]
- **Applicable constraints and non-goals:** Замена остаётся одной транзакцией верхнего уровня на единственном соединении. Отказ и завершение процесса до COMMIT оставляют прежний граф и копии. Действие «назад» прогресс не закрывает. Новых текстов нет.
- **Excluded change scope:** Замена импортом и её прогресс относятся к этапу 4.

### U4 · Относительный день копий следует за сменой местной даты

- **Work items:** ["3.32"]
- **Requirements and scenarios:** ["graph-backups: Список резервных копий", "graph-backups: Восстановление копии", "graph-backups: Локализация и доступность резервных копий — сценарий «Копия читается экранным диктором»"]
- **Affected boundary:** Человек перед строкой «Резервные копии», панелью копий и подтверждением восстановления на странице «Настройки», в том числе с экранным диктором.
- **Implementation target:** ["lib/src/data_transfer/presentation/settings_data_section.dart", "lib/src/data_transfer/presentation/backups_sheet.dart", "lib/src/data_transfer/presentation/restore_backup_confirmation.dart", "test/data_transfer/presentation/settings_data_section_test.dart", "test/data_transfer/presentation/backups_sheet_test.dart", "test/data_transfer/presentation/restore_backup_confirmation_test.dart"]
- **Applicable constraints and non-goals:** Подписи строятся по часам копий, а о смене даты поверхности узнают так же, как Главная и каталог дневных выборов. Форматы подписей, граница дня копий в 03:00 и новые тексты не меняются.

### U5 · «Сделать копию сейчас» закреплена под прокручиваемым списком копий

- **Work items:** ["3.33"]
- **Requirements and scenarios:** ["graph-backups: Список резервных копий", "макет SettingsBackups"]
- **Affected boundary:** Человек в панели «Резервные копии»; общий лист дизайн-системы, которым пользуются панель экспорта и листы быстрого создания.
- **Implementation target:** ["lib/src/design_system/components/sheet.dart", "lib/src/data_transfer/presentation/backups_sheet.dart", "test/data_transfer/presentation/backups_sheet_test.dart"]
- **Applicable constraints and non-goals:** Компоненты дизайн-системы без предметной логики (ADR-0030), листы показываются над корневым навигатором (ADR-0032). Остальные листы и тексты не меняются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Работали два свежих изолированных рецензента `implementation-decision-review`, каждый со своей нейтральной запиской о намерении. Планирующие артефакты, история Git, прежний отчёт и обсуждение реализации им не передавались. U1–U3 делят тестовые файлы `drift_graph_replacement_test.dart` и `graph_restore_test.dart`, поэтому их проверил один рецензент с объединённой запиской и всеми 20 путями. Итог — `Changes needed` (F1), покрытие полное. U4 и U5 делят `backups_sheet.dart`, их проверил второй рецензент с 7 путями. Замечаний нет, покрытие полное. |
| OpenSpec conformance | Complete | Проверено в чистом worktree, `HEAD` которого совпадает с `b28e1db28f14512d628d546075c703204f70fc12`; кроме отчёта, файлов не менялось. Целевые тесты диапазона прошли: 298 обычных тестов и 4 процессных теста замены. `mise run check` (этап 3 завершается) прошёл: формат — 760 файлов без изменений, проверки CI-скриптов прошли, `flutter analyze` — без замечаний, обычные тесты — 3213 прошли, процессные тесты `flutter_process` — 18 прошли. `mise run codegen-check` прошёл, и рабочее дерево осталось чистым. `mise exec --no-deps -- openspec validate add-graph-export-import --strict` прошла. Каждая задача 3.28–3.34 сопоставлена с кодом и тестами её коммита. Диапазон не меняет `android/`, `pubspec.yaml` и `pubspec.lock`, поэтому APK не собирался. |
| Code quality | Complete | Все 27 путей поставки и тестов пройдены по линзам `code-review-and-quality`: корректность, читаемость, архитектура, безопасность, производительность и доказательность. Учтены неизменённые `graph_log_compaction.dart`, `graph_snapshot_store.dart`, `daily_choice_local_day_observer.dart`, `daily_choice_local_date_provider.dart` и места использования `classifySqliteFailure`. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Копии, сделанные после повреждённого последнего снимка до его пересборки, не восстанавливаются, пока хранятся

- **Evidence:** `lib/src/graph/data/drift_personal_graph_repository_fact_log.dart:296-347`. `_removeHistoryBefore` сохраняет для каждой хранимой копии ближайший снимок не новее её позиции (`backupSnapshotIds`, строки 313–344) и не учитывает, прошёл ли снимок проверку. Если последний снимок L не проходит проверку, неизменённый `lib/src/graph_snapshots/graph_log_compaction.dart:298-308` пересобирает снимок R из базы и вызывает `removeHistoryBefore(R.position)`. Для копии D, сделанной между L и R, ближайшим снимком остаётся L, и граница хранения его не удаляет. Восстановление собирает состояние от ближайшего снимка (`lib/src/graph_snapshots/graph_snapshot_store.dart:134-139`), получает `GraphSnapshotCorruption`, и человек видит «Не удалось восстановить копию. Ничего не изменено». На базе `6c9b22e8` снимок L удалялся, если копия старше L удерживала более ранний снимок и пакеты после него. Тогда D восстанавливалась воспроизведением больше порога пакетов. Сборка состояния читает пакеты после выбранного снимка и не проверяет их непрерывность (`lib/src/graph_snapshots/graph_snapshot_store.dart:700-713`, `_readHistoryPackages`).
- **Evidence revisions:** ["b28e1db28f14512d628d546075c703204f70fc12", "6c9b22e85c2448527a39499e8cf01fb920285219"]
- **Potential impact:** Если файл последнего снимка повреждён, каждая копия, сделанная между ним и пересборкой (обычно копии за последний интервал сжатия, до 1000 команд), отказывает в восстановлении, пока не выйдет из окна хранения копий. Это до 7 дней с изменениями. Граф, экспорт, сводки копий и более старые копии не затрагиваются, а отказ виден человеку и ничего не меняет.
- **Acceptance rationale:** Нужен физически повреждённый файл во внутреннем хранилище. Переход на более ранний снимок помог бы, только если его и пакеты после него удерживает более старая копия, а восстановление воспроизводило бы больше порога пакетов, вплоть до всей истории окна копий. Тем самым нарушалась бы граница памяти восстановления, ради которой задача 3.28 сохраняет ближайший снимок каждой копии. Кроме того, понадобилось бы правило с защитой от тихо неверного графа, потому что сборка состояния не проверяет непрерывность пакетов.
- **Scope and assumptions:** Только копии, у которых ближайший снимок не новее их позиции не прошёл проверку, а состояние нельзя собрать иначе в пределах сохраняемой истории. Граница хранения сохраняет ближайший снимок каждой хранимой копии, а восстановление собирает состояние только от него и не больше чем из порога пакетов после него. Повреждение снимка обнаруживается проверкой при чтении, отказ восстановления оставляет граф и копии прежними.
- **Reopen when:** Восстановление начинает переходить на другой снимок или иначе обходить повреждённый. Отказ восстановления копии при повреждённом снимке меняет граф или копии либо перестаёт быть видимым. Появляется сценарий, в котором повреждение снимков становится частым или массовым, например запись снимков без fsync и атомарного переименования. Решение 7 дизайна или ADR-0034 меняют правило хранения или сборки состояния.
- **Acceptance authority:** Явное решение владельца продукта в сессии разбора F1 2026-10-19: «Принять риск».
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** `docs/adr/0034-record-confirmed-graph-changes-in-local-fact-log.md` («Состояния, которые собирались из повреждённого снимка, восстановить нельзя») и `openspec/changes/add-graph-export-import/design.md`, решение 7 «Пересборка из базы».

## Review coverage

**Цель и сопоставление.** Цель — 7 коммитов от `5caf5ead` до `b28e1db2` и 28 путей. Рабочее дерево чистое, `HEAD` совпадает с проверяемой головой. Прежний отчёт относился к диапазону `51c9e34e..9a0a612b` (задачи 3.1–3.27). Активных замечаний и принятых рисков в нём не было, поэтому переносить нечего. `tasks.md` — свидетельство планирования: диапазон меняет в нём только отметки 3.28–3.34. Каждая задача сопоставлена со своим коммитом и единицей U1–U5, а каждый путь поставки входит в единицу. Посторонней работы и путей без задачи нет.

**Проверенные свойства.** Ближайший снимок копии выбирается тем же порядком (позиция, затем номер), что и `readSnapshotAtOrBefore`. Он не старше базы границы, поэтому пакеты после него сохраняются. Тест сжатия падал бы без правила: промежуточные снимки удалялись бы. Классификатор разворачивает `CouldNotRollBackException` и вложенные `DriftRemoteException` до исходной ошибки. Отказ отката после ошибки, которая не откатывает транзакцию сама, недостижим: обычный `ROLLBACK` тогда проходит. Восстановление в этом случае даёт исход и диагностику нехватки места, а граф, копии, лог, реестр и каталог снимков остаются прежними. `request()` и `passPointOfNoReturn()` синхронны в одном изоляте и исключают друг друга. Точка невозврата стоит после включения захвата, непосредственно перед COMMIT, и все обновления хода приходят до неё, поэтому `GraphRestoreCommitting` не сменяется на `GraphRestoreRunning`. Отказ COMMIT после точки невозврата по-прежнему даёт отказ восстановления под строкой. Hook `beforeTransactionCommit` добавлен в наблюдатель соединения, который используют только тесты и бенчмарки: без него проверка не удержит транзакцию между точкой невозврата и COMMIT. Наблюдатель местной даты освобождается в `dispose` каждой поверхности. Без `footer` дерево `Sheet` не меняется, а отступы кнопки совпадают с прежними.

**Рассмотрено, но в замечания не записано.** Зависимость `data_transfer` от `daily_choice/presentation/catalog` задана задачей 3.32 и уже есть у Главной и страницы намерения. Часы копий и источник местной даты в приложении читают одни и те же часы устройства, а разойтись могут только в тестах. Копии, сделанные до обновления сборками со старым правилом сжатия, могли потерять промежуточные снимки. Но установок с данными нет, а план требует очистить данные сборок предыдущих этапов, поэтому этот случай недостижим.

**Ограничения.** На устройстве ничего не проверялось, эти проверки остаются ручными проверками пользователя: недоступная «Отменить» после точки невозврата и её чтение экранным диктором, смена «сегодня» на «вчера» в строке, панели и подтверждении после полуночи, закреплённая кнопка в длинном списке копий и нехватка места на реальном хранилище.
