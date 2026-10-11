## Phase 1: Дневной выбор использует только пошаговое построение пути

- [x] 1.1 Перевести сохраняемые сквозные проверки создания, замены пути и выхода на пошаговый выбор
  - **Критерии приёмки:**
    - Проверки создания и замены в обоих направлениях достигают подтверждения через шаги пути; обращения к подсказкам и проверки их предпросмотра удалены. Сценарий в `test/app/daily_choice_app_lifecycle_test.dart`, открывающий подтверждение через `choice-suggestion-select-0`, также переведён на пошаговый выбор снизу вверх.
    - Сохраняются проверки независимых полей, актуализации после конфликта, атомарной замены, исходной истории, чужого черновика и позднего результата принятой команды по [спецификации дневных выборов](specs/daily-choice-management/spec.md). Сценарий жизненного цикла сохраняет проверки защиты от повторной отправки, завершения записи после ухода с подтверждения и потери фокуса, однократного предъявления результата после возвращения фокуса и просмотра созданного выбора. Дублирующие сценарии после перевода объединены без потери самостоятельных гарантий.
    - Из `test/app/navigation/app_shell_unnamed_page_scenarios.dart` удалены только сценарии предпросмотра подсказок в обоих направлениях и вспомогательный код без оставшихся потребителей. Проверки построения пути, подтверждения замены и блокировки обычной страницы и панели открытым диалогом сохранены; смешанный набор запускается через `test/app/navigation/app_shell_pages_above_test.dart`.
  - **Проверка:** `flutter test test/daily_choice/presentation/daily_choice_creation_flow_test.dart test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart test/daily_choice/presentation/daily_choice_creation_exit_test.dart test/app/daily_choice_app_lifecycle_test.dart test/app/navigation/app_shell_pages_above_test.dart`.
  - **Зависимости:** нет; существующий пошаговый контракт уже доступен.
  - **Вероятные файлы:** `test/daily_choice/presentation/daily_choice_creation_flow_test.dart`, `test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart`, `test/daily_choice/presentation/daily_choice_creation_exit_test.dart`, `test/app/daily_choice_app_lifecycle_test.dart`, `test/app/navigation/app_shell_unnamed_page_scenarios.dart`.
  - **Объём:** M.

- [x] 1.2 Оставить на странице пути только пошаговый выбор с явным подтверждением
  - **Критерии приёмки:**
    - Страница пути больше не создаёт и не обслуживает модель подсказок, не предлагает прежние маршруты и не открывает их предпросмотр; удалены представление подсказок, его отдельные тесты и конструктор шага подтверждения из подсказки по решениям 2 и 5 [дизайна](design.md).
    - Сценарий «Сохранённый маршрут не предлагается при новом выборе» проверяется с уже сохранённым допустимым путём: построение начинается от выбранного участника без предложения или подстановки шагов, а подтверждение требует пошагового прохода. Проверка выявляет прежнее поведение до изменения и проходит после него.
  - **Проверка:** `flutter test test/daily_choice/presentation/path/choice_path_page_test.dart test/daily_choice/presentation/daily_choice_creation_flow_test.dart test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart`; `flutter analyze`.
  - **Зависимости:** 1.1; сохраняемые сквозные проверки, включая жизненный цикл приложения и смешанный набор навигации, уже не используют интерфейс подсказок.
  - **Вероятные файлы:** `lib/src/daily_choice/presentation/path/choice_path_page.dart`, `lib/src/daily_choice/presentation/path/choice_path_suggestions_view.dart`, `lib/src/daily_choice/presentation/editor/daily_choice_creation_page.dart`, `test/daily_choice/presentation/path/choice_path_suggestions_view_test.dart`, `test/daily_choice/presentation/daily_choice_creation_flow_test.dart`.
  - **Объём:** M.

- [x] 1.3 Сократить выход из создания до оставшихся страниц собственного потока
  - **Критерии приёмки:**
    - Из действия выхода и обработчика завершения удалены параметр `previewRoute` и ветви владения предпросмотром.
    - Сохраняются проверки принадлежности страниц потоку и наличия безымянной страницы сверху, необходимые при открытом диалоге; обычный возврат, отмена и поздний результат следуют решению 3 дизайна и навигационному контексту из [ADR-манифеста](adr.md).
  - **Проверка:** `flutter test test/daily_choice/presentation/daily_choice_creation_exit_test.dart test/daily_choice/presentation/daily_choice_creation_completion_test.dart test/daily_choice/presentation/daily_choice_creation_flow_session_test.dart`.
  - **Зависимости:** 1.2; единственный потребитель специального параметра удалён вместе с представлением.
  - **Вероятные файлы:** `lib/src/daily_choice/presentation/daily_choice_creation_exit_action.dart`, `lib/src/daily_choice/presentation/daily_choice_creation_completion.dart`; при необходимости адаптации — `test/daily_choice/presentation/daily_choice_creation_exit_test.dart`.
  - **Объём:** S.

- [x] 1.4 Подтвердить работоспособность пользовательских потоков без предложений прежнего маршрута
  - **Критерии приёмки:**
    - Создание, актуализация и замена в обоих направлениях, отмена и завершение принятой команды работают через оставшиеся страницы; существующие проверки навигации и независимых полей проходят.
    - Поведение согласовано с delta-спецификациями [дневных выборов](specs/daily-choice-management/spec.md) и [навигации](specs/app-navigation/spec.md), что позволяет удалять оставшуюся внутреннюю поддержку подсказок.
  - **Проверка:** `flutter test test/daily_choice/presentation test/app/daily_choice_app_flow_test.dart test/app/daily_choice_app_lifecycle_test.dart test/app/navigation/app_shell_pages_above_test.dart`; `openspec validate remove-previous-route-reuse --strict`.
  - **Зависимости:** 1.1, 1.2, 1.3.
  - **Вероятные файлы:** нет, только проверка; результаты сообщаются в сессии.
  - **Объём:** XS.

- [x] 1.5 Исключить подсказки из общих проверок согласования графа
  - **Критерии приёмки:**
    - Общие проверки согласования и потребителей пакетов изменений больше не создают модель подсказок и не ожидают её состояния; обслуживающие только её фикстуры и вспомогательные преобразования удалены.
    - Проверки остальных потребителей, атомарного согласования и ограниченности чтений сохраняют прежние гарантии по принятому [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md).
  - **Проверка:** `flutter test test/graph/presentation/graph_reconciliation_checkpoint_test.dart test/graph/presentation/favorite_mark_package_consumers_test.dart test/graph/presentation/tag_package_catalog_consumers_test.dart`.
  - **Зависимости:** нет; эти потребители находятся только в тестах.
  - **Вероятные файлы:** три перечисленных файла проверок и `test/graph/presentation/package_consumers_test_support.dart`.
  - **Объём:** M.

- [x] 1.6 Удалить невостребованные состояния и модель представления подсказок
  - **Критерии приёмки:**
    - Модель подсказок, её состояния и отдельные тесты удалены вместе с подписками и согласованием, принадлежавшими только этому представлению.
    - Модель пошагового пути и её существующий контракт сохраняются; новые модели или интерфейсы взамен удалённых не вводятся.
  - **Проверка:** `flutter analyze`; `flutter test test/daily_choice/presentation/path test/graph/presentation`.
  - **Зависимости:** 1.4, 1.5; пользовательские и тестовые потребители модели уже устранены.
  - **Вероятные файлы:** `lib/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart`, `lib/src/daily_choice/presentation/path/choice_path_suggestions_state.dart`, `test/daily_choice/presentation/path/choice_path_suggestions_view_model_test.dart`.
  - **Объём:** S.

- [x] 1.7 Сохранить проверки стоимости чтений и длинных путей без получения подсказок
  - **Критерии приёмки:**
    - Из смешанной проверки удалены отбор недавних кандидатов, актуализация подсказок и только необходимые им данные.
    - Проверки каталога, дневных групп, полного длинного пути, его сохранения и замены остаются; необходимые подтверждённые пути подготавливаются через существующие типы без запроса подсказок.
  - **Проверка:** `flutter test test/graph/data/drift_daily_choice_read_cost_test.dart`; убедиться, что сохраняемые проверки выполняются, включая помеченные `slow`.
  - **Зависимости:** нет; действующие контракты пути и репозитория уже позволяют подготовить эти данные.
  - **Вероятные файлы:** `test/graph/data/drift_daily_choice_read_cost_test.dart`.
  - **Объём:** S.

- [x] 1.8 Удалить контракт чтения подсказок со всеми реализациями и отдельными тестами
  - **Критерии приёмки:**
    - Типы подсказок, метод `getChoicePathSuggestions`, его делегирование, Drift-реализация и отдельные прикладные и репозиторные тесты удалены по решению 1 дизайна; отбор кандидатов и специальная проверка пути больше не исполняются.
    - Все тестовые реализации репозитория согласованно лишены метода и ненужных импортов. `ConfirmedChoicePath`, чтение подробностей и транзакционная проверка нового пути остаются у существующих потребителей.
  - **Проверка:** `flutter analyze`; `flutter test test/daily_choice/application test/graph/application test/graph/data/drift_choice_path_continuations_test.dart test/graph/data/drift_daily_choice_create_test.dart test/graph/data/drift_daily_choice_replace_test.dart test/graph/data/drift_daily_choice_read_test.dart`.
  - **Зависимости:** 1.1, 1.6, 1.7; все сохраняемые потребители удаляемого метода уже переведены.
  - **Вероятные файлы:** `lib/src/daily_choice/application/choice_path_suggestions.dart`, `lib/src/graph/application/personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository_choice_path_suggestions.dart`, `test/daily_choice/application/choice_path_suggestions_test.dart`, `test/graph/data/drift_choice_path_suggestions_test.dart`; реализации и обёртки репозитория в `test/app/`, `test/intention/presentation/`, `test/long_term_relation/presentation/`, `test/graph/application/`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart` и `test/daily_choice/presentation/daily_choice_creation_exit_test.dart`.
  - **Объём:** M; одна согласованная правка контракта с механическим удалением его повторяющихся реализаций в тестах.

- [x] 1.9 Удалить индексы недавних выборов, сохранив чтение общих счётчиков и целостность схемы
  - **Критерии приёмки:**
    - `daily_choices_source_recent` и `daily_choices_selected_recent` удалены из единственной схемы версии 1 и её производных артефактов по решению 4 дизайна, без миграции и удаления пользовательских записей.
    - Принудительные ссылки `INDEXED BY` в агрегатах дневных связей переведены на сохраняемые `daily_choices_source_date_creation_order` и `daily_choices_selected_date_creation_order`; запросы счётчиков и групп продолжают работать.
    - Таблицы, ограничения, триггеры защиты пути и остальные индексы сохранены; снимок схемы соответствует генерируемой базе по условиям [ADR-0002](../../../docs/adr/0002-use-drift-sqlite-for-local-graph.md) и ADR-манифеста.
  - **Проверка:** `mise run codegen`; `flutter test test/data/local test/graph/data/drift_relation_count_aggregates_test.dart test/graph/data/drift_daily_choice_groups_test.dart test/graph/data/drift_daily_choice_read_cost_test.dart test/graph/data/file_backed_daily_choice_durability_test.dart`.
  - **Зависимости:** 1.8.
  - **Вероятные файлы:** `lib/src/data/local/schema/daily_choice_schema.drift`, `lib/src/graph/data/drift_relation_count_aggregates.dart`, `lib/src/data/local/app_database.g.dart`, `drift_schemas/drift_schema_v1.json`.
  - **Объём:** M.

- [x] 1.10 Удалить диагностические события, принадлежавшие чтению подсказок
  - **Критерии приёмки:**
    - Удалены `ChoicePathSuggestionReadStage`, `ChoicePathSuggestionReadDiagnosticsEvent` и их представление в диагностическом приёмнике.
    - Диагностика пошагового чтения, проверки и записи пути сохраняется; общие события и канал предъявления результатов по [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) не изменены.
  - **Проверка:** `flutter test test/shared/diagnostics/diagnostics_sink_test.dart test/graph/data/drift_daily_choice_diagnostics_test.dart`; `flutter analyze`.
  - **Зависимости:** 1.8; источник удаляемых событий больше не существует.
  - **Вероятные файлы:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`.
  - **Объём:** S.

- [x] 1.11 Удалить локализованные строки подсказок и согласовать генерируемые локализации
  - **Критерии приёмки:**
    - Ключи `choiceSuggestion*` и их метаданные удалены из обеих локалей, сгенерированные классы больше не предоставляют эти сообщения.
    - Общие строки сохраняются у действующих потребителей; проверки дневного выбора используют оставшийся интерфейс.
  - **Проверка:** `flutter gen-l10n`; `flutter analyze`; `flutter test test/daily_choice/presentation/path/choice_path_page_test.dart test/daily_choice/presentation/daily_choice_creation_flow_test.dart test/daily_choice/presentation/daily_choice_path_replacement_flow_test.dart`.
  - **Зависимости:** 1.6; представление подсказок и его тесты удалены.
  - **Вероятные файлы:** `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_ru.dart`, `lib/l10n/app_localizations_en.dart`.
  - **Объём:** S.

- [ ] 1.12 Согласовать актуальное описание продукта с пошаговым построением пути
  - **Критерии приёмки:**
    - Из обсуждения предметной системы удалены описание механизма подсказок и утверждения о доступности повтора при создании и замене; описание соответствует delta-спецификациям и решению 5 дизайна.
    - Архив OpenSpec и самостоятельные смыслы переиспользуемой декомпозиции и тегов сохранены. Изменения основных спецификаций остаются представлены delta-файлами для штатной синхронизации OpenSpec.
  - **Проверка:** `rg -n 'подсказ|прежн|повтор' docs/discussions/action-centered-goal-system.md` с оценкой найденного текста по смыслу; `openspec validate remove-previous-route-reuse --strict`.
  - **Зависимости:** 1.4; новое пользовательское поведение уже проверено.
  - **Вероятные файлы:** `docs/discussions/action-centered-goal-system.md`.
  - **Объём:** S.

- [ ] 1.13 Подтвердить готовность единственной фазы к итоговой проверке изменения
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» из [плана](plan.md): поддержка повтора удалена, сохраняемые потоки, владение навигацией, завершение команд и целостность дневных выборов подтверждены проверками.
    - Действующие проверки сохраняют ограничения готовности и независимое редактирование сохранённых выборов по [спецификации намерений](specs/intention-management/spec.md); код, актуальная документация и delta-спецификации согласованы, производные артефакты воспроизводимы.
    - Проверка изменений подтверждает точную границу удаления без потери общих механизмов; результаты проверок сообщены в сессии.
  - **Проверка:**
    - `mise run check`, включая полный набор тестов с `slow`; `openspec validate remove-previous-route-reuse --strict`.
    - После фиксации согласованных изменений, включая артефакты OpenSpec, — `mise run codegen-check` на чистой рабочей копии: эта команда требует отсутствия незакоммиченных файлов до и после генерации.
    - `rg -n 'ChoicePathSuggestion|choice_path_suggestions|getChoicePathSuggestions|fromSuggestion|choiceSuggestion|previewRoute|daily_choices_(source|selected)_recent' lib test widgetbook drift_schemas` не находит остатков удаляемой поддержки; архив и артефакты данного удаления в область поиска не входят.
    - Проверить итоговый diff по навыку `code-review-and-quality`, включая сохранение общих проверок пути и ссылочной целостности; `git diff --check`.
  - **Зависимости:** 1.1–1.12.
  - **Вероятные файлы:** нет, только проверка; отдельный документ с результатами не создаётся.
  - **Объём:** XS.
