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
