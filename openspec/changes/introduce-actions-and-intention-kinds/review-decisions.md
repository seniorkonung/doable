# Решения по findings OpenSpec review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F2 · Medium — Текстовые проверки удаления готовности в 3.14 и 3.15 дают неверный вердикт

- **Решение:** Устранить
- **Как устранить:** Устранить правкой только tasks.md через openspec-update-change, без новых задач. Проверка 3.14: английский grep дополнить ключами строк, чтобы `grep -rnE 'Readiness|readiness|is_action_ready|isActionReady|actionReady|notReady|readyOnly|detailsType|editorReadiness' lib test benchmark drift_schemas` ничего не находил; русскую проверку заменить шаблоном `готовност|готов[а-я]*|неготов` по lib test benchmark с исключением явного списка файлов, где слово имеет другое значение (составить по текущей выдаче: например, lib/src/design_system/components/tabs.dart, order_button.dart, catalog_row.dart, count_tiles.dart, calendar_header.dart, lib/src/app/app_runtime.dart, lib/src/app/navigation/app_shell_page.dart, intention_actions_view_model(.g).dart, relation_list_reconciliation.dart и соответствующие тесты), и после исключения выдача пуста; список исключений записать в задачу. Файлы, где готовность к действию упоминается наряду с другим значением, в список не включать. Проверка 3.15: `grep -rlziE 'готовност[а-я]*[[:space:]]+к[[:space:]]+действию|action[[:space:]]+readiness' README.md docs/adr` перечисляет только ADR-0001, а `grep -zqiE` по README.md подтверждает, что вводная часть называет вид намерения (главное или вспомогательное). Поведение продукта не меняется. Затем openspec validate --strict.
