# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** Changes needed
**Coverage status:** Complete
**Summary:** Полностью рассмотрены три целевых коммита, задача 23 / 2.14 и все 11 изменённых путей. Подтверждены F2 — телефонный корень сохраняет разделённый экран после смены категории; F3 — системный жест «Назад» после переноса закрывает Activity вместо возврата по сохранённому маршруту; F4 — планирование продолжает ссылаться на отменённую задачу устройств. Оба дефекта поведения воспроизведены на сборке reviewed head в эмуляторе API 36. Принятых остаточных рисков нет; исправления остаются последующим этапам разрешения замечаний.

## Review target

- **Baseline ref:** a7ac989243d860ce978740e76dd2faa2f67918c1
- **Base commit:** a7ac989243d860ce978740e76dd2faa2f67918c1
- **Reviewed head:** 8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea
- **Target commits:** ["2797209ffe6a6805f7d23a2fa4e36408a5af65ea", "b3836e0b2f136501b33d71d5a722f15a5691a464", "8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea"]
- **Reviewable paths:** ["android/app/build.gradle.kts", "android/app/src/main/AndroidManifest.xml", "android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/main/kotlin/software/doable/doable/MainActivity.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "docs/adr/0031-restrict-phones-to-portrait-full-screen.md", "docs/adr/README.md", "openspec/changes/redesign-daily-choice-calendar/design.md", "openspec/changes/redesign-daily-choice-calendar/tasks.md", "test/android/orientation_policy_test.dart"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["docs/adr/0031-restrict-phones-to-portrait-full-screen.md", "docs/adr/README.md", "openspec/changes/redesign-daily-choice-calendar/design.md", "openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Телефонная оконная политика и сохранение сессии при смене дисплея

- **Work items:** ["23 / 2.14"]
- **Requirements and scenarios:** ["app-appearance: Портретная ориентация на телефоне", "Поворот телефона не поворачивает интерфейс", "Разделённый экран на телефоне недоступен", "ADR-0031: граница дисплея 600 dp", "design.md: решения 6 и 9", "tasks.md: отмена проверки 2.15 владельцем"]
- **Affected boundary:** Нативный запуск Android, полноразмерный дисплей и окно Android task, жизненный цикл FlutterEngine и сохранённая навигация приложения.
- **Implementation target:** ["android/app/build.gradle.kts", "android/app/src/main/AndroidManifest.xml", "android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/main/kotlin/software/doable/doable/MainActivity.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "test/android/orientation_policy_test.dart"]
- **Applicable constraints and non-goals:** Android API 24+, targetSdk 36. Телефонный дисплей с короткой стороной менее 600 dp получает портретное полноэкранное окно при первом показе интерфейса, включая подготовку хранилища и её отказ. Дисплей от 600 dp сохраняет системные поворот и изменение размера; узкое окно не меняет категорию. Смена категории и повторный launcher сохраняют открытую сессию. Ограничения принадлежат Android; новые раскладки, изменения данных и opt-out Android 16 не входят в объём.
- **Excluded change scope:** Компоненты и интеграция календаря прежних задач 1.1–2.13 не переаудируются. Выбор года и месяца фазы 3 ещё не реализуется этим диапазоном; отсутствие её задач не является дефектом данного приращения.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Свежий контекст /root/android_independent_review с fork_turns=none по implementation-decision-review проверил все семь полных delivery/test paths U1 в точном base..head. Передан нейтральный brief; планирование, история коммитов, отчёт и прежние замечания не передавались. Неизменность контекстных путей проверена перед чтением. Динамические проверки выполняет координатор. |
| OpenSpec conformance | Complete | Прочитаны proposal, три delta-spec, design, adr, plan, tasks, канонический контекст и ADR-0031 из head. Все изменённые пути, коммиты, критерии 2.14 и отмена 2.15 сопоставлены с U1. Строгая OpenSpec validation: exit 0, valid=true, issues=[]. Проверки манифеста (6), нативные тесты (32) и debug APK успешны на reviewed head; runtime API 36 подтверждает нарушения телефонного режима и сохранённой навигации. Физическая проверка владельца исключена из задачи последним целевым коммитом; её отсутствие не выдано за успех приёмки. |
| Code quality | Complete | Все семь delivery/test paths просмотрены полностью по code-review-and-quality: классификация дисплея и плотности, lifecycle/cached engine, launcher/task root, безопасность экспортируемой точки входа, ограниченность вычислений и стоимость контекстов, тестовые наблюдения и Gradle. Новые зависимости только тестовые; новых входов пользовательских данных, миграций и production-сервисов нет. Unit-тесты защищают выбор Activity и Intent, но не фактический multi-window/Back — эти дефекты подтверждены отдельно. diff --check успешен. |

## Findings

### F2 · High — Телефонный корень сохраняет разделённый экран после смены категории

- **Evidence:** android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt:60–88 заменяет корень через NEW_TASK | CLEAR_TASK при сохранённой общей affinity Activity; android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt:41–53 инициирует замену при изменении дисплея. openspec/changes/redesign-daily-choice-calendar/design.md:197 предписывает эту пару флагов как механизм смены оконной политики. На свежем APK head в эмуляторе API 36: полный дисплей 1200×1800 px при 320 dpi (600×900 dp), LargeDisplayActivity в обычном Split screen с Settings; затем wm size 780x1688 (390×844 dp). dumpsys activity activities показывает тот же task #44, новый root PhoneActivity, resizeMode=RESIZE_MODE_UNRESIZEABLE, но mode=multi-window, mLastReportedMultiWindowMode=true и окно Rect(0,0–780,788). force_resizable_activities=null, enable_non_resizable_multi_window=0; обходные настройки не включались. Официальная семантика [CLEAR_TASK](https://developer.android.com/reference/android/content/Intent#FLAG_ACTIVITY_CLEAR_TASK) обещает очистку существующей задачи, а не смену режима её окна.
- **Evidence revisions:** ["8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea"]
- **Impact:** После перехода складного устройства в телефонную категорию приложение остаётся рядом с другим приложением, нарушая телефонное требование. Пользователь получает окно ниже поддерживаемой высоты закреплённого календаря. Успех выбора PhoneActivity и наличия флагов в Robolectric не проверяет фактический режим задачи.
- **Required outcome:** Переход из многооконного большого дисплея в телефонную категорию должен обеспечивать портретное полноэкранное окно с сохранением сессии. Регрессионная проверка должна наблюдать фактическое окно после переноса, а техническое решение — описывать механизм, обеспечивающий этот результат.
- **Earliest source of truth:** design/ADR
- **Affected artifacts:** ["openspec/changes/redesign-daily-choice-calendar/design.md", "docs/adr/0031-restrict-phones-to-portrait-full-screen.md", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt"]

### F3 · Medium — Системный жест «Назад» теряет сохранённый маршрут после переноса двигателя

- **Evidence:** android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt:65–70 сохраняет только FlutterEngine; android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt:78–80 создаёт другую Activity с cached engine. Нативная регистрация OnBackInvokedCallback принадлежит Activity, а новый запуск не получает savedInstanceState прежнего хоста. Это подтверждают исходники установленного Flutter 3.47.1: [FlutterActivity](https://github.com/flutter/flutter/blob/3.47.1/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterActivity.java#L730) и [обработка NavigationNotification](https://github.com/flutter/flutter/blob/3.47.1/packages/flutter/lib/src/widgets/app.dart#L1443). На API 36 с navigation_mode=2 сохранён экран «Подробности намерения», выполнен перенос LargeDisplayActivity→PhoneActivity сменой полного дисплея 600→390 dp; edge swipe через adb shell input swipe 1 800 350 800 400 закрыл Activity и показал QuickstepLauncher. Контрольный запуск той же сборки без переноса, тот же экран и тот же жест вернули «Главная» с активной PhoneActivity. KEYCODE_BACK после переноса в другом прогоне работал; дефект не распространяется этим выводом на все способы Back. lib/src/app/routing/app_router.dart:40 подтверждает достижимый вложенный маршрут IntentionDetailsRoute.
- **Evidence revisions:** ["8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea"]
- **Impact:** После складывания системный жест закрывает приложение вместо возврата по сохранённому стеку. Сам перенос двигателя сохраняет экран, но его нативная обработка навигации расходится с состоянием Flutter. Перестроение Navigator может послать повторное уведомление, однако синхронизация после подключения нового хоста не гарантирована; наблюдаемый контроль исключает общий дефект жеста до переноса.
- **Required outcome:** После переноса системный жест «Назад» должен обслуживать сохранённый стек Flutter и действующие ограничения закрытия маршрута так же, как до переноса. Регрессионная проверка должна наблюдать этот исход после подключения нового хоста. Другие версии API и направления переноса этим замечанием не объявляются неисправными.
- **Earliest source of truth:** implementation/tests
- **Affected artifacts:** ["android/app/src/main/kotlin/software/doable/doable/DisplayHostActivity.kt", "android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt"]

### F4 · Low — Отмена задачи устройств не согласована с обязательными ссылками на неё

- **Evidence:** Коммит 8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea удаляет 2.15 по запросу владельца, передавая физические проверки ему. В head openspec/changes/redesign-daily-choice-calendar/tasks.md:262 по-прежнему объявляет проверку обязательной в 2.15; openspec/changes/redesign-daily-choice-calendar/design.md:199 также назначает её несуществующей задаче, openspec/changes/redesign-daily-choice-calendar/adr.md:15 относит подтверждение к 2.14–2.15. OpenSpec instructions apply показывает all_done и 23/23, хотя ссылка на владельца обязательного подтверждения больше не разрешается.
- **Evidence revisions:** ["a7ac989243d860ce978740e76dd2faa2f67918c1", "8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea"]
- **Impact:** Следующий этап не может проследить, где сохраняется результат проверки оконной политики и что подтверждает готовность фазы. Отмена задачи сама по себе разрешена владельцем и не является принятием дефекта F2.
- **Required outcome:** Согласовать ссылки и владение проверкой с отменой задачи и внешней проверкой владельца, сохранив записанную историю и завершённость существующих задач. Не выдавать отсутствие задачи или all_done за подтверждение поведения устройств.
- **Earliest source of truth:** task/verification
- **Affected artifacts:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md", "openspec/changes/redesign-daily-choice-calendar/design.md", "openspec/changes/redesign-daily-choice-calendar/adr.md"]

## Review coverage

Все 11 reviewable paths учтены: четыре — плановые доказательства, семь — точное подмножество поставки U1. Несопоставленных или посторонних путей нет. До аудита рабочее дерево было чистым, HEAD совпадал с reviewed head. Отчёт исключён из целевого diff и прочитан как текущее состояние после независимого прохода; прежних активных F/AR нет.

Каждый целевой коммит проверен отдельно и по совокупному diff:

Коммит 2797209ffe6a6805f7d23a2fa4e36408a5af65ea: уточнение нативного механизма в design, ADR-0031 и её индексе; плановые доказательства U1 и задачи 23 / 2.14.

Коммит b3836e0b2f136501b33d71d5a722f15a5691a464: все семь delivery/test paths, отметка выполнения 2.14; реализация и проверки U1.

Коммит 8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea: отмена 2.15 и передача физической проверки владельцу; проверка согласованности планирования U1. Коммит вне taskCommitRange включён по содержанию.

Задача ID 23, номер 2.14, «Нативный запуск Android ограничивает ориентацию и окно только на телефонных дисплеях», сопоставлена с U1. Её сохранённый диапазон a7ac989243d860ce978740e76dd2faa2f67918c1..b3836e0b2f136501b33d71d5a722f15a5691a464 включает плановое уточнение и реализацию; последний целевой коммит также рассмотрен. ID, номер, описание, порядок и завершённость задачи не изменены.

Проверки выполнялись в /home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn на reviewed head 8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea, без изменений исходников:

mise exec --no-deps -- flutter test test/android — exit 0, 6 тестов.

JAVA_HOME=/home/seniorkonung/.local/share/mise/installs/java/temurin-25.0.3+9.0.LTS android/gradlew -p android :app:testDebugUnitTest --console=plain — exit 0, BUILD SUCCESSFUL; JUnit XML: 32 теста, 0 failures/errors/skipped на API 24, 30, 35, 36.

mise exec --no-deps -- flutter build apk --debug --no-pub — exit 0, собран build/app/outputs/flutter-apk/app-debug.apk.

mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json — exit 0, valid=true, issues=[].

git --literal-pathspecs diff --check a7ac989243d860ce978740e76dd2faa2f67918c1 8cafb70fd4eefcd521eed89c7dd2ab16a8a4d8ea — exit 0.

AVD doable-foundation-2-3 запущен отдельно с -read-only -no-window -no-audio -no-snapshot, API 36, minSdk=24, targetSdk=36. Установка свежего debug APK успешна. На холодном телефонном запуске 390×844 dp наблюдалась PhoneActivity в fullscreen/portrait, в Recents команда Split отсутствовала. На большом дисплее 600×900 dp наблюдалась LargeDisplayActivity; системный поворот дал landscape 900×600 dp, обычная команда Split работала. Сужение полного дисплея после Split воспроизвело F2. Отдельный перенос Large→Phone на вложенном маршруте с жестовой системной навигацией и контроль без переноса подтвердили F3; исходники Flutter прочитаны из установленной версии 3.47.1, соответствующей конфигурации head. Это моделирование изменения логического дисплея эмулятором; физическое складывание, API 24–35 и отказ подготовки хранилища здесь не проверены. Эти ограничения не означают принятие риска или готовность всей фазы 2. Полнота покрытия относится к данному ограниченному ревью; физическая матрица и визуальная приёмка каталогов прежних задач не объявляются выполненными. Полный mise run check здесь не запускался: этап не завершает фазу плана, а затронутые модули проверены приведёнными командами.

node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/redesign-daily-choice-calendar/implementation-review.md — exit 0, формат v1 валиден, 3 findings и 0 accepted risks.

Код, тесты и планирование в этом аудите не исправлялись: навык разрешает только запись отчёта. Замечания остаются для последующих этапов разрешения; новые задачи и другие workflow не создавались. Физические проверки владельца не подменены повторным добавлением отменённой задачи. Отчёт не подтверждает завершение фазы 3 или всего изменения.
