# ADR-0008: Считать SQLite schema-functions долговечным контрактом

- Status: proposed
- Originating change: manage-intentions
- Date: 2026-09-04

## Контекст

SQLite schema version 1 вычисляет восстанавливаемый поисковый ключ названия через application-defined функцию `doable_title_search_key(TEXT)`. Generated column делает имя и сигнатуру функции частью сохраняемой схемы: отсутствие регистрации или несовместимая реализация может помешать открыть либо изменить существующую базу. Вызов из schema требует `directOnly: false`, что безопасно только при явно ограниченной функции и доверенном внутреннем файле.

## Решение

Имя и сигнатура каждой application-defined функции, на которую ссылается опубликованная SQLite-схема, являются долговечным schema contract. Единый канонический connection setup регистрирует такую функцию до разбора или использования схемы на каждом physical SQLite connection. Для Doable-owned executors типизированная capability доказывает, что setup привязан к их pre-open пути и будет выполнен до первого schema use; она не утверждает, что ленивое открытие уже произошло. Если verification tool или другой внешний компонент сам создаёт соединение, специализированный Doable adapter владеет передачей того же setup во внешний callback API и не выдаёт capability на чужое соединение. Дополнительный fixture setup выполняется раньше канонического, чтобы последняя регистрация зарезервированных имени и arity всегда принадлежала Doable. Capability-preserving tracing и fault injection доступны только через закрытые adapters local-data module: их hooks не принимают и не возвращают `QueryExecutor`, а open path безусловно делегируется исходному configured executor. Generic `QueryInterceptor` не сохраняет capability автоматически.

Callback должен быть total, deterministic и pure, не выполнять I/O, не читать изменяемое внешнее состояние и не писать пользовательские данные в diagnostics; analyzer configuration и contract tests подтверждают ту же сигнатуру.

`doable_title_search_key(TEXT)` регистрируется с `deterministic: true` и необходимым для generated column `directOnly: false`. Допустимый межрелизный дрейф её Unicode-данных ограничен восстанавливаемой поисковой проекцией так, как определяет capability; имя и сигнатура при этом не меняются. Doable открывает только собственный внутренний SQLite-файл. До появления импорта чужих баз, отключения trusted schema или более широкой модели угроз schema-function должна получить innocuous-capable реализацию либо быть удалена из схемы через отдельное миграционное решение.

## Последствия

- Каждый новый connection-owning path обязан либо создавать Doable-owned executor через типизированную factory, либо получить специализированный adapter к внешнему callback API; частичная регистрация хотя бы на одном физическом соединении считается несовместимой реализацией lifecycle.
- Произвольные interceptors и raw executors допустимы только в явно отделённых низкоуровневых test fixtures и не являются альтернативной границей создания `AppDatabase`.
- Переименование, изменение arity или удаление schema-function после публикации требует новой версии схемы и совместимой миграции, а не локального рефакторинга callback.
- Функции, не используемые сохраняемой схемой, не получают этот долговечный статус автоматически.
- Расширение trust boundary до импортированных файлов или `trusted_schema = OFF` блокируется до отдельного security и migration design.
