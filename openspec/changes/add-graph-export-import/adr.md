# ADR Review Manifest

- Status: completed
- Review date: 2026-10-17

## Review Summary

Обзор завершён. [design.md](design.md) согласован с применимыми ADR и пятью новыми предлагаемыми записями:

- ADR-0034 — локальный лог фактов: захват триггерами схемы, единый путь записи, снимки и резервные копии как позиции.
- ADR-0035 — предметный версионируемый формат данных графа.
- ADR-0036 — атомарная замена графа с новой эпохой ревизий и новым поколением корневых страниц. Запись частично пересматривает принятую ADR-0009 и ADR-0014.
- ADR-0037 — открытый файл экспорта и доступ к документам без разрешений. Запись дополняет ADR-0004.
- ADR-0038 — направление синхронизации, которое это изменение не реализует.

Остальные решения отдельной ADR не требуют:

- Базовая схема версии 3 без миграции — разовое исключение для предварительных сборок, оно описано в дизайне и README.
- Результаты операций с данными идут через протокол ADR-0012 и объединение ADR-0023. Успеху ручной копии координатор задаёт политику «только отказ» по ADR-0016; ссылка на неё добавлена в дизайн при сверке.
- Соединения с базой и функции схемы не меняются (ADR-0002, ADR-0008).
- Настройки установки остаются вне графа по ADR-0021.
- Страница «Настройки» использует каркас обычной страницы по ADR-0020 и листы дизайн-системы по ADR-0032.

В [CONTEXT.md](../../../CONTEXT.md) добавлены понятия «Замена графа», «Файл экспорта», «Импорт», «Резервная копия» и «Восстановление копии». Последнее отделено от существующего «Восстановления из архива». Лог фактов и снимки — структуры хранения, они описаны в ADR-0034 и дизайне, а не в глоссарии.

Существенных нерешённых решений в дизайне нет: открытыми остались только инженерные пороги, которые подбираются по бенчмаркам.

Принадлежащие изменению ADR остаются `proposed` и редактируемыми до архивации. Принятые ADR неизменяемы; записи других изменений и их статусы этим обзором не пересматриваются. Статус `completed` относится к завершённости обзора.

## Key ADRs for This Change

- [ADR-0034 — Лог фактов](../../../docs/adr/0034-record-confirmed-graph-changes-in-local-fact-log.md) — `proposed`; Originating change: `add-graph-export-import`. Основа экспорта, резервных копий и будущей синхронизации: полнота захвата задаётся схемой, позиции не заменяют эфемерную ревизию.
- [ADR-0035 — Формат данных графа](../../../docs/adr/0035-keep-graph-data-in-versioned-domain-format.md) — `proposed`; Originating change: `add-graph-export-import`. Контракт файлов экспорта, снимков и пакетов лога: gzip поверх JSON Lines, каноническая запись, версия у каждого носителя записей, построчное повышение версий, эталоны.
- [ADR-0036 — Атомарная замена графа](../../../docs/adr/0036-replace-graph-atomically-with-new-epoch-and-generation.md) — `proposed`; Originating change: `add-graph-export-import`. Решение о порядке изменений и согласовании снимков при импорте, которого требует ADR-0009.
- [ADR-0037 — Открытый файл экспорта без разрешений](../../../docs/adr/0037-export-unencrypted-file-through-system-dialogs.md) — `proposed`; Originating change: `add-graph-export-import`. Пересмотр модели угроз, которого ADR-0004 требует до появления экспорта.
- [ADR-0038 — Синхронизация через тонкий сервер](../../../docs/adr/0038-sync-devices-through-thin-encrypted-file-server.md) — `proposed`; Originating change: `add-graph-export-import`. Направление, ради которого формат, лог и замена графа строятся переиспользуемыми; метаданных только для синхронизации нет.
- [ADR-0009 — Личный граф и ревизия](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) — `accepted`, обязательное ограничение. Единственная граница графа, последовательный исполнитель, эфемерная ревизия. ADR-0036 частично пересматривает её: эпоха принадлежит поколению графа.
- [ADR-0004 — Граф во внутреннем хранилище Android](../../../docs/adr/0004-keep-personal-graph-device-local.md) — `accepted`, обязательное ограничение. Каталог `app_flutter/` исключён из системного копирования, набор разрешений — точный список. Снимки, копии и временные файлы остаются внутри этой границы.
- [ADR-0014 — Оболочка корневых страниц](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). Контекст оболочки и `IndexedStack`. ADR-0036 частично пересматривает её в части жизни корневой страницы до конца процесса.
- [ADR-0012 — Предъявление результатов](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) — `accepted`, обязательное ограничение. Операции с данными получают новые виды результата в координаторе. Отказы импорта и восстановления принадлежат строке страницы, отказ экспорта — общей поверхности; собственного `SnackBar` нет.
- [ADR-0002 — Drift и SQLite](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md) — `accepted`, обязательное ограничение. Новые соединения не появляются, схема создаётся через существующую границу, автоматического удаления или пересоздания хранилища нет.
- [ADR-0010 — Последовательность создания связей](../../../docs/adr/0010-persist-long-term-relation-creation-order.md) — `accepted`, обязательное ограничение. При замене графа порядок файла становится локальным порядком создания. Объединение порядков разных источников остаётся за синхронизацией (ADR-0038).
- [ADR-0031 — Портретная ориентация и перенос движка](../../../docs/adr/0031-restrict-phones-to-portrait-full-screen.md) — `proposed`; Originating change: `redesign-daily-choice-calendar` (архивировано). Плагин документов привязан к движку и переносится вместе с ним; прерванный запрос считается отменой.

## Additional Context

- [ADR-0006 — Часы устройства как наблюдения](../../../docs/adr/0006-treat-device-clock-timestamps-as-observations.md) — `accepted`, обязательное ограничение. Время записи пакетов, суточная отсечка и срок хранения копий не задают причинный порядок.
- [ADR-0003 — Типизированные UUID](../../../docs/adr/0003-use-typed-uuid-identifiers-for-domain-entities.md) — `accepted`. Идентификаторы переносятся файлами и снимками без изменения.
- [ADR-0007 — Unicode без NUL](../../../docs/adr/0007-restrict-graph-user-text-to-unicode-without-nul.md) — `accepted`, обязательное ограничение. Импортируемый текст проходит ту же проверку, что и ввод.
- [ADR-0008 — Функции схемы SQLite](../../../docs/adr/0008-treat-sqlite-schema-functions-as-durable-contract.md) — `accepted`. Импорт не открывает чужие файлы SQLite, поэтому граница доверия не расширяется.
- [ADR-0016 — Только отказ для очевидного успеха](../../../docs/adr/0016-present-only-failure-for-self-evident-success.md) — `proposed`; Originating change: `add-home-navigation-and-favorites` (архивировано). По индексу ADR сейчас имеет историческое значение; её политика снова применяется к успеху ручной копии.
- [ADR-0020 — Навигация в каркасах обычных страниц](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation` (архивировано). Страница «Настройки» — обычная страница с панелью; сброс истории пунктом не прерывает фоновый экспорт.
- [ADR-0021 — Настройки установки отдельно от графа](../../../docs/adr/0021-separate-installation-preferences-from-personal-graph.md) — `proposed`; Originating change: `add-quick-creation-and-persistent-navigation` (архивировано). Режим быстрого создания не попадает в файлы экспорта и копии и не меняется заменой графа.
- [ADR-0023 — Объединение ожидающих результатов](../../../docs/adr/0023-collapse-pending-results-into-shared-surface-messages.md) — `proposed`; Originating change: `collapse-operation-result-messages` (архивировано). Сообщения операций с данными объединяются тем же правилом, что и результаты команд графа.
- [ADR-0026 — Вклад через связи вне очереди](../../../docs/adr/0026-compute-contribution-through-relations-off-queue.md) — `proposed`; Originating change: `add-contribution-statistics` (архивировано). Новая эпоха сбрасывает снимок связей статистики. Фоновые изоляты экспорта и сжатия следуют тому же подходу коротких чтений очереди.
- [ADR-0027 — Перечитывание статистики при показе](../../../docs/adr/0027-reread-statistics-only-when-visible.md) — `proposed`; Originating change: `add-contribution-statistics` (архивировано). Пока открыта страница «Настройки», Главная невидима и перечитывается после возвращения уже в новом поколении.
- [ADR-0028 — Состояние экземпляра страницы](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — `proposed`; Originating change: `add-contribution-statistics` (архивировано). Поколение графа создаёт корневые экземпляры страниц заново.
- [ADR-0030 — Компоненты дизайн-системы без предметной логики](../../../docs/adr/0030-keep-design-system-components-presentational.md) и [ADR-0032 — Листы дизайн-системы](../../../docs/adr/0032-present-design-system-sheets-over-root-navigator.md) — `proposed`; Originating changes: `redesign-daily-choice-calendar` и `redesign-navigation-bar` (архивированы). Нижние панели экспорта и копий открываются функцией модуля основ, тексты и обработчики передаёт экран.

## ADRs Owned by This Change

- [ADR-0034 — Записывать подтверждённые изменения графа в локальный лог фактов](../../../docs/adr/0034-record-confirmed-graph-changes-in-local-fact-log.md) — `proposed`; Originating change: `add-graph-export-import`.
- [ADR-0035 — Переносить данные графа в предметном версионируемом формате](../../../docs/adr/0035-keep-graph-data-in-versioned-domain-format.md) — `proposed`; Originating change: `add-graph-export-import`.
- [ADR-0036 — Заменять граф атомарно с новой эпохой ревизий и новым поколением корневых страниц](../../../docs/adr/0036-replace-graph-atomically-with-new-epoch-and-generation.md) — `proposed`; Originating change: `add-graph-export-import`.
- [ADR-0037 — Экспортировать открытый файл через системные диалоги без разрешений](../../../docs/adr/0037-export-unencrypted-file-through-system-dialogs.md) — `proposed`; Originating change: `add-graph-export-import`.
- [ADR-0038 — Синхронизировать устройства через тонкий сервер зашифрованных файлов](../../../docs/adr/0038-sync-devices-through-thin-encrypted-file-server.md) — `proposed`; Originating change: `add-graph-export-import`.
