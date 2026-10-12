# ADR Review Manifest

- Status: completed
- Review date: 2026-10-12

## Review Summary

Обзор завершён. После согласования [design.md](design.md) соответствует применимым принятым ADR и двум новым предложениям.

- **ADR-0024** закрепляет вычисление состояний дней агрегатом сохранённых дневных выборов без хранимой сводки и повторное чтение после каждой новой ревизии. Принятая ADR-0011 приводит те же доводы, но ограничена счётчиками долговременных связей.
- **ADR-0025** частично пересматривает ADR-0017 с явной областью `Supersedes`: просмотр периода может запускать чтение отметок, но не чтение выдачи. ADR-0017 и её статус не изменены.

При согласовании design ссылка на заменённую ADR-0005 исправлена на ADR-0009, а решения 1, 2 и 4 получили ссылки на новые ADR.

Окно из трёх месяцев, единый тип отказа на границе модуля, предел длины диапазона, раскладка ячейки и пассивная строка отказа — детали дизайна и спецификации, которые не создают долговременной границы. В `CONTEXT.md` добавлен термин «Состояние дня»; «отметка дня» остаётся элементом интерфейса. Существенных нерешённых архитектурных решений нет, поэтому дополнительное испытание дизайна не требовалось.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0009 — Личный граф и ревизия](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — `accepted`, обязательное ограничение. Единственная граница `PersonalGraphRepository`, ограниченные чтения, общая ревизия снимков, последовательный исполнитель и отбрасывание устаревших ответов.
- [ADR-0011 — Счётчики связей из снимков](../../../docs/adr/0011-derive-relation-counts-from-graph-snapshots.md) — `accepted`. Прецедент агрегатов в хранилище без хранимых счётчиков и без ложного нуля. Как ограничение действует только для счётчиков связей.
- [ADR-0017 — Компонент календаря](../../../docs/adr/0017-isolate-inline-calendar-behind-app-component.md) — `proposed`; Originating change: `add-inline-daily-choice-calendar` (архивировано). Контракт компонента, владение выбранной датой и просмотром сохраняются вне части, пересматриваемой ADR-0025.
- [ADR-0024 — Состояния дней агрегатом](../../../docs/adr/0024-derive-calendar-day-states-from-saved-daily-choices.md) — `proposed`; Originating change: `add-daily-choice-calendar-day-marks`. Целевой контракт решений 2 и 4 дизайна.
- [ADR-0025 — Отдельная модель отметок](../../../docs/adr/0025-load-calendar-day-marks-in-separate-viewport-model.md) — `proposed`; Originating change: `add-daily-choice-calendar-day-marks`. Целевой контракт решений 1 и 5 дизайна.

## Additional Context

- [ADR-0012 — Предъявление результатов](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — `accepted`, и [ADR-0023 — Объединение ожидающих результатов](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — `proposed`; Originating change: `collapse-operation-result-messages` (архивировано). Общая поверхность принадлежит результатам команд, поэтому отказ получения отметок показывается в календаре, а не через неё.
- [ADR-0014 — Оболочка корневых страниц](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). Контекст времени жизни: сохранённая оболочкой страница каталога удерживает модель отметок при переходах между разделами.
- [ADR-0002 — Drift и SQLite](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md) — `accepted`. Агрегат выполняется внутри адаптера Drift; SQL не пересекает границу модуля.
- [ADR-0005 — Ограниченные снимки каталога](../../../docs/adr/0005-use-bounded-catalog-snapshots.md) — `accepted`, заменена ADR-0009 и в этой области имеет только историческое значение.

## ADRs Owned by This Change

- [ADR-0024 — Вычислять состояния дней календаря агрегатом сохранённых дневных выборов](../../../docs/adr/0024-derive-calendar-day-states-from-saved-daily-choices.md) — `proposed`; Originating change: `add-daily-choice-calendar-day-marks`.
- [ADR-0025 — Получать отметки календаря каталога отдельной моделью по периоду просмотра](../../../docs/adr/0025-load-calendar-day-marks-in-separate-viewport-model.md) — `proposed`; Originating change: `add-daily-choice-calendar-day-marks`.
