# ADR Review Manifest

- Status: completed
- Review date: 2026-10-11

## Review Summary

Обзор завершён: [design.md](design.md) согласован с применимыми принятыми ADR и одним новым предложением. ADR-0023 закрепляет форму права оболочки на все ожидающие результаты, подтверждение охваченного подмножества и владение составом сообщения в presentation-слое. Она частично пересматривает принятую ADR-0012 с явной областью `Supersedes`; ADR-0012 и её статус не изменены.

Строка локализации с числом остальных результатов и горизонтальное смахивание остаются деталями дизайна: они реализуют спецификации внутри presenter и не создают долговременной границы. Объединённое сообщение, общая поверхность и право предъявления — понятия механизма показа, а не предметной области личного графа, поэтому `CONTEXT.md` не меняется. Незакрытых существенных архитектурных решений нет.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0012 — Предъявление результатов](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — `accepted`, обязательное ограничение вне пересматриваемой части. Исключительность claims, право экранной сессии на собственную ошибку и его освобождение, подтверждение по завершённому кадру и возврат результатов при пересоздании оболочки сохраняются.
- [ADR-0023 — Объединение ожидающих результатов](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — `proposed`; Originating change: `collapse-operation-result-messages`. Целевой контракт решений 1–2 дизайна.

## Additional Context

- [ADR-0016 — Политика «только отказ»](../../../docs/adr/0016-present-only-failure-for-self-evident-success.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). Историческая запись: её единственная операция удалена. Объединение не подавляет успехи: каждый результат получает право и подтверждение в составе сообщения.
- [ADR-0020 — Каркасы обычных страниц](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation` (архивировано). Контекст размещения: собственные `Scaffold` страниц остаются получателями общих сообщений; изменение не меняет их размещение.

## ADRs Owned by This Change

- [ADR-0023 — Объединять ожидающие результаты операций в сообщения общей поверхности](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — `proposed`; Originating change: `collapse-operation-result-messages`.
