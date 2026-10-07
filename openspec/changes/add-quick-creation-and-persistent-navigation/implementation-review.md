# OpenSpec Implementation Review: add-quick-creation-and-persistent-navigation

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F1: поздний результат удаления закрывает заново открытый просмотр той же сущности. Новая форма и каталог тегов защищены, однако повторная готовность Phase 1 требует устранения этого нарушения принадлежности навигации. Phase 2 и Phase 3 остаются вне инкремента.

## Review target

- **Baseline ref:** dab964d3c63f34511b9ae1239dc556bbcc7092dc
- **Base commit:** dab964d3c63f34511b9ae1239dc556bbcc7092dc
- **Reviewed head:** 0818d4748333340dce8bc94ec8a9d04e35073681
- **Target commits:** ["9ba49567907cf8a8464970f5e5c28e906eac9d61", "1d27b1ce73a616af283458df62f26448a610e19f", "0818d4748333340dce8bc94ec8a9d04e35073681"]
- **Reviewable paths:** ["docs/verification/persistent-navigation-1.14.md", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/details/relation_details_page.dart", "openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md", "test/app/navigation/app_shell_operation_reset_test.dart", "test/intention/presentation/details/details_test_support.dart"]
- **OpenSpec change:** add-quick-creation-and-persistent-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["docs/verification/persistent-navigation-1.14.md", "openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md"]

## Reviewed increment

### U1 · Позднее удаление сохраняет новую историю и несохранённый ввод

- **Work items:** ["1.12", "1.13", "1.14"]
- **Requirements and scenarios:** ["Сброс истории выбором пункта", "Позднее удаление намерения не закрывает новый каталог тегов", "Позднее удаление не закрывает новую форму связи", "Сохранение состояния корневых страниц", "Ready to advance Phase 1"]
- **Affected boundary:** Пользователь принимает удаление намерения или долговременной связи, возвращается к текущему либо другому разделу и открывает новую страницу до завершения операции и обратной анимации прежнего просмотра.
- **Implementation target:** ["lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/details/relation_details_page.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "test/intention/presentation/details/details_test_support.dart"]
- **Applicable constraints and non-goals:** Прежний экземпляр теряет право на навигацию сразу после удаления из истории. Удаление с актуальной верхней страницы закрывает собственный просмотр. Принятая команда завершается один раз; согласование по ревизии, выбранный пункт, состояние корней и действующий протокол сообщений сохраняются. Предметные правила, схема хранения и статусы ADR не меняются.
- **Excluded change scope:** Задачи 1.1–1.11 и неизменённые вызывающие стороны изучены как контекст. Новые входы и завершение создания из Phase 2, кнопка быстрого создания и хранение режима из Phase 3 не входят в обязательства этого диапазона.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Агент /root/independent_decisions с пустой историей получил нейтральное намерение U1, точные base/head и четыре целевых пути. Полностью прочитал их снимки и diff; перед чтением каждого контекстного пути проверял отсутствие изменений в диапазоне. Планирование, прежний отчёт и описания коммитов не передавались и не читались. После отдельной проверки повторного открытия того же ID: Changes needed, Coverage: Complete; подтверждён F1. |
| OpenSpec conformance | Complete | Сопоставлены сохранённые proposal, delta specs, design, ADR, plan и задачи 1.12–1.14, включая контрольную 1.14. Проверены все обязательства инкремента; нарушение принадлежности навигации и связанного условия готовности отражено в F1. На reviewed head заново выполнены 679 целевых тестов, повторная генерация, общий check, release-сборка APK и строгая валидация OpenSpec. Результаты приведены ниже. |
| Code quality | Complete | Все четыре изменённых пути кода и тестов проверены на корректность, читаемость, архитектуру, безопасность и производительность. Прослежены сброс истории, жизненный цикл слушателей, завершение команды, согласование каталога и предъявление сообщения. Проверены изоляция тестового репозитория и прежнее поведение его необязательного callback. Анализатор без замечаний. |

## Findings

### F1 · Medium — Позднее удаление закрывает повторно открытый просмотр той же сущности

- **Evidence:** На reviewed head `lib/src/intention/presentation/details/intention_details_page.dart:70`, `:82` и `lib/src/long_term_relation/presentation/details/relation_details_page.dart:39`, `:47` связывают подписку только с ID сущности и закрывают любой текущий экземпляр при общем состоянии `Deleted`. Provider имеет равенство только по ID (`intention_details_view_model.g.dart:141`, `relation_details_view_model.g.dart:158`). Подтверждённое удаление публикуется всем наблюдателям (`intention_details_view_model.dart:307`, `relation_details_view_model.dart:342`). После принятия удаления, сброса и повторного открытия того же ID прежний маршрут отсутствует в истории, прежний виджет ещё смонтирован, а новый маршрут текущий. Поздний результат вызывает `maybePop` из нового listener и удаляет новый просмотр. Изменённые тесты `test/app/navigation/app_shell_operation_reset_test.dart:69` и `:173` проверяют новые формы с независимыми участниками; повторного открытия того же ID в них нет. Это противоречит требованию «Сброс истории выбором пункта» (`specs/app-navigation/spec.md:55`) и явному правилу повторного открытия сущности в решении 4 (`design.md:130`).
- **Evidence revisions:** ["0818d4748333340dce8bc94ec8a9d04e35073681"]
- **Impact:** Пользователь возвращается к разделу и снова открывает ещё существующее намерение или долговременную связь; завершение ранее принятого удаления неожиданно закрывает этот новый просмотр. Проверка текущего положения маршрута не устанавливает принадлежность операции конкретному экземпляру страницы; условие готовности Phase 1 пока не подтверждено для этого случая.
- **Required outcome:** Автоматическое закрытие по результату принятого удаления затрагивает только принявший его экземпляр просмотра, пока он остаётся актуальным. Заново открытый просмотр той же сущности сохраняет свой маршрут и отображает согласованные данные. Команда и сообщение завершаются один раз. Регрессионные проверки должны охватывать обе сущности, повторное открытие того же ID до освобождения прежнего виджета и сохранение обычного удаления с актуальной страницы.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/long_term_relation/presentation/details/relation_details_page.dart", "test/app/navigation/app_shell_operation_reset_test.dart", "tasks.md:1.12", "tasks.md:1.13", "tasks.md:1.14"]

## Review coverage

Все шесть путей диапазона учтены: четыре пути реализации и тестов принадлежат U1, два документа служат свидетельствами планирования и проверки. Несопоставленных или посторонних изменений нет. Каждый из трёх целевых коммитов просмотрен отдельно, затем проверен совокупный результат. Все ссылки на строки ниже относятся к reviewed head `0818d4748333340dce8bc94ec8a9d04e35073681`.

Задача ID 12, «1.12 Сохранить новую страницу и её ввод при позднем удалении намерения со сброшенной страницы», сопоставлена с U1. Её диапазон: `dab964d3c63f34511b9ae1239dc556bbcc7092dc..9ba49567907cf8a8464970f5e5c28e906eac9d61` (исключая начало, включая конец).

Задача ID 13, «1.13 Сохранить новую форму при позднем удалении долговременной связи со сброшенной страницы», сопоставлена с U1. Её диапазон: `9ba49567907cf8a8464970f5e5c28e906eac9d61..1d27b1ce73a616af283458df62f26448a610e19f` (исключая начало, включая конец).

Задача ID 14, «1.14 Подтвердить готовность Phase 1 после защиты последующих страниц от позднего удаления», сопоставлена с U1. Её диапазон: `1d27b1ce73a616af283458df62f26448a610e19f..0818d4748333340dce8bc94ec8a9d04e35073681` (исключая начало, включая конец).

Для 1.12 проверены `lib/src/intention/presentation/details/intention_details_page.dart:76` и `test/app/navigation/app_shell_operation_reset_test.dart:173`, `:279`, `:330`. Проверки удерживают прежний виджет смонтированным при отсутствии его маршрута в истории, завершают принятую команду до конца анимации и подтверждают идентичность новой формы либо каталога тегов, сохранность текста, выбранного пункта и единственное сообщение. Удалённое намерение исключается из сохранённого каталога без нового начального запроса.

Для 1.13 проверены `lib/src/long_term_relation/presentation/details/relation_details_page.dart:42`, `test/app/navigation/app_shell_operation_reset_test.dart:69`, `:248`, `:670` и `test/intention/presentation/details/details_test_support.dart:233`. Отдельные сценарии связи охватывают оба пункта сброса и обычное удаление с верхней страницы. Подтверждены сохранность новой формы, одно выполнение команды и сообщения, изменение счётчика связей с 1 до 0 на новой ревизии без повторного начального запроса. Callback наблюдения связи задан только в нужных сценариях; без него сохраняется прежний явный отказ тестового репозитория.

Проверка `ModalRoute.of(context)?.isCurrent` относится к конкретному экземпляру маршрута. В закреплённом Flutter она сравнивает его с последней присутствующей записью истории; удалённый маршрут не получает право закрывать новую страницу, даже если ещё не освобождён. Вызов `maybePop` сохраняет проверку актуальности истории после внутреннего асинхронного ожидания. Проверка защищает от закрытия из прежнего listener, однако текущий экземпляр того же ID сам получает общее состояние `Deleted`; эту границу защиты устанавливает F1. Принятие команды и владение её результатом не меняются. Изменение не вводит нового хранилища, очереди, сетевого доступа или работы с пользовательским содержимым.

Для 1.14 проверено [свидетельство повторной готовности](../../../docs/verification/persistent-navigation-1.14.md). Оно относится к `1d27b1ce73a616af283458df62f26448a610e19f`; следующий целевой коммит меняет только этот документ и отметку задачи. Реализация и тесты на reviewed head те же. Результаты проверок этой сессии приведены ниже.

Дополнительная диагностика F1 выполнена без изменений файлов репозитория. Из сохранённого `test/app/navigation/app_shell_operation_reset_test.dart` создан временный файл `/tmp/hypnotic-bird-reopened-route-review_test.dart` с абсолютными импортами исходных helpers и двумя сценариями. Каждый принимает удаление через существующий контролируемый репозиторий, сбрасывает историю без `pumpAndSettle`, открывает подробный просмотр того же ID и сохраняет его новый `matchId`. Перед завершением команды проверены `mounted == true` прежнего виджета и отсутствие прежнего `matchId` в стеке; после результата проверяется сохранность нового `matchId`. Для обеих сущностей последнее ожидание упало: вместо нового маршрута вершиной оказалась оболочка.

Команда `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter test --no-pub --concurrency=1 --reporter expanded /tmp/hypnotic-bird-reopened-route-review_test.dart --plain-name 'проверка ревью:'` завершилась с exit 1: два сценария, два подтверждённых нарушения сохранности маршрута. Компиляция и все предшествующие проверки воспроизведения успешны; лог — `/tmp/hypnotic-bird-review-reopened-route.log`.

Рабочий каталог проверок: `/home/seniorkonung/.paseo/worktrees/1id27gtb/hypnotic-bird`. До проверок HEAD точно совпадал с reviewed head, рабочая копия была чистой; после повторной генерации tracked-файлы также не изменились. Инструменты не устанавливались и не обновлялись.

Целевой прогон `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter test --no-pub --reporter expanded test/app/navigation test/intention/presentation/details test/long_term_relation/presentation/details test/daily_choice/presentation/details test/graph/presentation/graph_operation_presenter_test.dart test/graph/presentation/operation_failure_presentation_test.dart` завершился с exit 0: 679 тестов успешны, пропусков нет.

Повторная генерация командой `MISE_AUTO_INSTALL=false mise run codegen-check` завершилась с exit 0: генерация воспроизведена, рабочая копия и lockfile остались без изменений.

Общий прогон `MISE_AUTO_INSTALL=false mise run check` завершился с exit 0: форматирование 562 файлов без изменений, проверка области CI, анализатор без замечаний, 4811 тестов приложения и 8 тестов Widgetbook успешны. Пропусков нет; lockfile не изменился.

Сборка командой `MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter build apk --release` завершилась с exit 0: получен `build/app/outputs/flutter-apk/app-release.apk`, 66,4 МБ.

Строгая валидация командой `MISE_AUTO_INSTALL=false mise exec --no-deps -- openspec validate add-quick-creation-and-persistent-navigation --strict --json` завершилась с exit 0: valid: true, issues: [].

Логи текущих прогонов: `/tmp/hypnotic-bird-review-targeted.log`, `/tmp/hypnotic-bird-review-codegen.log`, `/tmp/hypnotic-bird-review-check.log` и `/tmp/hypnotic-bird-review-build.log`.

Первый запуск помощника discovery использовал его внутренний прямой вызов OpenSpec. Обнаружение повторено с `--openspec /tmp/hypnotic-bird-review-openspec`: обёртка выполняет только `mise exec --no-deps -- openspec "$@"`. Повторный запуск подтвердил тот же точный диапазон и инвентарь; последующие обращения к OpenSpec выполнялись через mise.

Dart MCP `dtd listDtdUris` не обнаружил работающего приложения или DTD; применены предусмотренные задачей проверки CLI. Ручные жесты и озвучивание TalkBack в этой сессии не проверялись. Прежние ручные свидетельства и известное ограничение Flutter 3.47.1 при дробной ширине `PageView` остаются в [документе 1.10](../../../docs/verification/persistent-navigation-1.10.md), вне изменённых путей этого диапазона. Устранение ошибки SDK этим ревью не установлено.

Сопоставлены точный заголовок и условие готовности Phase 1 в `plan.md`, сохранённое состояние корней, матрица страниц, защищённая сессия намерения, раскладка, локализация и семантика панели в затронутых проверках. Проверка текста `tasks.md` между base и head после исключения отметок завершения показала полное совпадение: номера, описания, порядок и все остальные данные задач сохранены; изменены только отметки 1.12–1.14.

Изменён только отчёт; F1 остаётся для последующей стадии разрешения замечаний. Код, спецификации и история выполненных задач сохранены. Новых задач и принятых агентом остаточных рисков не добавлено. Полная готовность Phase 1 требует разрешения F1. Изменение в целом остаётся незавершённым: Phase 2 и Phase 3 сохраняются в плане без пакетов задач.
