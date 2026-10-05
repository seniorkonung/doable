# OpenSpec Implementation Review: simplify-intention-creation

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Подтверждено одно замечание средней серьёзности: при открытой клавиатуре и масштабе текста 200% на низком экране единственная панель полностью скрывает поля. Проверки доступности обходят это состояние скрытием клавиатуры. Замечание F1 остаётся для последующего этапа устранения. Принятых человеком остаточных рисков нет.

## Review target

- **Baseline ref:** 19c4f37610d48b28cd53fea5d0f1a3c10a7740f8
- **Base commit:** 19c4f37610d48b28cd53fea5d0f1a3c10a7740f8
- **Reviewed head:** d3374f0a589e3ff0238f2b08ae442d21b5de509c
- **Target commits:** ["69680753791d19b1671948f5f6e47c14cc5c9082", "2d592dcd65893f0a0ebe232cd27a3685e5c5d534", "db192459ebb80ffdaab84631921afd97e8c3b269", "0165a3ed760bd3c8acf2214650c09ec3aeb9528c", "ef5a06d8511c355248223790ad048ab0b7053171", "d3374f0a589e3ff0238f2b08ae442d21b5de509c"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/editor/intention_creation_sheet.dart", "lib/src/intention/presentation/editor/intention_creation_sheet_mode.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "openspec/changes/simplify-intention-creation/tasks.md", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_failure_integration_test.dart", "test/app/intention_creation_sheet_tags_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_creation_sheet_layout_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **OpenSpec change:** simplify-intention-creation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/simplify-intention-creation/tasks.md"]

## Reviewed increment

### U1 · Создание намерения в единственной адаптивной панели с сохранной сессией

- **Work items:** ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6"]
- **Requirements and scenarios:** ["intention-management / Адаптивная нижняя панель создания намерения", "Начальное состояние компактной панели", "Свайп вверх не разворачивает форму", "Длинное название увеличивает компактную панель", "Описание увеличивает панель до предела", "Длинное описание не разворачивает панель автоматически", "Клавиатура сохраняет компактный режим", "Сохранение при клавиатуре и увеличенном тексте", "Состояния быстрых иконок понятны без цвета", "Ошибка сохраняет открытую форму / сохранность черновика и исправление отказа", "app-navigation / Панель только на корневых страницах / Создание открывается поверх исходного каталога", "Общий выбор тегов открывается над панелью", "Общий выбор тегов возвращает ту же панель"]
- **Affected boundary:** Человек заполняет модальную форму над каталогом намерений, работает с клавиатурой и средствами доступности, выбирает теги, защищает изменённый черновик при уходе и получает результат принятой записи.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/editor/intention_creation_sheet.dart", "lib/src/intention/presentation/editor/intention_creation_sheet_mode.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/intention_creation_sheet_failure_integration_test.dart", "test/app/intention_creation_sheet_tags_test.dart", "test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart", "test/intention/presentation/editor/intention_creation_sheet_layout_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart"]
- **Applicable constraints and non-goals:** Сохраняются предел видимого контекста 72/24 логических пикселя, безопасные области, доступность ввода и сохранения, одна сессия черновика, защита ухода, атомарная запись и однократное предъявление результата. Принятая операция продолжается независимо от формы; другое открытие имеет самостоятельную сессию. Правила текста, тегов, избранного и готовности к действию, схема данных и зависимости не меняются.
- **Excluded change scope:** Фаза 2 из `plan.md`: передача идентификатора созданного намерения в событии, замена формы страницей намерения и новые сценарии истории возврата. Отсутствие этой навигации в проверяемом диапазоне не считается невыполненным обязательством первой фазы.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий ревьюер `/root/independent_decision`, `fork_turns: none`, применил `implementation-decision-review` к точным base/head и всем 18 путям U1. Получил нейтральное описание результата и ограничений без плановых артефактов, истории сообщений коммитов и прежнего отчёта. Прочитал полные назначенные файлы; удалённое перечисление — из base. Подтвердил корень F1. Динамическое воспроизведение независимо выполнил координатор. |
| OpenSpec conformance | Complete | Плановые источники прочитаны из reviewed head, все шесть задач сопоставлены с U1 и их сохранёнными диапазонами. Строгая структурная проверка OpenSpec и `mise run --no-deps codegen-check` завершились с кодом 0. Минимальная проверка воспроизвела F1. Полная команда `mise run --no-deps check` завершилась с кодом 0: 4606 тестов приложения и 8 тестов Widgetbook прошли. F1 нарушает проверенное требование доступности, несмотря на прохождение существующего набора. |
| Code quality | Complete | По `code-review-and-quality` проверены корректность, читаемость, архитектура, безопасность и производительность всех 18 путей U1. Прослежены геометрия и прокрутка, фокус, RU/EN и семантика, состояние и токен сессии, закрытие, выбор тегов, неизменность отправки, ошибки и право их предъявления. Проверены неизменённые вызывающие границы маршрутизатора, предметной валидации и графа; F1 воспроизведён на reviewed head. |

## Findings

### F1 · Medium — Тесная клавиатура полностью скрывает поля единственной панели

- **Evidence:** В `lib/src/intention/presentation/editor/intention_creation_sheet.dart:668` нижняя часть сначала получает всё место после верхней полосы. Расчёт предела в строке 678 сохраняет 24 пикселя контекста, но при нехватке места повторная раскладка нижней части в строке 691 снова отдаёт ей весь остаток. В строках 697–705 полям и сообщению достаётся `space == 0`. Минимальная проверка на reviewed head открыла пустую форму на фикстуре `_narrowLandscape` из `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart:1567`: экран 568×320, верхний безопасный отступ 24, боковой 48, клавиатура 160, масштаб текста 2.0. Панель заняла `Rect.fromLTRB(0, 48, 568, 160)`, область полей — `Rect.fromLTRB(0, 96, 520, 96)`, высота полей 0; сохранение оставалось нажимаемым. Проверка `fields.height > 0` завершилась с кодом 1. В базе компактная ветвь уже могла отдавать полям ноль, но развёрнутая ветвь в `lib/src/intention/presentation/editor/intention_creation_sheet.dart:839` использовала всю доступную высоту и давала дополнительное место. Проверяемый диапазон удаляет этот способ восстановления доступности. В новом `_expectPanelUsable` (`test/intention/presentation/editor/intention_creation_sheet_layout_test.dart:1098`) нулевая высота принимается при любой открытой клавиатуре: helper скрывает её, проверяет поля в другой геометрии и возвращает прежние отступы. Комментарий о масштабе сверх максимума Android не ограничивает эту ветвь; дефект воспроизводится и при 200%.
- **Evidence revisions:** ["19c4f37610d48b28cd53fea5d0f1a3c10a7740f8", "d3374f0a589e3ff0238f2b08ae442d21b5de509c"]
- **Impact:** При вводе на низком горизонтальном экране человек не видит даже получившее фокус название; прокрутка нулевой области не возвращает поля, теги и сообщения ошибок. Скрытие клавиатуры временно возвращает содержимое, но её повторное открытие снова убирает его. Удалённое управление размером больше не позволяет восстановить ввод над клавиатурой. Это нарушает доступность адаптивной формы и исправления ошибок, предусмотренную задачами 1.3–1.6 и сценариями первой фазы, при этом существующий тест выдаёт прохождение.
- **Required outcome:** Единственная адаптивная панель должна сохранять видимую прокручиваемую область ввода и доступное исправление отказов при проверяемом тесном экране, открытой клавиатуре и масштабе 200%, сохраняя согласованные пределы контекста, защиту черновика и доступность сохранения и закрытия. Проверка должна обнаруживать нулевую область в исходной геометрии, не подменяя её скрытием клавиатуры.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/editor/intention_creation_sheet.dart", "test/intention/presentation/editor/intention_creation_sheet_layout_test.dart", "openspec/changes/simplify-intention-creation/tasks.md / 1.3–1.6", "openspec/changes/simplify-intention-creation/specs/intention-management/spec.md / Адаптивная нижняя панель создания намерения"]

## Review coverage

Проверены полный неизменяемый диапазон и вклад каждого целевого коммита. Весь список из discovery классифицирован: 11 продуктовых путей, включая локализации, генерацию и удалённое перечисление; семь тестовых путей; один плановый путь `tasks.md`. Все продуктовые и тестовые пути принадлежат U1, все задачи имеют реализационное либо проверочное свидетельство. Несопоставленных и посторонних путей нет.

Версионный контекст прочитан из reviewed head: `proposal.md`, обе дельты спецификаций, `design.md`, `adr.md`, `plan.md`, `tasks.md`, `CONTEXT.md`, применимые ADR-0009, ADR-0012, ADR-0018 и ADR-0019. Из неизменённых файлов дополнительно проверены границы `app_router.dart`, `IntentionText`, контрольные сквозные проверки полного создания и предъявления результатов. Упоминание двух размеров в ADR-0018 не меняет предмет проверки: активная спецификация и первая фаза явно удаляют эту возможность.

Задача ID 1, номер 1.1, коммит `69680753791d19b1671948f5f6e47c14cc5c9082`, единица U1. Миграция проверок геометрии, доступности, защиты полного черновика и независимости сессий; сопоставлены удалённые ожидания режима и сохранённые обязательства. Обход нулевой области относится к F1.

Задача ID 2, номер 1.2, коммит `2d592dcd65893f0a0ebe232cd27a3685e5c5d534`, единица U1. Возврат из настоящего выбора и редактора тегов в ту же панель с прокруткой; атомарный отказ файлового хранилища, полный черновик, однократное сообщение и явный повтор.

Задача ID 3, номер 1.3, коммит `db192459ebb80ffdaab84631921afd97e8c3b269`, единица U1. Удаление перечисления, состояния, методов, кнопки и интерполяции размера; сохранение компактного расчёта, закрытия свайпом вниз, бездействия свайпа вверх и сессии. Дополнительно проверена миграция жизненного цикла приложения с клавиатурным открытием выбора тегов над общим сообщением. F1 затрагивает доступную область полей.

Задача ID 4, номер 1.4, коммит `0165a3ed760bd3c8acf2214650c09ec3aeb9528c`, единица U1. Рост и сокращение обоих полей, предел высоты, буквальный текст принятой команды, тип клавиатуры, явный переход фокуса и запрет правок во время отправки. Проверена освобождаемая принадлежность `FocusNode` странице.

Задача ID 5, номер 1.5, коммит `ef5a06d8511c355248223790ad048ab0b7053171`, единица U1. Удаление двух ключей и метаданных из RU/EN и производных локализаций; отсутствие действий размера в тексте, подсказках и семантическом дереве, порядок обхода и многострочное поле названия.

Задача ID 6, номер 1.6, коммит `d3374f0a589e3ff0238f2b08ae442d21b5de509c`, единица U1. Коммит меняет только отметку выполнения контрольной задачи. Её утверждения проверяются общей реализацией и тестами предыдущих коммитов, повторной генерацией, строгой проверкой OpenSpec и текущими CLI-проверками. Готовность первой фазы ограничена F1; второй фазе не приписано выполнение.

Все команды выполнены в `/home/seniorkonung/.paseo/worktrees/1id27gtb/pretty-bullfrog` на `d3374f0a589e3ff0238f2b08ae442d21b5de509c`. До проверок рабочая копия была чистой; продуктовые исходники и плановые артефакты совпадают с этим коммитом. Временные диагностические копии теста находятся вне репозитория и не входят в целевой диапазон.

Discovery через `node .agents/skills/openspec-review-implementation/scripts/discover-review-target.mjs --base 19c4f37610d48b28cd53fea5d0f1a3c10a7740f8 --head d3374f0a589e3ff0238f2b08ae442d21b5de509c --openspec <временный-адаптер>`: код 0, `ready`, шесть коммитов в указанном порядке, 19 путей, чистая рабочая копия. Адаптер вызывает исключительно `mise exec --no-deps -- openspec "$@"`.

Команда `mise exec --no-deps -- openspec status --change simplify-intention-creation --json` и `mise exec --no-deps -- openspec instructions apply --change simplify-intention-creation --json`: прочитаны контекст, схема и шесть завершённых задач. Команда получения инструкций не запускает реализацию; её общее сообщение о готовности к архивированию не применяется к ещё не представленной задачами второй фазе.

Команда `mise exec --no-deps -- openspec validate simplify-intention-creation --type change --strict --json --no-interactive`: код 0, одна проверка пройдена, ошибок нет. Это структурное свидетельство, а не доказательство доступности формы.

Команда `mise run --no-deps codegen-check`: код 0; локализации, генератор Riverpod/Drift/маршрутов и снимок схемы воспроизводятся без изменений Git. Предупреждение о неиспользуемом `--delete-conflicting-outputs` не остановило проверку.

Команда `mise run --no-deps check`: код 0; форматирование 548 файлов без изменений, проверка CI, зависимости Widgetbook с обязательным lockfile и статический анализ прошли; 4606 тестов приложения и 8 тестов Widgetbook прошли. Журнал этой сессии: `/tmp/simplify-intention-review-check.log`.

Команда `git --literal-pathspecs diff --check 19c4f37610d48b28cd53fea5d0f1a3c10a7740f8 d3374f0a589e3ff0238f2b08ae442d21b5de509c`: код 0. Поиск удалённых символов и ключей в `lib` точного reviewed head не дал совпадений.

Dart MCP: сначала зарегистрирован корень workspace, затем `dtd listDtdUris` не обнаружил запущенного приложения. Проверка выполнена через CLI и фикстуры с настоящим маршрутизатором; ручной прогон на устройстве и runtime-проверка не заявляются.

Диагностическая копия committed `intention_creation_sheet_layout_test.dart` с сохранёнными фикстурами и печатью геометрии: `mise exec --no-deps -- flutter test --concurrency=1 --plain-name 'все пять полей, закрытие' /tmp/simplify_intention_layout_probe_test.dart`, код 0, четыре сценария. В варианте 200% зафиксирована нулевая высота полей до скрытия клавиатуры; прохождение этих сценариев не опровергает F1.

Минимальная копия той же фикстуры: `mise exec --no-deps -- flutter test --concurrency=1 /tmp/simplify_intention_minimal_probe_test.dart`, код 1, одна проверка упала с `Actual: 0.0` при ожидании `fields.height > 0`. Начальная форма уже воспроизводит дефект без длинного текста, выбранных тегов и отказа записи.

Минимальное воспроизведение сохраняет helpers и фикстуры копии layout-теста reviewed head, заменяя только `main` одной проверкой. Последовательность: перевести lifecycle в `AppLifecycleState.resumed`; вызвать `_usePhone(tester, _narrowLandscape, keyboard: true)`; задать `tester.platformDispatcher.textScaleFactorTestValue = 2` с освобождением через `addTearDown`; открыть форму через `_openEditor(tester, ControlledCatalogRepository(), _EditorSessions())`; проверить `tester.getRect(find.byKey(_fields)).height > 0`. Проверка падает на нулевой высоте. Для запуска вне репозитория относительные импорты направлены на те же неизменённые фикстуры workspace.

F1 остаётся открытым для последующих этапов устранения замечаний. Коррекции продуктового кода и тестов в этом этапе не выполнялись, плановое владение исправлением не заявляется, принятие риска не подразумевается. История задач сохранена: ID, номера, описания, порядок и завершённые отметки не изменены; новые задачи и фазы не добавлены. Полнота покрытия ревью не означает выполнения условия готовности первой фазы при сохраняющемся F1.
