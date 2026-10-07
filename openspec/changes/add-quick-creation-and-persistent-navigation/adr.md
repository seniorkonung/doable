# ADR Review Manifest

- Status: completed
- Review date: 2026-10-07

## Review Summary

Обзор завершён: [design.md](design.md) согласован с применимыми принятыми ADR и тремя новыми предложениями. Они закрепляют размещение постоянной навигации, отделение настройки установки от графа и границу завершения создания. Записи этого изменения остаются `proposed` и редактируемыми до архивации; принятые ADR не изменены.

ADR-0014 имеет статус `proposed`, хотя исходное изменение архивировано. Её частичный пересмотр оформлен отдельной ADR-0020 с явной областью `Supersedes`; ни принятие прежней записи, ни принятие её замены не предполагаются. Из принятых ADR-0018 и ADR-0019 сохраняются владение модальной сессией и типизированные контексты тегов. Запрет обычных страниц из сессии создания намерения исключает обход согласованного закрытия черновика при сбросе истории.

Изоляция поиска токеном страницы, новый вариант контекста формы связи, конкретные значки, анимация панели и вызовы маршрутизатора остаются деталями дизайна: они реализуют спецификации в установленных границах и не требуют самостоятельных ADR. Термины намерения, действия, дневного выбора, долговременной связи, тега и черновика соответствуют `CONTEXT.md`; новых предметных понятий для этих решений не требуется. Незакрытых существенных архитектурных решений нет; визуальная сверка значков остаётся в дизайне.

## Key ADRs for This Change

- [ADR-0020 — Каркасы обычных страниц](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`. Целевое решение для навигации, частично пересматривающее ADR-0014; согласовано с решениями 1–5 дизайна.
- [ADR-0021 — Настройки установки вне графа](../../../docs/adr/0021-separate-installation-preferences-from-personal-graph.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`. Целевая граница владения и хранения режима; согласована с решениями 6–7 и 13.
- [ADR-0022 — Граница завершения создания](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`. Целевой контракт потоков из решений 8–9.
- [ADR-0014 — Оболочка корневых страниц](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). Исходный архитектурный контекст, а не принятое ограничение. Сохраняемая часть явно отделена от пересмотра в ADR-0020; финализация исходной записи этому изменению не принадлежит.
- [ADR-0018 — Модальная сессия в корневом стеке](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) — `accepted`, обязательное ограничение. Создание намерения над любой обычной страницей сохраняет одну сессию, её черновик и процедуру закрытия.
- [ADR-0009 — Единая граница графа и ревизия](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — `accepted`, обязательное ограничение; принятое решение заменяет ADR-0005. Новые входы используют прежние команды и согласование; уход со страницы не отменяет принятую команду, результат маршрута не обновляет граф.
- [ADR-0012 — Предъявление результатов](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — `accepted`, обязательное ограничение. Панели и завершение потоков сохраняют общую поверхность успеха, право экранной сессии на ошибку и его освобождение при исчезновении поверхности.

## Additional Context

- [ADR-0002 — Drift/SQLite для графа](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md) — `accepted`, обязательное ограничение для данных графа. Отдельная настройка не меняет схему базы, миграционные обязательства или границу соединений.
- [ADR-0004 — Локальные данные Android](../../../docs/adr/0004-keep-personal-graph-device-local.md) — `accepted`, обязательное ограничение платформы. Файл режима размещается в уже исключённом каталоге; перенос, резервное копирование и набор разрешений не расширяются.
- [ADR-0019 — Контексты выбора тегов](../../../docs/adr/0019-separate-tag-selection-context-from-persistence.md) — `accepted`, обязательное ограничение. Вид каталога тегов следует контексту просмотра или выбора; временное состояние черновика не переходит в контракт репозитория.
- [ADR-0013 — Полные снимки тегов](../../../docs/adr/0013-load-complete-tag-snapshots.md) — `accepted`, дополнительное ограничение чтения тегов. Изоляция страниц поиска не меняет этот протокол или ограниченные порции намерений.
- [ADR-0016 — Политика «только отказ»](../../../docs/adr/0016-present-only-failure-for-self-evident-success.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). Контекст действующей политики отдельных операций; открытие созданной сущности само по себе не разрешает подавлять её сообщение успеха. Запись не финализируется этим изменением.

## ADRs Owned by This Change

- [ADR-0020 — Размещать постоянную навигацию в каркасах обычных страниц](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`.
- [ADR-0021 — Отделить настройки установки от данных личного графа](../../../docs/adr/0021-separate-installation-preferences-from-personal-graph.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`.
- [ADR-0022 — Завершать создание в границах собственного потока маршрутов](../../../docs/adr/0022-complete-creation-flows-within-owned-route-boundaries.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation`.
