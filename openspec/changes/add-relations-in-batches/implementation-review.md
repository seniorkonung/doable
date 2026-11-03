# OpenSpec Implementation Review: add-relations-in-batches

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Задачи 4.14–4.21 выполнены по своим критериям, `mise run check` проходит. Самая важная находка — F9: после задачи 4.18 не перегенерирован `intention_editor_view_model.g.dart`, поэтому `mise run codegen-check`, который запускает CI, падает на голове. Ещё три находки низкой важности. F10: строка «Создать» снова прячется над списком, если до перестройки выдачи приходит второе изменение. F11: описания правила закрытия панели создания противоречат новому поведению. F12: защита от второй панели в поиске участника хранит копию состояния стека со своим жизненным циклом. Принятых рисков нет.

## Review target

- **Baseline ref:** 1a7271be78ab239ad44b493731f60f95e506e737
- **Base commit:** 1a7271be78ab239ad44b493731f60f95e506e737
- **Reviewed head:** 5611feb81880cb86a16fa62ee46c60cb0b748135
- **Target commits:** ["83e594d9ad70795c1dd736032ab5e66e4318de25","b61096809843d5bae3179e5a5e7e1f826c9c3049","5d485757b0c2460884901d7b0d7071c81165c325","c2c9c28e396db5ced42e40441be825e39f5827ce","90a42f59ffcba1e5bcfff974e3ed1132e689b67d","8b34876d77bf93c17c450121bd1cdbbde6750b54","3e599060edd94fffa454123359a3c7706ae37634","0c19a8ee3d2bfd1d414a53b1d2975f001d9d793a","5611feb81880cb86a16fa62ee46c60cb0b748135"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/daily_choice/presentation/daily_choice_creation_flow_session.dart","lib/src/daily_choice/presentation/path/choice_path_page.dart","lib/src/intention/presentation/editor/intention_creation_close.dart","lib/src/intention/presentation/editor/intention_editor_view_model.dart","lib/src/intention/presentation/search/results_scroll_keeper.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart","openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md","test/app/choice_path_dead_end_app_flow_test.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart","test/daily_choice/presentation/daily_choice_creation_flow_session_test.dart","test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart","test/daily_choice/presentation/editor/daily_choice_creation_view_model_test.dart","test/daily_choice/presentation/path/choice_path_page_test.dart","test/graph/data/drift_relation_update_test.dart","test/graph/presentation/graph_operation_presenter_test.dart","test/intention/data/drift_intention_repository_large_fixture_test.dart","test/intention/presentation/editor/intention_editor_page_test.dart","test/intention/presentation/editor/intention_editor_view_model_test.dart","test/intention/presentation/search/intention_search_list_test.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **OpenSpec change:** add-relations-in-batches
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-relations-in-batches/task-profiles.md","openspec/changes/add-relations-in-batches/tasks.md"]

## Reviewed increment

### U1 · Проверка объёма чтения большой фикстуры учитывает число точных названий

- **Work items:** ["4.14"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника (подсчёт точных названий из 4.1)"]
- **Affected boundary:** Охранный тест объёма чтения поиска намерений.
- **Implementation target:** ["test/intention/data/drift_intention_repository_large_fixture_test.dart"]
- **Applicable constraints and non-goals:** Послабление — ровно одна строка и только для первой порции запроса с пробой пары и фильтром названия. Код хранилища не меняется, замеров времени в тесте нет.

### U2 · Четыре сценария дельт подтверждены по исходу

- **Work items:** ["4.15"]
- **Requirements and scenarios:** ["long-term-relation-management: Изменение типа сохраняет связь","long-term-relation-management: Редактирование архивированной связи","long-term-relation-management: Охват «все» остаётся только в общем каталоге намерений","app-navigation: Закрытие возвращает исходную страницу"]
- **Affected boundary:** Набор регрессионных тестов изменения.
- **Implementation target:** ["test/graph/data/drift_relation_update_test.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_test_support.dart"]
- **Applicable constraints and non-goals:** Код продукта и сценарии не меняются. Фикстуры минимальны, тесты без устройства и замеров времени.

### U3 · Тупик сверху вниз объясняет условие продолжения

- **Work items:** ["4.16"]
- **Requirements and scenarios:** ["daily-choice-management: Связь с неготовым намерением не становится продолжением"]
- **Affected boundary:** Человек в пошаговом выборе дневного пути, тексты на русском и английском.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_ru.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/src/daily_choice/presentation/path/choice_path_page.dart","test/daily_choice/presentation/path/choice_path_page_test.dart","test/app/choice_path_dead_end_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Тексты снизу вверх, чтение продолжений, модель пути и кнопка «Открыть связи» не меняются.

### U4 · Создание в поиске участника снова доступно после любого снятия панели

- **Work items:** ["4.17"]
- **Requirements and scenarios:** ["long-term-relation-management: Создание намерения из поиска участника","long-term-relation-management: Намерение из подстроки сразу отмечено"]
- **Affected boundary:** Человек в поиске участника и корневой стек навигации.
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **Applicable constraints and non-goals:** Пока панель открыта, второй панели нет. Пока идёт добавление, панель не открывается. Страница панели создания не меняется.

### U5 · Уход во время принятого сохранения требует подтверждения

- **Work items:** ["4.18"]
- **Requirements and scenarios:** ["intention-management: Уход во время сохранения непоправленного названия требует подтверждения","app-navigation: Выход из потока создания"]
- **Affected boundary:** Человек в панели создания намерения и решение о закрытии, которое читает страница.
- **Implementation target:** ["lib/src/intention/presentation/editor/intention_creation_close.dart","lib/src/intention/presentation/editor/intention_editor_view_model.dart","test/intention/presentation/editor/intention_editor_view_model_test.dart","test/intention/presentation/editor/intention_editor_page_test.dart"]
- **Applicable constraints and non-goals:** Смысл `isChanged` не меняется. Поздний успех после подтверждённого ухода идёт по действующим правилам.

### U6 · Вернувшаяся строка «Создать» видна в начале выдачи

- **Work items:** ["4.19"]
- **Requirements and scenarios:** ["long-term-relation-management: Точное совпадение убирает строку создания","long-term-relation-management: Причина занятой пары в поиске участника (исключение со сбросом позиции)"]
- **Affected boundary:** Человек, прокручивающий выдачу поиска участника.
- **Implementation target:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/search/intention_search_list_test.dart"]
- **Applicable constraints and non-goals:** Якорь по видимой строке вне начала выдачи работает как прежде, лишних `jumpTo` нет.

### U7 · Английские строки называют отметку словом «selected»

- **Work items:** ["4.20"]
- **Requirements and scenarios:** ["plan: инвариант «Новые и изменённые строки появляются сразу на русском и английском»"]
- **Affected boundary:** Человек, читающий приложение по-английски.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","test/graph/presentation/graph_operation_presenter_test.dart","test/intention/presentation/editor/intention_editor_page_test.dart"]
- **Applicable constraints and non-goals:** Ключи не переименовываются, русские строки не меняются, созданные файлы приходят из кодогенерации.

### U8 · Сессию создания дневного выбора нельзя собрать без экземпляра пути корня

- **Work items:** ["4.21"]
- **Requirements and scenarios:** ["daily-choice-management: Назад из подтверждения возвращает на шаг"]
- **Affected boundary:** Сборка сессии создания дневного выбора.
- **Implementation target:** ["lib/src/daily_choice/presentation/daily_choice_creation_flow_session.dart","test/daily_choice/presentation/daily_choice_creation_flow_session_test.dart","test/daily_choice/presentation/editor/daily_choice_creation_page_test.dart","test/daily_choice/presentation/editor/daily_choice_creation_view_model_test.dart"]
- **Applicable constraints and non-goals:** Поведение продукта не меняется, веток только для тестов нет, новых тестов на то, что проверяет компилятор, нет.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежие изолированные ревьюеры `implementation-decision-review` проверяли `1a7271be…..5611feb8…` и получали только нейтральный бриф и пути своей группы. U3, U5 и U7 делят файлы локализации и `intention_editor_page_test.dart`, поэтому шли одной группой (Opus, high). U4 — отдельно (Opus, high), U6 — отдельно (Sonnet, high), U1, U2 и U8 — каждая отдельно (Sonnet, medium). Первый ревьюер U8 вернул `Incomplete`: единственный рабочий вызов конструктора лежит в `choice_path_page.dart`, а этот путь изменён в диапазоне и принадлежит группе U3. Новый ревьюер получил тот же бриф с добавленным `choice_path_page.dart`, но только для места сборки сессии, и вернул полное покрытие. Так `choice_path_page.dart` проверили две группы. Ревьюер U2 читал неизменённые вспомогательные файлы тестов без проверки `git diff --quiet`, но ни один из них не входит в список путей диапазона. |
| OpenSpec conformance | Complete | Проверки шли в рабочем дереве с `HEAD` = `5611feb81880cb86a16fa62ee46c60cb0b748135` без правок. `mise run check` — код 0: анализ без замечаний, 4017 и 18 тестов прошли. `mise run codegen-check` — код 1: после генерации меняется хеш в `intention_editor_view_model.g.dart` (F9); созданный файл после проверки возвращён к закоммиченному. `mise exec --no-deps -- openspec validate add-relations-in-batches --strict --json` — успех; это только структурное свидетельство. Критерии приёмки 4.14–4.21 сверены с диффом, сценарии из U1–U8 подтверждены тестами диапазона. F10 воспроизведён временным тестом: два подтверждённых изменения подряд без кадра между ними дали позицию 56 вместо 0. Файл теста удалён, дерево чистое. Устройство и эмулятор не использовались. |
| Code quality | Complete | Пять линз `code-review-and-quality` применены ко всем рабочим путям на `5611feb8…`. Вне правок как контекст учтены `intention_editor_page.dart`, `intention_catalog_view_model.dart`, `intention_search_list.dart`, `app_router.dart`, а также `push`, `_addNewPage`, `_removeRoute`, `_canNavigate` и `onPopPage` из auto_route 11.1.0. Новых зависимостей и границ доверия нет. |

## Findings

### F9 · Medium — Созданный файл модели панели создания устарел, и проверка кодогенерации в CI падает

- **Evidence:** Коммит `8b34876d…` (задача 4.18) меняет `lib/src/intention/presentation/editor/intention_editor_view_model.dart`, но не трогает `intention_editor_view_model.g.dart`. На `5611feb8…` команда `mise run codegen-check` (`tool/check_generated.sh`) завершается с кодом 1: повторная генерация меняет `_$intentionEditorViewModelHash()` с `fdfe23ea…` на `a8b99df4…`. `.github/workflows/ci.yml:67` запускает `mise run --skip-tools codegen-check`. `mise run check` эту проверку не включает и проходит.
- **Evidence revisions:** ["5611feb81880cb86a16fa62ee46c60cb0b748135"]
- **Impact:** CI на голове ветки падает. Phase 4 не готова к переходу, потому что её критерий требует, чтобы проходили полные проверки проекта. Устаревший хеш провайдера Riverpod к тому же сбивает обнаружение изменений провайдера при горячей перезагрузке.
- **Required outcome:** Созданные файлы соответствуют своим исходникам на голове, и `mise run codegen-check` завершается с кодом 0.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/editor/intention_editor_view_model.g.dart","tasks.md 4.18"]

### F10 · Low — Строка «Создать» в начале выдачи снова прячется, если до перестройки списка приходит второе изменение

- **Evidence:** В `results_scroll_keeper.dart:84-90` появление строки «Создать» при позиции в начале только обнуляет `_pendingVisualAnchor` и выходит. Решение «держать начало» нигде не сохраняется. Следующий переход до перестройки идёт обычным путём (`:91-97`). `previous.createTitle` уже непуст, поэтому `_revealsCreateRowAtStart` (`:163-170`) даёт `false`, а `_mayShiftVisibleRow` даёт `true` при любой смене строки. Якорь снимается по ещё не перестроенной раскладке, где первая строка стоит в 0. После перестройки `_restoreVisualAnchor` сдвигает список на высоту строки «Создать». Временный тест на основе `intention_search_list_test.dart` подтвердил это на голове: после ухода точного совпадения и правки строки «Действие 30» без кадра между ними позиция стала 56, а не 0. В приложении скрытая под страницей поиск не перестраивается (комментарий к `_shown`, `:37-39`). Поэтому сценарий достижим и без двух событий в одном кадре: на странице, открытой стрелкой, человек переименовывает точное совпадение, а затем меняет другое намерение из выдачи, например его название, готовность или теги, и возвращается в поиск.
- **Evidence revisions:** ["5611feb81880cb86a16fa62ee46c60cb0b748135"]
- **Impact:** После возврата в поиск человек не видит строку «Создать», хотя список стоит у начала выдачи. Задача 4.19 исправила только случай с одним переходом.
- **Required outcome:** Если строка «Создать» появилась, пока список стоял в начале, список остаётся в начале и строка видна после перестройки, сколько бы состояний ни пришло до неё. В остальных случаях якорь работает как прежде. Регрессионный тест покрывает несколько переходов до перестройки.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/search/results_scroll_keeper.dart","test/intention/presentation/search/intention_search_list_test.dart"]

### F11 · Low — Описания правила закрытия панели создания противоречат новому поведению

- **Evidence:** После 4.18 `requestClose` сразу закрывает только неизменённый черновик до отправки, а принятая отправка всегда требует подтверждения (`intention_editor_view_model.dart:225-232`). Новому правилу соответствуют только комментарии к методу и к типам в `intention_creation_close.dart`. Комментарий класса `IntentionEditorViewModel` (`intention_editor_view_model.dart:31-33`) по-прежнему говорит, что неизменённый черновик закрывается сразу, а изменённый — после подтверждения. Так же сформулированы описание `IntentionEditorPage` (`intention_editor_page.dart:51-53`: «сразу для неизменённого черновика») и `_CloseConfirmationDialog` (`intention_editor_page.dart:563`: «Подтверждение закрытия изменённого черновика»).
- **Evidence revisions:** ["5611feb81880cb86a16fa62ee46c60cb0b748135"]
- **Impact:** Описания контракта сессии и страницы задают ровно то поведение, которое исправила 4.18. Тот, кто сверит код с ними, увидит лишнюю ветку подтверждения и может снова свести правило к одной проверке `isChanged`.
- **Required outcome:** Все описания правила закрытия сессии создания согласованы: подтверждение нужно для изменённого черновика или принятой отправки, сразу закрывается только неизменённый черновик до отправки.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/editor/intention_editor_view_model.dart","lib/src/intention/presentation/editor/intention_editor_page.dart"]

### F12 · Low — Защита от второй панели создания хранит копию состояния стека со своим жизненным циклом

- **Evidence:** В `relation_batch_picker_page.dart:53-108` правило «пока над поиском стоит панель создания, вторую не открывать» хранится в поле `_stopFollowingCreation`. Поле поддерживают слушатель роутера, эвристика поиска `matchId` панели по имени маршрута выше поиска, снятие по `whenComplete` с проверкой `identical` и переопределённый `dispose`. Корректность держится на том, что каждый путь снятия панели либо уведомит роутер, либо завершит future перехода. Исходный дефект 4.17 был как раз нарушением второго условия. В auto_route 11.1.0 при отсутствии guard-ов (`app_router.dart` их не объявляет) `_canNavigate` завершается без ожидания, и `_addNewPage` добавляет панель в `stackData` до следующего пользовательского события. Значит, ответ «есть ли над поиском панель» можно получить из стека в момент нажатия. `intention_editor_page.dart` уже поступает так: `_canCloseRoute` и `_completeCreation` читают `stackData` в момент действия.
- **Evidence revisions:** ["5611feb81880cb86a16fa62ee46c60cb0b748135"]
- **Impact:** Около 45 строк синхронизации закрывают одно правило. Новый путь снятия панели, который не уведомляет роутер и не завершает future, снова заблокирует создание до конца сессии поиска. Это тот же класс дефекта, который устраняла 4.17.
- **Required outcome:** Решение, можно ли открыть панель, опирается на фактическое состояние навигации в момент нажатия и не зависит от того, были ли замечены события снятия панели. Поведение 4.17 и её регрессионный тест сохраняются.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart"]

## Review coverage

Восемь задач отображены на диапазоны своих коммитов. `83e594d9…` только планирующий: он добавляет профили задач фазы 4 и входит в диапазон 4.14. Отметки выполнения в `tasks.md` — планирующие свидетельства. Все 27 путей учтены в U1–U8 или как планирующие свидетельства, неотнесённых нет.

По U3 проверено, что `choicePathNoPath` используется только сверху вниз, а снизу вверх показываются прежние `choicePathBottomNoPath` и `choicePathNoFurtherPath`. Текст согласован с неизменённым чтением продолжений: продолжением становится связь, через которую достижимо готовое неархивное намерение. По U5 проверено, что после подтверждённого ухода `_endOnRequest` снимает токен, поэтому поздний успех не вызывает `onCreated` и идёт обычным сообщением. Подтверждение, открытое во время отправки, снимается при её результате. Ожидания в `operation_failure_presentation_test.dart` совпадают с новым типом без поля, поэтому правка не понадобилась. По U7 в `lib` и `test` не осталось прежних английских строк. По U8 единственный рабочий вызов в `choice_path_page.dart:100` передаёт `_pageInstance` своей страницы.

Прошлый отчёт не содержал активных находок и принятых рисков, переносить нечего. Новые находки получили номера F9–F12 после F8 из предыдущих этапов. Код и планирующие артефакты в этом этапе не менялись, новых задач нет: находки оставлены для следующих этапов их устранения. Ручные проверки на устройстве остаются за владельцем продукта: вид объяснения тупика, повторное открытие панели после закрытия с диалогом и видимость строки «Создать» после возврата в поиск.
