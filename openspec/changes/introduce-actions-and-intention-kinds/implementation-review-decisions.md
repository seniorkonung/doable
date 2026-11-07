# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F3 · Low — Скрипт проверки на устройстве ищет удалённый пункт «Дневные выборы»

- **Решение:** Нужно новое решение
- **Препятствие:** Решение требует, чтобы 1.39 (F3+F6) шла последней: по решению F4 её проверка допускает ключ удалённого режима, если тест 1.37 останется. F3 обрабатывается первой, а задачи только дописываются в конец, поэтому 1.39 встанет перед 1.34–1.38 и выполнится первой. Нужно решить: обработать F3 после F4, F5, F7, F8, F10–F12 или изменить порядок и номер задачи.

## F4 · Low — Тесты быстрого создания и маршрутизатора после удаления режима дневного выбора не ловят свои регрессии и прячут удалённые имена

- **Решение:** Устранить
- **Как устранить:** Удалить тесты быстрого создания и маршрутизатора, которые не могут упасть при называемой регрессии, без изменения продуктового поведения: в test/app/quick_creation/quick_creation_mode_controller_test.dart тесты «поздние исходы отказ → отказ не меняют режим» и «повторный выбор текущего режима получает собственный исход» (при одном режиме они бессмысленны; тесты отката с двумя режимами появятся в Фазе 2 вместе со вторым режимом, plan.md не менять); отрицательную проверку ключа 'catalog-open-daily-choices' в test/app/routing/app_router_test.dart; повторы правила неизвестного ключа для прежнего ключа режима и значения daily-choice-from-intention/daily-choice-from-action в file_quick_creation_mode_store_test.dart, app_runtime_quick_creation_mode_test.dart, quick_creation_mode_controller_test.dart, quick_creation_mode_process_test.dart, quick_creation_runtime_restart_test.dart. Поведение сохранённого ключа удалённого режима доказывается не больше чем одним тестом, и только если он ловит регрессию, не покрытую общим тестом неизвестного ключа; ни один литерал не разрезан ради прохождения текстовой проверки — если такой тест остаётся, проверка задачи 1.39 явно допускает этот ключ. Выполнить вместе с F12 одной новой задачей Фазы 1 — 1.37, после 1.36 и всех существующих задач.

## F5 · Low — Удаление дневных выборов оставило элементы без потребителей

- **Решение:** Устранить
- **Как устранить:** Удалить элементы без потребителей, сохранив поведение: убрать закрытую иерархию RelationGroup (оставить LongTermRelationGroup напрямую), закрытый RelationGroupPageQuery с единственной реализацией (группа строится без промежуточного типа), forSelection в lib/src/long_term_relation/application/relation_counts.dart и переключения с одной ветвью в lib/src/graph/data/drift_personal_graph_repository_relation_groups.dart; удалить вариант ActionValidationFailure из lib/src/action/application/action_result.dart вместе с его сообщением в action_command_failure_message.dart и случаями в test/graph/presentation/graph_operation_presenter_test.dart; удалить строку relationNeighborhoodEmpty из app_ru.arb и app_en.arb и перегенерировать локализацию. Выполнить вместе с F11 одной новой задачей Фазы 1 — 1.36, после 1.35 и всех существующих задач; проверка — тесты затронутых модулей и анализатор.

## F6 · Medium — Текст панели резервных копий переписан из «ежедневных» в «суточные» вопреки спеке

- **Решение:** Устранить
- **Как устранить:** Вернуть словарь резервных копий к спеке и глоссарию: «ежедневн…» вместо «суточн…» везде, где это заменил коммит 402dbbfe — видимый текст dataBackupsExplanation в lib/l10n/app_ru.arb («Остаются 7 последних ежедневных копий»), описание @dataBackupsExplanation в app_en.arb, сгенерированная локализация, комментарии и названия в lib/src/graph_backups, lib/src/graph/data/drift_personal_graph_repository_backups.dart, lib/src/app/app_runtime.dart, lib/src/shared/diagnostics/diagnostics_sink.dart и тестах копий (test/data_transfer/presentation/backups_sheet_test.dart и др.). Проверку отсутствия дневных выборов заменить на шаблон, который не совпадает с «ежедневн» и охватывает lib, test, benchmark и tool (например, daily.?choice или «дневн» не после «еже»), и записать её в проверку новой задачи. Выполнить вместе с F3 одной новой задачей Фазы 1 — 1.39, последней из добавляемых, после всех существующих задач; спеки и CONTEXT.md не менять.

## F7 · Medium — При переносе на действия потеряны регрессионные проверки экрана дня и вкладки «Действия»

- **Решение:** Устранить
- **Как устранить:** Восстановить регрессионные проверки без изменения поведения: test/action/presentation/day/action_day_calendar_utc_dates_test.dart проверяет все несгенерированные файлы календаря и отметок экрана дня (action_day_calendar*.dart и action_day_marks_*.dart, без .g.dart), комментарий теста соответствует охвату; добавить тесты, что две страницы одного намерения не делят выбранную плитку роли и порции вкладки «Действия» (test/intention/presentation/details/intention_details_actions_test.dart или модель вкладки), и что подтверждённое изменение корневого намерения (переименование, ветвь IntentionCatalogMutation в intention_actions_view_model.dart) обновляет строки вкладки (test/action/presentation/intention_actions/intention_actions_view_model_test.dart). Новая задача Фазы 1 — 1.35, после 1.34 и всех существующих задач.

## F8 · Low — Устаревший список вкладки «Действия» вечно показывает подгрузку

- **Решение:** Устранить
- **Как устранить:** Исправить в коде: подвал списка вкладки «Действия» (lib/src/action/presentation/intention_actions/intention_actions_sliver.dart, _pageFooter) показывает индикатор «Загружаем ещё действия…», только когда подгрузка может начаться (часть списка свежая), а для устаревшей части индикатор не показывается — так же, как на экране дня (lib/src/action/presentation/day/action_day_body.dart). Закрепить тестом в test/action/presentation/intention_actions: после отказа обновления при наличии следующей порции индикатор не показан. Новая задача Фазы 1 — 1.34, после 1.33 и всех существующих задач.

## F9 · Low — Короткие русские даты показываются с точкой, а тесты закрепляют расхождение со сценарием

- **Решение:** Устранить
- **Как устранить:** Вариант A (выбран пользователем): примеры дат в спеке — иллюстрация, а видимый формат приложения — стандартный короткий формат intl с точкой, как на страницах намерений и связей. Через openspec-update-change исправить примеры в openspec/changes/introduce-actions-and-intention-kinds/specs/action-management/spec.md: сценарий требования «Время создания и изменения действия» — «Создано 6 окт. · Изменено 8 окт.», требование и сценарии «Список действий роли намерения» — «пн 12 окт. · 09:00», «вт 5 янв. 2027 · 09:00», «пн 12 окт.» и прочие короткие месяцы с точкой. Код и тесты не меняются (test/action/presentation/panel/action_panel_test.dart уже ожидает «6 окт.»); новая задача не нужна. Затем openspec validate --strict.

## F10 · Low — Названия тестов и вспомогательных параметров сохраняют прежнюю терминологию

- **Решение:** Устранить
- **Как устранить:** Переименовать устаревшие термины в названиях, текстах и вспомогательных параметрах тестов на канонические по CONTEXT.md и спекам (корневое и конечное намерение, действие, экран дня), не меняя проверок: test/app/home_statistics_app_flow_test.dart («исходные намерения» → корневые), test/statistics/presentation/intention_statistics_view_model_test.dart, test/statistics/application/intention_statistics_read_contract_test.dart («месяцы без выборов» → без действий), test/app/intention_statistics_navigation_test.dart («каталог» → экран дня), параметры sourcesCursor/actionsCursor в test/statistics/presentation/intention_statistics_test_support.dart (→ курсоры разбивок корневых и конечных намерений), test/action/presentation/day/action_day_rows_test.dart, action_day_root_page_test.dart, помощники catalog* в test/support/action_day_controls.dart, test/design_system/count_tiles_test.dart («Выборы намерения» → «Действия намерения»). Новая задача Фазы 1 — 1.38, после 1.37 (чтобы не переименовывать удаляемые тесты) и всех существующих задач.

## F11 · Low — Статистика намерения обрабатывает недостижимую нулевую долю и описывает несуществующую привязку курсора

- **Решение:** Устранить
- **Как устранить:** Убрать обработку недостижимого состояния без изменения поведения: _shareLabel в lib/src/statistics/presentation/intention_statistics_overview.dart всегда возвращает долю (без ветви periodCounts.planned == 0, контракт IntentionStatisticsSection гарантирует ненулевой период при показе сводки), удалить описание того же невозможного случая в lib/src/statistics/application/intention_statistics_read_contract.dart (около строк 216-217), исправить комментарий курсора в lib/src/statistics/application/intention_statistics_breakdown.dart — без «местной даты», только реальные условия привязки. Выполнить вместе с F5 одной новой задачей Фазы 1 — 1.36, после 1.35 и всех существующих задач.

## F12 · Low — Тесты без собственной регрессии: повторы другого слоя, мёртвое измерение и перезапуск без записи

- **Решение:** Устранить
- **Как устранить:** Оставить только тесты с собственной регрессией: удалить тесты «пустой путь действия» и «повтор намерения в пути действия» в test/graph_format/graph_format_file_test.dart (повторяют graph_format_codec_test.dart); удалить тест 197-219 в test/statistics/presentation/home_statistics_content_test.dart; в test/long_term_relation/presentation/details/relation_details_tags_test.dart убрать признак usedByAction и создание/удаление действия с путём, сохранив остальные варианты, если они ловят свою регрессию; в test/app/action_day_app_flow_test.dart до первого перезапуска изменить действие через панель (например, выполнение или дату) и проверить изменение после перезапуска, а если это повторяет другой тест — удалить сравнение после перезапуска. Выполнить вместе с F4 одной новой задачей Фазы 1 — 1.37, после 1.36 и всех существующих задач.
