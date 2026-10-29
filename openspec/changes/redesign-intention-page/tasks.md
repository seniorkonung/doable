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

- [x] 4.23 Подтвердить готовность четвёртой фазы: «Обзор», шапка и параметры намерения работают по дизайну
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

- [x] 4.24 Обрезать плоскости, кольца и отклик нажатия `TextField.saved` и `OptionTiles` видимой частью компонента в области прокрутки
  - **Критерии приёмки:**
    - Плоскость `fill`, кольца (рамка `hairline` невыбранной плитки и кольцо фокуса) и отклик нажатия у `TextField.saved` и `OptionTiles` рисуются только внутри видимой части самого компонента и обрезаются областью прокрутки. Сейчас `Ink` рисует их на холсте `Material` каркаса, который область прокрутки не обрезает.
    - Когда компонент частично прокручен за верх `CustomScrollView` под прозрачной `TopBar`, панель и полоса состояния не получают его цветов. Это выполняется и на «Обзоре» страницы намерения, и в листах с прокруткой.
    - Механизм выбирает реализация, например собственный прозрачный `Material` у каждого компонента с обрезкой по скруглению. Вид, размеры, семантика, отклик нажатия, кольцо фокуса и поведение компонентов не меняются: прежние компонентные проверки сохраняют ожидания.
    - В `text_field_test.dart` и `option_tiles_test.dart` добавлено по одной регрессионной проверке: компонент внутри прокручиваемого предка под прозрачной панелью сдвигается частично за верх области прокрутки, и в точке панели цвет фона `bg`, а не `fill`. Проверка идёт в обеих темах, если это нужно, чтобы различить цвета.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/text_field_test.dart test/design_system/option_tiles_test.dart test/intention`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.3, 4.6.
  - **Предполагаемые файлы:** `lib/src/design_system/components/text_field.dart`, `lib/src/design_system/components/option_tiles.dart`, `test/design_system/text_field_test.dart`, `test/design_system/option_tiles_test.dart`.
  - **Размер:** S.

- [x] 4.25 Возвращать выбранный пункт `OptionsMenu` только после окончания обратной анимации закрытия листа
  - **Критерии приёмки:**
    - Показ `OptionsMenu` отдаёт выбранный доступный пункт вызывающему только после окончания обратной анимации закрытия листа, а не в момент `pop`. Сейчас `OptionsMenu` закрывает лист через `Navigator.pop(value)`, а будущее `showDoableSheet` завершается сразу при `pop`, до обратной анимации. Так соблюдается записанный контракт `OptionsMenu`, критерий задачи 4.18 и ADR-0042: действие начинается без открытого листа.
    - Поэтому `_openOptions` страницы намерения вызывает архивирование или восстановление, открывает экран изменения или диалог удаления уже после исчезновения листа, и уходящий лист параметров не перерисовывает пункты из-за начатой команды.
    - Закрытие без выбора (затемнением и «назад») по-прежнему возвращает отсутствие выбора.
    - Меняется только показ `OptionsMenu`. Момент возврата результата у остальных потребителей `showDoableSheet` (экспорт, резервные копии, старт дневного выбора, панели тегов, листы выбора и прочие) не меняется. Механизм выбирает реализация, например ожидание завершения маршрута листа в пути показа `OptionsMenu`, без новых общих параметров `showDoableSheet`. Контракт и документация `OptionsMenu`, задача 4.18 и ADR-0042 по смыслу не меняются.
    - Проверка возврата выбранного пункта в `options_menu_test.dart` различает моменты: пока анимация закрытия листа идёт, результат ещё не получен, а после её окончания получен.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/options_menu_test.dart test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.18, 4.19.
  - **Предполагаемые файлы:** `lib/src/design_system/components/options_menu.dart`, при необходимости `lib/src/design_system/components/sheet.dart` без изменения поведения других потребителей и `lib/src/intention/presentation/details/intention_details_page.dart`, `test/design_system/options_menu_test.dart`.
  - **Размер:** S.

- [x] 4.26 Показывать занятость страницы намерения, когда вход в правку отклонён из-за команды, которую её модель ещё не отразила
  - **Критерии приёмки:**
    - Если `_openEdit` в `intention_details_page.dart` отклоняет нажатие на название в шапке, описание или приглашение его добавить или пункт «Изменить», потому что координатор считает намерение занятым (`isRunning`), а модель страницы этого ещё не отразила, страница вызывает существующий `IntentionDetailsViewModel.refreshOperationRunning()`. Так модель становится видимо занятой, как отклонённое изменение готовности, архивирования или восстановления через `AlreadyRunning`. Сейчас нажатие молча ничего не делает, а входы остаются доступными, что нарушает требование «Экран изменения намерения».
    - После этого входы в правку и прочие изменяющие действия страницы недоступны, а после завершения операции снова доступны у сохранившегося намерения через существующий путь `_handleCompletion` и `_scheduleGateRefresh` модели.
    - Новые механизмы занятости, подписки на координатор и параметры не добавляются.
    - Проверка `intention_details_head_test.dart` «нажатие на название не открывает экран изменения, если команду приняла не страница и она ещё не отразила занятость» переписана: после нажатия экран изменения не открыт и `PageHead.onEdit` равен `null`, а после завершения команды координатора `onEdit` снова доступен.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.5, 4.19.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `test/intention/presentation/details/intention_details_head_test.dart`.
  - **Размер:** XS.

- [x] 4.27 Убрать тон у недоступного пункта `OptionsMenu`: выключенная строка рисуется одинаково при любом тоне
  - **Критерии приёмки:**
    - Конструктор `OptionsMenuItem.unavailable` в `options_menu.dart` не принимает параметр `tone`, и недоступный пункт всегда имеет обычный тон. По README `OptionRow` и критерию задачи 4.18 выключенная строка рисуется плиткой `fill` со значком и названием `grip` независимо от тона, поэтому параметр ни на что не влиял.
    - Сборщик меню в `intention_options.dart` не передаёт тон выключенному «Удалить». Доступное «Удалить» сохраняет опасный тон.
    - Проверки `options_menu_test.dart` не передают тон недоступному пункту (вызовы около строк 122 и 152). Ожидание опасного тона у недоступного пункта (`rows.last.tone` около строки 44) не остаётся: проверка листа по-прежнему подтверждает, что лист передаёт строке опасный тон доступного пункта. В `intention_options_test.dart` ожидание опасного тона у выключенного удаления (около строки 116) удалено, а ожидание опасного тона доступного удаления сохраняется.
    - Вид и поведение меню и строк не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/options_menu_test.dart test/design_system/option_row_test.dart test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.18, 4.19, 4.25 — тоже меняет `options_menu.dart` и его проверку.
  - **Предполагаемые файлы:** `lib/src/design_system/components/options_menu.dart`, `lib/src/intention/presentation/details/intention_options.dart`, `test/design_system/options_menu_test.dart`, `test/intention/presentation/details/intention_options_test.dart`.
  - **Размер:** XS.

- [x] 4.28 Удалить проверку страницы намерения, все ожидания которой подтверждают проверки шапки и «Обзора»
  - **Критерии приёмки:**
    - В `intention_details_page_test.dart` нет проверки «показывает архивное состояние и отсутствие описания». После задачи 4.21 она проверяет только метку «Archived», приглашение «Add a description» и выбранную плитку «Намерение» у неготового намерения и не ловит регрессии, которую не ловят другие проверки.
    - Перед удалением подтверждено, что каждое её ожидание остаётся покрытым: метку архивированного намерения на английском — сценарий шапки архивированного намерения в `intention_details_head_test.dart`, приглашение «Add a description» — проверка приглашения добавить описание в `intention_details_overview_test.dart` для английского языка, выбранную плитку «Намерение» у неготового намерения — проверка «Обзора» только что созданного намерения в `intention_details_overview_test.dart`.
    - Вспомогательные функции и импорты `intention_details_page_test.dart`, которые после удаления больше нигде не используются, удалены. Используемые другими проверками, например `_pumpDetailsPage` и `_selectedType`, остаются.
    - Код приложения и остальные проверки не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.21.
  - **Предполагаемые файлы:** `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** XS.

- [x] 4.29 Отбрасывать выбор листа параметров намерения, если до его получения над страницей что-то открыто или она уходит
  - **Критерии приёмки:**
    - После задачи 4.25 `_openOptions` в `intention_details_page.dart` получает выбранный в `OptionsMenu` пункт только после обратной анимации закрытия листа. В это окно страница под листом принимает нажатия: «⋯», название, описание, системное «назад». Сейчас пришедший позже выбор проверяет только `mounted` и начинает действие при втором открытом листе, поверх открытого экрана изменения или диалога либо на уходящей странице.
    - Выбранное действие (изменить, архивировать, восстановить, удалить) начинается, только если после получения выбора страница смонтирована и остаётся текущим маршрутом своего навигатора (`ModalRoute.isCurrentOf(context) == true`). Иначе выбор молча отбрасывается: без сообщения, без операции, без экрана изменения и без диалога. Страница, экран изменения, лист и диалог лежат в одном корневом стеке (`app_router.dart`), поэтому эта проверка исключает все четыре последовательности: второй лист «⋯», открытый экран изменения, диалог удаления и уходящая по «назад» страница.
    - Обычный выбор без второго нажатия работает как сейчас, закрытие листа без выбора по-прежнему ничего не делает.
    - Страница не блокирует ввод на время анимации закрытия листа. `sheet.dart`, `SheetPresentation.closeWithChoice`, `showDoableSheet`, `OptionsMenu` и остальные потребители листов не меняются. Смысл ADR-0042 и задач 4.18 и 4.25 сохраняется.
    - Комментарий к `_openOptions` на русском дополнен: поздний выбор отбрасывается, если над страницей уже что-то открыто или она уходит.
    - Проверка на русском в `intention_details_options_test.dart` воспроизводит хотя бы одну такую последовательность и до исправления падает. Например, выбрать «Изменить» и до окончания анимации закрытия нажать название — открыт ровно один экран изменения; или выбрать «Архивировать» и в это окно нажать «⋯» — архивирование не началось, открыт второй лист. Окно продвигается через `pump(Duration)` без измерения времени.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 4.25, 4.26.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `test/intention/presentation/details/intention_details_options_test.dart`.
  - **Размер:** XS.

## Phase 5: Вкладка «Выборы» с созданием дневного выбора

- [x] 5.1 Добавить модель вкладки «Выборы», которая порциями получает прямые дневные выборы намерения в одной роли и принадлежит экземпляру страницы
  - **Критерии приёмки:**
    - По решениям 2 и 8 дизайна `IntentionChoicesViewModel` — семейство по `IntentionId` и `IntentionPageInstance`. Модель освобождается вместе со строками, продолжениями и подписками, когда её больше никто не слушает.
      - При создании модель берёт роль из настроек экземпляра страницы и начинает получение с первой порции этой роли. Без сохранённого выбора роль — «исходное», первая роль прежнего переключателя.
      - Смена роли отбрасывает строки прежней роли, начинает первую порцию новой и записывает роль в настройки экземпляра. Поэтому новая модель того же экземпляра начинает с неё.
      - Настройки экземпляра не содержат строк, курсоров и якорей.
    - Модель поверх `RelationGroupPaging` воспроизводит поведение дневных ветвей `RelationNeighborhoodViewModel`:
      - первую порцию и сводку на одной ревизии, подгрузку при приближении к концу, повтор после устранимых отказов;
      - согласование по завершениям координатора — `DailyChoiceChange`, изменениям участников загруженных строк и чужим ревизиям — с показом прежней пары до замены;
      - отказы чтения и обновления и подтверждённое отсутствие намерения.

      Поздний ответ прежней роли или освобождённой модели ничего не публикует. Состояние модели — собственный закрытый тип без долговременных групп и `RelationGroupSelection`. Соседство в этой задаче не меняется.
    - Проверки дневных групп из `relation_neighborhood_view_model_test.dart` воспроизведены для новой модели с теми же ожиданиями; из соседства они уходят в 5.9. Новые проверки подтверждают:
      - роль «исходное» без сохранённого выбора и первую порцию сохранённой роли у новой модели того же экземпляра;
      - запись смены роли в настройки экземпляра;
      - независимость ролей и порций двух экземпляров одного намерения;
      - отсутствие чтений и публикаций после освобождения, в том числе от позднего ответа.
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы.
    - `mise exec --no-deps -- flutter test test/daily_choice/presentation/intention_choices test/long_term_relation/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart` (новый), `lib/src/daily_choice/presentation/intention_choices/intention_choices_state.dart` (новый) и сгенерированный провайдер, `lib/src/intention/presentation/details/intention_page_target.dart` — настройки экземпляра;
    - проверки: `test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart` (новый), при необходимости `test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart`.
  - **Размер:** M.

- [x] 5.2 Показывать на странице намерения вкладку «Выборы» с прежними строками и переключателем ролей, которые получаются, только пока она выбрана
  - **Критерии приёмки:**
    - По требованию «Страница намерения и её вкладки» полоса вкладок — «Обзор», «Связи», «Выборы», «Статистика» в этом порядке. У «Выборов» нет числа, видимое и доступное название — «Выборы» / «Choices». Переключение не добавляет шагов в историю.
    - По решению 8 дизайна тело вкладки — sliver модели из 5.1:
      - переключатель ролей с числами и строки дневных выборов переносятся из соседства без нового оформления, с ключами вкладки «Выборы» вместо префикса `relation-neighborhood-daily`;
      - строка открывает подробности дневного выбора;
      - загрузка, отказ первого чтения, подгрузка, обновление, пустая роль и отсутствие намерения показываются прежними видами.

      Роли «на пути» и нового оформления нет.
    - По решению 2 дизайна модель существует, только пока выбрана вкладка «Выборы», в том числе когда над страницей открыта другая страница. До первого показа модели и чтений дневных групп нет. При уходе на другую вкладку модель освобождается вместе со строками, продолжениями и подписками. Возвращение сохраняет роль и начинает получение с первой порции без восстановления прежнего объёма.
    - Дневные группы соседства на «Связях» остаются до 5.9.
    - Проверки страницы подтверждают:
      - порядок вкладок, отсутствие числа и доступное название «Выборов» на русском и английском;
      - сценарий «Возвращение к выборам сохраняет роль и начинает список заново»: роль «выбранное» сохранена, получена только первая порция, модель прежнего показа освобождена;
      - отсутствие чтений дневных групп при открытии на «Обзоре», «Связях» и «Статистике»;
      - открытие подробностей дневного выбора строкой.

      Проверки дневных групп из `relation_neighborhood_widget_test.dart` воспроизведены для вкладки: пустая роль не скрывает число выборов другой роли, а строка дневного выбора читается диктором.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/daily_choice/presentation/intention_choices`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.1.
  - **Предполагаемые файлы:**
    - `lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart` (новый), `lib/src/intention/presentation/details/intention_details_tabs.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_details_choices_test.dart` (новый), `test/intention/presentation/details/details_test_support.dart`.
  - **Размер:** M.

- [x] 5.3 Открывать страницу намерения на вкладке «Выборы» по цели `ChoicesTarget`, не связывая её роль и порции с другими страницами того же намерения
  - **Критерии приёмки:**
    - По требованию «Цель открытия страницы намерения» и решению 2 дизайна `IntentionPageTarget` получает вариант `ChoicesTarget` без параметров. Он один раз выбирает начальную вкладку «Выборы», и её модель сразу получает первую порцию роли «исходное». Цели статистики у этого варианта нет. Вызывающие в приложении не меняются: по решению 2 им эта цель не нужна.
    - Две страницы одного намерения в истории не меняют друг у друга роль и порции «Выборов». Смена роли на верхней странице не меняет нижнюю, а после «назад» нижняя показывает свою роль и свои строки.
    - Проверки подтверждают открытие по `ChoicesTarget` с выбранной вкладкой и одним чтением первой порции, отсутствие чтений долговременных групп и статистики и независимость двух страниц одного намерения.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/statistics/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.2.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_page_target.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `test/intention/presentation/details/intention_details_tabs_test.dart`, `test/intention/presentation/details/intention_details_choices_test.dart`.
  - **Размер:** S.

- [x] 5.4 Расширить `AddRow` строкой с подсказкой, в которой может не быть «Добавить» или самой подсказки
  - **Критерии приёмки:**
    - По README `AddRow` строка с подсказкой не ниже `tap-min`. Подсказка — стилем `hint` цвета `muted`, начинается в `space-1` от края и переносится. «Добавить» выглядит и нажимается как в строке с заголовком: подпись и доступное название передаёт потребитель.
    - Потребитель может не передать «Добавить»: тогда его нет ни в раскладке, ни в семантике, а подсказка занимает строку. Потребитель может не передать подсказку: тогда строка держит только «Добавить» у правого края. Строку без подсказки и без «Добавить» API не допускает. Выключенного «Добавить» в строке с подсказкой нет: у него нет потребителя.
    - Компонентные проверки в обеих темах подтверждают:
      - стиль, цвет и отступ подсказки;
      - перенос длинной подсказки без переполнения при увеличенном тексте;
      - строку без «Добавить» и строку только с «Добавить»;
      - вызов обработчика и доступное название «Добавить».

      Проверки строки с заголовком и `TagsSection` сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/add_row_test.dart test/design_system/tags_section_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/add_row.dart`, `test/design_system/add_row_test.dart`.
  - **Размер:** S.

- [x] 5.5 Начинать создание дневного выбора строкой «Добавить» над списком роли на вкладке «Выборы»
  - **Критерии приёмки:**
    - По требованию «Входы в создание дневного выбора» и решению 8 дизайна между переключателем ролей и списком стоит строка `AddRow` с подсказкой из 5.4:
      - у роли «исходное» активного намерения «Добавить» сразу открывает `ChoicePathRoute(sourceIntentionId: id, direction: topDown)` без поиска;
      - у роли «выбранное» активного действия «Добавить» сразу открывает `ChoicePathRoute(sourceIntentionId: id, direction: bottomUp)` без поиска действия;
      - у архивированного намерения в обеих ролях и у роли «выбранное» неготового намерения «Добавить» нет.

      Доступность берётся из последнего принятого снимка подробных данных. На время изменяющей операции намерения «Добавить» не выключается: создание дневного выбора не изменяет намерение, а модель пути отклоняет недопустимое начало. Оба маршрута сами владеют границей потока создания (ADR-0022).
    - Подсказка называет роль: «Дневные выборы, которые начинаются с этого намерения.» / «Daily choices that start from this intention.» и «Дневные выборы, которые заканчиваются этим намерением.» / «Daily choices that end in this intention.». По README `AddRow` подсказка показывается, только когда подтверждённый список роли не пуст. Иначе строка держит одно «Добавить», а без «Добавить» строки нет.
    - Доступные названия «Добавить»: «Создать дневной выбор, который начинается с этого намерения» / «Create a daily choice that starts from this intention» и «Создать дневной выбор, который заканчивается этим действием» / «Create a daily choice that ends in this action».
    - Прежняя кнопка «Выбрать действие по пути» остаётся до перевода её сценариев в 5.6 и удаляется в 5.7.
    - Проверки страницы подтверждают:
      - сценарии «Вход со страницы намерения не требует поиска» и «Вход со страницы действия идёт снизу вверх» по открытому `ChoicePathPage` с идентификатором и направлением;
      - отсутствие «Добавить» у архивированного намерения и у роли «выбранное» неготового намерения;
      - показ подсказки по списку роли;
      - доступные названия «Добавить» на русском и английском.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/daily_choice/presentation/intention_choices test/design_system/add_row_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.2, 5.4.
  - **Предполагаемые файлы:**
    - `lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/intention/presentation/details/intention_details_choices_test.dart`.
  - **Размер:** M.

- [x] 5.6 Перевести сценарии, которые начинали выбор пути кнопкой «Выбрать действие по пути», на «Добавить» вкладки «Выборы», удалить дублирующие 5.5 проверки маршрутизатора и подтвердить возвращение на вкладку после создания
  - **Критерии приёмки:**
    - Сценарии потока создания дневного выбора, дневных выборов приложения и матрицы страниц навигации открывают вкладку «Выборы» и начинают путь её «Добавить» у роли «исходное». Их прочие ожидания сохраняются.
    - Проверки маршрутизатора «верхний обход открывается из активного намерения» и «архивное намерение не предлагает верхний обход» в `test/app/routing/app_router_test.dart` удалены, а не переведены: проверки страницы из 5.5 собирают её через `AppRouter` и подтверждают открытый `ChoicePathPage` с идентификатором и направлением и отсутствие «Добавить» у архивированного намерения. Перед удалением подтверждено, что каждое ожидание этих двух проверок покрыто проверками 5.5. После удаления убраны ставшие неиспользуемыми импорты и вспомогательные функции; по текущему коду это импорт `ChoicePathPage`, а `_pumpRouter`, `_settleNeighborhood` и `testRelationCounts` нужны остальным проверкам файла.
    - Сценарий потока создания подтверждает «Созданный выбор открывается вместо построения пути». После подтверждения открыт подробный просмотр созданного выбора. «Назад» возвращает на страницу намерения с выбранной вкладкой «Выборы», прежней ролью и созданным выбором в списке, а пошагового выбора и подтверждения в истории нет.
    - Эти файлы не используют ключ `intention-details-choose-path`.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/daily_choice/presentation/daily_choice_creation_flow_test.dart test/app/daily_choice_app_flow_test.dart test/app/routing/app_router_test.dart test/app/navigation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.5.
  - **Предполагаемые файлы:** `test/daily_choice/presentation/daily_choice_creation_flow_test.dart`, `test/app/daily_choice_app_flow_test.dart`, `test/app/routing/app_router_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`.
  - **Размер:** M — замена способа входа механическая.

- [x] 5.7 Убрать со страницы намерения кнопку «Выбрать действие по пути»
  - **Критерии приёмки:**
    - На «Обзоре» нет кнопки «Выбрать действие по пути». Со страницы намерения создание дневного выбора начинается только «Добавить» вкладки «Выборы».
    - Строка `detailsChoosePathAction` удалена на обоих языках. Проверка доступности изменяющих действий страницы в `intention_details_page_test.dart` больше не ждёт этой кнопки, остальные её ожидания сохраняются.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `rg -n "intention-details-choose-path|detailsChoosePathAction" lib test` ничего не находит.
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/daily_choice/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.6.
  - **Предполагаемые файлы:** `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** XS.

- [x] 5.8 Перевести проверки согласования графа, состояния оболочки и страницы намерения с дневных групп соседства на модель и вкладку «Выборы»
  - **Критерии приёмки:**
    - Проверка контрольной точки согласования графа выбирает роли через модель из 5.1 с экземпляром страницы, а не через `RelationNeighborhoodViewModel.selectDailyGroup`. Сценарий состояния оболочки открывает дневной выбор со вкладки «Выборы», а не из дневной группы соседства. Их ожидания сохраняются.
    - Проверка «дневная зависимость намерения открывает свой полный путь» в `intention_details_page_test.dart` удалена: открытие подробностей дневного выбора строкой вкладки подтверждает 5.2.
    - Эти файлы не используют `selectDailyGroup`, `DailyChoiceGroupLoaded` и ключи `relation-neighborhood-daily-…`.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph/presentation test/app/navigation/app_shell_state_test.dart test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.2.
  - **Предполагаемые файлы:** `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`, `test/app/navigation/app_shell_state_test.dart`, `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Размер:** M.

- [x] 5.9 Убрать дневные группы из соседства на вкладке «Связи»
  - **Критерии приёмки:**
    - По результату фазы 5 плана в соседстве нет дневных групп:
      - у `RelationNeighborhoodViewModel` нет `selectDailyGroup`, дневного источника порций и согласования строк дневной роли;
      - у состояния соседства нет `DailyChoiceGroupLoaded`, а выбранная группа — только долговременная;
      - у `RelationNeighborhoodSliver` нет сводки дневных выборов с переключателем ролей, дневных строк и `onOpenDailyChoice`.

      Долговременные группы, их порции и якоря, полная сводка и её согласование по изменённым количествам, в том числе после изменений дневных выборов, не меняются.
    - Проверки дневных групп в проверках модели и вида соседства удалены: их воспроизвели 5.1 и 5.2. Ветвь дневной группы в `package_consumers_test_support.dart` удалена. Остальные проверки соседства и потребителей пакета изменений сохраняют ожидания. Строки, которые больше нигде не используются, удалены на обоих языках.
  - **Проверка:**
    - `mise run codegen` — провайдеры и локализация пересозданы.
    - `rg -n "selectDailyGroup|DailyChoiceGroupLoaded|relation-neighborhood-daily" lib test` ничего не находит.
    - `mise exec --no-deps -- flutter test test/long_term_relation test/intention test/daily_choice test/graph/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 5.2; 5.8 — проверки больше не читают дневные группы соседства.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`, при необходимости `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model_test.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M — в основном удаление.

- [x] 5.10 Подтвердить готовность пятой фазы: дневные выборы страницы и их создание идут через вкладку «Выборы»
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» пятой фазы:
      - требования о просмотре прямых дневных зависимостей и входах в создание дневного выбора выполняются через вкладку;
      - цель открытия выбирает вкладку «Выборы»;
      - настройки и порции независимы для двух страниц одного намерения. Автоматические проверки подтверждают сохранение роли и повторное порционное получение после переключения вкладок, освобождение прежних данных и отсутствие чтений до первого показа;
      - созданный выбор возвращает на вкладку «Выборы».
    - На странице нет кнопки «Выбрать действие по пути», а в соседстве на «Связях» — дневных групп.
    - Результаты проверок и путь к APK сообщены в сессии. Ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - Команды `rg` из 5.7 и 5.9 ничего не находят.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - вкладка «Выборы» между «Связями» и «Статистикой» без числа, прежние строки и переключатель ролей;
      - «Добавить» у «исходного» открывает пошаговый выбор сверху вниз, у «выбранного» действия — снизу вверх; у архивированного намерения и у «выбранного» неготового намерения «Добавить» нет;
      - смена роли, уход на «Обзор» и возвращение сохраняют роль;
      - после создания выбора «назад» возвращает на «Выборы» с той же ролью;
      - обе темы и увеличенный текст.
  - **Зависимости:** 5.1–5.9.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.

- [x] 5.11 Убрать из `AddRow` публичные nullable-геттеры, которые читает только проверка `TagsSection`
  - **Критерии приёмки:**
    - В `lib/src/design_system/components/add_row.dart` нет публичных геттеров `title`, `addText`, `addLabel`, `onAdd` и `addKey`. Закрытая модель вариантов (`_Lead` с `_Title` и `_Hint`, `_Add`) и конструкторы `AddRow`, `AddRow.hint`, `AddRow.hintOnly`, `AddRow.addOnly` не меняются.
    - Проверка «блок передаёт строке заголовок, подписи, ключ и выключенность «Добавить»» в `test/design_system/tags_section_test.dart` не читает поля виджета `AddRow`. Она подтверждает наблюдаемое поведение при `onAdd: null`:
      - тексты «Теги» и «Добавить» стоят внутри `AddRow` (`find.descendant`);
      - кнопка находится по ключу;
      - семантика кнопки: подпись «Добавить теги», кнопка, есть состояние доступности, выключена.
    - Поведение и вид приложения не меняются. Потребители `tags_section.dart` и `intention_choices_sliver.dart` не меняются.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/add_row_test.dart test/design_system/tags_section_test.dart`.
    - `mise exec --no-deps -- flutter analyze` без замечаний.
  - **Зависимости:** 5.4.
  - **Предполагаемые файлы:** `lib/src/design_system/components/add_row.dart`, `test/design_system/tags_section_test.dart`.
  - **Размер:** XS.

## Phase 6: Вкладка «Связи» по дизайну

- [x] 6.1 Перенести политику размера порций из соседства в общий модуль порционных списков страницы
  - **Критерии приёмки:**
    - По решению 6 дизайна политика размера порции и запаса до подгрузки живёт рядом с ядром `RelationGroupPaging`, а не в `relation_neighborhood_paging_policy.dart`. Тип политики, проверка её пределов, производственные значения 50 и 15 и провайдер не зависят от соседства. Файл политики соседства удалён.
    - Модели соседства и «Выборов» и проверки, которые подменяют политику, используют общий модуль. Размер порций, условие подгрузки и отказы проверки пределов не меняются, ожидания проверок сохраняются.
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы.
    - `rg -n "RelationNeighborhoodPagingPolicy|relationNeighborhoodPagingPolicy|relation_neighborhood_paging_policy" lib test` ничего не находит.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation test/daily_choice/presentation/intention_choices test/intention/presentation/details test/graph/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/relation_group_paging_policy.dart` (новый) и сгенерированный провайдер, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart` (удаляется), `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart`;
    - проверки, подменяющие политику: `test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart`, `test/intention/presentation/details/intention_details_choices_test.dart`, `test/intention/presentation/details/intention_details_delete_test.dart`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`, проверки соседства.
  - **Размер:** S — перенос механический.

- [x] 6.2 Вынести общий слой согласования порционного списка страницы с графом и перевести на него модель «Выборов» без изменения поведения
  - **Критерии приёмки:**
    - По решениям 6 и 8 дизайна над ядром `RelationGroupPaging` стоит общий слой согласования порционного списка страницы с подтверждёнными изменениями графа. Слой владеет:
      - подпиской на `watchIntention` и завершения координатора и их разбором;
      - сравнением ревизий и циклом пересборки;
      - первым чтением, подгрузкой по политике из 6.1 и повторами после устранимых отказов;
      - сопоставлением отказов наблюдения намерения с отказами чтения;
      - завершением контекста при удалении намерения;
      - статусами сводки и подгрузки.

      Провайдеров, вкладок и предметных групп слой не знает. Вкладка задаёт только запрос порции, принадлежность строки, признак значимого изменения и форму публикуемого состояния.
    - `IntentionChoicesViewModel` стоит на слое и задаёт только роль, принадлежность строки роли и признак значимого изменения: `DailyChoiceChange` своей роли и загруженных строк, изменения участников загруженных строк и изменение сводки намерения. Своих подписок, сравнения ревизий, цикла пересборки и сопоставления отказов у модели нет. Смена роли, настройки экземпляра и освобождение работают как прежде.
    - Поведение вкладки «Выборы» не меняется. Проверки модели и страницы «Выборов» проходят с прежними ожиданиями; в них меняются только имена типов статусов, которые теперь принадлежат слою. Модель соседства в этой задаче не меняется.
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы.
    - `mise exec --no-deps -- flutter test test/daily_choice/presentation/intention_choices test/intention/presentation/details test/long_term_relation/presentation test/graph/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.1.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/relation_list_reconciliation.dart` (новый, рядом с ядром порций), `lib/src/daily_choice/presentation/intention_choices/intention_choices_view_model.dart`, `lib/src/daily_choice/presentation/intention_choices/intention_choices_state.dart`, `lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart`;
    - проверки — только имена типов статусов: `test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart`, `test/intention/presentation/details/intention_details_choices_test.dart`.
  - **Размер:** M.

- [x] 6.3 Перенести проверки гонок согласования из проверок модели «Выборов» в проверки общего слоя
  - **Критерии приёмки:**
    - Каждая обязанность слоя из 6.2 проверяется на уровне слоя, без провайдеров вкладки, с подставными чтением порций, наблюдением намерения и завершениями координатора:
      - поздний ответ прежнего выбора или освобождённого потребителя ничего не публикует;
      - устаревшее продолжение и прерванная подгрузка ведут к новой основе в пределах загруженной части и запрошенной порции;
      - чужая ревизия требует новой основы, а запоздалое чтение не возвращает прежние строки и сводку;
      - удаление намерения по наблюдению и по завершению координатора завершает контекст без новых чтений;
      - до готовности замены видна прежняя подтверждённая часть с состоянием обновления, отказ обновления её сохраняет;
      - категории отказов первого чтения и подгрузки; повтор доступен только при устранимой недоступности и продолжает список один раз.
    - Проверки модели «Выборов», которые проверяли только эти механизмы, перенесены, а не продублированы. У модели остаются проверки её решений: роль по умолчанию и сохранённая роль, запись смены роли в экземпляр, принадлежность строк роли, признак значимого изменения и независимость двух экземпляров.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/relation_list_reconciliation_test.dart test/daily_choice/presentation/intention_choices`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.2.
  - **Предполагаемые файлы:** `test/long_term_relation/presentation/relation_list_reconciliation_test.dart` (новый), `test/daily_choice/presentation/intention_choices/intention_choices_view_model_test.dart`.
  - **Размер:** M.

- [x] 6.4 Перенести правило начала описания из `IntentionDescriptionPreview` в общий модуль текста
  - **Критерии приёмки:**
    - По решению 6 дизайна правило начала описания живёт в общем модуле текста `lib/src/shared/domain/` под именем без предметной сущности: серии пробельных символов схлопываются, края обрезаются, остаётся не больше 512 расширенных графемных кластеров, пустой результат не допускается. Каталог намерений строит начало описания по этому правилу. `IntentionDescriptionPreview` удалён, а не оставлен обёрткой.
    - Каталог намерений ведёт себя как прежде. Проверки правила перенесены к общему модулю, проверки каталога сохраняют ожидания.
  - **Проверка:**
    - `rg -n "IntentionDescriptionPreview" lib test` ничего не находит.
    - `mise exec --no-deps -- flutter test test/shared/domain test/intention/application test/intention/data test/intention/presentation/catalog`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/shared/domain/text_preview.dart` (новый), `lib/src/intention/application/intention_description_preview.dart` (удаляется), `lib/src/intention/application/intention_catalog.dart`, `lib/src/graph/data/drift_personal_graph_repository.dart`;
    - проверки: `test/shared/domain/text_preview_test.dart` (новый, вместо `test/intention/application/intention_description_preview_test.dart`), `test/intention/application/intention_contract_test.dart`, `test/support/intention_description_preview.dart`.
  - **Размер:** S.

- [x] 6.5 Отдавать в порциях группы связей строку `RelationGroupEntry` с соседом, его готовностью и началом описания
  - **Критерии приёмки:**
    - По решению 6 дизайна и ADR-0047 первая порция и продолжение группы связей содержат `RelationGroupEntry` вместо `LongTermRelationSummary`:
      - саму связь;
      - соседа — участника, который не владеет группой: идентификатор, название, архивное состояние и готовность к действию;
      - `descriptionPreview` — начало описания связи по правилу из 6.4; у связи без описания его нет.

      Владельца группы и `hasDescription` в строке нет. SQL, порядок, порции, курсоры, сводка и проверка принадлежности строк группе не меняются. Чтение пути выбора и `RelationParticipantSummary` не меняются.
    - Прежнее соседство до удаления в 6.20 показывает прежние формулировку и обоих участников. Соседа оно берёт из строки, а название и архивное состояние владельца — из подробных данных страницы.
    - Проверки чтения группы подтверждают:
      - начало описания: схлопнутые пробелы, обрезку краёв, предел длины и отсутствие у связи без описания;
      - готовность соседа во входящих и исходящих группах;
      - отсутствие владельца в строке;
      - неизменные порядок и порции.

      Фикстуры проверок, которые строят порции групп, переходят на новый тип с прежними ожиданиями.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/graph/data/drift_relation_group_page_test.dart test/graph/data/drift_relation_group_large_fixture_test.dart test/long_term_relation test/intention/presentation/details test/graph/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.4.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/application/relation_group_page.dart`, `lib/src/long_term_relation/application/long_term_relation_projection.dart`, `lib/src/graph/data/drift_personal_graph_repository_relation_groups.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`;
    - проверки: `test/graph/data/drift_relation_group_page_test.dart`, `test/graph/data/drift_relation_group_large_fixture_test.dart`, `test/long_term_relation/application/relation_group_page_test.dart`;
    - фикстуры порций групп: `test/long_term_relation/presentation/neighborhood/neighborhood_test_support.dart`, `test/intention/presentation/details/details_test_support.dart`, `test/app/routing/app_router_test.dart`, `test/app/intention_app_lifecycle_test.dart`, `test/app/navigation/app_shell_operation_reset_test.dart`, `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`.
  - **Размер:** M — замена типа в фикстурах механическая.

- [x] 6.6 Начинать создание связи с ролью участника и типом, которые задаёт группа `IntentionRelationGroup`
  - **Критерии приёмки:**
    - По решениям 2 и 7 дизайна в прикладном слое связей есть перечисление `IntentionRelationGroup` четырёх групп страницы: `needs` — «нужно», исходящие; `canUse` — «можно», исходящие; `neededFor` — «нужно», входящие; `canBeUsedFor` — «можно», входящие. Каждое значение даёт тип и направление.
    - `RelationCreationContext(participant, direction)` заменён на `RelationCreationContext(participant, group)`:
      - роль участника выводится из направления группы, а начальный тип формы — из её типа;
      - `==` и `hashCode` включают группу;
      - изменённость формы создания сравнивает тип с типом группы: только что открытая форма не изменена;
      - тип остаётся переключаемым.
    - Прежнее соседство передаёт группу своего выбранного типа и направления. Других вызывающих с направлением нет.
    - Проверки редактора подтверждают сценарий «Вход из исходящей группы»: из «Можно использовать» намерение выбрано исходным участником, тип «можно» выбран, а связанный участник и приоритет не выбраны. Входящая группа выбирает намерение связанным участником. Проверки подтверждают отсутствие изменённости сразу после открытия и её появление при смене типа. Остальные проверки, которые строят контекст создания, сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/editor test/app/routing/app_router_test.dart test/app/navigation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/application/intention_relation_group.dart` (новый), `lib/src/long_term_relation/presentation/editor/relation_editor_state.dart`, `lib/src/long_term_relation/presentation/editor/relation_editor_view_model.dart`, `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`, `lib/src/intention/presentation/details/intention_details_page.dart`;
    - проверки: `test/long_term_relation/presentation/editor/relation_editor_view_model_test.dart`, `test/long_term_relation/presentation/editor/relation_editor_page_test.dart`, `test/long_term_relation/presentation/editor/relation_creation_navigation_test.dart`, `test/app/routing/app_router_test.dart`, `test/app/navigation/app_shell_operation_reset_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`.
  - **Размер:** M — замена конструктора в проверках механическая.

- [x] 6.7 Добавить модель вкладки «Связи», которая порциями получает активные связи выбранной группы и принадлежит экземпляру страницы
  - **Критерии приёмки:**
    - По решениям 2 и 6 дизайна `IntentionRelationsViewModel` — семейство по `IntentionId` и `IntentionPageInstance` поверх общего слоя из 6.2. Модель освобождается вместе со строками, продолжениями и подписками, когда её больше никто не слушает. До создания модели группы не читаются.
    - Выбранная группа — настройка экземпляра страницы рядом с ролью «Выборов». `RelationsTarget` получает необязательную группу `IntentionRelationGroup`.
      - Начальная группа задаётся один раз, при первом создании модели экземпляра: группой из цели, а без неё — по готовности из последнего принятого снимка подробных данных: `needs` для неготового намерения, `neededFor` для действия.
      - Следующие модели того же экземпляра берут сохранённый выбор. Изменение готовности и новые показы его не сбрасывают.
      - Настройки не содержат строк, курсоров и якорей.
    - Модель публикует сводку и активную часть выбранной группы — строки `RelationGroupEntry`, продолжение и подгрузку — на одной ревизии. Смена группы отбрасывает строки прежней группы, начинает первую порцию новой и записывает группу в экземпляр.
    - Признак значимого изменения модели:
      - изменение связи, которое вводит её в выбранную группу, выводит из неё или меняет её приоритет;
      - изменение загруженной связи;
      - изменение владельца или соседа загруженной строки;
      - изменение любого группового количества владельца, в том числе от дневных выборов.

      Остальное согласует слой. Якорь прокрутки хранит идентификатор связи активной части.
    - Проверки модели подтверждают:
      - начальную группу по цели, по готовности неготового намерения и действия и сохранённый выбор у новой модели того же экземпляра;
      - сохранённую группу у новой модели того же экземпляра, когда после первого создания модели готовность в последнем снимке подробных данных изменилась;
      - группу, выбранную после открытия по цели, у новой модели того же экземпляра вместо группы цели;
      - запись смены группы в экземпляр и первую порцию только выбранной группы;
      - отсутствие чтений до создания модели и после её освобождения;
      - независимость групп и порций двух экземпляров одного намерения;
      - признак значимого изменения, включая сценарии «Изменение непросматриваемой группы обновляет полностью загруженную страницу» и «Пустая выбранная группа не задерживает обновление сводки».

      Ожидания проверок долговременных групп из `relation_neighborhood_view_model_test.dart`, которые относятся к решениям модели, воспроизведены для новой модели. Гонки не повторяются: их проверяет слой (6.3).
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/intention_relations test/intention/presentation/details`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.3, 6.5, 6.6.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/intention_relations/intention_relations_view_model.dart` (новый), `lib/src/long_term_relation/presentation/intention_relations/intention_relations_state.dart` (новый) и сгенерированный провайдер, `lib/src/intention/presentation/details/intention_page_target.dart`;
    - проверки: `test/long_term_relation/presentation/intention_relations/intention_relations_view_model_test.dart` (новый).
  - **Размер:** M.

- [ ] 6.8 Публиковать в модели «Связей» архив выбранной группы вместе с её активной частью на одной ревизии
  - **Критерии приёмки:**
    - По решению 6 дизайна и ADR-0047 состояние модели — сводка, активная часть и, пока архив группы раскрыт, архивная часть на одной ревизии. Общий слой из 6.2 принимает форму из нескольких частей:
      - первое чтение получает первые порции раскрытых частей на одной ревизии;
      - подгрузка идёт той части, к концу которой подходит прокрутка;
      - пересборка повторяет загруженное каждой частью и запрошенное продолжение и заменяет все части атомарно.

      «Выборы» остаются формой из одной части без изменения поведения.
    - Раскрытие архива — флаг каждой группы в настройках экземпляра.
      - Только при первом создании модели экземпляра флаги всех групп раскрыты у архивированного намерения и свёрнуты у активного.
      - Раскрытие читает первую порцию архивированных связей группы, сворачивание отбрасывает её строки.
      - Смена группы отбрасывает строки прежней группы и сохраняет флаги. Возвращение к группе с раскрытым архивом снова получает его первую порцию без повторного раскрытия.
      - Свёрнутый архив и невыбранные группы не читаются.
    - Архивирование и восстановление связи и каскадное архивирование намерения переносят строку между частями: на любой опубликованной ревизии связь видна ровно в одной части. Отказ одной части задерживает публикацию всей новой пары, а прежняя пара остаётся с состоянием обновления или отказа. Якорь прокрутки хранит идентификатор связи из любой части.
    - Проверки слоя подтверждают публикацию нескольких частей на одной ревизии, пересборку в пределах загруженного каждой частью и сохранение прежней пары при отказе одной части. Проверки модели подтверждают:
      - пару на одной ревизии при архивировании и восстановлении связи и каскаде;
      - начальные флаги раскрытия и их сохранение при смене группы и у новой модели того же экземпляра;
      - сценарии «Просмотр архива сохраняет тип и направление», «Смена типа в архиве сохраняет архивное состояние списка», «Многолетний архив не загружается целиком при открытии» и «Архив архивированного намерения раскрыт сразу».
  - **Проверка:**
    - `mise run codegen` — провайдеры пересозданы.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation test/daily_choice/presentation/intention_choices`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.7.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/relation_list_reconciliation.dart`, `lib/src/long_term_relation/presentation/intention_relations/intention_relations_view_model.dart`, `lib/src/long_term_relation/presentation/intention_relations/intention_relations_state.dart`, `lib/src/intention/presentation/details/intention_page_target.dart`;
    - проверки: `test/long_term_relation/presentation/relation_list_reconciliation_test.dart`, `test/long_term_relation/presentation/intention_relations/intention_relations_view_model_test.dart`.
  - **Размер:** M.

- [ ] 6.9 Перевести проверки контрольной точки согласования графа и потребителей пакета изменений с модели соседства на модель «Связей»
  - **Критерии приёмки:**
    - Проверки контрольной точки согласования графа и потребители пакета изменений наблюдают `IntentionRelationsViewModel` с экземпляром страницы. Группы они выбирают через `IntentionRelationGroup`, архивные связи получают раскрытием архива группы, а не выбором типа, направления и архивного состояния соседства.
    - Ожидания сохраняются: согласование счётчиков и списков после создания, изменения типа и участников, архивирования, восстановления, удаления связи и каскада на настоящем хранилище, без двойного применения изменения и без возврата прежних чисел запоздалым чтением.
    - Эти файлы не используют `RelationNeighborhoodViewModel`, `RelationGroupSelection` и состояния соседства.
  - **Проверка:**
    - `rg -n "relationNeighborhoodViewModelProvider|RelationGroupSelection|RelationNeighborhoodState" test/graph/presentation` ничего не находит.
    - `mise exec --no-deps -- flutter test test/graph/presentation`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.8.
  - **Предполагаемые файлы:** `test/graph/presentation/graph_reconciliation_checkpoint_test.dart`, `test/graph/presentation/package_consumers_test_support.dart`.
  - **Размер:** M.

- [ ] 6.10 Добавить в дизайн-систему плитки групп `CountTiles` в две и три колонки
  - **Критерии приёмки:**
    - По README `CountTiles`, решению 11 дизайна и ADR-0048 потребитель передаёт плитки с идентификатором, числом, подписью и доступным названием, раскладку в две или три колонки, открытую плитку, обработчик выбора и доступное название группы. У плитки группы связей есть необязательный глиф направления: тип «нужно» или «можно» и направление от намерения или к нему — и отметка архива. Предметных типов в компоненте нет (ADR-0030).
      - Плитки — равные колонки в `space-2`; углы `radius-lg`, поля 11 сверху и `space-3` по бокам и снизу. Число — стиль `headline` с табличными цифрами, подпись — стиль `caption` цвета `muted` в 2 под ним. Нулевое число — цвета `grip`.
      - Открытая плитка — плоскость `fill`, закрытая — без плоскости с внутренним кольцом `hairline` в 1. Открыта ровно одна.
      - Отметка архива — малый значок архива цвета `muted` после числа.
      - Глиф 38 × 12 стоит в конце строки числа и строится из `RelationStroke`: сплошная линия для «нужно», пунктир 3/3 для «можно»; закрашенная точка — это намерение, кольцо — другое; стрелка идёт от намерения к тому, что ему нужно или что оно может использовать. Цвет глифа — цвет числа.
    - Плитки для экранного диктора — радиогруппа с доступным названием; каждая плитка называет себя переданным доступным названием и сообщает выбранное состояние.
    - Широкой плитки и вариантов «Выборов» и «Статистики» нет.
    - Компонентные проверки в обеих темах подтверждают:
      - обе раскладки — в две и три колонки — с равными колонками и отступами;
      - цвета открытой и закрытой плиток и нулевого числа;
      - отметку архива и вид и направление глифа;
      - вызов обработчика и семантику радиогруппы с выбранным состоянием;
      - перенос длинных подписей без переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/count_tiles_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/count_tiles.dart` (новый), `test/design_system/count_tiles_test.dart` (новый).
  - **Размер:** M.

- [ ] 6.11 Добавить в дизайн-систему строку связи `RelationRow`
  - **Критерии приёмки:**
    - По README `RelationRow` и решению 11 дизайна потребитель передаёт тип «нужно» или «можно», приоритет 1–4, готовую подпись типа и приоритета, название соседа, необязательную заметку, признаки «сосед — действие», «связь архивирована» и «сосед архивирован», обработчики нажатия на строку и на стрелку и доступные названия строки и стрелки. Предметных типов и выбора строк удержанием в компоненте нет (ADR-0030).
      - Строка — плоскость с углами `radius-lg`: для `p1`–`p3` цвет приоритета смешан на 10% с `fill`, для `p4` — чистый `fill`.
      - Над названием — метка типа 15 × 2, сплошная для «нужно» и пунктирная для «можно», и подпись стилем `label`. Для `p1`–`p3` метка цвета приоритета, подпись — этот цвет, смешанный с `ink`; для `p4` метка `grip`, подпись `muted`.
      - После подписи в 6 друг от друга — `Badge.mark` архива цвета `muted`, если сосед архивирован, и молния цвета `ink`, если сосед — действие; в приглушённой строке молния `muted`.
      - Название — стиль `action`, переносится и не обрезается. Заметка — стиль `note` цвета `muted`, не больше двух строк; без заметки её строки нет.
      - Архивированная связь — плоскость `fill`, метка `grip`, подпись и название `muted`. Связь с архивированным соседом сохраняет цвет, а название соседа `muted`.
      - Две области нажатия: строка и стрелка цвета `muted` шириной 48 на всю высоту строки.
    - Компонентные проверки в обеих темах подтверждают подкраску `p1`–`p4`, цвета метки и подписи, отметки соседа, приглушение архивированной связи и названия архивированного соседа, перенос названия, предел заметки в две строки и её отсутствие, раздельные обработчики и семантику строки и стрелки, отсутствие переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/relation_row_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/relation_row.dart` (новый), `test/design_system/relation_row_test.dart` (новый).
  - **Размер:** M.

- [ ] 6.12 Добавить в дизайн-систему строку свёрнутого архива `ArchivedFold`
  - **Критерии приёмки:**
    - По README `ArchivedFold` и решению 11 дизайна потребитель передаёт число, раскрытость, обработчик, подпись и доступное название, которое называет группу.
      - Строка стилем `label` цвета `muted`: значок архива 14, подпись, число табличными цифрами и шеврон 16, через 6 друг от друга.
      - Шеврон смотрит вниз у свёрнутого архива и вверх у раскрытого; поворот анимирован.
      - Кнопка высотой `tap-min` стоит у левого края в `space-1` от него и занимает в списке 36.
    - Компонентные проверки в обеих темах подтверждают раскладку и цвета, направление шеврона, вызов обработчика, семантику кнопки с раскрытым или свёрнутым состоянием и отсутствие переполнения при увеличенном тексте.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/archived_fold_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/archived_fold.dart` (новый), `test/design_system/archived_fold_test.dart` (новый).
  - **Размер:** S.

- [ ] 6.13 Расширить `EmptyState` шириной текста, свободными полями сверху и снизу и правилом последней строки текста
  - **Критерии приёмки:**
    - По README `EmptyState` и решению 11 дизайна потребитель может задать наибольшую ширину текста, свободное поле над заголовком и свободное поле под блоком. По умолчанию они равны 260, 0 и 40, поэтому нынешние потребители не меняются. Блок по-прежнему центрируется в оставшейся высоте, а в низком месте начинается сверху.
    - По README `EmptyState` потребитель может включить правило `pretty`: последняя строка текста не состоит из одного слова. Флаг необязателен и по умолчанию выключен, поэтому нынешние потребители не меняются. При включённом флаге, если текст занимает больше одной строки, а последняя строка состоит из одного слова, ширина текста подбирается наибольшей, не больше заданной ширины текста, при которой в последней строке не меньше двух слов, а число строк не растёт. Если такой ширины нет, применяется обычный перенос. Строки замеряются по тем же правилам, что применяет `Text`: стиль, масштаб, локаль и направление, — как в `lib/src/design_system/text_metrics.dart`.
    - Других параметров README (`minHeight`, `level`) нет: у них нет потребителя.
    - Компонентные проверки подтверждают ширину текста и оба поля для «Связей» — 270, 24 и 24 — и прежнюю раскладку по умолчанию. Остальные проверки компонента сохраняют ожидания.
    - Компонентные проверки `pretty` подтверждают, что при включённом флаге слово переносится в последнюю строку и она перестаёт состоять из одного слова, что при выключенном флаге тот же текст переносится как прежде и что без подходящей ширины применяется обычный перенос.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/design_system/empty_state_test.dart test/design_system/text_metrics_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** нет.
  - **Предполагаемые файлы:** `lib/src/design_system/components/empty_state.dart`, `lib/src/design_system/text_metrics.dart`, `test/design_system/empty_state_test.dart`.
  - **Размер:** M.

- [ ] 6.14 Вынести вид статусов порционного списка и сообщения его отказов из вкладки «Выборы» в общий вид
  - **Критерии приёмки:**
    - По решению 6 дизайна статусы, которыми владеет общий слой, имеют общий вид: первое чтение, отказ первого чтения, отсутствие намерения, подгрузка, отказ подгрузки, обновление, отказ обновления и подтверждённый конец — с прежними сообщениями отказов по категориям, индикатором, живой областью и повтором только при устранимой недоступности.
    - Вкладка «Выборы» показывает статусы общим видом. Её вид, тексты и семантика не меняются, проверки сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/daily_choice/presentation/intention_choices`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.2.
  - **Предполагаемые файлы:** `lib/src/long_term_relation/presentation/relation_list_status.dart` (новый), `lib/src/daily_choice/presentation/intention_choices/intention_choices_sliver.dart`.
  - **Размер:** S.

- [ ] 6.15 Показывать во вкладке «Связи» плитки четырёх групп и порционный список активных связей выбранной группы
  - **Критерии приёмки:**
    - По решениям 6 и 12 дизайна `IntentionRelationsSliver` строится над моделью из 6.7 и пока не стоит на странице. Название, готовность и архивное состояние владельца и сводку подробных данных он получает от страницы.
    - Плитки `CountTiles` в две колонки стоят в 8 под вкладками: «Нужно», «Можно использовать» сверху, «Нужно для», «Можно использовать для» снизу. Каждая показывает число активных связей группы, глиф её типа и направления и отметку архива, если в группе есть архивированные связи. Числа берутся из опубликованного состояния модели, а до первой публикации — из сводки подробных данных. Выбор плитки выбирает группу в модели. Доступное название плитки — название группы, число и наличие архива; группа плиток называется «Группы связей» / «Relation groups».
    - Строки активной части — `RelationRow`:
      - подпись «нужно · P1» / «need · P1», сосед с отметками архива и действия, начало описания как заметка;
      - нажатие на строку открывает подробности связи, стрелка передаёт странице соседа и группу строки;
      - доступное название строки — формулировка «Чтобы …, нужно/можно …» с владельцем и соседом по направлению, приоритет, архивные состояния и заметка; стрелки — что откроется страница соседа.

      Строки идут через `space-2`, ключ строки — `intention-relations-row-<id>`, ключ плитки — `intention-relations-group-<группа>`.
    - Подгрузка начинается при приближении к концу активной части. Статусы показывает общий вид из 6.14. Восстановление якоря после пересборки учитывает высоту закреплённых вкладок, чтобы строка не уходила под них.
    - Проверки вида на русском и английском подтверждают:
      - порядок, числа, глифы и отметки архива плиток, числа до первой публикации и выбор группы плиткой; сценарии «Все групповые количества видны до выбора списка» и «Количество возле перехода учитывает направление»;
      - состав, отметки и семантику строки, сценарий «Строка связи показывает соседа и описание», открытие подробностей связи и передачу соседа и группы стрелкой;
      - подгрузку, статусы и восстановление якоря под закреплёнными вкладками.

      Ожидания проверок долговременных групп из `relation_neighborhood_widget_test.dart`, которые относятся к строкам и статусам, воспроизведены для нового вида.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/intention_relations test/design_system/count_tiles_test.dart test/design_system/relation_row_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.7, 6.10, 6.11, 6.14.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart` (новый), `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/long_term_relation/presentation/intention_relations/intention_relations_sliver_test.dart` (новый).
  - **Размер:** M.

- [ ] 6.16 Показывать под плитками смысл выбранной группы с «Добавить» и объяснять пустую группу
  - **Критерии приёмки:**
    - По требованию «Порционное получение выбранной группы связей намерения» под плитками в 4 стоит `AddRow` с подсказкой о смысле группы:

      | Группа | Подсказка | «Добавить» для диктора |
      |---|---|---|
      | «Нужно» | «Чтобы достичь этого, нужно всё перечисленное.» / «To get there, you need each of these.» | «Добавить то, что нужно» / «Add what it needs» |
      | «Можно использовать» | «Чтобы достичь этого, можно сделать любое из перечисленного.» / «To get there, you can do any of these.» | «Добавить то, что можно использовать» / «Add what it can use» |
      | «Нужно для» | «Каждому из них это нужно.» / «Each of these needs it.» | «Добавить намерение, которому это нужно» / «Add an intention that needs it» |
      | «Можно использовать для» | «Каждое из них может использовать это как один из путей.» / «Each of these can use it, as one of the ways.» | «Добавить намерение, которое может это использовать» / «Add an intention that can use it» |

      «Добавить» передаёт странице выбранную группу. У архивированного намерения строка держит только подсказку. Ключ «Добавить» — `intention-relations-add`.
    - Группа без активных и архивированных связей показывает `EmptyState` без значка, с шириной текста 270, включённым правилом `pretty` и полями 24 сверху и снизу в оставшейся высоте под строкой «Добавить»:

      | Группа | Заголовок | Текст |
      |---|---|---|
      | «Нужно» | «Пока ничего не нужно» / «Needs nothing yet» | намерение: «Добавьте то, без чего этому намерению не обойтись.» / «Add what this intention cannot do without.»; действие: «Действие может обходиться без других. Добавьте то, что ему нужно, если у него есть свои шаги.» / «An action can stand alone. Add what it needs if it has steps of its own.» |
      | «Можно использовать» | «Пока нечего использовать» / «Nothing to use yet» | «Добавьте то, что помогает достичь этого, но не обязательно.» / «Add what helps to get there without being required.» |
      | «Нужно для» | «Пока ни для чего не нужно» / «Nothing needs it yet» | «Здесь появятся намерения, которым без этого не обойтись.» / «Intentions that cannot do without this one will appear here.» |
      | «Можно использовать для» | «Пока ни для чего не используется» / «Nothing can use it yet» | «Здесь появятся намерения, к которым это — один из путей.» / «Intentions that this one is a way to will appear here.» |

      У архивированного намерения заголовок прежний, а текст — «Чтобы добавлять связи, восстановите намерение.» / «Restore the intention to add relations.»; ширина текста, `pretty` и поля те же Группа только с архивированными связями пустой не считается. Плитки и строка «Добавить» над пустым состоянием остаются.
    - Проверки вида на русском и английском подтверждают подсказку и доступное название «Добавить» каждой группы, передачу группы, отсутствие «Добавить» у архивированного намерения, пустые состояния всех групп для намерения и действия с включённым `pretty`, в том числе у архивированного намерения, сценарии «Пустая группа архивированного намерения» и «Пустая группа не снимает блокировку другой группы» и отсутствие пустого состояния у группы только с архивом.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/intention_relations test/design_system/add_row_test.dart test/design_system/empty_state_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.13, 6.15.
  - **Предполагаемые файлы:** `lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/long_term_relation/presentation/intention_relations/intention_relations_sliver_test.dart`.
  - **Размер:** M.

- [ ] 6.17 Показывать во вкладке «Связи» свёрнутый архив группы после её активных связей
  - **Критерии приёмки:**
    - По требованию «Порционное получение выбранной группы связей намерения» и решению 6 дизайна `ArchivedFold` стоит после последней активной связи, когда активная часть получена до подтверждённого конца, а в группе есть архивированные связи. Подпись — «Архив» / «Archived», число — архивированные связи группы. Доступное название называет группу и число.
    - Нажатие раскрывает или сворачивает архив группы в модели. Раскрытый архив показывает свои строки `RelationRow` в приглушённом виде со своей подгрузкой и статусами общего вида. Восстановление якоря работает для строк обеих частей.
    - Проверки вида подтверждают:
      - отсутствие архива до конца активной части и в группе без архивированных связей;
      - раскрытие с чтением только первой порции архива группы и сворачивание;
      - раскрытый сразу архив архивированного намерения;
      - подгрузку и статусы архивной части и якорь её строки.
  - **Проверка:**
    - `mise run codegen` — локализация пересоздана.
    - `mise exec --no-deps -- flutter test test/long_term_relation/presentation/intention_relations test/design_system/archived_fold_test.dart`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.8, 6.12, 6.16.
  - **Предполагаемые файлы:** `lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart`, `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация, `test/long_term_relation/presentation/intention_relations/intention_relations_sliver_test.dart`.
  - **Размер:** M.

- [ ] 6.18 Перевести сценарии, которые только проходят через связи страницы намерения, на ключи и числа, не зависящие от вида соседства
  - **Критерии приёмки:**
    - Действие создания связи в прежнем соседстве получает ключ `intention-relations-add`, а строки связей — ключи `intention-relations-row-<id>`: те же, что у вида «Связей» из 6.15 и 6.16. Сценарии, которые этими элементами только входят в создание связи или открывают связь, используют новые ключи и сохраняют ожидания.
    - Сценарии, которые сверяли число связей по сводке соседства, сверяют его по доступному названию вкладки «Связи». Их ожидания по смыслу не меняются.
    - Поведение и вид приложения не меняются.
  - **Проверка:**
    - `rg -n "relation-neighborhood-create-relation|relation-neighborhood-row-|relation-neighborhood-summary|relationNeighborhoodSelectedGroupCount|relationNeighborhoodActiveTotal" test/app test/daily_choice` ничего не находит.
    - `mise exec --no-deps -- flutter test test/app test/daily_choice/presentation test/long_term_relation/presentation/neighborhood --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.6 — прежнее соседство уже передаёт группу, как «Добавить» новой вкладки.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart`;
    - проверки: `test/app/navigation/app_shell_back_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`, `test/app/navigation/app_shell_pages_above_test.dart`, `test/app/navigation/app_shell_operation_reset_test.dart`, `test/app/navigation/ordinary_page_layout_scenarios.dart`, `test/app/routing/app_router_test.dart`, `test/app/intention_statistics_app_flow_test.dart`, `test/app/long_term_relation_app_flow_test.dart`, `test/daily_choice/presentation/daily_choice_creation_completion_test.dart`, `test/daily_choice/presentation/daily_choice_creation_exit_test.dart`, `test/daily_choice/presentation/daily_choice_creation_route_scenarios.dart`, `test/long_term_relation/presentation/neighborhood/relation_neighborhood_widget_test.dart`.
  - **Размер:** M — замена ключей механическая.

- [ ] 6.19 Показывать на странице намерения вкладку «Связи» по дизайну вместо прежнего соседства
  - **Критерии приёмки:**
    - По решениям 2 и 6 дизайна тело вкладки «Связи» — вид из 6.15–6.17. Прежнее соседство на странице больше не показывается; его код остаётся до 6.20.
      - Модель «Связей» существует, только пока выбрана вкладка «Связи», в том числе когда над страницей открыта другая страница. До первого показа модели и чтений групп нет.
      - При уходе на другую вкладку модель освобождается вместе со строками, продолжениями и подписками. Возвращение сохраняет группу и флаги архивов и получает только первые порции показанных частей.
      - Число на вкладке «Связи» берётся из опубликованного состояния модели, пока она существует, иначе — из подробных данных.
      - Смена намерения у того же виджета начинает новый экземпляр без прежней модели.
    - Нажатие на строку открывает подробности связи. «Добавить» открывает форму создания с `RelationCreationContext(participant, group)` выбранной группы. Стрелка открывает страницу соседа с `RelationsTarget(group)` группы строки.
    - Проверки страницы подтверждают:
      - сценарии «Возвращение к связям сохраняет настройки и начинает список заново», «Открытие намерения загружает только активную группу «нужно»» и «Действие открывает группу «Нужно для»»;
      - отсутствие чтений групп при открытии на «Обзоре», «Выборах» и «Статистике»;
      - число вкладки из модели и из подробных данных;
      - сценарии «Стрелка открывает соседа на той же группе» и «Две страницы одного намерения не влияют друг на друга»;
      - сценарий «Вход из исходящей группы» и возвращение после созданной связи на «Связи» с прежней группой и новой связью в списке;
      - смену готовности на «Обзоре» после показа «Связей» и возвращение на «Связи» с прежней группой;
      - открытие подробностей связи над страницей при выбранной вкладке «Связи»: модель со строками сохраняется, после «назад» новых чтений первой порции нет и загруженные строки на месте.
    - Проверки, которые выбирали группы, архив и строки прежнего соседства на странице, переведены на плитки, архив и строки новой вкладки с прежними ожиданиями, кроме одного. В проверке «вкладка и группа переживают переключения и страницу сверху, назад закрывает страницу» из `intention_details_tabs_test.dart` после «Связи» → «Обзор» → «Связи» ожидаются новые получения первых порций показанных частей вместо неизменного числа чтений `relationGroupQueries`. Ожидание, что после возвращения со страницы сверху новых чтений нет, сохраняется. Сценарии из 6.18 сохраняют ожидания.
  - **Проверка:**
    - `mise exec --no-deps -- flutter test test/intention/presentation/details test/long_term_relation test/daily_choice/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.17, 6.18.
  - **Предполагаемые файлы:**
    - `lib/src/intention/presentation/details/intention_details_page.dart`, `lib/src/intention/presentation/details/intention_details_tabs.dart`;
    - проверки: `test/intention/presentation/details/intention_details_relations_test.dart` (новый), `test/intention/presentation/details/details_test_support.dart`, `test/intention/presentation/details/intention_details_tabs_test.dart`, `test/app/navigation/app_shell_page_matrix.dart`, `test/app/routing/app_router_test.dart`, `test/app/long_term_relation_app_flow_test.dart`.
  - **Размер:** M.

- [ ] 6.20 Удалить прежнее соседство связей
  - **Критерии приёмки:**
    - По результату фазы 6 плана в приложении нет `RelationNeighborhoodViewModel`, его состояния с `RelationGroupSelection`, `RelationNeighborhoodSliver` и их сгенерированных частей, и никакой модуль на них не ссылается.
    - Проверки модели и вида соседства удалены. Перед удалением подтверждено, что каждое их ожидание покрыто проверками ядра порций, общего слоя, модели и вида «Связей»; непокрытые ожидания перенесены туда. Общие подставные реализации из `neighborhood_test_support.dart`, которые нужны другим проверкам, сохраняются вне удаляемого каталога без частей соседства.
    - Строки локализации, которые больше нигде не используются, удалены на обоих языках. Строки, которые используют вкладки «Выборы» и «Связи», подробности связи, путь выбора и статистика, остаются.
  - **Проверка:**
    - `mise run codegen` — провайдеры и локализация пересозданы.
    - `rg -n "RelationNeighborhood|relation_neighborhood|RelationGroupSelection|relation-neighborhood-" lib test` ничего не находит.
    - `mise exec --no-deps -- flutter test test/long_term_relation test/intention test/daily_choice test/graph/presentation test/app --exclude-tags=flutter_process`.
    - `mise exec --no-deps -- flutter analyze`.
  - **Зависимости:** 6.9, 6.19.
  - **Предполагаемые файлы:**
    - `lib/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart`, `relation_neighborhood_state.dart`, `relation_neighborhood_sliver.dart` и сгенерированный провайдер (удаляются), `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` и сгенерированная локализация;
    - проверки: `test/long_term_relation/presentation/neighborhood/` (удаляется), общая поддержка проверок связей вместо `neighborhood_test_support.dart` и её потребители.
  - **Размер:** M — в основном удаление.

- [ ] 6.21 Подтвердить готовность шестой фазы: вкладка «Связи» работает по дизайну, а у списков страницы один владелец согласования с графом
  - **Критерии приёмки:**
    - Выполнено условие «Ready to advance» шестой фазы:
      - требования о порционном получении групп, навигации по связям, счётчиках страницы и входах в создание связи выполняются через вкладку;
      - цель открытия выбирает заданную группу, а две страницы одного намерения не влияют на выбранную группу, раскрытие архива и загруженные порции друг друга;
      - автоматические проверки подтверждают сохранение группы и флагов архивов при переключении вкладок, повторное получение с первой порции без восстановления прежнего объёма и освобождение прежних данных;
      - копий протокола согласования в моделях вкладок нет: гонки поздних ответов, устаревших продолжений, чужих ревизий и удаления намерения проверяются в общем слое, а модели вкладок — только по своему;
      - компонентные проверки в обеих темах покрывают обе раскладки `CountTiles`; эталоны подчиняются правилу решения 14 дизайна;
      - вся страница соответствует proposal, полная проверка проекта проходит.
    - Прежнего соседства, его переключателей и вида в приложении нет.
    - Результаты проверок и путь к APK сообщены в сессии. Ручная проверка на устройстве остаётся за пользователем и не блокирует готовность фазы.
  - **Проверка:**
    - Команда `rg` из 6.20 ничего не находит.
    - `mise run check` и `mise exec --no-deps -- openspec validate redesign-intention-page --strict --no-interactive`; после фиксации изменений — `mise run codegen-check` на чистой рабочей копии.
    - `mise exec --no-deps -- flutter build apk --release` с артефактом `build/app/outputs/flutter-apk/app-release.apk`. Если через DTD найдено запущенное приложение, выполнить hot restart и проверить `get_runtime_errors`. Эмулятор и устройство не запускаются.
    - Сообщить оставшиеся ручные проверки:
      - плитки в две колонки с числами, глифами, отметками архива и нулями; группа по умолчанию у намерения и у действия;
      - подсказка и «Добавить» под плитками, форма создания с выбранными ролью и типом;
      - строки с подкраской приоритета, отметками соседа и заметкой в две строки; стрелка открывает соседа на той же группе;
      - архив после активных связей, раскрытие и сворачивание, раскрытый архив архивированного намерения, пустые группы;
      - сохранение группы и архивов при переходе «Связи» → «Обзор» → «Связи»;
      - обе темы и увеличенный текст.
  - **Зависимости:** 6.1–6.20.
  - **Предполагаемые файлы:** нет, только проверка и сборка.
  - **Размер:** XS.
