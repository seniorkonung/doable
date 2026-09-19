## Phase 1: CI toolchain ограничен setup-контрактом каждого job

- [x] 1.1 Зафиксировать regression-тестом границу между setup-шагом и рабочими командами CI
  - **Acceptance criteria:**
    - Тест требует отключённый workflow-level auto-install.
    - Тест отклоняет проектные `mise run` без `--skip-tools` и OpenSpec-вызов через `mise exec`.
    - На исходном workflow тест воспроизводит нарушение контракта.
  - **Verification:**
    - Выполнить `bash test/tool/check_ci_scope_test.sh` до изменения workflow и подтвердить ожидаемый отказ новых утверждений.
  - **Dependencies:** None
  - **Files likely touched:** `test/tool/check_ci_scope_test.sh`
  - **Estimated scope:** XS

- [x] 1.2 Ограничить каждый CI job явно установленным и независимо кэшируемым toolchain
  - **Acceptance criteria:**
    - Workflow запрещает поздний auto-install, а project job запускает существующие задачи с `--skip-tools`.
    - OpenSpec job вызывает экспортированный executable напрямую после установки только Node.js и OpenSpec.
    - Все mise setup-шаги явно сохраняют стандартное кэширование и прежние `install_args`; Android-команды и версии инструментов не меняются.
  - **Verification:**
    - Выполнить `bash test/tool/check_ci_scope_test.sh` и подтвердить успех regression-теста.
    - Проверить изолированным запуском mise с пустым data-каталогом, что `--skip-tools` не устанавливает инструменты.
  - **Dependencies:** 1.1
  - **Files likely touched:** `.github/workflows/ci.yml`
  - **Estimated scope:** S (1 файл)

- [x] 1.3 Подтвердить готовность CI-контракта к pull-request проверке
  - **Acceptance criteria:**
    - Focused CI contract test, строгая OpenSpec-валидация и полный проектный gate успешны.
    - Изменение прошло проверку корректности, читаемости, архитектуры, безопасности и производительности.
    - Рабочая копия не содержит непредусмотренных изменений; ожидаемое отсутствие поздних установок сформулировано для проверки в pull-request логах.
  - **Verification:**
    - Выполнить `bash test/tool/check_ci_scope_test.sh`.
    - Выполнить `openspec validate prevent-ci-toolchain-overinstall --strict --no-interactive`.
    - Выполнить `mise run check` и `git diff --check`.
  - **Dependencies:** 1.1, 1.2
  - **Files likely touched:** None (verification only)
  - **Estimated scope:** XS
