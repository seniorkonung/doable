# OpenSpec Implementation Review: add-quick-creation-and-persistent-navigation

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** F2 (Medium): матрица доступности повторно проверяет поле поиска вместо строки кандидата, а документ готовности заявляет достижимость кандидатов подтверждённой. Геометрия и прямое нажатие текстовой отмены проверяются отдельно; дефекта самого исправления компоновки не установлено. Принятых остаточных рисков нет. Ревью ограничено задачами 2.23–2.24 Phase 2.

## Review target

- **Baseline ref:** 60ecc6aa563611c03526f53d22646e892c314837
- **Base commit:** 60ecc6aa563611c03526f53d22646e892c314837
- **Reviewed head:** 48c896a5f78b7e95d1147eae6391a9985e8d788f
- **Target commits:** ["9ffa2dd7c45dc24a8b992e6d1434b3603a16c003","48c896a5f78b7e95d1147eae6391a9985e8d788f"]
- **Reviewable paths:** ["docs/verification/persistent-navigation-phase-two-readiness.md","lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart","lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart","openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md","test/daily_choice/presentation/daily_choice_creation_launcher_test.dart","test/daily_choice/presentation/daily_choice_picker_context_test_support.dart"]
- **OpenSpec change:** add-quick-creation-and-persistent-navigation
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md"]

## Reviewed increment

### U1 · Текстовая отмена начального поиска доступна при клавиатуре

- **Work items:** ["ID 40 / 2.23"]
- **Requirements and scenarios:** ["Входы в создание дневного выбора","Отмена поиска основания ничего не создаёт","Выход из потока создания","Самостоятельное состояние открытых страниц поиска намерений","Ready to advance Phase 2"]
- **Affected boundary:** Человек ищет основание или действие дневного выбора, взаимодействует с клавиатурой и явно отменяет конкретный запуск над сохранённой историей.
- **Implementation target:** ["lib/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart","lib/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart","test/daily_choice/presentation/daily_choice_creation_launcher_test.dart","test/daily_choice/presentation/daily_choice_picker_context_test_support.dart"]
- **Applicable constraints and non-goals:** Русский и английский интерфейсы, текст 1.0/2.6, телефон 400×800 и планшет 800×1280/1280×800 при DPR 1, клавиатура 260 логических пикселей и безопасные отступы. Отмена доступна напрямую и в семантике; поле, условия тегов и выдача остаются достижимыми. Отмена сохраняет исходную историю и самостоятельное состояние поиска, не принимает команду и запрещает поздний переход. Вспомогательный выбор сохраняет возврат результата; предметные правила и границы записи не меняются.
- **Excluded change scope:** Общая кнопка создания, меню, сохранение режима и удаление прежних кнопок каталогов относятся к Phase 3. Остальная реализация Phase 1/2 используется только как контекст и регрессионное покрытие.

### U2 · Готовность исправленной Phase 2 подтверждается проверенной ревизией

- **Work items:** ["ID 41 / 2.24"]
- **Requirements and scenarios:** ["Ready to advance Phase 2","Входы в создание дневного выбора","Выход из потока создания","Открытие созданной сущности","Адаптивная нижняя панель создания намерения","Входы в создание долговременной связи"]
- **Affected boundary:** Инженер или процесс оценивает готовность четырёх потоков создания к подключению общей точки входа по воспроизводимым свидетельствам.
- **Implementation target:** ["docs/verification/persistent-navigation-phase-two-readiness.md","test/daily_choice/presentation/daily_choice_creation_launcher_test.dart","test/daily_choice/presentation/daily_choice_picker_context_test_support.dart"]
- **Applicable constraints and non-goals:** Свидетельства относятся к исправленной ревизии и честно раскрывают отсутствие проверки устройства. Успех, отмена, возврат, выход после принятия команды и частичные отказы сохраняют принадлежность исходной истории и результата. Готовность Phase 2 не означает завершения всего изменения. Инструменты не устанавливаются и не обновляются; история задач и план сохраняются.
- **Excluded change scope:** Phase 3 остаётся без пакета задач; её планирование и реализация не входят в этот этап.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | /root/picker_decision_review запущен с fork_turns=none по implementation-decision-review. Получил нейтральные намерения U1/U2, exact base/head, упорядоченные target commits и полную объединённую границу пяти delivery-путей. Прочитал diff и полные файлы head, проверил неизменность контекстных файлов до чтения. Планирование, прежнее ревью и описания коммитов не передавались. Подтвердил F2 и полное покрытие группы. |
| OpenSpec conformance | Complete | Из head прочитаны proposal, delta specs, применимые canonical specs, design, ADR manifest, plan, задачи и применимые ADR. Обе задачи и оба коммита сопоставлены с U1/U2. Генерация, strict OpenSpec validate, полный check и release-сборка завершились с Exit 0 на reviewed head в корне репозитория; 5223 теста приложения и 8 тестов Widgetbook прошли. Требуемое тестовое свидетельство доступности кандидатов имеет дефект F2. |
| Code quality | Complete | Все пять delivery-путей рассмотрены по корректности, читаемости, архитектуре, безопасности, производительности и качеству свидетельств. Прослежены Scaffold/SafeArea, общий поиск и семантика, конкретные маршруты, launcher, отмена и вспомогательный выбор. Dart MCP analyze_files четырёх изменённых Dart-файлов: No errors. Ошибка finder подтверждена исходниками закреплённого flutter_test. |

## Findings

### F2 · Medium — Матрица подтверждает поле поиска вместо достижимости кандидата

- **Evidence:** На reviewed head в test/daily_choice/presentation/daily_choice_picker_context_test_support.dart:374 поле получает «Гулять», после чего строка 407 выбирает find.text('Гулять').first для ensureVisible/hitTestable (строки 403–412). find.text включает EditableText, а controls с полем предшествуют results в IntentionSearchLayout; первым выбирается ввод, а не строка выдачи. Это подтверждено package:flutter_test/src/finders.dart:1538–1541 закреплённого SDK через Dart MCP. В docs/verification/persistent-navigation-phase-two-readiness.md:31 достижимость кандидатов объявлена проверенной. Получение lateSelection из IntentionSummaryView доказывает наличие обработчика в дереве, но не достижимость строки при клавиатуре. Остальные проверки выбора кандидатов не закрывают эту матрицу InitialDailyChoicePickerContext с клавиатурой и увеличенным текстом.
- **Evidence revisions:** ["48c896a5f78b7e95d1147eae6391a9985e8d788f"]
- **Impact:** Все 96 сочетаний могут пройти без проверки доступности строк выдачи, поэтому регрессия их достижимости останется незамеченной, а свидетельство готовности 2.24 завышает доказанное покрытие. Это дефект проверки и достоверности отчёта; фактическая недоступность кандидатов в исправленном приложении не установлена.
- **Required outcome:** Заявленная доступность выдачи в обеих начальных поисковых страницах должна проверяться именно на кандидате во всей установленной матрице, включая клавиатуру и текст 2.6. Проверка должна отличать строку от одноимённого ввода и обнаруживать её недостижимость; документ готовности должен соответствовать свежим результатам такой проверки.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["test/daily_choice/presentation/daily_choice_picker_context_test_support.dart","docs/verification/persistent-navigation-phase-two-readiness.md","openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md:2.23","openspec/changes/add-quick-creation-and-persistent-navigation/tasks.md:2.24"]

## Review coverage

Все шесть reviewable paths учтены: tasks.md — свидетельство планирования; две страницы приложения — поведение; два тестовых файла — проверка поведения; readiness-документ — поставляемое свидетельство готовности. Точное множество delivery-путей равно объединению Implementation target U1/U2: пять файлов. Несопоставленных и посторонних изменений нет. U1/U2 пересекаются по двум тестовым файлам и проверены одним независимым reviewer с объединённым нейтральным brief. Дополнительный изолированный reviewer /root/readiness_decision_review проверил документ и неизменённый контекст, но сообщил неполноту границы без изменённых тестов; этот пробел закрыт объединённым проходом, его частичный вывод не используется как самостоятельное подтверждение всей U2.

Задача ID 40 / 2.23 «Сохранить видимую и достижимую текстовую отмену обоих начальных поисков дневного выбора при открытой клавиатуре»: fromExclusive 60ecc6aa563611c03526f53d22646e892c314837, throughInclusive 9ffa2dd7c45dc24a8b992e6d1434b3603a16c003, единица U1. Две страницы учитывают клавиатуру в нижнем действии и используют существующий fullViewport для списка; helper добавляет 96 сочетаний и проверяет отмену, семантику и историю; launcher добавляет четыре сценария над чужим черновиком. Дефект свидетельства доступности кандидатов отражён в F2.

Задача ID 41 / 2.24 «Подтвердить готовность Phase 2 после исправления доступности отмены начального поиска»: fromExclusive 9ffa2dd7c45dc24a8b992e6d1434b3603a16c003, throughInclusive 48c896a5f78b7e95d1147eae6391a9985e8d788f, единица U2. Обновлены только документ готовности и отметка 2.24. Связка ревизии/дерева верна, но утверждение о достижимости кандидатов зависит от F2.

Каждый target commit рассмотрен отдельно в сохранённом taskCommitRange, затем проверен совокупный base..head. Сравнение подтвердило: в tasks.md изменены только [ ] → [x] у 2.23 и 2.24; описания, ID, номера, порядок и прочие отметки сохранены. plan.md дословно совпадает с base. Нумерация фаз и пакеты Phase 1/2 согласованы, Phase 3 не представлена задачами.

Документ готовности ссылается на 9ffa2dd7c45dc24a8b992e6d1434b3603a16c003 и его дерево c1153bc681163039a7a5af1c6d883bf68bae92f4. Между этой ревизией и reviewed head исходники приложения и тестов не менялись. Автоматическая матрица геометрии кнопки, семантики, прямого нажатия, отмены до закрытия, отсутствия команды, точных matchId, нижележащего фильтра и позднего выбора соответствует заявленным проверкам; доступность кандидата имеет отдельный пробел F2. Сохраняются типизированные начальный/вспомогательный контексты и прежний контракт замены пути.

Проверки этой сессии выполнены в /home/seniorkonung/.paseo/worktrees/1id27gtb/hypnotic-bird на 48c896a5f78b7e95d1147eae6391a9985e8d788f. Перед проверками HEAD совпадал с reviewed head и рабочая копия была чистой. Во время полного check изменён только этот отчёт; исходники, тесты, зависимости и конфигурация оставались в проверяемом снимке. После всех прогонов изменён только implementation-review.md; generated-файлы и lockfile не изменены. Discovery использовал временную обёртку, которая вызывает OpenSpec только через mise exec --no-deps -- openspec.

Проверка MISE_AUTO_INSTALL=false mise run codegen-check: Exit 0; локализация, генераторы и снимок Drift воспроизводятся, ноль изменённых generated-файлов, рабочая копия после команды чистая.

Проверка mise exec --no-deps -- openspec validate add-quick-creation-and-persistent-navigation --strict --json: Exit 0, valid: true, issues: [].

Проверка Dart MCP analyze_files: No errors для всех четырёх изменённых Dart-файлов.

Проверка MISE_AUTO_INSTALL=false mise run check: Exit 0; форматирование 585 файлов без изменений, проверки области CI и закреплённых зависимостей Widgetbook успешны, flutter analyze без замечаний, 5223 теста приложения и 8 тестов Widgetbook прошли, без пропусков. Общий прогон включает обе страницы с 96 сочетаниями матрицы, launcher, вспомогательную замену пути, четыре потока создания и навигацию. Успех прогона не устраняет ложную проверку кандидата, описанную в F2.

Проверка MISE_AUTO_INSTALL=false mise exec --no-deps -- flutter build apk --release: Exit 0; build/app/outputs/flutter-apk/app-release.apk, 66.7 MB. Использованы закреплённые инструменты без установки или обновления. Приведённые результаты получены в этой сессии; прежние записи readiness-документа не заменяют свежую проверку.

Dart MCP dtd listDtdUris не обнаружил работающего приложения или DTD. Применён предусмотренный задачами CLI-путь; горячая перезагрузка, get_runtime_errors и ручная проверка TalkBack на устройстве не выполнялись. Отсутствие проверки устройства раскрыто и в readiness-документе; автоматическая семантика не выдаётся за ручную проверку.

Принятых остаточных рисков и нерешённых продуктовых вопросов нет. F2 остаётся неразрешённой и передаётся последующему этапу finding-resolution. Коррекция не реализована и не передана в новую задачу в этом аудите; история завершённых задач, план, код и тесты сохранены. Остаточный риск не принимался. Публикация review-коммита принадлежит оркестратору; реализация и планирование других фаз за границей этапа.
