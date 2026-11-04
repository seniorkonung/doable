# OpenSpec Implementation Review: open-full-intention-pages-from-pickers

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** На закреплённом диапазоне проверены все 10 коммитов, задачи 1.1–1.9 и 19 путей реализации и тестов. Независимая оценка решений, соответствие OpenSpec и проверка качества не выявили содержательных замечаний. Автоматические условия готовности Phase 1 подтверждены. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** a65f586d5ad62fbf011d4a8283b150a3bc8a62a4
- **Base commit:** a65f586d5ad62fbf011d4a8283b150a3bc8a62a4
- **Reviewed head:** 7e9f6dd2db93dc6102fc59f27a0285bc1bc55731
- **Target commits:** ["b3be4819e36bb187011ae68f3804b3a90850e424","e960fa2f04ef4e8e6ba5d3b1155b34710216becd","2d4fe846ed9261571fdc9ef070a91d1005e0a2c6","93f5be2c84ec18d777fce8dc6f192089397d2f7e","a70b93d4ea95fe33fc4604ffa289144b73cbec0e","f8512a112b97e69e5b2b7ea483d84725e845b9c5","77a7e88457ffcc1c28f5429febc7fb2f88aa03eb","3c54f585e87bd8451e38d6767a67e1d2fdd12532","a66063e169fdf443d36e1013e3d415013553ef10","7e9f6dd2db93dc6102fc59f27a0285bc1bc55731"]
- **Reviewable paths:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/app/navigation/ordinary_page_scaffold.dart","lib/src/app/navigation/relation_picker_position.dart","lib/src/app/routing/app_router.gr.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_page_footer.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.g.dart","openspec/changes/open-full-intention-pages-from-pickers/task-profiles.md","openspec/changes/open-full-intention-pages-from-pickers/tasks.md","test/app/creation_flows_integration_test.dart","test/app/creation_flows_relation_picker_scenarios.dart","test/app/long_term_relation_app_flow_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart","test/long_term_relation/presentation/batch_picker/relation_batch_view_model_test.dart"]
- **OpenSpec change:** open-full-intention-pages-from-pickers
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/open-full-intention-pages-from-pickers/task-profiles.md","openspec/changes/open-full-intention-pages-from-pickers/tasks.md"]

## Reviewed increment

### U1 · Полноценные обычные страницы и самостоятельное вложенное создание

- **Work items:** ["1.2","1.3","1.4","1.5","1.6","1.7","1.8","1.9"]
- **Requirements and scenarios:** ["app-navigation / Панель на обычных страницах независимо от истории","app-navigation / Выход из потока создания","app-navigation / Переход к настройкам с Главной","app-navigation / Сброс истории пунктом панели","app-navigation / Переход к созданной сущности","long-term-relation-management / Вход в добавление связей из группы","long-term-relation-management / Полноценная страница намерения из поиска участника","long-term-relation-management / Закрытие поиска участника","intention-management / Самостоятельное состояние открытых страниц поиска намерений","daily-choice-management / Входы в создание дневного выбора"]
- **Affected boundary:** Пользователь открывает намерение из поиска участника, продолжает декомпозицию, создаёт дневной выбор или намерение и возвращается к первоначальному поиску; подтверждённые вложенные записи сохраняются при его сбросе.
- **Implementation target:** ["lib/l10n/app_en.arb","lib/l10n/app_localizations.dart","lib/l10n/app_localizations_en.dart","lib/l10n/app_localizations_ru.dart","lib/l10n/app_ru.arb","lib/src/app/navigation/ordinary_page_scaffold.dart","lib/src/app/navigation/relation_picker_position.dart","lib/src/app/routing/app_router.gr.dart","lib/src/intention/presentation/details/intention_details_page.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_page_footer.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart","test/app/creation_flows_integration_test.dart","test/app/creation_flows_relation_picker_scenarios.dart","test/app/long_term_relation_app_flow_test.dart","test/app/navigation/app_shell_page_matrix.dart","test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart"]
- **Applicable constraints and non-goals:** Вид страницы определяется её назначением. Отметки остаются у экземпляра поиска; открытие и обычный возврат их не меняют. Вложенное создание завершает только собственный поток. Ограничения архивирования и готовности к действию, сброс истории пунктом панели, формат данных и общий протокол результатов сохраняются.

### U2 · Согласование всех отметок с подтверждённой занятостью направленных пар

- **Work items:** ["1.1","1.6","1.9"]
- **Requirements and scenarios:** ["long-term-relation-management / Отметка намерений для новых связей","long-term-relation-management / Вложенное создание снимает отметку вне выдачи","long-term-relation-management / Причина занятой пары в поиске участника"]
- **Affected boundary:** Подтверждённые изменения графа обновляют отметки каждого открытого поиска независимо от его фильтра и видимой выдачи.
- **Implementation target:** ["lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart","lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.g.dart","test/long_term_relation/presentation/batch_picker/relation_batch_view_model_test.dart","test/app/long_term_relation_app_flow_test.dart"]
- **Applicable constraints and non-goals:** Направленная пара уникальна независимо от типа и архивного состояния связи; обратная пара самостоятельна. Сохраняются порядок остальных отметок, единственный канал подтверждённых изменений и существующее владение предъявлением отказа. Новые чтения графа и отдельный механизм занятости не вводятся.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий рецензент `/root/independent_decisions`, модель `gpt-6.1-sol`, reasoning `high`, `fork_turns=none`. Получил нейтральное описание исходов U1/U2 и точные base/head и объединение их 19 delivery/test-путей; планирование, описания коммитов и отчёт ему не передавались. Общий изменённый файл `test/app/long_term_relation_app_flow_test.dart` связывает единицы, поэтому использован один изолированный проход. Результат: `No substantive findings`, охват: `Complete`. |
| OpenSpec conformance | Complete | Из зафиксированного head прочитаны proposal, обе delta-спецификации, design, ADR manifest, plan, tasks и применимые канонические контракты и ADR. Все задачи и сценарии сопоставлены с реализацией и новыми либо существующими тестами ниже. Проверки выполнялись в корне репозитория на `7e9f6dd2db93dc6102fc59f27a0285bc1bc55731` с чистыми исходниками. `mise run codegen-check`, полный `mise run check` и строгая OpenSpec-валидация завершились с кодом 0; сборка release APK также успешна. Подробности и границы проверки приведены ниже. |
| Code quality | Complete | Все 19 delivery/test-путей проверены по корректности, читаемости, архитектуре, безопасности и производительности с `code-review-and-quality`. Прослежены вызывающие страницы, независимые сессии, границы завершения создания, занятость строк каталога, подтверждённые пакеты и права предъявления. Содержательных дефектов и неоправданного расширения объёма не установлено. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все доказательства реализации и номера строк ниже относятся к `7e9f6dd2db93dc6102fc59f27a0285bc1bc55731`; удалённые файлы сопоставлены с `a65f586d5ad62fbf011d4a8283b150a3bc8a62a4`. Проверены изменения каждого целевого коммита и итоговое состояние диапазона. Все 21 изменённый путь учтены: 19 входят в U1/U2, два служат плановым контекстом. Несопоставленных путей, сторонних изменений и исключённых незакоммиченных исходников нет.

Плановый контекст: proposal, обе delta-спецификации, design, ADR manifest, plan и tasks этого изменения, CONTEXT.md, применимые основные спецификации и ADR-0009, ADR-0012, ADR-0018, ADR-0020, ADR-0022, ADR-0028, ADR-0050, ADR-0052 и ADR-0053. Неизменённые файлы не расширяют цель ревью. Delta-спецификации пересматривают прежнее ограничение над поиском; старое правило в основных спецификациях до синхронизации не считается действующим требованием этой реализации.

Сопоставление целевых коммитов и задач.

Коммит `b3be4819e36bb187011ae68f3804b3a90850e424`, U1/U2: task-profiles.md классифицирован как плановый контекст задач 1.1–1.9; поведения приложения не добавляет.

Задача ID 1 / 1.1, U2, коммит `e960fa2f04ef4e8e6ba5d3b1155b34710216becd`: согласование полного набора отметок, направлений, отдельных сессий и освобождения права предъявления отказа.

Задача ID 2 / 1.2, U1, коммит `2d4fe846ed9261571fdc9ef070a91d1005e0a2c6`: удалены контекст отметки, нижние кнопки и аргумент маршрута; стрелка открывает намерение по идентификатору.

Задача ID 3 / 1.3, U1, коммит `93f5be2c84ec18d777fce8dc6f192089397d2f7e`: навигация обычных страниц, четыре группы и оба направления дневного выбора доступны над поиском; проверен сброс истории.

Задача ID 4 / 1.4, U1, коммит `a70b93d4ea95fe33fc4604ffa289144b73cbec0e`: удалены три ключа локализации и обращения к ним; приложенческая проверка перенесена на отметку в поиске.

Задача ID 5 / 1.5, U1, коммит `f8512a112b97e69e5b2b7ea483d84725e845b9c5`: успех и сброс вложенного поиска того же назначения сохраняют первоначальный поиск и его отметку.

Задача ID 6 / 1.6, U1/U2, коммит `77a7e88457ffcc1c28f5429febc7fb2f88aa03eb`: настоящее хранилище подтверждает снятие скрытой отметки, порядок оставшихся связей и сохранность вложенной записи при завершении и сбросе.

Задача ID 7 / 1.7, U1, коммит `3c54f585e87bd8451e38d6767a67e1d2fdd12532`: создание дневного выбора со вкладки и быстрым созданием, успех и отмена сохраняют первоначальный поиск; сохранённая запись переживает его сброс.

Задача ID 8 / 1.8, U1, коммит `a66063e169fdf443d36e1013e3d415013553ef10`: быстро созданное намерение и его данные сохраняются после возврата и сброса первоначального поиска.

Задача ID 9 / 1.9, U1/U2, коммит `7e9f6dd2db93dc6102fc59f27a0285bc1bc55731`: завершение пакета задач и согласованный generated hash модели проверены повторной генерацией и обязательными проверками фазы.

Текст, номера и порядок задач совпадают с baseline; в tasks.md изменены только девять отметок выполнения. Все задачи остаются завершёнными. Новая работа и изменения планирования не требуются.

Реализация и границы.

Каркас `lib/src/app/navigation/ordinary_page_scaffold.dart:18` всегда размещает обычную навигацию. Удалены специальное определение положения над поиском и нижняя кнопка отметки; в маршруте намерения больше нет batchRow.

Страница `lib/src/intention/presentation/details/intention_details_page.dart:779` сохраняет ограничения активности и готовности дневного выбора; строка 809 открывает поиск группы. Неизменённый `lib/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart:178` сохраняет запрет добавления для архивированного намерения.

Поиск `lib/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart:47` создаёт собственную сессию, строка 68 завершает добавление по идентичности конкретного маршрута, строка 149 открывает подробности без доступа страницы к отметкам.

Модель `lib/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart:158` сначала согласует изменения намерений, затем применяет reconcilePairOccupants ко всем оставшимся отметкам. Удаление из упорядоченной карты сохраняет порядок остальных; пакет публикует итоговое состояние, а устранённый отказ освобождает прежнее право предъявления.

Неизменённые `lib/src/intention/presentation/catalog/pair_occupant_reconciliation.dart:43` и `lib/src/intention/presentation/catalog/intention_catalog_view_model.dart:817` обеспечивают направление пары и текущую причину занятости видимых строк. Новое согласование не добавляет чтений хранилища или второго канала результатов.

Прослежены существующие границы DailyChoiceCreationFlowSession, завершение IntentionEditorPage, QuickCreationLauncher и сброс истории через AppNavigation. Исходная история сохраняется по идентичностям экземпляров, подтверждённые записи остаются у координатора графа. Generated-маршруты, generated-модель и локализация соответствуют исходникам. Удалённые ключи и типы не имеют обращений в lib и test. Новые зависимости, форматы хранения, миграции и внешние границы доверия не вводятся.

Сценарии и проверочные свидетельства.

Сценарий «Открытие страницы оставляет выбор в поиске»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:1202` — свободное намерение; `:1264`, `:1505`, `:1520` — отмеченное, занятое и архивированное.

Сценарий «Вложенное добавление с глубокой страницы сохраняет первоначальный поиск»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:1279` и `:1341` — четыре группы, глубокий переход, независимые экземпляры того же назначения, успех и сброс.

Сценарий «Вложенное создание снимает отметку вне выдачи»: `test/app/long_term_relation_app_flow_test.dart:461` — скрытая отметка, два оставшихся элемента в прежнем порядке, причина занятой пары и проверка записей настоящего хранилища.

Сценарий «Сброс первоначального выбора сохраняет вложенную связь»: Вариант `complete == false` того же теста `test/app/long_term_relation_app_flow_test.dart:461` — после сброса остаётся только вложенная связь.

Сценарий «Отметка не закрывает поиск; отметка переживает смену выдачи; архивирование снимает отметку»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:962`, `:1059`; `test/app/long_term_relation_app_flow_test.dart:821`.

Сценарий «Вход из исходящей и входящей групп»: `test/app/long_term_relation_app_flow_test.dart:630` — сохранённые участники, направление, порядок и повторное чтение; доступность всех групп над поиском — `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:1279`.

Сценарий «Причины группы и архива; другой тип; входящая группа; нажатие занятой строки»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:962`, `:991`, `:1009`, `:1023` — существующий контракт занятости.

Сценарий «Удаление связи на странице из поиска снимает причину; восстановленное намерение начинает выдачу заново»: `test/app/long_term_relation_app_flow_test.dart:360` и `:882`.

Сценарий «Подтверждение называет связи и созданные намерения; без отметок поиск закрывается сразу»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:346`, `:389`, `:453`.

Сценарий «Страница намерения показывает панель; страница-задача скрывает панель; экран изменения скрывает панель; поиск действия не является корневой страницей»: Матрица `test/app/navigation/app_shell_page_matrix.dart:462` и её запуск `:558`; возврат из изменения проверяется тем же тестом матрицы.

Сценарий «Обычная страница над задачей показывает панель; страницы над поиском участника показывают панель»: `test/app/navigation/app_shell_pages_above_test.dart:152`; `test/app/navigation/app_shell_page_matrix.dart:83` — прямой и глубокий переходы, возврат с сохранённой отметкой.

Сценарий «Правка на странице намерения не скрывает панель; каталог на дату из статистики сохраняет пункт; настройки открываются с Главной; подробный просмотр связи перекрывает панель»: `test/app/navigation/app_shell_page_matrix.dart:240`; `test/app/intention_statistics_navigation_test.dart:217`; `test/app/navigation/settings_navigation_test.dart:26`; `test/app/navigation/app_shell_page_matrix.dart:416`.

Сценарий «Отказ подготовки хранилища показан без панели»: `test/app/bootstrap/app_bootstrap_shell_test.dart:60` — отказ и повторная подготовка без оболочки и корневых страниц.

Сценарий «Отмена завершает только собственный поток; назад из подтверждения возвращает на шаг; выход во время сохранения не отменяет команду»: `test/app/creation_flows_relation_picker_scenarios.dart:163` — отмена над первоначальным поиском; `test/app/quick_creation/quick_creation_flow_scenarios.dart:6`, `:88` — общий возврат и поздний результат в обоих направлениях.

Сценарий «Самостоятельность дневного выбора и намерения после сброса первоначального поиска»: `test/app/creation_flows_relation_picker_scenarios.dart:163` — вкладка и быстрое создание, успех и отмена; `:3` — быстро созданное намерение. Записи и отсутствие первоначальных несохранённых связей проверяются через настоящий адаптер.

Сценарий «Раздельные параметры поиска и правило сброса истории»: `test/long_term_relation/presentation/batch_picker/relation_batch_picker_session_test.dart:11` использует существующие сценарии параметров, тегов, порций, прокрутки, типа и сортировки; `test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart:1483` — сброс истории без команды.

Новые тесты различают существенные регрессии: потерю чужого маршрута того же назначения, перенос отметок между сессиями, неснятие скрытой отметки, повторное добавление занятой пары, потерю подтверждённых данных при сбросе внешнего выбора и отсутствие предметных действий над поиском. Общие механизмы параметров поиска, причин занятости, архивирования, возврата и поздних результатов продолжают проверяться существующими наборами; новые сценарии используют их в изменившемся контексте.

Проверки и передача результата.

Все команды выполнены в `/home/seniorkonung/.paseo/worktrees/1id27gtb/stingy-zebra` на зафиксированном reviewed head до добавления этого отчёта. Повторная генерация оставила рабочую копию чистой.

Проверка `mise run codegen-check`: код 0; локализация, маршруты, generated-модели и схема воспроизводятся без изменений tracked-файлов.

Полная проверка `mise run check`: код 0; форматирование 862 файлов без изменений, проверки shell-инструментов и статический анализ успешны; 4030 обычных тестов и 18 тестов flutter_process прошли.

Структурная проверка `mise exec --no-deps -- openspec validate open-full-intention-pages-from-pickers --strict --no-interactive --json`: код 0; изменение валидно, список issues пуст.

Сборка `mise exec --no-deps -- flutter build apk --release`: код 0; получен `build/app/outputs/flutter-apk/app-release.apk`.

Проверка `git diff --check a65f586d5ad62fbf011d4a8283b150a3bc8a62a4 7e9f6dd2db93dc6102fc59f27a0285bc1bc55731`: код 0; ошибок пробелов нет. Поиск `rg -n 'batchPageAdd|batchPageRemove|batchPageArchived|RelationBatchRowContext|RelationBatchPageFooter|isAboveRelationPicker|pickerFooter' lib test` не дал совпадений, ожидаемый код 1.

Код, тесты и плановые артефакты в ходе ревью не изменялись; исправления и новые задачи для передачи в реализацию отсутствуют. Проверка устройства не выполнялась и по правилам репозитория не блокирует автоматическую готовность фазы. Пользователю остаются ручные проверки вложенного создания, обычного возврата и сброса истории на его устройстве с полученным APK. Ревью само по себе не принимает остаточные риски и не выполняет публикацию, слияние или архивацию.
