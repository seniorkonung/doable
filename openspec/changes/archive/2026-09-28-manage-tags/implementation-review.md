# OpenSpec Implementation Review: manage-tags

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены все шесть целевых коммитов и задачи 86–91 (4.1–4.6). Навигация сохраняет типизированный отказ наблюдения после окончания потока и любого позднего ответа страницы; явное восстановление требует новой подписки и согласованной первой порции. Три прохода завершены, существенных нерешённых замечаний и принятых остаточных рисков нет. На reviewed head прошли 399 тестов выбранного набора, генерация, анализ, форматирование и обе валидации OpenSpec. Вывод ограничен восстановлением навигации в фазе 4.

## Review target

- **Baseline ref:** 77521632d914688213e607693fb1e6cbfd48bf9a
- **Base commit:** 77521632d914688213e607693fb1e6cbfd48bf9a
- **Reviewed head:** a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf
- **Target commits:** ["bdc5f8b12fc92f32206137d940b1eb87ce88341a", "8c71302ff1bfcf33433d168b0c02b81e4fa5782f", "3ce2cd18006c3b38d6cb6341f28d130b03d07656", "e6cbdc02516a20db06ea518ddc9a24bd5937c37b", "38a3e7d8e16555b2f72454d3c40ba71fd448c9c1", "a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf"]
- **Reviewable paths:** ["lib/src/tag/presentation/navigation/tag_navigation_page.dart", "lib/src/tag/presentation/navigation/tag_navigation_view_model.dart", "lib/src/tag/presentation/navigation/tag_navigation_view_model.g.dart", "openspec/changes/manage-tags/evidence/navigation-phase-readiness.md", "openspec/changes/manage-tags/tasks.md", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_late_page_app_scenarios.dart", "test/app/tag_navigation_terminal_app_scenarios.dart", "test/graph/data/drift_tag_read_test.dart", "test/tag/presentation/navigation/tag_navigation_late_page_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_late_page_widget_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_terminal_page_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_terminal_watch_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_view_model_test.dart"]
- **OpenSpec change:** manage-tags
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/manage-tags/evidence/navigation-phase-readiness.md", "openspec/changes/manage-tags/tasks.md"]

## Reviewed increment

### U1 · Сохранение конечного отказа и действенное восстановление навигации

- **Work items:** ["86", "4.1", "86 / 4.1 @ bdc5f8b12fc92f32206137d940b1eb87ce88341a", "87", "4.2", "87 / 4.2 @ 8c71302ff1bfcf33433d168b0c02b81e4fa5782f", "88", "4.3", "88 / 4.3 @ 3ce2cd18006c3b38d6cb6341f28d130b03d07656"]
- **Requirements and scenarios:** ["Получение данных и безопасные ошибки тегов", "Временный отказ наблюдения до первой порции", "Временный отказ наблюдения после загрузки", "Завершение наблюдения после повреждения данных", "Необъяснённое окончание наблюдения", "Явное восстановление завершившегося наблюдения", "Подтверждённые изменения и согласованные представления тегов", "Навигация по выбранному тегу", "Локализация и доступность управления тегами", "Фаза 4: Восстановление навигации после отказа наблюдения тега — готовность задач 4.1–4.2"]
- **Affected boundary:** Открытая экранная сессия навигации, наблюдение выбранного тега, чтения через Drift и AppRuntime, доступные действия пользователя в ru/en.
- **Implementation target:** ["lib/src/tag/presentation/navigation/tag_navigation_page.dart", "lib/src/tag/presentation/navigation/tag_navigation_view_model.dart", "lib/src/tag/presentation/navigation/tag_navigation_view_model.g.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_terminal_app_scenarios.dart", "test/graph/data/drift_tag_read_test.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_terminal_page_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_terminal_watch_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_view_model_test.dart"]
- **Applicable constraints and non-goals:** unavailable, corruption и unexpected сохраняют различимые причины и действия как до первой порции, так и после загрузки. Обычный явный повтор восстанавливает только доказанно временную недоступность с теми же TagId и охватом; он не повторяет запись. Устаревшие строки не допускают переходов. Новое наблюдение вместе с согласованной новой первой порцией подтверждают восстановление; прежние callbacks после смены выбора, переподключения или освобождения сессии не публикуют состояние. Сохраняются идентичности, русская и английская локализации, доступность и конфиденциальность личного графа.
- **Excluded change scope:** Фазы 1–3, общий поиск, несколько тегов, синхронизация и теги дневных выборов не получают новых требований реализации. Задача 4.3 проверяет исход задач 4.1–4.2 и явно оставляет независимость поздней страницы задачам 4.4–4.6.

### U2 · Независимость отказа наблюдения от поздней страницы

- **Work items:** ["89", "4.4", "89 / 4.4 @ e6cbdc02516a20db06ea518ddc9a24bd5937c37b", "90", "4.5", "90 / 4.5 @ 38a3e7d8e16555b2f72454d3c40ba71fd448c9c1", "91", "4.6", "91 / 4.6 @ a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf"]
- **Requirements and scenarios:** ["Получение данных и безопасные ошибки тегов", "Поздний отказ подгрузки после повреждения в наблюдении", "Поздняя первая порция после временного отказа наблюдения", "Поздняя успешная подгрузка после неизвестного отказа наблюдения", "Явное восстановление после отклонённого позднего ответа", "Устранимая ошибка подгрузки", "Подтверждённые изменения и согласованные представления тегов", "Локализация и доступность управления тегами", "Фаза 4: Восстановление навигации после отказа наблюдения тега — полная готовность"]
- **Affected boundary:** Одновременно выполняемые чтения страницы и наблюдение тега, право публикации результата, курсор и переходы, восстановление через настоящий экран и хранение.
- **Implementation target:** ["lib/src/tag/presentation/navigation/tag_navigation_view_model.dart", "lib/src/tag/presentation/navigation/tag_navigation_view_model.g.dart", "test/app/tag_navigation_app_lifecycle_test.dart", "test/app/tag_navigation_late_page_app_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_late_page_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_late_page_widget_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_page_test.dart", "test/tag/presentation/navigation/tag_navigation_terminal_watch_scenarios.dart", "test/tag/presentation/navigation/tag_navigation_view_model_test.dart"]
- **Applicable constraints and non-goals:** Успех и любой типизированный отказ страницы, начатой до независимого отказа наблюдения, не снимают этот отказ, не меняют его категорию и не возвращают актуальность, пригодный курсор или обычный повтор подгрузки. Правило действует для первой порции и продолжения, открытого и конечного потока. Отброшенное чтение освобождает занятое состояние; восстановление требует новой первой порции и успешного текущего наблюдения. При здоровом наблюдении сохраняется обычный повтор отказавшего продолжения без потери строк и дубликатов. Автоматические бесконечные переподписки и повтор подтверждённых команд не добавляются.
- **Excluded change scope:** Новые способы чтения и записи графа не вводятся. Задача 4.6 подтверждает весь расширенный исход фазы 4, а исторические измерения и готовность фаз 1–3 не подменяют текущие свидетельства.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Изолированный рецензент `/root/independent_navigation_review` с нулевой историей применил `implementation-decision-review` к точным base/head и объединению 13 продуктовых и тестовых путей U1–U2. Общие целые файлы проверены одним рецензентом. Он получил нейтральные намерения, границы этапа и SHA; не получал planning-артефакты, историю и описания коммитов, предыдущий отчёт или замечания. Все 13 файлов прочитаны полностью; неизменность контекстных путей проверена перед чтением. Результат `No substantive findings`, покрытие `Complete`. |
| OpenSpec conformance | Complete | proposal, три specs, design, adr, plan и tasks рассмотрены как контекст на `a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf`; status и instructions apply использованы только для обнаружения артефактов и текущего прогресса. Проверены все шесть taskCommitRanges, сценарии U1–U2 и проверочные свидетельства 4.3/4.6. Из корня репозитория на чистом reviewed head выполнены `mise exec --no-deps -- openspec validate manage-tags --json` (1/1, без issues), строгая валидация (код 0) и выбранный прогон навигации, Drift, AppRuntime и согласования графа (399/399, код 0). Все задачи диапазона имеют свидетельства реализации либо проверки. |
| Code quality | Complete | По `code-review-and-quality` проверены корректность, читаемость, архитектура, безопасность, производительность и качество тестовых свидетельств всех трёх продуктовых и десяти тестовых путей. Проверены владельцы отказов и восстановления, поколения запросов и подписок, освобождение текущего чтения, границы маршрута, ограниченность нового состояния и защита от публикации старых callbacks. Генерация оставила дерево чистым, анализ не выявил замечаний, форматирование 404 файлов не внесло изменений; проверка области CI и проверка diff прошли с кодом 0. Продуктовый код не добавляет зависимостей, записей, SQL или внешних интеграций. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все 15 reviewable-путей учтены: три продуктовых пути (включая сгенерированный Riverpod-файл) и десять тестовых путей составляют точный delivery-поднабор в U1–U2; tasks.md и navigation-phase-readiness.md являются planning/evidence. Неотнесённых и посторонних путей нет. Неизменённые контракты, состояния, Drift-адаптер, координатор, AppRuntime, маршруты и локализации использованы как контекст, а не как расширение target. Переносимых активных замечаний и принятых остаточных рисков нет; прежний отчёт прочитан только координатором после независимого прохода.

Каждый коммит проверен в собственном последовательном диапазоне. Описания, ID, номера и порядок всех 91 задач сохранены; в target изменены только шесть соответствующих отметок с неполного на завершённое состояние.

Задача 86 (4.1): диапазон fromExclusive=`77521632d914688213e607693fb1e6cbfd48bf9a`, throughInclusive=`bdc5f8b12fc92f32206137d940b1eb87ce88341a`. U1: типизированный конечный исход, состояние совместного восстановления, регрессии ViewModel и generated hash.

Задача 87 (4.2): диапазон fromExclusive=`bdc5f8b12fc92f32206137d940b1eb87ce88341a`, throughInclusive=`8c71302ff1bfcf33433d168b0c02b81e4fa5782f`. U1: реальное окончание Drift-потока, AppRuntime, ru/en, запрет старых переходов и защита кнопки закрытой сессии.

Задача 88 (4.3): диапазон fromExclusive=`8c71302ff1bfcf33433d168b0c02b81e4fa5782f`, throughInclusive=`3ce2cd18006c3b38d6cb6341f28d130b03d07656`. U1: navigation-phase-readiness.md:64–98; проверка задач 4.1–4.2 с явно указанной границей поздней страницы.

Задача 89 (4.4): диапазон fromExclusive=`3ce2cd18006c3b38d6cb6341f28d130b03d07656`, throughInclusive=`e6cbdc02516a20db06ea518ddc9a24bd5937c37b`. U2: отзыв права страницы на публикацию, сохранение отказа при смене охвата и подтверждённых изменениях, 84 сценария исходов страницы и дополнительные перестановки восстановления.

Задача 90 (4.5): диапазон fromExclusive=`e6cbdc02516a20db06ea518ddc9a24bd5937c37b`, throughInclusive=`38a3e7d8e16555b2f72454d3c40ba71fd448c9c1`. U2: настоящие Drift-чтения, поздние ответы, запрет действий и семантического tap, восстановление и дальнейшее переименование, старая экранная сессия.

Задача 91 (4.6): диапазон fromExclusive=`38a3e7d8e16555b2f72454d3c40ba71fd448c9c1`, throughInclusive=`a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf`. U2: navigation-phase-readiness.md:100–135; полное сопоставление задач 4.1–4.5, генерации, анализа и расширенного набора тестов.


Конечные сценарии закрывают поток и дожидаются очереди событий. Проверены три категории до и после первой порции, необъяснённое окончание, неклассифицированная ошибка, повторный отказ новой подписки и оба порядка доставки новой страницы и наблюдения. Восстановление остаётся неактуальным до их совместного успеха; смена ревизии отвергает ожидающую старую страницу. Callback старой подписки и кнопка закрытого маршрута не меняют новую сессию.

Матрица поздних ответов покрывает первую порцию/продолжение × открытый/конечный поток × три причины наблюдения × семь исходов страницы: успех, unavailable, corruption, unexpected, отсутствие тега, истёкший снимок и чужой курсор. Загруженные строки остаются неактуальными, курсор отсутствует, canActOn, обычная подгрузка и её повтор запрещены. Поздняя первая порция не создаёт актуальной выдачи. Завершение отброшенного запроса освобождает чтение, а явный повтор после unavailable возвращает тот же тег и охват без повторных строк.

Сквозные тесты сохраняют настоящее чтение Drift и управляют доставкой его результата. SQL-инъекция вызывает типизированную ошибку с фактическим окончанием наблюдения. Проверены конечное corruption → поздний unavailable продолжения, поздний успех первой порции и подгрузки после всех трёх категорий, открытый поток, обе локали и доступность действий. Повтор не увеличивает число команд и SQLite total_changes(); последующее переименование достигает нового наблюдения при удержанном пакете координатора. Обычная ошибка продолжения при здоровом наблюдении сохраняет строки, курсор и действенный повтор. Неизменённые проверки большого списка и согласования также вошли в прогон.

Все приведённые ниже проверки выполнены в этой сессии из `/home/seniorkonung/.paseo/worktrees/1id27gtb/stunning-hedgehog` при HEAD=`a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf`. Дерево до записи отчёта было чистым; отслеживаемые входы соответствовали снимку. Новых исправлений кода, тестов или плановых артефактов в этапе ревью не потребовалось; авторское изменение этапа — этот отчёт.

Команда `mise exec --no-deps -- flutter test --no-pub --reporter expanded test/tag/presentation/navigation test/app/tag_navigation_app_lifecycle_test.dart test/graph/data/drift_tag_read_test.dart test/graph/presentation/graph_reconciliation_checkpoint_test.dart`: код 0, `02:30 +399: All tests passed!`, включая slow, без отказов и пропусков.

Команда `mise run --skip-tools codegen-check`: код 0; генерация локализаций, Riverpod, Drift, маршрутов, schema snapshot и шагов миграции оставила дерево и pubspec.lock неизменными. Предупреждение build_runner об игнорировании удалённого параметра `--delete-conflicting-outputs` не повлияло на результат.

Команда `mise exec --no-deps -- flutter analyze --no-pub`: код 0, `No issues found!`.

Команда `mise exec --no-deps -- dart format --output=none --set-exit-if-changed .`: код 0, 404 файла, 0 изменений.

Команда `bash test/tool/check_ci_scope_test.sh`: код 0, проверки контракта области CI прошли.

Команда `mise exec --no-deps -- openspec validate manage-tags --json`: код 0, 1/1, без issues.

Команда `mise exec --no-deps -- openspec validate manage-tags --strict --no-interactive`: код 0, изменение допустимо.

Команда `git --literal-pathspecs diff --check 77521632d914688213e607693fb1e6cbfd48bf9a a5b7b5dfbb2c5e9407ccadb65b040c62aa1c2ddf`: код 0.


Команда `node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/manage-tags/implementation-review.md`: код 0, формат v1 допустим, 0 замечаний и 0 принятых рисков. Точные SHA, порядок целевых коммитов, массив reviewable-путей и сопоставление каждой задачи дополнительно сверены с локальным Git.

Проверки относятся к локальной Linux/debug-среде. Физическое повреждение файла, ручной проход экранного диктора на Android, APK и полный тестовый набор проекта в этом этапе не проверялись; они не входят в критерии задач 4.1–4.6. Исторические измерения фаз 1–3 не заявляются свежими результатами этого диапазона. Необходимости передавать новые замечания последующим этапам разрешения не выявлено; человеческих решений и принятия остаточного риска не требуется.
