## Phase 1: Основа связей без массового удаления

- [x] 1.1 Убрать со страницы намерения переход к блокирующим связям и режим их выбора в соседстве, сохранив прежний текст отказа удаления намерения
  - **Критерии приёмки:**
    - Отказ удаления намерения с блокирующими связями показывает на странице прежний текст. Кнопки «Показать блокирующие связи» нет, страница не переключает соседство на первую непустую группу и не прокручивается к нему.
    - В соседстве нет режима выбора: отметок выбора у строк, просмотра выбранного и подтверждения массового удаления. Модель выбора, подтверждение, `RelationNeighborhoodViewModel.showBlockingRelations` и строки локализации этих частей удалены на обоих языках.
    - Выбор групп, подгрузка и согласование соседства работают как прежде. Проверки выбора и подтверждения удалены вместе с ними, как и сквозные сценарии, которые проходили через массовое удаление.
  - **Проверка:**
    - `mise run codegen` — локализация и провайдеры пересозданы без удалённых частей.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/long_term_relation/presentation/neighborhood test/app/intention_app_lifecycle_test.dart test/app/daily_choice_app_lifecycle_test.dart test/app/long_term_relation_app_flow_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - удаляются `lib/src/long_term_relation/presentation/neighborhood/blocking_relations_confirmation.dart`, `blocking_relations_selection_state.dart`, `blocking_relations_selection_view_model.dart` с `.g.dart`;
    - проверки: `test/intention/presentation/details/intention_details_delete_test.dart`, `test/intention/presentation/details/intention_details_page_test.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart`, `test/app/intention_app_lifecycle_test.dart`, `test/app/daily_choice_app_lifecycle_test.dart`, `test/app/long_term_relation_app_flow_test.dart`; удаляются `test/long_term_relation/presentation/neighborhood/blocking_relations_confirmation_test.dart` и `blocking_relations_selection_test.dart`.
  - **Размер:** M — в основном удаление.

- [x] 1.2 Убрать из координатора команд и презентера графа приём, завершение и предъявление массового удаления блокирующих связей
  - **Критерии приёмки:**
    - У `GraphCommandCoordinator` нет `acceptBlockingRelationsDelete`, токена, старта и завершения массового удаления. У `GraphOperationPresenter` нет их ветви и текстов, а строки локализации, которые использовала только она, удалены на обоих языках.
    - Если в проверке массовое удаление через координатор было лишь способом получить подтверждённое удаление связи, она использует одиночное удаление связи с тем же изменением графа и сохраняет свои ожидания. Это касается согласования соседства, занятости намерения и контрольной точки согласования. Проверки приёма и предъявления самого массового удаления удалены.
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/graph/application test/graph/presentation test/long_term_relation/presentation/neighborhood`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 1.1 — у приёма команды больше нет потребителя в представлении.
  - **Предполагаемые файлы:**
    - `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: удаляется `test/graph/application/graph_command_coordinator_blocking_relations_test.dart`; меняются `test/graph/application/graph_command_coordinator_tag_test.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart`.
  - **Размер:** M.

- [x] 1.3 Убрать из хранилища графа команду массового удаления блокирующих связей вместе с её исполнением и диагностическим событием
  - **Критерии приёмки:**
    - В приложении нет `DeleteBlockingRelations` с её исходом и отказами. Нет и её исполнения в `DriftPersonalGraphRepository`, а также события `BlockingRelationsDeleteDiagnosticsEvent` и его вывода в разработческий приёмник.
    - Если в проверке хранилища массовая команда была лишь способом удалить связь или дневной выбор, проверка использует одиночные команды удаления и сохраняет свои ожидания. Случаи, достижимые только массовой командой, удалены вместе с проверками самой команды по решению 13 дизайна. Это удаление связи и дневного выбора одной транзакцией и конфликт выбранного набора.
    - Тестовые адаптеры репозитория не исполняют массовую команду.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph test/intention/presentation/details test/long_term_relation/presentation/neighborhood test/app/intention_app_lifecycle_test.dart --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 1.2.
  - **Предполагаемые файлы:**
    - удаляются `lib/src/graph/application/delete_blocking_relations.dart` и `lib/src/graph/data/drift_personal_graph_repository_blocking_relations.dart`; меняются `lib/src/graph/data/drift_personal_graph_repository.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`;
    - проверки: удаляются `test/graph/application/delete_blocking_relations_test.dart`, `test/graph/data/drift_blocking_relations_delete_test.dart`, `test/support/large_blocking_relations_fixture.dart`; меняются `test/graph/data/drift_graph_fact_log_completeness_test.dart`, `test/graph/data/drift_graph_fact_log_write_test.dart`, `test/graph/data/drift_daily_path_protection_test.dart`, `test/graph/data/drift_statistics_relation_snapshot_test.dart`, `test/support/daily_choice_durability_fixture.dart`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`;
    - ветви тестовых адаптеров в `test/intention/presentation/details/details_test_support.dart`, `test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart`, `test/app/intention_app_lifecycle_test.dart`.
  - **Размер:** M — в основном удаление.

- [x] 1.4 Убрать из границы графа чтение и наблюдение явно выбранных связей вместе со ссылками на блокирующие связи
  - **Критерии приёмки:**
    - В `PersonalGraphRepository` нет `getSelectedRelations` и `watchSelectedRelations`. Удалены также:
      - типы выбранных связей и `BlockingRelationReference`;
      - их часть адаптера Drift;
      - наблюдатели выбранных связей и их оповещение при замене графа;
      - событие `SelectedRelationsReadDiagnosticsEvent`.
    - Тестовые адаптеры репозитория не реализуют удалённые методы. Проверки самих чтений удалены, в том числе их случаи в проверках большого набора групп и замены графа. Остальные ожидания этих файлов не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter analyze` — все тестовые адаптеры компилируются без удалённых методов.
    - `mise exec --no-deps -- flutter test test/graph --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter test --concurrency=1 --tags=flutter_process test/graph/data` — замена графа на файловом хранилище.
  - **Зависимости:** 1.1 — модель выбора была единственным потребителем чтений; 1.3 — команда использовала ссылки на блокирующие связи.
  - **Предполагаемые файлы:**
    - удаляются `lib/src/graph/application/selected_relations.dart`, `lib/src/graph/application/blocking_relation_reference.dart`, `lib/src/graph/data/drift_personal_graph_repository_selected_relations.dart`;
    - меняются `lib/src/graph/application/personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository_replacement.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`;
    - проверки: удаляются `test/graph/application/selected_relations_test.dart` и `test/graph/data/drift_selected_relations_test.dart`; меняются `test/graph/data/drift_relation_group_large_fixture_test.dart` и `test/graph/data/drift_graph_replacement_test.dart`;
    - механическое удаление переопределений во всех тестовых адаптерах `PersonalGraphRepository`, например `test/intention/presentation/details/details_test_support.dart`, `test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart`, `test/app/navigation/app_shell_state_test.dart`.
  - **Размер:** M — метод интерфейса нельзя убрать по частям, поэтому механическая адаптация тестовых адаптеров входит в задачу.

- [x] 1.5 Перевести проверки, которые сверяют количества связей или ревизию самостоятельным чтением сводки, на сводку наблюдения намерения
  - **Критерии приёмки:**
    - Такие проверки берут количества из `IntentionDetails.relationCounts`, а ревизию — из снимка `watchIntention`, и сохраняют свои ожидания по ADR-0047. Отличие отсутствующего намерения от намерения без связей проверяется по пустому снимку наблюдения.
    - `getRelationCounts` вызывают только проверки самого этого чтения и делегирующие тестовые адаптеры.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph/data test/graph/presentation/graph_reconciliation_checkpoint_test.dart test/intention/data --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter test --concurrency=1 --tags=flutter_process test/graph/data/file_backed_graph_durability_test.dart`.
    - `grep -rn 'getRelationCounts(' test` находит только проверки самого чтения в `test/intention/data/drift_intention_relation_counts_test.dart` и тестовые адаптеры.
  - **Зависимости:** 1.3 — файл проверок массового удаления, который тоже читал сводку, уже удалён.
  - **Предполагаемые файлы:** `test/graph/data/drift_relation_delete_test.dart`, `test/graph/data/drift_relation_archive_restore_test.dart`, `test/graph/data/drift_relation_update_test.dart`, `test/graph/data/drift_relation_watch_test.dart`, `test/graph/data/drift_personal_graph_repository_create_relation_test.dart`, `test/graph/data/file_backed_graph_durability_test.dart`, `test/graph/data/file_backed_daily_choice_durability_test.dart`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`, `test/intention/data/drift_intention_repository_fault_test.dart`, `test/intention/data/drift_intention_relation_counts_test.dart`.
  - **Размер:** M — механическая замена способа чтения в десяти файлах проверок.

- [x] 1.6 Убрать из границы графа самостоятельное чтение сводки связей `getRelationCounts` вместе с его диагностическим событием
  - **Критерии приёмки:**
    - В `PersonalGraphRepository` и адаптере Drift нет `getRelationCounts`. Нет и события `RelationCountsReadDiagnosticsEvent` с его выводом в разработческий приёмник. Сводка связей читается только вместе с наблюдением намерения и первыми порциями групп.
    - Тестовые адаптеры не реализуют удалённый метод, проверки самого чтения удалены. Проверки, переведённые в 1.5, проходят без изменений.
  - **Проверка:**
    - `mise exec --no-deps -- flutter analyze` — все тестовые адаптеры компилируются без удалённого метода.
    - `mise exec --no-deps -- flutter test test/intention/data test/graph/data --exclude-tags=flutter_process`.
  - **Зависимости:** 1.1 — модель выбора была единственным потребителем чтения в приложении; 1.5.
  - **Предполагаемые файлы:** `lib/src/graph/application/personal_graph_repository.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`, `lib/src/shared/diagnostics/diagnostics_sink.dart`, `lib/src/shared/diagnostics/developer_diagnostics_sink.dart`, `test/intention/data/drift_intention_relation_counts_test.dart` и механическое удаление переопределений в тестовых адаптерах `PersonalGraphRepository`.
  - **Размер:** M — метод интерфейса нельзя убрать по частям, поэтому механическая адаптация тестовых адаптеров входит в задачу.

- [x] 1.7 Вынести механику порций и согласования ревизий соседства в общее ядро `RelationGroupPaging`, не меняя поведения соседства
  - **Критерии приёмки:**
    - По решению 6 дизайна ядро отвечает за:
      - проверку первой порции и полноты количества;
      - приём продолжения только на его ревизии;
      - поколения запросов;
      - сборку «загруженная часть плюс порция» на одной ревизии с ограничением повторов;
      - выбор ближайшего сохранившегося якоря.

      Ядро обобщено по строке и её идентификатору: долговременные и дневные группы соседства собираются одной реализацией вместо двух копий.
    - От потребителя ядро получает только чтение порции его группы, размер порции и проверку принадлежности строки. Провайдеров, групп и состояний соседства ядро не знает. Фильтр завершений координатора, наблюдение намерения, выбор группы и публикуемое состояние остаются у `RelationNeighborhoodViewModel`.
    - Проверки соседства проходят, а их файлы в этой задаче не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/neighborhood test/intention/presentation/details test/app/long_term_relation_app_flow_test.dart`.
    - Перед фиксацией задачи `git diff --exit-code HEAD -- test/long_term_relation/presentation/neighborhood` подтверждает, что файлы проверок соседства не менялись.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 1.1, 1.2 — проверки соседства больше не используют показ блокирующих связей и массовое удаление.
  - **Предполагаемые файлы:** `lib/src/long_term_relation/presentation/relation_group_paging.dart` (новый), `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart`.
  - **Размер:** M.

- [x] 1.8 Перенести проверки механики порций из проверок модели соседства в проверки общего ядра порций
  - **Критерии приёмки:**
    - Каждая обязанность ядра из решения 6 дизайна проверяется на уровне ядра, без провайдеров и модели:
      - несогласованные первая порция и полное количество;
      - порция больше размера, чужая или повторная строка;
      - продолжение другой ревизии;
      - поздний ответ прежнего поколения;
      - прерывание сборки при смене ревизии и исчерпание повторов;
      - выбор ближайшего сохранившегося якоря.
    - Проверки модели соседства, которые проверяли только эти механизмы, перенесены, а не продублированы. У модели остаются проверки её собственных решений: выбора группы, отбора завершений и наблюдений, публикуемых состояний прогресса, обновления и отказа.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/relation_group_paging_test.dart test/long_term_relation/presentation/neighborhood`.
  - **Зависимости:** 1.7.
  - **Предполагаемые файлы:** `test/long_term_relation/presentation/relation_group_paging_test.dart` (новый), `test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart`.
  - **Размер:** M.

- [x] 1.9 Подтвердить готовность первой фазы: массового удаления и самостоятельного чтения сводки в приложении нет, а соседство работает поверх общего ядра порций
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» первой фазы:
      - изменённые требования о физическом удалении и о согласованности счётчиков выполняются без массовой операции. Блокирующие ссылки проверяются атомарно с удалением, отказ удаления намерения показывает прежний текст без перехода к выбору связей, а счётчики согласуются после одиночных операций;
      - поведение соседства подтверждено прежними проверками, переведёнными на общее ядро.
    - В `lib/`, `test/` и `benchmark/` нет следов массового удаления, чтения выбранных связей и самостоятельного чтения сводки.
    - Результаты проверок и путь к APK сообщены в сессии. Ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - `grep -rnE 'DeleteBlockingRelations|BlockingRelationsDelete|BlockingRelationReference|SelectedRelations|blockingRelations|[sS]howBlockingRelations|relationNeighborhood(AddTo|RemoveFrom)Selection|getRelationCounts|RelationCountsRead' lib test benchmark` ничего не находит.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - отказ удаления намерения со связями показывает прежний текст без кнопки перехода к связям;
      - соседство переключает группы, подгружает длинную группу и обновляется после архивирования и удаления связи как прежде.
  - **Зависимости:** 1.1–1.8.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

## Phase 2: Страница намерения с вкладками и целью открытия

- [x] 2.1 Расширить `TopBar` стрелкой «назад», заголовком со значком и приглушением и вариантом без видимого заголовка с доступным именем маршрута
  - **Критерии приёмки:**
    - По README `TopBar` панель может начинаться стрелкой «назад» вместо крестика: область нажатия 44 в `space-2` от края, значок 24 цвета `ink`, доступное название передаёт потребитель. Заголовок может иметь значок 16 цвета `muted` в 6 перед текстом и приглушённый вид `muted`. Он остаётся одной строкой с многоточием, заголовком маршрута и не шире панели без 64 с каждой стороны. По решению 1 design явный вариант API без видимого заголовка требует доступное имя маршрута от потребителя: панель передаёт его диктору и не создаёт пустого семантического заголовка. Отсутствие заголовка не кодируется пустой строкой. Действие справа, удержание стрелки и остальные варианты README не добавляются: у них нет потребителя в этой фазе.
    - Значок стрелки «назад» перенесён из макета `IntentionPage.dc.html` в `lib/src/design_system/icons/` по правилам его README: SVG, запись происхождения, значение `DoableIconData` и обновлённый эталон каталога иконок.
    - Компонентные проверки в обеих темах подтверждают, что стрелка вызывает обработчик и слышна диктору под переданным названием. Они проверяют значок и приглушение заголовка и обрезку длинного заголовка многоточием. Для варианта без видимого заголовка они подтверждают отсутствие видимого текста заголовка и пустого семантического заголовка, наличие переданного имени маршрута для диктора и работу стрелки. Прежние варианты с крестиком и строкой назначения не меняются.
  - **Проверка:**
    - Эталон каталога иконок пересоздан `mise exec --no-deps -- flutter test --update-goldens test/design_system/doable_icon_test.dart`; в нём добавлена только стрелка.
    - `mise exec --no-deps -- flutter test test/design_system/top_bar_test.dart test/design_system/doable_icon_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/top_bar.dart`, `lib/src/design_system/doable_icon.dart`, новый SVG стрелки в `lib/src/design_system/icons/assets/`, `lib/src/design_system/icons/README.md`, `test/design_system/top_bar_test.dart`, `test/design_system/doable_icon_test.dart`, `test/design_system/goldens/doable_icons.png`.
  - **Размер:** M.

- [x] 2.2 Добавить в дизайн-систему шапку `PageHead` с названием целиком и полосу вкладок `Tabs` с числом, значком и закреплённым состоянием
  - **Критерии приёмки:**
    - `PageHead` по README показывает переданное название стилем `page-title` цвета `ink` с переносом и без обрезки при любой длине. Название — второй заголовок экрана, поля шапки соответствуют README. Нажатие на название, метка, строка пояснения и кнопка под названием не добавляются: их потребители появляются в фазах 3 и 4.
    - `Tabs` по README — полоса пилюль со смыслом вкладок:
      - текущая вкладка лежит на `fill` с текстом `ink`, остальные — `muted`, начертание не меняется;
      - после названия необязательные число с табличными цифрами и значок; доступное название пункта задаёт потребитель, диктор слышит выбранную вкладку;
      - полоса прокручивается вбок с затуханием краёв и показывает текущую вкладку; в закреплённом состоянии под ней линия `hairline`; фокус клавиатуры рисует `focus-ring`.

      Варианты `radio`, `toggle`, `leading`, `disabled` и `minWidth` не добавляются: на странице намерения у них нет потребителя.
    - Компонентные проверки в обеих темах подтверждают выбор и вызов обработчика, семантику выбранной вкладки и доступные названия. Они проверяют длинные подписи при увеличенном тексте без переполнения, прокрутку к текущей вкладке, линию только в закреплённом состоянии и перенос длинного названия шапки.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/page_head_test.dart test/design_system/tabs_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/page_head.dart` (новый), `lib/src/design_system/components/tabs.dart` (новый), `test/design_system/page_head_test.dart` (новый), `test/design_system/tabs_test.dart` (новый).
  - **Размер:** M.

- [x] 2.3 Перевести страницу намерения на верхнюю панель с типом и шапку с полным названием, которое при прокрутке переходит в панель
  - **Критерии приёмки:**
    - Вместо `AppBar` страница держит `TopBar`. Стрелка с доступным названием «Назад» закрывает только страницу намерения. После загрузки заголовок маршрута — тип «Намерение» или «Действие» по готовности к действию со своим значком. Пока подробные данные не получены или их чтение отказало, страница использует вариант из 2.1 без видимого заголовка и передаёт ему локализованное имя маршрута `detailsTitle` («Подробности намерения» / «Intention details»). Визуально панель показывает только стрелку, без пустого заголовка в семантике, а под ней — прежние состояния загрузки и отказа. `detailsTitle` сохранена на обоих языках только для имени маршрута в этих состояниях.
    - Первым элементом прокрутки стоит `PageHead` с названием целиком вместо прежнего заголовка, ниже без переделки идёт прежнее содержимое. Нажатие на название до фазы 3 ничего не открывает.
    - По решению 1 дизайна страница измеряет высоту шапки после раскладки и при смене масштаба текста и держит флаг «шапка скрыта» отдельно от прокрутки. Смена флага перестраивает только панель:
      - когда название уходит из видимой части, панель показывает его одной строкой с многоточием без значка, у архивированного намерения — приглушённым;
      - при возврате к началу панель снова показывает тип.
    - Проверки страницы подтверждают тип для обеих готовностей, переход названия в панель и обратно, приглушённое название архивированного намерения и закрытие стрелкой. В состояниях загрузки и отказа чтения они подтверждают панель только со стрелкой, непустое имя маршрута для диктора на русском и английском и отсутствие пустого семантического заголовка; успешное чтение заменяет это имя показанным типом. Сценарии, которые уходили со страницы намерения через `BackButton` или `tester.pageBack()` либо искали у неё `AppBar`, используют стрелку и заголовок `TopBar` и сохраняют прежние ожидания.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/app/navigation test/app/routing test/app/intention_app_lifecycle_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/long_term_relation_app_flow_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 2.1, 2.2.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_details_page_test.dart`, `test/app/navigation/app_navigation_accessibility_test.dart`, `test/app/intention_app_lifecycle_test.dart`, `test/app/intention_creation_sheet_integration_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/app/routing/app_router_test.dart`.
  - **Размер:** M — проверки в основном меняются механически: способ возврата и поиск заголовка.

- [x] 2.4 Разложить прежнее содержимое страницы намерения по закреплённым вкладкам «Обзор», «Связи» и «Статистика», которые переключаются без шагов в истории
  - **Критерии приёмки:**
    - По решению 1 дизайна сразу под шапкой стоит закреплённая полоса `Tabs`:
      - «Обзор» показывает прежние поля, действия, правку и теги;
      - «Связи» — прежнее соседство и число активных долговременных связей с отметкой архива, если есть архивированные, по сводке подробных данных; диктор слышит число активных и число архивированных связей на русском и английском;
      - «Статистика» — прежний раздел статистики.

      Нового оформления содержимого нет. Вкладка «Выборы» появляется в фазе 5.
    - Переключение вкладок не добавляет шагов в историю: «назад» закрывает страницу, а страница остаётся обычной страницей с нижней панелью. Выбранная вкладка хранится в состоянии страницы и сохраняется при возвращении с открытых над ней страниц. Без цели страница открывается на «Обзоре», с прежней целью статистики — на «Статистике» с её видом и периодом. Прокрутка к разделу и ожидание загрузки тегов удалены.
    - Соседство не создаётся и не читает групп до первого показа вкладки «Связи», в том числе при открытии на статистике. После первого показа страница удерживает его до своего закрытия, поэтому выбранная группа сохраняется при переключении вкладок. Состояние соседства остаётся общим по намерению до фазы 6. Кнопка «Показать архив связей» на «Обзоре» выбирает вкладку «Связи» и показывает архив связей, как прежде.
    - Сценарии, которые пользовались соседством или разделом статистики на странице намерения, сначала выбирают нужную вкладку и сохраняют прежние ожидания. Новые проверки страницы подтверждают:
      - «назад» после нескольких вкладок;
      - сохранение вкладки после возврата со страницы над ней;
      - отсутствие чтений групп до показа «Связей»;
      - число, отметку архива и доступное название вкладки «Связи»;
      - кнопку показа архива.
  - **Проверка:**
    - `mise run codegen`.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/long_term_relation/presentation test/daily_choice/presentation test/statistics/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 2.3.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки страницы в `test/intention/presentation/details/`: `intention_details_page_test.dart`, `intention_details_delete_test.dart`, `intention_details_statistics_test.dart`, `details_test_support.dart`;
    - сценарии, открывающие соседство или статистику со страницы, например `test/app/navigation/app_shell_page_matrix.dart`, `test/app/navigation/app_shell_back_test.dart`, `test/app/navigation/ordinary_page_layout_scenarios.dart`, `test/app/routing/app_router_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/app/intention_statistics_app_flow_test.dart`, `test/daily_choice/presentation/daily_choice_creation_completion_test.dart`, `test/daily_choice/presentation/daily_choice_creation_exit_test.dart`, `test/daily_choice/presentation/daily_choice_creation_route_scenarios.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart`.
  - **Размер:** M — перенос соседства и статистики на вкладки требует механически добавить выбор вкладки в сценарии, которые открывают их со страницы намерения.

- [x] 2.5 Сохранять закреплённые вкладки у панели при смене вкладки и отмечать закреплённую полосу линией
  - **Критерии приёмки:**
    - По решению 1 дизайна смена вкладки при скрытой шапке переводит страницу к смещению высоты шапки: вкладки остаются под панелью, а тело новой вкладки начинается с начала. При видимой шапке смещение не меняется. Позиция прокрутки страницы сохраняется при возвращении с открытых над ней страниц.
      - При повторном показе «Связей» якорь прежнего согласования, сохранённый в удерживаемом соседстве, не меняет заданное страницей положение. Это не сбрасывает выбранную группу и загруженные порции, которые удерживаются по 2.4. Восстановление якоря при новом согласовании уже видимой вкладки сохраняется.
    - Полоса вкладок показывает линию закреплённого состояния по тому же флагу «шапка скрыта», что и название в панели, без перестройки всей прокрутки.
    - Проверки страницы подтверждают оба случая смены вкладки, линию только при скрытой шапке и сохранение позиции после возврата со страницы над ней. Дополнительно они проходят путь «согласование с запомненной строкой → Обзор → Связи»:
      - при скрытой шапке тело «Связей» остаётся в начале под закреплёнными вкладками, включая заголовок соседства с выбором группы;
      - при видимой шапке сохраняется смещение страницы без перехода к строке прежнего якоря.

      В обоих случаях строка прежнего якоря построена при повторном показе: проверка должна обнаруживать её ошибочное восстановление. Прежняя проверка восстановления видимой строки при согласовании открытого списка сохраняется.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/long_term_relation/presentation/neighborhood`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 2.4.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`, `test/intention/presentation/details/intention_details_page_test.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart`.
  - **Размер:** M.

- [x] 2.6 Читать статистику страницы намерения, только пока её маршрут текущий и выбрана вкладка «Статистика»
  - **Критерии приёмки:**
    - По решению 9 дизайна и ADR-0027 видимость для модели статистики — «маршрут текущий и выбрана вкладка „Статистика“». Страница сообщает её из одной точки при смене маршрута и вкладки. Пока выбрана другая вкладка, статистика ничего не читает. Показ вкладки после подтверждённых изменений один раз перечитывает загруженную часть.
    - Страница удерживает провайдер статистики, пока жив её экземпляр, поэтому вид, период и загруженные порции переживают смену вкладок. Закреплённое сообщение об обновлении раздела учитывает перекрытие и встаёт под полосу вкладок.
    - Проверки статистики страницы подтверждают:
      - отсутствие чтений на других вкладках и под открытыми над страницей страницами;
      - одно обновление при показе вкладки;
      - сохранение выбора после переключений;
      - положение сообщения об обновлении под вкладками.

      Прежние проверки полуночи и возврата приложения сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details/intention_details_statistics_test.dart test/statistics/presentation test/app/intention_statistics_app_flow_test.dart test/app/intention_statistics_navigation_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 2.4.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/statistics/presentation/intention_statistics_section.dart`, `test/intention/presentation/details/intention_details_statistics_test.dart`.
  - **Размер:** S.

- [x] 2.7 Открывать страницу намерения по типизированной цели на доступной вкладке и привязать её вкладку и статистику к ключу экземпляра
  - **Критерии приёмки:**
    - По решению 2 дизайна аргумент маршрута `statisticsTarget` заменён закрытым типом `IntentionPageTarget` с вариантами доступных вкладок. «Обзор» открывается по умолчанию, «Связи» — без группы, «Статистика» — с `IntentionStatisticsTarget`. Группа в цели «Связей» и цель «Выборов» появляются в фазах 6 и 5. Цель выбирает начальную вкладку один раз, дальше вкладку меняет только пользователь. Цель статистики передаётся модели статистики, как прежде.
    - Страница при создании своего состояния порождает ключ `IntentionPageInstance`, сравниваемый по идентичности, и использует его вместо `Object()` как типизированный ключ семейства статистики. Смена `IntentionId` у того же виджета создаёт новый экземпляр с вкладкой из цели.
    - Главная и разбивка статистики открывают страницу с целью статистики, остальные вызывающие — без цели. Проверки подтверждают:
      - открытие на каждой доступной вкладке;
      - вид и период при открытии из Главной и разбивки;
      - отсутствие чтений групп при открытии на статистике;
      - независимость выбранной вкладки и параметров статистики двух страниц одного намерения в истории.
  - **Проверка:**
    - `mise run codegen` — маршруты и провайдеры пересозданы.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/statistics/presentation test/app/intention_statistics_navigation_test.dart test/app/intention_statistics_app_flow_test.dart test/app/home_statistics_app_flow_test.dart test/app/routing`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 2.4; 2.6 — меняет те же проверки статистики страницы.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_page_target.dart` (новый, вместе с `IntentionPageInstance`), `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/statistics/presentation/intention_statistics_view_model.dart`, `lib/src/statistics/presentation/intention_statistics_section.dart`, `lib/src/app/home/home_page.dart` и сгенерированные маршруты и провайдеры;
    - проверки: `test/intention/presentation/details/intention_details_statistics_test.dart`, `test/intention/presentation/details/details_test_support.dart`, `test/statistics/presentation/intention_statistics_test_support.dart`, `test/app/intention_statistics_navigation_test.dart`, `test/app/intention_statistics_app_flow_test.dart`.
  - **Размер:** M.

- [x] 2.8 Подтвердить готовность второй фазы: страница намерения с панелью, шапкой и закреплёнными вкладками открывается по типизированной цели
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» второй фазы:
      - требования о странице с вкладками и разделе статистики выполняются для уже существующих частей страницы, а требование о цели открытия — в части выбора доступной вкладки и параметров статистики;
      - навигация из Главной, статистики и других мест открывает страницу на ожидаемой вкладке;
      - выбранная вкладка и состояние статистики независимы для двух страниц одного намерения.
    - На странице нет `AppBar`, прокрутки к разделу статистики и аргумента `statisticsTarget`. Прежние поля, действия, правка, теги и соседство работают на своих вкладках как прежде.
    - Результаты проверок и путь к APK сообщены в сессии. Сравнение с макетом и ручная проверка на устройстве остаются за пользователем и не блокируют готовность фазы.
  - **Проверка:**
    - `rg -n 'statisticsTarget' lib test` ничего не находит. `rg -n 'detailsTitle' lib test` подтверждает, что в коде страницы строка используется только как доступное имя маршрута без видимого заголовка при загрузке и отказе чтения; остальные вхождения — локализация и проверки этого поведения.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - тип и значок в панели, переход длинного названия в панель и обратно, приглушённое название архивированного намерения;
      - закреплённые вкладки с линией, полоса при крупном шрифте, число и отметка архива на «Связях»;
      - открытие с Главной и из разбивки статистики на вкладке «Статистика» с видом и периодом; «назад» после нескольких вкладок закрывает страницу.
  - **Зависимости:** 2.1–2.7.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

## Phase 3: Правка названия и описания на отдельном экране

- [x] 3.1 Не объявлять сообщением успех изменения названия и описания намерения, оставляя его отказ экранной сессии инициатора по ADR-0046
  - **Критерии приёмки:**
    - По решению 4 дизайна и ADR-0046 `GraphCommandCoordinator` применяет к `UpdateIntention` третью политику предъявления — «успех без сообщения». Политику задаёт вид операции в координаторе, а не экран или модель:
      - успех публикуется в канал завершений для согласования данных, но не образует права предъявления и не оставляет в координаторе непредъявленной записи;
      - отказ следует протоколу ADR-0012 без изменений: живой экранной сессии право выдаёт `claimInitiatorFailure`, а освобождение права или уход сессии передаёт отказ оболочке.

      Создание и физическое удаление сохраняют политику по умолчанию. Готовность, архивирование и восстановление тоже не меняются: «только отказ» они получают в фазе 4.
    - У `GraphOperationPresenter` нет текста успеха изменения намерения, строка `detailsSaved` удалена на обоих языках. Тексты отказов изменения сохраняются.
    - Проверки координатора закрепляют новую политику отдельно от «только отказ»: успех изменения не выдаётся ни инициатору, ни оболочке и не оставляет непредъявленной записи; отказ принадлежит живой сессии, а после её освобождения предъявляется оболочкой один раз. Проверки встроенной правки и сквозные сценарии, которые ожидали сообщение об успехе изменения, подтверждают его отсутствие и сохраняют остальные ожидания.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана без удалённой строки.
    - `mise exec --no-deps -- flutter test test/intention test/graph/application test/graph/presentation test/daily_choice/presentation/catalog test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/operation/intention_command_coordinator_test.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/intention/presentation/details/intention_details_page_test.dart`, `test/app/intention_app_lifecycle_test.dart`.
  - **Размер:** M.

- [x] 3.2 Расширить `TextField` растущим многострочным полем с пределами строк, видами названия и текста, автофокусом и слотом виджета ошибки вместо строки
  - **Критерии приёмки:**
    - По README `TextField` и решению 11 дизайна поле может расти вместе с текстом:
      - вид `name` пишется стилем `action`, вид `text` — стилем `field`; боковые поля растущего поля — `space-3`, сверху и снизу 13 у `name` и 11 у `text`;
      - наименьшая и наибольшая высота задаются в строках; после наибольшей текст прокручивается внутри поля, а без неё поле растёт без предела и ничего не обрезает;
      - метка перед текстом необязательна, автофокус ставит курсор в поле при первом показе.

      Режим сохранённого текста с открытием правки и приглушением не добавляется: его потребитель — Обзор фазы 4.
    - По решению 5 дизайна ошибка под полем — слот виджета вместо строки: строковая ошибка не даёт свидетельства кадра. Поле ставит виджет в 6 под собой и в `space-1` от края стилем `hint` цвета `danger`. Лист тега передаёт ошибку названия через слот, сохраняя её вид и объявление диктором.
    - Компонентные проверки в обеих темах подтверждают рост от наименьшей до наибольшей высоты и прокрутку внутри после неё, рост названия без обрезки, стили обоих видов, поле без метки и автофокус. Они проверяют положение и стиль виджета ошибки и отсутствие переполнения при увеличенном тексте. Проверки однострочного поля с меткой и листа тега сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/text_field_test.dart test/tag/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/text_field.dart`, `lib/src/tag/presentation/editor/tag_sheet.dart`, `test/design_system/text_field_test.dart`, `test/tag/presentation/editor/tag_sheet_test.dart`.
  - **Размер:** M.

- [x] 3.3 Добавить компактную основную кнопку `Button` размера sm и место для одной такой кнопки справа в `TopBar` со стрелкой «назад»
  - **Критерии приёмки:**
    - По README `Button` основная кнопка размера `sm` имеет высоту `control-height-sm` (36), боковые поля 14 и ширину по подписи, а область нажатия — не меньше `tap-min`. Выключенная кнопка остаётся на месте плашкой `fill` с подписью `grip` и объявляется недоступной.
    - По README `TopBar` панель со стрелкой «назад» может нести справа одну кнопку размера `sm`, переданную потребителем, в `space-3` от края. Заголовок остаётся по центру панели и не шире её без 64 с каждой стороны. Кнопка-иконка справа не добавляется: её потребитель — параметры намерения в фазе 4.
    - Компонентные проверки в обеих темах подтверждают размеры, цвета и выключенное состояние кнопки. Для панели они проверяют положение кнопки, центр и обрезку длинного заголовка рядом с ней, вызов обработчиков стрелки и кнопки и их доступные названия. Прежние варианты кнопки и панели не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/button_test.dart test/design_system/top_bar_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/button.dart`, `lib/src/design_system/components/top_bar.dart`, `test/design_system/button_test.dart`, `test/design_system/top_bar_test.dart`.
  - **Размер:** M.

- [x] 3.4 Добавить в `ConfirmDialog` вариант отмены изменений с текстовой кнопкой отмены и основной кнопкой, которая сохраняет работу
  - **Критерии приёмки:**
    - По README `ConfirmDialog` вариант `discard` спрашивает перед уходом с несохранённой работой. Заголовок-вопрос — название маршрута для диктора, первый абзац — простой текст без выделенного названия. Действия:
      - текстовая кнопка `md` цвета `accent`, которая отменяет работу;
      - за ней в `space-1` основная кнопка `md` по ширине подписи, которая сохраняет работу.

      Ряд стоит в 14 под текстом и выходит на 8 правее него, нижнее поле — 14. Безопасный ответ — сохранить работу: его дают основная кнопка, нажатие на подложку и системное «назад». Отмену даёт только текстовая кнопка.
    - `Button` получает текстовую кнопку размера `md` с боковыми полями 14 и основную кнопку размера `md` по ширине подписи, нужные варианту. Вариант подтверждения не меняется.
    - Компонентные проверки в обеих темах подтверждают раскладку и цвета, исход каждого способа ответа, доступные названия и перенос длинных подписей при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/confirm_dialog_test.dart test/design_system/button_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.3 — расширяет тот же `Button`.
  - **Предполагаемые файлы:** `lib/src/design_system/components/confirm_dialog.dart`, `lib/src/design_system/components/button.dart`, `test/design_system/confirm_dialog_test.dart`, `test/design_system/button_test.dart`.
  - **Размер:** M.

- [x] 3.5 Добавить модель экрана изменения намерения с черновиком, доступностью «Сохранить», сохранением и единым решением о закрытии
  - **Критерии приёмки:**
    - По решению 5 дизайна `IntentionEditViewModel` — семейство по ключу формы, который создаёт и держит экран, и `IntentionId`. Модель держит сохранённые название и описание из подробных данных намерения на момент открытия, черновик, `OperationState<Intention>` и опубликованное право предъявления отказа.
      - Текст изменён, если сырой черновик отличается от сохранённого названия или описания; отсутствующее описание считается пустым текстом.
      - «Сохранить» доступна, если текст изменён, название непусто по правилу нормализации предметного типа и для намерения не выполняется другая команда. Занятость читается при построении и по завершениям координатора; ответ `AlreadyRunning` делает модель занятой.
      - Сохранение принимает `UpdateIntention`, пустое описание отправляется как отсутствующее.
      - Правка поля снимает отказ по правилам нынешнего `IntentionDetailsEdit`: отказ проверки этого поля и общий отказ проверки.
    - Отказ сохранения публикуется с правом из `claimInitiatorFailure`. Как в `IntentionEditorViewModel`, `listenSelf` освобождает право, которое состояние больше не публикует, а освобождение модели — выполняющийся токен.
    - Решение о закрытии одно для всех способов ухода: неизменённый текст — закрыть; изменённый без выполняющегося сохранения, в том числе после отказа, — спросить об отмене; принятое сохранение — закрыть без вопроса. Успех сохранения сообщает экрану закрыться.
    - Проверки модели по решению 14 дизайна подтверждают:
      - изменённость и доступность «Сохранить» для пустого названия, чужой выполняющейся команды и после её завершения;
      - отказ поля и общий отказ с освобождением права при правке поля и при освобождении модели;
      - новый токен повторного сохранения после отказа, при котором прежний отказ не ожидает оболочку;
      - решение о закрытии в каждом состоянии;
      - уход во время сохранения: поздний отказ переходит оболочке, а успех сообщения не образует.
  - **Проверка:**
    - `mise run codegen` — провайдер модели сгенерирован.
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.1 — успех изменения не образует права предъявления.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_view_model.dart` (новый, с `.g.dart`), `lib/src/intention/presentation/edit/intention_edit_state.dart` (новый), `test/intention/presentation/edit/intention_edit_view_model_test.dart` (новый); тестовый репозиторий подробных данных из `test/intention/presentation/details/details_test_support.dart`.
  - **Размер:** M.

- [x] 3.6 Добавить экран-задачу «Изменить намерение» с полями названия и описания, «Сохранить» в верхней панели и отказами у поля и на экране
  - **Критерии приёмки:**
    - По решению 5 дизайна маршрут `IntentionEditRoute` с `IntentionId` открывает страницу-задачу с собственным `Scaffold` без нижней панели по ADR-0020. Экран создаёт и держит ключ формы своей сессии для модели из 3.5.
      - Верхняя панель — стрелка «назад», заголовок «Изменить намерение» и компактная «Сохранить» из 3.3.
      - Поле названия вида `name` и поле описания вида `text` из 3.2 заполнены сохранёнными значениями. Описание растёт от пяти до тринадцати строк и дальше прокручивается внутри. Курсор стоит в конце названия.

      Выбор поля для курсора не добавляется: вход из описания появляется в фазе 4.
    - «Сохранить» доступна по правилам модели. Успех закрывает экран, а страница намерения показывает новые данные без сообщения. Отказ проверки поля рисуется под этим полем через `OperationFailurePresentation` в слоте ошибки, остальные отказы — `Notice` над полями. Введённый текст при отказе сохраняется. Тексты экрана, полей и действия добавлены на русском и английском; отказы используют существующие тексты изменения.
    - Проверки экрана подтверждают:
      - сохранённые значения, курсор в конце названия и недоступную «Сохранить» при открытии;
      - недоступность «Сохранить» при названии из пробелов и изменённом описании;
      - закрытие после успеха с новым названием в шапке страницы и без сообщения общей поверхности;
      - объяснение длины у поля для названия из 256 символов: экран открыт с введённым текстом, а общая поверхность не дублирует отказ;
      - общий отказ хранилища в `Notice` с сохранённым вводом и успешное повторное «Сохранить»;
      - прокрутку описания внутри поля после тринадцати строк и доступность полей и «Сохранить» без переполнения при тексте 2× и открытой клавиатуре;
      - сохранение экрана и черновика при смене системной темы.
  - **Проверка:**
    - `mise run codegen` — маршруты и локализация пересозданы.
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit test/app/routing`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.2, 3.3, 3.5.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_page.dart` (новый), `lib/src/app/routing/app_router.dart` и сгенерированные маршруты, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/intention/presentation/edit/intention_edit_page_test.dart` (новый).
  - **Размер:** M.

- [x] 3.7 Закрывать экран изменения одним решением сессии: сразу для неизменённого текста и во время сохранения, с вопросом «Отменить изменения?» для изменённого
  - **Критерии приёмки:**
    - По решению 5 дизайна экран не закрывается системным «назад» сам: стрелка и системное «назад» запрашивают решение модели из 3.5. Закрытие убирает маршрут через `removeRoute`, не проходя собственную защиту возврата. Вопрос — вариант `discard` из 3.4: «Отменить изменения?», текст о том, что изменения намерения не сохранятся, и действия «Отменить» и «Продолжить правку» на русском и английском.
    - «Отменить» закрывает экран без команды. «Продолжить правку», нажатие на подложку и «назад» над вопросом возвращают к полям с прежним текстом.
    - Уход во время принятого сохранения закрывает экран без вопроса. Сохранение выполняется один раз и продолжается: успех не объявляется сообщением, а страница показывает сохранённые данные; отказ после ухода общая поверхность предъявляет один раз. Поздний результат не закрывает страницу намерения и другие страницы.
    - Проверки экрана подтверждают:
      - закрытие стрелкой и системным «назад» без вопроса, пока текст не изменён;
      - вопрос при изменённом тексте и возврат к полям каждым безопасным ответом;
      - «Отменить» после изменения описания: экран закрыт, страница показывает прежнее описание;
      - уход стрелкой во время сохранения без вопроса: команда одна, успех даёт новые данные на странице без сообщения, а отказ — одно сообщение общей поверхности при открытой странице намерения.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.4, 3.6.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/intention/presentation/edit/intention_edit_page_test.dart`.
  - **Размер:** M.

- [x] 3.8 Открывать экран изменения нажатием на название в шапке, только пока намерение свободно от изменяющей операции
  - **Критерии приёмки:**
    - По README `PageHead` и решению 10 дизайна название — кнопка: доступное нажатие вызывает обработчик потребителя, а диктор слышит переданное доступное название как кнопку и как заголовок второго уровня. Компонент принимает недоступность от потребителя: выключенная кнопка не вызывает обработчик и отражает недоступность в семантике. Вид, перенос и поля названия не меняются. Метка архива, строка пояснения и кнопка под названием не добавляются: их потребитель — шапка фазы 4.
    - Страница передаёт доступное название «Изменить название: …» с названием намерения на русском и английском. По требованию «Экран изменения намерения» и решению 3 дизайна вход недоступен, пока модель показывает занятость; перед открытием маршрута страница также проверяет актуальную занятость намерения в координаторе. Доступное нажатие открывает `IntentionEditRoute` над страницей, а закрытие экрана возвращает на неё.
    - Компонентные проверки в обеих темах подтверждают вызов обработчика только доступной кнопки, семантику доступности, кнопки и заголовка с доступным названием и перенос длинного названия без обрезки. Проверки страницы подтверждают доступное название на обоих языках, открытие экрана с названием намерения в поле и отсутствие перехода во время изменяющей операции, в том числе если модель страницы ещё не отразила занятость координатора.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/design_system/page_head_test.dart test/intention/presentation/details test/intention/presentation/edit`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.7 — экран закрывается по решению своей сессии.
  - **Предполагаемые файлы:** `lib/src/design_system/components/page_head.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/design_system/page_head_test.dart`, `test/intention/presentation/details/intention_details_head_test.dart`.
  - **Размер:** M.

- [x] 3.9 Показывать на странице намерения занятость, начатую экраном изменения, когда страница снова становится текущим маршрутом
  - **Критерии приёмки:**
    - По решению 3 дизайна координатор не сообщает о принятии чужой команды. Поэтому страница перечитывает занятость намерения в той же точке, где синхронизирует видимость статистики при смене текущего маршрута. Модель подробных данных обновляет признак выполнения, а блок тегов — доступность выбора и снятия тегов.
    - Пока сохранение, начатое на экране изменения, выполняется после ухода с экрана, изменяющие действия страницы, теги и вход в правку нажатием на название недоступны; повторное нажатие не открывает `IntentionEditRoute`. После завершения они снова доступны, а шапка показывает подтверждённое название.
    - Проверка страницы проходит путь: отправить новое название → уйти до результата → попытаться снова открыть правку нажатием на название. До результата действия, теги и вход в правку недоступны, экран изменения не открывается. После успеха повторный вход показывает новое название; изменение и сохранение только описания сохраняют это название. После отказа первого сохранения вход снова доступен с прежним подтверждённым текстом. Проверка использует управляемое завершение операции без задержек и измерения времени.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/tag/presentation/assignments`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.7 — уход во время сохранения; 3.8 — вход на экран со страницы.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/tag/presentation/assignments/tag_assignments_section.dart`, `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** M.

- [x] 3.10 Перевести сценарии, которые переименовывали намерение встроенной правкой, на экран изменения и добавить экран в матрицу страниц навигации
  - **Критерии приёмки:**
    - Сценарии жизненного цикла намерения, потока долговременных связей и сохранения состояния корневых страниц переименовывают намерение нажатием на название, экраном изменения и «Сохранить». Они сохраняют ожидания согласования каталога, соседства и параметров.
    - Проверка пакетов тегов держит незавершённую правку в модели экрана изменения вместо модели подробных данных и подтверждает, что пакет не меняет черновик. В `test/graph/presentation/package_consumers_test_support.dart` проба черновика получает название, описание и состояние операции из модели экрана изменения той же сессии, которую использует `tag_package_catalog_consumers_test.dart`, без чтения `IntentionDetailsLoaded.edit`.
    - Матрица страниц навигации содержит экран изменения намерения, открытый нажатием на название, с `panel: false`: на экране панели нет, а после его закрытия страница намерения снова показывает панель.
    - Эти файлы не используют ключи и методы встроенной правки.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/app/intention_app_lifecycle_test.dart test/app/long_term_relation_app_flow_test.dart test/app/navigation test/graph/presentation/tag_package_catalog_consumers_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.8.
  - **Предполагаемые файлы:** `test/app/intention_app_lifecycle_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/app/navigation/app_shell_state_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`, `test/graph/presentation/tag_package_catalog_consumers_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M — замена способа правки в сценариях механическая.

- [x] 3.11 Убрать из сценариев быстрого создания, сброса истории и раскладки проверки несохранённой встроенной правки на странице намерения
  - **Критерии приёмки:**
    - По изменённым требованиям быстрого создания и навигации правка идёт на странице-задаче, над которой быстрое создание и выбор пункта недоступны. Поэтому:
      - быстрое создание и история создания над глубокой страницей больше не вводят и не проверяют несохранённое название на странице намерения, а черновик формы связи ниже в истории проверяется как прежде;
      - сброс истории выбором пункта больше не вводит несохранённую правку на странице намерения, а закрытие формы связи без подтверждения проверяется как прежде;
      - сценарий раскладки встроенной правки над клавиатурой и панелью обычной страницы удалён вместе с предметом: раскладку экрана изменения проверяет 3.6;
      - сценарий недоступности страницы под диалогом удаления проверяет другой элемент управления страницы вместо кнопки правки.
    - Файлы сценариев не используют ключи встроенной правки.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/app/quick_creation test/app/navigation test/app/creation_flows_integration_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_failure_integration_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.8 — правка открывается экраном-задачей.
  - **Предполагаемые файлы:** `test/support/intention_creation_origin.dart`, `test/app/quick_creation/quick_creation_launcher_test.dart`, `test/app/quick_creation/quick_creation_launcher_test_support.dart`, `test/app/navigation/app_shell_pages_above_test.dart`, `test/app/navigation/ordinary_page_layout_scenarios.dart`, `test/app/navigation/app_shell_unnamed_page_scenarios.dart`.
  - **Размер:** M — в основном удаление.

- [x] 3.12 Убрать со страницы намерения кнопку правки и встроенную форму, а из модели подробных данных — правку и охрану наблюдения на её время
  - **Критерии приёмки:**
    - По решению 3 дизайна у `IntentionDetailsViewModel` нет `beginEditing`, `cancelEditing`, `changeTitle`, `changeDescription`, `saveChanges`, завершения изменения и охраны наблюдения на время правки. У `IntentionDetailsLoaded` нет поля правки, тип `IntentionDetailsEdit` удалён. Переходы готовности, архивирования, восстановления и удаления с их нынешним предъявлением отказов не меняются до фазы 4.
    - На странице нет кнопки «Изменить» и встроенной формы: правку открывает только нажатие на название. Строки, которые использовала только встроенная правка, удалены на обоих языках.
    - Проверки встроенной правки удалены из проверок страницы и модели подробных данных: поведение правки на новом месте подтверждают проверки экрана изменения и его модели. Остальные проверки страницы и модели сохраняют ожидания. В `test/app/intention_statistics_app_flow_test.dart` возвращение на «Обзор» подтверждается видимой меткой описания (`detailsDescriptionLabel`) вместо удаляемой кнопки `detailsEditAction`; остальные ожидания сценария статистики сохраняются.
  - **Проверка:**
    - `mise run codegen` — провайдеры и локализация пересозданы.
    - `mise exec --no-deps -- flutter test test/intention/presentation test/graph/presentation test/tag/presentation test/app --exclude-tags=flutter_process`.
    - `rg -nw 'beginEditing|cancelEditing|saveChanges|IntentionDetailsEdit' lib test` и `rg -n 'intention-details-edit' lib test` ничего не находят.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.9 — занятость после возвращения показывается без встроенной правки; 3.10, 3.11 — сценарии больше не используют встроенную правку.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/intention/presentation/details/intention_details_state.dart`, `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированный код;
    - проверки: `test/intention/presentation/details/intention_details_page_test.dart`, `test/intention/presentation/details/intention_details_view_model_test.dart`, `test/app/intention_statistics_app_flow_test.dart`.
  - **Размер:** M — в основном удаление.

- [x] 3.13 Подтвердить готовность третьей фазы: правка названия и описания идёт на отдельном экране без сообщения об успехе
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» третьей фазы:
      - требования экрана изменения и предъявления результата правки выполняются;
      - экран занимает место страницы-задачи в навигации, а прежние проверки встроенной правки заменены проверками экрана.
    - На странице намерения нет кнопки правки и встроенной формы: правку открывает нажатие на название. Успех изменения не объявляется сообщением, а занятость после возвращения с экрана видна странице.
    - Результаты проверок и путь к APK сообщены в сессии. Сравнение с макетом и ручная проверка на устройстве остаются за пользователем и не блокируют готовность фазы.
  - **Проверка:**
    - `rg -nw 'beginEditing|cancelEditing|saveChanges|IntentionDetailsEdit|detailsSaved' lib test` и `rg -n 'intention-details-edit' lib test` ничего не находят.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - нажатие на название открывает экран без нижней панели с курсором в конце названия, «Сохранить» в панели выключена до изменения;
      - описание растёт до тринадцати строк и дальше прокручивается внутри, клавиатура не закрывает поля;
      - сохранение возвращает на страницу с новым текстом без сообщения, а слишком длинное название объясняется у поля;
      - вопрос «Отменить изменения?» при уходе с изменённым текстом: вид, «Отменить», «Продолжить правку» и нажатие на подложку;
      - смена системной темы на экране сохраняет введённый текст.
  - **Зависимости:** 3.1–3.12.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

- [x] 3.14 Не открывать экран изменения, пока страница намерения перечитывает подробные данные после подтверждённого изменения этого намерения
  - **Критерии приёмки:**
    - По требованию «Экран изменения намерения» и решению 3 дизайна новая сессия экрана изменения получает последние подтверждённые название и описание. Координатор снимает занятость до того, как модель подробных данных примет снимок после подтверждённого изменения. Поэтому с момента, когда модель начинает перечитывание по завершению, затрагивающему это намерение, и до принятия снимка не старше ревизии этого изменения вход в правку нажатием на название недоступен. Недоступность видна в шапке и проверяется перед открытием `IntentionEditRoute`. Шапка в это время показывает прежнее подтверждённое название.
    - После принятия свежего снимка вход снова доступен и открывает экран с новыми названием и описанием. Если перечитывание заканчивается отказом, страница показывает состояние отказа по нынешним правилам, и экран изменения из устаревшего текста не открывается.
    - Проверка страницы с управляемой выдачей снимков: сохранить новое название с экрана изменения, дождаться закрытия экрана до прихода нового снимка и нажать на название. Экран изменения не открывается. После прихода снимка нажатие открывает экран с новым названием, а изменение и сохранение только описания отправляют новое название. Проверка обходится без задержек и измерения времени.
  - **Проверка:**
    - `mise run codegen`, если меняются аннотированные провайдеры или состояние.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/intention/presentation/edit test/app/intention_app_lifecycle_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.9 — занятость после возвращения с экрана; 3.12 — модель подробных данных без встроенной правки.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_state.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** S.

- [x] 3.15 Не принимать перенос строки в названии на экране изменения и в панели создания намерения
  - **Критерии приёмки:**
    - По требованию «Ввод названия намерения без переносов строк» растущее поле вида `name` не принимает перенос строки. Клавиатура названия не предлагает перенос, клавиша ввода переводит фокус в следующее поле, а `\r\n`, `\r` и `\n` во вставленном тексте заменяются одним пробелом каждый. Название по-прежнему визуально переносится и растёт. Поле вида `text` принимает переносы строк, как прежде.
    - На экране изменения клавиша ввода в названии переводит фокус в описание и не меняет название. В панели создания название тем же правилом заменяет вставленные переносы; переход клавишей ввода к описанию сохраняется. Правило замены задано в одном месте и используется обоими полями.
    - Нормализация и проверка названия в домене, импорт и сохранённые данные не меняются: название с переносами, полученное другим путём, показывается как прежде.
    - Проверки:
      - компонентная — у растущего поля `name` вставка «Бегать\nпо утрам» и «Бегать\r\nпо утрам» даёт «Бегать по утрам», а у поля `text` перенос сохраняется;
      - экрана изменения — клавиша ввода в названии оставляет название прежним и переводит фокус в описание;
      - панели создания — вставка текста с переносом в название даёт название через пробел.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/text_field_test.dart test/intention/presentation/edit test/intention/presentation/editor`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.2 — растущее поле `name`; 3.6 — экран изменения.
  - **Предполагаемые файлы:** `lib/src/design_system/components/text_field.dart`, `lib/src/intention/presentation/edit/intention_edit_page.dart`, `lib/src/intention/presentation/editor/intention_editor_page.dart`, `test/design_system/text_field_test.dart`, `test/intention/presentation/edit/intention_edit_page_test.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`.
  - **Размер:** S.

- [x] 3.16 Прокручивать экран изменения к отказу сохранения, чтобы он был виден без ручной прокрутки
  - **Критерии приёмки:**
    - По требованию «Экран изменения намерения» и разделу «Как показываются отказы» решения 5 дизайна новый отказ на открытом экране становится видимым без ручной прокрутки. После кадра с отказом экран прокручивает содержимое к его сообщению: к `Notice` над полями для общего отказа или к ошибке под полем названия для отказа проверки поля.
    - Предъявление по-прежнему подтверждается свидетельством кадра `OperationFailurePresentation`. После прокрутки отказ получает экран, а не общая поверхность. Введённый текст и позиция курсора не меняются.
    - Проверки экрана при тексте 2× и открытой клавиатуре, после ввода длинного описания, когда начало экрана вне видимой части:
      - отказ хранилища после «Сохранить» — `Notice` попадает в видимую часть, его текст есть в дереве семантики, общая поверхность сообщения не показывает, введённый текст сохранён;
      - название из 256 символов — объяснение длины под полем названия попадает в видимую часть без ручной прокрутки.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.6 — экран изменения с местами отказов.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_page.dart`, `test/intention/presentation/edit/intention_edit_page_test.dart`.
  - **Размер:** S.

- [x] 3.17 Снимать фокус с полей экрана изменения при новом отказе сохранения, чтобы возвращение клавиатуры не уводило сообщение из видимой части
  - **Критерии приёмки:**
    - По требованию «Экран изменения намерения» и разделу «Как показываются отказы» решения 5 дизайна новый отказ на открытом экране остаётся видимым и доступным экранному диктору после того, как улягутся клавиатура и раскладка. При новом отказе экран снимает фокус с полей названия и описания до того, как они снова станут редактируемыми, а после кадра прокручивает к сообщению, как в 3.16. Клавиатура после отказа не возвращается.
    - Предъявление по-прежнему подтверждается свидетельством кадра `OperationFailurePresentation`, и отказ получает экран, а не общая поверхность. Введённый текст и выделение в полях сохраняются, а нажатие на поле снова даёт его фокус и клавиатуру.
    - Проверка экрана при тексте 2× и открытой клавиатуре, после ввода длинного описания, когда начало экрана вне видимой части. Клавиатура закрывается на время принятого сохранения, затем приходит отказ хранилища. После этого ни одно поле не в фокусе, подключение ввода закрыто, `Notice` остаётся в видимой части и принимает нажатия, его текст есть в дереве семантики, общая поверхность сообщения не показывает, а введённый текст сохранён.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 3.16 — прокрутка к отказу сохранения.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_page.dart`, `test/intention/presentation/edit/intention_edit_page_test.dart`.
  - **Размер:** XS.

## Phase 4: Обзор, шапка и параметры намерения по дизайну

- [x] 4.1 Отдавать общей поверхности отказы переходов состояния и удаления, начатых на странице намерения, убрав их инлайн-показ и повтор
  - **Критерии приёмки:**
    - По решениям 3 и 4 дизайна у `IntentionDetailsViewModel` нет `retryStateChange` и права предъявления отказа, а у `IntentionDetailsLoaded` — состояния перехода с отказом: тип `IntentionDetailsStateChange` удалён. Признак выполнения остаётся для недоступности элементов управления. Модель освобождает право инициатора через `releaseInitiatorPresentation` сразу при принятии готовности, архивирования, восстановления и удаления. Поэтому отказ любой из этих команд общая поверхность предъявляет один раз, а страница показывает последнее подтверждённое состояние.
    - Ответ `AlreadyRunning` по-прежнему делает модель занятой. Ответ `GraphCommandCoordinatorDraining` во время замены графа ничего не начинает и ничего не показывает: состояние и доступность элементов не меняются, повтор — повторное действие пользователя. `delete()` по-прежнему возвращает успех только собственной принятой команды, а страница закрывает себя, только если её маршрут текущий.
    - Со страницы убраны инлайн-сообщение отказа перехода и кнопка повтора. Прежние кнопки готовности, архивирования, восстановления и удаления остаются до замены в следующих задачах фазы.
    - Проверки модели подтверждают:
      - освобождение права при принятии команды;
      - предъявление отказа оболочкой при открытой странице;
      - занятость после `AlreadyRunning`;
      - отсутствие команды и изменения состояния после `Draining`.

      Проверки страницы и сценарии, ожидавшие инлайн-отказ или кнопку повтора, ожидают одно сообщение общей поверхности. Повтор в них — повторное нажатие с новым токеном.
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы, если меняется аннотированная модель.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/app/long_term_relation_app_flow_test.dart test/app/navigation/app_shell_operation_reset_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/src/intention/presentation/details/intention_details_state.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`;
    - проверки: `test/intention/presentation/details/intention_details_view_model_test.dart`, `test/intention/presentation/details/intention_details_page_test.dart`, `test/intention/presentation/details/intention_details_delete_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/app/navigation/app_shell_operation_reset_test.dart`.
  - **Размер:** M.

- [x] 4.2 Не объявлять сообщением успех изменения готовности, архивирования и восстановления, отдавая их отказ сразу общей поверхности по ADR-0016
  - **Критерии приёмки:**
    - По решению 4 дизайна `GraphCommandCoordinator` применяет к `EnableIntentionReadiness`, `DisableIntentionReadiness`, `ArchiveIntention` и `RestoreIntention` политику «только отказ». Политику задаёт вид операции в координаторе:
      - успех публикуется в канал завершений для согласования данных, но не образует права предъявления и не оставляет непредъявленной записи;
      - отказ сразу принадлежит общей поверхности, без права инициатора.

      Создание и удаление сохраняют политику по умолчанию, изменение названия и описания — «успех без сообщения».
    - У `GraphOperationPresenter` нет текстов успеха этих операций: строки `detailsReadinessEnabled`, `detailsReadinessDisabled`, `detailsArchivedSuccess` и `detailsRestoredSuccess` удалены на обоих языках. Тексты отказов сохраняются. Модель подробных данных освобождает право инициатора при принятии только у удаления: у остальных её команд этого права нет.
    - Проверки координатора закрепляют политику для каждой из четырёх операций: успех не выдаётся ни инициатору, ни оболочке и не оставляет непредъявленной записи, а отказ оболочка предъявляет один раз при открытой странице. Сценарии, где успех этих операций служил видимым сообщением, делятся по предмету проверки:
      - если предмет — успех одной из четырёх операций, сценарий подтверждает отсутствие сообщения и сохраняет остальные ожидания;
      - если успех лишь занимает или показывает общую поверхность, как в проверках положения и очереди сообщений над панелью и создания при занятой поверхности, сценарий переходит на операцию, успех которой по-прежнему объявляется, и сохраняет все ожидания об общей поверхности.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана без удалённых строк.
    - `mise exec --no-deps -- flutter test test/intention test/graph/application test/graph/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.1 — страница больше не забирает отказ себе.
  - **Предполагаемые файлы:**
    - `lib/src/graph/application/graph_command_coordinator.dart`, `lib/src/graph/presentation/graph_operation_presenter.dart`, `lib/src/intention/presentation/details/intention_details_view_model.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/operation/intention_command_coordinator_test.dart`, `test/graph/presentation/graph_operation_presenter_test.dart`, `test/app/navigation/app_shell_state_test.dart`, `test/app/navigation/app_shell_layout_test.dart`, `test/app/creation_flows_integration_test.dart`.
  - **Размер:** M.

- [x] 4.3 Расширить `TextField` режимом сохранённого текста, который показывает текст целиком и открывает его правку
  - **Критерии приёмки:**
    - По README `TextField` режим сохранённого текста — кнопка, а не поле:
      - плоскость `fill` высотой не меньше `tap-min` с полями 11 и `space-3`;
      - текст стилем `field` целиком, с сохранёнными переносами строк и без обрезки;
      - у пустого текста — приглашение цвета `muted` в одну строку.

      Доступное название кнопки передаёт потребитель.
    - Компонент принимает недоступность от потребителя: недоступная кнопка не вызывает обработчик и отражает недоступность в семантике. Приглушённый текст `muted` не добавляется: его потребитель — заметка выполненного дневного выбора.
    - Компонентные проверки в обеих темах подтверждают:
      - плоскость, поля и стиль;
      - перенос длинного текста и сохранение переносов строк без обрезки;
      - приглашение у пустого текста;
      - вызов обработчика только доступной кнопкой;
      - семантику кнопки с доступным названием и недоступностью;
      - отсутствие переполнения при увеличенном тексте.

      Проверки растущего и однострочного поля сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/text_field_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/text_field.dart`, `test/design_system/text_field_test.dart`.
  - **Размер:** S.

- [x] 4.4 Открывать экран изменения намерения с курсором в конце названия или описания по типизированной цели поля
  - **Критерии приёмки:**
    - По требованию «Экран изменения намерения» маршрут `IntentionEditRoute` принимает вместе с `IntentionId` типизированное поле для курсора: название или описание. Без явной цели курсор стоит в конце названия, как сейчас. Цель описания ставит курсор в конец сохранённого описания, а при его отсутствии — в пустое поле описания.
    - Остальное поведение экрана не меняется: сохранённые значения, недоступная «Сохранить» до изменения, закрытие и отказы.
    - Проверки экрана подтверждают курсор в конце описания и недоступную «Сохранить» для цели описания, курсор в пустом описании и прежний курсор в конце названия без явной цели.
  - **Проверка:**
    - `mise run codegen` — маршруты пересозданы.
    - `mise exec --no-deps -- flutter test test/intention/presentation/edit test/app/routing`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/edit/intention_edit_page.dart`, `lib/src/app/routing/app_router.dart` и сгенерированные маршруты, `test/intention/presentation/edit/intention_edit_page_test.dart`.
  - **Размер:** S.

- [x] 4.5 Показывать описание первым на «Обзоре» и открывать его правку нажатием на описание или приглашение его добавить
  - **Критерии приёмки:**
    - По требованию «Обзор намерения» и решению 10 дизайна описание — первая часть вкладки «Обзор»: сохранённый текст `TextField` из 4.3 в 4 под вкладками, с боковыми полями страницы. Оно показывается целиком с сохранёнными переносами строк; без описания на его месте стоит приглашение «Добавить описание». Доступное название — «Изменить описание: …» с текстом описания или приглашение; тексты на русском и английском.
    - По требованию «Экран изменения намерения» и решению 3 дизайна вход доступен по тому же правилу, что название в шапке. Он недоступен, пока модель показывает занятость или ждёт снимок после подтверждённого изменения, а перед открытием маршрута страница проверяет актуальную занятость в координаторе. Доступное нажатие открывает экран из 4.4 с курсором в конце описания.
    - Прежнее поле «Описание» со строкой «Нет описания» удалено вместе со строками, которые больше нигде не используются. Поля готовности и состояния архива остаются до своих задач фазы.
    - Проверки страницы подтверждают описание с переносами строк, приглашение у намерения без описания, сценарий «Нажатие на описание открывает его изменение» и отсутствие перехода, пока выполняется изменяющая операция. Сценарии, которые находили «Обзор» или пустое описание по прежнему полю, опираются на новое описание.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/app/intention_statistics_app_flow_test.dart test/app/intention_creation_sheet_integration_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.3, 4.4.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_details_overview_test.dart` (новый), `test/app/intention_statistics_app_flow_test.dart`, `test/app/intention_creation_sheet_integration_test.dart`.
  - **Размер:** M.

- [x] 4.6 Добавить в дизайн-систему плитки выбора `OptionTiles` со значком, названием, пояснением и выбранным состоянием
  - **Критерии приёмки:**
    - По README `OptionTiles` и решению 11 дизайна компонент показывает две плитки, переданные потребителем: значок, название и пояснение. Выбранную плитку, обработчик выбора и доступное название пары задаёт потребитель. Предметных типов в компоненте нет (ADR-0030).
      - Две равные колонки в `space-2`, обе высотой с более высокую; поля `space-3`, углы `radius-lg`. Круглая плитка значка 32 со значком 20, название стилем `section` в `space-2` после неё, пояснение в 6 ниже стилем `hint` цвета `muted`.
      - Выбранная плитка — плоскость `fill`, плитка значка `accent` со значком `on-accent` и отметка `accent` 18 в конце. Невыбранная — без плоскости, с внутренним кольцом `hairline` и плиткой значка `fill` со значком `ink`.
      - Нажатие на выбранную плитку ничего не делает. Компонент принимает недоступность от потребителя: недоступные плитки не вызывают обработчик.
    - Каждая плитка для экранного диктора — кнопка с выбранным состоянием внутри пары с доступным названием.
    - Компонентные проверки в обеих темах подтверждают раскладку и равную высоту, цвета выбранной и невыбранной плиток, вызов обработчика только невыбранной доступной плиткой, семантику выбора и недоступности, перенос длинных слов и отсутствие переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/option_tiles_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/option_tiles.dart` (новый), `test/design_system/option_tiles_test.dart` (новый).
  - **Размер:** S.

- [x] 4.7 Выбирать готовность к действию плитками «Намерение» и «Действие» на «Обзоре» без отдельного подтверждения
  - **Критерии приёмки:**
    - По требованию «Явный выбор готовности к действию» и решениям 3 и 10 дизайна плитки из 4.6 стоят в 12 под описанием. «Намерение» поясняет, что намерение может быть любого размера и занимать больше одного дня. «Действие» называет выполнимость за один день и понятность того, что делать. Тексты на русском и английском. Страница сопоставляет `IntentionReadiness` с выбранной плиткой.
    - Нажатие на невыбранную плитку сразу вызывает `enableReadiness` или `disableReadiness`. Плитки доступны у активного и архивированного намерения и недоступны, пока выполняется изменяющая операция.
    - Прежние поле готовности, кнопки её включения и выключения и диалог подтверждения удалены вместе со строками, которые больше нигде не используются.
    - Проверки страницы подтверждают:
      - сценарий «Включение готовности плиткой» с типом «Действие» в верхней панели;
      - сценарий «Обратимое выключение готовности» плиткой «Намерение»;
      - сценарий «Успех изменения готовности не объявляется сообщением»;
      - доступность плиток у архивированного намерения и их недоступность во время операции.

      Сценарии, которые меняли или сверяли готовность прежними элементами, используют плитки.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/app/intention_app_lifecycle_test.dart test/app/intention_creation_sheet_integration_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.2 — успех изменения готовности не объявляется; 4.5 — описание над плитками; 4.6.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_details_overview_test.dart`, `test/intention/presentation/details/intention_details_page_test.dart`, `test/app/intention_app_lifecycle_test.dart`, `test/app/intention_creation_sheet_integration_test.dart`.
  - **Размер:** M.

- [x] 4.8 Перенести из макетов значки «⋯», малого крестика и восстановления из архива
  - **Критерии приёмки:**
    - По решению 11 дизайна значки переносятся из макетов `context/doable-design/design/` в `lib/src/design_system/icons/` по правилам его README: SVG, запись происхождения и значения `DoableIconData`. Их потребители в этой фазе — кнопка параметров в верхней панели, крестик чипа тега и пункт «Восстановить из архива» в параметрах.
    - Эталон каталога иконок пересоздан, и в нём добавлены только эти три значка.
  - **Проверка:**
    - Эталон пересоздан `mise exec --no-deps -- flutter test --update-goldens test/design_system/doable_icon_test.dart`.
    - `mise exec --no-deps -- flutter test test/design_system/doable_icon_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/doable_icon.dart`, три новых SVG в `lib/src/design_system/icons/assets/`, `lib/src/design_system/icons/README.md`, `test/design_system/doable_icon_test.dart`, `test/design_system/goldens/doable_icons.png`.
  - **Размер:** S.

- [x] 4.9 Расширить `TagChip` чипом формы размера md с крестиком снятия
  - **Критерии приёмки:**
    - По README `TagChip` чип md — пилюля `fill` высотой не меньше `control-height-sm` (36) с углами 18. Точка тега 8 стоит в 6 перед названием, название — стилем `row` цвета `ink`. Длинное название переносится внутри пилюли без обрезки, а пилюля не шире строки.
    - Крестик — значок малого крестика 16 цвета `muted` в области нажатия шириной 34 в конце пилюли. Его доступное название передаёт потребитель. Компонент принимает недоступность крестика от потребителя: недоступный крестик не вызывает обработчик и отражает недоступность в семантике. Потребитель может передать ключ крестика, как `closeKey` у `TopBar`: ключ стоит на области нажатия крестика, а не на всём чипе. Чип md без крестика не добавляется: у него нет потребителя.
    - Компонентные проверки в обеих темах подтверждают размеры, цвета и стили, перенос длинного названия без обрезки и переполнения при увеличенном тексте, вызов обработчика только доступным крестиком, в том числе нажатием по переданному ключу, его доступное название и недоступность. Проверки малого чипа сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/tag_chip_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.8 — малый крестик.
  - **Предполагаемые файлы:** `lib/src/design_system/components/tag_chip.dart`, `test/design_system/tag_chip_test.dart`.
  - **Размер:** S.

- [x] 4.10 Добавить в дизайн-систему строку `AddRow` с заголовком и блок тегов `TagsSection`
  - **Критерии приёмки:**
    - По README `AddRow` строка с заголовком высотой не меньше `tap-min`. Заголовок — стилем `row` цвета `ink` в `space-1` от края, справа — «Добавить» стилем `section` цвета `accent` с плюсом 18. Область нажатия «Добавить» высотой `tap-min` выходит на 6 за правый край содержимого, а слово кончается в 4 от него. Подпись и доступное название «Добавить» передаёт потребитель. Вариант с подсказкой не добавляется: его потребитель — вкладка «Выборы» фазы 5.
    - Потребитель может выключить «Добавить» в `AddRow` и `TagsSection`. Выключенное «Добавить» остаётся на месте без сдвига раскладки, а слово и плюс окрашены `grip`, как выключенная текстовая кнопка по README `Button`. Нажатие не вызывает обработчик, а семантика объявляет недоступность. Потребитель может передать ключ «Добавить», как `closeKey` у `TopBar`: ключ стоит на области нажатия «Добавить», а не на всей строке или блоке.
    - По README `TagsSection` блок — `AddRow` с заголовком «Теги» и переданные потребителем чипы под ней. Ряды чипов переносятся с промежутком `space-2` по обеим осям, под последним рядом остаётся 6. Без чипов блок состоит из одной шапки.
    - Компонентные проверки в обеих темах подтверждают раскладку и стили строки, область нажатия и доступное название «Добавить», вызов обработчика нажатием по переданному ключу и выключенное «Добавить»: цвет `grip`, неизменную раскладку, отсутствие вызова обработчика и недоступность в семантике. Для блока они подтверждают передачу выключенности и ключа «Добавить» его строке, перенос чипов, блок без чипов и отсутствие переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/add_row_test.dart test/design_system/tags_section_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/add_row.dart` (новый), `lib/src/design_system/components/tags_section.dart` (новый), `test/design_system/add_row_test.dart` (новый), `test/design_system/tags_section_test.dart` (новый).
  - **Размер:** M.

- [x] 4.11 Рисовать теги намерения на «Обзоре» блоком `TagsSection` с чипами, которые снимаются крестиком
  - **Критерии приёмки:**
    - По решению 10 дизайна `TagAssignmentsSection` рисует `TagsSection` из 4.10 с чипами md из 4.9 в порядке назначения, а блок стоит в 8 под плитками. Логика снятия, занятости и чтения не меняется. «Добавить» и крестик выключаются в тех же условиях, что прежние кнопки, через состояния компонентов из 4.9 и 4.10. Ключи «Добавить» (`tag-assignments-choose`), крестика (`tag-assignment-remove-…`) и чипа (`tag-assignment-row-…`) сохраняются ради существующих проверок. Ключи «Добавить» и крестика передаются компонентам как ключи их областей нажатия, ключ чипа стоит на чипе.
    - «Добавить» открывает панель тегов. Её доступное название перечисляет назначенные теги и говорит, что их можно добавить или убрать, а без тегов — «Добавить теги». Крестик сразу снимает тег, его доступное название называет тег. Без тегов блок состоит из одной шапки, без строки о пустом списке. Архивированное намерение сохраняет «Добавить» и крестики.
    - Строки состояния чтения и снятия стоят под блоком в виде `ListState` и `Notice`. Тексты на русском и английском; строки, которые больше нигде не используются, удалены.
    - Проверки блока тегов, его доступности и тегов на странице подтверждают чипы и шапку, снятие крестиком, недоступность «Добавить» и крестиков во время операции намерения, доступные названия и состояния чтения. Сценарии тегов приложения проходят с сохранёнными ключами.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/tag/presentation test/intention/presentation/details test/app/tag_assignment_app_flow_test.dart test/app/tag_assignment_app_lifecycle_test.dart test/app/tag_app_flow_test.dart test/app/intention_tag_search_app_flow_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.7 — плитки над блоком; 4.9, 4.10.
  - **Предполагаемые файлы:**
    - `lib/src/tag/presentation/assignments/tag_assignments_section.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/tag/presentation/assignments/tag_assignments_section_test.dart`, `test/tag/presentation/tag_accessibility_test.dart`, `test/intention/presentation/details/intention_details_tags_test.dart`.
  - **Размер:** M.

- [x] 4.12 Добавить в дизайн-систему строку дат `DatesLine`
  - **Критерии приёмки:**
    - По README `DatesLine` строка получает от потребителя готовые подписи и метки даты создания и, если она есть, даты изменения. Строка одна, стилем `hint` цвета `muted` с табличными цифрами, по левому краю. Две части разделены средней точкой, без даты изменения строка называет одну дату.
    - Форматирование дат и решение, показывать ли дату изменения, остаются у потребителя (ADR-0030).
    - Компонентные проверки в обеих темах подтверждают текст одной и двух дат, стиль и цвет, перенос без переполнения при увеличенном тексте и прочтение экранным диктором.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/dates_line_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/dates_line.dart` (новый), `test/design_system/dates_line_test.dart` (новый).
  - **Размер:** XS.

- [x] 4.13 Закрывать «Обзор» строкой дат создания и изменения намерения по местной дате устройства
  - **Критерии приёмки:**
    - По требованию «Обзор намерения» и решению 10 дизайна страница форматирует даты через `intl` по локали интерфейса и передаёт `DatesLine` из 4.12 готовые подписи:
      - день сохранённого момента определяется по местной дате устройства;
      - дата — день и сокращённый месяц, а год добавляется только к дате не текущего года;
      - дата изменения показывается, только если её день отличается от дня создания.

      Текущий год берётся из местного дня, за которым уже следит страница, и пересчитывается при его смене. Метки «Создано» и «Изменено» — на русском и английском.
    - Строка стоит в 10 под блоком тегов и в `space-1` от края содержимого, под ней остаётся 16.
    - Проверки форматирования подтверждают одну дату для одного дня, две даты для разных дней, сценарий «Даты разных лет» и обе локали. Проверка страницы подтверждает сценарий «Обзор только что созданного намерения»: приглашение «Добавить описание», выбранная плитка «Намерение», «Теги» с «Добавить» без чипов и только сегодняшняя дата создания.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.5, 4.7, 4.11 — части «Обзора» над строкой; 4.12.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_dates.dart` (новый), `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_dates_test.dart` (новый), `test/intention/presentation/details/intention_details_overview_test.dart`.
  - **Размер:** M.

- [x] 4.14 Расширить `Badge` меткой со словом и значком архива, а `Button` — тихой кнопкой на всю ширину
  - **Критерии приёмки:**
    - По README `Badge` метка со словом тона `muted` лежит на плоскости `fill`. Значок архива 13 с линией 2 стоит в `space-1` перед словом; левое поле 5, остальные поля 1 и 7, углы `radius-xs`; слово стилем `caption` в одну строку. Экранный диктор читает слово; метка не кнопка. Тон `accent` и слово без значка не добавляются: у них нет потребителя в этой фазе.
    - По README `Button` тихая кнопка может растягиваться на ширину контейнера: высота `control-height` (40) в строке нажатия `tap-min`. Прежняя тихая кнопка по ширине подписи не меняется.
    - Компонентные проверки в обеих темах подтверждают размеры, цвета и стили метки и её прочтение диктором. Для тихой кнопки на всю ширину они подтверждают ширину, высоту и область нажатия, выключенное состояние и перенос длинной подписи при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/badge_test.dart test/design_system/button_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/badge.dart`, `lib/src/design_system/components/button.dart`, `test/design_system/badge_test.dart`, `test/design_system/button_test.dart`.
  - **Размер:** S.

- [x] 4.15 Расширить `PageHead` приглушённым названием, слотом метки, строкой пояснения и слотом кнопки
  - **Критерии приёмки:**
    - По README `PageHead`:
      - приглушённое название рисуется цветом `muted`;
      - метка из слота стоит на строке названия в 8 после него по центру строки, а если название заполняет строку, — на своей строке в 6 ниже;
      - строка пояснения стилем `hint` стоит в 6 под названием;
      - кнопка из слота растянута на ширину шапки и стоит в 10 под текстом.

      Поля 2 сверху и 6 под последней частью не меняются, как и название-кнопка с доступным названием и недоступностью. Текст пояснения передаёт потребитель: компонент не встраивает текст по умолчанию.
    - Компонентные проверки в обеих темах подтверждают положение метки на строке названия и её перенос, отступы пояснения и кнопки, цвет приглушённого названия, отсутствие обрезки и переполнения при увеличенном тексте и прежнюю семантику названия. Проверки шапки без новых частей сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/page_head_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/page_head.dart`, `test/design_system/page_head_test.dart`.
  - **Размер:** S.

- [x] 4.16 Показывать в шапке архивированного намерения метку «Архив», пояснение и восстановление из архива
  - **Критерии приёмки:**
    - По требованию «Страница намерения и её вкладки» и решению 10 дизайна шапка архивированного намерения показывает:
      - приглушённое название;
      - метку «Архив» из 4.14;
      - строку о том, что архивированные намерения остаются в сохранённых путях и не предлагаются в новых;
      - тихую кнопку «Восстановить из архива» на всю ширину.

      Тексты на русском и английском. Шапка активного намерения не меняется.
    - Кнопка сразу вызывает `restore` без подтверждения и недоступна, пока выполняется изменяющая операция. После восстановления шапка снова показывает активное намерение.
    - Прежнее поле состояния архива на «Обзоре» удалено вместе со строками, которые больше нигде не используются.
    - Проверки шапки подтверждают сценарий «Шапка архивированного намерения», восстановление кнопкой с возвратом к шапке активного намерения без сообщения общей поверхности и недоступность кнопки во время операции.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.2 — успех восстановления не объявляется; 4.14, 4.15.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/intention/presentation/details/intention_details_head_test.dart`.
  - **Размер:** M.

- [x] 4.17 Добавить в `TopBar` со стрелкой «назад» одну кнопку-иконку справа
  - **Критерии приёмки:**
    - По README `TopBar` панель со стрелкой «назад» и заголовком со значком может нести справа одну кнопку-иконку, переданную потребителем. Её область нажатия 44 стоит в `space-2` от края, значок 24 — цвета `ink`, доступное название передаёт потребитель. Заголовок остаётся по центру и не шире панели без 64 с каждой стороны. Удержание стрелки, значок темы 22 и действие у остальных вариантов панели не добавляются: у них нет потребителя.
    - Компонентные проверки в обеих темах подтверждают положение и размер кнопки, вызов обработчика, доступное название, центр и обрезку длинного заголовка рядом с ней. Прежние варианты панели не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/top_bar_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/top_bar.dart`, `test/design_system/top_bar_test.dart`.
  - **Размер:** S.

- [x] 4.18 Добавить опасный тон `OptionRow` и лист параметров `OptionsMenu`, который возвращает выбранный пункт после закрытия
  - **Критерии приёмки:**
    - По README `OptionRow` опасная строка — плитка `danger-soft` со значком `danger` и название `danger`, а пояснение остаётся `muted`. Выключенная строка, в том числе опасная, рисуется плиткой `fill` со значком и названием `grip`, пояснение называет причину, а нажатия строка не принимает.
    - По README `OptionsMenu` и решению 10 дизайна лист параметров — `Sheet` с заголовком вида предмета и без строки пояснения. Имя маршрута для диктора — этот заголовок, как у прочих листов; отдельного доступного названия нет, и `Sheet` не меняется. Пункты — строки `OptionRow` со значком в переданном порядке. Лист открывается через `showDoableSheet` над корневым навигатором (ADR-0032).
      - Выбор доступного пункта закрывает лист и возвращает этот пункт вызывающему после закрытия. Поэтому действие начинается уже без открытого листа (ADR-0042).
      - Закрытие без выбора возвращает отсутствие выбора.

      Параметры выделения и лист «Назад к…» не добавляются: у них нет потребителя.
    - Компонентные проверки в обеих темах подтверждают:
      - цвета опасной строки, вид выключенной опасной строки с причиной и её недоступность;
      - заголовок листа, который называет его маршрут, и порядок пунктов;
      - возврат выбранного пункта после закрытия и отсутствие выбора при закрытии затемнением и «назад»;
      - отсутствие переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/option_row_test.dart test/design_system/options_menu_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/option_row.dart`, `lib/src/design_system/components/options_menu.dart` (новый), `test/design_system/option_row_test.dart`, `test/design_system/options_menu_test.dart` (новый).
  - **Размер:** M.

- [x] 4.19 Открывать кнопкой «⋯» в верхней панели параметры намерения: изменить, архивировать или восстановить с пояснением и удалить
  - **Критерии приёмки:**
    - По требованию «Параметры намерения на его странице» и решению 10 дизайна после получения подробных данных верхняя панель несёт кнопку «⋯» из 4.17 с доступным названием «Параметры намерения». При загрузке и отказе чтения её нет. Кнопка открывает лист «Намерение» из 4.18. Сборщик меню в приложении сопоставляет состояние намерения и `IntentionDetails.relationCounts` последнего принятого снимка с пунктами:
      - «Изменить» открывает экран изменения с курсором в конце названия. Вход подчиняется правилу доступности правки, а перед открытием проверяется занятость в координаторе.
      - «Архивировать» поясняет, что связи архивируются вместе с намерением, если `active > 0`, а иначе — что оно останется в сохранённых путях и не будет предлагаться в новых.
      - У архивированного намерения вместо него стоит «Восстановить из архива». Оно поясняет, что связи останутся в архиве до отдельного восстановления, если `longTermTotal > 0`, а иначе — что новые пути снова смогут его использовать.
      - «Удалить» в опасном тоне при `total == 0` поясняет: «Его теги сохранятся» / «Its tags stay». При `total > 0` оно выключено, а его причина выбирается по `longTermTotal` и `dailyTotal`: сначала удалить связи, дневные выборы или и то, и другое.

      Пока выполняется изменяющая операция, все пункты недоступны, в том числе в открытом листе, и поясняют: «Дождитесь окончания текущего изменения» / «Wait for the current change to finish». Исключение — «Удалить» при `total > 0`: оно сохраняет причину по связям и дневным выборам. Тексты на русском и английском.
    - Выбор закрывает лист и выполняет действие. Архивирование и восстановление выполняются сразу. «Удалить» открывает `showConfirmDialog` «Удалить намерение?» с опасной кнопкой и пояснением, что намерение безвозвратно удаляется вместе с описанием, а его теги сохраняются. После подтверждения и собственного успеха страница закрывается, если её маршрут текущий.
    - Прежний ряд кнопок остаётся до перевода проверок и удаляется в 4.22.
    - Проверки сборщика подтверждают пояснения при наличии и отсутствии связей, пояснение доступного удаления, причину выключенного удаления для связей любого архивного состояния, для дневных выборов и для обоих, а также недоступность всех пунктов во время операции с пояснением об ожидании и сохранённой причиной выключенного удаления при `total > 0`. Проверки страницы подтверждают:
      - сценарий «Архивирование из параметров» с архивным состоянием в шапке;
      - сценарий «Отказ архивирования со страницы показан общим сообщением»;
      - «Изменить» с курсором в названии и отсутствие перехода во время изменяющей операции;
      - сценарии «Подтверждённое удаление активного намерения» с закрытием страницы и «Отмена удаления»;
      - сценарии «Архивированная входящая связь блокирует удаление» и «Дневной выбор блокирует обоих прямых участников»: «Удалить» выключено и называет причину;
      - отсутствие кнопки параметров при загрузке и отказе чтения.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.2, 4.8, 4.16 — архивное состояние в шапке; 4.17, 4.18.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_options.dart` (новый), `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_options_test.dart` (новый), `test/intention/presentation/details/intention_details_options_test.dart` (новый).
  - **Размер:** M.

- [x] 4.20 Перевести сценарии приложения, которые архивировали, восстанавливали и удаляли намерение прежними кнопками, на параметры и шапку
  - **Критерии приёмки:**
    - Сценарии жизненного цикла намерения, потока долговременных связей, сброса операций, состояния оболочки, безымянных страниц и доступности тегов архивируют и удаляют намерение через параметры, а восстанавливают через параметры или шапку. Удаление подтверждается в диалоге «Удалить намерение?». Ожидания согласования каталога, соседства и тегов, сообщений и навигации сохраняются.
    - Сценарий недоступности страницы под диалогом удаления проверяет диалог, открытый из параметров.
    - Эти файлы не используют ключи прежних кнопок архивирования, восстановления и удаления и прежнего диалога удаления.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/app/intention_app_lifecycle_test.dart test/app/long_term_relation_app_flow_test.dart test/app/navigation test/tag/presentation/tag_accessibility_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.16, 4.19.
  - **Предполагаемые файлы:** `test/app/intention_app_lifecycle_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/app/navigation/app_shell_operation_reset_test.dart`, `test/app/navigation/app_shell_state_test.dart`, `test/app/navigation/app_shell_unnamed_page_scenarios.dart`, `test/tag/presentation/tag_accessibility_test.dart`.
  - **Размер:** M — замена способа действия механическая.

- [x] 4.21 Перевести проверки страницы намерения, её удаления, шапки и тегов с прежних кнопок архивирования, восстановления и удаления на параметры и шапку
  - **Критерии приёмки:**
    - Проверки, чей предмет сохраняется, выполняют действие через параметры или шапку и сохраняют прочие ожидания. Проверки, которые дублируют проверки 4.19, удалены.
    - Эти файлы не используют ключи прежних кнопок архивирования, восстановления и удаления и прежнего диалога удаления.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.16, 4.19.
  - **Предполагаемые файлы:** `test/intention/presentation/details/intention_details_page_test.dart`, `test/intention/presentation/details/intention_details_delete_test.dart`, `test/intention/presentation/details/intention_details_head_test.dart`, `test/intention/presentation/details/intention_details_tags_test.dart`.
  - **Размер:** M — замена способа действия механическая.

- [x] 4.22 Убрать со страницы намерения прежний ряд кнопок, пояснения о связях и диалог удаления, оставив прежнюю кнопку выбора пути
  - **Критерии приёмки:**
    - На странице нет прежних кнопок архивирования, восстановления и удаления, диалога удаления Material и пояснений о связях при архивировании и восстановлении с переходом к архиву связей. Управление намерением идёт через шапку, «Обзор» и параметры. Кнопка «Выбрать действие по пути» у активного намерения остаётся прежней под строкой дат до вкладки «Выборы» фазы 5.
    - У модели соседства нет `showArchivedRelations`: её единственным вызывающим был удалённый переход. Строки, которые использовали только удалённые элементы, удалены на обоих языках.
    - Проверки удалённых пояснений и перехода к архиву связей удалены: пояснения параметров подтверждает 4.19. Остальные проверки страницы и соседства сохраняют ожидания.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation test/long_term_relation/presentation test/tag/presentation test/app --exclude-tags=flutter_process`.
    - `rg -n "intention-details-(state-change|show-archived-relations|archive-explanation|restore-explanation|confirm-delete)" lib test` и `rg -nw "retryStateChange|IntentionDetailsStateChange|showArchivedRelations|detailsArchiveCascadeExplanation|detailsRestoreRelationsExplanation|detailsShowArchivedRelationsAction|detailsReadinessConfirmationTitle" lib test` ничего не находят.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.20, 4.21.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** S — в основном удаление.

- [ ] 4.23 Подтвердить готовность четвёртой фазы: «Обзор», шапка и параметры намерения работают по дизайну
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» четвёртой фазы:
      - требования Обзора, параметров, выбора готовности, физического удаления и предъявления результатов выполняются на странице;
      - управление самим намерением целиком идёт через новый вид.
    - Прежних полей, ряда кнопок, диалога готовности и инлайн-отказов переходов на странице нет. Успех изменения готовности, архивирования и восстановления не объявляется сообщением, а их отказы и отказ удаления показывает общая поверхность.
    - Результаты проверок и путь к APK сообщены в сессии. Сравнение с макетом и ручная проверка на устройстве остаются за пользователем и не блокируют готовность фазы.
  - **Проверка:**
    - Обе команды `rg` из 4.22 ничего не находят. `rg -nw "detailsReadinessEnabled|detailsReadinessDisabled|detailsArchivedSuccess|detailsRestoredSuccess|detailsEnableReadinessAction|detailsDisableReadinessAction" lib test` тоже ничего не находит.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - «Обзор» по макету: описание или приглашение, плитки типа, блок тегов с чипами и строка дат;
      - нажатие на описание открывает экран изменения с курсором в описании;
      - нажатие на плитку меняет тип в панели без диалога и сообщения;
      - шапка архивированного намерения с меткой, пояснением и «Восстановить из архива»;
      - лист «Намерение»: порядок пунктов, пояснения, выключенное «Удалить» с причиной и диалог удаления;
      - обе темы и увеличенный текст.
  - **Зависимости:** 4.1–4.22.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.
