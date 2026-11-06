# ADR Review Manifest

- Status: completed
- Review date: 2026-11-06

## Review Summary

Просмотрены решения о модуле графа и ревизиях, счётчиках связей, журнале фактов, формате данных, замене графа, синхронизации, статистике через связи, поиске намерений, потоках создания, модальных сессиях, листах, навигации и предъявлении результатов. Долговечными и не покрытыми действующими записями оказались шесть решений `design.md`: путь действия с общими надгробиями (D2, D3), индекс удержания (D5), исполнение каскада по подтверждённому составу (D6–D8), лист нового действия как маршрут с сессией (D11), панель действия и экран пути (D12) и опорные намерения статистики (D15). Они частично пересматривают ADR-0022, ADR-0026 и ADR-0051 и заменяют ADR-0054.

Сверка выявила в `design.md` одно расхождение: D8 предлагал вместо абсолютных количеств связей в пакетах передавать множество затронутых намерений, что пересматривало бы ADR-0011 и ADR-0043 без доказанной необходимости. D8 исправлен: пакеты каскада несут абсолютные количества по ADR-0011, а пересмотр допускается только после бенчмарка крупного каскада. Остальные решения тактические или применяют существующие записи: новая базовая схема — разовое решение этого изменения, новый состав формата версии 1 следует ADR-0035, быстрое создание — ADR-0021. Нерешённых существенных вопросов нет, поэтому `grill-with-docs` не применялся. `design.md` согласован с записями ниже.

Записи, где дневные выборы и готовность к действию остаются только в формулировках, а решение не меняется, получают терминологические правки при реализации: ADR-0017, ADR-0024, ADR-0025, ADR-0028, ADR-0031, ADR-0032, ADR-0033, ADR-0034, ADR-0035, ADR-0041, ADR-0047, ADR-0049, ADR-0050, ADR-0052, ADR-0053. Принятая ADR-0001 упоминает дневной выбор и готовность к действию в обосновании и сохраняет его по `ADR-FORMAT.md`. Упоминания в ADR-0022, ADR-0026, ADR-0051 и ADR-0054 относятся к частям, которые заменяют ADR-0055, ADR-0058, ADR-0059 и ADR-0060; в остальных записях остаются только поля происхождения, имена изменений и имена файлов в ссылках.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Все команды действий, вида и каскада идут через единственный координатор, одну транзакцию и одну ревизию; отдельного репозитория действий нет. Ограничение.
- [ADR-0010](../../../docs/adr/0010-persist-long-term-relation-creation-order.md) — accepted. Порядок создания действий хранится так же, автоинкрементом отдельно от идентичности. Ограничение.
- [ADR-0011](../../../docs/adr/0011-derive-relation-counts-from-graph-snapshots.md) — accepted. Пакеты каскада несут абсолютные количества связей всех затронутых намерений. Ограничение для D8.
- [ADR-0043](../../../docs/adr/0043-read-relation-counts-only-for-intention-page.md) — proposed, изменение `redesign-intention-page` в архиве. Количества по-прежнему только у страницы намерения и в пакетах; группы связей дневных выборов из сводки уходят.
- [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — accepted. Лист нового действия — модальная сессия в корневом стеке; все способы ухода, включая сброс истории, согласуются до освобождения черновика. Ограничение для D11.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, изменение `add-quick-creation-and-persistent-navigation` в архиве. Граница потока остаётся; правило завершения для действия пересматривает ADR-0058, возврат замены пути — ADR-0059.
- [ADR-0026](../../../docs/adr/0026-compute-contribution-through-relations-off-queue.md) — proposed, изменение `add-contribution-statistics` в архиве. Снимок связей, изолят, кэш и сброс сохраняются; опорные намерения пересматривает ADR-0060. Образец для индекса удержания.
- [ADR-0034](../../../docs/adr/0034-record-confirmed-graph-changes-in-local-fact-log.md) — proposed, изменение в архиве. Механизм захвата триггерами без изменений; новые таблицы действий, путей и надгробий получают свои отметки.
- [ADR-0035](../../../docs/adr/0035-keep-graph-data-in-versioned-domain-format.md) — proposed, изменение `add-graph-export-import` в архиве. Версия формата остаётся 1 с новым составом до публикации; ссылки только назад определяют порядок разделов. Ограничение для D14.
- [ADR-0036](../../../docs/adr/0036-replace-graph-atomically-with-new-epoch-and-generation.md) — proposed, изменение `add-graph-export-import` в архиве. Замена графа охватывает действия, пути и надгробия.
- [ADR-0038](../../../docs/adr/0038-sync-devices-through-thin-encrypted-file-server.md) — proposed, изменение в архиве. Список постоянных инвариантов меняется (непрерывность пути уходит, появляется целостность надгробий); пересмотр относится к изменению синхронизации, вне объёма.
- [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md) — proposed, изменение `redesign-intention-catalog` в архиве. Каталог и поиски остаются одним модулем; фильтр вида и назначение поиска начала пути встраиваются в него.
- [ADR-0051](../../../docs/adr/0051-identify-long-term-relation-by-immutable-pair.md) — proposed, изменение `add-relations-in-batches` в архиве. Неизменная пара остаётся идентичностью связи и звена пути; положения о шагах пути пересматривает ADR-0055.
- [ADR-0053](../../../docs/adr/0053-open-ordinary-pages-independently-of-picker-history.md) — proposed, изменение `open-full-intention-pages-from-pickers` в архиве. Страница намерения из поиска полноценна, в том числе для создания действия; второй черновик действия — самостоятельный поток.
- [ADR-0054](../../../docs/adr/0054-show-and-change-daily-choice-in-one-routeless-sheet.md) — proposed, изменение `redesign-daily-choices` в архиве. Историческая для действия: её правила панели перенесены в ADR-0059, которая её заменяет.

## Additional Context

- [ADR-0008](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md) — accepted. Триггеры надгробий не используют функций схемы, поэтому долговечный набор функций не меняется.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md), [ADR-0016](../../../docs/adr/0016-present-only-failure-for-self-evident-success.md), [ADR-0023](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md), [ADR-0046](../../../docs/adr/0046-keep-edit-failures-on-screen-without-success-message.md) — accepted и proposed из архивных изменений. Одно сообщение об исходе каскада и молчаливый успех изменения полей и пути действия следуют этим правилам.
- [ADR-0014](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md), [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, изменения в архиве. Перехват сброса истории стоит в общем обработчике пунктов панели оболочки и обычных страниц.
- [ADR-0021](../../../docs/adr/0021-separate-installation-preferences-from-personal-graph.md) — proposed, изменение в архиве. Режим быстрого создания остаётся настройкой установки с новым ключом.
- [ADR-0024](../../../docs/adr/0024-derive-calendar-day-states-from-saved-daily-choices.md), [ADR-0025](../../../docs/adr/0025-load-calendar-day-marks-in-separate-viewport-model.md), [ADR-0033](../../../docs/adr/0033-coordinate-daily-choice-sections-on-one-revision.md) — proposed, изменения в архиве. Состояния дней, отметки календаря и секции дня применяются к действиям без изменения решений.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, изменение в архиве. Сессия листа нового действия и экраны пути держат состояние в своих экземплярах.
- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md), [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md), [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md), [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md), [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed, изменения в архиве. Новые компоненты остаются представлениями; панель действия и лист нового действия используют общие листы и показывают сообщения в собственном `Scaffold`.

## ADRs Owned by This Change

- [ADR-0055](../../../docs/adr/0055-store-action-path-as-intention-sequence-with-shared-tombstones.md) — proposed. Путь как последовательность намерений и общие надгробия удалённого; частично заменяет ADR-0051.
- [ADR-0056](../../../docs/adr/0056-compute-intention-holding-in-per-revision-index.md) — proposed. Индекс удержания на ревизию графа вне очереди записи.
- [ADR-0057](../../../docs/adr/0057-execute-cascade-against-previewed-composition.md) — proposed. Один планировщик каскада, предпросмотр и проверка конфликта по множествам затронутых намерений.
- [ADR-0058](../../../docs/adr/0058-create-actions-in-open-route-sheet-sessions.md) — proposed. Лист нового действия — маршрут с сессией, остаётся открытым, сброс истории спрашивает; частично заменяет ADR-0022.
- [ADR-0059](../../../docs/adr/0059-show-action-in-routeless-sheet-and-change-path-on-own-screen.md) — proposed. Панель действия без маршрута и экран пути, который сам выполняет замену; заменяет ADR-0054 и частично ADR-0022.
- [ADR-0060](../../../docs/adr/0060-count-actions-through-relations-from-existing-path-intentions.md) — proposed. Опорные намерения статистики — существующие намерения пути; частично заменяет ADR-0026.
