# ADR Review Manifest

- Status: completed
- Review date: 2026-10-24

## Review Summary

`design.md` согласован с ADR. Решение о единой модели положения листа, о ведении анимации модального маршрута Material пальцем, о передаче жеста от тела и об одной функции показа долговременно: оно определяет поведение всех будущих листов. Оно же частично пересматривает ADR-0041 и ADR-0032, поэтому записано новой ADR-0044. Пороги отпускания, длительность доводки, предел компактной высоты и исправление размера графики `DoableIcon` — тактические решения, они остаются в `design.md`. Новых терминов предметной области изменение не вводит: слова о листах относятся к интерфейсу и определены в требованиях `bottom-sheets`.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md) — proposed, originating change `add-tags-panel` (в архиве). Раскрываемый лист с порогом шапки и отдельной функцией показа. ADR-0044 пересматривает её порог, жест только на шапке, неизменный размер листа при прокрутке тела и привязку варианта к функции. Размеры листа остаются в силе.
- [ADR-0032](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — proposed, originating change `redesign-navigation-bar` (в архиве). Показ листов функцией модуля основ через модальную нижнюю панель Material в корневом навигаторе. Это ограничение сохраняется для затемнения, «назад», фокуса и семантики; ADR-0044 пересматривает только перетаскивание.
- [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md) — proposed, originating change `add-tags-panel` (в архиве). Собственный `Scaffold` листа для сообщений общей поверхности. Это ограничение: движение листа охватывает этот `Scaffold` и не меняет место сообщений.

## Additional Context

- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Компоненты дизайн-системы — представления. Ограничение: `Sheet` получает готовые подписи ручки и шеврона от потребителей.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, originating change `add-design-foundation`. Модуль основ владеет значениями дизайна. Контекст для длительности, кривой и предела компактной высоты как констант модуля.

## ADRs Owned by This Change

- [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed. Вести листы дизайн-системы пальцем одной моделью положения.
