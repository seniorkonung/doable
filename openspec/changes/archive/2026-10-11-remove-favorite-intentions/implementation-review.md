# OpenSpec Implementation Review: remove-favorite-intentions

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все три целевых коммита и обе задачи 1.20–1.21. Единая база токенов сохраняет пять конкретных видов операций, идентичность токенов и раздельные права предъявления. Проверки подтверждают сохранение поведения и воспроизводимость генерации. Неразрешённых замечаний и принятых остаточных рисков нет.

## Review target

- **Baseline ref:** f3037ae3dadcabc02f1bf6e0451bda6feff9cb91
- **Base commit:** f3037ae3dadcabc02f1bf6e0451bda6feff9cb91
- **Reviewed head:** 43285c3693478d3bc9454f26ce522686fbb3764f
- **Target commits:** ["254769a0ef2c6d7cb9caf877b50179dc590ea5c0", "cdda1de868727dad3b2b9d2cfb8dce62d6676b8d", "43285c3693478d3bc9454f26ce522686fbb3764f"]
- **Reviewable paths:** ["lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "openspec/changes/remove-favorite-intentions/tasks.md", "test/graph/presentation/graph_operation_presenter_test.dart"]
- **OpenSpec change:** remove-favorite-intentions
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/remove-favorite-intentions/tasks.md"]

## Reviewed increment

### U1 · Единая база токенов сохраняет права предъявления и готовность фазы

- **Work items:** ["20 (1.20): Оставить единую базу токенов операций без изменения прав предъявления", "21 (1.21): Подтвердить готовность фазы после упрощения баз токенов"]
- **Requirements and scenarios:** ["design.md: решение 4 — единая база токенов и раздельные права предъявления", "plan.md: Phase 1 — Ready to advance", "intention-management: Независимость принятой изменяющей операции от экрана / Уход до кадра с ошибкой формы", "intention-management: Независимость принятой изменяющей операции от экрана / Ожидающее сообщение не потребляется вместе с текущим", "intention-management: Независимость принятой изменяющей операции от экрана / Пересоздание презентера при сохранённой общей поверхности", "intention-management: Независимость принятой изменяющей операции от экрана / Досрочное снятие после подтверждённого кадра не повторяет результат", "app-navigation: Сброс истории выбором пункта / Сброс не отменяет принятую операцию"]
- **Affected boundary:** Принятые операции личного графа, их токены, экранные сессии инициаторов и общая поверхность сообщений приложения.
- **Implementation target:** ["lib/src/graph/application/graph_command_coordinator.dart", "lib/src/graph/application/graph_command_coordinator.g.dart", "test/graph/presentation/graph_operation_presenter_test.dart"]
- **Applicable constraints and non-goals:** Сохраняются контракт ADR-0012, пять конкретных видов токенов, раздельные исключительные claims инициатора и общей поверхности, последовательная публикация, блокировки повторной отправки и ожидание принятых команд до закрытия базы по ADR-0009. Упрощение не вводит новые операции, проверки типов или совместимые псевдонимы; предметные правила, навигация и содержание Главной не пересматриваются.
- **Excluded change scope:** Реализация задач 1.1–1.19 предшествует base и рассматривается только как контекст и вход полного проверочного набора задачи 1.21. Их исходный диапазон повторно не включён в аудит. Синхронизация основных спецификаций и архивирование находятся вне этого этапа.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный рецензент `/root/token_decision_review` без истории получил нейтральное намерение, точные base/head и все три delivery/test-пути U1. Прочитал полный diff и файлы, проверил неизменённость каждого внешнего context path перед чтением. Planning, отчёт и описания коммитов не передавались. Результат: `No substantive findings`, покрытие полное; исполнение проверок выполнено координатором. |
| OpenSpec conformance | Complete | Обе задачи сопоставлены U1, просмотрены все три отдельных коммита. Метаданные и versioned planning сопоставлены с saved head. Из корня репозитория на чистом checkout `43285c3693478d3bc9454f26ce522686fbb3764f` выполнены `mise run check`, `mise run codegen-check` и строгая валидация OpenSpec; все завершились exit 0. |
| Code quality | Complete | Все три delivery/test-пути проверены по корректности, читаемости, архитектуре, безопасности и производительности. Прослежены владение claims, экранные потребители, очередь общей поверхности и остановка приложения. Типовые изменения не добавляют исполняемых ветвей, зависимостей, внешних входов или запросов. Проверены сохранность тестовых утверждений, отсутствие удалённого типа, история задач и `git diff --check` точного диапазона. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все ссылки на код и тесты ниже относятся к reviewed head `43285c3693478d3bc9454f26ce522686fbb3764f`; прежние типы и изменённые участки сопоставлены с base `f3037ae3dadcabc02f1bf6e0451bda6feff9cb91`. Discovery зафиксировал четыре reviewable-пути: три delivery/test-пути U1 и `tasks.md` как planning evidence. Неотнесённых путей, задач или целевых коммитов нет. Одна единица обоснована общим результатом: упрощение контракта токенов и подтверждение сохранности того же поведения.

Коммит `254769a0ef2c6d7cb9caf877b50179dc590ea5c0` сопоставлен ID 20, 1.20 → U1. Удаление промежуточной базы, непосредственное наследование пяти конкретных токенов, изменение трёх прикладных сигнатур и двух тестовых параметров; отметка выполнения 1.20.

Коммит `cdda1de868727dad3b2b9d2cfb8dce62d6676b8d` сопоставлен ID 21, 1.21 → U1; генерируемое следствие 1.20. Единственное изменение — hash Riverpod-провайдера. Воспроизводимость проверена штатным `codegen-check` на конечном head.

Коммит `43285c3693478d3bc9454f26ce522686fbb3764f` сопоставлен ID 21, 1.21 → U1. Единственное изменение — отметка выполнения 1.21. Checkbox не доказывает исторический запуск; актуальное свидетельство получено проверками в этой сессии.

Оба сохранённых task commit range проверены: 1.20 — `f3037ae3dadcabc02f1bf6e0451bda6feff9cb91..254769a0ef2c6d7cb9caf877b50179dc590ea5c0`; 1.21 — `254769a0ef2c6d7cb9caf877b50179dc590ea5c0..43285c3693478d3bc9454f26ce522686fbb3764f`. Сравнение полного `tasks.md` base/head подтвердило, что изменены только два checkbox: номера, описания, порядок и все ранее выполненные задачи сохранены.

В `lib/src/graph/application/graph_command_coordinator.dart:108` закрытая база имеет ровно пять прямых конкретных наследников с прежними закрытыми конструкторами и идентичностью объектов. В `:458` остаются разные конечные типы прав инициатора и приложения. В `:891`, `:915`, `:957` сохранены проверки отказа, освобождения сессии и идентичности действующего claim. Удаление промежуточной базы не расширяет набор реально создаваемых токенов. В тестовом файле изменены только типы параметров `:1595` и `:2003`; утверждения не удалены и не ослаблены.

Порядок принятия и публикации, блокировки и время жизни команд остаются в `graph_command_coordinator.dart:844`, ожидание завершения — в `:981` и `:1136`. Неизменённый `lib/src/app/app_runtime.dart:218` ожидает coordinator перед закрытием локального хранилища. Проверены потребители намерений, долговременных связей, массового удаления связей, дневных выборов и тегов. Общая поверхность `lib/src/graph/presentation/graph_operation_presenter.dart:75` запрашивает следующее право только после закрытия текущего сообщения. Новых разрешений, способов ввода данных, хранения, диагностических событий или затрат выполнения диапазон не вводит. Различие типов токенов сокращено без замены проверками времени выполнения; новое тестовое дублирование отсутствует.

Условие «Уход до кадра с ошибкой формы; отказ сначала принадлежит живому инициатору»: `test/intention/presentation/operation/intention_command_coordinator_test.dart:254` проверяет передачу отказа и бездействие прежнего права; `test/graph/presentation/operation_failure_presentation_test.dart:284` проверяет удаление формы до кадра.

Условие «Ожидающее сообщение не потребляется вместе с текущим»: `test/graph/presentation/graph_operation_presenter_test.dart:46` проверяет последовательный показ и отсутствие вытеснения; `test/intention/presentation/operation/intention_command_coordinator_test.dart:590` проверяет выдачу следующего app claim.

Условие «Пересоздание презентера при сохранённой общей поверхности»: `test/graph/presentation/graph_operation_presenter_test.dart:790` проверяет снятие прежней поверхности до подтверждения; `test/intention/presentation/operation/intention_command_coordinator_test.dart:627` проверяет перевыдачу и бездействие позднего подтверждения.

Условие «Досрочное снятие после подтверждённого кадра не повторяет результат»: `test/graph/presentation/graph_operation_presenter_test.dart:861` проверяет продолжение очереди без возврата предъявленного сообщения.

Условие «Сброс истории не отменяет принятую операцию»: `test/app/navigation/app_shell_operation_reset_test.dart:373` проверяет завершение команды при сбросе; `test/intention/presentation/operation/intention_command_coordinator_test.dart:726` проверяет сохранение gate после ухода.

Условие «Публикация завершений, отдельные токены и остановка приложения»: `test/intention/presentation/operation/intention_command_coordinator_test.dart:79`, `:133`, `:395`, `:809` и существующие наборы `test/graph/application/` проверяют порядок, одну отправку, один результат и ожидание принятых команд.

Контекст соответствия прочитан из committed head: `proposal.md`, три дельты `specs/*/spec.md`, `design.md`, `adr.md`, `plan.md`, `tasks.md`, `.openspec.yaml`, канонический контракт предъявления и применимые ADR-0009/ADR-0012. `status` и `instructions apply` использованы только для чтения метаданных; CLI подтвердил схему `intent-driven` и 21 завершённую задачу. Незакоммиченных исходных или planning-изменений не было. Независимый проход завершён до чтения существующего отчёта; активных F и AR для переноса нет.

Проверки выполнены в этой сессии из `/home/seniorkonung/.paseo/worktrees/1id27gtb/rotten-gopher` на точном reviewed head, до записи отчёта:

Команда `mise run check` — exit 0: форматирование 546 файлов без изменений, проверки CI scope прошли, анализатор сообщил `No issues found!`, все 2380 тестов приложения и четыре теста Widgetbook прошли. Это включает указанные контрактные проверки предъявления, проверки навигации, сессии создания, атомарного отката, схемы и файловой долговечности.

Команда `mise run codegen-check` — exit 0 из чистого дерева на том же head: повторные генерация локализации, build_runner и выгрузка снимка Drift не изменили отслеживаемые файлы; build_runner записал 0 outputs. После проверки дерево осталось чистым.

Команда `mise exec --no-deps -- openspec validate remove-favorite-intentions --type change --strict --no-interactive --json` — exit 0: passed 1, failed 0, issues пусты. Это структурная проверка committed planning, а не самостоятельное доказательство поведения.

Команда `git --literal-pathspecs diff --check f3037ae3dadcabc02f1bf6e0451bda6feff9cb91 43285c3693478d3bc9454f26ce522686fbb3764f` — exit 0.

Поиск на committed head подтвердил отсутствие `GraphInitiatorOperationToken` в `lib`, `test`, `widgetbook/lib`, `widgetbook/test`. Поиск прежних символов избранного в действующих исходниках, тестах, Widgetbook, схеме, глоссарии и README оставил только условия очистки базы в README и отрицательные проверки отсутствия удалённой возможности.

Перед первым Dart MCP зарегистрирован workspace root. `dtd listDtdUris` не обнаружил запущенного приложения; применены предусмотренные CLI-проверки. Ручная проверка работающего интерфейса и hot reload не заявляются.

Логи проверок находятся локально в `/tmp/remove-favorite-intentions-review-check.log` и `/tmp/remove-favorite-intentions-review-codegen-check.log`; они не являются поставляемыми артефактами. Инвентаризация получена штатным discovery helper с wrapper, запускающим OpenSpec исключительно через `mise exec --no-deps -- openspec`.

В этом этапе исходники, тесты и planning-артефакты не исправлялись. Новых задач или принятий риска нет; нерешённых решений и работы для этапа разрешения замечаний не осталось. Отчёт охватывает сохранённый диапазон и не расширяет его до всего изменения.
