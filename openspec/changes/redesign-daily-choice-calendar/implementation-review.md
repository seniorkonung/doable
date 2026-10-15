# OpenSpec Implementation Review: redesign-daily-choice-calendar

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Проверены оба целевых коммита, задачи 27 / 2.18 и 28 / 2.19 и все четыре изменённых пути. Холодный запуск сохраняет выбранную системой половину Split screen большого дисплея; сценарий Android подтверждает фактическое размещение и сохранность переноса, сессии, повторного launcher и жестов «Назад». Все три прохода завершены. Активных замечаний и принятых остаточных рисков нет. Готовность всей фазы 2, физическая проверка владельца и фаза 3 этим результатом не подтверждаются.

## Review target

- **Baseline ref:** 3c6bf52057601d705a9d0997921d845686e1f7ae
- **Base commit:** 3c6bf52057601d705a9d0997921d845686e1f7ae
- **Reviewed head:** 56ecec7139ca894fb8690ea048e73ee1d55dcb19
- **Target commits:** ["48de84b3e271a0276868f06abe5133412ca0dc20", "56ecec7139ca894fb8690ea048e73ee1d55dcb19"]
- **Reviewable paths:** ["android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt", "openspec/changes/redesign-daily-choice-calendar/tasks.md", "tool/check_android_display_transfer.py"]
- **OpenSpec change:** redesign-daily-choice-calendar
- **OpenSpec schema:** intent-driven
- **Target scope:** User-requested bounded range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["openspec/changes/redesign-daily-choice-calendar/tasks.md"]

## Reviewed increment

### U1 · Холодный запуск большого хоста сохраняет системное размещение

- **Work items:** ["27 / 2.18"]
- **Requirements and scenarios:** ["app-appearance: Портретная ориентация на телефоне — системное управление окном больших дисплеев", "ADR-0031: граница телефонных ограничений", "design.md: решение 6 — холодный запуск без существующего хоста"]
- **Affected boundary:** Launcher Android, нативная точка входа и хост, связь запуска с исходной Activity/task, сохранённый FlutterEngine.
- **Implementation target:** ["android/app/src/main/kotlin/software/doable/doable/DisplayWindowPolicy.kt", "android/app/src/test/kotlin/software/doable/doable/DisplayWindowPolicyTest.kt"]
- **Applicable constraints and non-goals:** Android API 24+, targetSdk 36. Большой дисплей определяется короткой стороной полного дисплея от 600 dp, независимо от ширины окна. На нём размещением и ориентацией управляет система; телефон сохраняет полный портретный экран с нативного запуска. Холодный вход разграничен с переносом двигателя; повторный launcher, сессия и возврат сохраняются. Новые раскладки и изменения данных не входят в объём.
- **Excluded change scope:** Ранее выполненные задачи 1.1–2.17 рассматриваются только как контекст затронутых гарантий. Выбор года и месяца фазы 3 и физическая проверка владельца не входят в этот диапазон.

### U2 · Проверка Android наблюдает холодный вход в выбранную половину

- **Work items:** ["28 / 2.19"]
- **Requirements and scenarios:** ["design.md: решение 6 — холодный вход 2.19 и сохранность сценариев 2.16–2.17", "app-appearance: системное размещение большого дисплея и полный экран телефона", "app-navigation: сохранение состояния и действие «назад»", "intention-management: Сессия черновика создания намерения"]
- **Affected boundary:** Оператор локальной проверки, эмулятор API 36, системный launcher и Split screen, наблюдения Activity/task/окна и настройки эмулятора.
- **Implementation target:** ["tool/check_android_display_transfer.py"]
- **Applicable constraints and non-goals:** Обычный Split screen рядом с Settings на полном дисплее 600×900 dp, без принудительных обходных настроек. Непосредственно перед выбором второй стороны отсутствуют процесс и task приложения. Режим, границы окна и видимость соседа наблюдаются на Android. Сценарии переноса к 390×844 dp, сохранения сессии и системных жестов остаются действующими; изменённые настройки восстанавливаются при успехе и отказе. Проверка на эмуляторе не заменяет физическую проверку владельца.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Два свежих контекста с fork_turns=none: /root/decision_cold_launch для двух путей U1 и /root/decision_android_scenario для единственного пути U2. Каждый применил implementation-decision-review к точным Base/Head и полным назначенным файлам; оба вернули No substantive findings и Complete. Переданы нейтральное намерение, SHA, пути и ограничения этапа, без планирования, истории, прежнего отчёта или замечаний. Неизменные контекстные пути проверены до чтения; целевой диапазон не расширялся. |
| OpenSpec conformance | Complete | Прочитаны сохранённые proposal, три delta-spec, design, adr, plan, tasks, ADR-0031 и относящиеся к сохранению сессии и возврату канонические контракты. Оба диапазона задач и все четыре пути сопоставлены с U1/U2. Проверены критерии 2.18–2.19, необходимые результаты и отсутствие избыточного поведения. На reviewed head прошли 44 свежих нативных теста, 6 проверок test/android, сборка APK, полный сценарий Android и строгая OpenSpec validation. |
| Code quality | Complete | По code-review-and-quality проверено всё подмножество поставки из трёх путей: корректность, читаемость, архитектура, безопасность и производительность. Рассмотрены источник запуска Activity, отдельные affinity, неизменные launcher/AppTask и перенос двигателя, нативные тесты, предусловия и реальные наблюдения сценария, восстановление настроек. Новых зависимостей, разрешений, внешних production-интеграций и миграций нет. diff --check успешен. |

## Findings

No unresolved findings remain in the implementation review.

## Review coverage

Все четыре reviewable paths учтены: tasks.md служит плановым доказательством; два нативных файла полностью покрыты U1, сценарий Python — U2. Это точное подмножество поставки из трёх путей. Несопоставленных или посторонних изменений нет. До проверки дерево было чистым, HEAD совпадал с reviewed head; исходники и планирование читались по полным сохранённым SHA. Прежний отчёт прочитан после независимых проходов: активных F/AR для переноса нет, согласованным исправлением холодного запуска уже владели задачи 2.18–2.19.

Каждая задача и каждый целевой коммит рассмотрены отдельно:

Задача ID 27, номер 2.18, «Холодный запуск на большом дисплее сохраняет выбранное системой размещение окна»: диапазон 3c6bf52057601d705a9d0997921d845686e1f7ae..48de84b3e271a0276868f06abe5133412ca0dc20, U1. Коммит 48de84b3e271a0276868f06abe5133412ca0dc20 изменяет политику и нативные тесты; отмечает только 2.18. Ветка холодного большого хоста сохраняет токен Activity; телефонный запуск, перенос и AppTask остаются отдельными путями.

Задача ID 28, номер 2.19, «Сценарий Android подтверждает выбранную половину Split screen при холодном запуске»: диапазон 48de84b3e271a0276868f06abe5133412ca0dc20..56ecec7139ca894fb8690ea048e73ee1d55dcb19, U2. Коммит 56ecec7139ca894fb8690ea048e73ee1d55dcb19 расширяет сценарий и отмечает только 2.19. Холодный вход проверяет отсутствие процесса/task перед выбором, нижнюю половину приложения, верхнюю половину Settings, видимое содержимое и фактические границы обоих окон; затем выполняются прежние сценарии.

На reviewed head DisplayWindowPolicy.kt:111–122 разделяет три входа: существующая AppTask, холодный большой хост через Activity и независимый запуск телефона/переноса. DisplayWindowPolicyTest.kt:58–93 проверяет источник запуска на границе Instrumentation, а проверка переноса на строках 118–163 защищает противоположный путь. Токен вызова подтверждён [исходниками Activity Android API 24](https://android.googlesource.com/platform/frameworks/base/+/android-7.0.0_r1/core/java/android/app/Activity.java#4224); независимый проход также проследил выбор корневой task в AOSP API 36. Нативный тест сам по себе не доказывает фактическое размещение окна: это подтверждено отдельным runtime-сценарием. Эти проверки защищают разные уровни одной регрессии.

В tool/check_android_display_transfer.py:173–246 проверены холодное предусловие и наблюдаемый результат, на строке 493 — выполнение холодного входа перед прежними проверками. Обобщение window_frame сохраняет наблюдение телефонного окна; SHA-256 связывает результат с конкретным APK. Новых сценариев или обработчиков для недостижимых состояний не обнаружено.

Проверки выполнены в /home/seniorkonung/.paseo/worktrees/1id27gtb/lawful-unicorn на 56ecec7139ca894fb8690ea048e73ee1d55dcb19 без изменения исходников и тестов:

Команда `JAVA_HOME=/home/seniorkonung/.local/share/mise/installs/java/temurin-25.0.3+9.0.LTS mise exec --no-deps -- android/gradlew -p android :app:testDebugUnitTest --rerun-tasks --console=plain` — exit 0, BUILD SUCCESSFUL, все 68 Gradle tasks выполнены. Свежий JUnit XML: 44 теста на API 24, 30, 35, 36; failures/errors/skipped = 0.

Команда `mise exec --no-deps -- flutter test test/android` — exit 0, 6 тестов.

Команда `JAVA_HOME=/home/seniorkonung/.local/share/mise/installs/java/temurin-25.0.3+9.0.LTS mise exec --no-deps -- flutter build apk --debug --no-pub` — exit 0. SHA-256 APK: a49e8e5b549a9465fb2d904a3b172c1217d07deb685cea2b8dac0f7ded0da081.

Команда `python3 tool/check_android_display_transfer.py --serial emulator-5554` — exit 0. AVD doable-foundation-2-3, API 36, navigation_mode=2, fingerprint Android/sdk_phone64_x86_64/emu64x:16/BE2A.250530.026.D1/13818094:userdebug/test-keys. Наблюдения: /tmp/doable-display-transfer-kbxl1g77.

Команда `mise exec --no-deps -- openspec validate redesign-daily-choice-calendar --strict --json` — exit 0, valid=true, issues=[].

Синтаксис сценария проверен через Python ast.parse; `--help` работает. `git --literal-pathspecs diff --check 3c6bf52057601d705a9d0997921d845686e1f7ae 56ecec7139ca894fb8690ea048e73ee1d55dcb19` — exit 0.

Перед холодным выбором runtime подтвердил process=false и task=false. LargeDisplayActivity осталась в нижней половине с bounds/frame [0,455,600,900], Settings — в верхней с bounds/frame [0,0,600,445]; обе Activity видимы в multi-window на полном дисплее 600×900 dp. После отдельной подготовки каталога и Split screen перенос дал активную PhoneActivity в fullscreen, multi-window=false, portrait, с bounds/display/frame [0,0,390,844]. PID 2690, выбранное 14 октября 2026, раскрытый ноябрь, фильтр «Не выполненные», количество 1 и строка дневного выбора сохранились. Повторный launcher сохранил PID, каталог и одну карточку. Контроль без переноса и первый жест после переноса с подробностей вернули Главную; жест в изменённом черновике при скрытой клавиатуре запросил подтверждение, продолжение сохранило текст; жест с Главной показал launcher.

Сценарий подтвердил восстановление size=reset, density=160, accelerometer_rotation=1, user_rotation=0. Временно включённый координатором gesture overlay отключён, исходный navigation_mode=0 и отсутствие включённых navbar overlays подтверждены отдельно.

Сообщение коммита 56ecec7139ca894fb8690ea048e73ee1d55dcb19 записывает отрицательный контроль с политикой Base, успешный сценарий после 2.18, 44 нативных, 6 Android и 2669 полных проектных тестов. Это свидетельство автора, отдельно от свежих проверок выше: сборка Base и отрицательный контроль в этом ревью не повторялись. Полный mise run check также не повторяется: этап завершает ограниченное ревью, а не фазу плана; изменённые модули и непосредственно затронутые потребители проверены. Runtime API 24–35, физическое складывание, подготовка хранилища с отказом и ручная сверка обоих каталогов в обеих темах этим запуском не подтверждаются. Физическая проверка владельца и остальные условия Ready to advance фазы 2 остаются действующими; это не принятие остаточного риска.

Процессное отклонение: первый запуск discovery helper использовал его default executable OpenSpec. Discovery повторён с временной обёрткой, исполняющей `mise exec --no-deps -- openspec`; SHA и пути совпали. Последующие вызовы OpenSpec выполнялись только через mise. Инструменты не устанавливались и не обновлялись.

Коррекции кода, тестов и плановых артефактов на этом этапе не требовались. Задачи, их ID, номера, описания, порядок и завершённые отметки сохранены; новых задач нет. Согласованный результат 2.18–2.19 подтверждён текущими проверками. Замечаний для последующих этапов разрешения findings и принятых рисков нет. Формат отчёта проверен командой `node .agents/skills/openspec-review-implementation/scripts/validate-review.mjs openspec/changes/redesign-daily-choice-calendar/implementation-review.md`: valid review format v1, 0 findings, 0 accepted risks. В коммит этапа входит только этот отчёт; реализация фазы 3 и подтверждение владельцем остаются за пределами этапа.
