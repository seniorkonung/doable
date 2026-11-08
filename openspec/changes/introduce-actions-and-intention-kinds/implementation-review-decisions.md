# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F10 · Low — Состав каскада несёт поля, которые никто не показывает, и предпросмотр читает для них названия

- **Решение:** Устранить
- **Как устранить:** Устранить вариантом (а): удалить поля состава каскада без потребителя. Добавить в конец фазы 4 tasks.md новую задачу 4.<следующий свободный номер>. Удалить ArchiveCascadeComposition.mainsLosingRelation и DeleteCascadeComposition.archivedRelationCount (lib/src/intention/application/cascade/intention_cascade.dart), их вычисление в lib/src/graph/data/intention_cascade_planner.dart и чтение названий главных намерений архивирования в lib/src/graph/data/drift_intention_cascade_preview.dart (_listedIntentions для ArchiveCascadeComposition). Используемые поля сохранить: DeleteCascadeComposition.mainsLosingRelation (список «Главные, теряют только связь» на странице удаления намерения) и ArchiveCascadeComposition.archivedRelationCount (подсказка архивирования в intention_options.dart). Проверка конфликта эти поля не сравнивает, поэтому поведение не меняется. Обновить тесты планировщика, эталон test/support/intention_cascade_reference.dart и тесты предпросмотра, убрав проверки удалённых полей. Нового требования не добавлять; спеку не менять. Проверка: тесты планировщика, предпросмотра и хранилища каскада и `mise exec --no-deps -- flutter test test/intention/presentation/details`. Ожидаемые артефакты: tasks.md, intention_cascade.dart, intention_cascade_planner.dart, drift_intention_cascade_preview.dart, эталон и тесты каскада.
