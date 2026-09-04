# Проверка OpenSpec change: manage-intentions

## Оценка

**Результат:** Существенных замечаний нет.

Граф артефактов согласован в обоих направлениях. Specs определяют общую границу
пользовательского текста как корректную последовательность скалярных значений
Unicode без `U+0000`, отдельные правила названия, описания и фильтра и
наблюдаемое поведение при отказе. Design проводит этот контракт до lossy
UTF-8/SQLite/FTS-перехода, сохраняет field-specific типы, добавляет NUL-защиту
схемы и полную проверку описания внутри ограниченной catalog materialization.
ADR-0007 распространяет решение на будущие текстовые поля графа, импорт и
синхронизацию, а ADR-0008 закрепляет lifecycle и trust boundary сохраняемой
SQLite schema-function.

Незавершённая Phase 6 имеет последовательную corrective chain 6.24–6.26 после
cursor/search checkpoint: общий Unicode contract предшествует schema/catalog
integrity, а финальный checkpoint зависит от обоих результатов. Phase 7 владеет
локализованным field-specific объяснением без потери ввода. Выполненные задачи и
завершённые Phase 1–5 не переписаны. Текущий код ещё не соответствует новому
контракту; это ожидаемая implementation delta, явно принадлежащая unchecked
задачам, а не разрешение на Apply или утверждение о готовности реализации.

**Валидация:** `openspec validate manage-intentions --type change --strict
--no-interactive --json` успешна: 1/1, структурных issues нет. Команда проверяет
структуру OpenSpec, но не доказывает будущую реализацию задач, runtime-поведение
SQLite/FTS или Android UI.

## Замечания

Существенных замечаний в проверенных артефактах change и относящемся к ним
контексте репозитория не найдено.

## Охват проверки

Перечитаны полный artifact graph `proposal → specs → design → adr → plan →
tasks`, предметный glossary, действующие и superseded ADR, текущий review,
implementation-review и затронутые domain/application/Drift/SQLite/FTS seams и
tests. Проверены intent и non-goals, capability ownership, Unicode scalar/NUL и
malformed UTF-16 boundaries, буквальный поиск, описание в ограниченном каталоге,
generated search projection, schema-function lifecycle и security boundary,
неопубликованная schema version 1, rollback, bounded materialization,
локализация, diagnostics без пользовательского текста, будущие описания, теги,
импорт и синхронизация. Отдельно сверены двусторонняя traceability,
dependency-order, сохранность завершённого task ledger и исполнимость каждого
нового acceptance/verification contract по существующим путям репозитория.
