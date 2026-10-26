# OpenSpec Implementation Review: redesign-intention-picker-show-and-sort

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Все три прохода завершены; все 10 задач проверенного диапазона и 26 путей покрыты обзором. Неразрешённых замечаний нет: устранение двух диагностик анализатора в тесте OrderButton передано новой незавершённой задаче 1.11 в tasks.md по явному решению пользователя. Это передача исправления в планирование, а не подтверждение исправленного кода: на Reviewed head mise run check завершился с ошибкой. Готовность Phase 1 подтвердит следующий обзор реализации после задачи 1.11. Принятых остаточных рисков нет.

## Review target

- **Baseline ref:** 5e5f3f30cd2f0c69bf6f68d489d9791910599e9e
- **Base commit:** 5e5f3f30cd2f0c69bf6f68d489d9791910599e9e
- **Reviewed head:** 8f5c357d238a5d502c199de670bd8719bdb335df
- **Target commits:** ["b96b8bc56b29fccbf4e3352a411765cee25cfbc0", "b609788c76eea1a047f808e7361ce9d64c0c7f81", "43d2845910ee62563c74a8b19c06932d6a800244", "50ccf5a0140caea6492a2eb96a9a5edcd520a510", "99bfc9c2b2053c8b69e93116b7130bf45c8b360b", "376c7ab62ae2765a00496563727d0391615ec09a", "8e865b2853f2a7a44322c0b11da2daf643c1a68e", "db1d8e94663ec1bf1827c3fb00b3bf6f9bc93b76", "67fadcc08e374f251d6e7210391d5bf6f39a4950", "8f5c357d238a5d502c199de670bd8719bdb335df"]
- **Reviewable paths:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/design_system/components/option_group.dart", "lib/src/design_system/components/order_button.dart", "lib/src/design_system/components/select_row.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/arrow_down.svg", "lib/src/design_system/icons/assets/selector.svg", "lib/src/design_system/icons/assets/sort_asc.svg", "lib/src/design_system/icons/assets/sort_desc.svg", "lib/src/design_system/text_metrics.dart", "lib/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart", "openspec/changes/redesign-intention-picker-show-and-sort/tasks.md", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png", "test/design_system/option_group_test.dart", "test/design_system/order_button_test.dart", "test/design_system/select_row_test.dart", "test/design_system/sheet_test.dart", "test/intention/presentation/picker/intention_picker_show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart"]
- **OpenSpec change:** redesign-intention-picker-show-and-sort
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-intention-picker-show-and-sort/tasks.md"]

## Reviewed increment

### U1 · Значки выбора и направления в обеих темах

- **Work items:** ["1.1 (taskId 1)", "1.2 (taskId 2)", "1.9 (taskId 9)"]
- **Requirements and scenarios:** ["Параметры показа в поиске для выбора — селектор и значок текущего направления", "Кнопка направления переключает порядок по названию"]
- **Affected boundary:** Локальные SVG, типизированный каталог значков и эталон светлой и тёмной тем.
- **Implementation target:** ["lib/src/design_system/doable_icon.dart", "lib/src/design_system/icons/README.md", "lib/src/design_system/icons/assets/arrow_down.svg", "lib/src/design_system/icons/assets/selector.svg", "lib/src/design_system/icons/assets/sort_asc.svg", "lib/src/design_system/icons/assets/sort_desc.svg", "test/design_system/doable_icon_test.dart", "test/design_system/goldens/doable_icons.png"]
- **Applicable constraints and non-goals:** Геометрия источника дизайна, тематический цвет и автономная поставка ресурсов; остальные значки сохраняются. Удаление arrow_up.svg учтено как прежняя сторона переименования в selector.svg в полном diff.

### U2 · Читаемые и доступные общие контролы листа

- **Work items:** ["1.3 (taskId 3)", "1.4 (taskId 4)", "1.7 (taskId 7)", "1.8 (taskId 8)", "1.10 (taskId 10)"]
- **Requirements and scenarios:** ["Меню параметров показа в поиске для выбора", "Нажатие вне меню не переключает направление сортировки", "Системное «назад» закрывает только открытое меню", "Крупный текст переносится в строках и меню"]
- **Affected boundary:** Дизайн-система: строки выбора, кнопка направления, метрики текста, шапка общего Sheet и удаляемая группа кнопок.
- **Implementation target:** ["lib/src/design_system/components/option_group.dart", "lib/src/design_system/components/order_button.dart", "lib/src/design_system/components/select_row.dart", "lib/src/design_system/components/sheet.dart", "lib/src/design_system/text_metrics.dart", "test/design_system/option_group_test.dart", "test/design_system/order_button_test.dart", "test/design_system/select_row_test.dart", "test/design_system/sheet_test.dart"]
- **Applicable constraints and non-goals:** Системный масштаб текста, перенос, правый край всей строки, семантика выбора и поглощение внешнего касания; предметная логика остаётся у потребителя. Изменение шапки обслуживает достижимый случай «Сбросить» при крупном русском тексте; общая модель движения листа не меняется.

### U3 · Параметры той же выдачи во всех назначениях поиска

- **Work items:** ["1.5 (taskId 5)", "1.6 (taskId 6)", "1.7 (taskId 7)", "1.8 (taskId 8)", "1.10 (taskId 10)"]
- **Requirements and scenarios:** ["Параметры показа в поиске для выбора", "Меню типа показывает количества независимо от выбранного типа", "Меню типа без чисел до получения выдачи", "Повторный выбор текущего типа сохраняет позицию списка", "Выбор типа сразу меняет список, а количества учитывают поиск", "Переход от времени к названию выбирает прямой порядок", "Переход между временем создания и изменения сохраняет направление", "Кнопка направления переключает порядок по названию", "«Сбросить» возвращает начальный показ"]
- **Affected boundary:** Общая панель поиска исходного намерения, действия и участника связи; модель поиска и локализация ru/en.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart", "test/intention/presentation/picker/intention_picker_show_and_sort_sheet_test.dart", "test/intention/presentation/picker/intention_picker_view_test.dart", "lib/src/design_system/components/sheet.dart", "test/design_system/sheet_test.dart"]
- **Applicable constraints and non-goals:** Параметры принадлежат странице, числа появляются только у подтверждённой текущей выдачи; закреплённый тип действия остаётся недоступным с пояснением. Правила хранения, общий каталог и лист назначения поиска вне изменения.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Изолированные контексты с fork_turns=none: review_icons (gpt-6-luna, high) — U1; review_controls (gpt-6.1-sol, high) — объединённая группа U2/U3 с общими изменёнными путями Sheet и его теста. Каждый получил нейтральные цели, полные SHA, полный список назначенных путей и запрет чтения планирования/истории. Оба вернули Complete / No substantive findings. |
| OpenSpec conformance | Complete | Проверены полные артефакты Reviewed head, все сценарии delta-спецификации, связь с каноническими требованиями и задачи 1.1–1.10. Строгая OpenSpec-валидация, codegen-check, 3517 обычных и 18 процессных тестов успешны. Release APK собран. Условие прохождения mise run check на Reviewed head не выполнено; исправление и повторная проверка готовности принадлежат задаче 1.11 и следующему обзору реализации. Команды, место и ревизия исходного аудита приведены ниже. |
| Code quality | Complete | По code-review-and-quality проверена вся совокупность delivery paths: корректность, читаемость, архитектура, безопасность и производительность; также неизменённые модель поиска, владелец прокрутки и точки открытия листа. Подтверждены два замечания анализатора в тесте OrderButton, переданные задаче 1.11; других существенных дефектов или избыточного поведения не выявлено. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все 26 путей сохранённого diff распределены между U1–U3 и planning evidence; несопоставленных путей нет. Точная совокупность delivery paths равна Reviewable paths за исключением tasks.md. Планирование прочитано из Reviewed head: proposal.md, specs/intention-management/spec.md, design.md, adr.md, plan.md, tasks.md; контекст — CONTEXT.md, канонические требования и применимые ADR-0028, 0029, 0030, 0032, 0044. При начале исходного аудита HEAD совпадал с Reviewed head, рабочая копия была чистой; исходные и генерируемые файлы во время аудита не исправлялись. При исходном аудите ранее существующего implementation-review.md и переносимых F/AR не было. Добавленная позднее задача 1.11 не входит в проверенный диапазон и не меняет его покрытие.

Все десять коммитов проверены в заданном порядке: просмотрены их состав и изменения задач, изменения реализации и тестов сопоставлены с итоговым diff. Промежуточные замены и удаления учтены по Base/Reviewed head; отметки выполнения не использованы как доказательство корректности.

Task ID 1 / 1.1, коммит b96b8bc56b29fccbf4e3352a411765cee25cfbc0, U1: Самостоятельные SVG и источник в каталоге.

Task ID 2 / 1.2, коммит b609788c76eea1a047f808e7361ce9d64c0c7f81, U1: Регистрация значков, размеры, эталон обеих тем.

Task ID 3 / 1.3, коммит 43d2845910ee62563c74a8b19c06932d6a800244, U2: SelectRow, метрики текста, реальные меню над Sheet.

Task ID 4 / 1.4, коммит 50ccf5a0140caea6492a2eb96a9a5edcd520a510, U2: OrderButton, фокус, клавиатура и действие диктора.

Task ID 5 / 1.5, коммит 99bfc9c2b2053c8b69e93116b7130bf45c8b360b, U3: Отдельные подписи листа ru/en и генерируемые классы.

Task ID 6 / 1.6, коммит 376c7ab62ae2765a00496563727d0391615ec09a, U3: Строка типа, актуальные числа, закрепление действия, входы из трёх назначений.

Task ID 7 / 1.7, коммит 8e865b2853f2a7a44322c0b11da2daf643c1a68e, U2, U3: Сортировка, направление, сброс, читаемость всей панели и шапки.

Task ID 8 / 1.8, коммит db1d8e94663ec1bf1827c3fb00b3bf6f9bc93b76, U2, U3: Удалены OptionGroup, его тесты и подпись отдельного порядка.

Task ID 9 / 1.9, коммит 67fadcc08e374f251d6e7210391d5bf6f39a4950, U1: Удалены прежние стрелки, согласованы каталог и эталон.

Task ID 10 / 1.10, коммит 8f5c357d238a5d502c199de670bd8719bdb335df, U2, U3: Только отметка задачи; исходный аудит не подтвердил готовность из-за двух диагностик анализатора.


Каждый сценарий delta-спецификации сопоставлен с тестом в Reviewed head. Ниже номера строк относятся к test/intention/presentation/picker/intention_picker_show_and_sort_sheet_test.dart; общие проверки механизма дополнительно находятся в select_row_test.dart и order_button_test.dart.

Сценарий «Меню типа показывает количества независимо от выбранного типа»: Строка 40: выбор типа и количества 3/2/1 до и после ограничения по типу.

Сценарий «Меню типа без чисел до получения выдачи»: Строка 40: меню открыто во время загрузки и обновляется после ответа; строка 138 — снятие прежних чисел и отказ.

Сценарий «Нажатие вне меню не переключает направление сортировки»: Строка 228: первое нажатие OrderButton закрывает любое меню без команды модели; select_row_test.dart — поглощение касания затемнения.

Сценарий «Повторный выбор текущего типа сохраняет позицию списка»: Строка 180: повторное «Всё» сохраняет запрос, выдачу и pixels; новый тип возвращает к началу.

Сценарий «Системное «назад» закрывает только открытое меню»: Строка 228: оба меню, параметры, выдача и позиция сохранены; следующее back закрывает Sheet.

Сценарий «Выбор типа сразу меняет список, а количества учитывают поиск»: Строка 40: фильтр «чит», новый тип, заголовок, выдача и подтверждённые числа.

Сценарий «Переход от времени к названию выбирает прямой порядок»: Строка 465: переход с даты на название, актуальное значение до ответа новой порции.

Сценарий «Переход между временем создания и изменения сохраняет направление»: Строка 465: переходы между обеими датами сохраняют возрастающее направление.

Сценарий «Кнопка направления переключает порядок по названию»: Строки 228 и 465: новая команда, верх списка, сводка, значок и доступное название текущего/следующего порядка.

Сценарий ««Сбросить» возвращает начальный показ»: Строка 583: тип, дата создания, направление, верх списка; фильтр и теги сохраняются.

Сценарий «Крупный текст переносится в строках и меню»: Строка 321: ru/en × ширины 320/390 × масштабы 1/2 × свободный/закреплённый тип; фактические границы и полная высота TextPainter.


Закреплённый тип и доступность проверяются на строке 676; вход через заголовок во всех трёх назначениях — в intention_picker_view_test.dart. Механизм поиска, согласования подтверждённых операций и изоляции страниц остаётся у прежней модели; он не продублирован в новых компонентах. Ресурсы XML, геометрия SVG относительно локального источника ActionPicker и все ссылки каталога проверены скриптом; эталон значков просмотрен визуально. Удалённые OptionGroup и arrow_up/arrow_down больше не имеют использований в lib/ и test/. Новых зависимостей, сетевых обращений, схем данных или миграций нет; отдельные механизмы безопасности и наблюдаемости для этого изменения не требуются.

Приведённые ниже проверки выполнены при исходном аудите из /home/seniorkonung/.paseo/worktrees/1id27gtb/giant-starfish на ревизии 8f5c357d238a5d502c199de670bd8719bdb335df. Исходники, зависимости и генерируемые файлы соответствовали этому коммиту; добавление самого отчёта не меняет входы анализа, тестов и сборки.

Запуск `mise run check` завершился с кодом 1: форматирование 815 файлов прошло без изменений, проверки определения области CI и разбиения тестов прошли, затем flutter analyze остановил check:static на `unnecessary_import` для избыточного импорта `flutter/semantics.dart` в test/design_system/order_button_test.dart:9 и `deprecated_member_use` для `tester.binding.pipelineOwner` в строке 84. Для полного покрытия фазы оставшиеся части того же набора выполнены отдельно и последовательно: `mise run check:tests -- 0 1` — код 0, 3517 тестов; `mise run check:process-tests` — код 0, 18 тестов. Сбой общего check на проверенной ревизии сохраняется; отдельные успешные наборы его не отменяют.

Запуск `mise run codegen-check` выполнен до создания отчёта на чистой рабочей копии: код 0, повторная генерация локализации, Riverpod, Drift и маршрутов не изменила tracked-файлы и pubspec.lock. `mise exec --no-deps -- openspec validate redesign-intention-picker-show-and-sort --type change --strict --no-interactive --json` — код 0, valid: true, issues: []. `git diff --check` для сохранённого диапазона — код 0. Дополнительно проверены точное совпадение массива Target commits с сохранённым диапазоном, полный учёт Reviewable paths и соответствие всех taskId/номеров их коммитам.

Сборка командой `mise exec --no-deps -- flutter build apk --release --no-pub` — код 0. Доступный артефакт: /home/seniorkonung/.paseo/worktrees/1id27gtb/giant-starfish/build/app/outputs/flutter-apk/app-release.apk, размер 72235488 байт, SHA-256 678c3f132f0d96fa6a6c068e063f24c9bf3ed0a14ef98040c58fff0f52e6a0b4. Визуальная сверка на устройстве, TalkBack и нативное системное «назад» вручную не проверялись; их выполняет пользователь позднее. Автоматизированные проверки закрытия меню подтверждены, исправление исходного дефекта непосредственно на устройстве этим аудитом не утверждается.

Последующая передача в планирование ограничена новой незавершённой [задачей 1.11](tasks.md), добавленной в конец Phase 1 по явному решению пользователя запланировать исправление. Задачи 1.1–1.10 и их отметки сохранены дословно. Требуемое поведение уже принадлежит [delta-спецификации](specs/intention-management/spec.md), подход к проверке — решению 6 [дизайна](design.md), а условие готовности — [плану](plan.md); их изменения не требуются. Задача сохраняет реальную проверку команды экранного диктора и требует устранить обе диагностики; успешный полный `mise run check` на исправленной ревизии должен подтвердить следующий обзор реализации, который завершает Phase 1. Код и тесты на этапе передачи не изменялись; тесты, сборки и проектные проверки не запускались. Исправление кода и готовность фазы пока не подтверждены, остаточный риск не принимался. Отчёт фиксирует результат обзора и передачу исправления в планирование; он не даёт разрешения на слияние или архивацию.
