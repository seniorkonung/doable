# ADR Review Manifest

- Status: completed
- Review date: 2026-10-25

## Review Summary

`design.md` согласован с ADR. Изменение не вводит долговременных архитектурных решений: вид ручки, отказ от отклика Material на касание и удаление неиспользуемого значка — решения об облике одного компонента, а не шаблон, технология, граница или контракт для будущих изменений. Поэтому новая ADR не создаётся.

ADR-0041 упоминает, что в полном размере ручку заменяет шеврон. Это деталь облика, а не предмет её решения, которое уже частично пересмотрено ADR-0044. Поведение ручки задаёт требование `bottom-sheets` «Ручка нижней панели», поэтому ADR-0041 не правится и не заменяется. Новых терминов предметной области изменение не вводит.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0044](../../../docs/adr/0044-drive-design-system-sheets-by-finger-with-one-position-model.md) — proposed, originating change `unify-bottom-sheets` (в архиве). Модель положения листа и источники жеста. Ограничение: кнопка ручки распознаёт только нажатие и не вмешивается в перетаскивание листа; изменение модель не трогает.
- [ADR-0041](../../../docs/adr/0041-expand-design-system-sheets-by-header-drag.md) — proposed, originating change `add-tags-panel` (в архиве). Раскрываемый лист и ручка как кнопка с подписями раскрытия и сворачивания. Ручка остаётся такой кнопкой; упоминание шеврона — историческая деталь облика, её заменяет требование `bottom-sheets`.

## Additional Context

- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Компоненты дизайн-системы — представления. Ограничение: `Sheet` по-прежнему получает готовые подписи ручки от потребителей.

## ADRs Owned by This Change

- None - no major durable architectural decisions were introduced.
