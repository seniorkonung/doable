# ADR Review Manifest

- Status: completed
- Review date: 2026-10-14

## Review Summary

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

Представление дизайн-системы в коде — долговременное решение, на которое опирается перевод всех экранов. Поэтому решения 1–7 из `design.md` закреплены в одной новой ADR-0029:

- модуль основ оформления;
- ручной перенос токенов;
- роли Material из токенов;
- применение обеих тем;
- поставка Inter;
- минимальные размеры.

Решения 8 и 9 (Widgetbook и способ проверки) относятся только к этому изменению. Принятые ADR не пересматриваются. `design.md` согласован с ADR-0029 и ссылается на неё.

Термины предметной области изменение не вводит и не меняет. «Оформление» и «тема» — понятия интерфейса, `CONTEXT.md` не меняется.

## Key ADRs for This Change

- [ADR-0004](../../../docs/adr/0004-keep-personal-graph-device-local.md) — accepted. Ограничение: release-сборка не имеет разрешения на сеть, поэтому Inter поставляется вместе с приложением, а не загружается.
- [ADR-0017](../../../docs/adr/0017-isolate-inline-calendar-behind-app-component.md) — proposed, originating change `add-inline-daily-choice-calendar`. Оформление календаря остаётся внутри `DailyChoiceCalendar`; тема меняет только роли, которые он читает.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Панель навигации остаётся общим компонентом каркасов и берёт цвета из ролей темы; её размещение и поведение не меняются.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted — и [ADR-0023](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — proposed, originating change `collapse-operation-result-messages`. Тема меняет только вид `SnackBar` общей поверхности, а протокол предъявления и подтверждения кадром сохраняется.

## Additional Context

- ADR-0026–ADR-0028 — proposed, originating change `add-contribution-statistics`. Они не связаны с оформлением, но их номера заняты, поэтому запись этого изменения получила номер 0029. Обе ветки добавляют строки в индекс ADR, и при слиянии второй ветки индекс сводится по номерам.

## ADRs Owned by This Change

- [ADR-0029 — Представлять дизайн-систему Doable модулем основ оформления](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed.
