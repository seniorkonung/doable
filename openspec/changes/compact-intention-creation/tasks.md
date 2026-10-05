Пакет охватывает первую фазу [плана](plan.md). Его поведение задают требования [создания намерения](specs/intention-management/spec.md), [тегов](specs/tag-management/spec.md) и [избранного](specs/favorite-intention-management/spec.md); границы записи и потребления результата — решения 6–9 [дизайна](design.md) и применимые записи из [манифеста ADR](adr.md). Подготовка черновика и модальная навигация относятся к последующим фазам.

Пути ниже — оценка по текущему устройству репозитория. Каждая изменяющая поведение задача включает проверку, которая воспроизводит отсутствие требуемой гарантии до изменения и проходит после него. Контрактные проверки потребителя дополняются подключением к настоящему хранилищу в указанных контрольных точках.

## Phase 1: Полное начальное состояние намерения сохраняется одним подтверждённым результатом

- [x] 1.1 Определить типизированный контракт полного начального состояния и различимый отказ отсутствующих выбранных тегов
  - **Acceptance criteria:**
    - `CreateIntention` предоставляет совместимый путь передачи начальных `IntentionReadiness`, `FavoriteMark` и неизменяемого набора `TagId`; минимальные вызовы, включая существующие `const`-вызовы, сохраняют выключенные отметки и пустой набор. Изменение переданной извне коллекции не меняет уже созданную команду, повторные идентификаторы не размножаются.
    - `IntentionCreationTagsMissingFailure` принадлежит категории `validation` и несёт непустой неизменяемый набор отсутствующих идентификаторов; он отличим от ошибки текста, отсутствия намерения и повреждения данных. Существующие обработчики отказов остаются исчерпывающими.
    - Документация контракта рядом с командой и результатом фиксирует единое атомарное создание, один окончательный `IntentionSaved` с фактами назначений на общей ревизии и владение принятой отправкой координатором. Проверка типов и данных команды не выдаётся за доказательство исполнения репозитория, которое входит в 1.2–1.4.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/application/intention_contract_test.dart --reporter expanded`
    - Проверить независимость команды от исходной коллекции, невозможность изменения опубликованного набора и недопустимость пустого набора в новом отказе.
  - **Dependencies:** Нет.
  - **Files likely touched:** `lib/src/intention/application/intention_command.dart`, `lib/src/intention/application/intention_result.dart`, `lib/src/intention/application/intention_catalog.dart`, `test/intention/application/intention_contract_test.dart`.
  - **Estimated scope:** M.

- [x] 1.2 Реализовать единое транзакционное создание намерения с начальной готовностью, избранным и назначениями тегов
  - **Acceptance criteria:**
    - Одна команда через существующий репозиторий создаёт новое активное намерение, все выбранные назначения и отметку избранного в одной транзакции. Правила текста сохраняются, время создания и изменения берётся одним показанием часов; место избранного определяется текущим максимумом полного порядка, включая архивированные намерения. Запись места переиспользует внутренний механизм самостоятельной отметки без обхода её проверки получателя.
    - Внутри транзакции проверяются выбранные теги по идентификаторам и окончательные сохраняемые данные. Отсутствующий тег отклоняет всю команду типизированно, переименование сохраняет идентичность; все потенциально отказные чтения и проверки результата завершаются до подтверждения транзакции.
    - Успех содержит одну `IntentionCatalogCreated` с полным снимком и факты `TagAssignmentChangedChange` для созданных назначений на одной новой ревизии. Публичные команды отметки, готовности и назначения отдельно не вызываются; отказ не публикует успех и не продвигает ревизию.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/data/drift_intention_repository_command_test.dart test/intention/data/drift_intention_favorite_mark_command_test.dart test/graph/data/drift_tag_assignment_test.dart --concurrency=2 --reporter expanded`
    - Через реальный адаптер проверить минимальные данные и сочетания начальных отметок с пустым и непустым набором тегов; сопоставить подтверждённый пакет с повторным чтением графа.
  - **Dependencies:** 1.1.
  - **Files likely touched:** `lib/src/graph/data/drift_personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository_favorite_marks.dart`, `test/intention/data/drift_intention_repository_command_test.dart`, `test/intention/data/drift_intention_favorite_mark_command_test.dart`.
  - **Estimated scope:** M.

- [x] 1.3 Доказать полный откат создания и актуальность его предусловий при конкурирующих операциях
  - **Acceptance criteria:**
    - Отказы после вставки намерения, части назначений, отметки избранного и при чтении окончательного результата откатывают весь новый набор, включая поисковую проекцию. Предыдущий граф, порядок избранного и ревизия сохраняются; независимо созданные теги остаются доступными.
    - Удаление выбранного тега, в том числе с последующим созданием одноимённого, возвращает точные отсутствующие идентификаторы без подмены или пропуска. Некорректные сохранённые данные тега и инфраструктурный отказ сохраняют свои категории и не маскируются отсутствием.
    - Последовательное исполнение создания вместе с удалением тега, отметкой или перестановкой избранного использует состояние на момент транзакции. В обоих порядках завершения сохраняется целый результат и корректное конечное место без двойной записи или промежуточного пакета.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/data/drift_intention_repository_fault_test.dart test/intention/data/drift_intention_repository_command_test.dart test/graph/data/favorite_order_concurrency_test.dart --concurrency=2 --reporter expanded`
    - Применить существующие наблюдатели настроенного соединения для отказов на границах записи и чтения; проверить состояние через публичные чтения и целостность FTS, а не только тип возвращённой ошибки.
  - **Dependencies:** 1.2.
  - **Files likely touched:** `test/intention/data/drift_intention_repository_fault_test.dart`, `test/intention/data/drift_intention_repository_command_test.dart`, `test/graph/data/favorite_order_concurrency_test.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`.
  - **Estimated scope:** M.

- [x] 1.4 Подтвердить готовность атомарной границы создания перед подключением потребителей результата
  - **Acceptance criteria:**
    - Контракт 1.1 подтверждён реальным адаптером: полный успех, типизированные отказы, откат, окончательный пакет и единая ревизия проверены без подмены постоянного хранилища.
    - Существующие минимальное создание, самостоятельная отметка избранного и назначение тегов проходят регрессионные проверки; изменения собираются и проходят анализ.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/application test/intention/data/drift_intention_repository_command_test.dart test/intention/data/drift_intention_repository_fault_test.dart test/intention/data/drift_intention_favorite_mark_command_test.dart test/graph/data/drift_tag_assignment_test.dart test/graph/data/favorite_order_concurrency_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 1.1, 1.2, 1.3.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [x] 1.5 Подтвердить долговечность полного создания после повторного открытия базы и остановки процесса
  - **Acceptance criteria:**
    - Повторное открытие того же файлового хранилища восстанавливает подтверждённое намерение со всеми тегами, готовностью, избранным, местом и согласованными временными метками; результат виден через публичные чтения и поиск.
    - После отказа либо остановки процесса до подтверждения транзакции не остаётся части создаваемого намерения, назначений или места. Остановка после подтверждения сохраняет весь набор; самостоятельные теги и прежний граф сохраняются в обоих случаях.
    - Проверки используют действующие фабрики настроенного соединения и существующий процессный механизм. Новая эпоха репозитория устанавливается после открытия без сохранения ревизии в базе и без изменения схемы.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/data/file_backed_drift_intention_repository_test.dart test/intention/data/file_backed_favorite_mark_durability_test.dart --concurrency=1 --reporter expanded`
    - Подтвердить фактический запуск отдельного процесса и остановку на выбранной границе; отсутствие сигнала готовности не считать успешным испытанием отказа.
  - **Dependencies:** 1.4.
  - **Files likely touched:** `test/intention/data/file_backed_drift_intention_repository_test.dart`, `test/support/graph_operation_process_worker.dart`, `test/support/local_database_harness.dart`.
  - **Estimated scope:** M.

- [x] 1.6 Сделать этап и исход расширенного создания наблюдаемыми без раскрытия данных намерения
  - **Acceptance criteria:**
    - Существующее событие создания получает типизированные этапы проверки, записи и проверки результата; длительность и категория отказа соответствуют фактическому исходу. Ошибка выбранных тегов относится к проверке и категории `validation`.
    - В событии и его сериализованном представлении отсутствуют пользовательский текст, идентификаторы и названия тегов, состав избранного, SQL и путь базы. Начальные назначения и отметки не порождают отдельные события самостоятельных команд.
    - Ошибка диагностического получателя не меняет результат, число записей и ревизию графа; действующие события остальных команд сохраняют свои гарантии.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/shared/diagnostics/diagnostics_sink_test.dart test/intention/data/drift_intention_repository_fault_test.dart --concurrency=2 --reporter expanded`
    - Проверить события настоящего выполнения при успехе и отказах разных этапов, сериализацию с контрольными личными значениями и выполнение с диагностическим получателем, который выбрасывает исключение.
  - **Dependencies:** 1.4.
  - **Files likely touched:** `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `test/shared/diagnostics/diagnostics_sink_test.dart`, `test/intention/data/drift_intention_repository_fault_test.dart`.
  - **Estimated scope:** M.

- [x] 1.7 Сохранить единственную отправку и однократное предъявление результата полного создания независимо от инициатора
  - **Acceptance criteria:**
    - Координатор удерживает одну принятую команду со всем начальным набором до результата; повтор по ключу формы отклоняется, а уход инициатора не отменяет команду и не освобождает блокировку раньше времени.
    - Окончательный пакет публикуется один раз. Создание использует обычную политику подтверждения успеха, а факты готовности, избранного и назначений не порождают отдельных сообщений или повторного применения через результат маршрута.
    - Новый типизированный отказ сохраняется в завершении команды и проходит действующий протокол права предъявления: живая поверхность удерживает своё сообщение, освобождённая передаёт его общей поверхности, поздние callbacks не подтверждают чужое право. Существующие локализованные сообщения сохраняют корректную категорию исхода; исправление набора в черновике относится к фазе 2.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/operation/intention_command_coordinator_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart test/app/intention_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - Дополнить проверки задержанной команды полным начальным набором; проверить реальное выполнение через координатор и общую поверхность после освобождения инициатора, без добавления нижней панели на этой фазе.
  - **Dependencies:** 1.4.
  - **Files likely touched:** `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `test/intention/presentation/operation/intention_command_coordinator_test.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/app/intention_app_lifecycle_test.dart`.
  - **Estimated scope:** M.

- [x] 1.8 Подтвердить долговечность и независимое от экрана завершение полного создания
  - **Acceptance criteria:**
    - Проверки файловой базы, диагностики и времени жизни команды подтверждают один и тот же контракт полного создания. Результат сохраняется после закрытия инициатора, а отказ не оставляет частей записи или потерянного сообщения.
    - Целевые регрессии диагностики, координатора и представления проходят; существующие обработчики команд остаются исчерпывающими, анализ проходит.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/data/file_backed_drift_intention_repository_test.dart test/shared/diagnostics/diagnostics_sink_test.dart test/intention/data/drift_intention_repository_fault_test.dart test/intention/presentation/operation/intention_command_coordinator_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/app/intention_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 1.5, 1.6, 1.7.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [x] 1.9 Согласовать каталог намерений с полным результатом создания без сброса выдачи и повторного добавления
  - **Acceptance criteria:**
    - Каталог определяет принадлежность нового намерения совместному текстовому фильтру, готовности и условиям тегов по окончательному снимку. Неподходящее намерение не появляется в выдаче, подходящее учитывается один раз вместе с точным количеством.
    - Параметры, порядок, загруженная область и позиция прокрутки сохраняются по действующему протоколу. Поздний ответ чтения и пакет, уже отражённый в снимке, не откатывают состояние и не добавляют строку повторно.
    - Составной пакет с фактами назначений применяется как одно изменение ревизии; каталог не ожидает последующих самостоятельных команд для получения тегов или готовности.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart --concurrency=2 --reporter expanded`
    - Через настоящий репозиторий и координатор проверить создание в подходящей и неподходящей выдаче; перестановку ответов дополнительно проверить управляемым контрактным источником.
  - **Dependencies:** 1.4, 1.7.
  - **Files likely touched:** `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart`, `test/intention/presentation/catalog/intention_catalog_tag_filter_integration_test.dart`, `test/intention/presentation/catalog/intention_catalog_tag_filter_revision_protocol_test.dart`, `test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart`.
  - **Estimated scope:** M.

- [x] 1.10 Согласовать Главную с намерением, созданным сразу избранным, в том числе при скрытой вкладке
  - **Acceptance criteria:**
    - Загруженная Главная получает новое активное избранное намерение из результата создания в конце актуального полного порядка, сохраняя взаимный порядок прежних элементов. Создание без отметки не добавляет его в избранное.
    - Согласование работает и на скрытой корневой странице; устаревшее чтение, повторная доставка пакета и обновление во время перестановки не возвращают прежний состав или порядок.
    - Настоящий путь сохранения и согласования использует отметку окончательного снимка без дополнительной команды отметки и без зависимости от сообщения об успехе.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/favorite/presentation/home/home_reconciliation_test.dart test/app/home_favorites_app_flow_test.dart test/app/home_favorites_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - Проверить полное создание через координатор при другом выбранном пункте и возвращение на Главную; исходный порядок должен включать архивированные места.
  - **Dependencies:** 1.4, 1.7.
  - **Files likely touched:** `lib/src/favorite/presentation/home/home_view_model.dart`, `test/favorite/presentation/home/home_reconciliation_test.dart`, `test/favorite/presentation/home/home_test_support.dart`, `test/app/home_favorites_app_flow_test.dart`, `test/app/home_favorites_app_lifecycle_test.dart`.
  - **Estimated scope:** M.

- [x] 1.11 Согласовать навигацию по тегу и чтение назначений с фактами единого создания
  - **Acceptance criteria:**
    - Уже открытая навигация по выбранному тегу отражает подходящее созданное намерение по подтверждённому пакету, сохраняя охват и параметры. Несколько начальных тегов не вызывают повторного добавления или публикации частичного набора.
    - Чтение назначений созданного намерения показывает весь сохранённый набор с актуальными названиями. Более старые чтения не заменяют результат, ошибки чтения сохраняют свои состояния.
    - Существующее назначение и снятие тегов продолжают согласовываться тем же способом; работа общего выбора с черновиком остаётся задачей следующей фазы.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/navigation/tag_navigation_view_model_test.dart test/tag/presentation/assignments/tag_assignments_view_model_test.dart test/graph/presentation/tag_package_catalog_consumers_test.dart --concurrency=2 --reporter expanded`
    - В существующих сценариях интеграции навигации с каталогом проверить полный пакет настоящей команды создания и сопоставить его с чтением назначений.
  - **Dependencies:** 1.4, 1.7.
  - **Files likely touched:** `lib/src/tag/presentation/navigation/tag_navigation_view_model.dart`, `lib/src/tag/presentation/assignments/tag_assignments_view_model.dart`, `test/tag/presentation/navigation/tag_navigation_view_model_test.dart`, `test/tag/presentation/navigation/tag_navigation_catalog_integration_scenarios.dart`, `test/tag/presentation/assignments/tag_assignments_view_model_test.dart`.
  - **Estimated scope:** M.

- [x] 1.12 Подтвердить готовность полного атомарного создания к подключению сессии черновика
  - **Acceptance criteria:**
    - Реальная связка координатора, постоянного хранилища и потребителей подтверждает результат первой фазы: целое начальное состояние либо различимый отказ без частичных записей, долговечность, согласование каталога, Главной и тегов и однократное предъявление исхода.
    - Целевые проверки пакета, полный набор проверок репозитория, сборка и строгая валидация изменения проходят. Производные файлы согласованы с источниками; схема и существующие данные совместимы с предусмотренным дизайном откатом.
    - Прикладной контракт и его гарантии описаны рядом с кодом, проверка качества и критерии готовности репозитория выполнены для этой фазы. Завершение пакета разрешает подготовку задач фазы 2 и не означает завершения или готовности к архивации всего изменения.
  - **Verification:**
    - `mise run check`
    - `mise run codegen-check` — в чистой рабочей копии проверяемого коммита: скрипт требует отсутствия незакоммиченных файлов до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `openspec validate compact-intention-creation --type change --strict --json --no-interactive`
    - Проверить на настоящем хранилище полное создание при одновременно загруженных потребителях, включая скрытую Главную, и отказ без изменения их подтверждённых данных. После изменений Dart проверить доступное запущенное приложение через DTD, перезагрузку и runtime errors; при его отсутствии использовать указанные проверки CLI.
  - **Dependencies:** 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11.
  - **Files likely touched:** Нет — итоговая контрольная точка.
  - **Estimated scope:** XS.

- [x] 1.13 Доказать в сквозной контрольной точке первой фазы неизменность ревизии при отклонённом создании и отказ хранилища только после всех записей создания
  - **Acceptance criteria:**
    - В каждом сценарии отказа `full_intention_creation_checkpoint_test.dart` свежее публичное чтение модуля графа после отклонённого создания сообщает ту же ревизию, что подтверждённые снимки потребителей до него. Продвижение ревизии при откате приводит к падению сценария.
    - Сценарий недоступности хранилища срабатывает только внутри ещё не подтверждённой транзакции создания после записи строки намерения, назначения каждого выбранного тега и места избранного. Иной состав или порядок записей к моменту отказа приводит к падению сценария, а не к молчаливому отказу после части записей.
    - Комментарии теста и запись готовности `docs/verification/compact-intention-creation-phase-one-readiness.md` утверждают только фактически проверяемое. Итоговые проверки первой фазы повторены на коммите с усилением, их результаты отражены в записи готовности; продуктовый код не меняется.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/full_intention_creation_checkpoint_test.dart --reporter expanded`
    - Подтвердить чувствительность временными незафиксированными искажениями кода: продвижение ревизии при откате создания и запись места избранного раньше назначений приводят к падению соответствующих сценариев.
    - `mise run check`
    - `mise run codegen-check` — в чистой рабочей копии проверяемого коммита: скрипт требует отсутствия незакоммиченных файлов до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
  - **Dependencies:** 1.12.
  - **Files likely touched:** `test/app/full_intention_creation_checkpoint_test.dart`, `docs/verification/compact-intention-creation-phase-one-readiness.md`.
  - **Estimated scope:** S.

- [x] 1.14 Доказать в сквозной контрольной точке первой фазы, что отказ хранилища срабатывает только после записи всего заданного командой начального состояния создаваемого намерения
  - **Acceptance criteria:**
    - В сценарии недоступности хранилища `full_intention_creation_checkpoint_test.dart` в момент отказа внутри ещё не подтверждённой транзакции проверено всё начальное состояние, заданное командой создания: название и описание, готовность к действию, активное состояние, назначение каждого выбранного тега и место в ручном порядке избранного. Учитывается каждая запись после взвода отказа, а не только вставки. Запись создания, ещё не выполненная к моменту отказа, в том числе обновлением, удалением, пакетной или произвольной операцией, приводит к падению сценария.
    - Название сценария, комментарии теста и запись готовности `docs/verification/compact-intention-creation-phase-one-readiness.md` утверждают только фактически проверяемое. Проверки ревизии, сохранённых данных и подтверждённых снимков потребителей остальных сценариев контрольной точки не ослабляются; продуктовый код не меняется.
    - Итоговые проверки первой фазы повторены на коммите с усилением; их результаты и подтверждённая чувствительность отражены в записи готовности.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/full_intention_creation_checkpoint_test.dart --reporter expanded`
    - Подтвердить чувствительность временными незафиксированными искажениями кода: строка намерения вставляется с выключенной готовностью к действию, а готовность записывается отдельным обновлением после места избранного, — оба сценария недоступности хранилища падают. Искажения задачи 1.13 — продвижение ревизии при откате создания и запись места избранного раньше назначений — по-прежнему приводят к падению соответствующих сценариев.
    - `mise run check`
    - `mise run codegen-check` — в чистой рабочей копии проверяемого коммита: скрипт требует отсутствия незакоммиченных файлов до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
  - **Dependencies:** 1.13.
  - **Files likely touched:** `test/app/full_intention_creation_checkpoint_test.dart`, `docs/verification/compact-intention-creation-phase-one-readiness.md`.
  - **Estimated scope:** S.

- [x] 1.15 Учитывать в точке отказа сквозной контрольной точки первой фазы записи с возвратом строк, которые выполняются через путь чтения
  - **Acceptance criteria:**
    - В сценарии недоступности хранилища `full_intention_creation_checkpoint_test.dart` в точке отказа учитывается каждая запись на соединении приложения после взвода отказа, включая записи с возвратом строк (`RETURNING`), которые drift выполняет через путь чтения, а перехватчик соединения помечает как чтение. Пропускаются только операции, не изменяющие данные. Лишняя, отсутствующая или переставленная запись любой формы до места избранного приводит к падению сценария.
    - Название сценария, комментарии теста, документация наблюдателя отказа и запись готовности `docs/verification/compact-intention-creation-phase-one-readiness.md` утверждают только фактически проверяемое. Проверки начального состояния в точке отказа, ревизии, сохранённых данных и подтверждённых снимков потребителей не ослабляются; продуктовый код, включая перехватчик соединения в `lib/src/data/local/database_connection.dart`, не меняется.
    - Итоговые проверки первой фазы повторены на коммите с усилением; их результаты и подтверждённая чувствительность отражены в записи готовности.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/full_intention_creation_checkpoint_test.dart --reporter expanded`
    - Подтвердить чувствительность временными незафиксированными искажениями кода: строка намерения вставляется с выключенной готовностью к действию, а готовность записывается обновлением с возвратом строк (`writeReturning`) между назначениями и местом избранного, — оба сценария недоступности хранилища падают, хотя версия теста до этой задачи пропускает искажение. Искажения задач 1.13 и 1.14 по-прежнему приводят к падению соответствующих сценариев.
    - `mise run check`
    - `mise run codegen-check` — в чистой рабочей копии проверяемого коммита: скрипт требует отсутствия незакоммиченных файлов до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
  - **Dependencies:** 1.14.
  - **Files likely touched:** `test/app/full_intention_creation_checkpoint_test.dart`, `docs/verification/compact-intention-creation-phase-one-readiness.md`.
  - **Estimated scope:** S.

Пакет второй фазы следует решениям 1, 4, 5 и 8–9 [дизайна](design.md), требованиям [создания и сессии намерения](specs/intention-management/spec.md), [общего выбора тегов](specs/tag-management/spec.md) и [начального избранного](specs/favorite-intention-management/spec.md), а также [ADR-0017](../../../docs/adr/0017-manage-modal-creation-sessions-in-root-stack.md) и [ADR-0018](../../../docs/adr/0018-separate-tag-selection-context-from-persistence.md). Он использует подтверждённую границу сохранения фазы 1. Геометрия нижней панели и подключение решения сессии к её жестам и навигации остаются в фазе 3 по [плану](plan.md) и [спецификации навигации](specs/app-navigation/spec.md).

Пути задач — оценка по изученным модулям; новые файлы явно отмечены или ограничены существующим модулем ответственности. Производные Riverpod-файлы, маршруты и локализации обновляются вместе со своими источниками. Проверки потребителей на управляемых зависимостях дополняются реальной сборкой в 2.11 и постоянным хранилищем в 2.13. Задачи выполняются в порядке файла; зависимости обозначают обязательные предпосылки, а не возможность пропустить предыдущие задачи.

## Phase 2: Черновик подготавливает полное намерение через общий выбор тегов

- [x] 2.1 Сделать полный черновик создания самостоятельным состоянием сессии и предоставить узкий контракт его набора тегов
  - **Acceptance criteria:**
    - Сессия по собственному `IntentionCreationFormKey` хранит сырые название и описание, неизменяемый набор `TagId`, `IntentionReadiness` и `FavoriteMark`; начальные значения пусты или выключены. Новый экземпляр не наследует прежний черновик или фильтры каталога и не имеет `IntentionId`.
    - Изменённость определяется сравнением всех пяти полей с начальными значениями, включая полностью пробельные строки; возврат к исходным значениям снимает её. Поиск, кандидат, фокус и будущий размер панели не входят в предметные данные.
    - Контракт для общего выбора предоставляет наблюдаемый набор и явное локальное добавление подтверждённого тега с последним известным названием; снятие и обе отметки изменяют только черновик. Повторное добавление идемпотентно, готовность не выводится из других полей и включается только по явному подтверждению критериев действия. Закрытая сессия отвергает изменения; постоянные команды и детали хранилища не входят в этот контракт.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart --reporter expanded`
    - Проверить каждое поле отдельно, пробельный ввод, возврат к начальному состоянию, два независимых открытия и неизменяемость опубликованного набора; ни одно локальное действие не отправляет команду графа.
  - **Dependencies:** 1.15.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`; узкий контракт набора — рядом с состоянием сессии в том же модуле.
  - **Estimated scope:** M.

- [x] 2.2 Отправлять неизменяемый снимок всего черновика одной командой и блокировать его изменение до результата
  - **Acceptance criteria:**
    - `submit` передаёт координатору одну `CreateIntention` со всеми пятью полями по ключу сессии, используя готовый путь фазы 1. Принятая отправка имеет собственный токен; повтор не принимается и не ставится в очередь.
    - Все методы изменения текста, набора и отметок, включая запоздалые callbacks общего выбора, отвергаются во время отправки. Наблюдаемая проекция названий может обновляться, но состав принятой команды остаётся неизменным.
    - Успех публикует событие завершения своей сессии один раз; данные согласуются только через координатор. Освобождение инициатора не отменяет принятую операцию и не освобождает её блокировку; минимальное создание существующей формой продолжает работать.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/intention/presentation/operation/intention_command_coordinator_test.dart --concurrency=2 --reporter expanded`
    - На задержанном выполнении вызвать все методы правки и повторную отправку, затем сравнить полный состав единственной команды с исходным черновиком; проверить успех и завершение после освобождения инициатора.
  - **Dependencies:** 2.1.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `lib/src/intention/presentation/editor/intention_editor_state.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`, `test/intention/presentation/operation/intention_command_coordinator_test.dart`.
  - **Estimated scope:** M.

- [x] 2.3 Сохранять полный черновик при отказе и разрешать исправление или повтор только по его типизированной причине
  - **Acceptance criteria:**
    - Любой отказ оставляет сырые строки, выбранные идентификаторы и обе отметки без нормализации или сброса. Ошибка текста снимается исправлением соответствующего поля; `IntentionCreationTagsMissingFailure` сохраняет точные отсутствующие идентификаторы и разрешает новую проверку после явного изменения набора, без пропуска или замены одноимённым тегом.
    - Доказанно устранимая `unavailable` предоставляет явную повторную отправку с новым токеном. Остальные `conflict`, `corruption` и `unexpected` не получают обычного повтора; нерелевантная правка, обновление названия тега или повторное добавление уже включённого тега не снимают блокирующую причину.
    - Состояние ошибки предоставляет её тип и действующее право предъявления существующему `OperationFailurePresentation`; ViewModel не подтверждает видимость сообщения и не вводит отдельный presenter. Существующая форма сохраняет свои проверки ошибок полей, а данные для будущего отображения отсутствующих тегов различимы.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/graph/presentation/operation_failure_presentation_test.dart --concurrency=2 --reporter expanded`
    - Проверить матрицу «категория отказа × исправляемое поле», весь сохранённый черновик и число отправок; отдельно проверить отсутствие автоматической отправки после исправления и новый токен допустимого повтора.
  - **Dependencies:** 2.2.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`.
  - **Estimated scope:** M.

- [x] 2.4 Подтвердить совместные гарантии локального черновика, единственной отправки и восстановления после отказов
  - **Acceptance criteria:**
    - Проверки 2.1–2.3 подтверждают отсутствие команд при подготовке, неизменность принятого снимка и сохранение всех данных после каждого отказа. Разные сессии не обмениваются состоянием.
    - Существующее минимальное создание, блокировка координатора и предъявление ошибок проходят регрессии; анализ проходит. Контракт набора пригоден для общего выбора без знания устройства записи.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/intention/presentation/operation/intention_command_coordinator_test.dart test/graph/presentation/operation_failure_presentation_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 2.1, 2.2, 2.3.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [x] 2.5 Поддерживать актуальную проекцию выбранных тегов без изменения их идентичностей и состава черновика
  - **Acceptance criteria:**
    - Для каждого выбранного `TagId` сессия использует существующий `watchTag`; последнее подтверждённое название из выбора доступно сразу. Переименование обновляет только проекцию, а подтверждённое отсутствие сохраняет идентификатор и последнее имя в различимом недоступном состоянии до явного снятия.
    - Загрузка и типизированный отказ чтения отличаются от удаления. Только устранимый отказ предлагает повтор наблюдения; окончание потока сохраняет установленную причину, необъяснённое окончание даёт неизвестный отказ. Ошибка проекции не заменяет транзакционную проверку при сохранении.
    - Ревизия и поколение наблюдения не позволяют старому ответу отменить новое название, восстановить снятый тег или изменить повторно добавленный тег и другую сессию. Снятие и завершение сессии освобождают соответствующие подписки; наблюдения не отправляют команды графа.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart --reporter expanded`
    - Проверить переименование, удаление с одноимённым новым тегом, отказ и восстановление чтения, поздние ответы после снятия и повторного добавления, завершение потоков и освобождение подписок управляемым источником контракта `watchTag`.
  - **Dependencies:** 2.4.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`; при выделении владельца наблюдений — отдельный файл в этом же модуле.
  - **Estimated scope:** M.

- [x] 2.6 Разделить типизированный контекст общего выбора и режим чтения, сохранив постоянное назначение существующему намерению
  - **Acceptance criteria:**
    - Общий выбор получает закрытые варианты просмотра, назначения существующему намерению и добавления в черновик с явными зависимостями. Контекст черновика читает `TagCatalogBrowseMode` и использует контракт набора из 2.1; существующий получатель продолжает использовать `TagCatalogSelectionMode`. Сессионные данные и фиктивный `IntentionId` не добавляются в репозиторий.
    - Контракт явного действия различает локальное добавление и постоянную команду, включая недоступность при закрытой или отправленной сессии. Адаптер постоянного назначения сохраняет проверки пары и существования, актуальность кандидата, блокировки координатора и права предъявления; неизвестный статус пары не разрешает запись.
    - Общие список, выбор кандидата и наблюдение его идентичности остаются едиными. Существующие вызывающие стороны компилируются и сохраняют поведение на каждом шаге переноса; общий компонент не получает весь объект приложения и не решает, когда создавать намерение.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_view_model_test.dart test/tag/presentation/catalog/tag_catalog_snapshot_selection_test.dart test/tag/presentation/catalog/tag_catalog_selection_stability_test.dart test/tag/presentation/catalog/tag_catalog_page_test.dart --concurrency=2 --reporter expanded`
    - Проверить оба адаптера через предоставляемый ими контракт: постоянный путь принимает `AssignTag`, локальный меняет только наблюдаемый набор; чтение черновика не запрашивает статус назначения несуществующему получателю.
  - **Dependencies:** 2.4.
  - **Files likely touched:** `lib/src/tag/presentation/catalog/tag_catalog_state.dart`, `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart`, `lib/src/tag/presentation/catalog/tag_catalog_view.dart`, `test/tag/presentation/catalog/tag_catalog_view_model_test.dart`, `test/tag/presentation/catalog/tag_catalog_page_test.dart`; типизированный контекст и адаптеры — в этом же модуле, имена уточняются при реализации.
  - **Estimated scope:** M.

- [x] 2.7 Добавлять несколько тегов в черновик через общий компонент с понятными состояниями и доступным явным действием
  - **Acceptance criteria:**
    - Тот же `TagCatalogView` показывает включённые и доступные теги. Нажатие строки меняет только кандидата; закреплённое действие «Добавить» меняет набор явно, повторное включение недоступно. Несколько тегов добавляются в одном открытии без автоматического закрытия, записи назначений и перечитывания каталога ради локального изменения.
    - Обновление набора сразу меняет признаки строк, сохраняя идентичность открытия, поиск, строки, геометрию и прокрутку. Удалённый или неподтверждённый кандидат, закрытая сессия и выполняющаяся отправка не разрешают добавление; уже включённый отсутствующий тег остаётся в сессии.
    - Русские и английские подписи и семантика различают добавление в черновик и сохранённое назначение; состояние понятно без одного цвета. Действие и выбранный кандидат доступны с экранным диктором, клавиатурой и увеличенным текстом; локальные правки не порождают сообщения или диагностические события постоянного назначения.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_page_test.dart test/tag/presentation/catalog/tag_catalog_selection_stability_test.dart test/tag/presentation/tag_accessibility_test.dart --concurrency=2 --reporter expanded`
    - Проверить общий компонент в обоих контекстах, семантику на `ru` и `en`, быстрые повторные нажатия и число чтений и команд. Производные локализации обновить штатной генерацией вместе с исходными ARB.
  - **Dependencies:** 2.5, 2.6.
  - **Files likely touched:** `lib/src/tag/presentation/catalog/tag_catalog_view.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `test/tag/presentation/catalog/tag_catalog_page_test.dart`, `test/tag/presentation/tag_accessibility_test.dart`; производные файлы `lib/l10n/app_localizations*.dart`.
  - **Estimated scope:** M.

- [x] 2.8 Подтвердить общий выбор для черновика без регрессий существующего назначения тегов
  - **Acceptance criteria:**
    - Совместные проверки проекции и общего компонента подтверждают различие локального включения и постоянного назначения, отсутствие потери выбранных идентичностей и единственный явный эффект действия.
    - Существующие выбор кандидата, проверка пары, поиск, стабильность списка и доступность проходят регрессии; локальное изменение набора не запускает команду, перечитывание каталога или сброс открытия.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/tag/presentation/catalog test/tag/presentation/tag_accessibility_test.dart test/app/tag_assignment_app_flow_test.dart test/app/tag_assignment_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 2.5, 2.6, 2.7.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [x] 2.9 Сохранять поиск и набор черновика в пределах открытия общего выбора при переходах в редактор тегов
  - **Acceptance criteria:**
    - Каждое открытие выбора для конкретной сессии имеет собственный `TagCatalogOpening`, кандидат и поиск. Обновление набора и возврат из редактора сохраняют их; закрытие и новое открытие либо смена сессии сбрасывают поиск. Два одновременно открытых выбора не разделяют своё состояние.
    - Поиск использует существующие Unicode-проверку, полный case folding, последний корректный фильтр и пустые состояния. Изменение, очистка и отсутствие совпадений не меняют набор; скрытый кандидат остаётся понятен у явного действия и не подмешивается в совпадения. Отказ чтения с допустимым повтором сохраняет сырой поисковый ввод.
    - «+» вызывает существующий редактор: успешный `CreateTag` сохраняет самостоятельный тег и может выбрать кандидата, но не включает его в черновик; отмена не создаёт тег и не меняет набор. Поздний возврат редактора прежнего открытия не меняет другое открытие; локальные правки не сбрасывают защиту этих callbacks.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_selection_search_test.dart test/tag/presentation/catalog/tag_catalog_search_page_test.dart test/tag/presentation/catalog/tag_catalog_search_read_cost_widget_test.dart test/tag/presentation/editor/tag_editor_page_test.dart --concurrency=2 --reporter expanded`
    - В контексте черновика проверить корректный и некорректный поиск, скрытый выбор, возврат после сохранения и отмены редактора, сбой чтения, повторное открытие и два независимых открытия; сравнить набор до и после каждого перехода.
  - **Dependencies:** 2.8.
  - **Files likely touched:** `lib/src/tag/presentation/catalog/tag_catalog_view.dart`, `lib/src/tag/presentation/catalog/tag_catalog_view_model.dart`, `test/tag/presentation/catalog/tag_catalog_selection_search_test.dart`, `test/tag/presentation/catalog/tag_catalog_search_page_test.dart`, `test/tag/presentation/catalog/tag_catalog_search_read_cost_widget_test.dart`.
  - **Estimated scope:** M.

- [x] 2.10 Определять завершение сессии через единое решение о закрытии с защитой от запоздалых подтверждений
  - **Acceptance criteria:**
    - Сессия предоставляет типизированный результат запроса закрытия: неизменённую можно завершить сразу, изменённая требует одного подтверждения. Продолжение сохраняет все данные, подтверждённый сброс до отправки не создаёт намерение; во время отправки решение явно сообщает, что сохранение продолжится. Переход в выбор или редактор и возврат не завершают сессию.
    - Подтверждение связано с ключом сессии и актуальным состоянием отправки. Успех при ожидающем подтверждении завершает только свою сессию и делает её прежний callback недействительным; повторный запрос не создаёт второе подтверждение. После сброса новое открытие пусто и не получает данные или событие старой команды.
    - Завершение освобождает наблюдения и право непредъявленной ошибки по существующему протоколу, не отменяя координатор и не подтверждая сообщение во ViewModel. Временное перекрытие живого renderer сохраняет его право; окончательное удаление до предъявления передаёт его общей поверхности. Реальные жесты, диалог и навигационное закрытие панели подключаются в фазе 3.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/graph/presentation/operation_failure_presentation_test.dart test/intention/presentation/operation/intention_command_coordinator_test.dart --concurrency=2 --reporter expanded`
    - Проверить закрытие при каждом изменённом поле, продолжение, сброс, отправку во время ожидания подтверждения, успех и отказ при подтверждении, освобождение и новое открытие. В управляемом renderer проверить удержание и передачу конкретного права, не имитируя успех вызовом подтверждения из ViewModel.
  - **Dependencies:** 2.4, 2.5.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`, `test/graph/presentation/operation_failure_presentation_test.dart`.
  - **Estimated scope:** M.

- [x] 2.11 Подключить контекст черновика к существующей странице выбора тегов и проверить сборку с настоящим редактором
  - **Acceptance criteria:**
    - Существующая `TagCatalogPage` принимает типизированный контекст и передаёт явные зависимости общему компоненту; вызывающие стороны просмотра и назначения сохраняют прежнюю семантику. Нет второй страницы выбора, глобального черновика, нового режима репозитория или отдельного навигатора.
    - Связка сессии, общего выбора и существующего `TagEditorRoute` проверяется через настоящее создание и отмену тега: возврат сохраняет тот же черновик и поиск, а закрытие только выбора сохраняет владельца сессии. Окончательное завершение делает переданный контекст недоступным для дальнейшего изменения.
    - Маршрут выбора и его производные аргументы согласованы штатной генерацией. Форма создания ещё не переводится в нижнюю панель: подключение её маршрута, кнопок и реальных способов ухода остаётся фазе 3; сборка фазы 2 проверяет готовые компоненты без второго механизма сохранения.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/tag/presentation/catalog/tag_catalog_page_test.dart test/tag/presentation/editor/tag_editor_page_test.dart test/app/tag_app_flow_test.dart test/app/tag_assignment_app_flow_test.dart --concurrency=2 --reporter expanded`
    - Через существующий маршрутизатор открыть общий выбор с контекстом живой сессии, сохранить и отменить тег, вернуться и повторно открыть выбор; проверить прежние места вызова каталога и назначения. Сессию в проверке удерживает владелец, пока открыты дочерние страницы.
  - **Dependencies:** 2.9, 2.10.
  - **Files likely touched:** `lib/src/tag/presentation/catalog/tag_catalog_page.dart`, `lib/src/intention/presentation/catalog/intention_catalog_page.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `test/tag/presentation/catalog/tag_catalog_page_test.dart`, `test/app/tag_app_flow_test.dart`; производный `lib/src/app/routing/app_router.gr.dart`.
  - **Estimated scope:** M.

- [x] 2.12 Подтвердить независимые жизненные циклы черновика, открытия выбора и самостоятельного редактора тега
  - **Acceptance criteria:**
    - Поиск и редактор не теряют ввод сессии, разные открытия не смешиваются, а решение о закрытии принадлежит сессии. Успех, отказ и запоздалое подтверждение не меняют новое открытие.
    - Общий выбор собран с существующими маршрутами тегов, прежнее назначение работает; локализации, анализ и целевые проверки проходят. Гарантии модальной геометрии и реальных способов закрытия ещё не объявляются доказанными.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/tag/presentation/catalog test/tag/presentation/editor test/app/tag_app_flow_test.dart test/app/tag_assignment_app_flow_test.dart test/app/tag_assignment_app_lifecycle_test.dart test/graph/presentation/operation_failure_presentation_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 2.9, 2.10, 2.11.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [x] 2.13 Доказать совместную работу сессии и общего выбора на настоящем хранилище до отправки, при успехе и при отказе
  - **Acceptance criteria:**
    - Связка настоящих сессии, `TagCatalogView`, координатора и Drift-адаптера подтверждает подготовку всех пяти полей без создания намерения, назначений или избранного и без событий постоянных команд локальных правок. Отдельно созданный через редактор тег сохраняется сразу, переживает сброс и отказ создания; его явное включение до отправки ничего не назначает.
    - Отправка подготовленного набора даёт один полный результат через путь фазы 1. Переименование сохраняет идентичность; удаление выбранного тега, в том числе с одноимённой заменой, отклоняет весь набор. После явного исправления возможна новая проверка; при отказе записи сохраняются черновик и прежний граф, без частичных данных или продвижения ревизии.
    - Задержанная отправка после завершения сессии заканчивается один раз и предъявляет результат по общему протоколу; новое открытие остаётся независимым. Наблюдения выбранных тегов освобождаются, диагностика не раскрывает тексты и идентификаторы. Проверка использует реальное соединение и публичные чтения, а управляемые отказы — существующие hooks локального хранилища.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/intention_creation_draft_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/app/tag_assignment_app_flow_test.dart --concurrency=1 --reporter expanded`
    - Добавить `test/app/intention_creation_draft_integration_test.dart` как проверку компонентов фазы 2 по образцу существующей контрольной точки. Наблюдать команды, фактический граф, ревизию и предъявление результата; не заменять этот путь заранее подготовленным `CreateIntention` в обход сессии и общего выбора.
  - **Dependencies:** 2.12.
  - **Files likely touched:** `test/app/intention_creation_draft_integration_test.dart` — новый файл в изученном `test/app/`; при необходимости `test/support/local_database_harness.dart`, `test/support/in_memory_diagnostics_sink.dart`.
  - **Estimated scope:** M.

- [x] 2.14 Подтвердить готовность полного черновика и общего выбора к подключению управляемой модальной панели
  - **Acceptance criteria:**
    - Критерий готовности фазы 2 доказан связкой с настоящим хранилищем: ввод сохраняется, до отправки нет записей намерения, изменение выбранных тегов и отказы обработаны, самостоятельные теги живут независимо. Существующее назначение тегов сохраняет проверки и однократное предъявление.
    - Контракты сессии и контекстов выбора документированы рядом с кодом, генерация согласована с источниками; целевые и общие проверки, сборка и строгая валидация изменения проходят. Завершение этой фазы не означает завершения всего изменения.
    - Сессия предоставляет данные, отправку, исправление отказа и решение о закрытии, необходимые панели, без дополнительной записи или глобального черновика. Оценка готовности не включает ещё не реализованные геометрию панели, жесты и её маршрут из фазы 3.
  - **Verification:**
    - `mise run check`
    - `mise run codegen-check` — после коммита в чистой рабочей копии: штатный скрипт требует чистоты до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
    - После изменений Dart проверить доступное запущенное приложение через DTD, горячую перезагрузку или перезапуск и runtime errors; при его отсутствии использовать указанные проверки CLI. Сопоставить результаты 2.4, 2.8, 2.12 и 2.13 с `Ready to advance` фазы 2.
  - **Dependencies:** 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13.
  - **Files likely touched:** Нет — итоговая контрольная точка.
  - **Estimated scope:** XS.

- [x] 2.15 Передавать общей поверхности неподтверждённое право ошибки создания, полученное сессией, при её завершении или снятии отказа независимо от того, получил ли его renderer
  - **Acceptance criteria:**
    - Сессия сама учитывает право предъявления ошибки, выданное ей координатором, пока оно не подтверждено. При окончательном освобождении сессии, закрытии по запросу и переходе в состояние, которое больше не публикует это право (снятие отказа правкой, новая отправка), неподтверждённое право ровно один раз переходит общей поверхности по существующему протоколу координатора, даже если ни один renderer его не получал. Уже подтверждённое или освобождённое renderer право повторно не предъявляется; принятая отправка не отменяется, а ViewModel не подтверждает сообщение сама.
    - Временное перекрытие живого хоста непрозрачным выбором или редактором тега оставляет право форме: после возвращения ошибку предъявляет форма, а общая поверхность её не показывает. Гарантии 2.3 и 2.10 сохраняются.
    - Документация сессии и её состояния рядом с кодом называет фактического владельца права на каждом переходе; описания, по которым право остаётся только у renderer, устранены.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_view_model_test.dart test/intention/presentation/editor/intention_editor_page_test.dart test/graph/presentation/operation_failure_presentation_test.dart --concurrency=2 --reporter expanded`
    - В виджетном хосте с настоящими `OperationFailurePresentation`, координатором и регистрацией общей поверхности отправка завершается отказом, пока хост сессии закрыт непрозрачным маршрутом выбора или редактора тега (не прозрачным диалогом). После возвращения форма предъявляет ошибку один раз, общая поверхность её не показывает. Если хост удаляется без нового построения (`popUntil` или сброс стека), общая поверхность предъявляет ошибку ровно один раз и запись координатора не остаётся. Передачу права не имитировать ручным `releaseInitiatorClaim`.
    - В проверках ViewModel без renderer освобождение сессии, подтверждённое закрытие и снятие отказа правкой передают право общей поверхности ровно один раз; право, подтверждённое renderer до этого, повторно не предъявляется.
    - Подтвердить чувствительность временным незафиксированным искажением кода: без освобождения права сессией сценарий удаления хоста без возвращения падает.
  - **Dependencies:** 2.10, 2.14.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `lib/src/intention/presentation/editor/intention_editor_state.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`, `test/graph/presentation/operation_failure_presentation_test.dart`; виджетный хост сессии — в одном из этих тестов или в `test/intention/presentation/editor/intention_editor_page_test.dart`.
  - **Estimated scope:** M.

- [x] 2.16 Повторно подтвердить готовность полного черновика и общего выбора к подключению управляемой модальной панели после исправления передачи права ошибки
  - **Acceptance criteria:**
    - `Ready to advance` фазы 2 подтверждён на коммите с исправлением 2.15. Результаты 2.4, 2.8, 2.12, 2.13 и новые проверки 2.15 проходят; отказ создания предъявляется ровно одним владельцем при возвращении на форму, подтверждённом закрытии и удалении хоста без возвращения.
    - Генерация согласована с источниками; общие проверки, сборка и строгая валидация изменения проходят. Оценка готовности не включает ещё не реализованные геометрию панели, жесты и её маршрут из фазы 3.
  - **Verification:**
    - `mise run check`
    - `mise run codegen-check` — после коммита в чистой рабочей копии: штатный скрипт требует чистоты до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
    - После изменений Dart проверить доступное запущенное приложение через DTD, горячую перезагрузку или перезапуск и runtime errors; при его отсутствии использовать указанные проверки CLI.
  - **Dependencies:** 2.15.
  - **Files likely touched:** Нет — итоговая контрольная точка.
  - **Estimated scope:** XS.

Пакет третьей фазы завершает пользовательский сценарий по [плану](plan.md): использует готовые контракты сессии и атомарного сохранения фаз 1–2 и подключает их к управляемой модальной панели. Требуемое поведение задают спецификации [намерений](specs/intention-management/spec.md), [навигации](specs/app-navigation/spec.md), [тегов](specs/tag-management/spec.md) и [избранного](specs/favorite-intention-management/spec.md); границы — решения 1–9 [дизайна](design.md), [ADR-0017](../../../docs/adr/0017-manage-modal-creation-sessions-in-root-stack.md), [ADR-0018](../../../docs/adr/0018-separate-tag-selection-context-from-persistence.md) и действующий протокол [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md).

Задачи выполняются строго в порядке файла; зависимости обозначают обязательные предпосылки. Пути ниже оценочные, новые файлы отмечены явно. Появляющиеся элементы сразу получают локализацию и доступность; производные маршруты, Riverpod-файлы и локализации обновляются штатной генерацией вместе с источниками. Каждая изменяющая поведение задача включает чувствительную проверку до и после изменения; реальные соединения проверяются в сквозных задачах 3.13–3.14. Контрольные точки подтверждают накопленный результат, а не заменяют проверки отдельных задач.

## Phase 3: Быстрое создание полностью доступно в компактной нижней панели

- [x] 3.1 Подключить существующий хост создания к единому решению сессии о закрытии с подтверждением потери черновика
  - **Acceptance criteria:**
    - Хост использует готовые `requestClose` и `resolveClose` и исчерпывающе обрабатывает их типизированные исходы. Кнопка закрытия, системное «назад» и программный запрос ухода обращаются к сессии до удаления маршрута; успех и уже подтверждённое завершение закрывают только принадлежащий ей маршрут. Прямой безусловный `maybePop` не обходит проверку изменённости.
    - Один локализованный диалог предлагает продолжить ввод или сбросить черновик; при принятой отправке объясняет продолжение сохранения. Продолжение сохраняет сырые строки и остальные данные; пустой или возвращённый к исходным значениям черновик закрывается сразу. Закрытие диалога без выбора сброса не теряет данные.
    - Диалог и callbacks связаны с конкретным подтверждением и ключом сессии. Успех при открытом диалоге закрывает свою форму и подтверждение; смена состояния отправки делает прежний ответ недействительным. Повторный запрос не создаёт второй диалог, запоздалый ответ не закрывает другой маршрут или новое открытие.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_page_test.dart test/app/intention_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - Проверить настоящий диалог и back-навигацию до отправки, при задержанном успехе и отказе; изменять по отдельности текст, в том числе только пробелы, набор и отметки. Проверить продолжение, сброс, новое открытие и устаревший ответ, не подменяя UI вызовом `resolveClose` из теста.
  - **Dependencies:** 2.16.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/app/intention_app_lifecycle_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.2 Открывать компактную модальную панель из кнопки «+» в общем корневом стеке с сохранением исходного каталога
  - **Acceptance criteria:**
    - `IntentionEditorRoute` становится управляемым `CustomRoute` с `opaque: false`, сохранением состояния и отключённым автоматическим закрытием по фону по решению 2 дизайна. Содержимое существующего хоста заменяет полноэкранную форму: собственный модальный фон вызывает процедуру 3.1, каталог и основная навигация исключены из взаимодействия, фокуса и доступной семантики.
    - Новое открытие имеет новый ключ и пустой черновик, фокус в названии, компактное однострочное начало описания и видимый участок каталога над панелью. Высота зависит от содержимого и доступной области с учётом безопасных отступов и клавиатуры, без фиксированного процента; основное действие отправки закреплено отдельно от прокручиваемых полей.
    - Кнопка каталога показывает только «+» с локализованными подсказкой и доступным названием. Закрытие возвращает тот же каталог с выбранным пунктом, параметрами и прокруткой; результат маршрута не обновляет данные вторым каналом. Остальные маршруты сохраняют полноэкранное открытие над оболочкой, отдельный навигатор не появляется.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_page_test.dart test/intention/presentation/catalog/intention_catalog_page_test.dart test/app/routing/app_router_test.dart test/app/navigation/app_shell_pages_above_test.dart --concurrency=2 --reporter expanded`
    - Из настоящего каталога открыть маршрут кнопкой, измерить панель и видимую область каталога при коротком вводе, проверить фокус и невозможность взаимодействовать с фоном и пунктами навигации. Реальное нажатие вне изменённой панели должно открыть подтверждение 3.1; обновить прежние ожидания полноэкранного создания.
  - **Dependencies:** 3.1.
  - **Files likely touched:** `lib/src/app/routing/app_router.dart`, `lib/src/intention/presentation/editor/intention_editor_page.dart`, `lib/src/intention/presentation/catalog/intention_catalog_page.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/app/navigation/app_shell_pages_above_test.dart`; производный `lib/src/app/routing/app_router.gr.dart` при изменении генерируемого контракта.
  - **Estimated scope:** M.

- [ ] 3.3 Разворачивать и сворачивать ту же панель без потери сессии при жестах, клавиатуре и росте содержимого
  - **Acceptance criteria:**
    - Типизированный режим «компактный / развёрнутый» принадлежит одной экранной сессии и отделён от изменённости черновика. Кнопка с локализованной семантикой и свайп вверх по ручке разворачивают панель на всю доступную высоту; свайп вниз из развёрнутого режима только сворачивает её. Дальнейший свайп вниз из компактного режима вызывает закрытие 3.1, а прокрутка полей не закрывает форму.
    - Клавиатура и безопасные отступы пересчитывают геометрию без смены режима. Длинное описание и много тегов прокручиваются внутри ограничения, не разворачивая форму автоматически; отправка доступна на узком и низком экране с увеличенным текстом. Геометрия не создаёт новый маршрут, ключ сессии или команду.
    - Смена режима и продолжение после запроса закрытия сохраняют текстовые контроллеры, фокус и положение содержимого в допустимых пределах. Каждое новое открытие снова компактно; жест, скрывающий только клавиатуру по правилам платформы, сохраняет панель и черновик. Действия изменения размера доступны без жеста.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor --concurrency=2 --reporter expanded`
    - Добавить `intention_creation_sheet_layout_test.dart`: реальные жесты на ручке и прокрутку содержимого, оба режима, размеры телефона в портретной и альбомной ориентации, системные отступы, появление и скрытие клавиатуры, масштаб текста 200% и максимальный поддерживаемый на проверяемом устройстве. Проверять видимые и доступные области, отсутствие переполнений и неизменность ключа сессии, а не только значение режима.
  - **Dependencies:** 3.2.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, при необходимости новый компонент геометрии `lib/src/intention/presentation/editor/intention_creation_sheet.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, новый `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.4 Подтвердить управляемую модальность, геометрию и защиту закрытия перед подключением всех полей черновика
  - **Acceptance criteria:**
    - Настоящий маршрут подтверждает компактное открытие, явное изменение размера, доступность отправки и изоляцию каталога. Фон, ручка, кнопка и системное «назад» сохраняют единое решение сессии о закрытии; изменение размера и скрытие клавиатуры не теряют ввод.
    - Существующие корневые переходы, возврат в каталог и минимальное создание сохраняют гарантии; анализ и целевые проверки проходят. Локализованные элементы, уже появившиеся в панели, имеют доступные названия и действия без жеста.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/intention/presentation/catalog/intention_catalog_page_test.dart test/app/routing test/app/navigation test/app/intention_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 3.1, 3.2, 3.3.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [ ] 3.5 Подготавливать избранное и явную готовность быстрыми иконками панели перед единым сохранением
  - **Acceptance criteria:**
    - Панель показывает начальные выключенные отметки, переключает их только через существующую сессию и не отправляет самостоятельных команд. Перед включением готовности объясняются полная выполнимость за один день и операционная понятность; только явное подтверждение включает её, отмена оставляет выключенной, выключение локально.
    - Обе иконки различают состояния формой и семантикой, имеют русские и английские подсказки без утверждения уже сохранённого результата. Подтверждение готовности сохраняет черновик и режим; запоздалый callback не меняет закрытую, отправленную или другую сессию.
    - Основное действие называется «Сохранить» и отправляет весь черновик через готовую команду фазы 1. Во время отправки поля, обе отметки и повторное сохранение недоступны, индикатор виден, а закрытие по правилам сессии остаётся доступным.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_editor_page_test.dart test/intention/presentation/editor/intention_editor_view_model_test.dart --concurrency=2 --reporter expanded`
    - Проверить UI-путь включения, отмены и выключения готовности, оба состояния избранного и семантику `ru`/`en`; до отправки команд нет, после неё есть одна команда с выбранными значениями. На задержанной операции проверить повторные и запоздалые нажатия.
  - **Dependencies:** 3.4.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `test/intention/presentation/editor/intention_editor_page_test.dart`; при необходимости локальный компонент быстрых действий в том же модуле редактора.
  - **Estimated scope:** M.

- [ ] 3.6 Добавлять и снимать теги через общий выбор с возвращением в ту же панель и сохранением самостоятельных тегов
  - **Acceptance criteria:**
    - Панель передаёт готовый `TagDraftContext(notifier.draftTagSet)` существующему `TagCatalogRoute`. Выбор и `TagEditorRoute` открываются полноэкранно в том же корневом стеке; владелец удерживает сессию под ними. Возврат сохраняет все поля, режим и прокрутку панели, а «назад» из выбора закрывает только выбор.
    - Набор показан компактными элементами с актуальными названиями и локализованным доступным снятием. Несколько явных добавлений и снятие изменяют только черновик; выбор кандидата, поиск и создание тега не включают его автоматически. Сохранение и отмена редактора сохраняют поиск текущего открытия; повторное открытие выбора начинает новый поиск.
    - Новый тег сохраняется самостоятельной операцией, остаётся после сброса черновика и добавляется в него только явно. Отправленная или закрытая сессия не допускает изменения набора, поздний возврат не меняет новое открытие; отдельная страница выбора или механизм записи не вводятся.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/intention_creation_sheet_tags_test.dart test/app/tag_app_flow_test.dart test/app/tag_assignment_app_flow_test.dart test/tag/presentation/catalog --concurrency=2 --reporter expanded`
    - Добавить `intention_creation_sheet_tags_test.dart` с настоящими маршрутами: открыть выбор из компактной и развёрнутой панели, добавить несколько тегов, скрыть выбранный тег поиском, создать и отменить тег, вернуться, снять тег и подтвердить сброс. Сверить сохранность полей, режима, поиска и отсутствие назначения до отправки.
  - **Dependencies:** 3.5.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, новый `lib/src/intention/presentation/editor/intention_creation_tags.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, новый `test/app/intention_creation_sheet_tags_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.7 Показывать актуальность выбранных тегов и доступное исправление их отсутствия без потери набора черновика
  - **Acceptance criteria:**
    - Представление тегов исчерпывающе отображает готовую проекцию сессии: загрузку, подтверждённое название, подтверждённое отсутствие и отказ чтения. Переименование сохраняет идентичность; отсутствующий тег остаётся с последним известным именем и явным снятием, одноимённый новый тег его не заменяет.
    - Отказ чтения не выдаётся за удаление и предлагает повтор наблюдения только когда он разрешён контрактом. `IntentionCreationTagsMissingFailure` получает понятное локализованное объяснение и доступное исправление конкретного набора; до явной правки набор не сокращается и автоматическая повторная отправка не запускается.
    - Названия, состояния, снятие и восстановление чтения доступны с экранным диктором и увеличенным текстом. Элементы используют данные и методы готовой сессии, не добавляют собственных чтений репозитория, команд назначения или второго владельца ошибки операции.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_creation_tags_test.dart test/intention/presentation/editor/intention_editor_view_model_test.dart test/app/intention_creation_sheet_tags_test.dart --concurrency=2 --reporter expanded`
    - Добавить `intention_creation_tags_test.dart`: переименование, удаление с одноимённой заменой, задержанное чтение, устранимый и неповторяемый отказ наблюдения, явное снятие. Проверить локализованный текст и семантику, неизменность идентификаторов до исправления и отсутствие повторного сохранения.
  - **Dependencies:** 3.6.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_creation_tags.dart`, `lib/src/intention/presentation/editor/intention_editor_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, новый `test/intention/presentation/editor/intention_creation_tags_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.8 Подтвердить подготовку всех пяти полей через панель и общий выбор без преждевременной записи намерения
  - **Acceptance criteria:**
    - Реальная сборка панели, сессии и страниц тегов сохраняет текст, набор и обе отметки при изменении размера и временных переходах. Назначение существующему намерению продолжает работать, самостоятельные теги переживают сброс черновика.
    - Проверены состояния проекции и явное исправление отсутствующего тега, блокировка правок во время отправки и локализованная доступность новых элементов; анализ и целевые проверки проходят.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_draft_integration_test.dart test/app/tag_assignment_app_flow_test.dart test/app/tag_assignment_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 3.5, 3.6, 3.7.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [ ] 3.9 Делать ошибки сохранения и разрешённое исправление видимыми в панели при прокрутке и открытой клавиатуре
  - **Acceptance criteria:**
    - Название и описание сохраняют сырые строки; после ошибки соответствующее поле и собственный текст ошибки доводятся до видимости в прокручиваемой области. Сообщение подключено к существующему `OperationFailurePresentation`, и видимость поля не подменяет свидетельство видимости ошибки.
    - Общий отказ, необходимое исправление и допустимый повтор находятся в закреплённой области вместе с сохранением и доступны при длинном содержимом, клавиатуре и увеличенном тексте. Отсутствующие теги используют исправление 3.7; только доказанно устранимая причина предоставляет обычный повтор, а нерелевантная правка не снимает неповторяемый отказ.
    - При любом отказе сохраняются все пять полей и режим панели; исправление само не отправляет команду. Повтор передаётся существующей сессии и получает новый токен без второго пути сохранения или локального SnackBar.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/graph/presentation/operation_failure_presentation_test.dart --concurrency=2 --reporter expanded`
    - В реальной панели проверить ошибки обоих полей, отсутствие тегов, устранимую недоступность, конфликт, повреждение и неожиданный отказ при прокрутке и клавиатуре; измерить видимость собственного текста, действия и доступность исправления. Проверить удержание права до пригодного кадра и число принятых отправок.
  - **Dependencies:** 3.8.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, компонент геометрии из 3.3 при его выделении, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.10 Согласовать общие сообщения с модальной панелью и завершением отправки при временном перекрытии или уходе
  - **Acceptance criteria:**
    - Scaffold панели участвует в существующем `ScaffoldMessenger` и единственном `GraphOperationPresenter`. Общее сообщение видно над панелью и не перекрывает сохранение; появление и закрытие панели, подтверждения или страницы тегов не создаёт дублей и не вытесняет текущее сообщение очередным исходом.
    - Временное перекрытие живой формы непрозрачным выбором или редактором и диалогом сохраняет её право ошибки до возвращения и пригодного кадра. Окончательный уход или удаление хоста до предъявления передаёт неподтверждённое право общей поверхности ровно один раз, включая уже исправленный в 2.15 случай, когда renderer ещё не получал право.
    - Принятая отправка после подтверждённого ухода завершается один раз; успех закрывает только свою сессию и её подтверждение. Отказ прежней отправки не восстанавливает черновик и не закрывает новое открытие; сообщение появляется у действующего владельца, данные согласуются независимо от предъявления.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/intention_app_lifecycle_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart test/intention/presentation/editor/intention_editor_page_test.dart --concurrency=2 --reporter expanded`
    - Использовать настоящие маршруты и presenter, задержанные завершения и очередь сообщений: успех и отказ при подтверждении, перекрытие выбором/редактором, удаление хоста без возвращения и новое открытие до результата. Считать видимые сообщения и оставшиеся права, проверять геометрию SnackBar и кнопки; не подменять передачу ручным `releaseInitiatorClaim` из теста.
  - **Dependencies:** 3.9.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, при необходимости `lib/src/graph/presentation/graph_operation_presenter.dart` в пределах существующего протокола, `test/app/intention_app_lifecycle_test.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/graph/presentation/operation_failure_presentation_test.dart`.
  - **Estimated scope:** M.

- [ ] 3.11 Подтвердить доступное восстановление после отказов и однократное предъявление результатов на реальных маршрутах
  - **Acceptance criteria:**
    - Сообщения полей и общие отказы доступны в обоих режимах, а исправление и повтор соответствуют категории причины. Принятая операция не зависит от ухода; перекрытие, окончательное удаление, открытое подтверждение и новое создание не теряют и не дублируют результат.
    - Целевые регрессии координатора и обеих поверхностей проходят вместе с панелью, локализациями и анализом; существующая политика успеха создания сохранена.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor test/intention/presentation/operation/intention_command_coordinator_test.dart test/app/intention_app_lifecycle_test.dart test/graph/presentation --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 3.9, 3.10.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [ ] 3.12 Подтвердить доступность полного сценария панели с экранным диктором, клавиатурой и увеличенным текстом
  - **Acceptance criteria:**
    - На русском и английском доступны название, описание, выбор и снятие тегов, отметки, объяснение готовности, изменение размера, закрытие, сохранение и исправление ошибок. Семантика описывает черновик и состояния без опоры только на цвет; пользовательские тексты не переводятся.
    - Фокус начинается в названии, остаётся в доступной верхней поверхности при диалогах и переходах в теги и возвращается в ту же панель. Каталог и основная навигация под ней не доступны клавиатуре или экранному диктору; все действия выполняются без свайпа, размеры целей нажатия и контраст проходят действующие guidelines.
    - Проверен полный заполненный сценарий на узком и низком экране, в landscape, с безопасными отступами, открытой клавиатурой, масштабом текста 200% и максимальным системным текстом проверяемого устройства. Нет переполнений и недоступных действий; найденные дефекты устраняются в владельце соответствующего элемента без изменения требований.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart test/intention/presentation/editor/intention_creation_sheet_layout_test.dart test/app/navigation/app_navigation_accessibility_test.dart test/tag/presentation/tag_accessibility_test.dart --concurrency=2 --reporter expanded`
    - Добавить `intention_creation_sheet_accessibility_test.dart` с проверкой семантики, порядка фокуса и guidelines; на доступном устройстве проверить экранный диктор и системное скрытие клавиатуры, указав устройство и настройки. При отсутствии устройства не объявлять ручную проверку выполненной; автоматизированные проверки геометрии и семантики обязательны.
  - **Dependencies:** 3.11.
  - **Files likely touched:** Новый `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`; при исправлении выявленного дефекта — соответствующий компонент в изученном модуле `lib/src/intention/presentation/editor/` и его строки в `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`.
  - **Estimated scope:** M.

- [ ] 3.13 Доказать полное создание через кнопку каталога и панель на настоящем хранилище с согласованием всех представлений
  - **Acceptance criteria:**
    - Сквозной сценарий начинается с «+» настоящего каталога и подготавливает все пять полей через UI панели, общий выбор и редактор тега. До отправки в графе появляется только отдельно созданный тег; сохранение даёт одно целое активное намерение с тегами, готовностью, избранным, равными временными метками и одним подтверждённым результатом.
    - Успех закрывает панель, сохраняя текстовый и теговый фильтры, готовность, охват, порядок и допустимую позицию прокрутки каталога. Подходящее намерение учитывается ровно один раз; неподходящее не вставляется. Ранее загруженная скрытая Главная и навигация по тегу отражают полный результат; последнее место избранного учитывает архивированные записи.
    - Проверка использует настоящий AppRouter, сессию, координатор, presenter и Drift-адаптер через настроенное файловое соединение. После повторного открытия базы полный результат читается через публичную границу; минимальное создание по-прежнему имеет пустой набор и выключенные отметки. Команда не формируется тестом в обход пользовательского пути.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/intention_creation_sheet_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/app/intention_creation_draft_integration_test.dart test/app/home_favorites_app_flow_test.dart test/app/tag_navigation_app_flow_test.dart --concurrency=1 --reporter expanded`
    - Добавить `intention_creation_sheet_integration_test.dart` по образцу существующих контрольных точек; наблюдать фактические записи, публичные снимки и ревизию, состояние выдачи и число сообщений. Выполнить случаи совпадения и несовпадения фильтрам и чтение после повторного открытия файлового хранилища.
  - **Dependencies:** 3.12.
  - **Files likely touched:** Новый `test/app/intention_creation_sheet_integration_test.dart`; при необходимости существующие `test/support/local_database_harness.dart`, `test/support/favorite_storage_fixture.dart`, `test/support/tag_storage_fixture.dart`.
  - **Estimated scope:** M.

- [ ] 3.14 Доказать отсутствие частичного результата и независимость принятой отправки от ухода через реальные действия панели
  - **Acceptance criteria:**
    - В полном UI-пути подтверждённый сброс до отправки не создаёт намерение, назначения или избранное, но сохраняет самостоятельный тег. Переименование выбранного тега сохраняет идентичность; удаление с одноимённой заменой отклоняет весь набор, оставляет черновик и допускает только явное исправление перед новой отправкой.
    - Управляемый отказ настоящего хранилища после записи полного начального набора и до commit оставляет прежний граф, порядок избранного и ревизию без частичных записей. Панель сохраняет все данные и показывает одно сообщение; допустимый повтор после устранения причины создаёт только одно намерение. Проверка опирается на существующие узкие hooks соединения.
    - На задержанном выполнении реальные способы ухода подтверждают продолжение принятой команды. Успех и отказ после закрытия, при открытом подтверждении и после нового открытия не меняют чужую сессию; право результата получает ровно один владелец. Локальные правки не порождают событий постоянных команд, диагностика исхода не раскрывает личные данные и её отказ не меняет сохранение.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/app/intention_creation_sheet_failure_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/app/intention_creation_draft_integration_test.dart test/app/intention_app_lifecycle_test.dart --concurrency=1 --reporter expanded`
    - Добавить `intention_creation_sheet_failure_integration_test.dart` с настоящими маршрутизатором, presenter, координатором и Drift-адаптером. Сверять граф и публичную ревизию до и после отказа, наблюдать единственную команду и предъявление; проверять нажатия по фону, свайп ручки и системное «назад» вместо прямого закрытия сессии из теста.
  - **Dependencies:** 3.13.
  - **Files likely touched:** Новый `test/app/intention_creation_sheet_failure_integration_test.dart`; при необходимости `test/support/local_database_harness.dart`, `test/support/in_memory_diagnostics_sink.dart` и общий тестовый помощник в изученном `test/support/` для сценариев 3.13–3.14.
  - **Estimated scope:** M.

- [ ] 3.15 Подтвердить готовность полного сценария компактного создания по всем четырём спецификациям
  - **Acceptance criteria:**
    - `Ready to advance` фазы 3 подтверждён на настоящей навигации и постоянном хранилище: компактное открытие и изменение размера, пять полей, переходы в теги, доступность ввода и сохранения, защита черновика, ошибки, независимое завершение принятой операции и однократное предъявление результата.
    - Результаты 3.4, 3.8, 3.11–3.14 согласованы с требованиями намерений, тегов, избранного и навигации и решениями дизайна 1–9. Существующее назначение тегов и корневые переходы сохраняют гарантии; документация контрактов рядом с изменённым кодом и производные файлы соответствуют реализации.
    - Полные проверки репозитория, проверка генерации, релизная сборка и строгая валидация изменения проходят. Старый полноэкранный пользовательский путь создания отсутствует; схема хранения совместима с предусмотренным откатом, новые механизмы записи, хранения черновика или предъявления не появились.
  - **Verification:**
    - `mise run check`
    - `mise run codegen-check` — после коммита в чистой рабочей копии: штатный скрипт требует чистоты до и после генерации.
    - `mise exec --no-deps -- flutter build apk --release`
    - `mise exec --no-deps -- openspec validate compact-intention-creation --type change --strict --json --no-interactive`
    - После изменений Dart проверить запущенное приложение через DTD, горячую перезагрузку или перезапуск и runtime errors; при отсутствии запущенного приложения использовать указанные проверки CLI. Сопоставить доказательства с `Ready to advance` фазы 3 и явно указать фактически выполненные проверки устройства из 3.12.
  - **Dependencies:** 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 3.14.
  - **Files likely touched:** Нет — итоговая контрольная точка.
  - **Estimated scope:** XS.
