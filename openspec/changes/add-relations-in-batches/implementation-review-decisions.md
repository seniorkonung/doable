# Решения по findings OpenSpec implementation review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F3 · Low — Отказ занятой пары называет не те намерения

- **Решение:** Устранить
- **Как устранить:** Заменить текст relationsAdditionPairOccupied на согласованный пользователем дословно. В lib/l10n/app_ru.arb: «Некоторые выбранные намерения уже связаны с этим намерением. Связи не созданы.» В lib/l10n/app_en.arb: «Some selected intentions are already linked to this intention. No relations were created.» Конкретные намерения в сообщении не называть, контракт отказа LongTermRelationPairOccupiedFailure и команду не менять. Пересоздать файлы локализации app_localizations*.dart через mise run codegen, а не правкой вручную. Обновить ожидания старого текста в test/long_term_relation/presentation/batch_picker/relation_batch_picker_page_test.dart (строки около 409 и 575) и test/graph/presentation/graph_operation_presenter_test.dart (строки около 1254-1255); отчёт ревью эти тесты и созданные файлы не перечислил, но они меняются вместе со строкой. Спецификации не меняются: они не задают дословный текст этого отказа. Добавить новую задачу в конец фазы 3 следующим свободным номером, после задач F1 и F2 и всех существующих задач; новую фазу не создавать. Ожидаемые артефакты: tasks.md, оба ARB, созданные файлы локализации, два названных теста.

## F4 · Low — Строка `relationEditorDescriptionLabel` осталась без читателя

- **Решение:** Устранить
- **Как устранить:** Удалить строку relationEditorDescriptionLabel без читателя: ключ в lib/l10n/app_ru.arb, ключ и блок описания @relationEditorDescriptionLabel в lib/l10n/app_en.arb. Пересоздать файлы локализации app_localizations.dart, app_localizations_ru.dart и app_localizations_en.dart через mise run codegen, а не правкой вручную. Поведение продукта не меняется: на голове строку не читает никто в lib/src и test. Остальные строки шаблона relationEditorDescription* читает relation_details_sheet.dart, их не трогать. Другие строки без читателя, существовавшие до этого изменения (navigationActiveIntentions, navigationArchive, commonLoading, commonEmpty, commonError, editorCreateAction), вне объёма этой находки и остаются. Спецификации не меняются. Добавить новую задачу в конец фазы 3 следующим свободным номером, после задач F1, F2 и F3 и всех существующих задач; новую фазу не создавать. Ожидаемые артефакты: tasks.md, оба ARB, созданные файлы локализации.
