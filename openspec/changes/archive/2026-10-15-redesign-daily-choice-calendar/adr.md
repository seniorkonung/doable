# ADR Review Manifest

- Status: completed
- Review date: 2026-10-15

## Review Summary

Решения `design.md` сверены с ADR календаря, отметок дней, навигации и основ оформления. Найдено одно противоречие с ADR-0025: дизайн переносил строку об отказе получения отметок в тело каталога. Дизайн исправлен: строку по-прежнему показывает календарь, теперь карточкой `Notice` под ручкой. После правки `design.md` согласован с ADR.

Две записи переживают изменение и созданы им: граница компонентов дизайн-системы (ADR-0030) и портретная ориентация телефонов (ADR-0031). Внутреннее состояние выбора года и месяца и правило даты просмотра остаются в границах ADR-0017 и ADR-0025 и отдельной записи не требуют. Открытых решений с серьёзными последствиями в дизайне нет. Новых понятий предметной области изменение не вводит, поэтому `CONTEXT.md` не меняется.

Владелец продукта исключил маленькие окна из поддержки, сохранив закреплённый календарь. Проверяемую границу области поддержки задаёт `app-appearance`, расчёт и проверку — решения 3, 6 и 9 дизайна. Это уточнение применимости портретной раскладки, а не новый способ управления окном: ADR-0031 сохраняется, но её ссылка на портретную высоту не означает гарантию для любого маленького телефона. Размеры области поддержки принадлежат спецификации; отдельной архитектурной записи не требуется.

ADR-0031 и её индекс согласованы с решением 6: нативный запуск ограничивает только телефонные дисплеи, а большие сохраняют системные режимы на всех поддерживаемых Android API, включая версии до Android 16. Безусловные атрибуты общей Activity больше не предписываются. Требование `app-appearance` сохраняется; реализация этой границы описана задачей 2.14 и корректирующими задачами 2.15–2.17. Физическая проверка остаётся за владельцем продукта вне списка задач; порядок подтверждения и его связь с готовностью фазы 2 задаёт решение 6 дизайна. Статус ADR-0031 остаётся `proposed`; завершённость обзора ADR не означает завершённость реализации или проверки устройств.

ADR review completed. Owned ADRs remain proposed and editable until archival;
accepted ADRs are immutable.

## Key ADRs for This Change

- [ADR-0017](../../../docs/adr/0017-isolate-inline-calendar-behind-app-component.md) — proposed, originating change `add-inline-daily-choice-calendar`. Ограничение: календарь остаётся компонентом `DailyChoiceCalendar` на `table_calendar` с контрактом на `CalendarDate`; страница владеет просмотром.
- [ADR-0025](../../../docs/adr/0025-load-calendar-day-marks-in-separate-viewport-model.md) — proposed, originating change `add-daily-choice-calendar-day-marks`. Ограничение: отметки получает отдельная модель по просмотру, а отказ их получения показывает сам календарь.
- [ADR-0029](../../../docs/adr/0029-represent-design-system-as-foundation-module.md) — proposed, originating change `add-design-foundation`. Ограничение: значения дизайн-системы и её компоненты живут в модуле основ; размеры из дизайна минимальные; решения проекта важнее советов дизайн-системы.
- [ADR-0028](../../../docs/adr/0028-scope-opening-parameter-state-to-page-instances.md) — proposed, originating change `add-contribution-statistics`. Ограничение: состояние календаря, включая открытый выбор года и месяца, принадлежит экземпляру каталога.
- [ADR-0020](../../../docs/adr/0020-host-persistent-navigation-in-ordinary-page-scaffolds.md) — proposed, originating change `add-quick-creation-and-persistent-navigation`. Ограничение: корневые страницы сохраняют собственный `Scaffold`, поэтому корневой каталог убирает только `AppBar`.

## Additional Context

- [ADR-0024](../../../docs/adr/0024-derive-calendar-day-states-from-saved-daily-choices.md) — proposed, originating change `add-daily-choice-calendar-day-marks`. Состояния дней по-прежнему вычисляются из сохранённых дневных выборов одним ограниченным чтением на общей ревизии. Решение 2 дизайна расширяет окно и предел чтения для шестинедельных сеток в этих границах; отдельной ADR это уточнение не требует.
- [ADR-0014](../../../docs/adr/0014-host-primary-navigation-in-root-page-shell.md) — proposed, originating change `add-home-navigation-and-favorites`. Исторический контекст оболочки корневых страниц; в части размещения панели её пересматривает ADR-0020.

## ADRs Owned by This Change

- [ADR-0030](../../../docs/adr/0030-keep-design-system-components-presentational.md) — proposed, originating change `redesign-daily-choice-calendar`. Дополняет ADR-0029: компоненты дизайн-системы — представления без предметных типов и локализации. Параллельное изменение `redesign-navigation-bar` следует этой записи.
- [ADR-0031](../../../docs/adr/0031-restrict-phones-to-portrait-full-screen.md) — proposed, originating change `redesign-daily-choice-calendar`. Телефоны работают только в портретной ориентации во весь экран.
