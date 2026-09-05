# Проверка OpenSpec change: manage-intentions

## Оценка

**Результат:** No unresolved findings

Planning artifacts однозначно разделяют connection evidence и фактический
межрелизный drift поисковой проекции. Задача 6.20c владеет типизированными
Doable-owned connection paths, отдельной `drift_dev` verifier boundary,
missing-setup и collision evidence на минимальной synthetic dependent schema.
Она явно supersedes только соответствующие недоказанные claims завершённой
6.20a и прежнюю формулировку 6.8 о прямом владении `QueryExecutor`.

Задача 6.22 после schema work 6.21 единолично владеет file-backed evidence двух
реализаций `doable_title_search_key` над фактическими `STORED GENERATED` key и
FTS. Повторное использование низкоуровневых test primitives не смешивает
ownership результатов. Финальный checkpoint 6.26 прямо включает evidence
6.20b и 6.20c. Последовательность `6.20b → 6.20c → 6.21 → 6.22 → 6.23 → 6.24
→ 6.25 → 6.26` остаётся ацикличной и исполнимой.

Предложение и behavioral specs менять не требуется: они владеют наблюдаемым
пользовательским и local-data lifecycle поведением, а обсуждаемая correction
остаётся внутренним механизмом исполнения уже утверждённого schema-function
contract. Принятый остаточный риск `AR1` сохраняется и не считается активным
замечанием.

**Валидация:** `openspec validate manage-intentions --type change --strict
--no-interactive`, `openspec schema validate intent-driven --json` и
`git diff --check` успешны. Код реализации в рамках исправления planning
artifacts не изменялся, поэтому runtime-тесты не запускались.

## Замечания

В проверенных planning artifacts и релевантном repository context нерешённых
замечаний не осталось.

## Принятые риски

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Доказательства:** действующие specs, design и ADR-0006 считают UTC
  wall-clock timestamps наблюдениями; каталог использует сохранённое значение и
  `IntentionId` как tie-breaker без causal clock.
- **Потенциальное влияние:** быстрые операции или перевод часов могут дать
  одинаковые либо убывающие timestamps, поэтому выбранный пользователем порядок
  иногда не совпадёт с фактической последовательностью действий.
- **Обоснование принятия:** отдельная revision/logical-clock модель или
  синтетическое продвижение времени несоразмерны вспомогательной сортировке и
  исказили бы наблюдаемое wall-clock значение.
- **Граница и предпосылки:** timestamps не используются как revision, causal
  order, средство синхронизации, аудита или разрешения конфликтов.
- **Пересмотреть, когда:** timestamps получают хронологически значимое
  поведение, появляется синхронизация/разрешение конфликтов либо наблюдается
  существенный пользовательский ущерб от перестановок.
- **Кем принято:** явное решение пользователя от 2026-09-03.
- **Исходное замечание:** F1 предыдущего implementation review.
- **Запись решения:** ADR-0006, соответствующие требования intention-management
  spec и раздел рисков design.

## Охват проверки

Сфокусированно проверены task ownership, dependency order и verification
coverage 6.20a–6.22 и 6.26 против ADR-0002, ADR-0008, design, Phase 6,
behavioral search contract и текущей SQLite schema. Отдельно проверено, что
synthetic connection evidence не требует преждевременной реализации generated
schema, а product mapping-drift evidence не дублируется до 6.21.

Предложение, specs, design, ADR и plan менять не потребовалось: исправление
уточняет исполнение уже утверждённых connection и search-projection contracts.
Принятый риск AR1 остаётся применим в прежней границе.
