# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F5 · Low — В Badge представимо состояние без значка и слова

- **Решение:** Устранить
- **Как устранить:** Исправить в этой ветке новой задачей в конце Phase 1 tasks.md с номером 1.<следующий свободный>. Требуемый результат: варианты метки Badge выражены закрытым (sealed) типом, поэтому состояние без значка и слова не представимо, а ветки `(null, null) => throw StateError(...)` и разбора пары полей в `build` нет. Именованные конструкторы `Badge.mark`, `Badge.archived`, `Badge.word` остаются const, с теми же параметрами; вид, цвета, размеры и узлы экранного диктора не меняются. test/design_system/relation_row_test.dart читает `badge.icon` и `badge.tone`: сохранить эти геттеры, если это не возвращает необязательное поле в модель вариантов, либо перевести проверку на видимый результат; решает сессия исполнения по меньшей цене, не ослабляя проверку. Компонент остаётся представлением без предметной логики. Новых тестов не добавлять: состояние исключает компилятор, а поведение закрывает test/design_system/badge_test.dart. Проверка: `flutter test test/design_system/badge_test.dart test/design_system/relation_row_test.dart` и `flutter analyze`. Завершающая задача: если в implementation-review-decisions.md, кроме этой находки, не осталось других, после своей задачи добавить последнюю задачу Phase 1 — повторить проверки задачи 1.8 (`grep` на `excludedIntentionId`, `mise run check`, `openspec validate --strict`, `mise run codegen-check`, `flutter build apk --release`, ручные проверки). Ожидаемые артефакты: tasks.md, lib/src/design_system/components/badge.dart и при необходимости relation_row_test.dart.
