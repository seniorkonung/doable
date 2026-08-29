# OpenSpec Change Review: manage-intentions

## Оценка

**Результат:** Существенных замечаний нет

Предметное ядро capability определено верно: создание, просмотр, изменение, готовность к действию, архивирование, восстановление и физическое удаление образуют одну связную capability `intention-management`. Общий lifecycle локальных данных отделён в `local-data-lifecycle`, который владеет долговечностью установки, версиями схемы, миграциями, bootstrap recovery и общей политикой системного backup/transfer. Оба delta specs теперь формулируют платформонезависимое поведение.

Текущий change квалифицирует только Android host adapter: его внутреннее storage, backup rules, APK/manifest и ручной TalkBack evidence не становятся ограничениями capability или предметных interfaces, а поддержка других платформ не заявляется без их adapters и evidence. Будущая управляемая синхронизация не реализуется частично: независимые UUID и storage-neutral seam `IntentionRepository` сохраняют точку расширения, но remote port, transport, outbox, tombstones, revisions и конфликтные правила не входят в interface без наблюдаемого sync-контракта. Наблюдаемые ветви требований представлены исполнимыми примерами и прослеживаются в design, tasks и verification.

**Валидация:** `openspec validate manage-intentions --type change --strict --no-interactive` прошла; OpenSpec видит все 5 из 5 артефактов и 22 добавляемых требования в двух delta specs. Валидация подтверждает структуру Markdown и граф артефактов, но не проверяет полноту примеров, согласованность наблюдаемого поведения или фактическую поддержку platform hosts; текущая platform evidence ограничена Android.

## Замечания

Существенных замечаний в проверенных артефактах change и релевантном контексте репозитория не обнаружено.

## Покрытие ревью

Проверены единственный активный change и его фактический граф из proposal, двух delta specs, design, ADR-манифеста, четырёх repository-level ADR и tasks; canonical specs пока отсутствуют. Выполнены core-проверки intent/scope, наблюдаемого поведения, двусторонней трассировки proposal → specs → design → ADR → tasks → verification и исполнимости задач. В глубину проверены границы capability, разделение platform-neutral modules и Android host adapter, sync-ready seam без спекулятивных adapters, сценарии Gherkin, постоянные данные и миграции, bootstrap/recovery, конкурентные изменения, границы внутренней и внешней навигации, Android backup/transfer, локализация, доступность, диагностика, CI и rollback. Реализация ещё отсутствует и не проверялась; Apply, код и состояние tasks не изменялись.
