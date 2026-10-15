# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Полностью рассмотрены три целевых коммита, задача 23 / 2.14 и все 11 изменённых путей. Неурегулированных замечаний нет: исправления полноэкранного переноса, сохранения сессии и системного жеста «Назад» закреплены в решении 6 дизайна и незавершённых задачах 2.15–2.17. По явному решению пользователя физическая проверка остаётся за владельцем продукта вне списка задач; её подтверждение на итоговой сборке требуется для готовности фазы 2. Дизайн, обзор ADR и пояснение к исторической ссылке в задачах согласованы с этим владением. Исправление кода и проверка результата ещё предстоят; это передача в план реализации. Принятых остаточных рисков нет. Результат No unresolved findings не подтверждает исправность реализации или завершение фазы.

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

No unresolved findings remain in the implementation review.

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

AVD doable-foundation-2-3 запущен отдельно с -read-only -no-window -no-audio -no-snapshot, API 36, minSdk=24, targetSdk=36. Установка свежего debug APK успешна. На холодном телефонном запуске 390×844 dp наблюдалась PhoneActivity в fullscreen/portrait, в Recents команда Split отсутствовала. На большом дисплее 600×900 dp наблюдалась LargeDisplayActivity; системный поворот дал landscape 900×600 dp, обычная команда Split работала. Сужение полного дисплея после Split подтвердило сохранение многооконного размещения при смене категории. Отдельный перенос Large→Phone на вложенном маршруте с жестовой системной навигацией и контроль без переноса подтвердили F3; исходники Flutter прочитаны из установленной версии 3.47.1, соответствующей конфигурации head. Это моделирование изменения логического дисплея эмулятором; физическое складывание, API 24–35 и отказ подготовки хранилища здесь не проверены. Эти ограничения не означают принятие риска или готовность всей фазы 2. Полнота покрытия относится к данному ограниченному ревью; физическая матрица и визуальная приёмка каталогов прежних задач не объявляются выполненными. Полный mise run check здесь не запускался: этап не завершает фазу плана, а затронутые модули проверены приведёнными командами.

Проверки текущего согласования выполнялись на рабочих артефактах изменения, отдельно от приведённых выше доказательств reviewed head:

mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json — exit 0, valid=true, issues=[].

node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/redesign-daily-choice-calendar/implementation-review.md — exit 0, формат v1 валиден, 0 findings и 0 accepted risks.

git --literal-pathspecs diff --check -- openspec/changes/redesign-daily-choice-calendar — exit 0. Побайтовое сравнение tasks.md с исходным HEAD после добавленного пояснения подтвердило сохранность всех 26 существующих задач, их порядка, текста и отметок; новых задач нет.

Код и тесты не менялись. Планирование владеет исправлением оконного переноса: решение 6 в design.md задаёт отдельные task хостов и сохранение сессии, задача 2.15 реализует этот механизм, а 2.16 закрепляет наблюдение фактического окна на Android. Согласование обработки системного жеста «Назад» с сохранённой навигацией и её PopScope также принадлежит решению 6; незавершённая задача 2.17 реализует передачу актуального состояния новому хосту и проверяет фактический жест после переноса на API 36, подтверждение закрытия изменённого черновика и обычный выход с Главной. По явному решению пользователя физическую проверку выполняет владелец продукта вне списка задач; решение 6 задаёт состав сообщаемого в сессии подтверждения и его необходимость для готовности фазы 2. Пояснение в tasks.md отличает историческую ссылку завершённой 2.14 от нынешних задач 2.15–2.17; adr.md ссылается на актуальное владение реализацией и проверкой. Спецификации, plan.md и ADR-0031 уже задают требуемый результат и не менялись. Реализация не переаудировалась, результат её исправления и выполнение физической проверки не заявлены. Отчёт не подтверждает завершение фазы 2, фазы 3 или всего изменения.
