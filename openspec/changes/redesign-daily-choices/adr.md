# ADR Review Manifest

- Status: completed
- Review date: 2026-11-01

## Review Summary

Просмотрены решения о модуле графа, предъявлении результатов, потоках создания, каркасах страниц, листах, модуле основ и каталоге дневных выборов. Долговечным и не покрытым действующими записями оказалось одно решение `design.md`: дневной выбор показывается и меняется в одном листе без маршрута, создание его не открывает, а страницы открываются поверх листа (D1, D9, D11). Оно частично пересматривает ADR-0022.

Остальные решения тактические либо применяют существующие записи: успех без сообщения следует ADR-0046, запись отказа — ADR-0012, вариант листа — ADR-0030 и ADR-0041. Неизменность пути отдельной записи не получила: по решению владельца продукта это поведение приложения, а не инвариант данных.

Сверка выявила в `design.md` два упущения, оба исправлены: отказы панели идут через `OperationFailurePresentation` по ADR-0012, а компактная высота равна общему пределу ADR-0041, а не 560 из README `Sheet`. Нерешённых существенных вопросов нет, поэтому `grill-with-docs` не применялся. `design.md` согласован с записями ниже.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Запись панели идёт через один координатор и пакеты изменений. Ограничение.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted. Отказ принадлежит открытой панели и переходит общей поверхности после её закрытия. Ограничение для D2.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, изменение `add-quick-creation-and-persistent-navigation` в архиве. Страницы и каркасы сохраняются, лист к ним не относится.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, изменение `add-quick-creation-and-persistent-navigation` в архиве. Граница потока сохраняется, правило о замене корня для дневного выбора пересматривает ADR-0053.
- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, изменение `redesign-daily-choice-calendar` в архиве. Новые компоненты остаются представлениями и появляются вместе с потребителем.
- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — proposed, изменение `redesign-navigation-bar` в архиве. Панель показывается общей функцией листа.
- [ADR-0033](../../../docs/adr/0033-coordinate-daily-choice-sections-on-one-revision.md) — proposed, изменение `enrich-daily-choice-catalog` в архиве. Обе секции уже читаются на одной ревизии, поэтому счётчики и признак времени дня доступны без нового чтения.
- [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md) — proposed, изменение `add-tags-panel` в архиве. Общий предел компактной высоты и связь варианта листа с показом.
- [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md) — proposed, изменение `add-tags-panel` в архиве. Панель выполняет операции и показывает сообщения в собственном `Scaffold`.
- [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed, изменение `unify-bottom-sheets` в архиве. Полный размер при изменении описания добавляется к этой модели.
- [ADR-0046](../../../docs/adr/0046-keep-edit-failures-on-screen-without-success-message.md) — proposed, изменение `redesign-intention-page` в архиве. Политика «успех без сообщения» для изменения дневного выбора.
- [ADR-0052](../../../docs/adr/0052-add-relations-as-one-batch-from-group-picker.md) — proposed, активное изменение `add-relations-in-batches`. Координация: запись сняла правило ADR-0022 для связей и оставила для дневного выбора, что теперь пересматривается. Файла пока нет в `main`.

## Additional Context

- [ADR-0017](../../../docs/adr/0017-isolate-inline-calendar-behind-app-component.md) — proposed, изменение `add-inline-daily-choice-calendar` в архиве. Календарь каталога не меняется, лист даты собирается из частей модуля основ.
- [ADR-0024](../../../docs/adr/0024-derive-calendar-day-states-from-saved-daily-choices.md) — proposed, изменение `add-daily-choice-calendar-day-marks` в архиве. Лист даты читает те же состояния дней.
- [ADR-0025](../../../docs/adr/0025-load-calendar-day-marks-in-separate-viewport-model.md) — proposed, изменение `add-daily-choice-calendar-day-marks` в архиве. Лист даты использует ту же модель отметок.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, изменение `add-contribution-statistics` в архиве. Лист даты держит собственный экземпляр модели отметок.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, изменение `add-design-foundation` в архиве. Значения новых компонентов берутся из модуля основ.
- [ADR-0051](../../../docs/adr/0051-identify-long-term-relation-by-immutable-pair.md) — proposed, активное изменение `add-relations-in-batches`. Сравнение: у связи неизменность жёсткая и закреплена в схеме, а у пути выбора это только поведение приложения. Файла пока нет в `main`.

## ADRs Owned by This Change

- [ADR-0053](../../../docs/adr/0053-show-and-change-daily-choice-in-one-routeless-sheet.md) — proposed. Лист без маршрута как единственное место просмотра и изменения, кроме флажка выполнения в карточке, создание без открытия сущности и страницы поверх листа.
