# OpenSpec Implementation Review: add-contribution-statistics

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** В диапазоне 22a0a707cb8ca23ea56c05ddfa1b8b64da9c9500..253695f1c8d173d78b85bd7f0147d9ff624d424a существенных замечаний не обнаружено. Все семь целевых коммитов и задачи 43–49 / 4.1–4.7 покрыты единицами U1–U3: независимое состояние каталогов, обычная страница на дату, доступный переход из дня статистики и согласование через реальную навигацию. AR1, AR2 и AR3 сохранены в прежних границах; новых принятий риска нет.

## Review target

- **Baseline ref:** 22a0a707cb8ca23ea56c05ddfa1b8b64da9c9500
- **Base commit:** 22a0a707cb8ca23ea56c05ddfa1b8b64da9c9500
- **Reviewed head:** 253695f1c8d173d78b85bd7f0147d9ff624d424a
- **Target commits:** ["2bbb30145b30d59d3d91b0729df158d4c703cc39","0a8bb5772fb60e3ef7a686b4cb6fc79cba888bf4","7c7c03e7524cc7f3fd655eeef34dc49d69c05a0a","6a2dbf93067a686247aab8359f5cc7c842a57762","d592272b7200e522af0646ee3e2c9722422af456","afe9f0433ff5c7102046c4f2732660e78edd4ce0","253695f1c8d173d78b85bd7f0147d9ff624d424a"]
- **Reviewable paths:** ["lib/src/app/routing/app_router.dart","lib/src/app/routing/app_router.gr.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_instance.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart","lib/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart","lib/src/statistics/presentation/intention_statistics_calendar.dart","lib/src/statistics/presentation/intention_statistics_overview.dart","lib/src/statistics/presentation/intention_statistics_section.dart","openspec/changes/add-contribution-statistics/tasks.md","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/intention_statistics_app_flow_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/intention_statistics_navigation_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","test/statistics/presentation/intention_statistics_calendar_test.dart","test/statistics/presentation/intention_statistics_overview_test.dart","test/support/daily_choice_catalog_provider.dart"]
- **OpenSpec change:** add-contribution-statistics
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-contribution-statistics/tasks.md"]

## Reviewed increment

### U1 · Независимое состояние каждого экземпляра каталога

- **Work items:** ["43","4.1","44","4.2","45","4.3","49","4.7"]
- **Requirements and scenarios:** ["daily-choice-management / Каталог дневных выборов на заданную дату","daily-choice-management / Начальное состояние и сохранение календаря каталога","app-navigation / Сохранение состояния корневых страниц","ADR-0017 / владение выбором и просмотром","ADR-0024 / согласование отметок","ADR-0025 / отдельная модель отметок","ADR-0028 / состояние экземпляра"]
- **Affected boundary:** Страница каталога → модели выдачи и отметок → подтверждённые изменения личного графа.
- **Implementation target:** ["lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.g.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_instance.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.g.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart","test/app/daily_choice_app_lifecycle_test.dart","test/app/navigation/app_shell_state_test.dart","test/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_details_integration_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart","test/daily_choice/presentation/catalog/daily_choice_catalog_view_model_test.dart","test/graph/presentation/graph_reconciliation_checkpoint_test.dart","test/graph/presentation/package_consumers_test_support.dart","test/graph/presentation/tag_package_catalog_consumers_test.dart","test/support/daily_choice_catalog_provider.dart"]
- **Applicable constraints and non-goals:** Одинаковая начальная дата не объединяет состояния. Корневой каталог лениво начинает с местного сегодня и сохраняет условия, порции, просмотр и прокрутку весь запуск. Просмотр календаря не меняет фильтр выдачи; каждый живой экземпляр согласует отметки даже под другой страницей. Закрытие освобождает только свой экземпляр и прекращает продолжения его поздних ответов. Существующие порционность и категории отказов сохраняются.

### U2 · Каталог на дату в обычной истории и согласование нескольких каталогов

- **Work items:** ["46","4.4","48","4.6","49","4.7"]
- **Requirements and scenarios:** ["daily-choice-management / Каталог дневных выборов на заданную дату / Открытие на дату не меняет корневой каталог","app-navigation / Панель на обычных страницах / Каталог на дату из статистики сохраняет выбранный пункт","app-navigation / Сброс истории выбором пункта / Пункт «Дневные выборы» над каталогом на дату","contribution-statistics / Согласование статистики с изменениями","contribution-statistics / Отзывчивость на максимальных данных / граница выполнения команды и подсчёта","ADR-0020 / обычные страницы","ADR-0027 / чтения только при показе"]
- **Affected boundary:** Маршрутизатор → обычная страница каталога → подробности выбора, панель навигации и скрытая статистика.
- **Implementation target:** ["lib/src/app/routing/app_router.dart","lib/src/app/routing/app_router.gr.dart","lib/src/daily_choice/presentation/catalog/daily_choice_catalog_body.dart","lib/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart","test/app/intention_statistics_app_flow_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/intention_statistics_navigation_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/app/navigation/app_shell_pages_above_test.dart","test/app/navigation/app_shell_state_test.dart","test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart"]
- **Applicable constraints and non-goals:** Обязательная CalendarDate задаёт первое чтение; при открытии показана неделя заданной даты в свёрнутом календаре, фильтр охватывает все состояния. Каталог содержит все выборы дня без ограничения намерением или видом статистики и не создаёт ещё не открытый корень. Возврат сохраняет живые страницы, выбор пункта удаляет историю над сохранённой корневой страницей. Команда не ждёт подсчёта; скрытая статистика не начинает новых чтений, а при возврате обновляется.

### U3 · Доступное действие каждого дня календаря статистики

- **Work items:** ["47","4.5","48","4.6","49","4.7"]
- **Requirements and scenarios:** ["contribution-statistics / Переходы из статистики / День открывает каталог на эту дату","contribution-statistics / Переходы из статистики / Столбик месяца открывает месяц","contribution-statistics / Локализация и доступность статистики","intention-management / Раздел статистики на странице намерения"]
- **Affected boundary:** Пользователь календаря → типизированное событие дня → композиция раздела → каталог на дату.
- **Implementation target:** ["lib/src/statistics/presentation/intention_statistics_calendar.dart","lib/src/statistics/presentation/intention_statistics_overview.dart","lib/src/statistics/presentation/intention_statistics_section.dart","test/app/intention_statistics_app_flow_test.dart","test/app/intention_statistics_catalog_scenarios.dart","test/app/intention_statistics_navigation_test.dart","test/statistics/presentation/intention_statistics_calendar_test.dart","test/statistics/presentation/intention_statistics_overview_test.dart"]
- **Applicable constraints and non-goals:** Каждый реальный день, включая день без отметки, открывает именно показанную календарную дату без преобразования часового пояса; заполнители вне месяца не имеют действия. Возврат сохраняет вид, период и прокрутку статистики. Действие доступно указателю, клавиатуре и семантике экранного диктора на RU/EN с текстом 3×; годовые столбики по-прежнему выбирают месяц. Расчёты статистики, новые фильтры, настройки и вкладки намерения не входят в инкремент.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий изолированный агент /root/decision_review, fork_turns=none, навык implementation-decision-review. Переданы только нейтральные намерения U1–U3, ограничения, точные SHA, семь целевых commit ID и объединение всех 33 путей. Общие изменённые файлы требуют одного reviewer для группы пересечения. Планирование, описания и история коммитов, прежние находки и риски не передавались. Reviewer проверил полный diff и неизменённый контекст после diff --quiet; результат No substantive findings, покрытие Complete. Проход статический, без запуска Flutter. |
| OpenSpec conformance | Complete | Все семь задач и коммитов сопоставлены с требованиями и сценариями; проверены обе стороны соответствия, отметки завершения и необходимость новых элементов. Проверки на чистом reviewed head: mise run --skip-tools check — повторный полный прогон exit 0; mise run --skip-tools codegen-check — exit 0; mise exec --no-deps -- openspec validate add-contribution-statistics --strict --no-interactive --json — exit 0, valid=true, issues=[]. Первый невоспроизведённый сбой и границы проверки описаны ниже. |
| Code quality | Complete | По code-review-and-quality проверены все 33 пути U1–U3 и затронутый контекст: корректность, читаемость, архитектура, безопасность и производительность. Проверены владение состоянием, autoDispose, поколения и ревизии, отдельная прокрутка, обычная история и сброс, поздние ответы, типизированная дата, семантика и клавиатура. Существенных дефектов, дублирования общих механизмов и неоправданного расширения не установлено. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Скрытое продолжение уведомления недоступно с клавиатуры

- **Evidence:** На исходной ревизии `31c3aa02f55084f401e5b735033a4fd081f57513` `lib/src/statistics/presentation/home_statistics_content.dart:264` и `:280` помещают только Semantics → Text в отдельный SingleChildScrollView(primary: false), без доступного клавиатурного фокуса; TextButton повтора (`:285`) — его сосед. Клавиатурная прокрутка не достигает этого Scrollable. Временный probe на исходниках указанной исходной ревизии при 320×700, RU/EN и тексте 3× подтвердил: при фокусе на повторе после PageDown и ArrowDown смещение уведомления остаётся 0, хотя максимальное смещение положительно. Новый тест `test/statistics/presentation/home_statistics_content_test.dart:421` читает скрытый текст перетаскиванием, а с клавиатуры (`:436`) проверяет только запуск повтора. На reviewed head механизм перенесён в `lib/src/statistics/presentation/statistics_read_notice.dart:62` и `:74`: прокручиваемый Semantics → Text по-прежнему не получает клавиатурного фокуса, а повтор остаётся соседней кнопкой (`:82`). Главная передаёт `scrollMessage: true`; новая клавиатурная навигация по самому сообщению не добавлена. Прежнее воспроизведение относится к исходной ревизии, в этой сессии оно не повторялось.
- **Evidence revisions:** ["31c3aa02f55084f401e5b735033a4fd081f57513", "b4d00e2361e1d71455657847afb22f07e296d290"]
- **Potential impact:** Пользователь с клавиатурой и крупным текстом видит лишь начало длинного сообщения об отказе обновления; прочитать его полностью без указателя нельзя, хотя повтор доступен. Обещанная задачей 1.13 доступность сообщения остаётся неполной.
- **Acceptance rationale:** На текущем этапе владелец сосредоточен на логике и базовом отображении и явно предпочёл не добавлять доработку клавиатурного фокуса и прокрутки с регрессионной проверкой до работы над окончательным интерфейсом. Ограничение сохраняется; корректирующая задача 1.14 не планируется.
- **Scope and assumptions:** Только полное чтение длинного сообщения об отказе обновления Главной с клавиатуры при крупном тексте в рамках активного изменения add-contribution-statistics. Прокрутка указателем и допустимый повтор остаются доступны, прежние числа и позиция каталога сохраняются. Принятие не распространяется на F3 и не отменяет требования доступности окончательного интерфейса.
- **Reopen when:** Начинается работа над окончательным интерфейсом статистики либо поступает сообщение пользователя о невозможности дочитать уведомление с клавиатуры.
- **Acceptance authority:** Явный ответ владельца в исходной сессии принятия риска: «Да, принять F2 как остаточный риск на этих условиях» — после описания ограничения, отказа от задачи 1.14 и обоих условий пересмотра.
- **Originating finding:** F2
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

### AR2 · В низком окне сообщение с крупным текстом обрезается по высоте

- **Evidence:** На исходной ревизии `31c3aa02f55084f401e5b735033a4fd081f57513` `lib/src/statistics/presentation/home_statistics_content.dart:76` разрешает уведомлению не более половины доступной высоты. Внутри `:270` и `:276` сообщение получает лишь остаток после вертикальных отступов 16 dp и непрокручиваемой кнопки. Воспроизведение при 700×360, тексте 3×, AppBar и нижней области 64 dp, соответствующей `lib/src/app/navigation/app_navigation_bar.dart:28`, оставляет прокрутке сообщения 28 dp при высоте строки 60 dp; результат одинаков для RU/EN. Даже один символ по высоте не помещается целиком. Альбомная ориентация не запрещена в `android/app/src/main/AndroidManifest.xml`; оболочка действительно вычитает панель из области Главной (`lib/src/app/navigation/app_shell_page.dart:35`). Новый тест `test/statistics/presentation/home_statistics_content_test.dart:361` ограничен высоким окном 320×700 и проверяет попадание в отдельную точку текста, что не доказывает читаемость строки. На reviewed head ограничение половиной высоты сохраняется в `lib/src/statistics/presentation/home_statistics_content.dart:78`, а прежние отступы, Flexible с прокруткой текста и отдельная кнопка — в `lib/src/statistics/presentation/statistics_read_notice.dart:68`. Извлечение общего компонента не устраняет причину обрезания. Исходное воспроизведение низкого окна в этой сессии не повторялось.
- **Evidence revisions:** ["31c3aa02f55084f401e5b735033a4fd081f57513", "b4d00e2361e1d71455657847afb22f07e296d290"]
- **Potential impact:** После отказа обновления в достижимом альбомном окне пользователь видит узкую обрезанную полосу сообщения. Прокрутка меняет обрезанный фрагмент, но не позволяет прочитать строку целиком.
- **Acceptance rationale:** Владелец сосредоточен на логике и базовой работоспособности интерфейса и явно принял это ограничение до работы над окончательным интерфейсом. Доработка распределения высоты уведомления и регрессионная проверка низкого окна на RU/EN откладываются; корректирующая задача 1.14 не добавляется. Условие риска остаётся в реализации.
- **Scope and assumptions:** Только читаемость сообщения об отказе обновления Главной в низком окне при крупном тексте на RU/EN в рамках активного изменения add-contribution-statistics. Допустимый повтор остаётся доступен, прежние числа, выбранные период и вид, загруженные элементы и позиция каталога сохраняются. Принятие не меняет правила расчёта, обновления и хранения статистики и не отменяет требования доступности окончательного интерфейса.
- **Reopen when:** Начинается работа над окончательным интерфейсом статистики либо поступает жалоба пользователя на обрезанное сообщение об отказе обновления в низком окне при крупном тексте.
- **Acceptance authority:** Явный ответ владельца «Да» в исходной сессии принятия риска на вопрос «Подтверждаете принятие F3 на этих условиях?» после описания обрезанного сообщения, отказа от задачи 1.14 и пересмотра при работе над окончательным интерфейсом или жалобе пользователя. Владелец пояснил приоритет: «Я сейчас сосредотачиваюсь на логике, а не на интерфейсе».
- **Originating finding:** F3
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

### AR3 · Два измеренных превышения бюджетов приняты для завершения Phase 2

- **Evidence:** На исходной ревизии `6b0321b9b95c4f33c249c8d0f16697fb61e9ec04` в `openspec/changes/add-contribution-statistics/tasks.md:329`, задача 2.11, записано решение владельца о двух превышениях: p95 чтения названий годовой порции длинного профиля с готовым снимком после архивирования 10,973 мс при бюджете 10 мс и p95 подтверждения команды во время поздней годовой порции длинного профиля до архивирования 80,576 мс при бюджете 50 мс. На той же исходной ревизии сохранено повторное измерение первого условия 11,666 мс; причина не установлена. Свидетельства и решение перенесены из предыдущего отчёта; причина превышений отдельно не пересматривалась.
- **Evidence revisions:** ["6b0321b9b95c4f33c249c8d0f16697fb61e9ec04"]
- **Potential impact:** Указанные задержки могут выходить за исходные числовые ориентиры. После явного решения владельца из design.md, решения 10, временные превышения выводятся отдельным бенчмарком и больше не отклоняют регулярный check. Изменение способа запуска не доказывает устранение причины задержек.
- **Acceptance rationale:** Владелец признал текущую производительность удовлетворительной для закрытия 2.11 и отнёс отдельное профилирование и оптимизацию к следующим изменениям. Это исключение из приёмки Phase 2, а не отмена проверок или изменение бюджетов.
- **Scope and assumptions:** Только условия двух названных превышений и приёмка Phase 2 активного изменения. Корректность, выполнение команды до окончания подсчёта, остальные бюджеты и Phase 1 остаются обязательными. Превышения в иных сериях, профилях или бюджетах не принимаются автоматически. Новый общий допуск времени не установлен; принятие не распространяется на исправление каскадного чтения.
- **Reopen when:** Появляются превышения вне принятой области, нарушается функциональная корректность или подтверждение команды до окончания подсчёта, либо начинается предусмотренное владельцем отдельное профилирование.
- **Acceptance authority:** Явное решение владельца, сохранённое в `openspec/changes/add-contribution-statistics/tasks.md`, задача 2.11, блок «Решение владельца при подтверждении готовности», на исходной и текущей ревизиях. Дополнительное принятие риска от имени владельца не выполнялось.
- **Originating finding:** F5
- **Acceptance lifetime:** Change-scoped
- **Current target relation:** Carried forward; not re-reviewed

## Review coverage

Discovery выполнен штатным discover-review-target.mjs с точными полными SHA и --openspec /tmp/contribution-review-openspec; обёртка вызывает только mise exec --no-deps -- openspec. Инвентарь: 34 пути, из них 33 пути реализации и тестов в U1–U3 и tasks.md как свидетельство планирования. Несопоставленных или посторонних путей нет. Диапазон исключает base и включает head; проверены все семь коммитов и их отдельные сохранённые диапазоны. Движение ветки не меняло цель ревью.

Версионное намерение сверено с proposal.md, четырьмя delta-specs, design.md, adr.md, plan.md, задачами Phase 4 и CONTEXT.md из записанного head, включая применимые ADR-0009, ADR-0017, ADR-0020, ADR-0024, ADR-0025, ADR-0027 и ADR-0028. CLI status и instructions apply использованы только для чтения метаданных; схема intent-driven, задачи 43–49 завершены. Незакоммиченных источников намерения нет. Реализация предыдущих фаз вне целевого diff использована как контекст и проверена регрессионным набором; отметка 4.7 не превращает её в новый целевой диапазон.

U1: DailyChoiceCatalogInstance использует равенство по идентичности и хранит типизированную начальную CalendarDate. Корневая страница создаёт ключ один раз при первом построении; тело получает его через ObjectKey. Семейства выдачи и отметок получают один и тот же ключ; generated-код сохраняет autoDispose и различает аргументы по идентичности. Тело владеет просмотром, наблюдателем местного дня и отдельным PageStorageBucket. При выделении тела из страницы в коммите 7c7c03e7524cc7f3fd655eeef34dc49d69c05a0a выдача, фильтры, сообщения и переход к подробностям перенесены без изменения поведения; отдельное хранилище прокрутки необходимо для двух текущих потребителей. Существующие защита поколений, согласование ревизий и освобождение подписок сохранены. Механическая адаптация тестовых потребителей использует реальный уже открытый экземпляр и не создаёт корень раньше страницы.

U2: DailyChoiceDateCatalogPage создаёт собственный ключ из обязательной даты до построения тела; обычный каркас предоставляет панель и возврат. AppRouter и generated-маршрут передают CalendarDate без строки или преобразования часового пояса. Новый маршрут использует существующую общую историю и механизм сброса AppNavigation. Проверки страницы подтверждают первое чтение только заданного дня, отсутствие раннего корневого экземпляра, независимость двух открытий одной даты, возврат из подробностей с прежней прокруткой, освобождение и повторное открытие. Новые сквозные сценарии на SQLite и GraphCommandCoordinator проверяют выполнение, перенос даты, отметки каждого живого каталога, сохранение 100 загруженных записей, условий и просмотра, чужой для статистики выбор того же дня, сброс к корню и отсутствие возврата истории после позднего чтения. Отдельный сценарий удерживает подсчёт, выполняет настоящую команду через новый каталог и подтверждает завершение команды до результата подсчёта, отсутствие скрытых чтений и одно обновление статистики после возврата.

U3: Календарь передаёт ValueChanged<CalendarDate> через обзор; только композиция раздела открывает маршрут. Реальные дни стали TextButton, заполнители остались без действия. Использована существующая локализованная полная дата и состояние дня; дополнительная строка не понадобилась. Проверки календаря подтверждают 31 доступное действие октября, кнопку и tap в семантике, активацию клавиатурой, отмеченные и пустые дни, RU/EN и текст 3×. Проверка настоящей навигации подтверждает переданную дату, прежний выбранный пункт, вид, период и точное смещение статистики после возврата. Существующий тест годовых столбиков сохраняет выбор месяца клавиатурой.

Проход качества по code-review-and-quality охватил корректность, читаемость, архитектуру, безопасность и производительность всех 33 путей. Новый ключ и общий виджет нужны текущим независимым страницам; сетка не получила зависимости от маршрутизатора или репозитория. Условие страницы-задания, границы подтверждённых команд и категории отказов не дублируются. Дополнительных записей в хранилище, изменений схемы, зависимостей, диагностического пользовательского содержимого или тяжёлых расчётов диапазон не вводит. Новые тесты различают реальные регрессии экземпляров, маршрута и действия дня; повторные проверки общих правил вычисления статистики не добавлены.

Все проверки выполнены в этой сессии в /home/seniorkonung/.paseo/worktrees/1id27gtb/tearful-gorilla при HEAD=253695f1c8d173d78b85bd7f0147d9ff624d424a и чистом рабочем дереве, до записи отчёта. Результаты ниже относятся именно к этому снимку.

Сопоставление каждого сохранённого диапазона задачи:

Задача ID 43 / 4.1: сохранённый диапазон 22a0a707cb8ca23ea56c05ddfa1b8b64da9c9500..2bbb30145b30d59d3d91b0729df158d4c703cc39, целевой коммит 2bbb30145b30d59d3d91b0729df158d4c703cc39, единицы U1.

Задача ID 44 / 4.2: сохранённый диапазон 2bbb30145b30d59d3d91b0729df158d4c703cc39..0a8bb5772fb60e3ef7a686b4cb6fc79cba888bf4, целевой коммит 0a8bb5772fb60e3ef7a686b4cb6fc79cba888bf4, единицы U1.

Задача ID 45 / 4.3: сохранённый диапазон 0a8bb5772fb60e3ef7a686b4cb6fc79cba888bf4..7c7c03e7524cc7f3fd655eeef34dc49d69c05a0a, целевой коммит 7c7c03e7524cc7f3fd655eeef34dc49d69c05a0a, единицы U1.

Задача ID 46 / 4.4: сохранённый диапазон 7c7c03e7524cc7f3fd655eeef34dc49d69c05a0a..6a2dbf93067a686247aab8359f5cc7c842a57762, целевой коммит 6a2dbf93067a686247aab8359f5cc7c842a57762, единицы U2.

Задача ID 47 / 4.5: сохранённый диапазон 6a2dbf93067a686247aab8359f5cc7c842a57762..d592272b7200e522af0646ee3e2c9722422af456, целевой коммит d592272b7200e522af0646ee3e2c9722422af456, единицы U3.

Задача ID 48 / 4.6: сохранённый диапазон d592272b7200e522af0646ee3e2c9722422af456..afe9f0433ff5c7102046c4f2732660e78edd4ce0, целевой коммит afe9f0433ff5c7102046c4f2732660e78edd4ce0, единицы U2, U3.

Задача ID 49 / 4.7: сохранённый диапазон afe9f0433ff5c7102046c4f2732660e78edd4ce0..253695f1c8d173d78b85bd7f0147d9ff624d424a, целевой коммит 253695f1c8d173d78b85bd7f0147d9ff624d424a, единицы U1, U2, U3.

Коммиты 4.1 и 4.2 меняют области жизни моделей и их потребителей; 4.3 выделяет общее тело; 4.4 добавляет обычный маршрут; 4.5 добавляет событие дня и действие; 4.6 добавляет сквозные проверки. Коммит задачи 4.7 меняет только её отметку завершения: утверждения контрольной точки сверены с шестью предыдущими коммитами и выполненными проверками. В tasks.md различия с base ограничены семью отметками завершения Phase 4; описания и порядок всех 49 задач совпадают.

«Открытие на дату не меняет корневой каталог»; независимость одинаковых дат: test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart:69; test/app/intention_statistics_catalog_scenarios.dart:115.

«Первый просмотр выбирает сегодня»; корень не создаётся каталогом на дату: test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart:25; test/daily_choice/presentation/catalog/daily_choice_catalog_lifecycle_test.dart:236.

«Перезапуск на следующий день»: test/app/daily_choice_app_lifecycle_test.dart:610.

«Возврат из другого раздела сохраняет просмотр» и прежние порции: test/app/navigation/app_shell_state_test.dart; test/app/intention_statistics_catalog_scenarios.dart:115.

«Каталог на дату из статистики сохраняет выбранный пункт»: test/app/intention_statistics_navigation_test.dart:201; test/app/navigation/app_shell_page_matrix.dart:107.

«Пункт „Дневные выборы“ над каталогом на дату»; повторный выбор Главной и поздний ответ: test/app/intention_statistics_catalog_scenarios.dart:4.

«День открывает каталог на эту дату» и возврат к прежнему разделу: test/app/intention_statistics_navigation_test.dart:201.

«Столбик месяца открывает месяц»: test/statistics/presentation/intention_statistics_calendar_test.dart:72.

Доступность действия дня, пустые дни и отсутствие действия заполнителей; RU/EN, текст 3×: test/statistics/presentation/intention_statistics_calendar_test.dart:16 и :116.

Выполнение и перенос даты согласуют каталоги; скрытая статистика не читает, команда завершается до подсчёта: test/app/intention_statistics_catalog_scenarios.dart:115 и :295.

Закрытие освобождает состояние и поздние ответы не запускают продолжения: test/daily_choice/presentation/catalog/daily_choice_date_catalog_page_test.dart:165; новые проверки двух модельных семейств.

Команда mise run --skip-tools check — повторный полный прогон exit 0: форматирование 623 файлов, 0 изменений; проверки CI scope, анализ Flutter, 2668 тестов приложения и 4 теста Widgetbook прошли. Проверки сценариев Phase 4 входят в этот набор. Журнал текущей сессии: /tmp/contribution-review-check-retry.log.

Первый полный прогон той же команды завершился exit 1: 2667 тестов прошли, один тест test/graph/data/tag_assignment_integration_test.dart («два потребителя намерения согласуют полные снимки и изменения графа») получил Bad state при подготовке локального хранилища и затем LateInitializationError в tearDown. Тест, LocalDatabaseHarness и production bootstrap в целевом диапазоне не менялись; bootstrap завершился до создания моделей каталога. Отдельная команда mise exec --no-deps -- flutter test --no-pub test/graph/data/tag_assignment_integration_test.dart прошла, exit 0, 1 тест; затем повторный полный check прошёл без изменений исходников. Причина первого сбоя не установлена; исправление или принятие этого условия не заявляется. Первоначальный журнал сохранён в /tmp/contribution-review-check.log.

Команда mise run --skip-tools codegen-check — exit 0: build_runner записал 0 outputs, повторная генерация локализации, кода и схемы сохранила lockfile и чистое дерево. Журнал: /tmp/contribution-review-codegen.log.

Команда mise exec --no-deps -- openspec validate add-contribution-statistics --strict --no-interactive --json — exit 0, valid=true, issues=[]. Это структурная проверка планирования, а не доказательство поведения. После записи отчёта его формат отдельно проверяется штатным node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/add-contribution-statistics/implementation-review.md; точные SHA, порядок коммитов и покрытие путей сверяются с Git.

DTD после roots add с URI рабочего каталога не обнаружил запущенного приложения. Предусмотренный задачей 4.7 CLI-вариант выполнен; hot reload/restart, runtime errors, настоящий экранный диктор и наблюдения на устройстве не подтверждены. Повторные p95 и бенчмарки не запускались: этот диапазон меняет состояние и переходы представления, а не измеренные вычисления. Прежние числовые бюджеты и ограничения измерений сохраняются.

AR1–AR3 перенесены без изменения исходных доказательств и полномочий владельца. Упоминание reviewed head внутри свидетельств AR1–AR2 относится к b4d00e2361e1d71455657847afb22f07e296d290 из их Evidence revisions, а не к текущему head. Механизмы уведомления Главной и причины задержек Phase 2 в данном диапазоне не меняются; условия пересмотра не установлены. Принятие не расширено на новый каталог, доступность действия дня или новые отказы проверок.

Коррекции кода и планирования не потребовались; новых задач, решений владельца или принятий риска нет. IDs, номера, описания, порядок и завершённые отметки существующих задач сохранены. Единственное авторское изменение стадии — implementation-review.md. Дальнейшего исправления находок в этом отчёте не требуется. Отчёт фиксирует ограниченное ревью и не является разрешением на merge, archive или новым принятием риска.
