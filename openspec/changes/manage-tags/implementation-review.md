# OpenSpec Implementation Review: manage-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Два замечания к согласованию выбранного тега: пакет подтверждённой команды может быть пропущен после опережающего чтения страницы (F1), а сообщение об отсутствии выбранного тега может вновь открыть действия устаревшей строки (F2). Задача 1.30 отмечена выполненной, но критерий согласованного каталога пока не подтверждён.

## Review target

- **Baseline ref:** c7fd121af6757c162bf62864e43271a2140ee4ae
- **Base commit:** c7fd121af6757c162bf62864e43271a2140ee4ae
- **Reviewed head:** e6596932ad7cdde9a2ecaea865d236468d931fb5
- **Target commits:** ["6194fd1f6f9f3921b9e4da406e7481b492357d29", "a55a6b6ddb1c599e8489a361e177e303ddc9254a", "bc85426869173259f000c5391cb55a5fa5ffe5c1", "e6596932ad7cdde9a2ecaea865d236468d931fb5"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.g.dart", "lib/src/tag/presentation/editor/tag_editor_page.dart", "lib/src/tag/presentation/editor/tag_editor_state.dart", "lib/src/tag/presentation/editor/tag_editor_view_model.dart", "lib/src/tag/presentation/editor/tag_editor_view_model.g.dart", "openspec/changes/manage-tags/tasks.md", "test/app/tag_app_lifecycle_test.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart", "test/tag/presentation/editor/tag_editor_page_test.dart", "test/tag/presentation/editor/tag_editor_view_model_test.dart"]
- **OpenSpec change:** manage-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-tags/tasks.md"]

## Reviewed increment

### U1 · Согласование выбранного тега с подтверждённым каталогом

- **Work items:** ["1.27", "1.30"]
- **Requirements and scenarios:** ["Подтверждённые изменения и согласованные представления тегов", "Запоздалое чтение после переименования", "Получение данных и безопасные ошибки тегов"]
- **Affected boundary:** Пользователь открытого каталога → состояние выбора и порционные чтения → общий канал подтверждённых изменений и наблюдение тега.
- **Implementation target:** ["lib/src/tag/presentation/catalog/tag_catalog_page.dart", "lib/src/tag/presentation/catalog/tag_catalog_state.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "lib/src/tag/presentation/catalog/tag_catalog_view_model.g.dart", "test/app/tag_app_lifecycle_test.dart", "test/tag/presentation/catalog/tag_catalog_page_test.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart"]
- **Applicable constraints and non-goals:** Идентичность определяется `TagId`; каталог читается ограниченными порциями; после подтверждения записи поздний ответ не возвращает старое состояние. Назначения и навигация по помеченным сущностям относятся к следующим фазам.

### U2 · Видимый исход повторного сохранения занятой формы

- **Work items:** ["1.28", "1.30"]
- **Requirements and scenarios:** ["Подтверждённые изменения и согласованные представления тегов", "Повторная отправка создания", "Локализация и доступность управления тегами"]
- **Affected boundary:** Повторно открытая форма создания или переименования → общий координатор команд → локализованное сообщение и единый канал результата.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/tag/presentation/editor/tag_editor_page.dart", "lib/src/tag/presentation/editor/tag_editor_state.dart", "lib/src/tag/presentation/editor/tag_editor_view_model.dart", "lib/src/tag/presentation/editor/tag_editor_view_model.g.dart", "test/app/tag_app_lifecycle_test.dart", "test/tag/presentation/editor/tag_editor_page_test.dart", "test/tag/presentation/editor/tag_editor_view_model_test.dart"]
- **Applicable constraints and non-goals:** Принятая запись завершается после ухода с формы, повторная команда не ставится в очередь, ввод новой сессии сохраняется, результат предъявляется один раз; сообщение доступно на ru/en.

### U3 · Завершение сообщения о занятом удалении

- **Work items:** ["1.29", "1.30"]
- **Requirements and scenarios:** ["Удаление общего тега", "Подтверждённые изменения и согласованные представления тегов", "Локализация и доступность управления тегами"]
- **Affected boundary:** Повторное подтверждение в каталоге → общий координатор команд → сообщение о занятости и конечный результат удаления.
- **Implementation target:** ["lib/src/tag/presentation/catalog/tag_catalog_page.dart", "test/tag/presentation/catalog/tag_catalog_delete_test.dart"]
- **Applicable constraints and non-goals:** Удаление требует отдельного подтверждения для конкретного `TagId`; повтор не создаёт вторую запись, занятость исчезает по завершении исходной команды, итог предъявляется по общему протоколу на ru/en.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий рецензент с нулевой историей проверил все 19 изменённых delivery/test путей U1–U3 на точном диапазоне; неизменённые контракт, координатор и адаптер чтения использованы только как контекст. |
| OpenSpec conformance | Complete | Сопоставлены задачи 1.27–1.30, спецификация, дизайн и тесты. На HEAD e6596932ad7cdde9a2ecaea865d236468d931fb5 прошли `mise exec --no-deps -- openspec validate manage-tags --json` и `--strict --no-interactive`, 47 тестов `test/tag/presentation test/app/tag_app_lifecycle_test.dart` и `mise run --skip-tools check` (форматирование, анализ, 1669 тестов). Выводы F1–F2 ограничивают подтверждение критериев 1.27 и 1.30. |
| Code quality | Complete | На зафиксированном HEAD проверены корректность гонок, читаемость состояний, границы модулей, безопасность сообщений и стоимость чтения во всех изменённых delivery-путях; `git diff --check` прошёл. |

## Findings

### F1 · High — Опережающее чтение страницы скрывает изменение выбранного тега

- **Evidence:** `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart:300-309` отбрасывает подтверждённый пакет, если ревизия страницы уже равна ревизии команды, до обработки выбора на строках 321-335. `watchTag` обновляет выбор отдельным асинхронным потоком. `lib/src/tag/presentation/catalog/tag_catalog_page.dart:274-350` показывает прежний выбранный объект поверх свежей страницы, в том числе как отдельную строку с действиями после удаления. Проверки `test/tag/presentation/catalog/tag_catalog_view_model_test.dart` покрывают позднее чтение старой ревизии, но не страницу новой ревизии до публикации пакета.
- **Evidence revisions:** ["e6596932ad7cdde9a2ecaea865d236468d931fb5"]
- **Impact:** После подтверждённого переименования старое название остаётся на экране; после удаления вне загруженной порции удалённый тег может вновь отображаться с действиями до следующего сигнала наблюдения. Критерии 1.27 и 1.30 о согласованном каталоге не выполнены во всех допустимых порядках завершения.
- **Required outcome:** Подтверждённый пакет должен согласовывать выбранную идентичность независимо от того, успела ли страница перейти на его ревизию; запоздалое чтение не должно возвращать старый выбор или действия.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "lib/src/tag/presentation/catalog/tag_catalog_page.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart", "openspec/changes/manage-tags/tasks.md"]

### F2 · Medium — Отсутствующий выбранный тег остаётся действующей строкой страницы

- **Evidence:** `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart:129-153` после `watchTag` с результатом `null` очищает только выбор, сохраняя прежний `TagCatalogLoaded.items`; строки 107-116 вновь разрешают действие по наличию `TagId` в этой порции. `lib/src/tag/presentation/catalog/tag_catalog_page.dart:332-350` показывает действия уже не выбранной устаревшей строки. В тестах проверено очищение выбора при пакете удаления, но не при более раннем ответе `watchTag(null)`.
- **Evidence revisions:** ["e6596932ad7cdde9a2ecaea865d236468d931fb5"]
- **Impact:** Между подтверждением удаления и публикацией пакета командами из каталога можно попытаться действовать по уже отсутствующему тегу; при изменении без пакета строка остаётся до иной актуализации. Прежнее название видимо как обычный актуальный элемент.
- **Required outcome:** Подтверждённое отсутствие выбранного тега должно убрать его загруженную строку либо запретить действия по ней до согласования страницы.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/tag/presentation/catalog/tag_catalog_view_model.dart", "lib/src/tag/presentation/catalog/tag_catalog_page.dart", "test/tag/presentation/catalog/tag_catalog_view_model_test.dart", "openspec/changes/manage-tags/tasks.md"]

## Review coverage

Все четыре целевых коммита и задачи 1.27–1.30 охвачены U1–U3. Каждый из 20 изменённых путей включён в review unit либо отмечен как planning evidence; других путей в диапазоне нет. Сверены поток чтения выбранного тега, ревизии порционного каталога, публикация координатора, завершение занятых команд, локализации и семантика сообщений; неизменённые координатор и адаптер чтения использованы как контекст. Отчёт касается только зафиксированного диапазона и не меняет состояние задач.
