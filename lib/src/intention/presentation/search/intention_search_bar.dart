import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/filter_button.dart';
import '../../../design_system/components/search_field.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../tag/presentation/panel/tags_panel.dart';
import '../../../tag/presentation/panel/tags_panel_context.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import '../catalog/intention_tag_conditions_view_model.dart';
import 'intention_search_kind.dart';

/// Строка поиска назначения [purpose]: поле названия и кнопка фильтра по
/// тегам с числом условий.
///
/// Поле показывает ошибку недопустимого фильтра названия. Кнопка открывает
/// панель тегов в режиме фильтра для условий того же назначения. Полем
/// управляет [controller] страницы: так страница очищает его при сбросе
/// фильтров. Отступы вокруг строки задаёт страница.
final class IntentionSearchBar extends ConsumerWidget {
  const IntentionSearchBar({
    required this.purpose,
    required this.controller,
    super.key,
  });

  final IntentionCatalogPurpose purpose;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalogProvider = intentionCatalogViewModelProvider(purpose);
    // Подписка перестраивает строку при каждой смене выдачи, а текущий выбор
    // берётся из модели: AsyncValue при загрузке может сохранять прежнюю
    // выдачу.
    // https://riverpod.dev/docs/concepts2/refs#refwatch
    ref.watch(catalogProvider);
    final notifier = ref.read(catalogProvider.notifier);
    final conditionsProvider = intentionTagConditionsViewModelProvider(purpose);
    final conditionCount = ref.watch(
      conditionsProvider.select((state) => state.conditions.length),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SearchField(
            key: ValueKey(
              '${IntentionSearchKind.of(purpose).keyPrefix}-filter',
            ),
            controller: controller,
            placeholder: l10n.intentionPickerSearchPlaceholder,
            label: l10n.intentionPickerSearchPlaceholder,
            clearLabel: l10n.intentionPickerClearSearch,
            onChanged: notifier.changeTitleFilter,
            error: switch (notifier.selection.filterValidationFailure) {
              IntentionCatalogFilterValidationFailure
                  .invalidUnicodeRepertoire =>
                l10n.catalogFilterInvalidUnicode,
              IntentionCatalogFilterValidationFailure.tooLong =>
                l10n.catalogFilterTooLong,
              null => null,
            },
          ),
        ),
        const SizedBox(width: DoableMetrics.space2),
        FilterButton(
          count: conditionCount,
          label: l10n.intentionPickerFilterLabel(conditionCount),
          onPressed: () => unawaited(
            showTagsPanel(
              context,
              TagsPanelFilterContext(ref.read(conditionsProvider.notifier)),
            ),
          ),
        ),
      ],
    );
  }
}
