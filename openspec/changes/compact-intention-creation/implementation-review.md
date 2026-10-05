# OpenSpec Implementation Review: compact-intention-creation

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Задачи 2.15 и 2.16 выполнены. Сессия создания сама учитывает право ошибки, выданное ей координатором. Когда состояние перестаёт публиковать неподтверждённое право — правка снимает отказ, принята новая отправка, сессия закрыта по запросу или освобождена, — сессия передаёт его общей поверхности через существующий протокол координатора, даже если renderer его не получал. Подтверждённое или уже освобождённое renderer право повторно не предъявляется, а под непрозрачным выбором тегов право остаётся у формы. Готовность фазы 2 подтверждена заново на `ff8a6569…`: проходят `mise run check`, `codegen-check`, релизная сборка APK и строгая валидация изменения, а чувствительность сценария удаления хоста подтверждена временной мутацией. Активных замечаний нет. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 8cfca21dc7a3f1da96069022cdc19696eee9a3e3
- **Base commit:** 8cfca21dc7a3f1da96069022cdc19696eee9a3e3
- **Reviewed head:** ff8a6569e4a299fefdc921d5476b929517af3b73
- **Target commits:** ["1493662941ab33aa4a8ea2d57de80249b9ae02fb", "0385daf67c5dd54cb13d54cf07f68ce93a1634bd", "e770c5218afab54bcd16167b2cfc874dde2803ae", "ff8a6569e4a299fefdc921d5476b929517af3b73"]
- **Reviewable paths:** ["lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "openspec/changes/compact-intention-creation/tasks.md", "test/app/intention_creation_draft_integration_test.dart", "test/graph/presentation/operation_failure_presentation_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **OpenSpec change:** compact-intention-creation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/compact-intention-creation/tasks.md"]

## Reviewed increment

### U1 · Неподтверждённое право ошибки создания переходит от сессии общей поверхности ровно один раз, а готовность фазы 2 подтверждена заново

- **Work items:** ["2.15", "2.16"]
- **Requirements and scenarios:** ["intention-management (основная спецификация): Независимость принятой изменяющей операции от экрана — передача права ошибки при удалении renderer и завершении экранной сессии, сценарий «Ошибка создания после ухода с формы»", "intention-management: Создание намерения — Повторная попытка после устранимой ошибки создания", "intention-management: Сессия черновика и подтверждение его закрытия — Возвращение из выбора тегов сохраняет черновик, Уход во время принятой отправки", "design: решения 4 (подтверждённое закрытие передаёт непредъявленную ошибку общей поверхности) и 8 (владение правом ошибки)", "ADR-0012", "plan: Phase 2 — Ready to advance"]
- **Affected boundary:** Экранная сессия создания (`IntentionEditorViewModel` и `IntentionEditorState`), протокол владения предъявлением в `GraphCommandCoordinator`, inline-renderer `OperationFailurePresentation` и общая поверхность сообщений приложения.
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "test/app/intention_creation_draft_integration_test.dart", "test/graph/presentation/operation_failure_presentation_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **Applicable constraints and non-goals:** Каждый terminal outcome получает одно предъявление одним владельцем. Используется существующий протокол координатора, без второго presenter или ScaffoldMessenger. Временная невидимость живого renderer удерживает владельца. Сессия сама предъявление не подтверждает, а закрытие не отменяет принятую отправку. Гарантии 2.3 и 2.10 сохраняются: весь черновик остаётся после отказа, повтор допустим только по типизированной причине, отправка единственная, устаревшие подтверждения закрытия не действуют.
- **Excluded change scope:** Геометрия нижней панели, её маршрут, реальные жесты и способы закрытия, а также вызов `requestClose`, `resolveClose` и `draftTagSet` из production-хоста относятся к фазе 3.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий субагент без истории работал по `implementation-decision-review` с нейтральным брифом для U1. Он проверил точный диапазон `8cfca21d…ff8a6569` и все шесть путей поставки и тестов вне `tasks.md`. Неизменённый контекст он читал только после проверки, что файлы не менялись в диапазоне: `graph_command_coordinator.dart`, `operation_failure_presentation.dart`, `graph_operation_presenter.dart`, `presentation_frame_evidence.dart`, `intention_editor_page.dart`, `pubspec.lock`, исходники riverpod и flutter_riverpod 3.4.2. Существенных замечаний нет, покрытие полное. Названные им ограничения закрыты здесь: тесты и кодогенерацию запустил координатор, а отсутствие production-вызывающих у `requestClose`, `resolveClose` и `draftTagSet` — объём фазы 3. |
| OpenSpec conformance | Complete | Все проверки выполнены в этой рабочей копии при `HEAD` = `ff8a6569…` и чистом дереве. `mise exec --no-deps -- flutter test` по `intention_editor_view_model_test.dart`, `intention_editor_page_test.dart`, `operation_failure_presentation_test.dart` и `intention_creation_draft_integration_test.dart` — 110 тестов прошли. `mise run check` — код 0: форматирование 515 файлов без изменений, проверка области CI, `flutter analyze` без замечаний, 4 189 тестов приложения и 8 тестов Widgetbook прошли. `MISE_AUTO_INSTALL=false mise run --skip-tools codegen-check` — код 0, дерево осталось чистым. `mise exec --no-deps -- flutter build apk --release` — код 0. `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive` — изменение допустимо, замечаний нет. Чувствительность проверена в одноразовой копии `ff8a6569…` вне репозитория: без освобождения права в `_publishFailureClaim` падает сценарий «сброс стека без нового построения хоста». В `tasks.md` изменились только отметки 2.15 и 2.16. План, дизайн и спецификации в диапазоне не менялись. Фаза 3 не считалась обязательством этого инкремента. |
| Code quality | Complete | Через `code-review-and-quality` проверены все пути поставки по пяти направлениям: корректность, читаемость, архитектура, безопасность, производительность. Сюда вошли переходы `IntentionEditorState`, новый `closedOnRequest`, теневое поле `_publishedFailureClaim`, освобождение права в `listenSelf` и `onDispose`, а также производный провайдер. Вместе с ними просмотрены неизменённые `claimInitiatorFailure`, `releaseInitiatorClaim`, `releaseInitiatorPresentation`, `confirmPresentation` координатора, `OperationFailurePresentation` и `IntentionEditorPage`. Освобождение идемпотентно при любом порядке вызовов сессии, renderer и `onDispose`. Теневое поле нужно, чтобы освободить право при уничтожении и пересборке провайдера. Новых входов, данных диагностики, зависимостей и горячих путей нет. Замечаний нет. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Проверены все 4 коммита диапазона и все 7 путей. `tasks.md` использован как планировочное свидетельство.

Задача 2.15 сопоставлена коммиту `14936629…` (реализация и тесты) с отметкой `0385daf6…`. На `0385daf6…` описания в производном `intention_editor_view_model.g.dart` и хэш провайдера ещё отставали от источника. Задача 2.16 сопоставлена коммиту `e770c521…` (перегенерация провайдера) с отметкой `ff8a6569…`; итоговые проверки этой контрольной точки воспроизведены этим ревью. Путей без задачи нет.

Сверено, что каждая ветвь передачи права доходит до единственного освобождения: снятие отказа текстовой правкой и явным снятием отсутствующих тегов (`_withEditedText`, `_withEditedTags`), новая отправка (`withOperation` без права), немедленное и подтверждённое закрытие по запросу, освобождение сессии. Неснимающие правки, обновления проекции тегов и ожидающее подтверждение закрытия сохраняют право формы. Под выбором тегов контракт набора даёт только добавление, а оно не снимает ни один тип отказа.

В протоколе координатора `releaseInitiatorClaim` действует только для текущего права, а после `confirmPresentation` запись удаляется. Поэтому подтверждённое renderer право общая поверхность не получает, а освобождённое renderer — получает один раз.

Прочитаны новые группы тестов ViewModel без renderer: освобождение, немедленное и подтверждённое закрытие, все четыре вида снятия отказа, новая отправка, подтверждённое и освобождённое renderer право. Прочитан виджетный хост с настоящими `OperationFailurePresentation`, координатором, регистрацией общей поверхности и `TagCatalogPage` с контекстом черновика; он проверяет возвращение на форму, `popUntil` и сброс стека без построения хоста и не имитирует передачу права ручным `releaseInitiatorClaim`. В интеграционной контрольной точке снятие отсутствующего тега и явный повтор устранимой недоступности теперь дают одно сообщение общей поверхности о прежнем отказе раньше результата повтора.

Документация класса сессии, поля `failurePresentation`, `withOperation`, `closedOnRequest`, `_operationAfterEditing` и `_endOnRequest` называет фактического владельца права. Прежних утверждений, что право остаётся только у renderer, в каталоге редактора не осталось.

Схема, миграции, зависимости, локализации и внешние сервисы в диапазоне не менялись. Приложение через DTD не проверялось: код в этом этапе не менялся, использованы проверки CLI.
