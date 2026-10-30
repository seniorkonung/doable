# ADR Review Manifest

- Status: completed
- Review date: 2026-10-30

## Review Summary

Решения [design.md](design.md) проверены по индексу `docs/adr/README.md` и записям о каталоге и ревизиях, количествах связей, потоках создания, предъявлении результатов и дизайн-системе. Учтено и активное изменение `redesign-intention-catalog`: его ADR-0049 пришла в эту ветку вместе с завершёнными фазами 1 и 2.

Новая долговременная запись одна — [ADR-0050](../../../docs/adr/0050-mark-occupied-pairs-in-same-catalog-page.md). Она фиксирует пробу пары в запросе каталога, вычисление занимающей связи в снимке порции и согласование её фактами связей. Причины записи две: впервые чтение каталога получает сведения о связях, а отвергнутая альтернатива — прочитать все связи второго участника — неочевидна.

Восстановление, которое завершает создание связи, отдельной записи не получило: оно укладывается в ADR-0022, где завершающая сессия удаляет свои страницы до корня потока. Отказ, отданный оболочке, — существующий механизм ADR-0012. Метка-слово и состав подтверждения — тактические решения.

`design.md` сверен с записями:
- он ссылается на ADR-0050 и ADR-0022;
- он строится поверх модуля поиска ADR-0049;
- пересечение с `redesign-intention-catalog` записано риском с порядком реализации.

Принятые записи не пересматриваются.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0050](../../../docs/adr/0050-mark-occupied-pairs-in-same-catalog-page.md) — proposed, originating change `mark-occupied-pairs-in-relation-participant-picker`. Принадлежит этому изменению: проба пары, занятость в порции, согласование фактами связей.
- [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — accepted. **Ограничение:** ограниченные порции, единый снимок и ревизия, пакеты подтверждённых команд со сведениями о связях. ADR-0050 дополняет её, не меняя протокола.
- [ADR-0043](../../../docs/adr/0043-read-relation-counts-only-for-intention-page.md) — proposed, originating change `redesign-intention-pickers`. **Ограничение:** каталог и поиски не получают количеств связей и не проверяют соседство. Отметка занятой пары — одна связь на строку, а не количество.
- [ADR-0049](../../../docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md) — proposed, originating change `redesign-intention-catalog`. **Координация:** модуль поиска, строки через `rowBuilder` страницы, отличия контекстов данными. Запись пришла с влитыми фазами 1 и 2 того изменения; это изменение сливается и архивируется после него.
- [ADR-0022](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. **Ограничение:** восстановление завершает поток создания связи по её правилам: удаление страниц потока до корня, переход только в актуальном потоке.
- [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — accepted. **Ограничение:** владение предъявлением результата. Отказ восстановления из поиска сразу принадлежит оболочке.

## Additional Context

- [ADR-0042](../../../docs/adr/0042-show-shared-surface-messages-over-operating-sheets.md) — proposed, originating change `add-tags-panel`. Сообщение оболочки об отказе видно над поиском.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, originating change `add-design-foundation`. Решения проекта важнее правил дизайн-системы, поэтому строки с отметкой остаются в выдаче, а метка — слово.
- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Вариант `Badge` со словом и `PickerRow` остаются представлениями без предметной логики.
- [ADR-0036](../../../docs/adr/0036-replace-graph-atomically-with-new-epoch-and-generation.md) — proposed, originating change `add-graph-export-import`. Замена графа начинает новое поколение, и модель каталога сбрасывает отметки вместе со строками.
- [ADR-0005](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — accepted, заменена ADR-0009. Историческое основание протокола порций и ревизий.

## ADRs Owned by This Change

- [ADR-0050](../../../docs/adr/0050-mark-occupied-pairs-in-same-catalog-page.md) — proposed.
