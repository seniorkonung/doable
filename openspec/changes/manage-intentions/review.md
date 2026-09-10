# OpenSpec Change Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Feature-specific keep-alive coordinator теперь задаёт lifetime
  принятых операций за пределами auto-dispose routes, не запрещая Back. Однако
  ADR-0005 всё ещё задаёт прежнюю зависимость ViewModels (F5), порядок
  согласования completions с конкурентными snapshot-запросами не определён
  (F6), владелец пользовательского сообщения при остающемся открытым дочернем
  экране не выбран (F7), а для следующей порции каталога отсутствует terminal
  failure state (F8). Принятый риск AR1 сохраняется в прежних границах.
**Validation:** `openspec validate manage-intentions --type change --strict
  --no-interactive` и `openspec schema validate intent-driven --json` успешны.
  Phase 7 ещё не реализована, поэтому runtime- и widget-тесты её поведения в
  рамках этого planning audit не запускались.

## Findings

### F5 · Medium — ADR-0005 сохраняет прежний путь ViewModel → Repository

- **Evidence:** действующий внутри change
  документ `docs/adr/0005-use-bounded-catalog-snapshots.md` прямо закрепляет зависимость
  ViewModels от `IntentionRepository` и локальное согласование command results в
  Catalog ViewModel. `design.md`, решение 3, теперь требует, чтобы editor/details
  ViewModels передавали commands в `IntentionCommandCoordinator`, а Catalog
  ViewModel потребляла его `IntentionCommandCompletion`. ADR-0005 имеет статус
  решения `proposed`, принадлежит этому change и остаётся долговечным источником решения,
  но `adr.md` и задачи не устраняют расхождение.
- **Impact:** implementer может обоснованно последовать ADR и вызвать repository
  прямо из auto-dispose ViewModel, вновь связав lifetime операции с экраном,
  либо последовать design и поставить реализацию в формальное противоречие с
  архитектурным решением. Следующие change также получат две разные схемы
  dependency direction.
- **Required change:** согласовать ADR-0005 с выбранным coordinator-подходом либо
  вернуть design к совместимому с ADR решению. Канонический текст должен явно
  различать query/read path, command path, владельца lifetime принятого `Future`
  и потребителя terminal completions, сохраняя `IntentionRepository` единственной
  storage-neutral seam.

### F6 · Medium — Completion невозможно однозначно согласовать с конкурентным snapshot каталога

- **Evidence:** intention-management spec требует после принятой операции точно
  согласовать текущую загруженную часть и `totalCount`. `design.md`, решение 3,
  независимо применяет асинхронные first/continuation page results и
  тип `IntentionCommandCompletion`; payload содержит только новый `IntentionSaved`
  либо ID в `IntentionDeleted` и не задаёт ordering/watermark относительно
  snapshot-запроса. После Back пользователь уже может сменить scope, filter или
  order до terminal outcome, поэтому прежний summary может отсутствовать в новой
  generation, а page result не сообщает, включает ли его snapshot выполненный
  commit. Задачи 7.5, 7.15–7.17 проверяют устаревшую query generation и delayed
  completion по отдельности, но не их пересечение; требуемая в design
  дедупликация tokens также не имеет ограниченной политики удаления.
- **Impact:** допустимый порядок завершения может повторно добавить удалённую или
  старую строку, потерять только что применённое изменение либо увеличить или
  уменьшить точный count дважды. Особенно неоднозначны удаление и изменение
  membership после смены фильтра, когда целевое намерение находится за текущей
  загруженной границей. Исправление обычным refresh способно нарушить обещание не
  перечитывать предшествующие порции, а бессрочный набор обработанных tokens —
  создать неограниченно растущее process-local состояние.
- **Required change:** определить один ограниченный протокол порядка и
  идемпотентности между page requests и command completions, который даёт
  достаточно pre/post-commit evidence для точного membership/count либо
  безопасно отклоняет и повторяет только затронутый snapshot. Добавить
  controlled-completer проверки completion до и после first/continuation page,
  смены query generation, нескольких последовательных completions и ограниченного
  удаления token bookkeeping.

### F7 · Medium — Один failure может быть повторно показан после успешного retry

- **Evidence:** `design.md`, решение 3, требует от остающейся открытой экранной
  ViewModel показать terminal failure и одновременно заставляет Catalog
  ViewModel создать и удерживать одноразовое сообщение до возвращения каталога.
  Задачи 7.8, 7.10 и 7.13 сохраняют failure и retry на дочернем экране, а 7.15
  создаёт catalog message для каждого failure. Не определено, считается ли
  failure уже представленным, должен ли каталог повторять его и как хранить
  несколько outcomes, если пользователь получил failure, повторил операцию и
  достиг success до закрытия route.
- **Impact:** после успешного retry пользователь может вернуться в каталог и
  получить устаревшее сообщение о неуспехе либо увидеть одну и ту же ошибку
  дважды. Перезапись единственного event, напротив, способна потерять сообщение о
  failure, который завершился уже после ухода с экрана.
- **Required change:** определить единственного presentation-owner или
  типизированное подтверждение потребления для каждого completion и явную
  политику нескольких outcomes, сохраняя обязательное сообщение для failure
  после ухода и не дублируя уже показанный результат. Проверки должны покрыть
  failure при открытом route, failure после Back и failure → retry → success до
  возврата в каталог.
- **Decision needed:** должен ли каталог повторять failure, уже показанный на
  остающемся открытым editor/details, или такой outcome считается там полностью
  представленным?

### F8 · Medium — Следующая порция каталога не имеет non-retryable failure state

- **Evidence:** Метод `IntentionRepository.getCatalogPage` может вернуть
  результаты `validation`, `corruption` или `unexpected` не только для первой страницы. Behavioral spec
  требует сохранить уже загруженные намерения при ошибке следующей порции и
  разрешает retry только там, где он способен восстановить работу. Однако
  При этом `design.md`, решение 3, предоставляет retry для любого failure продолжения, а
  задача 7.6 определяет состояние и verification только для retryable failure;
  7.7 не добавляет fixtures terminal-отказов после уже загруженных страниц.
- **Impact:** corruption или unexpected при чтении продолжения может быть
  потерян, ошибочно превращён в бесконечный retry либо заменить весь каталог
  общим failure state. Пользователь тогда не получит безопасного terminal
  сообщения или потеряет доступ к уже подтверждённому префиксу и count.
- **Required change:** определить presentation state для каждого применимого
  non-retryable результата следующей порции: сохранить подтверждённые items,
  count и неприменённую cursor boundary, показать безопасное различимое
  сообщение без обычного retry и проверить это после одной и нескольких
  загруженных порций. Если внутренний validation outcome должен приводить к
  иному восстановлению query, это поведение также должно быть задано явно и
  проверено.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** действующие specs, design и ADR-0006 считают UTC
  wall-clock timestamps наблюдениями; каталог использует сохранённое значение и
  идентификатор `IntentionId` как tie-breaker без causal clock.
- **Potential impact:** быстрые операции или перевод часов могут дать
  одинаковые либо убывающие timestamps, поэтому выбранный пользователем порядок
  иногда не совпадёт с фактической последовательностью действий.
- **Acceptance rationale:** отдельная revision/logical-clock модель или
  синтетическое продвижение времени несоразмерны вспомогательной сортировке и
  исказили бы наблюдаемое wall-clock значение.
- **Scope and assumptions:** timestamps не используются как revision, causal
  order, средство синхронизации, аудита или разрешения конфликтов.
- **Reopen when:** timestamps получают хронологически значимое
  поведение, появляется синхронизация/разрешение конфликтов либо наблюдается
  существенный пользовательский ущерб от перестановок.
- **Acceptance authority:** явное решение пользователя от 2026-09-03.
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** ADR-0006, соответствующие требования intention-management
  spec и раздел рисков design.

## Review coverage

Широко повторно проверены proposal, обе capability specs, design, ADR manifest,
phase plan, полный Phase 7 task graph, текущий review и schema-defined границы
будущего пакета Phase 8; commitments прослежены от intent и behavioral contract
через decisions к work и verification. Сверены ADR-0001–ADR-0008, корневой
доменный словарь и фактические классы `MainApp`, `LocalDataBootstrap` и
interface `IntentionRepository`, а также commands, sealed results/failures, Android host policy,
сборочная конфигурация и доступные lifecycle-примитивы зафиксированного
Riverpod. Углублённо проверены dependency direction, ownership принятого
выполнения `Future`, auto-dispose и повторное открытие routes, process-local
completion delivery, смена catalog query во время command, page/completion
races, paging/count/cursor reconciliation, initial и continuation failure
presentation, bounded state, privacy, localization, accessibility, delivery и
граница остановки процесса. Завершённые storage implementation details Phase
1–6 повторно не проверялись за пределами фактических seams, от которых зависит
Phase 7. После remediation F4 отдельно сверены общая табличная матрица всех
вариантов `IntentionFailure`, применимые command-specific fixtures, сохранение
формы или подтверждённого snapshot, retry-policy, отсутствие optimistic state и
повторная доступность gate.
