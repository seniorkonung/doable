# Манифест проверки ADR

- Status: completed
- Review date: 2026-08-28

## Результат проверки

Проверка ADR для change `manage-intentions` завершена. Design вводит четыре долговечных архитектурных решения, которые влияют на последующие change графа и требуют repository-level ADR.

## Рассмотренные действующие ADR

- Отсутствовали — до этой проверки каталог `docs/adr/` не существовал, действующих или superseded ADR в репозитории не было.

## Созданные долговечные ADR

- [ADR-0001: Сосредоточить управление намерениями в глубоком модуле](../../../docs/adr/0001-deep-intention-management-module.md)
- [ADR-0002: Хранить локальный граф в SQLite через Drift](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md)
- [ADR-0003: Использовать UUID v4 для идентичности намерений](../../../docs/adr/0003-use-uuid-v4-for-domain-identities.md)
- [ADR-0004: Сохранять личный граф только внутри приложения на устройстве](../../../docs/adr/0004-keep-personal-graph-device-local.md)

Ни один ранее принятый ADR не изменён и не superseded.
