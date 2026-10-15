# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Рассмотрены все три целевых коммита, задачи 24 / 2.15, 25 / 2.16 и 26 / 2.17 и все семь изменённых путей. Проверки reviewed head подтвердили полноэкранный перенос из Split screen, сохранение сессии, повторный launcher с одной карточкой и правильные системные жесты «Назад». Согласованным исправлением холодного запуска большого хоста владеют решение 6 в design.md и новые незавершённые задачи 2.18–2.19: сохранить выбранное системой размещение и подтвердить его на Android. Активных замечаний и принятых остаточных рисков нет. Код ещё не исправлен; воспроизведение холодного входа, готовность всей фазы 2 и физическая проверка владельца этим отчётом не подтверждаются.

## Review target

- **Baseline ref:** ff33528c32ef39a9c701bc6042bbeeae289338de
- **Base commit:** ff33528c32ef39a9c701bc6042bbeeae289338de
- **Reviewed head:** d7c03e5b404d65ad7eccc933a805c2d49fd23748
- **Target commits:** ["5b3dc2ac797c5469b18a47975d570003fb5f5461", "bd5e2cec2b54db24787018b69e2e9a8f25e239d7", "d7c03e5b404d65ad7eccc933a805c2d49fd23748"]
- **Reviewable paths:** ["android/app/src/main/AndroidManifest.xml", "android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/main/kotlin/software/doable/doable/MainActivity.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "openspec/changes/redesign-daily-choice-calendar/tasks.md", "tool/check_android_display_transfer.py"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Полный телефонный экран и сохранение сессии при переносе из Split screen

- **Work items:** ["24 / 2.15", "25 / 2.16"]
- **Requirements and scenarios:** ["app-appearance: Портретная ориентация на телефоне", "app-appearance: Разделённый экран на телефоне недоступен", "ADR-0031: системные режимы больших дисплеев и граница 600 dp", "app-navigation: Сохранение состояния корневых страниц", "design.md: решение 6, отдельные task и регрессия переноса 2.16"]
- **Affected boundary:** Нативный запуск Android, полный дисплей, размещение и карточки Android task, жизненный цикл FlutterEngine, сохранённые экран и состояние каталога.
- **Implementation target:** ["android/app/src/main/AndroidManifest.xml", "android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/main/kotlin/software/doable/doable/MainActivity.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "tool/check_android_display_transfer.py"]
- **Applicable constraints and non-goals:** Android API 24+, targetSdk 36. Телефон определяется короткой стороной полного дисплея менее 600 dp, а не узким окном планшета. Ограничения действуют с нативного запуска, включая подготовку хранилища и её отказ; большие дисплеи сохраняют системные ориентацию и многооконность. Перенос и launcher сохраняют сессию без второго движка и второй карточки. Сценарий использует обычный Split screen без принудительных обходных настроек и восстанавливает параметры эмулятора. Новых раскладок и изменений данных нет.
- **Excluded change scope:** Задачи 1.1–2.14 не переаудируются. Выбор года и месяца фазы 3 и физическая проверка владельца не входят в это приращение.

### U2 · Системный жест «Назад» следует сохранённой навигации после переноса

- **Work items:** ["26 / 2.17"]
- **Requirements and scenarios:** ["app-navigation: Действие «назад» на корневых страницах", "app-navigation: Выход из потока создания", "intention-management: Сессия черновика создания намерения", "intention-management: Продолжение после попытки закрытия", "design.md: решение 6, согласование жеста с навигацией Flutter"]
- **Affected boundary:** Регистрация системного обработчика в Android Activity, передаваемый FlutterEngine, Navigator и PopScope, подробности намерения, изменённый черновик и Главная.
- **Implementation target:** ["android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "tool/check_android_display_transfer.py"]
- **Applicable constraints and non-goals:** Источником готовности обработать возврат остаётся Flutter. Перенос не пересоздаёт Navigator, не требует промежуточного действия и не включает перехват безусловно. Новый хост применяет переданное значение после подключения движка; дальнейшие уведомления Flutter остаются действующими. Проверяется настоящий жест от края при navigation_mode=2, а не KEYCODE_BACK; подтверждение закрытия черновика и обычный выход с Главной сохраняются.
- **Excluded change scope:** Новые правила возврата, расширение матрицы жестов на другие API и направления переноса и физическое складывание не добавляются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий контекст /root/independent_decisions с fork_turns=none применил implementation-decision-review ко всему объединению шести delivery/test paths U1 и U2 в точном сохранённом диапазоне. Переданы нейтральное намерение, границы и SHA; планирование, история коммитов, прежний отчёт и замечания не передавались. Неизменность контекстных путей проверялась до чтения. После проверки правил AOSP reviewer завершил покрытие; координатор проверил исходные доказательства. |
| OpenSpec conformance | Complete | Из reviewed head прочитаны proposal, три delta-spec, design, adr, plan, tasks, ADR-0031 и относящиеся к переносу канонические контракты. Все пути и три taskCommitRanges сопоставлены с U1/U2; проверены необходимые результаты и избыточность. Проверена применимость контракта сохранения системного режима большого дисплея к холодному запуску. На точном reviewed head прошли строгая OpenSpec validation, 44 свежих нативных теста, 6 тестов test/android, сборка APK и сценарий переноса API 36. |
| Code quality | Complete | По code-review-and-quality рассмотрены все шесть delivery/test paths: корректность, читаемость, архитектура, безопасность и производительность. Проверены affinity, launcher/AppTask, момент удаления исходной task, владение движком, готовность «Назад», реальные наблюдения сценария и восстановление настроек. Рассмотрен общий путь холодного запуска. Новых зависимостей, разрешений, внешних production-интеграций и миграций нет; хосты остаются неэкспортируемыми. diff --check успешен. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все семь reviewable paths учтены: tasks.md — плановое доказательство, остальные шесть — точное подмножество поставки, полностью покрытое U1 и U2. Общие пути объединены для одного независимого reviewer; отдельные результаты единиц сохранены. Несопоставленных или посторонних путей нет. Рабочее дерево до проверки было чистым, HEAD совпадал с reviewed head. Версионируемые доказательства читались по полным сохранённым SHA. Прежний отчёт прочитан после независимого прохода; активных F/AR в нём нет.

Каждый целевой коммит и сохранённый диапазон задачи рассмотрены отдельно:

Задача ID 24, номер 2.15, «Переход из разделённого экрана большого дисплея в телефонную категорию сохраняет сессию в полном портретном окне»: диапазон ff33528c32ef39a9c701bc6042bbeeae289338de..5b3dc2ac797c5469b18a47975d570003fb5f5461, U1. Коммит 5b3dc2ac797c5469b18a47975d570003fb5f5461 меняет affinity, передачу и удаление task, launcher и нативные тесты; отмечает только 2.15. Основной результат подтверждён runtime на reviewed head; общий путь запуска также рассмотрен.

Задача ID 25, номер 2.16, «Регрессионная проверка на Android подтверждает полноэкранный перенос в телефонную категорию с сохранением сессии»: диапазон 5b3dc2ac797c5469b18a47975d570003fb5f5461..bd5e2cec2b54db24787018b69e2e9a8f25e239d7, U1. Коммит bd5e2cec2b54db24787018b69e2e9a8f25e239d7 добавляет наблюдения фактического Split screen, полного окна, сохранённого каталога, launcher и восстановления настроек; отмечает только 2.16. Проверен итоговый сценарий reviewed head.

Задача ID 26, номер 2.17, «После переноса двигателя системный жест «Назад» соблюдает сохранённую навигацию и ограничения закрытия»: диапазон bd5e2cec2b54db24787018b69e2e9a8f25e239d7..d7c03e5b404d65ad7eccc933a805c2d49fd23748, U2. Коммит d7c03e5b404d65ad7eccc933a805c2d49fd23748 передаёт готовность Flutter обработать возврат, добавляет нативные проверки обоих значений и потребления extras, расширяет сценарий реальными жестами; отмечает только 2.17. Локальные исходники установленного Flutter 3.47.1 подтверждают контракт setFrameworkHandlesBack. Новые проверки различают потерю состояния при переносе, обход подтверждения и постоянный перехват выхода.

Проверки выполнены в /home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn на d7c03e5b404d65ad7eccc933a805c2d49fd23748 без изменения исходников и тестов:

Команда `mise exec --no-deps -- flutter test --no-pub test/android` — exit 0, 6 тестов.

Команда `JAVA_HOME=/home/seniorkonung/.local/share/mise/installs/java/temurin-25.0.3+9.0.LTS mise exec --no-deps -- android/gradlew -p android :app:testDebugUnitTest --offline --console=plain --rerun-tasks` — exit 0, BUILD SUCCESSFUL; свежий JUnit XML: 44 теста на API 24, 30, 35, 36, 0 failures/errors/skipped.

Команда `JAVA_HOME=/home/seniorkonung/.local/share/mise/installs/java/temurin-25.0.3+9.0.LTS mise exec --no-deps -- flutter build apk --debug --no-pub` — exit 0. SHA-256 APK: 0647b584368f8a09ee6efc81d113a45f4fc9b3fd999c3cf28f3941d6970cd890.

Команда `python3 tool/check_android_display_transfer.py --serial emulator-5554` — exit 0. AVD doable-foundation-2-3, Android API 36, navigation_mode=2. Дампы, XML и снимки: /tmp/doable-display-transfer-uxvgjinr. Settings и LargeDisplayActivity действительно видимы в multi-window на полном дисплее 600×900 dp; исходные границы приложения [0,0,600,445]. После перехода к 390×844 dp PhoneActivity активна, fullscreen, multi-window=false, portrait; bounds, display и фактический frame равны [0,0,390,844]. PID 2332 сохранён. Выбранное 14 октября 2026, раскрытый ноябрь, фильтр «Не выполненные», количество 1 и строка дневного выбора совпадают до/после. Launcher сохраняет тот же каталог, PID и одну карточку. Контроль без переноса и первый жест после переноса с подробностей возвращают Главную; PhoneActivity активна. Жест в изменённом черновике при скрытой клавиатуре запрашивает подтверждение, продолжение сохраняет текст; жест с Главной показывает launcher. Сценарий подтвердил восстановление исходных size/density/rotation.

Команда `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json` — exit 0, valid=true, issues=[].

Команда `git --literal-pathspecs diff --check ff33528c32ef39a9c701bc6042bbeeae289338de d7c03e5b404d65ad7eccc933a805c2d49fd23748` — exit 0.

Сообщения коммитов проверены: 2.15 и 2.16 записывают обнаружение прежней регрессии общей affinity, а 2.17 — успешный mise run check с 2669 тестами. Это свидетельства автора, отдельно от свежих проверок выше. Старые APK и их red/green в этом аудите не запускались. Полный mise run check здесь не повторяется: этап завершает ограниченное ревью, а не фазу плана; затронутые модули и непосредственно затронутые потребители проверены. Моделирование размера эмулятором не доказывает физическое складывание, runtime API 24–35 или подготовку хранилища с отказом. Эти границы не выданы за дефекты других направлений или принятие риска; физическая проверка владельца и остальные условия Ready to advance остаются действующими.

Дополнительная попытка холодного входа во вторую сторону не установила нужное предусловие: переход из Recents к списку приложений сначала показал Home. Она не подтверждает сохранение или потерю выбранной половины при холодном запуске; ещё одна попытка выбрать карточку не нашла нужный элемент. Эти наблюдения отделены от успешного сохранённого сценария. Параметры дисплея и поворота восстановлены; временно включённый gesture overlay отключён для возврата к исходному navigation_mode=0.

Процессные отклонения: первоначальный discovery helper вызвал OpenSpec через свой default executable; discovery повторён с временной обёрткой, исполняющей только `mise exec --no-deps -- openspec`, и подтвердил те же SHA и пути. Независимый reviewer при уточнении AOSP выполнил один запрещённый read-only запрос GitHub Contents API к списку внешних исходников; GitHub-состояние не менялось. Координатор проверил цепочку по прямым URL исходников. Установки и обновления инструментов и изменения ветки не выполнялись.

Согласованное исправление холодного запуска передано в планирование через openspec-update-change: решение 6 в [design.md](design.md) разграничивает сохранение системного размещения большого хоста и телефонный перенос, [tasks.md](tasks.md) назначает реализацию и нативную регрессионную защиту задаче 2.18, а наблюдение фактического холодного входа и сохранности переноса — следующей задаче 2.19. Обе задачи добавлены незавершёнными после всех существующих задач фазы 2 по явному решению владельца; все 26 прежних блоков и отметки сохранены. Спецификации, ADR и фазовый план сохраняют прежний контракт. Код и тесты не менялись, подтверждённого исправления реализации и принятия риска нет. Целевой диапазон и покрытие трёх проходов сохранены; повторный аудит не выполнялся. Следующая реализация выполняется отдельно, строго в порядке 2.18, затем 2.19. Передача не означает завершения фазы 2, физической проверки владельца, фазы 3 или всего изменения.
