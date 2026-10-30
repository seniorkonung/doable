# Решения по findings OpenSpec review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F1 · Medium — Задача 4.12 меняет сообщения пустой выдачи, но не обновляет `intention_app_lifecycle_test.dart`

- **Решение:** Устранить
- **Как устранить:** Изменить только tasks.md, задачу 4.12; новых задач не добавлять, порядок задач не менять. Добавить test/app/intention_app_lifecycle_test.dart в предполагаемые файлы 4.12 и в её команду проверки. Добавить в критерии приёмки 4.12 замену трёх ожиданий пустой выдачи по третьей причине: строка 239 `No active intentions yet.` → `No active intentions` (архив не пуст); строка 278 `No archived intentions yet.` → `Nothing in the archive` (архивный охват); строка 315 `No active intentions yet.` → `No intentions yet` (намерений нет совсем). Тестовый адаптер менять не нужно: `answerCatalogQuery` уже отдаёт матрицу чисел, а модель согласует её при архивировании и удалении. Поведение продукта не меняется. Эта же команда 4.12 дополняется по решению F2, поэтому обе правки должны стоять в ней вместе.

## F2 · Medium — Команды проверки задач пропускают прямых потребителей изменённых шагов и типов

- **Решение:** Устранить
- **Как устранить:** Изменить только tasks.md, незавершённые задачи фазы 4; новых задач не добавлять, порядок не менять, поведение продукта не меняется. Дополнить команды проверки и предполагаемые файлы. 4.2: в команде заменить два файла навигации всей папкой test/app/navigation и добавить test/app/long_term_relation_app_flow_test.dart. 4.6: добавить test/app/creation_flows_integration_test.dart. 4.7: добавить test/app/graph_import_app_flow_test.dart и test/app/graph_restore_app_flow_test.dart. 4.9: назвать в предполагаемых файлах все вызовы `cycle` — test/intention/presentation/picker/intention_picker_view_test.dart, test/long_term_relation/presentation/participant_picker/relation_participant_picker_test.dart, test/daily_choice/presentation/daily_choice_picker_tag_search_test_support.dart, test/intention/presentation/catalog/intention_picker_session_test_support.dart, test/intention/presentation/intention_tag_search_accessibility_test.dart; в команду добавить `mise run codegen` и папки test/intention/presentation/picker, test/long_term_relation/presentation/participant_picker, test/daily_choice/presentation/source_picker, test/daily_choice/presentation/action_picker и названный файл доступности; размер 4.9 поднять с S до M. 4.10: добавить test/intention/presentation/intention_tag_search_accessibility_test.dart в файлы и команду, потому что на удаляемом IntentionSearchLayout держатся его _pageScrollable и _reach. 4.12: добавить в команду test/app/graph_import_app_flow_test.dart, test/app/graph_restore_app_flow_test.dart, test/app/tag_app_flow_test.dart, test/app/creation_flows_integration_test.dart и test/app/long_term_relation_app_flow_test.dart вместе с файлом из решения F1.

## F3 · Low — `tagPhraseText` остаётся без вызовов, и ни одна задача его не удаляет

- **Решение:** Устранить
- **Как устранить:** Изменить только tasks.md; новых задач не добавлять, порядок не менять, поведение продукта не меняется. Задача 4.8 удаляет lib/src/tag/presentation/tag_phrase_text.dart вместе с последним вызовом `tagPhraseText`: добавить удаление в критерии приёмки и предполагаемые файлы 4.8 и указать в её зависимостях 4.3, где убирается первый вызов. Своих тестов у файла нет. В команду поиска задачи 4.14 добавить `tagPhraseText` и `tag_phrase_text`, чтобы она подтверждала отсутствие ссылок на файл и функцию.

## F4 · Low — Design и ADR-0049 по-разному называют источник слов заголовка списка

- **Решение:** Устранить
- **Как устранить:** Привести документы к коду, задаче 4.5 и решению 3 design: слова заголовка списка выбираются разбором параметров показа (`selection.scope` и `selection.type`), а не `IntentionSearchKind`; за `IntentionSearchKind` остаётся заголовок страницы или экрана выбора. Изменить design.md: строку схемы решения 1 (`header title`) и абзац про `IntentionSearchKind.of`. Изменить пункт «Разбор назначения» в docs/adr/0049-build-intention-catalog-and-pickers-from-one-search-module.md (ADR в статусе proposed, принадлежит этому изменению). В plan.md, Phase 1, строка 30, заменить «слов заголовка» на «заголовка экрана». Код, спецификации и задачи не менять, поведение продукта не меняется.

## F5 · Low — Верхний отступ заголовка в задаче 4.10 нельзя однозначно взять из макета

- **Решение:** Устранить
- **Как устранить:** Выбран вариант В пользователя: верхний отступ заголовка «Граф намерений» равен 16 (`DoableMetrics.space4`) от края `SafeArea`, как у каталога дневных выборов — корневой вкладки без AppBar с тем же устройством (daily_choice_catalog_body.dart). Значение 58 из Catalog.dc.html не переносится: оно считается от края кадра и включает системную строку. Пользователь считает, что верхние и нижние отступы определяются тем, как экран умещается в реализации, а не макетом. Изменить design.md, решение 2, пункт «Раскладка»: назвать верхний отступ заголовка 16 от края SafeArea и причину. Изменить tasks.md, задачу 4.10: вместо «верхний — по Catalog.dc.html» указать 16 (`space4`) от края SafeArea. Нижний отступ 24 в задаче 4.12 не меняется: он считается от верхнего края панели навигации. Новых задач и отдельной проверки отступа не добавлять: при масштабе текста 2 и клавиатуре раскладку уже проверяет задача 4.10. Эта же задача 4.10 дополняется по решению F2: её команду и файлы эта правка не затрагивает.
