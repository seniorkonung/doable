# ADR Review Manifest

- Status: completed
- Review date: 2026-10-15

## Review Summary

Решения `design.md` сверены с ADR навигации, быстрого создания, потоков создания и дизайн-системы. Противоречий не найдено:
- панель остаётся общим компонентом в каркасах обычных страниц; совет дизайн-системы о собственном `Navigator` раздела отклонён;
- лист выбора начала закрывается до начала потока дневного выбора, поэтому граница и завершение потока не меняются;
- хранение режима сохраняет отдельную границу настройки установки, явные ключи и замену непригодного значения на «Новое намерение»;
- компоненты дизайн-системы остаются представлениями без предметных типов и локализации приложения.

Одно решение переживает изменение и записано им: листы дизайн-системы показываются функцией модуля основ над корневым навигатором (ADR-0032). Оно дополняет ADR-0030 правилом показа листов. После записи `design.md` ссылается на ADR и согласован с ними. Остальные решения — три режима, место листа выбора начала, токены, значки, жесты и строки — тактические или следуют существующим ADR.

Открытых решений с серьёзными последствиями в дизайне нет. Новых понятий предметной области изменение не вводит, поэтому `CONTEXT.md` не меняется; тексты листов используют «намерение» вместо «цели» по глоссарию.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: панель — общий компонент представления в каркасах обычных страниц с одним источником выбранного пункта и режима; сборка быстрого создания относится к приложению, а модули сущностей от неё не зависят.
- [ADR-0021](../../../docs/adr/0021-separate-installation-preferences-from-personal-graph.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: режим — настройка установки за отдельной границей с ключами, не зависящими от перечисления; непригодное значение заменяется режимом «Новое намерение» с записью в диагностику.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: выбор до корня потока завершается до продолжения создания; граница потока и открытие созданной сущности сохраняются.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, originating change `add-design-foundation`. Ограничение: значения и компоненты дизайн-системы живут в модуле основ, размеры и тени появляются с первым компонентом, решения проекта важнее советов дизайн-системы.
- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Координация с параллельным изменением: компоненты дизайн-системы — представления; панель, листы и строки вариантов этого изменения следуют записи.

## Additional Context

- [ADR-0014](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — proposed, originating change `add-home-navigation-and-favorites`. Исторический контекст: оболочка корневых страниц над общим стеком без собственных стеков пунктов; размещение панели пересмотрено ADR-0020.
- [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — accepted. Модальная сессия создания намерения остаётся маршрутом общего корневого стека и сохраняет свой вид; листы дизайн-системы открываются в том же стеке.

## ADRs Owned by This Change

- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — proposed, originating change `redesign-navigation-bar`. Листы дизайн-системы открываются одной функцией модуля основ через `showModalBottomSheet` в корневом навигаторе; `bottomSheetTheme` остаётся непереведённым нижним панелям Material.
