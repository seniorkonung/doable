# OpenSpec Implementation Review: add-graph-export-import

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 1.33–1.36 этапа 1 выполнены по существу. Тесты отката внедряют отказ на названной записи таблицы графа. Начальный U+FEFF исходного TEXT больше не проверяет ни одно чтение. Хранимый текст намерения проверяется за один проход. Модуль снимков распознаёт повреждённую строку графа через собственный контракт лога и не зависит от данных графа. Полные проверки и строгая проверка OpenSpec на голове проходят. Активных замечаний и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** c6fcb515180a38cdbecd862e22e9bc5636bcafc7
- **Base commit:** c6fcb515180a38cdbecd862e22e9bc5636bcafc7
- **Reviewed head:** 37028f5cc9f106e8a654e717b8e0dd9ef857e56d
- **Target commits:** ["8fae58b2cc565e007e270a2f39ffb77e279f4acc", "c473ecb49e8715f3afb6fbe99e4421962bc0fcf0", "9fe77388296667ddf71dcaef793ef1d14f5768c5", "37028f5cc9f106e8a654e717b8e0dd9ef857e56d"]
- **Reviewable paths:** ["lib/src/graph/data/drift_personal_graph_repository_fact_log.dart", "lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart", "lib/src/graph/data/stored_graph_rows.dart", "lib/src/graph_snapshots/graph_fact_log.dart", "lib/src/graph_snapshots/graph_snapshot_store.dart", "openspec/changes/add-graph-export-import/tasks.md", "test/graph/data/drift_tagged_entities_read_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/data/drift_intention_repository_fault_test.dart"]
- **OpenSpec change:** add-graph-export-import
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-graph-export-import/tasks.md"]

## Reviewed increment

### U1 · Тесты отката и классификации отказов команд намерений внедряют отказ на названной записи таблицы графа

- **Work items:** ["1.33"]
- **Requirements and scenarios:** ["design: решение 5 — признак записи единого пути ставится первой записью транзакции команды", "plan: Phase 1 Ready — после каждого вида команды, включая каскадное архивирование, база совпадает с состоянием из снимка и лога"]
- **Affected boundary:** Разработчики, которые опираются на тесты отказов `DriftPersonalGraphRepository` как на доказательство атомарного отката и классификации неизвестных отказов команд намерений.
- **Implementation target:** ["test/intention/data/drift_intention_repository_fault_test.dart"]
- **Applicable constraints and non-goals:** Код приложения, сценарии, ожидания и названия тестов не меняются. Служебные записи лога фактов не смещают точку отказа.

### U2 · Начальный U+FEFF исходного TEXT не проверяет ни один потребитель строк графа

- **Work items:** ["1.34"]
- **Requirements and scenarios:** ["design: решение 5 — форму хранения значений графа определяет только общий декодер", "local-data-lifecycle: Обработка обнаруженного повреждения данных"]
- **Affected boundary:** Чтения назначенных тегов и страницы намерений с тегом; команды, захват фактов и чтение записей порциями, которые разбирают те же строки.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository_tag_reads.dart", "lib/src/graph/data/drift_personal_graph_repository_tagged_intentions.dart", "test/graph/data/drift_tagged_entities_read_test.dart", "test/intention/data/drift_intention_catalog_test.dart"]
- **Applicable constraints and non-goals:** По решению владельца продукта приложение не обязано обнаруживать начальный U+FEFF в значениях, которые само так не пишет. Для данных приложения результаты чтений и команд, пакеты фактов и записи порций не меняются. Ограничение схемы на название тега и его тесты не меняются.

### U3 · Хранимый текст намерения проверяется в общем декодере за один проход

- **Work items:** ["1.35"]
- **Requirements and scenarios:** ["design: решение 5 — у каждой таблицы декодер один, строка вне формы хранения даёт общий отказ повреждения"]
- **Affected boundary:** Все потребители общего декодера строк графа: чтения и команды репозитория, захват фактов и чтение записей порциями.
- **Implementation target:** ["lib/src/graph/data/stored_graph_rows.dart"]
- **Applicable constraints and non-goals:** Набор проверок текста не меняется. Для данных приложения результаты, `GraphChange`, пакеты фактов и записи порций не меняются. Остальные декодеры файла вне задачи.

### U4 · Модуль снимков распознаёт строку графа вне формы хранения через собственный контракт лога фактов

- **Work items:** ["1.36"]
- **Requirements and scenarios:** ["design: решение 5 — пересборка снимка на строке вне формы хранения диагностируется категорией повреждения", "design: решение 14 — безопасная категория отказа в диагностике снимков"]
- **Affected boundary:** Граница модуля снимков и данных графа; диагностика пересборки и сжатия; реализации `GraphFactLog`, включая межизолятную пересылку и тестовые подмены.
- **Implementation target:** ["lib/src/graph/data/drift_personal_graph_repository_fact_log.dart", "lib/src/graph_snapshots/graph_fact_log.dart", "lib/src/graph_snapshots/graph_snapshot_store.dart"]
- **Applicable constraints and non-goals:** События диагностики не содержат пользовательских данных. Для целостных данных события, результаты команд и чтений, пакеты фактов и записи порций не меняются. Чтения и команды репозитория сохраняют свои отказы повреждения.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Четыре новых изолированных ревьюера без истории по `implementation-decision-review`, по одному на каждую единицу U1–U4; пути единиц не пересекаются. Каждый получил только нейтральный бриф и точную цель `c6fcb515..37028f5c` со своими путями. Планирования, истории коммитов, отчёта и прежних находок у них не было. Все четыре вернули `No substantive findings` с полным покрытием. Ревьюер U2 сообщил, что один его поиск по содержимому из-за ошибки кавычек охватил и пути вне его границы, но совпадений в них не дал, так что их содержимое он не увидел. |
| OpenSpec conformance | Complete | Рабочая копия на `37028f5cc9f106e8a654e717b8e0dd9ef857e56d`: HEAD совпадает с проверяемой головой, отслеживаемые файлы, кроме этого отчёта, не изменены. `mise run check` — exit 0: `dart format` 696 файлов без изменений, `flutter analyze` без замечаний, прошли 2955 тестов без `flutter_process` и 14 тестов `flutter_process`. `mise exec --no-deps -- openspec validate add-graph-export-import --strict --json` — valid. Поиск из проверки задачи 1.34 находит только ограничение названия тега в `tag_schema.drift`, его копию в `app_database.g.dart` и тест в `sqlite_tag_functions_test.dart`. Поиск из проверки задачи 1.36 ничего не находит. Проверка задачи 1.35 в уточнённой формулировке выполняется на голове: проверка текста в `decodeStoredIntention` и `decodeStoredIntentionTitle` перехватывает только `IntentionTextValidationException`. Проверку задачи 1.33 повторила временная печать в перехватчиках: отказ внедряется после `UPDATE "intentions"`, после `UPDATE long_term_relations`, перед `UPDATE "intentions"` и перед `DELETE FROM "intentions"`. Файл теста после опыта восстановлен. Критерии задач 1.33–1.36 сверены по пунктам. Релизный APK `build/app/outputs/flutter-apk/app-release.apk` (70,6 МБ) собран на `37028f5c` командой `mise exec --no-deps -- flutter build apk --release` — exit 0. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены в контексте координатора ко всем девяти путям доставки на `37028f5c`. Контекст прочитан на голове: путь записи и порядок каскада архивирования в `drift_personal_graph_repository.dart`, наблюдатель операций в `database_connection.dart`, фабрики `Intention` и `DailyChoice`, `IntentionText`, межизолятная пересылка лога в `graph_log_compaction.dart`, общая пересылка `test/support/forwarding_graph_fact_log.dart` и тест пересборки на повреждённой строке. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Цель ревью — `c6fcb515180a38cdbecd862e22e9bc5636bcafc7..37028f5cc9f106e8a654e717b8e0dd9ef857e56d`, четыре коммита, по одному на задачи 1.33–1.36. Каждый коммит меняет код или тесты и отмечает свою задачу в `tasks.md`. Все 10 путей инвентаря учтены: `tasks.md` — свидетельство планирования, остальные девять путей распределены по U1–U4 без пересечений. Посторонних путей в диапазоне нет. Прежний отчёт активных замечаний и принятых рисков не содержал: его находки F1–F4 к этому моменту стали задачами 1.33–1.36, поэтому переносить нечего.

Каждая задача сопоставлена с единицей: 1.33 — с U1, 1.34 — с U2, 1.35 — с U3, 1.36 — с U4.

Тесты отката. Перехватчики выбирают точку отказа по виду операции и таблице графа. Служебные записи признака, отметок и пакетов идут в таблицы `graph_log_*` и с ней не совпадают. В `_changeArchiveState` архивирование связей предшествует изменению намерения, поэтому отказ после `UPDATE long_term_relations` приходится между шагами каскада. Если целевая запись не произойдёт, команда завершится успешно и тест упадёт на ожидании отказа, а не пройдёт вхолостую. Тест удаления тоже переведён на названную запись, потому что перечисление вида операции удалено.

Чтения тегов. Столбцы `has_leading_bom`, их разбор и `_checkTaggedTextEncoding` удалены. Удалены тест начального BOM названия и случай начального BOM в идентификаторе тега; название оставшегося случая не изменилось. Другие проверки начального U+FEFF в `lib/` остались только в ограничении схемы на название тега.

Декодер намерения. От `decodeStoredIntention` до готового `Intention` название проходит `IntentionText.normalizeTitle`, а описание — `normalizeDescription` ровно один раз, внутри фабрики. Результат фабрики сравнивается с хранимым текстом. Набор отказов прежний: недопустимый Unicode, пустое название и превышение длины дают исключение проверки, а пробелы по краям названия и пустое или пробельное описание дают расхождение с хранимым текстом. Путь записи хранит вывод той же фабрики, поэтому данные приложения проходят проверку без изменений. Критерий приёмки и проверка задачи 1.35 в `tasks.md` уточнены после проверяемой головы: теперь они касаются только проверки текста намерения. Код головы этой формулировке соответствует. Перехваты `ArgumentError` в `_decodeStoredIntentionTimestamp` (`stored_graph_rows.dart:171`) и `decodeStoredDailyChoice` (`:350`) появились до диапазона и к задаче не относятся. По решению 5 дизайна они превращают строку вне формы хранения в отказ повреждения.

Контракт лога фактов. `GraphRecordCorruption` объявлен в `graph_fact_log.dart` без данных и назван в документации `readGraphRecords`. Перевод из `StoredGraphCorruption` выполняет только `readGraphRecords`; других вызовов `_readGraphRecords` в библиотеке нет. Остальные операции лога `StoredGraphCorruption` не бросают. Межизолятная пересылка передаёт отказ как есть. Тест пересборки «строка графа вне формы хранения диагностируется отказом пересборки и сжатия с категорией повреждения» проходит настоящий путь до категории `corruption` и упал бы без перевода. `lib/src/graph_snapshots/` больше не импортирует `lib/src/graph/`.

Рассмотрено, но в замечания не записано. Каталог дневных выборов проверяет название намерения через `decodeStoredIntentionTitle`, а затем фабрика `DailyChoiceCatalogParticipant` нормализует его ещё раз (`drift_personal_graph_repository_daily_choice_catalog.dart:258`, `lib/src/daily_choice/application/daily_choice_catalog.dart:65`). Так было до диапазона, диапазон этого не менял, а захват фактов и чтение порциями этот путь не используют. Тест каскада полагается на порядок шагов в коде приложения, но при обратном порядке он не станет холостым: откат проверится после обеих записей.

Бенчмарк лога не перезапускался. Диапазон убирает из захвата фактов и чтения порциями один проход нормализации и добавляет один перехват на порцию, а ни одна задача диапазона замера не требует. Последняя серия на `165886d1` уложилась в бюджеты решения 15. `mise run codegen-check` не запускался: схема и сгенерированные файлы в диапазоне не менялись.

На устройстве ничего не проверялось, ручные проверки остаются за пользователем. Диапазон не меняет схему, поэтому данные сборки с `165886d1` подходят. Данные более ранних сборок этапа 1 перед установкой нужно очистить. Затем нужно проверить работу команд графа и появление снимков в `app_flutter/graph_snapshots/` после 1000 пакетов. На Android только устройство подтверждает разрешение символов `@Native` для fsync каталога и fsync в `RandomAccessFile.flush`.
