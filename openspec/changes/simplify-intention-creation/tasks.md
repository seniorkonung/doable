Пакет соответствует первой фазе [плана](plan.md). Поведение задают [спецификация создания](specs/intention-management/spec.md) и [спецификация навигации](specs/app-navigation/spec.md), реализацию — решения 1, 2 и 6 [дизайна](design.md). Применимые архитектурные ограничения перечислены в [оценке ADR](adr.md). Автоматический переход после успеха относится ко второй фазе и в этот пакет не входит.

## Phase 1: Создание в единственной адаптивной панели

- [x] 1.1 Сохранить проверки геометрии, доступности и черновика для единственного компактного представления
  - **Acceptance criteria:**
    - Общие сценарии раскладки, клавиатуры, увеличенного текста, ошибок, фокуса и закрытия выполняются в компактной панели. Подготовка этих сценариев и проверка результата опираются на видимую геометрию, данные и идентичность сессии; переключение режима для них больше не требуется.
    - Удалены только проверки самого предоставления двух режимов. Обязательства, ранее проверявшиеся внутри сценариев разворачивания, сохранены отдельными проверками: полный черновик, доступность отправки, подтверждение ухода, неизменность принятой команды и изоляция нового открытия. Прямая фикстура конструктора панели мигрирует вместе с его контрактом в 1.3.
    - Проверки общего поведения проходят на текущей реализации. Проверки нового отсутствия управления размером добавляются при его удалении в 1.3 и завершаются проверкой семантики в 1.5.
  - **Verification:**
    - Выполнить `flutter test --concurrency=2 test/intention/presentation/editor/intention_creation_sheet_layout_test.dart test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart test/intention/presentation/editor/intention_editor_page_test.dart test/intention/presentation/editor/intention_editor_view_model_test.dart`.
    - Сопоставить изменённые сценарии с прежними: ожидания сохранности ввода, исправления ошибок и жизненного цикла сессии должны оставаться проверяемыми после удаления обхода режимов.
  - **Dependencies:** Нет; контракты панели и сессии определены дизайном и ADR-0018.
  - **Files likely touched:** `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`.
  - **Estimated scope:** M.

- [x] 1.2 Сохранить сквозные проверки выбора тегов и отказов записи в компактной панели
  - **Acceptance criteria:**
    - Существующие сценарии с настоящим маршрутизатором и хранилищем проходят через компактную панель, общий выбор и редактор тегов. Сохраняются проверки поиска тегов, полного черновика, прокрутки и возвращения в ту же сессию по [ADR-0018](../../../docs/adr/0018-manage-modal-creation-sessions-in-root-stack.md) и [ADR-0019](../../../docs/adr/0019-separate-tag-selection-context-from-persistence.md).
    - Сценарий отказа файлового хранилища сохраняет проверки атомарного отката, доступного сообщения, полного черновика и явного повтора. Удаляется только зависимость подготовки и ожидаемой геометрии от разворачивания; обязательства [ADR-0009](../../../docs/adr/0009-unify-personal-graph-module-and-revision.md) и [ADR-0012](../../../docs/adr/0012-centralize-graph-operation-result-presentation.md) продолжают проверяться.
  - **Verification:**
    - Выполнить `flutter test --concurrency=2 test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart`.
    - Проверить, что переходы выполняет настоящий маршрутизатор, а сохранение и отказ проходят через существующие интеграционные фикстуры хранилища.
  - **Dependencies:** Нет; использует существующие контракты общего выбора тегов и записи графа независимо от 1.1.
  - **Files likely touched:** `test/app/intention_creation_sheet_tags_test.dart`, `test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Estimated scope:** S.

- [x] 1.3 Удалить ручное разворачивание вместе с режимом размера и оставить адаптивную геометрию панели
  - **Acceptance criteria:**
    - Панель предоставляет единственную адаптивную раскладку по решению 1 дизайна. Её потребитель передаёт содержимое, сообщения, запрос видимости ошибки и запрос закрытия; расчёт высоты и прокрутка принадлежат панели. Кнопки изменения размера нет, свайп вверх ничего не запускает, свайп вниз запрашивает закрытие через сессию, а прокрутка полей её не закрывает.
    - Из контракта панели, состояния, модели представления и подключения страницы удалены режим размера и его операции; перечисление удалено без замены константным режимом или флагом. Удалены интерполяция и анимация размера; анимация входа и выхода маршрута, модальность и владение черновиком сохранены.
    - Сохраняются предел высоты с видимым контекстом 72/24 логических пикселя, ограничение ширины, безопасные области, учёт клавиатуры и доступность полей, закреплённого отказа и сохранения. Доведение ошибки до видимости продолжает работать при изменении геометрии и прекращается по прежним правилам пользовательской прокрутки.
  - **Verification:**
    - До правки продукта добавить проверки отсутствия кнопки и бездействия свайпа вверх; зафиксировать их падение на прежнем поведении, затем прохождение после изменения. Проверить свайп вниз, прокрутку полей и границы высоты по наблюдаемому поведению.
    - Выполнить `dart run build_runner build --delete-conflicting-outputs`, затем `flutter test --concurrency=2 test/intention/presentation/editor test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart`.
    - Проверить отсутствие прежнего контракта в продукте через `rg -n 'IntentionCreationSheetMode|sheetMode|expandSheet|collapseSheet' lib/src/intention/presentation/editor`; ожидается отсутствие совпадений.
  - **Dependencies:** 1.1, 1.2; сохраняемые сценарии уже проверяются без переключения режима.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_creation_sheet.dart`, `lib/src/intention/presentation/editor/intention_creation_sheet_mode.dart` (удаление), `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `lib/src/intention/presentation/editor/intention_editor_page.dart`; привязанная фикстура и новые проверки в `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`, согласование ожиданий семантики в `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`; производный `lib/src/intention/presentation/editor/intention_editor_view_model.g.dart`.
  - **Estimated scope:** M — один контракт в пяти исходниках; изменения потребителей в тестах и генерация входят в ту же проверяемую поставку.

- [x] 1.4 Обеспечить рост названия по тексту в пределах адаптивной панели
  - **Acceptance criteria:**
    - Короткие название и описание начинаются с одной строки. Длинное название визуально переносится и увеличивает поле и панель до её предела; дальнейшее содержимое доступно прокруткой. Рост описания сохраняет тот же контракт.
    - Мягкие переносы не добавляют символов в черновик и принятую команду. Название сохраняет прежний тип клавиатуры и действие перехода к следующему полю по решению 2 дизайна; описание сохраняет многострочный ввод.
    - Рост и сокращение текста, клавиатура, обе ориентации и увеличенный системный текст сохраняют доступность сохранения и исправления ошибок. Фокус, состояния тегов и отметок и запрет редактирования во время отправки продолжают работать.
  - **Verification:**
    - До изменения поля добавить проверку роста длинного названия, которая падает на однострочной реализации; после изменения проверить геометрию и точный текст черновика и отправленной команды, включая достижение предела панели.
    - Выполнить `flutter test --concurrency=2 test/intention/presentation/editor/intention_editor_page_test.dart test/intention/presentation/editor/intention_creation_sheet_layout_test.dart test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`.
  - **Dependencies:** 1.3; поле использует уже проверенный контракт адаптивной геометрии.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`.
  - **Estimated scope:** M.

- [x] 1.5 Завершить доступность адаптивной формы и удалить локализации изменения размера
  - **Acceptance criteria:**
    - В RU/EN среди видимых действий, подсказок и семантических действий отсутствуют разворачивание и сворачивание формы. Сохранены порядок чтения, доступное закрытие, названия полей, объяснения состояний иконок и недоступность каталога под модальной панелью.
    - Удалены только строки и метаданные `editorExpandFormAction` и `editorCollapseFormAction`; производные локализации получены генератором. Назначение и многострочное представление названия, клавиатурный обход и доступность сохранения соответствуют итоговому интерфейсу.
  - **Verification:**
    - Выполнить `flutter gen-l10n`, затем `flutter test --concurrency=2 test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart test/app/localization/locale_resolution_test.dart`.
    - Проверить отсутствие удалённых ключей через `rg -n 'editorExpandFormAction|editorCollapseFormAction' lib`; ожидается отсутствие совпадений. Проверить отсутствие действий также через семантическое дерево в обеих локалях.
  - **Dependencies:** 1.3, 1.4; окончательный состав действий и поведение поля уже реализованы.
  - **Files likely touched:** `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`, `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`; производные `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_ru.dart`, `lib/l10n/app_localizations_en.dart`.
  - **Estimated scope:** M.

- [x] 1.6 Подтвердить готовность адаптивной панели к изменению навигации во второй фазе
  - **Acceptance criteria:**
    - Выполнено условие `Ready to advance` первой фазы: создание доступно в единственной адаптивной панели, сохранены полный черновик, защита ухода, переходы в теги и исправление ошибок в тесной области. Все задачи 1.1–1.5 подтверждены проверками; ревью сверяет результат с требованиями и решениями, отнесёнными планом к первой фазе.
    - Сквозные проверки подтверждают запись всего начального состояния, атомарный отказ и допустимый повтор, завершение принятой операции после ухода, независимость новой сессии и однократное предъявление результата. Автоматический переход ещё не заявляется выполненным: он остаётся результатом второй фазы.
    - Обязательные проверки репозитория, воспроизводимость генерации и строгая проверка change проходят. Найденные регрессии исправлены и повторно проверены до отметки готовности фазы.
  - **Verification:**
    - Выполнить `flutter test --concurrency=2 test/intention/presentation/editor test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_draft_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart`.
    - Провести ревью по `code-review-and-quality`. При наличии запущенного приложения выполнить hot reload или restart и проверить `get_runtime_errors`; пройти ввод длинного текста, прокрутку, выбор тегов и отмену закрытия. При отсутствии приложения использовать проверки с настоящим маршрутизатором и репозиторные CLI-проверки.
    - Выполнить `mise run check`. После фиксации проверенных изменений исходников, артефактов и генерации выполнить `mise run codegen-check` на чистой рабочей копии: скрипт проверяет её чистоту до и после генерации.
    - Выполнить `openspec validate simplify-intention-creation --type change --strict --json --no-interactive`. После завершения пакета сверить план: перед реализацией второй фазы для неё требуется следующий пакет задач.
  - **Dependencies:** 1.1, 1.2, 1.3, 1.4, 1.5.
  - **Files likely touched:** Нет — контрольная проверка; прогресс отмечается в `tasks.md`.
  - **Estimated scope:** XS.

- [x] 1.7 Сохранить видимый ввод и исправление отказов над тесной клавиатурой в пределах компактной панели
  - **Acceptance criteria:**
    - Выполнен контракт решения 1 дизайна: на экране 568×320 с безопасными отступами 24 сверху и 48 справа, клавиатурой 160 и масштабом текста 2.0 пустая и заполненная формы сохраняют положительную высоту прокручиваемой области полей и видимый редактируемый участок поля с фокусом. Поля, выбранные теги и состояния доступны через прокрутку, сохранение и закрытие доступны над клавиатурой; сохраняются контекст 72/24, безопасные области и единственный вариант размера.
    - Ошибку поля и общий отказ записи можно прочитать и исправить либо выполнить допустимый повтор в той же тесной геометрии без потери полного черновика. Раскладка остаётся ответственностью `IntentionCreationSheet`; потребитель передаёт содержимое, сообщения и существующие запросы, а владение сессией, защитой ухода и предъявлением результата сохраняется.
    - Регрессионные проверки обнаруживают нулевую область на исходной реализации и проходят после исправления. Вспомогательные проверки доступности и нажатий не скрывают клавиатуру, не меняют экран или масштаб для обхода нулевой области; после прокрутки и работы с ошибками сохраняются исходные отступы клавиатуры. Проверки отдельного появления или скрытия клавиатуры не подменяют проверку ввода при открытой клавиатуре.
  - **Verification:**
    - До правки продукта зафиксировать падение минимального примера с исходной геометрией из решения 6 дизайна на ожидании положительной высоты области полей; после исправления проверить видимость ввода с фокусом, достижимость всех элементов через прокрутку и исправление обоих видов отказа без скрытия клавиатуры. Добавить эти проверки в постоянный набор, не ограничиваясь временной диагностической копией.
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor/intention_creation_sheet_layout_test.dart test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart test/app/intention_creation_sheet_failure_integration_test.dart`; сопоставить результаты при клавиатуре, обеих ориентациях, RU/EN, длинном содержимом и увеличенном тексте.
  - **Dependencies:** 1.3, 1.4, 1.5; согласованный контракт адаптивной панели уточнён решениями 1 и 6 дизайна для сценария «Сохранение при клавиатуре и увеличенном тексте» спецификации создания.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_creation_sheet.dart`, `test/intention/presentation/editor/intention_creation_sheet_layout_test.dart`, `test/intention/presentation/editor/intention_creation_sheet_accessibility_test.dart`, `test/app/intention_creation_sheet_failure_integration_test.dart`.
  - **Estimated scope:** M.

- [x] 1.8 Подтвердить готовность первой фазы после восстановления ввода при тесной клавиатуре
  - **Acceptance criteria:**
    - Выполнено условие `Ready to advance` первой фазы с исправлением 1.7: ввод и исправление отказов доступны при открытой клавиатуре и масштабе 200% в согласованных пределах панели. Регрессионные проверки сохраняют исходную геометрию; ревью сопоставляет наблюдаемый результат с решениями 1 и 6 дизайна и спецификацией создания.
    - Сквозные проверки сохраняют полный черновик, возврат из выбора тегов в ту же сессию, защиту ухода, атомарное создание и отказ, допустимый повтор, независимость новой сессии и однократное предъявление результата. Автоматическое открытие страницы намерения остаётся результатом второй фазы и здесь не проверяется как уже реализованное поведение.
    - Обязательные проверки репозитория, воспроизводимость генерации и строгая проверка change проходят. Отметка этой задачи опирается на результаты исправленной реализации; прежние отметки 1.1–1.6 сохраняются как выполненная работа и не заменяют новое подтверждение готовности.
  - **Verification:**
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_draft_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart`.
    - Провести ревью по `code-review-and-quality` с проверкой геометрии, фокуса и доведения ошибок до видимости. При наличии запущенного приложения выполнить hot reload или restart и проверить `get_runtime_errors`; при отсутствии использовать проверки с настоящим маршрутизатором и CLI-проверки репозитория.
    - Выполнить `mise run --no-deps check`; после фиксации проверенных исходников и артефактов выполнить `mise run --no-deps codegen-check` на чистой рабочей копии. Выполнить `mise exec --no-deps -- openspec validate simplify-intention-creation --type change --strict --json --no-interactive`.
  - **Dependencies:** 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7.
  - **Files likely touched:** Нет — контрольная проверка; прогресс отмечается в `tasks.md`.
  - **Estimated scope:** XS.

## Phase 2: Успешное создание открывает страницу намерения из живой сессии

- [x] 2.1 Передать подтверждённый идентификатор созданного намерения в одноразовом событии исходной сессии
  - **Acceptance criteria:**
    - По решению 3 [дизайна](design.md) `IntentionEditorCreated` содержит обязательный неизменяемый `IntentionId` из `IntentionSaved.intention.id` той же принятой отправки. Потребителю достаточно события для выбора страницы; название, выдача каталога и отдельное чтение состояния операции не нужны.
    - Модель представления публикует одно событие только для подтверждённого успеха своего активного токена. Потребление снимает событие без повторной команды и без подтверждения общего сообщения; ошибка, подтверждённый уход и освобождение сессии не публикуют событие перехода. Ожидающее подтверждение ухода сохраняет право исходной сессии завершиться успехом.
    - Сохраняются контракты ADR-0003, ADR-0009, ADR-0012 и ADR-0018 из [оценки ADR](adr.md): координатор владеет записью и результатом, сессия — своим одноразовым эффектом. Существующий хост остаётся работоспособным до подключения перехода в 2.3.
  - **Verification:**
    - До изменения контракта добавить проверку передачи именно подтверждённого идентификатора; подтвердить её непрохождение на прежнем событии и прохождение после изменения. Проверить потребление события, отказ, успех при ожидающем подтверждении, позднее завершение закрытой сессии и независимость новой сессии.
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor/intention_editor_view_model_test.dart test/intention/presentation/editor/intention_editor_page_test.dart test/app/intention_creation_draft_integration_test.dart`.
  - **Dependencies:** 1.8; контракт события согласован решением 3 дизайна, новая навигация для его проверки не требуется.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_state.dart`, `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, `test/intention/presentation/editor/intention_editor_view_model_test.dart`; при изменении исходника модели — производный `lib/src/intention/presentation/editor/intention_editor_view_model.g.dart`.
  - **Estimated scope:** M.

- [x] 2.2 Сохранить сквозные проверки записи и черновика при переходе через страницу созданного намерения
  - **Acceptance criteria:**
    - Проверки полного и минимального создания, назначения тегов, атомарного отказа и допустимого повтора сохраняют прежние проверки данных, ревизии, количества записей, сообщений и долговечности. Проверки интерфейса каталога и следующего открытия формы выполняются после явного возвращения в исходный каталог.
    - Шаг возвращения допускает уже открытый исходный каталог либо закрывает одну страницу подробных данных над ним; проверяет конечный каталог и не удаляет произвольную цепочку маршрутов. Он не скрывает оставшуюся форму, диалог ухода или неожиданную страницу. Вспомогательный шаг не используется для доказательства непосредственного результата успеха: этот результат проверяется в 2.3 и 2.5 до возвращения.
    - Подготовленные сценарии проходят на текущем поведении после 2.1 и сохраняют смысл после подключения перехода. Общий выбор тегов, запись всего начального состояния и исправление отказов продолжают проверяться через существующие настоящие маршруты и хранилище; пропуски проверок и ослабление ожиданий данных не вводятся.
  - **Verification:**
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart`.
    - Сопоставить изменённые сценарии с прежними: явное возвращение меняет только подготовку последующих действий в каталоге, а проверки полного пакета, отката, долговечности и однократного результата остаются.
  - **Dependencies:** 1.8; существующие контракты записи и сессии достаточны. Задача выполняется перед изменением маршрута в 2.3.
  - **Files likely touched:** `test/app/intention_creation_sheet_integration_test.dart`, `test/app/intention_creation_sheet_tags_test.dart`, `test/app/intention_creation_sheet_failure_integration_test.dart`, `test/app/full_intention_creation_checkpoint_test.dart`; при необходимости общего шага — `test/support/app_root_pages.dart`.
  - **Estimated scope:** M.

- [x] 2.3 Однократно заменить маршрут успешно завершённой формы страницей созданного намерения с защитой от запоздалого закрытия
  - **Acceptance criteria:**
    - По решениям 4 и 5 дизайна хост живой исходной сессии потребляет событие и через `StackRouter.replace` открывает `IntentionDetailsRoute` с идентификатором события в том же корневом стеке. Общая защёлка терминального перехода устанавливается до изменения стека; форма удаляется из истории, оболочка сохраняется, страница намерения занимает весь экран без основной навигации. Завершение сессии не ждёт возвращаемого `Future` нового маршрута.
    - Успех при ожидающем подтверждении ухода удаляет собственный диалог вместе с формой. Повторная обработка события, запрос закрытия и запоздалый ответ прежнего диалога не закрывают страницу намерения или новую форму. После подтверждённого ухода, включая анимацию удаления ещё существующего виджета, и после освобождения сессии поздний результат не вызывает перехода.
    - Навигация остаётся эффектом хоста: не управляет записью, согласованием каталога или claims сообщений и не обращается к освобождённому контексту. Ошибка навигационного эффекта не превращает подтверждённую запись в отказ создания и не запускает повторную запись. Существующие проверки страницы и жизненного цикла согласованы с новым непосредственным результатом успеха без потери проверок ошибок и новой сессии.
  - **Verification:**
    - До изменения хоста добавить проверки нового текущего маршрута и его идентификатора на настоящем `AppRouter`, зафиксировать падение при прежнем закрытии формы, затем прохождение после замены. Проверить отсутствие формы и её диалога в истории и сохранность страницы после запоздалого ответа.
    - Управляемым завершением записи проверить оба порядка: успех до ответа на подтверждение и подтверждённый уход до успеха, в том числе до окончания анимации. Проверить поздний успех поверх нового открытия с другим черновиком и однократность перехода при повторных кадрах.
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor/intention_editor_page_test.dart test/app/intention_app_lifecycle_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart`.
  - **Dependencies:** 2.1 — обязательный идентификатор события; 2.2 — сохранённые сквозные проверки готовы к переходу через подробные данные.
  - **Files likely touched:** `lib/src/intention/presentation/editor/intention_editor_page.dart`, `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/app/intention_app_lifecycle_test.dart`; при обнаружении связи ошибки эффекта с результатом записи — `lib/src/intention/presentation/editor/intention_editor_view_model.dart` и её производный файл.
  - **Estimated scope:** M.

- [x] 2.4 Подтвердить совместную работу события успеха, замены маршрута и завершения исходной сессии
  - **Acceptance criteria:**
    - Проверки 2.1–2.3 вместе доказывают передачу подтверждённого идентификатора, один переход из живой сессии и отсутствие управления текущей страницей после подтверждённого ухода. Оба порядка успеха и решения об уходе проверены, а поздний ответ диалога не удаляет новую страницу.
    - Подготовленные сквозные проверки сохраняют полный черновик, атомарную запись и отказ, однократное сообщение и изоляцию новой формы. Изменение маршрута не добавляет второго владельца записи, согласования или предъявления результата.
  - **Verification:**
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor/intention_editor_view_model_test.dart test/intention/presentation/editor/intention_editor_page_test.dart test/app/intention_app_lifecycle_test.dart test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_draft_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart`.
    - Сопоставить проверки с таблицей жизненного цикла решения 5 дизайна. Выявленные регрессии устранить и перепроверить до перехода к следующим задачам.
  - **Dependencies:** 2.1, 2.2, 2.3.
  - **Files likely touched:** Нет — контрольная проверка; прогресс отмечается в `tasks.md`.
  - **Estimated scope:** XS.

- [x] 2.5 Подтвердить открытие правильного намерения и возвращение в исходный каталог с сохранёнными условиями и позицией
  - **Acceptance criteria:**
    - Сценарии «Успешное создание открывает страницу нового намерения» и «Одноимённое намерение не подменяет созданное» из [спецификации создания](specs/intention-management/spec.md) проходят через кнопку каталога, адаптивную панель и настоящее хранилище. До возврата проверяются идентификатор текущего маршрута и подробные данные созданного намерения: название, описание, теги, избранное и готовность. Одноимённое существовавшее намерение имеет другой идентификатор и не подменяет результат.
    - Сценарии «Сохранение не сбрасывает текущий поиск» и «Возврат после создания не открывает завершённую форму» из обеих спецификаций проверяют прокрученный каталог с охватом, фильтром названия и условиями по тегам, которым новое намерение не соответствует. Его страница всё равно открывается; после «назад» сохраняются выбранный пункт, параметры, загруженная выдача и позиция по действующему протоколу согласования, а неподходящее намерение не вставляется в выдачу.
    - Страница результата открыта без основной навигации, сменить пункт нельзя. Возврат кнопкой страницы и системным «назад» не показывает завершённую форму или её диалог. Проверки RU/EN сохраняют совместную работу с полным черновиком, общим выбором тегов, минимальным созданием и чтением сохранённого состояния после повторного открытия хранилища.
  - **Verification:**
    - Расширить существующие сквозные сценарии наблюдаемыми ожиданиями непосредственно после успеха, до любого вспомогательного возвращения в каталог. Сверить идентификатор с подтверждённым результатом команды и проверить сохранённые данные через реальные подробные данные и существующие проверки хранилища.
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/full_intention_creation_checkpoint_test.dart test/app/navigation/app_shell_pages_above_test.dart`.
  - **Dependencies:** 2.4; работает собранный переход, включая границу завершения исходной сессии.
  - **Files likely touched:** `test/app/intention_creation_sheet_integration_test.dart`, `test/app/intention_creation_sheet_tags_test.dart`, `test/app/full_intention_creation_checkpoint_test.dart`.
  - **Estimated scope:** M.

- [ ] 2.6 Подтвердить независимость перехода от очереди сообщений и сохранность данных при отказах
  - **Acceptance criteria:**
    - Сценарий «Очередь сообщений не задерживает переход» проверяет успех создания при уже показанном сообщении другой операции: страница намерения открывается сразу, прежнее сообщение не вытесняется, успех создания предъявляется после него ровно один раз. Поздний успех после подтверждённого ухода согласует каталог и предъявляется над текущей страницей, включая новую форму, без перехода или изменения её черновика.
    - Отказ записи не открывает страницу намерения, сохраняет в открытой форме весь черновик и действующие способы исправления либо допустимого повтора. Ошибка при ожидающем подтверждении сохраняет форму и делает прежний ответ недействительным; после явного успешного повтора переход выполняется один раз. Сохраняются проверки атомарного отката и передачи непредъявленного отказа общей поверхности после ухода.
    - По решению 5 дизайна отказ чтения подробных данных уже созданного намерения использует существующее состояние страницы и допустимый повтор чтения. Команда создания не повторяется, идентификатор и успешный результат записи сохраняются; число записей и сообщений не увеличивается от повторных кадров или чтений.
  - **Verification:**
    - Управляемыми завершениями проверить занятую очередь, отказ и повтор, поздний результат после ухода и отказ чтения уже открытой страницы. Наблюдать текущий маршрут, полный черновик, количество команд, сообщения и результат хранилища; не подменять проверку навигации вызовом обработчика без настоящего маршрутизатора.
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor/intention_editor_page_test.dart test/app/intention_app_lifecycle_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/intention/presentation/details/intention_details_page_test.dart test/intention/presentation/details/intention_details_view_model_test.dart test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart`.
  - **Dependencies:** 2.4; использует собранный переход и существующие контракты предъявления результата и чтения подробных данных. Выполняется после 2.5 в порядке пакета.
  - **Files likely touched:** `test/intention/presentation/editor/intention_editor_page_test.dart`, `test/app/intention_app_lifecycle_test.dart`, `test/app/intention_creation_sheet_failure_integration_test.dart`; при необходимости уточнения проверки существующего повтора чтения — `test/intention/presentation/details/intention_details_page_test.dart`.
  - **Estimated scope:** M.

- [ ] 2.7 Подтвердить готовность второй фазы на совместной работе адаптивной формы, навигации и протокола результатов
  - **Acceptance criteria:**
    - Выполнено условие `Ready to advance` второй фазы [плана](plan.md): полный сценарий от заполнения формы до просмотра созданного намерения и возврата в каталог подтверждён для несовпадающих фильтров, одноимённых намерений, ошибок, занятой очереди и обоих порядков успеха и ухода. Задачи 2.1–2.6 подтверждены проверками обеих спецификаций и решений 3–6 дизайна.
    - Сохраняются результаты первой фазы: единственная адаптивная панель, рост полей, доступность ввода и исправления отказов с клавиатурой и увеличенным текстом в поддерживаемых ориентациях, полный черновик при переходах в теги и защита ухода. Существующий дополнительный регрессионный пример 568×320 проверяется без расширения гарантий горизонтального телефона.
    - Ревью и обязательные проверки репозитория, воспроизводимость генерации и строгая валидация изменения проходят. Проверки подтверждают однократность записи и предъявления, независимость новой сессии, атомарность и долговечность; обнаруженные регрессии исправлены и перепроверены до отметки готовности.
  - **Verification:**
    - Выполнить `mise exec --no-deps -- flutter test --concurrency=2 test/intention/presentation/editor test/app/intention_creation_sheet_integration_test.dart test/app/intention_creation_sheet_tags_test.dart test/app/intention_creation_sheet_failure_integration_test.dart test/app/intention_creation_draft_integration_test.dart test/app/full_intention_creation_checkpoint_test.dart test/app/intention_app_lifecycle_test.dart test/app/navigation test/intention/presentation/details test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart`.
    - Провести ревью по `code-review-and-quality`, сверив контракт события, владельца навигации, порядок завершения сессии и протокол сообщений. При наличии запущенного приложения выполнить hot reload или restart, проверить `get_runtime_errors` и пройти создание с длинным текстом и тегами, открытие подробных данных и возврат; при отсутствии приложения использовать проверки с настоящим маршрутизатором и CLI-проверки.
    - Выполнить `mise run --no-deps check`. После фиксации проверенных исходников, артефактов и генерации выполнить `mise run --no-deps codegen-check` на чистой рабочей копии; проверка требует её чистоты до и после генерации.
    - Выполнить `mise exec --no-deps -- openspec validate simplify-intention-creation --type change --strict --json --no-interactive`. Сверить наличие завершённых пакетов для всех фаз плана; отметка этой задачи подтверждает реализацию фазы, но сама по себе не выполняет архивирование.
  - **Dependencies:** 2.1, 2.2, 2.3, 2.4, 2.5, 2.6.
  - **Files likely touched:** Нет — контрольная проверка; прогресс отмечается в `tasks.md`.
  - **Estimated scope:** XS.
