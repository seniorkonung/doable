# ADR Review Manifest

- Status: completed
- Review date: 2026-10-27

## Review Summary

Проверены решения [design.md](design.md) против индекса [docs/adr](../../../docs/adr/README.md) и записей, применимых к странице намерения, связям, предъявлению результатов, навигации и дизайн-системе. Высший номер до проверки — ADR-0045.

Два решения дизайна вводят долговременные обязательства, не покрытые действующими записями, и оформлены как ADR-0046 и ADR-0047:
- политика предъявления «успех без сообщения» для правки на отдельном экране;
- публикация активной и архивной частей группы связей одной моделью экземпляра страницы. Она частично пересматривает ADR-0009 и ADR-0043.

Остальные решения дизайна являются тактическими или применяют существующие записи:
- типизированная цель открытия, экран изменения как страница-задача, вкладки в одном прокручиваемом виде;
- новый тип строки группы, компоненты дизайн-системы, удаление массового удаления;
- выключенное удаление по сводке.

`design.md` согласован с итоговым набором ADR: решения 4, 6 и 13 ссылаются на ADR-0046 и ADR-0047, открытых архитектурных вопросов не осталось. Проверка навыком `grill-with-docs` не проводилась: в дизайне нет существенных нерешённых решений.

Проверка языка предметной области: изменение использует существующие термины `CONTEXT.md` — намерение, действие, тип намерения, готовность к действию, связь «нужно» и «можно», дневной выбор, архивирование, физическое удаление. Новых предметных понятий нет. Вкладки, цель открытия и группы страницы — понятия интерфейса и навигации, определённые в спецификациях.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Ограничение: единая граница графа, ревизия, согласование сводки с выбранной группой на одной ревизии. Частично пересматривается ADR-0047.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted. Ограничение: протокол claims, инлайн-предъявление отказа экраном изменения и передача оболочке.
- [ADR-0016](../../../docs/adr/0016-present-only-failure-for-self-evident-success.md) — proposed, originating change `add-home-navigation-and-favorites` (в архиве). Политика «только отказ» применяется к изменению готовности, архивированию и восстановлению; ADR-0046 дополняет её третьей политикой.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, originating change `add-contribution-statistics`. Ограничение: состояние вкладок, групп и статистики принадлежит экземпляру страницы.
- [ADR-0033](../../../docs/adr/0033-coordinate-daily-choice-sections-on-one-revision.md) — proposed, originating change `enrich-daily-choice-catalog`. Прецедент совместной публикации двух частей на одной ревизии, на который опирается ADR-0047.
- [ADR-0043](../../../docs/adr/0043-read-relation-counts-only-for-intention-page.md) — proposed, originating change `redesign-intention-pickers`. Ограничение: количество связей только на странице намерения, без чисел у соседей. Перечень мест вычисления агрегатов уточняется ADR-0047.
- [ADR-0011](../../../docs/adr/0011-derive-relation-counts-from-graph-snapshots.md) — accepted. Ограничение: числа групп, вкладки и доступность удаления берутся из агрегатов сохранённых связей; разрешение удаления проверяется в транзакции команды.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) и [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating changes `add-design-foundation` и `redesign-daily-choice-calendar`. Ограничение: значения в модуле основ, компоненты без предметной логики.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: страница намерения — обычная страница, экран изменения — страница-задача со своим каркасом.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: создание связи и дневного выбора со вкладок владеет собственной границей потока.
- [ADR-0027](../../../docs/adr/0027-reread-statistics-only-when-visible.md) — proposed, originating change `add-contribution-statistics`. Ограничение: статистика читается, только пока маршрут текущий и выбрана её вкладка.

## Additional Context

- [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — accepted. Модальные сессии ограничены созданием; правка намерения остаётся отдельным экраном, но повторяет единое решение о закрытии.
- [ADR-0023](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — proposed, originating change `collapse-operation-result-messages`. Отказы действий страницы объединяются в общей очереди сообщений.
- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md), [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md) и [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed. Меню параметров открывается общим показом листов модуля основ.
- [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md) — proposed, originating change `add-tags-panel`. Меню параметров закрывается до операции, поэтому собственная поверхность сообщений ему не нужна.
- [ADR-0014](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — proposed, originating change `add-home-navigation-and-favorites`. Страница намерения открывается поверх оболочки корневых страниц.

## ADRs Owned by This Change

- [ADR-0046 — Не объявлять успех правки сообщением, оставляя отказ её экрану](../../../docs/adr/0046-keep-edit-failures-on-screen-without-success-message.md) — proposed.
- [ADR-0047 — Публиковать активную и архивную части группы связей одной моделью экземпляра страницы](../../../docs/adr/0047-publish-active-and-archived-parts-of-relation-group-together.md) — proposed.
