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

- [ ] 1.7 Сохранить единственную отправку и однократное предъявление результата полного создания независимо от инициатора
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

- [ ] 1.8 Подтвердить долговечность и независимое от экрана завершение полного создания
  - **Acceptance criteria:**
    - Проверки файловой базы, диагностики и времени жизни команды подтверждают один и тот же контракт полного создания. Результат сохраняется после закрытия инициатора, а отказ не оставляет частей записи или потерянного сообщения.
    - Целевые регрессии диагностики, координатора и представления проходят; существующие обработчики команд остаются исчерпывающими, анализ проходит.
  - **Verification:**
    - `mise exec --no-deps -- flutter test test/intention/data/file_backed_drift_intention_repository_test.dart test/shared/diagnostics/diagnostics_sink_test.dart test/intention/data/drift_intention_repository_fault_test.dart test/intention/presentation/operation/intention_command_coordinator_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/app/intention_app_lifecycle_test.dart --concurrency=2 --reporter expanded`
    - `mise exec --no-deps -- flutter analyze`
  - **Dependencies:** 1.5, 1.6, 1.7.
  - **Files likely touched:** Нет — контрольная точка.
  - **Estimated scope:** XS.

- [ ] 1.9 Согласовать каталог намерений с полным результатом создания без сброса выдачи и повторного добавления
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

- [ ] 1.10 Согласовать Главную с намерением, созданным сразу избранным, в том числе при скрытой вкладке
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

- [ ] 1.11 Согласовать навигацию по тегу и чтение назначений с фактами единого создания
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

- [ ] 1.12 Подтвердить готовность полного атомарного создания к подключению сессии черновика
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
