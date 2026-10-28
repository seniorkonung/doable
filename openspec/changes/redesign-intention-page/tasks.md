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
