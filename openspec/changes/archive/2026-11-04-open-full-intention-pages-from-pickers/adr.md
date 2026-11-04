# ADR Review Manifest

- Status: completed
- Review date: 2026-11-03

## Review Summary

Просмотрены решения о каркасах страниц, границах создания, владении состоянием поиска, пачках связей и согласовании занятых пар. Долговечное изменение — независимость обычной страницы от поиска ниже в истории — оформлено в ADR-0053 как частичный пересмотр ADR-0052. Самостоятельные экземпляры поиска и общий канал подтверждённых изменений уже описаны существующими ADR; конкретный вызов `reconcilePairOccupants` остаётся деталью `design.md`.

`design.md` согласован с итоговым набором записей и ссылается на ADR-0053. Существенных неразрешённых решений не осталось. Термины намерения, действия, декомпозиции, долговременной связи и дневного выбора сохраняют определения `CONTEXT.md`; новые предметные понятия не вводятся.

ADR review завершён. ADR этого изменения остаётся `proposed` и редактируемым до архивации. Принятые ADR и записи архивных изменений сохраняются.

## Key ADRs for This Change

- [ADR-0053](../../../docs/adr/0053-open-ordinary-pages-independently-of-picker-history.md) — proposed, изменение `open-full-intention-pages-from-pickers`. Собственное решение о границе обычной страницы и поиска; частичный пересмотр ADR-0052.
- [ADR-0052](../../../docs/adr/0052-add-relations-as-one-batch-from-group-picker.md) — proposed, архивное изменение `add-relations-in-batches`. Запрет навигации над поиском служит контекстом пересмотра; владение пачкой, атомарная команда и возврат к группе сохраняются.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, архивное изменение `add-quick-creation-and-persistent-navigation`. Архитектурный контекст обычного каркаса и сброса истории пунктом навигации.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, архивное изменение `add-quick-creation-and-persistent-navigation`. Контекст сохранения исходной истории при завершении вложенного создания намерения или дневного выбора; исключение для добавления связей остаётся за ADR-0052.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, изменение `add-contribution-statistics`. Основа самостоятельного состояния каждого открытого поиска.
- [ADR-0050](../../../docs/adr/0050-mark-occupied-pairs-in-same-catalog-page.md) — proposed, изменение `mark-occupied-pairs-in-relation-participant-picker`. Основа согласования занятости подтверждёнными фактами с учётом уточнённой в ADR-0052 пробы пары.

## Additional Context

- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. Ограничение: инварианты и принятые команды принадлежат модулю графа, подтверждённые изменения поступают одним каналом; маршрут не становится вторым каналом обновления.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted. Ограничение для владения и освобождения прав предъявления при закрытии поиска или изменении его состояния.
- [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — accepted. Ограничение: вложенное создание намерения сохраняет собственную модальную сессию и процедуру закрытия; пересмотр навигации над поиском их не заменяет.

## ADRs Owned by This Change

- [ADR-0053](../../../docs/adr/0053-open-ordinary-pages-independently-of-picker-history.md) — proposed, изменение `open-full-intention-pages-from-pickers`. Единственная собственная ADR; при архивации финализируется только она.
