import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/catalog_header.dart';
import '../../../design_system/components/filter_button.dart';
import '../../../design_system/components/search_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../tag/presentation/panel/tags_panel.dart';
import '../../../tag/presentation/panel/tags_panel_context.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import '../catalog/intention_tag_conditions_view_model.dart';
import 'intention_picker_kind.dart';
import 'intention_picker_results.dart';

/// Экран выбора намерения назначения [purpose]: крестик с заголовком, поле
/// поиска, фильтр по тегам и заголовок списка закреплены над выдачей.
///
/// Экран не знает маршрутов, права запуска и типа результата: о закрытии,
/// выборе и открытии подробностей страница узнаёт из обработчиков.
final class IntentionPickerView extends ConsumerStatefulWidget {
  const IntentionPickerView({
    required this.purpose,
    required this.closeLabel,
    required this.emptyScopeMessage,
    required this.onClose,
    required this.onPick,
    required this.onOpenDetails,
    super.key,
  });

  final IntentionPickerPurpose purpose;

  /// Доступное название крестика: его смысл для вызвавшего потока знает
  /// страница.
  final String closeLabel;

  /// Сообщение страницы о том, что допустимый охват пуст.
  final String emptyScopeMessage;

  final VoidCallback onClose;

  /// Получает сводку строки с ревизией выдачи, из которой строка построена.
  final void Function(GraphSnapshot<IntentionSummary> pick) onPick;

  final void Function(IntentionId id) onOpenDetails;

  @override
  ConsumerState<IntentionPickerView> createState() =>
      _IntentionPickerViewState();
}

final class _IntentionPickerViewState
    extends ConsumerState<IntentionPickerView> {
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = IntentionPickerKind.of(widget.purpose);
    final keyPrefix = intentionPickerKeyPrefix(widget.purpose);
    final catalogProvider = intentionCatalogViewModelProvider(widget.purpose);
    final catalog = ref.watch(catalogProvider);
    final notifier = ref.read(catalogProvider.notifier);
    final selection = notifier.selection;
    final count = switch (catalog) {
      AsyncData(
        isLoading: false,
        value: IntentionCatalogConfirmedState(:final totalCount),
      ) =>
        totalCount,
      _ => null,
    };
    final conditionsProvider = intentionTagConditionsViewModelProvider(
      widget.purpose,
    );
    final conditionCount = ref.watch(
      conditionsProvider.select((state) => state.conditions.length),
    );
    return Scaffold(
      appBar: TopBar(
        closeKey: ValueKey('$keyPrefix-cancel'),
        title: kind.title(l10n),
        closeLabel: widget.closeLabel,
        onClose: widget.onClose,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                DoableMetrics.space2,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SearchField(
                      key: ValueKey('$keyPrefix-filter'),
                      controller: _titleController,
                      placeholder: l10n.intentionPickerSearchPlaceholder,
                      label: l10n.intentionPickerSearchPlaceholder,
                      clearLabel: l10n.intentionPickerClearSearch,
                      onChanged: notifier.changeTitleFilter,
                      error: switch (selection.filterValidationFailure) {
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
                        TagsPanelFilterContext(
                          ref.read(conditionsProvider.notifier),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                0,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: CatalogHeader(
                title: switch (selection.type) {
                  IntentionTypeOpen(selected: IntentionTypeChoice.all) ||
                  IntentionTypeNotOffered() => l10n.intentionPickerAllHeader,
                  IntentionTypeOpen(selected: IntentionTypeChoice.intentions) =>
                    l10n.intentionPickerIntentionsHeader,
                  IntentionTypeOpen(selected: IntentionTypeChoice.actions) ||
                  IntentionTypePinnedToActions() =>
                    l10n.intentionPickerActionsHeader,
                },
                count: count,
                summary: _orderSummary(l10n, selection.order),
              ),
            ),
            Expanded(
              child: IntentionPickerResults(
                purpose: widget.purpose,
                emptyScopeMessage: widget.emptyScopeMessage,
                onResetFilters: () {
                  _titleController.clear();
                  notifier.clearTitleFilter();
                  ref.read(conditionsProvider.notifier).clear();
                },
                onPick: widget.onPick,
                onOpenDetails: widget.onOpenDetails,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _orderSummary(
  AppLocalizations l10n,
  IntentionCatalogOrder order,
) => switch ((order.field, order.direction)) {
  (
    IntentionCatalogSortField.createdAt,
    IntentionCatalogSortDirection.descending,
  ) =>
    l10n.intentionPickerOrderCreatedNewest,
  (
    IntentionCatalogSortField.createdAt,
    IntentionCatalogSortDirection.ascending,
  ) =>
    l10n.intentionPickerOrderCreatedOldest,
  (
    IntentionCatalogSortField.updatedAt,
    IntentionCatalogSortDirection.descending,
  ) =>
    l10n.intentionPickerOrderUpdatedNewest,
  (
    IntentionCatalogSortField.updatedAt,
    IntentionCatalogSortDirection.ascending,
  ) =>
    l10n.intentionPickerOrderUpdatedOldest,
  (IntentionCatalogSortField.title, IntentionCatalogSortDirection.ascending) =>
    l10n.intentionPickerOrderTitleAscending,
  (IntentionCatalogSortField.title, IntentionCatalogSortDirection.descending) =>
    l10n.intentionPickerOrderTitleDescending,
};
