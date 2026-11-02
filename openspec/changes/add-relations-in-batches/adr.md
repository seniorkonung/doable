# ADR Review Manifest

- Status: completed
- Review date: 2026-11-01

## Review Summary

Просмотрены решения о модуле графа, предъявлении результатов, потоках создания, листах, поиске намерений и занятых парах. Два решения `design.md` долговечны и не покрыты действующими записями: неизменная пара как идентичность связи (D1, D2) и атомарная пачка с завершением без открытия сущности и без панели навигации над поиском (D3, D5, D6, D7). Остальные решения применяют существующие записи: поиск строится по ADR-0049, лист показывается по ADR-0032, политика сообщений берётся из ADR-0046, даты связи (D12) следуют ADR-0006. `design.md` согласован с итоговым набором записей: D3, D4 и D7 опираются на ADR-0052, D1 и D2 — на ADR-0051.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Команды идут через один координатор и пакеты изменений. Ограничение для пачки и согласования отметок.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted. Успех принадлежит общей поверхности, отказ — открытой сессии инициатора. Ограничение для сообщений поиска и панели.
- [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — accepted. Панель создания намерения остаётся одной модальной сессией и при запуске из поиска.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, изменение `add-quick-creation-and-persistent-navigation` в архиве. Каркас по контексту открытия сохраняется, а над поиском участника действует исключение из ADR-0052.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, изменение `add-quick-creation-and-persistent-navigation` в архиве. Граница потока сохраняется для намерения и дневного выбора. Для связей частично пересматривается ADR-0052.
- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — proposed, изменение `redesign-navigation-bar`. Подробный просмотр показывается общей функцией листа.
- [ADR-0046](../../../docs/adr/0046-keep-edit-failures-on-screen-without-success-message.md) — proposed, изменение `redesign-intention-page`. Политика «успех без сообщения» для изменения, архивирования и восстановления связи.
- [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md) — proposed, изменение `redesign-intention-catalog`. Поиск участника остаётся на общем модуле, а различия выражаются данными.
- [ADR-0050](../../../docs/adr/0050-mark-occupied-pairs-in-same-catalog-page.md) — proposed, изменение `mark-occupied-pairs-in-relation-participant-picker` в архиве. Вычисление занятости сохраняется, состав пробы частично пересматривается ADR-0052.

## Additional Context

- [ADR-0006](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md) — accepted. Даты связи остаются наблюдениями и не задают порядок.
- [ADR-0008](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md) — accepted. Новая базовая схема меняет таблицу и триггеры, но не функции схемы.
- [ADR-0010](../../../docs/adr/0010-persist-long-term-relation-creation-order.md) — accepted. Последовательность создания задаёт порядок связей пачки.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, изменение `add-contribution-statistics`. Модель отметок живёт вместе с экземпляром поиска.
- [ADR-0034](../../../docs/adr/0034-record-confirmed-graph-changes-in-local-fact-log.md) — proposed, изменение `add-graph-export-import`. Пачка даёт один пакет фактов, новых таблиц нет.
- [ADR-0035](../../../docs/adr/0035-keep-graph-data-in-versioned-domain-format.md) — proposed, изменение `add-graph-export-import`. Запись связи в формате получает показания времени.
- [ADR-0043](../../../docs/adr/0043-read-relation-counts-only-for-intention-page.md) — proposed, изменение `redesign-intention-pickers`. Абсолютные счётчики идут в пакетах команд для всех участников пачки.
- [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed, изменение `unify-bottom-sheets`. Полный размер листа при изменении описания добавляется к этой модели.
- [ADR-0047](../../../docs/adr/0047-publish-active-and-archived-parts-of-relation-group-together.md) — proposed, изменение `redesign-intention-page`. Группа согласует обе части одним состоянием и при добавлении пачки.

## ADRs Owned by This Change

- [ADR-0051](../../../docs/adr/0051-identify-long-term-relation-by-immutable-pair.md) — proposed. Неизменная пара как идентичность связи и тип как изменяемый атрибут.
- [ADR-0052](../../../docs/adr/0052-add-relations-as-one-batch-from-group-picker.md) — proposed. Пачка одной командой и возврат результата вспомогательного создания своей задаче.
