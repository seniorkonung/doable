# OpenSpec Implementation Review: show-and-filter-intention-tags

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 3.18–3.27 реализованы, и полная проверка на head проходит: общий элемент выдачи один владеет верхней позицией при смене параметров и размещением отказа обновления на четырёх страницах, комментарий `_CatalogChangePackage` верен коду, сквозные утверждения о выборе различают намерения по идентификатору, тесты для устройства удалены без потери хостовых проверок. Остаётся одна находка низкой значимости F1: общий элемент запоминает исходные параметры поиска не при создании, а при первом уведомлении модели, поэтому первая смена параметров на элементе, смонтированном поверх уже загруженной выдачи, не открывает выдачу с верхней позиции. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 7ba58867052b8ce53eb5a962f41ab985794b6b95
- **Base commit:** 7ba58867052b8ce53eb5a962f41ab985794b6b95
- **Reviewed head:** 1e5f4447e8417d6d648dbca6f7a84f5c62609359
- **Target commits:** ["6c068ab291bfd00f4157263816147708f64ab37b","73ec1863de559b247631eda6efdd0b6ee00a3dd8","34a8ae558e31f6f5ccb81fdb97a41c4a7151361f","73e93de892a639bd81e78fd294b54a63bc131485","83fe0a65ab6bfe1b5a015655fd5276025fd5a3c4","525b71fc2f9072e2f902da4afd2685f4a0a4c7b6","88eb7efc4a8afa5ce6f4c21b6175418b40ddd400","f1dfa7eb2aa7610cf0a9f737a2ce5fd65be3ac6f","6de8bb8de705d531d2ce5a663ac545ca163abf36","1e5f4447e8417d6d648dbca6f7a84f5c62609359"]
- **Reviewable paths:** ["integration_test/tag_catalog_read_cost_test.dart","integration_test/tag_selection_stability_test.dart","lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart","lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart","lib/src/intention/presentation/catalog/intention_catalog_page.dart","lib/src/intention/presentation/catalog/intention_catalog_view_model.dart","lib/src/intention/presentation/catalog/intention_search_results.dart","lib/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart","openspec/changes/show-and-filter-intention-tags/tasks.md","pubspec.lock","pubspec.yaml","test/app/intention_tag_search_app_flow_test.dart","test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart","test/graph/data/drift_tag_catalog_read_cost_test.dart","test/intention/presentation/catalog/intention_catalog_page_test.dart","test/intention/presentation/catalog/intention_search_results_test.dart","test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart","test_driver/integration_test.dart"]
- **OpenSpec change:** show-and-filter-intention-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/show-and-filter-intention-tags/tasks.md"]

## Reviewed increment

### U1 · Общий элемент выдачи владеет верхней позицией при смене параметров и размещением отказа обновления на четырёх страницах поиска

- **Work items:** ["3.18","3.19","3.21","3.22","3.23","3.24","3.25"]
- **Requirements and scenarios:** ["intention-management: Согласованность параметров совместного поиска","intention-management: Сохранение условия после физического удаления тега — сценарий «Явное удаление сохранённого условия возобновляет поиск»","design: решение 6 — размещение отказа обновления поверх списка без сдвига строк","design: решение 7 — общий элемент выдачи поиска"]
- **Affected boundary:** Пользователь каталога намерений, поиска действия, поиска исходного намерения и поиска участника долговременной связи; слой представления поиска намерений.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_search_results.dart","lib/src/intention/presentation/catalog/intention_catalog_page.dart","lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart","lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart","lib/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart","test/intention/presentation/catalog/intention_search_results_test.dart","test/intention/presentation/catalog/intention_catalog_page_test.dart","test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart","test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart","test/app/intention_tag_search_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Смена параметров начинает выдачу с верхней позиции независимо от того, показан ли список; обновление без смены параметров позицию сохраняет. Отказ обновления не меняет ни смещение, ни экранное положение строк и отличим от успешной пустоты. Каталог сохраняет якорь видимого намерения и место под кнопку создания. Ограничения назначений поиска, выбор по идентификатору и запрет самосвязи сохраняются; элемент не читает граф, не выполняет команд и не меняет условия. Правила отбора, чтения репозитория и согласование модели вне объёма.

### U2 · Комментарий каталожной части подтверждённого пакета называет действительного гаранта каталожной мутации

- **Work items:** ["3.20"]
- **Requirements and scenarios:** ["tasks: 3.20 — документация без изменения поведения"]
- **Affected boundary:** Сопровождающие модели каталога намерений.
- **Implementation target:** ["lib/src/intention/presentation/catalog/intention_catalog_view_model.dart"]
- **Applicable constraints and non-goals:** Меняются только строки комментария; исполняемый код модели, контракт `TagAssignmentChanged` и тесты остаются прежними, проверка на стороне модели не возвращается.

### U3 · Сквозные утверждения о явном выборе намерения различают верный и неверный результат

- **Work items:** ["3.26"]
- **Requirements and scenarios:** ["daily-choice-management: явный выбор действия по идентификатору","long-term-relation-management: идентичность выбора участника связи среди одноимённых намерений"]
- **Affected boundary:** Набор тестов как свидетельство для вызывающих сценариев страниц поиска.
- **Implementation target:** ["test/app/intention_tag_search_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Меняется только тест; сохранённый граф после выбора не меняется, остальные утверждения не ослабляются, тест выполняется на хосте на обоих языках.

### U4 · Тесты, требующие Android-устройства, и их обвязка удалены

- **Work items:** ["3.27"]
- **Requirements and scenarios:** ["tasks: 3.27 — решение пользователя не поддерживать тесты только для устройства"]
- **Affected boundary:** Разработчики и CI, выполняющие проверки репозитория.
- **Implementation target:** ["integration_test/tag_catalog_read_cost_test.dart","integration_test/tag_selection_stability_test.dart","test_driver/integration_test.dart","pubspec.yaml","pubspec.lock","test/graph/data/drift_tag_catalog_read_cost_test.dart"]
- **Applicable constraints and non-goals:** Хостовые тесты сохраняются с прежними ожиданиями; `pubspec.lock` содержит только удаление записей без смены версий; исторические свидетельства в `openspec/changes/archive/` и `docs/verification/` не переписываются; поведение приложения не меняется.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Три свежих изолированных ревьюера получили только нейтральные брифы и точный диапазон. Группа U1+U3 с общим путём `test/app/intention_tag_search_app_flow_test.dart` проверена одним ревьюером на десяти путях; по его запросу группа расширена единственным путём U2 `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart`, после чего он подтвердил полное покрытие одиннадцати путей. U2 отдельно проверен вторым ревьюером на том же пути, U4 — третьим на шести путях. Ревьюеры U2 и U4 находок не вернули; ревьюер U1+U3 вернул две находки низкой значимости: первая подтверждена как F1, вторая опровергнута фактами репозитория (см. Review coverage). |
| OpenSpec conformance | Complete | На чистой рабочей копии с `HEAD` = 1e5f4447e8417d6d648dbca6f7a84f5c62609359: `mise run --skip-tools check` — формат без изменений, `flutter analyze` без замечаний, 2989 тестов прошли, включая медленные; `mise run --skip-tools codegen-check` и `codegen-check-test` — код выхода 0, рабочая копия осталась чистой; `mise exec --no-deps -- openspec validate show-and-filter-intention-tags --type change --strict --no-interactive --json` — valid, без замечаний. Проверки поиска из задач 3.22, 3.25 и 3.27 воспроизведены: `_scrollToTop`, `_CatalogScrollController`, `_ExtentObserver` и `IntentionCatalogRefreshStatusArea(` на четырёх страницах отсутствуют; каталогов `integration_test/` и `test_driver/` нет; diff `pubspec.lock` содержит только удаления. Отметки задач 3.18–3.27 в `tasks.md` соответствуют диапазону. |
| Code quality | Complete | Корректность, читаемость, архитектура, безопасность и производительность проверены по всем путям поставки и тестов на head: жизненный цикл контроллера и отложенных обратных вызовов, смена хранилища позиции, якорь каталога, место под отказ перед началом выдачи, подключение четырёх страниц, различающая способность новых утверждений, состав удалённых записей `pubspec.lock`. F1 воспроизведена временным тестом на head, который в коммит не вошёл. |

## Findings

### F1 · Low — Общий элемент выдачи запоминает исходные параметры поиска при первом уведомлении модели, а не при создании

- **Evidence:** `lib/src/intention/presentation/catalog/intention_search_results.dart:116` объявляет `late _SearchParameters _parameters = _currentParameters();`. Инициализатор `late`-поля выполняется при первом чтении, а единственное чтение — сравнение в `_handleCatalogStateChanged` (`:313`); `ref.listen` (`:142`) при подписке слушателя не вызывает. Если первое уведомление после создания элемента вызвано самой сменой параметров, база инициализируется уже изменённой выборкой, сравнение даёт равенство и `_startFromTop()` (`:334`) не вызывается: список снимается состоянием загрузки и возвращается из прежнего `_listStorage` с сохранённым смещением. Воспроизведено на head временным тестом по образцу `test/intention/presentation/catalog/intention_search_results_test.dart`: провайдер загружен до монтирования элемента, список прокручен до 300, смена порядка — ожидалось смещение 0, получено 300. В обычном потоке первое уведомление — исходная загрузка, поэтому тесты диапазона, всегда проходящие через неё, дефект не обнаруживают. Реальный путь узок: провайдер `intentionCatalogViewModelProvider` автоудаляемый и живёт вместе со страницей, поэтому нужен повторный вход на страницу с тем же назначением, пока прежний экземпляр ещё удерживает провайдер (например, во время перехода закрытия поиска действия или исходного намерения). До диапазона страницы переходили к началу безусловно в обработчиках элементов управления.
- **Evidence revisions:** ["1e5f4447e8417d6d648dbca6f7a84f5c62609359"]
- **Impact:** В узком окне нарушается требование «Согласованность параметров совместного поиска»: новая выдача открывается с устаревшего смещения, а не с верхней позиции. Гарантия неявно зависит от того, что до первой смены параметров придёт нейтральное уведомление модели; элемент этого не обеспечивает, и будущая смена времени жизни провайдера или порядка монтирования сделает дефект постоянным без падения существующих тестов.
- **Required outcome:** Базой сравнения служат параметры поиска, действующие в момент создания состояния элемента или смены назначения, независимо от того, пришло ли уже уведомление провайдера; первая смена параметров после монтирования на загруженную выдачу открывает выдачу со смещением ноль, и это закреплено тестом общего элемента.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/catalog/intention_search_results.dart","test/intention/presentation/catalog/intention_search_results_test.dart"]

## Review coverage

Проверены все 18 путей диапазона `7ba58867052b8ce53eb5a962f41ab985794b6b95..1e5f4447e8417d6d648dbca6f7a84f5c62609359`; `tasks.md` использован как свидетельство планирования, прежний отчёт находок и принятых рисков не содержал, переносить нечего.

U1: Общий элемент: контроллер освобождается, отложенные обратные вызовы защищены `mounted`/`attached`; смена параметров заменяет хранилище позиции и переводит показанный список к нулю; обновление без смены параметров, включая возврат выдачи после временной пустоты, позицию сохраняет; место под отказ отводится перед началом выдачи через `minScrollExtent`, список в начале остаётся в начале. Модель публикует состояние при каждой смене охвата, порядка, названия и условий по тегам (`changeScope`, `changeOrder`, `changeTitleFilter`, `changeTagFilter` → `ref.invalidateSelf()`), а `selection` обновляется до публикации. Каталог подключает якорь видимого намерения и место под кнопку создания явными параметрами; три страницы выбора собственных слушателя, перехода к началу и компоновки отказа не содержат.

Опровергнутая находка ревьюера: Предположение, что скрытая строка второго участника в поиске участника связи (`relation_participant_picker_page.dart:125-127`) завышает число элементов списка для вспомогательных технологий, не подтверждено: исключённое намерение не попадает в выдачу — его отсекают запрос репозитория (`drift_personal_graph_repository.dart:1221-1225`) и предикат принадлежности каталога (`intention_catalog.dart:187`); ветка страницы остаётся защитной и в достижимых состояниях не срабатывает.

U2: Diff содержит только четыре строки комментария; каждое утверждение комментария сверено с `TagAssignmentChanged` (`lib/src/tag/application/tag_result.dart`) и `_applyPackage` модели.

U3: Выбор действия сверяет `ChoicePathPage.sourceIntentionId` с идентификатором нажатой строки; выбор участника сверяет архивное состояние в редакторе связи и идентификатор открытых подробностей (намерение 7, не 5); сохранённый граф по-прежнему сравнивается.

U4: Удалённые записи `pubspec.lock` (`integration_test`, `flutter_driver`, `fuchsia_remote_debug_protocol`, `process`, `sync_http`, `webdriver`) больше ничем не требуются, версии остальных пакетов не менялись; ссылок на удалённую обвязку в `mise.toml`, CI и скриптах нет. Хостовые тесты сохраняют утверждения удалённых тестов о стабильности выбора и стоимости чтения; исчезает только неутверждаемая запись времени кадров при прокрутке 10 000 строк на устройстве — следствие решения пользователя, зафиксированного в задаче 3.27.

Не проверялось кодом или тестами диапазона: Порядок обхода экранным диктором отказа, лежащего поверх списка; свидетельство доступности подтверждено только прохождением `test/intention/presentation/intention_tag_search_accessibility_test.dart` в составе полной проверки.
