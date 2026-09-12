# OpenSpec Implementation Review: manage-intentions

## Assessment

**Format version:** 1
**Result:** No unresolved findings
**Coverage status:** Complete
**Summary:** Активных findings нет. Принятые риски AR1, AR2 и AR3 остаются
  применимыми в своих границах.

## Review target

- **Baseline ref:** ace53095f984d1cb2b316a4849290c6a5ac374f2 (предыдущий reviewed head)
- **Base commit:** ace53095f984d1cb2b316a4849290c6a5ac374f2
- **Reviewed head:** 870f208d11bdb220eae05da3a59df4b37a92efe2
- **Target commits:** ["69ddb187de3e7e8290cb2127fb273f8ff1884f0b", "432c1867cf987568610c1ed17b709844681e32ad", "15727b0ee179d52ce10e4d41b7e0c117488143b6", "de9b7768e6c47f0907e381391efa45dd485df445", "a5915783f2f80e50005f957b6d1a882889342879", "3a1fa82cff1a844d65b8b65b464f2e640c9575f9", "c5d51dc4200599dc1c4b91c632af5e67893c87f4", "f65b6662411c263377a0662d2837ba7e6f3bfacf", "172f9424c2cbf65a57fc14b2544ea9121b2cad35", "56fae7c98b981637d72792082d9d6895577903b9", "ead00d3e6b29882c0bfd34c97f59d36cb7ab631b", "98461951372525422e333885acd23962201f0b1d", "bed056a4cb11b2da3a35e7254117947499542170", "b633c9c73aae11cc68562fcea37f3e669f9f3fac", "c1747937141c100b441bf970db4a3a2892dafa23", "7d8c016dd9e38130490d44d0f5d50489ff9f201b", "f4ca3ea84907da56312e79c574377c754a7cc5e3", "e08b83459e83e188e7e01fb4529215f8475838db", "e2460e5f1c612598d05a3cf411b3db5d0bf294a5", "d388d7b7e6f18f3c8c578550949933562407216a", "2cca96f7ca2ac2f7b8feca22f7b955dc7559d5d3", "a9774616a01ddf6c4fd27453b6ad0b677ede8964", "e575e29f2d56c96e0bfc99503b1748b9e0b4cece", "9021140bb7ae6ff5c6bad239773c04c1a2c3b611", "7274da374164deb91f922a0e3cb769c7e622dcf2", "00cec02ee409153976d095bed405331fcffc07ae", "5b66b1a9cc10a7bf9bc5fe0c4ce225ea46fce7b4", "8a011c763f6b76f984e97572a05c59b167f83855", "770a21c3a1e5437f79a92ec39abb6e25c8f4fff8", "f88cc40e4ee5eae7121d1ed24dc2c79933000f26", "ec8506d04b348acd8288098b20cb7fecec1641e2", "b168d37a5772c466579bf68d1adec3543ecf263e", "74fe1a163da189c02a53808cad47f06a5f927961", "a667683e96a02449bbe09d825c59c638aa242d51", "4bd6ce650d06793a8059ab58f8ab9a1335899315", "bdb5579a3d6df3b0c89a7290423015ea7398e654", "ecdbfab8682c9517160affe9c54e2257ded64d22", "f84798c79bf617cb72f7b65a332db0dd34e02e62", "faa197a8dee567fd6fb175bcebfcb3c7e4ef0043", "0ba056e2bd637edba8ca9f817bf4667ca940faca", "da67f3b3e040ea05789cfef116aac3cf8970afaa", "3422532403007bb0087737aacd1e958121345b2b", "f4b6800f640f24654ee36db19d73bfd25d113792", "5789df647fc925d164a7c21ab40aaf0876fe4f56", "cf7358cdbc05edb25edca4861cc6f2191f3761cd", "f5323025d6aa79f62d099668bd3e5210f5177d6d", "c605b77b28e0cfbb716d021f6ea397a161152c49", "30c44cd60603e22876799c3aa9c9f8e8314cfe61", "bffb66deb7655f36e4d548bf1266b54f18bfced6", "e791b703a19573ada58b9c17823ce69e8fae6c04", "58235ac6bada5061400610e32939c5e0637156cf", "28537d4ea08b9718d454e59e55590bada5a7f84b", "c12de188f4447bb1ee1c2fb7f6f4c48dd0352afa", "efada633c648389a1af79ae30092b7f4c4ef2d4b", "990d6a85f865ed795abc1e4b13fc8e7bd5428c42", "38757b5ef72bcd37e2520aac9cdb7d665ad74739", "67b504876a3dc2a1605c76d967f735a4b9bba68b", "8b5310a331dac65d900fde7f551e2fd64b1e8566", "f93b2749a46cdd5e9f16cd7d66f80d429e326497", "85810794d981ffe0ebf720fad8268d71a8c13842", "f7b30728e8f2e527ff7e5cbe5e58b4ed2dc882f4", "5ec8cfd3afc8b915b1c084156bc7d395075057da", "19acb32d613bfb4f401dad590ba581ea78480218", "dbabd667a95f47ab050d64fb20024ec1cda613a9", "01188c9eee8b3057f240148363de5001695b9afe", "b1fd26d370546b07b8ccb4df58fef02d7f752846", "f17e96902a1a2c03b6c1b535e92c10c7a621a2ac", "d48444ff7d17b8b5c4ea6ab144b385c8f1b7eee3", "b8f2acfcde969862d4669bb8eaf6117bf1d41ddd", "6eac4f6b4f4def107c8e2e7f45fb1ac2ee8506da", "870f208d11bdb220eae05da3a59df4b37a92efe2"]
- **Reviewable paths:** [".github/workflows/ci.yml", "README.md", "apm.lock.yaml", "apm.yml", "docs/adr/0005-use-bounded-catalog-snapshots.md", "docs/adr/README.md", "lefthook.yaml", "lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/main.dart", "lib/src/app/app_runtime.dart", "lib/src/app/bootstrap/app_bootstrap_shell.dart", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/app/routing/app_router_provider.dart", "lib/src/app/routing/app_router_provider.g.dart", "lib/src/data/local/bootstrap/local_data_bootstrap.dart", "lib/src/intention/application/intention_repository.dart", "lib/src/intention/application/intention_result.dart", "lib/src/intention/data/drift_intention_repository.dart", "lib/src/intention/presentation/catalog/catalog_paging_policy.dart", "lib/src/intention/presentation/catalog/catalog_paging_policy.g.dart", "lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "lib/src/intention/presentation/details/intention_details_view_model.g.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "lib/src/intention/presentation/operation/intention_command_coordinator.dart", "lib/src/intention/presentation/operation/intention_command_coordinator.g.dart", "lib/src/intention/presentation/operation/intention_repository_provider.dart", "lib/src/intention/presentation/operation/intention_repository_provider.g.dart", "lib/src/intention/presentation/operation/operation_state.dart", "lib/src/shared/presentation/exclusive_operation.dart", "mise.toml", "openspec/changes/manage-intentions/adr.md", "openspec/changes/manage-intentions/design.md", "openspec/changes/manage-intentions/plan.md", "openspec/changes/manage-intentions/review.md", "openspec/changes/manage-intentions/specs/intention-management/spec.md", "openspec/changes/manage-intentions/tasks.md", "test/app/bootstrap/app_bootstrap_shell_test.dart", "test/app/bootstrap/app_runtime_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/localization/locale_resolution_test.dart", "test/app/routing/app_router_test.dart", "test/data/local/app_database_schema_test.dart", "test/data/local/bootstrap/local_data_bootstrap_test.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/data/drift_intention_repository_command_test.dart", "test/intention/data/drift_intention_repository_watch_test.dart", "test/intention/data/file_backed_drift_intention_repository_test.dart", "test/intention/presentation/catalog/catalog_reconciliation_test_support.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_page_test.dart", "test/intention/presentation/catalog/intention_catalog_revision_protocol_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_view_model_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/intention/presentation/operation/operation_state_test.dart", "test/shared/presentation/exclusive_operation_test.dart", "tool/check_generated.sh", "tool/check_generated_test.sh"]
- **OpenSpec change:** manage-intentions
- **OpenSpec schema:** intent-driven
- **Target scope:** Complete pre-push range
- **Baseline freshness:** Local ref state; no fetch performed
- **Planning evidence paths:** ["docs/adr/0005-use-bounded-catalog-snapshots.md", "docs/adr/README.md", "openspec/changes/manage-intentions/adr.md", "openspec/changes/manage-intentions/design.md", "openspec/changes/manage-intentions/plan.md", "openspec/changes/manage-intentions/review.md", "openspec/changes/manage-intentions/specs/intention-management/spec.md", "openspec/changes/manage-intentions/tasks.md"]

## Reviewed increment

### U1 · Согласование repository revisions и lossless storage boundary

- **Work items:** ["6.25", "6.26", "7.19"]
- **Requirements and scenarios:** ["local-data-lifecycle: Целостность сохранённого пользовательского текста", "intention-management: Последовательное изменение одного намерения"]
- **Affected boundary:** Публичная `IntentionRepository` seam, SQLite-строки и command mutation snapshots.
- **Implementation target:** ["lib/src/data/local/bootstrap/local_data_bootstrap.dart", "lib/src/intention/application/intention_repository.dart", "lib/src/intention/application/intention_result.dart", "lib/src/intention/data/drift_intention_repository.dart", "test/data/local/app_database_schema_test.dart", "test/data/local/bootstrap/local_data_bootstrap_test.dart", "test/intention/application/intention_contract_test.dart", "test/intention/data/drift_intention_catalog_test.dart", "test/intention/data/drift_intention_repository_command_test.dart", "test/intention/data/drift_intention_repository_watch_test.dart", "test/intention/data/file_backed_drift_intention_repository_test.dart"]
- **Applicable constraints and non-goals:** Сохранённые значения валидируются до lossy mapping; revisions process-local; внешняя синхронизация и новый schema version не добавляются.

### U2 · Доступный presentation lifecycle поверх единого object graph

- **Work items:** ["7.1–7.18", "7.20"]
- **Requirements and scenarios:** ["intention-management: пользовательский lifecycle", "intention-management: независимость принятой операции от экрана", "intention-management: состояния каталога и подробного просмотра"]
- **Affected boundary:** Flutter composition, routing, локализация, View/ViewModel и process-local coordinator.
- **Implementation target:** ["lib/l10n/app_en.arb", "lib/l10n/app_localizations.dart", "lib/l10n/app_localizations_en.dart", "lib/l10n/app_localizations_ru.dart", "lib/l10n/app_ru.arb", "lib/main.dart", "lib/src/app/app_runtime.dart", "lib/src/app/bootstrap/app_bootstrap_shell.dart", "lib/src/app/routing/app_router.dart", "lib/src/app/routing/app_router.gr.dart", "lib/src/app/routing/app_router_provider.dart", "lib/src/app/routing/app_router_provider.g.dart", "lib/src/intention/presentation/catalog/catalog_paging_policy.dart", "lib/src/intention/presentation/catalog/catalog_paging_policy.g.dart", "lib/src/intention/presentation/catalog/intention_catalog_page.dart", "lib/src/intention/presentation/catalog/intention_catalog_state.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.dart", "lib/src/intention/presentation/catalog/intention_catalog_view_model.g.dart", "lib/src/intention/presentation/details/intention_details_page.dart", "lib/src/intention/presentation/details/intention_details_state.dart", "lib/src/intention/presentation/details/intention_details_view_model.dart", "lib/src/intention/presentation/details/intention_details_view_model.g.dart", "lib/src/intention/presentation/editor/intention_editor_page.dart", "lib/src/intention/presentation/editor/intention_editor_state.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.dart", "lib/src/intention/presentation/editor/intention_editor_view_model.g.dart", "lib/src/intention/presentation/operation/intention_command_coordinator.dart", "lib/src/intention/presentation/operation/intention_command_coordinator.g.dart", "lib/src/intention/presentation/operation/intention_repository_provider.dart", "lib/src/intention/presentation/operation/intention_repository_provider.g.dart", "lib/src/intention/presentation/operation/operation_state.dart", "lib/src/shared/presentation/exclusive_operation.dart", "test/app/bootstrap/app_bootstrap_shell_test.dart", "test/app/bootstrap/app_runtime_test.dart", "test/app/intention_app_lifecycle_test.dart", "test/app/localization/locale_resolution_test.dart", "test/app/routing/app_router_test.dart", "test/intention/presentation/catalog/catalog_reconciliation_test_support.dart", "test/intention/presentation/catalog/catalog_test_support.dart", "test/intention/presentation/catalog/intention_catalog_mutation_reconciliation_test.dart", "test/intention/presentation/catalog/intention_catalog_page_test.dart", "test/intention/presentation/catalog/intention_catalog_revision_protocol_test.dart", "test/intention/presentation/catalog/intention_catalog_view_model_test.dart", "test/intention/presentation/details/details_test_support.dart", "test/intention/presentation/details/intention_details_delete_test.dart", "test/intention/presentation/details/intention_details_page_test.dart", "test/intention/presentation/details/intention_details_view_model_test.dart", "test/intention/presentation/editor/intention_editor_page_test.dart", "test/intention/presentation/editor/intention_editor_view_model_test.dart", "test/intention/presentation/operation/intention_command_coordinator_test.dart", "test/intention/presentation/operation/operation_state_test.dart", "test/shared/presentation/exclusive_operation_test.dart"]
- **Applicable constraints and non-goals:** Только подтверждённое состояние; один presentation owner; process-local managed shutdown не обещает ожидание при внезапном завершении Android-процесса; ручная TalkBack qualification не входит в change.

### U3 · Воспроизводимый обязательный PR gate и Android privacy evidence

- **Work items:** ["8.1–8.5"]
- **Requirements and scenarios:** ["Phase 8: воспроизводимая генерация", "Phase 8: обязательный полный CI gate", "local-data-lifecycle: локальная граница хранения и backup"]
- **Affected boundary:** Development tooling, GitHub Actions и packaged release APK manifest.
- **Implementation target:** [".github/workflows/ci.yml", "README.md", "apm.lock.yaml", "apm.yml", "lefthook.yaml", "mise.toml", "tool/check_generated.sh", "tool/check_generated_test.sh"]
- **Applicable constraints and non-goals:** Gate использует чистый Linux checkout и pinned toolchain; production signing, распространение, device/emulator jobs и Android benchmark не добавляются.

## Pass coverage

| Pass | Status | Evidence or limitation |
|---|---|---|
| Independent decision review | Complete | Три свежих изолированных reviewer покрыли точные U1–U3; `lib/main.dart` и ownership caller проверены в U2, что закрывает локальное ограничение U1-reviewer. |
| OpenSpec conformance | Complete | Оба specs, design, ADR-0002–ADR-0008, plan и tasks сопоставлены с кодом; `openspec validate manage-intentions --type change --strict --no-interactive` успешен на recorded head. |
| Code quality | Complete | Tests изучены до реализации; correctness, readability, architecture, security и performance проверены по U1–U3. Dart MCP analysis без ошибок, `mise run codegen-check` воспроизводим, `mise run check` завершил 331 тест, а `git diff --check` чист. |

## Findings

No unresolved findings remain in the implementation review.

## Accepted risks

### AR1 · Показания системных часов могут не отражать фактическую хронологию операций

- **Evidence:** На ранее проверенном head `faf205fbf1c4429cefe695cba06a7c938210ef83` и текущем head `870f208d11bdb220eae05da3a59df4b37a92efe2` операции сохраняют wall-clock UTC, а каталог использует timestamp и `IntentionId` как tie-breaker без causal clock.
- **Evidence revisions:** ["870f208d11bdb220eae05da3a59df4b37a92efe2"]
- **Potential impact:** Быстрые операции или перевод часов могут дать одинаковые либо убывающие timestamps, и порядок каталога иногда не совпадёт с фактической последовательностью действий.
- **Acceptance rationale:** Отдельная revision/logical-clock модель или синтетическое продвижение времени несоразмерны вспомогательной сортировке и исказили бы наблюдаемое wall-clock значение.
- **Scope and assumptions:** Timestamps не используются как revision, causal order, аудит или разрешение конфликтов; неизменность `createdAt` и атомарность записи сохраняются.
- **Reopen when:** Timestamps получают хронологически значимое поведение, появляется синхронизация/разрешение конфликтов либо наблюдается существенный ущерб от перестановок.
- **Acceptance authority:** Явное решение пользователя от 2026-09-03.
- **Originating finding:** F1
- **Acceptance lifetime:** Durable
- **Decision record:** ADR-0006, `design.md` и `specs/intention-management/spec.md`

### AR2 · Android process restart и production wiring не проверены на device/emulator

- **Evidence:** File-backed и app-runtime tests закрывают и повторно открывают SQLite object graph, CI собирает release APK и проверяет packaged manifest, но `design.md` и task 8.6 прямо исключают device/emulator integration test как доказательство Android process relaunch.
- **Evidence revisions:** ["870f208d11bdb220eae05da3a59df4b37a92efe2"]
- **Potential impact:** Ошибка только в Android plugin/host wiring может проявиться при production bootstrap или повторном запуске, несмотря на успешные platform-neutral и file-backed tests.
- **Acceptance rationale:** Для первой интеграции человек решил не добавлять device/E2E infrastructure; существующее evidence доказывает storage lifecycle, composition и release packaging по отдельности без заявления о runtime qualification.
- **Scope and assumptions:** Первая локальная Android capability внутри одной установки; отсутствие device evidence не считается доказательством restart, а публикация и production release qualification остаются вне change.
- **Reopen when:** Наблюдается Android bootstrap/relaunch failure, меняется host wiring или capability готовится к publication/device qualification.
- **Acceptance authority:** Явное решение пользователя не добавлять интеграционные тесты, закреплённое в `tasks.md` 8.6 и `design.md` на reviewed head.
- **Originating finding:** F11
- **Acceptance lifetime:** Change-scoped

### AR3 · Linux budget короткого фильтра не доказывает Android latency

- **Evidence:** Large file-backed suite на 50 000 строк проверяет p95 не выше 100 мс в Linux, а `design.md` и tasks 8.2/8.6 прямо запрещают считать это Android performance measurement; device benchmark отсутствует.
- **Evidence revisions:** ["870f208d11bdb220eae05da3a59df4b37a92efe2"]
- **Potential impact:** На слабом Android-устройстве запрос одной-двух кодовых точек через scan и точный `COUNT` может задерживать актуальный результат после debounce.
- **Acceptance rationale:** Человек решил не добавлять Android performance/integration infrastructure; bounded paging, debounce и Linux regression budget ограничивают риск без ложного Android latency claim.
- **Scope and assumptions:** До 50 000 локальных намерений, текущие query/schema/search strategy и отсутствие обещанного Android latency SLO.
- **Reopen when:** Появляется наблюдаемая задержка, меняется типичный объём или search strategy либо вводится Android latency/SLO или publication criterion.
- **Acceptance authority:** Явное решение пользователя не добавлять интеграционные тесты, закреплённое в `tasks.md` 8.6 и `design.md` на reviewed head.
- **Originating finding:** F12
- **Acceptance lifetime:** Change-scoped

## Review coverage

Предыдущий implementation review покрывал диапазон `d1ec7266a8bab934c8308740943b40323cbaeb7f`–`ace53095f984d1cb2b316a4849290c6a5ac374f2`: schema snapshot/generated artifacts, NUL-защиту, bounded catalog materialization, file-backed text integrity и AR1. Текущий обзор от его head повторно проверил изменившиеся repository/storage paths и дополнительно полностью покрыл ранее не проверенные composition/presentation и CI/tooling paths.

На recorded head успешно выполнены Dart MCP analysis, `mise run codegen-check` с нулём generated outputs, `mise run check` с format, analyze и 331 тестом, `bash tool/check_generated_test.sh`, строгая OpenSpec-валидация и `git diff --check`. GitHub PR #2 имеет успешный `Full checks`; его head `5985ada3b8c2649aeebd6af861d120d8a19dd583` имеет то же tree `fdcc9f6bee5f8c089d13146ba8dce8970dbb4a9d`, что reviewed head. Legacy branch protection `main` требует exact context `Full checks`; проверка точного финального commit остаётся отдельной задачей 8.10.

Автоматизированные widget tests доказывают semantics, guideline, локализацию и
text scale, но не фактическую работу TalkBack. Release APK и packaged manifest
доказывают сборку и статическую Android privacy boundary, но не Android process
restart. Linux large-fixture budget не является Android latency measurement.
